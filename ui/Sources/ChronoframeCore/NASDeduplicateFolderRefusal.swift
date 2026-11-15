import Foundation

/// Deduplicate moves files to the macOS Trash. Trash on SMB/AFP/NFS mounts is unverified
/// (docs/NAS_REQUIREMENTS.md ADR-NAS-04), so Deduplicate refuses any folder that is not on a
/// local volume. `.unknown` is refused too (fail closed), matching the CLI (CLI.swift:536).
public enum NASDeduplicateFolderRefusal: LocalizedError, Equatable, Sendable {
    case notLocal(path: String, kind: NASVolumeKind)

    public static func refusal(for folder: URL, classifier: NASVolumeClassifier = .live) -> NASDeduplicateFolderRefusal? {
        let observation = classifier.classify(folder)
        return observation.kind == .local ? nil : .notLocal(path: folder.path, kind: observation.kind)
    }

    public var errorDescription: String? {
        switch self {
        case .notLocal:
            return NASCapability.isEnabled
                ? "Choose a folder on this Mac or an attached drive. Deduplicate can't move files on a network share to the Trash safely yet, so nothing was changed. For a NAS, use NAS Library."
                : "Choose a folder on this Mac or an attached drive. Deduplicate can't move files on a network share to the Trash safely yet, so nothing was changed."
        }
    }
}
