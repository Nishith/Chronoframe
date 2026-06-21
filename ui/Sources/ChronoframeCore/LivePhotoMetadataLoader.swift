import AVFoundation
import Foundation

public struct LivePhotoMetadataBatchResult: Sendable, Equatable {
    public var identifiersByPath: [String: String]
    public var unsupportedPaths: Set<String>

    public init(identifiersByPath: [String: String] = [:], unsupportedPaths: Set<String> = []) {
        self.identifiersByPath = identifiersByPath
        self.unsupportedPaths = unsupportedPaths
    }
}

public protocol LivePhotoMetadataLoading: Sendable {
    func loadIdentifiers(for movieURLs: [URL]) async -> LivePhotoMetadataBatchResult
    func cancelAll()
}

public final class BoundedLivePhotoMetadataLoader: LivePhotoMetadataLoading, @unchecked Sendable {
    public static let defaultWorkerCount = 4
    public static let defaultTimeoutSeconds: TimeInterval = 10
    public static let defaultCircuitBreakerTimeoutCount = 4

    private struct ActiveLoad {
        let task: Task<String?, Never>
        let asset: AssetBox
        let gate: OutcomeGate
    }

    private final class AssetBox: @unchecked Sendable {
        let value: AVURLAsset
        init(_ value: AVURLAsset) { self.value = value }
    }

    private enum Outcome: Sendable {
        case identifier(String?)
        case timedOut
        case cancelled
        case circuitOpen
    }

    private final class OutcomeGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Outcome, Never>?
        private var pendingOutcome: Outcome?

        func install(_ continuation: CheckedContinuation<Outcome, Never>) {
            let pending: Outcome? = lock.synchronized {
                if let pendingOutcome { return pendingOutcome }
                self.continuation = continuation
                return nil
            }
            if let pending { continuation.resume(returning: pending) }
        }

