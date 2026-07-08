import Foundation

/// Identity stamp for one file inside a watched source, keyed by its
/// source-root-relative path. Nanosecond mtime plus ctime plus size make
/// an in-place replacement with an equal size and millisecond mtime
/// still register as a change.
public struct WatchedFileStamp: Codable, Equatable, Sendable {
    public var sizeBytes: Int64
    public var mtimeNanoseconds: Int64
    public var ctimeNanoseconds: Int64

    public init(sizeBytes: Int64, mtimeNanoseconds: Int64, ctimeNanoseconds: Int64) {
        self.sizeBytes = sizeBytes
        self.mtimeNanoseconds = mtimeNanoseconds
        self.ctimeNanoseconds = ctimeNanoseconds
    }
}

/// Whether a freshness scan saw the whole source. A scan that could not
/// read part of the tree must never be treated as authoritative: acting
/// on it would let "caught up" hide files Chronoframe simply couldn't
/// see.
public enum WatchedScanCompleteness: Equatable, Sendable {
    case complete
    case partial(unreadableSubtrees: Int)

    public var isComplete: Bool {
        if case .complete = self { return true }
        return false
    }
}

/// Result of one discovery-only freshness scan of a watched source.
public struct WatchedScanResult: Sendable {
    public var entries: [String: WatchedFileStamp]
    public var issues: [MediaDiscovery.DirectoryIssue]
    public var completeness: WatchedScanCompleteness
    public var capturedAt: Date

    public init(
        entries: [String: WatchedFileStamp],
        issues: [MediaDiscovery.DirectoryIssue],
        completeness: WatchedScanCompleteness,
        capturedAt: Date
    ) {
        self.entries = entries
        self.issues = issues
        self.completeness = completeness
        self.capturedAt = capturedAt
    }
}

/// Discovery-only freshness logic for watched sources.
///
/// Contract: this code never hashes file contents, never opens a
/// database, and never touches the destination. It exists to produce a
/// conservative "new arrivals" **estimate** — the authoritative plan is
/// always the real organize preview. Overcounting is acceptable;
/// silently hiding work is not, which is why partial scans are marked
/// as such and acknowledged checkpoints only ever advance from stamps
/// that were captured before an import was requested.
public enum WatchedSourceFreshness {
    /// Default quiescence window: entries modified more recently than
    /// this are treated as still settling (a sync tool may still be
    /// writing them) and held out of the pending estimate until a later
    /// scan sees them stable.
    public static let defaultSettlingWindow: TimeInterval = 5.0

