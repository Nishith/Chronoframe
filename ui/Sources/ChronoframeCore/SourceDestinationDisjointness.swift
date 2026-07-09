import Foundation

/// Shared guard that an organize source and destination do not overlap.
///
/// Overlapping roots are never a valid run: a source inside the
/// destination makes Chronoframe rediscover its own copies as new
/// files (a feedback loop for watched sources), and a destination
/// inside the source makes copies land back inside the folder being
/// organized. The check resolves existing symlinks via
/// `SafePathContainment`, so a symlinked alias of one root inside the
/// other is caught too.
///
/// Used by organize preflight (preview and transfer, app and CLI) and
/// re-used by watched-source registration for early feedback.
public enum SourceDestinationDisjointness {
    public enum Conflict: Equatable, Sendable {
        /// The source equals or sits inside the destination.
        case sourceInsideDestination
        /// The destination sits inside the source.
        case destinationInsideSource
    }

    public static func conflict(sourcePath: String, destinationPath: String) -> Conflict? {
        let sourceURL = URL(fileURLWithPath: sourcePath, isDirectory: true)
        let destinationURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
        if SafePathContainment.isContained(sourceURL, in: destinationURL) {
            return .sourceInsideDestination
        }
        if SafePathContainment.isContained(destinationURL, in: sourceURL) {
            return .destinationInsideSource
        }
        return nil
    }
}
