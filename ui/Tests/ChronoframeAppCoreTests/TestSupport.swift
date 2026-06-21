import Foundation
@testable import ChronoframeAppCore

enum TestFailure: Error, LocalizedError {
    case expectedFailure(String)

    var errorDescription: String? {
        switch self {
        case let .expectedFailure(message):
            return message
        }
    }
}

func testScanSnapshot(
    for clusters: [DuplicateCluster],
    sidecarOwners: [String: Set<String>] = [:],
    additionalIdentities: [String: FileIdentity] = [:]
) -> DeduplicateScanSnapshot {
    func filesystemSize(_ path: String, fallback: Int64) -> Int64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber
        else { return fallback }
        return size.int64Value
    }
    var sizes: [String: Int64] = [:]
    for member in clusters.flatMap(\.members) {
        sizes[member.path] = member.size
        if let partner = member.pairedPath, sizes[partner] == nil {
            sizes[partner] = filesystemSize(partner, fallback: member.size)
        }
        for sidecar in member.sidecarPaths where sizes[sidecar] == nil {
            sizes[sidecar] = filesystemSize(sidecar, fallback: 0)
        }
    }
    var identities = Dictionary(uniqueKeysWithValues: sizes.map { path, size in
        (path, FileIdentity(size: size, digest: Data(path.utf8).base64EncodedString()))
    })
    identities.merge(additionalIdentities) { _, explicit in explicit }
    return DeduplicateScanSnapshot(identitiesByPath: identities, sidecarOwners: sidecarOwners)
}

func testFileIdentity(at url: URL) -> FileIdentity {
    try! FileIdentityHasher().hashIdentity(at: url)
}

final class SecurityScopeCloseTracker {
    private(set) var closeCount = 0

    func makeScope() -> SecurityScopedFolderAccess {
        SecurityScopedFolderAccess(onClose: { [weak self] _ in
            self?.closeCount += 1
        })
    }
}

@MainActor
final class MockOrganizerEngine: OrganizerEngine {
    enum StreamMode {
        case events([RunEvent])
        case fails(Error)
        case pending
    }

    var preflightResult: Result<RunPreflight, Error>
    var startMode: StreamMode
    var resumeMode: StreamMode
    var revertMode: StreamMode
    var reorganizeMode: StreamMode
    var startConfigurations: [RunConfiguration] = []
    var resumeConfigurations: [RunConfiguration] = []
    var revertRequests: [(receiptURL: URL, destinationRoot: String)] = []
    var reorganizeRequests: [(destinationRoot: String, targetStructure: FolderStructure)] = []
    var cancelCallCount = 0
    var pendingContinuation: AsyncThrowingStream<RunEvent, Error>.Continuation?
    /// Optional hook invoked inside `preflight` before it returns. Tests use it
    /// to deterministically interleave a second operation (or a cancel) while a
    /// preflight is in flight, exercising the stale-completion epoch guard.
    var preflightHook: (@MainActor () async -> Void)?
    private let lockRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("MockOrganizerEngine-\(UUID().uuidString)", isDirectory: true)

    init(
        preflightResult: Result<RunPreflight, Error>,
        startMode: StreamMode = .events([]),
        resumeMode: StreamMode = .events([]),
        revertMode: StreamMode = .events([]),
        reorganizeMode: StreamMode = .events([])
    ) {
        self.preflightResult = preflightResult
        self.startMode = startMode
        self.resumeMode = resumeMode
        self.revertMode = revertMode
        self.reorganizeMode = reorganizeMode
    }

    func preflight(_ configuration: RunConfiguration) async throws -> RunPreflight {
        if let preflightHook {
            await preflightHook()
        }
        return try preflightResult.get()
    }

    func prepare(_ configuration: RunConfiguration) async throws -> PreparedRun {
        let preflight = try await preflight(configuration)
        let lease = try DestinationOperationLock.acquire(
            destinationRoot: lockRoot,
            surface: "test",
            operation: configuration.mode.rawValue
        )
        return PreparedRun(preflight: preflight, lease: lease)
    }

