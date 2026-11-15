import Foundation

/// Organize copies into a network folder only when it can install a file without ever replacing
/// an existing one (AGENTS.md INV-28). This is the plain-language answer when it cannot.
public enum NASCopyDestinationRefusal: LocalizedError, Equatable, Sendable {
    case noAtomicNoReplace(path: String, errorCode: Int32)

    public var errorDescription: String? {
        "This network folder can't guarantee that a copy never replaces an existing file, so Chronoframe won't organize into it. Choose a folder on this Mac or an attached drive. Nothing was copied, and your originals were untouched."
    }
}
