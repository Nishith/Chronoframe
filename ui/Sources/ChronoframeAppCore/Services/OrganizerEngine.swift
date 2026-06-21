#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

public enum OrganizerEngineError: LocalizedError {
    case profileNotFound(String)
    case sourceDoesNotExist(String)
    case destinationMissing
    case failedToLaunch(String)
    case invalidPreflight(String)
    case invalidOutput(String)

    public var errorDescription: String? {
        switch self {
        case let .profileNotFound(name):
            return "The saved profile \"\(name)\" no longer exists. Choose another profile or save it again."
        case let .sourceDoesNotExist(path):
            return "The source folder is no longer available. Reconnect the drive or choose the source folder again. Path: \(path)."
        case .destinationMissing:
            return "Choose a destination folder before starting this run."
        case let .failedToLaunch(message):
            return UserFacingErrorMessage.withDetails(
                "Chronoframe could not start the organizer. Try again; if it keeps happening, restart or reinstall Chronoframe.",
                details: message
            )
        case let .invalidPreflight(message):
            return UserFacingErrorMessage.withDetails(
                "Chronoframe could not validate the run settings. Review the source and destination, then try again.",
                details: message
            )
        case let .invalidOutput(line):
            return UserFacingErrorMessage.withDetails(
                "Chronoframe received an unexpected response from its helper. Try again.",
                details: line
            )
        }
    }
}

public final class PreparedRun: @unchecked Sendable {
    public let preflight: RunPreflight
    public let lease: DestinationOperationLease

    public init(preflight: RunPreflight, lease: DestinationOperationLease) {
        self.preflight = preflight
        self.lease = lease
    }
}

@MainActor
public protocol OrganizerEngine: AnyObject {
    func preflight(_ configuration: RunConfiguration) async throws -> RunPreflight
    func prepare(_ configuration: RunConfiguration) async throws -> PreparedRun
    func start(_ configuration: RunConfiguration) throws -> AsyncThrowingStream<RunEvent, Error>
    func resume(_ configuration: RunConfiguration) throws -> AsyncThrowingStream<RunEvent, Error>
    func cancelCurrentRun()

    /// Revert a previous transfer using its on-disk audit receipt. Emits
    /// `RunEvent`s identical in shape to a normal run so the same UI surface
    /// can render progress and the final summary.
    func revert(receiptURL: URL, destinationRoot: String) throws -> AsyncThrowingStream<RunEvent, Error>

    /// In-place layout migration: move every recognised file under
    /// `destinationRoot` so it sits in the directory layout described by
    /// `targetStructure`. No source folder is required — this only touches
    /// files already present in the destination.
    func reorganize(
        destinationRoot: String,
        targetStructure: FolderStructure
    ) throws -> AsyncThrowingStream<RunEvent, Error>
}

extension OrganizerEngine {
    public func prepare(_ configuration: RunConfiguration) async throws -> PreparedRun {
        let preflight = try await preflight(configuration)
        let lease = try DestinationOperationLock.acquire(
            destinationRoot: URL(fileURLWithPath: preflight.resolvedDestinationPath, isDirectory: true),
            surface: "app",
            operation: configuration.mode.rawValue
        )
        _ = MutationRecoveryCoordinator().recover(
            destinationRoot: URL(fileURLWithPath: preflight.resolvedDestinationPath, isDirectory: true)
        )
        return PreparedRun(preflight: preflight, lease: lease)
    }

    public func revert(receiptURL: URL, destinationRoot: String) throws -> AsyncThrowingStream<RunEvent, Error> {
        throw OrganizerEngineError.failedToLaunch("Revert is not supported by this engine.")
    }

    public func reorganize(
        destinationRoot: String,
        targetStructure: FolderStructure
    ) throws -> AsyncThrowingStream<RunEvent, Error> {
        throw OrganizerEngineError.failedToLaunch("Reorganize is not supported by this engine.")
    }
}
