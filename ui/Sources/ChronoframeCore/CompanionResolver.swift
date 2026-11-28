import Foundation

/// A companion (`.xmp` / `.aae`) that Organize will not copy, and why.
public struct UnresolvedCompanion: Equatable, Codable, Sendable {
    public enum Reason: String, Codable, Sendable {
        /// More than one media file in the same folder claims the companion.
        case multipleOwners
        /// No media file in the same folder claims the companion.
        case noOwner
        /// The destination name it would take is already used (on disk, or by
        /// another planned file).
        case nameTaken
        /// The companion could not be read to identify it.
        case unreadable
    }

    public var sourcePath: String
    public var reason: Reason

    public init(sourcePath: String, reason: Reason) {
        self.sourcePath = sourcePath
        self.reason = reason
    }
}

/// Pure owner resolution and destination planning for companion files.
///
/// A companion is an ordinary copy job planned from its owner's final
/// destination; nothing here touches the filesystem except through the
/// injected `fileExists` closure.
public enum CompanionResolver {
    public struct Resolution: Equatable, Sendable {
        /// Companion source path to owner source path, for companions with
        /// exactly one eligible owner.
        public var ownersByCompanion: [String: String]
        /// Companions with zero or more than one eligible owner, sorted by
        /// source path.
        public var unresolved: [UnresolvedCompanion]

        public init(ownersByCompanion: [String: String] = [:], unresolved: [UnresolvedCompanion] = []) {
            self.ownersByCompanion = ownersByCompanion
            self.unresolved = unresolved
        }
    }

    public struct PlannedCompanions: Equatable, Sendable {
        /// Companion copy jobs, sorted by source path.
        public var transfers: [PlannedTransfer]
        /// Every unresolved companion (including those from `resolve`), sorted
        /// by source path.
        public var unresolved: [UnresolvedCompanion]
        /// Companion source path to owner source path for `transfers` only.
        public var companionOwners: [String: String]

        public init(
            transfers: [PlannedTransfer] = [],
            unresolved: [UnresolvedCompanion] = [],
            companionOwners: [String: String] = [:]
        ) {
            self.transfers = transfers
            self.unresolved = unresolved
            self.companionOwners = companionOwners
        }
    }

    private enum NameForm {
        /// `IMG_1.xmp`, or the iOS `IMG_E1.AAE` edit form: the owner's stem.
        case stem
        /// `IMG_1.jpg.xmp`: the owner's full file name.
        case appended
    }

    /// Resolves each companion to the single media file that owns it.
    /// Eligible owners are only the paths in `mediaPaths`, in the same
    /// directory; names compare case-insensitively.
    public static func resolve(companionPaths: [String], mediaPaths: [String]) -> Resolution {
        var mediaByDirectory: [String: [String]] = [:]
        for path in mediaPaths {
            mediaByDirectory[directory(of: path), default: []].append(path)
        }

        var owners: [String: String] = [:]
        var unresolved: [UnresolvedCompanion] = []
        var seen = Set<String>()

        for companion in companionPaths where seen.insert(companion).inserted {
            let eligible = Set((mediaByDirectory[directory(of: companion)] ?? []).filter {
                nameForm(companion: companion, owner: $0) != nil
            })
            if eligible.count == 1, let owner = eligible.first {
                owners[companion] = owner
            } else {
                unresolved.append(UnresolvedCompanion(
                    sourcePath: companion,
                    reason: eligible.isEmpty ? .noOwner : .multipleOwners
                ))
            }
        }

        return Resolution(
            ownersByCompanion: owners,
            unresolved: unresolved.sorted { $0.sourcePath < $1.sourcePath }
        )
    }

