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
    /// Consulted by the gate in T9. Stored here in T7 so that adding that gate
    /// is a pure behavioural change.
    private let authorizer: any TrialAuthorizing
    private let scanner: DeduplicateScanner
    private let executor: DeduplicateExecutor
    private let recoveryCoordinator: MutationRecoveryCoordinator
    private var activeLease: DestinationOperationLease?
    private var activeLeaseDestination: String?
    /// Surfaces a one-time warning when the dedupe destination is on a network
    /// volume. Internal so tests can inject a stub advisory + scratch defaults.
    var networkAdvisory = NetworkDestinationAdvisory()

    /// - Parameter authorizer: who may do metered work. Required, never
    ///   defaulted — see `SwiftOrganizerEngine.init` for why a default here
    ///   would be a silent licensing bypass rather than a convenience.
    public init(
        authorizer: any TrialAuthorizing,
        scanner: DeduplicateScanner = DeduplicateScanner(),
        executor: DeduplicateExecutor = DeduplicateExecutor(),
        recoveryCoordinator: MutationRecoveryCoordinator = MutationRecoveryCoordinator()
    ) {
        self.authorizer = authorizer
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
        _ = DestinationRecovery.recoverAndReconcile(
            destinationRoot: destinationURL,
            coordinator: recoveryCoordinator
        )
        activeLease = lease
        activeLeaseDestination = destinationURL.standardizedFileURL.path
        let networkWarning = networkAdvisory.warningIfNeeded(for: destinationURL)
        return scanHoldingStream(
            scanner.scan(configuration: configuration),
            leadingWarning: networkWarning
        )
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
            _ = DestinationRecovery.recoverAndReconcile(
                destinationRoot: destinationURL,
                coordinator: recoveryCoordinator
            )
        }
        // Minted here, before the executor starts, because step 4 takes the
        // trial reservation at this same point. The receipt used to mint its own
        // ID inside the commit stream, which is after the reservation would
        // already have to exist.
        let runID = UUID()
        let stream = executor.commit(
            plan: plan,
            destinationRoot: configuration.destinationPath,
            additionalSourceRoots: configuration.additionalSources.map(\.path),
            hardDelete: false,
            runID: runID
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
        _ = DestinationRecovery.recoverAndReconcile(
            destinationRoot: destinationURL,
            coordinator: recoveryCoordinator
        )
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
        _ stream: AsyncThrowingStream<DeduplicateEvent, Error>,
        leadingWarning: String? = nil
    ) -> AsyncThrowingStream<DeduplicateEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                var reachedReview = false
                if let leadingWarning {
                    continuation.yield(.issue(DeduplicateIssue(severity: .warning, message: leadingWarning)))
                }
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
