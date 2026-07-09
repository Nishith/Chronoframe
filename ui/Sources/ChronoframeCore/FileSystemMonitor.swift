import Foundation
import CoreServices

/// FSEvents-based folder watcher that streams file-system change events.
/// Production consumer: watched-source freshness tracking (Sources tab).
///
/// Ordering contract
/// -----------------
/// The FSEvents stream is created with `kFSEventStreamEventIdSinceNow`,
/// so changes that happen before `start()` returns are never delivered.
/// Callers must therefore `start()` the monitor *first* and only then run
/// their catch-up scan; anything that changed in between is covered by
/// the scan, and anything after it by the stream. Consumers should also
/// tag scans with a monotonic generation so a slower, older scan can
/// never overwrite the result of a newer one.
///
/// Fidelity contract
/// -----------------
/// FSEvents can drop events (kernel or user buffer exhaustion) and can
/// coalesce a subtree into a single "must scan sub dirs" hint. Those
/// conditions are surfaced as `.reconcileRequired(_:)` outputs instead of
/// per-file events; on receipt the consumer must run a full reconciliation
/// scan rather than trusting incremental state. The watched root itself is
/// tracked with `kFSEventStreamCreateFlagWatchRoot`, so a rename or move
/// of the root arrives as `.reconcileRequired(.rootChanged)`.
///
/// Threading model
/// ---------------
/// `streamRef`, `continuation`, `pollingTask`, and `degraded` are guarded
/// by `stateLock` (NSLock, recursive-safe in practice because we only
/// hold it across short pointer-snapshot operations and never call out
/// to FSEvents APIs or `Continuation.yield` while holding it).
///
/// Why a lock and not `queue.sync`: `onTermination` on the
/// `AsyncStream.Continuation` can fire on `queue` itself (when stream
/// completion is processed by an iterator pulling on that queue). If
/// `stop()` then called `queue.sync`, dispatch would detect the
/// same-queue deadlock and trap with SIGTRAP via
/// `__DISPATCH_WAIT_FOR_QUEUE__`. NSLock side-steps that entirely.
///
/// Lifetime model
/// --------------
/// The FSEventStream holds a +1 retain on `self` via the retain/release
/// callbacks installed in `FSEventStreamContext`. `self` therefore stays
/// alive for as long as the stream exists, which makes the
/// `takeUnretainedValue` in the FSEvents callback safe — the retained
/// reference holds the floor until `FSEventStreamRelease` triggers the
/// release callback at the end of `stop()`.
///
/// Polling vs FSEvents
/// -------------------
/// Polling is a *fallback*, not a supplement. It only starts when
/// `FSEventStreamCreate` returns nil. Running both at once would yield
/// every event twice — once from FSEvents, once from the next poll tick.
/// While the fallback is active `isDegraded` is true and the stream opens
/// with `.reconcileRequired(.pollingGap)` so consumers know incremental
/// fidelity is reduced. The fallback keeps per-path size/mtime stamps so
/// in-place modifications are detected, not just additions and removals.
public final class FileSystemMonitor: @unchecked Sendable {
    private let paths: [String]
    private let latency: TimeInterval
    /// When true, `start()` skips the FSEvents path entirely and goes
    /// straight to the polling fallback. Exists so unit tests can
    /// exercise the polling branch without having to engineer an
    /// `FSEventStreamCreate` failure (which is rare in practice).
    /// Production code always uses the FSEvents path.
    private let forcePollingOnly: Bool

    private let queue = DispatchQueue(label: "com.chronoframe.fsmonitor", qos: .utility)
    private let stateLock = NSLock()
    private var streamRef: FSEventStreamRef?
    private var continuation: AsyncStream<FileSystemMonitorOutput>.Continuation?
    private var pollingTask: Task<Void, Never>?
    private var degraded = false

    /// True while the polling fallback is active in place of FSEvents.
    /// Consumers may surface this as reduced-fidelity watching.
    public var isDegraded: Bool {
        withState { degraded }
    }

