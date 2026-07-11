import Foundation

// MARK: - Guardian library probe (Phase 1)
//
// The I/O half of a scrub. It walks the library, hashes each media file, and emits
// raw `GuardianFileObservation`s for the pure `GuardianIntegrityClassifier` to
// judge. Keeping the walking/hashing here (and classification separate) means the
// decision logic stays pure and unit-testable.
//
// Read-only: the probe only reads. It never writes into the library.
//
// Edge cases handled here, per the Guardian design:
//   * symlinks / packages / hidden system files are skipped (MediaDiscovery,
//     safety invariant #20);
//   * an unreadable subtree marks the scan partial rather than reporting its files
//     as missing;
//   * iCloud-dataless files are recorded as `.dataless`, never corruption;
//   * a file whose size or mtime changes while it is being hashed is recorded as
//     `.changedDuringScan`, never corruption;
//   * hard links are de-duplicated by inode so one physical file is probed once.

public struct GuardianLibraryProbe: Sendable {
    public struct Result: Sendable {
        public var observations: [GuardianFileObservation]
        /// True if any subtree could not be fully read; the classifier then does not
        /// treat manifest entries as missing.
        public var partialScan: Bool

        public init(observations: [GuardianFileObservation], partialScan: Bool) {
            self.observations = observations
            self.partialScan = partialScan
        }
    }

    /// Thread-safe flag the `@Sendable` directory-issue callback can set.
    private final class PartialFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var flagged = false
        func mark() { lock.lock(); flagged = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return flagged }
    }

    private let hasher: FileIdentityHasher

    public init(hasher: FileIdentityHasher = FileIdentityHasher()) {
        self.hasher = hasher
    }

    public func probe(
        libraryRoot: URL,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> Result {
        var observations: [GuardianFileObservation] = []
        var seenInodes = Set<UInt64>()
        let partial = PartialFlag()

        try MediaDiscovery.enumerateMediaFiles(
            at: libraryRoot,
            isCancelled: isCancelled,
            onDirectoryIssue: { _ in partial.mark() }
        ) { path in
            let url = URL(fileURLWithPath: path)
            guard let key = GuardianPathNormalization.relativeKey(of: url, underRoot: libraryRoot) else {
                return
            }
            if let observation = observe(url: url, relativeKey: key, seenInodes: &seenInodes) {
                observations.append(observation)
            }
        }

        return Result(observations: observations, partialScan: partial.isSet)
    }

    private func observe(
        url: URL,
        relativeKey: String,
        seenInodes: inout Set<UInt64>
    ) -> GuardianFileObservation? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return GuardianFileObservation(
                relativePath: relativeKey,
                size: 0,
                modificationTime: 0,
                digest: nil,
                outcome: .unreadable
            )
        }

        // De-duplicate hard links: a second name for the same inode is skipped.
        if let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value {
            if seenInodes.contains(inode) { return nil }
            seenInodes.insert(inode)
        }

        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

        if MediaDiscovery.isICloudDatalessProvider(url) {
            return GuardianFileObservation(
                relativePath: relativeKey,
                size: size,
                modificationTime: mtime,
                digest: nil,
                outcome: .dataless
            )
        }

        let identity: FileIdentity
        do {
            identity = try hasher.hashIdentity(at: url, knownSize: size)
        } catch {
            return GuardianFileObservation(
                relativePath: relativeKey,
                size: size,
                modificationTime: mtime,
                digest: nil,
                outcome: .unreadable
            )
        }

        // If size or mtime changed while we were hashing, the reading is untrustworthy.
        if let after = try? FileManager.default.attributesOfItem(atPath: url.path) {
            let sizeAfter = (after[.size] as? NSNumber)?.int64Value ?? size
            let mtimeAfter = (after[.modificationDate] as? Date)?.timeIntervalSince1970 ?? mtime
            if sizeAfter != size || abs(mtimeAfter - mtime) >= GuardianIntegrityClassifier.modificationTimeTolerance {
                return GuardianFileObservation(
                    relativePath: relativeKey,
                    size: size,
                    modificationTime: mtime,
                    digest: nil,
                    outcome: .changedDuringScan
                )
            }
        }

        return GuardianFileObservation(
            relativePath: relativeKey,
            size: size,
            modificationTime: mtime,
            digest: identity.digest,
            outcome: .hashed
        )
    }
}