    /// Plans destinations for companions whose owner is among `ownerTransfers`
    /// (the final owner plan, including collision names and the duplicate
    /// directory). A companion whose owner is not planned is skipped silently
    /// with it. A companion is listed as not copied when its destination
    /// exists, equals any other planned destination (case-insensitively), or
    /// it cannot be identified.
    public static func plan(
        ownerTransfers: [PlannedTransfer],
        resolution: Resolution,
        identity: (String) -> FileIdentity?,
        fileExists: (String) -> Bool
    ) -> PlannedCompanions {
        var ownerBySource: [String: PlannedTransfer] = [:]
        for transfer in ownerTransfers where ownerBySource[transfer.sourcePath] == nil {
            ownerBySource[transfer.sourcePath] = transfer
        }

        struct Candidate {
            var companion: String
            var owner: PlannedTransfer
            var destination: String
        }

        var candidates: [Candidate] = []
        for companion in resolution.ownersByCompanion.keys.sorted() {
            guard let ownerSource = resolution.ownersByCompanion[companion],
                  let owner = ownerBySource[ownerSource],
                  let form = nameForm(companion: companion, owner: ownerSource) else {
                continue
            }
            candidates.append(Candidate(
                companion: companion,
                owner: owner,
                destination: destinationPath(companion: companion, owner: owner, form: form)
            ))
        }

        var plannedDestinationCounts: [String: Int] = [:]
        for transfer in ownerTransfers {
            plannedDestinationCounts[transfer.destinationPath.lowercased(), default: 0] += 1
        }
        for candidate in candidates {
            plannedDestinationCounts[candidate.destination.lowercased(), default: 0] += 1
        }

        var transfers: [PlannedTransfer] = []
        var unresolved = resolution.unresolved
        var companionOwners: [String: String] = [:]

        for candidate in candidates {
            if plannedDestinationCounts[candidate.destination.lowercased(), default: 0] > 1
                || fileExists(candidate.destination) {
                unresolved.append(UnresolvedCompanion(sourcePath: candidate.companion, reason: .nameTaken))
                continue
            }
            guard let companionIdentity = identity(candidate.companion) else {
                unresolved.append(UnresolvedCompanion(sourcePath: candidate.companion, reason: .unreadable))
                continue
            }
            transfers.append(PlannedTransfer(
                sourcePath: candidate.companion,
                destinationPath: candidate.destination,
                identity: companionIdentity,
                dateBucket: candidate.owner.dateBucket,
                isDuplicate: candidate.owner.isDuplicate
            ))
            companionOwners[candidate.companion] = candidate.owner.sourcePath
        }

        return PlannedCompanions(
            transfers: transfers.sorted { $0.sourcePath < $1.sourcePath },
            unresolved: unresolved.sorted { $0.sourcePath < $1.sourcePath },
            companionOwners: companionOwners
        )
    }

    // MARK: - Name matching

    private static func directory(of path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    private static func extensionText(of path: String) -> String {
        let ext = URL(fileURLWithPath: path).pathExtension
        return ext.isEmpty ? "" : ".\(ext)"
    }

    /// How `companion`'s name relates to `owner`'s name, or nil when it does
    /// not belong to it. Same directory is checked by the caller (`resolve`)
    /// and implied for planning by the resolved map.
    private static func nameForm(companion: String, owner: String) -> NameForm? {
        let companionURL = URL(fileURLWithPath: companion)
        let ownerURL = URL(fileURLWithPath: owner)
        let companionBase = companionURL.deletingPathExtension().lastPathComponent.lowercased()
        let ownerStem = ownerURL.deletingPathExtension().lastPathComponent.lowercased()
        let ownerFullName = ownerURL.lastPathComponent.lowercased()

        if companionBase == ownerStem { return .stem }
        if companionBase == ownerFullName { return .appended }

        // iOS edit form: IMG_<digits>.<ext> owns IMG_E<digits>.aae (exact digits).
        if MediaLibraryRules.normalizedExtension(for: companion) == ".aae",
           companionBase.hasPrefix("img_e"),
           ownerStem.hasPrefix("img_") {
            let companionDigits = companionBase.dropFirst(5)
            let ownerDigits = ownerStem.dropFirst(4)
            if !companionDigits.isEmpty,
               companionDigits == ownerDigits,
               companionDigits.allSatisfy({ $0.isASCII && $0.isNumber }) {
                return .stem
            }
        }
        return nil
    }

    private static func destinationPath(companion: String, owner: PlannedTransfer, form: NameForm) -> String {
        let ownerDestination = URL(fileURLWithPath: owner.destinationPath)
        let ownerName: String
        switch form {
        case .stem:
            ownerName = ownerDestination.deletingPathExtension().lastPathComponent
        case .appended:
            ownerName = ownerDestination.lastPathComponent
        }
        return ownerDestination
            .deletingLastPathComponent()
            .appendingPathComponent(ownerName + extensionText(of: companion))
            .path
    }
}