    private func withState<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }

    public init(paths: [String], latency: TimeInterval = 2.0) {
        self.paths = paths
        self.latency = latency
        self.forcePollingOnly = false
    }

    /// Testing entry point: forces the polling-only fallback path so
    /// tests can verify the polling task without engineering an
    /// FSEventStreamCreate failure.
    init(paths: [String], latency: TimeInterval, forcePollingOnly: Bool) {
        self.paths = paths
        self.latency = latency
        self.forcePollingOnly = forcePollingOnly
    }

    deinit {
        // Tear down without re-entering the queue. By the time deinit
        // runs, the FSEventStream has already been released (it held a
        // strong reference via the retain callback while it was alive),
        // so there's nothing on the queue that depends on `self`.
        teardown()
    }

    public func start() -> AsyncStream<FileSystemMonitorOutput> {
        stop()

        return AsyncStream { continuation in
            self.withState {
                self.continuation = continuation
                self.degraded = false
            }
            continuation.onTermination = { @Sendable [weak self] _ in
                self?.stop()
            }

            // Try FSEvents first; only fall back to polling if creation
            // fails. Running both at once would yield every event twice.
            // `forcePollingOnly` is a test seam (see init) that skips the
            // FSEvents branch entirely so the polling path can be
            // exercised without engineering an FSEventStreamCreate fail.
            if self.forcePollingOnly || !self.setupFSEvents() {
                self.startPollingFallback()
            }
        }
    }

    public func stop() {
        teardown()
    }

    private func teardown() {
        // Snapshot under the lock, then tear down outside the lock so the
        // FSEvents APIs and `Continuation.finish` never run while we
        // hold `stateLock` (some of those calls may themselves trigger
        // onTermination handlers that re-enter `stop()`).
        let (stream, continuation, polling): (FSEventStreamRef?, AsyncStream<FileSystemMonitorOutput>.Continuation?, Task<Void, Never>?) = withState {
            let s = self.streamRef
            let c = self.continuation
            let p = self.pollingTask
            self.streamRef = nil
            self.continuation = nil
            self.pollingTask = nil
            self.degraded = false
            return (s, c, p)
        }
        polling?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        continuation?.finish()
    }

    /// Returns true when the FSEventStream was created and started, false
    /// when `FSEventStreamCreate` returned nil so the caller can start
    /// the polling fallback in its place.
    private func setupFSEvents() -> Bool {
        // Keep this @convention(c) closure minimal: extract plain
        // Sendable values and hand off to an instance method. Swift
        // 6.0.3's TransferNonSendable region analysis crashes (signal 6,
        // Partition::merge abort) when richer logic lives inside the C
        // callback, so classification and yielding happen in
        // `handleCallbackBatch` instead.
        let callback: FSEventStreamCallback = { _, clientInfo, numEvents, eventPaths, eventFlags, _ in
            guard let clientInfo else { return }
            // `takeUnretainedValue` is safe: the retain callback below
            // bumped the refcount when the stream took ownership of the
            // `info` pointer.
            let monitor = Unmanaged<FileSystemMonitor>.fromOpaque(clientInfo).takeUnretainedValue()

            guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else {
                return
            }

            let flags = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
            monitor.handleCallbackBatch(eventPaths: paths, eventFlags: flags)
        }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: fileSystemMonitorRetainCallback,
            release: fileSystemMonitorReleaseCallback,
            copyDescription: nil
        )

        let pathsCF = self.paths as CFArray
        let createFlags: FSEventStreamCreateFlags =
            UInt32(kFSEventStreamCreateFlagFileEvents) |
            UInt32(kFSEventStreamCreateFlagUseCFTypes) |
            UInt32(kFSEventStreamCreateFlagNoDefer) |
            UInt32(kFSEventStreamCreateFlagWatchRoot)

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsCF,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            self.latency,
            createFlags
        ) else {
            return false
        }

        self.withState { self.streamRef = stream }
        FSEventStreamSetDispatchQueue(stream, self.queue)
        FSEventStreamStart(stream)
        return true
    }

    /// Classifies one FSEvents batch and yields the outputs. Called from
    /// the C callback on the FSEvents dispatch queue.
    private func handleCallbackBatch(eventPaths: [String], eventFlags: [UInt32]) {
        let outputs = Self.outputs(eventPaths: eventPaths, eventFlags: eventFlags)
        guard !outputs.isEmpty else { return }
        // Snapshot the continuation under `stateLock` so we never race
        // the assignment in `start()` or the nil-out in `stop()`.
        // Yielding is done outside the lock — yield itself is documented
        // thread-safe and we don't want to hold `stateLock` across a
        // callback into consumer code.
        let continuation = withState { self.continuation }
        for output in outputs {
            continuation?.yield(output)
        }
    }

    /// Pure classification of one FSEvents callback batch into stream
    /// outputs. Reconcile conditions (dropped events, must-scan-subdirs,
    /// root changes) are surfaced as `.reconcileRequired` — deduplicated
    /// per batch, ordered before the remaining per-file events — because
    /// incremental state cannot be trusted once any of them occur.
    static func outputs(
        eventPaths: [String],
        eventFlags: [UInt32]
    ) -> [FileSystemMonitorOutput] {
        var reasons: [FileSystemReconcileReason] = []
        var events: [FileSystemEvent] = []

        func noteReason(_ reason: FileSystemReconcileReason) {
            if !reasons.contains(reason) {
                reasons.append(reason)
            }
        }

        for index in 0..<min(eventPaths.count, eventFlags.count) {
            let flags = eventFlags[index]

            if flags & UInt32(kFSEventStreamEventFlagUserDropped) != 0 ||
                flags & UInt32(kFSEventStreamEventFlagKernelDropped) != 0 {
                noteReason(.droppedEvents)
                continue
            }
            if flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 {
                noteReason(.mustScanSubDirs)
                continue
            }
            if flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
                noteReason(.rootChanged)
                continue
            }

            events.append(FileSystemEvent(
                path: eventPaths[index],
                flags: flags,
                isFile: flags & UInt32(kFSEventStreamEventFlagItemIsFile) != 0,
                isCreated: flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0,
                isModified: flags & UInt32(kFSEventStreamEventFlagItemModified) != 0,
                isRemoved: flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0
            ))
        }

        var outputs: [FileSystemMonitorOutput] = reasons.map { .reconcileRequired($0) }
        if !events.isEmpty {
            outputs.append(.events(events))
        }
        return outputs
    }

    private func startPollingFallback() {
        var snapshot = Self.pollingSnapshot(paths: paths)
        let interval = max(latency, 0.1)

        withState { self.degraded = true }
        // Polling cannot see anything that happened before its first
        // snapshot and its fidelity is coarser than FSEvents; tell the
        // consumer to reconcile rather than trust incremental state.
        let initialContinuation = withState { self.continuation }
        initialContinuation?.yield(.reconcileRequired(.pollingGap))

        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard let self else { return }

                let nextSnapshot = Self.pollingSnapshot(paths: self.paths)
                let events = Self.pollingEvents(
                    previous: snapshot,
                    current: nextSnapshot,
                    roots: self.paths
                )
                if !events.isEmpty {
                    let continuation = self.withState { self.continuation }
                    continuation?.yield(.events(events))
                }
                snapshot = nextSnapshot
            }
        }
        self.withState { self.pollingTask = task }
    }

    /// Per-path identity snapshot used by the polling fallback. Size and
    /// mtime let the diff detect in-place modifications, not just
    /// additions and removals.
    struct PollingStamp: Equatable, Sendable {
        var isFile: Bool
        var sizeBytes: Int64
        var modifiedAt: TimeInterval

        init(isFile: Bool, sizeBytes: Int64 = 0, modifiedAt: TimeInterval = 0) {
            self.isFile = isFile
            self.sizeBytes = sizeBytes
            self.modifiedAt = modifiedAt
        }
    }

    static func pollingEvents(
        previous: [String: PollingStamp],
        current: [String: PollingStamp],
        roots: [String] = []
    ) -> [FileSystemEvent] {
        let oldPaths = Set(previous.keys)
        let newPaths = Set(current.keys)

        // Detect watched roots that disappeared this tick (volume
        // ejected, parent directory deleted). The naive diff would
        // emit one `isRemoved` event per previously-seen descendant —
        // tens of thousands of bogus events. Collapse the flood into
        // a single `isRemoved` event on the root itself.
        let standardizedRoots = roots.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        var disappearedRoots: Set<String> = []
        for root in standardizedRoots {
            if oldPaths.contains(root) && !newPaths.contains(root) {
                disappearedRoots.insert(root)
            }
        }

        var events: [FileSystemEvent] = []
        for path in newPaths.subtracting(oldPaths).sorted() {
            events.append(FileSystemEvent(
                path: path,
                isFile: current[path]?.isFile ?? false,
                isCreated: true
            ))
        }

        // In-place modifications: same path in both snapshots but the
        // size or mtime stamp changed. Only files — directory mtimes
        // churn on every child change and would double-report.
        for path in newPaths.intersection(oldPaths).sorted() {
            guard let before = previous[path], let after = current[path] else { continue }
            guard after.isFile, before.isFile else { continue }
            if before.sizeBytes != after.sizeBytes || before.modifiedAt != after.modifiedAt {
                events.append(FileSystemEvent(
                    path: path,
                    isFile: true,
                    isModified: true
                ))
            }
        }

        for path in oldPaths.subtracting(newPaths).sorted() {
            // If this removed path is a descendant of a root that just
            // disappeared, suppress it — the synthesized root-removed
            // event covers the whole subtree.
            let isUnderDisappearedRoot = disappearedRoots.contains { root in
                path != root && path.hasPrefix(root + "/")
            }
            if isUnderDisappearedRoot { continue }

            events.append(FileSystemEvent(
                path: path,
                isFile: previous[path]?.isFile ?? false,
                isRemoved: true
            ))
        }

        return events
    }

    static func pollingSnapshot(paths: [String]) -> [String: PollingStamp] {
        var snapshot: [String: PollingStamp] = [:]
        let fileManager = FileManager.default
        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey
        ]

        func stamp(for url: URL) -> PollingStamp {
            let resourceValues = try? url.resourceValues(forKeys: Set(resourceKeys))
            let isFile = resourceValues?.isRegularFile ?? false
            return PollingStamp(
                isFile: isFile,
                sizeBytes: Int64(resourceValues?.fileSize ?? 0),
                modifiedAt: resourceValues?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0
            )
        }

        for rootPath in paths {
            let rootURL = URL(fileURLWithPath: rootPath, isDirectory: true)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: rootPath, isDirectory: &isDirectory) else {
                continue
            }

            if isDirectory.boolValue {
                snapshot[rootURL.path] = PollingStamp(isFile: false)
            } else {
                snapshot[rootURL.path] = stamp(for: URL(fileURLWithPath: rootPath))
            }

            guard isDirectory.boolValue,
                  let enumerator = fileManager.enumerator(
                    at: rootURL,
                    includingPropertiesForKeys: resourceKeys,
                    options: [.skipsPackageDescendants]
                  )
            else {
                continue
            }

            for case let url as URL in enumerator {
                snapshot[url.path] = stamp(for: url)
            }
        }

        return snapshot
    }
}

