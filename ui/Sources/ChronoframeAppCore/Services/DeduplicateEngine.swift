#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

public enum DeduplicateEngineError: LocalizedError {
    case destinationMissing
    case scanFailed(String)
    case commitFailed(String)

    public var errorDescription: String? {
        switch self {
        case .destinationMissing:
            return "Choose a destination folder before running a deduplicate scan."
        case let .scanFailed(message):
            return message
        case let .commitFailed(message):
            return message
        }
    }
}

@MainActor
public protocol DeduplicateEngine: AnyObject {
    func scan(_ configuration: DeduplicateConfiguration) throws -> AsyncThrowingStream<DeduplicateEvent, Error>
    func cancelCurrentScan()
    func commit(
        plan: DeduplicationPlan,
        configuration: DeduplicateConfiguration
    ) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error>
    func revert(receiptURL: URL, destinationRoot: String) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error>
}

@MainActor
public final class NativeDeduplicateEngine: DeduplicateEngine {
    private let scanner: DeduplicateScanner
    private let executor: DeduplicateExecutor
    private let recoveryCoordinator: MutationRecoveryCoordinator
    private var activeLease: DestinationOperationLease?
    private var activeLeaseDestination: String?

    public init(
        scanner: DeduplicateScanner = DeduplicateScanner(),
        executor: DeduplicateExecutor = DeduplicateExecutor(),
        recoveryCoordinator: MutationRecoveryCoordinator = MutationRecoveryCoordinator()
    ) {
        self.scanner = scanner
        self.executor = executor
        self.recoveryCoordinator = recoveryCoordinator
    }

    public func scan(_ configuration: DeduplicateConfiguration) throws -> AsyncThrowingStream<DeduplicateEvent, Error> {
        guard !configuration.destinationPath.isEmpty else {
            throw DeduplicateEngineError.destinationMissing
        }
        activeLease?.release()
        let destinationURL = URL(fileURLWithPath: configuration.destinationPath, isDirectory: true)
        let lease = try DestinationOperationLock.acquire(
            destinationRoot: destinationURL,
            surface: "app",
            operation: "deduplicate scan"
        )
        _ = recoveryCoordinator.recover(destinationRoot: destinationURL)
        activeLease = lease
        activeLeaseDestination = destinationURL.standardizedFileURL.path
        return scanHoldingStream(scanner.scan(configuration: configuration))
    }

    public func cancelCurrentScan() {
        scanner.cancel()
        executor.cancel()
        activeLease?.release()
        activeLease = nil
        activeLeaseDestination = nil
    }

    public func commit(
        plan: DeduplicationPlan,
        configuration: DeduplicateConfiguration
    ) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        let destinationURL = URL(fileURLWithPath: configuration.destinationPath, isDirectory: true)
        let standardizedDestination = destinationURL.standardizedFileURL.path
        if activeLease == nil || activeLeaseDestination != standardizedDestination {
            activeLease?.release()
            activeLease = try DestinationOperationLock.acquire(
                destinationRoot: destinationURL,
                surface: "app",
                operation: "deduplicate commit"
            )
            activeLeaseDestination = standardizedDestination
            _ = recoveryCoordinator.recover(destinationRoot: destinationURL)
        }
        let stream = executor.commit(
            plan: plan,
            destinationRoot: configuration.destinationPath,
            additionalSourceRoots: configuration.additionalSources.map(\.path),
            hardDelete: false
        )
        return releasingStream(stream)
    }

    public func revert(receiptURL: URL, destinationRoot: String) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        let destinationURL = URL(fileURLWithPath: destinationRoot, isDirectory: true)
        activeLease?.release()
        activeLease = try DestinationOperationLock.acquire(
            destinationRoot: destinationURL,
            surface: "app",
            operation: "deduplicate revert"
        )
        activeLeaseDestination = destinationURL.standardizedFileURL.path
        _ = recoveryCoordinator.recover(destinationRoot: destinationURL)
        let stream = executor.revert(
            receiptURL: receiptURL,
            destinationBoundary: destinationURL
        )
        return releasingStream(stream)
    }

    private func releasingStream(
        _ stream: AsyncThrowingStream<DeduplicateCommitEvent, Error>
    ) -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                defer {
                    self?.activeLease?.release()
                    self?.activeLease = nil
                    self?.activeLeaseDestination = nil
                }
                do {
                    for try await event in stream { continuation.yield(event) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func scanHoldingStream(
        _ stream: AsyncThrowingStream<DeduplicateEvent, Error>
    ) -> AsyncThrowingStream<DeduplicateEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                var reachedReview = false
                do {
                    for try await event in stream {
                        if case .complete = event { reachedReview = true }
                        continuation.yield(event)
                    }
                    if !reachedReview {
                        self?.activeLease?.release()
                        self?.activeLease = nil
                        self?.activeLeaseDestination = nil
                    }
                    continuation.finish()
                } catch {
                    self?.activeLease?.release()
                    self?.activeLease = nil
                    self?.activeLeaseDestination = nil
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