        func resolve(_ outcome: Outcome) {
            let continuation: CheckedContinuation<Outcome, Never>? = lock.synchronized {
                guard pendingOutcome == nil else { return nil }
                pendingOutcome = outcome
                let continuation = self.continuation
                self.continuation = nil
                return continuation
            }
            continuation?.resume(returning: outcome)
        }
    }

    private let lock = NSLock()
    private var active: [UUID: ActiveLoad] = [:]
    private var generation: UInt64 = 0
    private var timeoutCount = 0
    private var circuitOpen = false
    private let workerCount: Int
    private let timeoutNanoseconds: UInt64
    private let circuitBreakerTimeoutCount: Int
    private let assetFactory: @Sendable (URL) -> AVURLAsset
    private let identifierLoader: @Sendable (AVURLAsset) async -> String?

    public init(
        workerCount: Int = defaultWorkerCount,
        timeoutSeconds: TimeInterval = defaultTimeoutSeconds,
        circuitBreakerTimeoutCount: Int = defaultCircuitBreakerTimeoutCount
    ) {
        self.workerCount = max(1, workerCount)
        self.timeoutNanoseconds = UInt64(max(0.001, timeoutSeconds) * 1_000_000_000)
        self.circuitBreakerTimeoutCount = max(1, circuitBreakerTimeoutCount)
        self.assetFactory = Self.makeMetadataAsset(url:)
        self.identifierLoader = Self.identifier(from:)
    }

    init(
        workerCount: Int,
        timeoutSeconds: TimeInterval,
        circuitBreakerTimeoutCount: Int,
        assetFactory: @escaping @Sendable (URL) -> AVURLAsset = BoundedLivePhotoMetadataLoader.makeMetadataAsset(url:),
        identifierLoader: @escaping @Sendable (AVURLAsset) async -> String?
    ) {
        self.workerCount = max(1, workerCount)
        self.timeoutNanoseconds = UInt64(max(0.001, timeoutSeconds) * 1_000_000_000)
        self.circuitBreakerTimeoutCount = max(1, circuitBreakerTimeoutCount)
        self.assetFactory = assetFactory
        self.identifierLoader = identifierLoader
    }

    public func loadIdentifiers(for movieURLs: [URL]) async -> LivePhotoMetadataBatchResult {
        let loadGeneration = lock.synchronized { () -> UInt64 in
            if active.isEmpty {
                timeoutCount = 0
                circuitOpen = false
            }
            return generation
        }
        return await withTaskCancellationHandler {
            var result = LivePhotoMetadataBatchResult()
            for batchStart in stride(from: 0, to: movieURLs.count, by: workerCount) {
                if Task.isCancelled { break }
                let batchEnd = min(batchStart + workerCount, movieURLs.count)
                let batch = Array(movieURLs[batchStart..<batchEnd])
                await withTaskGroup(of: (URL, Outcome).self) { group in
                    for url in batch {
                        group.addTask { [self] in
                            (url, await loadOne(url: url, generation: loadGeneration))
                        }
                    }
                    for await (url, outcome) in group {
                        switch outcome {
                        case let .identifier(identifier):
                            if let identifier { result.identifiersByPath[url.path] = identifier }
                        case .timedOut, .cancelled, .circuitOpen:
                            result.unsupportedPaths.insert(url.path)
                        }
                    }
                }
                if isCircuitOpen(for: loadGeneration) {
                    for url in movieURLs.dropFirst(batchEnd) { result.unsupportedPaths.insert(url.path) }
                    break
                }
            }
            return result
        } onCancel: {
            self.cancelAll()
        }
    }

    public func cancelAll() {
        let loads: [ActiveLoad] = lock.synchronized {
            generation &+= 1
            let loads = Array(active.values)
            active.removeAll()
            return loads
        }
        for load in loads {
            load.task.cancel()
            load.asset.value.cancelLoading()
            load.gate.resolve(.cancelled)
        }
    }

    private func isCircuitOpen(for loadGeneration: UInt64) -> Bool {
        lock.synchronized { loadGeneration == generation && circuitOpen }
    }

    private func loadOne(url: URL, generation loadGeneration: UInt64) async -> Outcome {
        if Task.isCancelled { return .cancelled }
        let loadID = UUID()
        let asset = assetFactory(url)
        let assetBox = AssetBox(asset)
        let identifierLoader = self.identifierLoader
        let gate = OutcomeGate()

        let operation = Task.detached(priority: .utility) {
            await identifierLoader(assetBox.value)
        }
        let rejection = lock.synchronized { () -> Outcome? in
            guard loadGeneration == generation else { return .cancelled }
            guard !circuitOpen, active.count < workerCount else { return .circuitOpen }
            active[loadID] = ActiveLoad(task: operation, asset: assetBox, gate: gate)
            return nil
        }
        if let rejection {
            operation.cancel()
            asset.cancelLoading()
            return rejection
        }

        // Cleanup follows the actual AVFoundation operation, not the caller's
        // deadline. A timed-out load therefore continues to consume one of the
        // four slots until AVFoundation really terminates it.
        Task.detached { [weak self] in
            let identifier = await operation.value
            guard let self else { return }
            _ = self.lock.synchronized { self.active.removeValue(forKey: loadID) }
            gate.resolve(.identifier(identifier))
        }

        let timeoutTask = Task.detached { [timeoutNanoseconds] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            if !Task.isCancelled { gate.resolve(.timedOut) }
        }
        let outcome = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                gate.install(continuation)
            }
        } onCancel: {
            operation.cancel()
            asset.cancelLoading()
            gate.resolve(.cancelled)
        }
        timeoutTask.cancel()

        switch outcome {
        case .timedOut:
            operation.cancel()
            asset.cancelLoading()
            lock.synchronized {
                guard loadGeneration == generation else { return }
                timeoutCount += 1
                if timeoutCount >= circuitBreakerTimeoutCount { circuitOpen = true }
            }
        case .cancelled:
            operation.cancel()
            asset.cancelLoading()
        case .identifier, .circuitOpen:
            break
        }
        return outcome
    }

    public static func makeMetadataAsset(url: URL) -> AVURLAsset {
        AVURLAsset(url: url, options: metadataAssetOptions)
    }

    static var metadataAssetOptions: [String: Any] {
        [
            AVURLAssetPreferPreciseDurationAndTimingKey: false,
            AVURLAssetReferenceRestrictionsKey: NSNumber(
                value: AVAssetReferenceRestrictions.forbidAll.rawValue
            ),
        ]
    }

    var outstandingLoadCount: Int { lock.synchronized { active.count } }
    var observedTimeoutCount: Int { lock.synchronized { timeoutCount } }

    private static func identifier(from asset: AVURLAsset) async -> String? {
        guard !Task.isCancelled, let metadata = try? await asset.load(.metadata) else { return nil }
        for item in metadata {
            guard !Task.isCancelled,
                  item.identifier?.rawValue == "mdta/com.apple.quicktime.content.identifier"
            else { continue }
            if let value = try? await item.load(.stringValue) { return value }
        }
        return nil
    }
}

private extension NSLock {
    func synchronized<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
