import Foundation

// MARK: - Canonical multi-root destination lock (Phase 0)
//
// Guardian's verified **restore** is the only surface that mutates two roots in one
// operation, so it is the only caller of this helper: it writes the library
// (same-directory quarantine + atomic install) and locks the mirror so the verified
// copy source can't change mid-restore. Acquiring two exclusive
// `DestinationOperationLock`s without a global ordering can deadlock two competing
// operations, so this helper:
//
//   * rejects overlapping roots (equal, or either nested inside the other, after
//     symlink resolution) — those can never be locked as two independent roots;
//   * orders acquisition by canonical absolute path, which is a total, deterministic
//     order shared across processes (the volume identity is already encoded in the
//     absolute mount path), so two operations always grab shared roots in the same
//     order and cannot deadlock;
//   * acquires all-or-nothing: any failure releases every lease already taken.
//
// Read-only Guardian surfaces never lock the library through this helper: a scrub
// takes no library lock (it only reads, coordinating via Application Support), and a
// mirror pass locks only the writable mirror while reading the library. The library
// is locked here solely by restore, which is already writing it — and its in-root
// `.organize_logs` lease is exactly what makes restore mutually exclusive with a
// concurrent organize/dedupe/reorganize on the same folder (all of which lock that
// same path). Any future read-only multi-root need must pass an explicit
// `lockFileURL` via `GuardianLockRoot.init(url:lockFileURL:…)`, pointing outside the
// protected root — the `inRoot` convenience is reserved for a root the operation
// actually mutates.
//
// Note: like `DestinationOperationLock`, this relies on `flock`, which is unreliable
// across multiple hosts on a network volume. It only guarantees mutual exclusion on
// a single machine.

/// One root to lock. `url` is the protected root (used only for deadlock-safe
/// ordering and overlap rejection); `lockFileURL` is where the physical lock file
/// is actually created. Keeping these separate is what lets Guardian lock a
/// read-only library **without** writing into it — the lock file lives in
/// Application Support, not under the library root.
public struct GuardianLockRoot: Sendable, Equatable {
    public var url: URL
    public var lockFileURL: URL
    public var surface: String
    public var operation: String

    /// Lock `url` using an explicit lock-file location. Use this for a read-only
    /// library, pointing `lockFileURL` at an Application Support path keyed by the
    /// library identity so acquiring the lease never mutates the library.
    public init(url: URL, lockFileURL: URL, surface: String, operation: String) {
        self.url = url
        self.lockFileURL = lockFileURL
        self.surface = surface
        self.operation = operation
    }

    /// Convenience for a **writable** root whose lock should coordinate with
    /// organize/dedupe: the lock lives at `<url>/.organize_logs/<lockName>` inside
    /// the root itself (the historical `DestinationOperationLock` location). Never
    /// use this for a read-only library root — it would write into the library.
    public static func inRoot(_ url: URL, surface: String, operation: String) -> GuardianLockRoot {
        let lockFileURL = url
            .appendingPathComponent(".organize_logs", isDirectory: true)
            .appendingPathComponent(DestinationOperationLock.filename)
        return GuardianLockRoot(url: url, lockFileURL: lockFileURL, surface: surface, operation: operation)
    }
}

public enum GuardianMultiRootLockError: Error, Equatable {
    /// Two requested roots resolve to overlapping locations and cannot be locked
    /// independently.
    case overlappingRoots(String, String)
}

/// Holds every lease acquired for a multi-root operation. Releasing frees them all;
/// release is idempotent and also runs on deinit.
public final class GuardianMultiRootLease: @unchecked Sendable {
    private let stateLock = NSLock()
    private var leases: [DestinationOperationLease]

    fileprivate init(leases: [DestinationOperationLease]) {
        self.leases = leases
    }

    public func release() {
        stateLock.lock()
        let toRelease = leases
        leases = []
        stateLock.unlock()
        // Release in reverse acquisition order for symmetry.
        for lease in toRelease.reversed() {
            lease.release()
        }
    }

    deinit { release() }
}

public enum GuardianMultiRootLock {
    /// Acquire an exclusive lease on every root, in a canonical order, atomically.
    /// Throws `GuardianMultiRootLockError.overlappingRoots` if two roots overlap, or
    /// the underlying `DestinationBusyError`/POSIX error if a root is already locked.
    public static func acquire(_ roots: [GuardianLockRoot]) throws -> GuardianMultiRootLease {
        let ordered = try canonicallyOrdered(roots)

        var acquired: [DestinationOperationLease] = []
        do {
            for root in ordered {
                let lease = try DestinationOperationLock.acquire(
                    lockFileURL: root.lockFileURL,
                    surface: root.surface,
                    operation: root.operation
                )
                acquired.append(lease)
            }
        } catch {
            for lease in acquired.reversed() {
                lease.release()
            }
            throw error
        }
        return GuardianMultiRootLease(leases: acquired)
    }

    /// A root paired with its resolved canonical path. A named type (rather than a
    /// tuple) keeps type inference cheap for the Release whole-module compile.
    private struct KeyedRoot {
        let root: GuardianLockRoot
        let path: String
    }

    /// Roots sorted by canonical absolute path, after rejecting any overlapping pair.
    /// Exposed for testing the ordering and overlap rules without touching the disk.
    public static func canonicallyOrdered(_ roots: [GuardianLockRoot]) throws -> [GuardianLockRoot] {
        var keyed: [KeyedRoot] = []
        keyed.reserveCapacity(roots.count)
        for root in roots {
            keyed.append(KeyedRoot(root: root, path: canonicalPath(root.url)))
        }
        for i in keyed.indices {
            for j in keyed.indices where j > i {
                if pathsOverlap(keyed[i].path, keyed[j].path) {
                    throw GuardianMultiRootLockError.overlappingRoots(keyed[i].path, keyed[j].path)
                }
            }
        }
        let sorted: [KeyedRoot] = keyed.sorted { $0.path < $1.path }
        var ordered: [GuardianLockRoot] = []
        ordered.reserveCapacity(sorted.count)
        for item in sorted {
            ordered.append(item.root)
        }
        return ordered
    }

    /// Resolve symlinks and standardize so equal/nested checks are reliable.
    public static func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Two roots overlap when they are equal or one contains the other, compared by
    /// path components so `/a/b` does not spuriously match `/a/bc`.
    public static func pathsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        if lhs == rhs { return true }
        let a = URL(fileURLWithPath: lhs).pathComponents
        let b = URL(fileURLWithPath: rhs).pathComponents
        let shorter = a.count <= b.count ? a : b
        let longer = a.count <= b.count ? b : a
        return Array(longer.prefix(shorter.count)) == shorter
    }
}