// Top-level C-callable retain/release functions for the FSEventStreamContext.
// Declared at file scope so the @convention(c) conversion is unambiguous.
private func fileSystemMonitorRetainCallback(_ ptr: UnsafeRawPointer?) -> UnsafeRawPointer? {
    guard let ptr else { return nil }
    _ = Unmanaged<FileSystemMonitor>.fromOpaque(ptr).retain()
    return ptr
}

private func fileSystemMonitorReleaseCallback(_ ptr: UnsafeRawPointer?) {
    guard let ptr else { return }
    Unmanaged<FileSystemMonitor>.fromOpaque(ptr).release()
}

/// Why incremental event state can no longer be trusted and a full
/// reconciliation scan is required.
public enum FileSystemReconcileReason: Sendable, Equatable {
    /// FSEvents reported kernel- or user-space event loss.
    case droppedEvents
    /// FSEvents coalesced a subtree; per-file fidelity was lost.
    case mustScanSubDirs
    /// The watched root itself moved or was renamed (WatchRoot).
    case rootChanged
    /// The polling fallback is active; it cannot observe changes that
    /// happened before its first snapshot.
    case pollingGap
}

/// One unit of monitor output: either a batch of per-file events, or a
/// signal that the consumer must run a full reconciliation scan.
public enum FileSystemMonitorOutput: Sendable {
    case events([FileSystemEvent])
    case reconcileRequired(FileSystemReconcileReason)
}

public struct FileSystemEvent: Sendable {
    public var path: String
    public var flags: UInt32
    public var isFile: Bool
    public var isCreated: Bool
    public var isModified: Bool
    public var isRemoved: Bool

    public init(
        path: String,
        flags: UInt32 = 0,
        isFile: Bool = false,
        isCreated: Bool = false,
        isModified: Bool = false,
        isRemoved: Bool = false
    ) {
        self.path = path
        self.flags = flags
        self.isFile = isFile
        self.isCreated = isCreated
        self.isModified = isModified
        self.isRemoved = isRemoved
    }
}