    func start(_ configuration: RunConfiguration) throws -> AsyncThrowingStream<RunEvent, Error> {
        startConfigurations.append(configuration)
        return try makeStream(for: startMode)
    }

    func resume(_ configuration: RunConfiguration) throws -> AsyncThrowingStream<RunEvent, Error> {
        resumeConfigurations.append(configuration)
        return try makeStream(for: resumeMode)
    }

    func cancelCurrentRun() {
        cancelCallCount += 1
        pendingContinuation?.finish()
        pendingContinuation = nil
    }

    func revert(receiptURL: URL, destinationRoot: String) throws -> AsyncThrowingStream<RunEvent, Error> {
        revertRequests.append((receiptURL: receiptURL, destinationRoot: destinationRoot))
        return try makeStream(for: revertMode)
    }

    func reorganize(
        destinationRoot: String,
        targetStructure: FolderStructure
    ) throws -> AsyncThrowingStream<RunEvent, Error> {
        reorganizeRequests.append((destinationRoot: destinationRoot, targetStructure: targetStructure))
        return try makeStream(for: reorganizeMode)
    }

    private func makeStream(for mode: StreamMode) throws -> AsyncThrowingStream<RunEvent, Error> {
        switch mode {
        case let .events(events):
            return AsyncThrowingStream { continuation in
                Task { @MainActor in
                    for event in events {
                        continuation.yield(event)
                    }
                    continuation.finish()
                }
            }
        case let .fails(error):
            throw error
        case .pending:
            return AsyncThrowingStream { continuation in
                self.pendingContinuation = continuation
            }
        }
    }
}

@MainActor
final class MockDeduplicateEngine: DeduplicateEngine {
    var clustersToEmit: [DuplicateCluster] = []
    var summary: DeduplicateSummary = DeduplicateSummary()
    var commitEvents: [DeduplicateCommitEvent] = []
    var revertEvents: [DeduplicateCommitEvent] = []
    var scanError: Error?
    var lastScanConfiguration: DeduplicateConfiguration?
    var lastCommitPlan: DeduplicationPlan?
    var lastCommitConfiguration: DeduplicateConfiguration?

    init(
        clusters: [DuplicateCluster] = [],
        summary: DeduplicateSummary = DeduplicateSummary(),
        commitEvents: [DeduplicateCommitEvent] = [],
        revertEvents: [DeduplicateCommitEvent] = []
    ) {
        self.clustersToEmit = clusters
        var summary = summary
        if summary.scanSnapshot.identitiesByPath.isEmpty {
            summary.scanSnapshot = testScanSnapshot(for: clusters, sidecarOwners: summary.sidecarOwners)
        }
        self.summary = summary
        self.commitEvents = commitEvents
        self.revertEvents = revertEvents
    }

    func scan(_ configuration: DeduplicateConfiguration) throws -> AsyncThrowingStream<DeduplicateEvent, Error> {
        lastScanConfiguration = configuration
        if let scanError {
            throw scanError
        }
        let clusters = clustersToEmit
        let summary = summary
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                continuation.yield(.startup)
                for cluster in clusters {
                    continuation.yield(.clusterDiscovered(cluster))
                }
                continuation.yield(.complete(summary))
                continuation.finish()
            }
        }
    }

    func cancelCurrentScan() {}

    func commit(
        plan: DeduplicationPlan,
        configuration: DeduplicateConfiguration
    ) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        lastCommitPlan = plan
        lastCommitConfiguration = configuration
        let events = commitEvents
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }

    func revert(receiptURL: URL, destinationRoot: String) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        let events = revertEvents
        return AsyncThrowingStream { continuation in
            Task { @MainActor in
                for event in events { continuation.yield(event) }
                continuation.finish()
            }
        }
    }
}

@MainActor
func waitForCondition(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    pollNanoseconds: UInt64 = 20_000_000,
    _ condition: @escaping @MainActor () -> Bool
) async -> Bool {
    let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

    while DispatchTime.now().uptimeNanoseconds < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: pollNanoseconds)
    }

    return condition()
}