    /// Walks the source with the exact same skip rules as organize
    /// discovery (hidden entries, symlinks, packages/photo libraries,
    /// unsupported extensions, iCloud dataless files) so the estimate
    /// counts precisely the files a real preview would discover.
    /// `lstat` only — no content reads.
    public static func scan(
        rootURL: URL,
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> WatchedScanResult {
        let issueBox = IssueBox()
        let standardizedRoot = rootURL.standardizedFileURL.path
        let rootPrefix = standardizedRoot.hasSuffix("/") ? standardizedRoot : standardizedRoot + "/"

        var entries: [String: WatchedFileStamp] = [:]
        try MediaDiscovery.enumerateMediaFiles(
            at: rootURL,
            isCancelled: isCancelled,
            onDirectoryIssue: { issueBox.append($0) }
        ) { path in
            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard standardizedPath.hasPrefix(rootPrefix) else { return }
            // A file that vanishes between discovery and lstat is normal
            // churn (the next scan settles it); skip without failing.
            guard let stamp = Self.stamp(forPath: standardizedPath) else { return }
            let relativePath = String(standardizedPath.dropFirst(rootPrefix.count))
            entries[relativePath] = stamp
        }

        let issues = issueBox.snapshot()
        return WatchedScanResult(
            entries: entries,
            issues: issues,
            completeness: issues.isEmpty ? .complete : .partial(unreadableSubtrees: issues.count),
            capturedAt: now
        )
    }

    /// Upper-bound "new since acknowledged": paths present now that are
    /// absent from the acknowledged checkpoint, plus paths whose stamp
    /// changed. Removals never count — a file the user deleted from the
    /// source is not pending work.
    public static func pendingRelativePaths(
        current: [String: WatchedFileStamp],
        acknowledged: [String: WatchedFileStamp]
    ) -> Set<String> {
        var pending: Set<String> = []
        for (path, stamp) in current {
            if acknowledged[path] != stamp {
                pending.insert(path)
            }
        }
        return pending
    }

    /// Checkpoint advance for a completed import: merge exactly the
    /// captured stamps into the acknowledged set. Files that appeared or
    /// changed after capture keep their live stamps in the next scan and
    /// therefore stay pending — an import can never acknowledge work the
    /// user was not shown.
    public static func merged(
        acknowledged: [String: WatchedFileStamp],
        acknowledging captured: [String: WatchedFileStamp]
    ) -> [String: WatchedFileStamp] {
        acknowledged.merging(captured) { _, capturedStamp in capturedStamp }
    }

    /// Checkpoint hygiene, applied only from a COMPLETE scan of an
    /// available source: drop acknowledged entries for paths that no
    /// longer exist so the checkpoint doesn't grow without bound. If a
    /// pruned file later reappears it counts as pending again — the
    /// conservative direction.
    public static func pruned(
        acknowledged: [String: WatchedFileStamp],
        retainingKeysIn current: [String: WatchedFileStamp]
    ) -> [String: WatchedFileStamp] {
        acknowledged.filter { current[$0.key] != nil }
    }

    /// Entries stamped within `settlingWindow` of `now` are still being
    /// written by whatever produced them; hold them out of the estimate
    /// until a later scan sees them stable.
    public static func settledEntries(
        _ entries: [String: WatchedFileStamp],
        now: Date,
        settlingWindow: TimeInterval = WatchedSourceFreshness.defaultSettlingWindow
    ) -> [String: WatchedFileStamp] {
        let cutoffNs = Int64((now.timeIntervalSince1970 - settlingWindow) * 1_000_000_000)
        return entries.filter { $0.value.mtimeNanoseconds <= cutoffNs }
    }

    /// Convenience: the pending estimate a complete scan produces, after
    /// the settling-window holdout.
    public static func pendingEstimate(
        current: [String: WatchedFileStamp],
        acknowledged: [String: WatchedFileStamp],
        now: Date,
        settlingWindow: TimeInterval = WatchedSourceFreshness.defaultSettlingWindow
    ) -> Int {
        let settled = settledEntries(current, now: now, settlingWindow: settlingWindow)
        return pendingRelativePaths(current: settled, acknowledged: acknowledged).count
    }

    /// lstat-based stamp; nil when the path vanished or cannot be
    /// stat'ed (the caller skips it and a later scan reconciles).
    static func stamp(forPath path: String) -> WatchedFileStamp? {
        var status = stat()
        guard lstat(path, &status) == 0 else { return nil }
        return WatchedFileStamp(
            sizeBytes: Int64(status.st_size),
            mtimeNanoseconds: Int64(status.st_mtimespec.tv_sec) * 1_000_000_000 + Int64(status.st_mtimespec.tv_nsec),
            ctimeNanoseconds: Int64(status.st_ctimespec.tv_sec) * 1_000_000_000 + Int64(status.st_ctimespec.tv_nsec)
        )
    }

    /// Lock-guarded issue accumulator: `onDirectoryIssue` is a
    /// `@Sendable` callback, so the box must be safe to share even
    /// though the walk itself is synchronous.
    private final class IssueBox: @unchecked Sendable {
        private let lock = NSLock()
        private var issues: [MediaDiscovery.DirectoryIssue] = []

        func append(_ issue: MediaDiscovery.DirectoryIssue) {
            lock.lock()
            defer { lock.unlock() }
            issues.append(issue)
        }

        func snapshot() -> [MediaDiscovery.DirectoryIssue] {
            lock.lock()
            defer { lock.unlock() }
            return issues
        }
    }
}
