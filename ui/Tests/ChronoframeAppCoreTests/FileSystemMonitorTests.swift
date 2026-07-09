import XCTest
@testable import ChronoframeCore

final class FileSystemMonitorTests: XCTestCase {
    private typealias PollingStamp = FileSystemMonitor.PollingStamp

    /// Shared collector that flattens `FileSystemMonitorOutput` into
    /// per-file events and reconcile reasons.
    private actor OutputCollector {
        var events: [FileSystemEvent] = []
        var reasons: [FileSystemReconcileReason] = []

        func record(_ output: FileSystemMonitorOutput) {
            switch output {
            case .events(let batch):
                events.append(contentsOf: batch)
            case .reconcileRequired(let reason):
                reasons.append(reason)
            }
        }

        func contains(path: String) -> Bool { events.contains { $0.path.contains(path) } }
        func first(path: String) -> FileSystemEvent? { events.first { $0.path.contains(path) } }
        func containsRemoved(path: String) -> Bool {
            events.contains { $0.path.contains(path) && $0.isRemoved }
        }
        func containsCreated(suffix: String) -> Bool {
            events.contains { $0.path.hasSuffix(suffix) && $0.isCreated }
        }
        func containsModified(suffix: String) -> Bool {
            events.contains { $0.path.hasSuffix(suffix) && $0.isModified }
        }
        func createdCount(path: String) -> Int {
            events.filter { $0.path == path && $0.isCreated }.count
        }
        var isEmpty: Bool { events.isEmpty }
    }

    func testFileSystemMonitorEmitsEventsOnCreation() async throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FSMonitorTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let monitor = FileSystemMonitor(paths: [temporaryDirectory.path], latency: 0.1)
        let stream = monitor.start()

        let fileURL = temporaryDirectory.appendingPathComponent("test.txt")

        let expectation = XCTestExpectation(description: "Wait for FS events")
        let collector = OutputCollector()

        let task = Task {
            for await output in stream {
                await collector.record(output)
                if await collector.contains(path: "test.txt") {
                    expectation.fulfill()
                }
            }
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        // Trigger event
        try Data("hello".utf8).write(to: fileURL)

        await fulfillment(of: [expectation], timeout: 5.0)

        let isEmpty = await collector.isEmpty
        XCTAssertFalse(isEmpty)
        let firstEvent = await collector.first(path: "test.txt")
        let event = try XCTUnwrap(firstEvent)
        XCTAssertTrue(event.isFile)
        XCTAssertFalse(monitor.isDegraded, "FSEvents path should not report degraded watching")

        task.cancel()
        monitor.stop()
    }

    func testFileSystemMonitorHandlesDeletion() async throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FSMonitorDeleteTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("to_delete.txt")
        try Data("delete me".utf8).write(to: fileURL)

        let monitor = FileSystemMonitor(paths: [temporaryDirectory.path], latency: 0.1)
        let stream = monitor.start()

        let expectation = XCTestExpectation(description: "Wait for deletion event")
        let collector = OutputCollector()

        let task = Task {
            for await output in stream {
                await collector.record(output)
                if await collector.containsRemoved(path: "to_delete.txt") {
                    expectation.fulfill()
                }
            }
        }

        try await Task.sleep(nanoseconds: 300_000_000)

        // Trigger deletion
        try FileManager.default.removeItem(at: fileURL)

        await fulfillment(of: [expectation], timeout: 5.0)

        task.cancel()
        monitor.stop()
    }

    func testPollingSnapshotIncludesRootsAndNestedItems() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FSMonitorSnapshotTest-\(UUID().uuidString)")
        let nestedDirectory = temporaryDirectory.appendingPathComponent("Nested", isDirectory: true)
        let fileURL = nestedDirectory.appendingPathComponent("image.jpg")
        let rootFileURL = temporaryDirectory.appendingPathComponent("loose.mov")
        let missingURL = temporaryDirectory.appendingPathComponent("missing")

        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        try Data("jpg".utf8).write(to: fileURL)
        try Data("mov".utf8).write(to: rootFileURL)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let snapshot = FileSystemMonitor.pollingSnapshot(paths: [
            temporaryDirectory.path,
            rootFileURL.path,
            missingURL.path
        ])

        XCTAssertEqual(snapshot[temporaryDirectory.path]?.isFile, false)
        XCTAssertEqual(snapshot.first { $0.key.hasSuffix("/Nested") }?.value.isFile, false)
        XCTAssertEqual(snapshot.first { $0.key.hasSuffix("/Nested/image.jpg") }?.value.isFile, true)
        XCTAssertEqual(snapshot[rootFileURL.path]?.isFile, true)
        XCTAssertNil(snapshot[missingURL.path])
    }

    func testPollingSnapshotRecordsSizeAndModificationStamps() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FSMonitorStampTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let fileURL = temporaryDirectory.appendingPathComponent("stamped.jpg")
        try Data("12345".utf8).write(to: fileURL)

        let snapshot = FileSystemMonitor.pollingSnapshot(paths: [temporaryDirectory.path])
        // Suffix lookup, matching the sibling snapshot test: enumerator
        // keys resolve /var/folders to /private/var/folders on macOS, so
        // a direct path-keyed lookup misses.
        let stamp = try XCTUnwrap(snapshot.first { $0.key.hasSuffix("/stamped.jpg") }?.value)
        XCTAssertTrue(stamp.isFile)
        XCTAssertEqual(stamp.sizeBytes, 5)
        XCTAssertGreaterThan(stamp.modifiedAt, 0, "Modification stamp should be captured")
    }

    func testPollingEventsReportsCreatedAndRemovedPathsInStableOrder() {
        let previous: [String: PollingStamp] = [
            "/tmp/a-old-directory": PollingStamp(isFile: false),
            "/tmp/z-old-file": PollingStamp(isFile: true, sizeBytes: 1, modifiedAt: 1)
        ]
        let current: [String: PollingStamp] = [
            "/tmp/b-new-file": PollingStamp(isFile: true, sizeBytes: 2, modifiedAt: 2),
            "/tmp/c-new-directory": PollingStamp(isFile: false)
        ]

        let events = FileSystemMonitor.pollingEvents(previous: previous, current: current)

        XCTAssertEqual(events.map(\.path), [
            "/tmp/b-new-file",
            "/tmp/c-new-directory",
            "/tmp/a-old-directory",
            "/tmp/z-old-file"
        ])
        XCTAssertEqual(events.map(\.isCreated), [true, true, false, false])
        XCTAssertEqual(events.map(\.isRemoved), [false, false, true, true])
        XCTAssertEqual(events.map(\.isFile), [true, false, false, true])
    }

    /// The polling fallback must detect in-place modifications — a file
    /// replaced or rewritten keeps its path but changes size or mtime.
    /// The old presence-only snapshot missed these entirely.
    func testPollingEventsDetectsInPlaceModification() {
        let previous: [String: PollingStamp] = [
            "/tmp/photo.jpg": PollingStamp(isFile: true, sizeBytes: 100, modifiedAt: 10),
            "/tmp/rewritten.jpg": PollingStamp(isFile: true, sizeBytes: 100, modifiedAt: 10),
            "/tmp/same.jpg": PollingStamp(isFile: true, sizeBytes: 50, modifiedAt: 5),
            "/tmp/dir": PollingStamp(isFile: false)
        ]
        let current: [String: PollingStamp] = [
            "/tmp/photo.jpg": PollingStamp(isFile: true, sizeBytes: 200, modifiedAt: 10),
            "/tmp/rewritten.jpg": PollingStamp(isFile: true, sizeBytes: 100, modifiedAt: 20),
            "/tmp/same.jpg": PollingStamp(isFile: true, sizeBytes: 50, modifiedAt: 5),
            "/tmp/dir": PollingStamp(isFile: false)
        ]

        let events = FileSystemMonitor.pollingEvents(previous: previous, current: current)

        let modified = events.filter { $0.isModified }.map(\.path).sorted()
        XCTAssertEqual(modified, ["/tmp/photo.jpg", "/tmp/rewritten.jpg"],
                       "Size change and mtime change must both surface as modifications")
        XCTAssertTrue(events.allSatisfy { !$0.isCreated && !$0.isRemoved },
                      "No spurious create/remove events for stable paths")
    }

    /// Regression for PHASE2_FINDINGS.md NEW3 — `start()` used to launch
    /// `startPollingFallback()` unconditionally and THEN set up FSEvents,
    /// so every real filesystem change emitted twice (once from the
    /// FSEvents callback, once from the next poll tick). Now the polling
    /// fallback only fires when `FSEventStreamCreate` returns nil.
    func testFileSystemMonitorDoesNotDoubleYieldEventsWhenFSEventsIsActive() async throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FSMonitorNoDoubleYield-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        // Use a very small latency to make FSEvents and the polling
        // fallback both have a realistic chance to fire within the test
        // window, were the bug to regress.
        let monitor = FileSystemMonitor(paths: [temporaryDirectory.path], latency: 0.1)
        let stream = monitor.start()

        let collector = OutputCollector()

        let task = Task {
            for await output in stream {
                await collector.record(output)
            }
        }

        // Settle.
        try await Task.sleep(nanoseconds: 300_000_000)

        // Create three files. Each should produce at most one "isCreated"
        // event per path. If the polling fallback is running alongside
        // FSEvents, we'd see two — one from each source.
        let urls = (0..<3).map {
            temporaryDirectory.appendingPathComponent("file-\($0).txt")
        }
        for url in urls {
            try Data("x".utf8).write(to: url)
        }

        // Give both potential producers more than enough time to fire.
        try await Task.sleep(nanoseconds: 800_000_000)

        for url in urls {
            let count = await collector.createdCount(path: url.path)
            XCTAssertLessThanOrEqual(
                count, 1,
                "NEW3 regression: path \(url.path) emitted \(count) created events; expected ≤1"
            )
        }

        task.cancel()
        monitor.stop()
    }

    /// Regression for PHASE2_FINDINGS.md NEW4 — repeated start/stop
    /// cycles must not crash from unsynchronized continuation mutation.
    /// The classic failure was `__DISPATCH_WAIT_FOR_QUEUE__` SIGTRAP
    /// when `onTermination` fired on the FSEvents queue while `stop()`
    /// tried to take that same queue.
    func testFileSystemMonitorSurvivesRepeatedStartStopCycles() async throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FSMonitorRestart-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let monitor = FileSystemMonitor(paths: [temporaryDirectory.path], latency: 0.1)
        for _ in 0..<5 {
            let stream = monitor.start()
            let task = Task {
                for await _ in stream {}
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            monitor.stop()
            task.cancel()
        }
        // Reaching here means no deadlock or trap during teardown.
    }

    /// Regression for PHASE2_FINDINGS.md NEW5 — the FSEvents callback
    /// used to dereference an unmanaged `self` pointer that could outlive
    /// the monitor. With retain/release callbacks installed on the
    /// FSEventStreamContext, the stream holds a +1 retain on `self` while
    /// it's alive. This test exercises the lifetime contract by letting
    /// `monitor` go out of scope while a stream is mid-flight.
    func testFileSystemMonitorReleasesItselfCleanlyWhenDroppedMidStream() async throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FSMonitorDrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        // Hold a weak reference so we can verify the monitor is actually
        // deallocated after the stream consumer drops.
        weak var weakMonitor: FileSystemMonitor?

        do {
            let monitor = FileSystemMonitor(paths: [temporaryDirectory.path], latency: 0.1)
            weakMonitor = monitor
            let stream = monitor.start()
            try Data("trigger".utf8).write(
                to: temporaryDirectory.appendingPathComponent("triggers-callback.txt")
            )
            // Pull one batch then stop iterating — the AsyncStream's
            // onTermination fires, which calls stop(), which releases the
            // FSEventStream, which fires the release callback, which
            // releases the retained `self`.
            for await _ in stream { break }
            monitor.stop()
        }

        // Give the runtime a tick to clean up.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertNil(weakMonitor, "NEW5 regression: monitor leaked after stream consumer dropped")
    }

    /// Exercises the polling fallback path directly via the
    /// `forcePollingOnly: true` test seam so the fallback's Task loop
    /// (`startPollingFallback`) is covered without having to engineer an
    /// `FSEventStreamCreate` failure (which is rare and platform-
    /// specific in practice).
    func testPollingFallbackEmitsCreatedModifiedAndRemovedEvents() async throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FSMonitorPolling-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let monitor = FileSystemMonitor(
            paths: [temporaryDirectory.path],
            latency: 0.1,
            forcePollingOnly: true
        )
        let stream = monitor.start()

        let collector = OutputCollector()
        let task = Task {
            for await output in stream {
                await collector.record(output)
            }
        }

        let target = temporaryDirectory.appendingPathComponent("poll-target.txt")
        try Data("poll".utf8).write(to: target)
        // Polling interval is `max(latency, 0.1)` = 0.1s; give 4 ticks.
        try await Task.sleep(nanoseconds: 400_000_000)
        let created = await collector.containsCreated(suffix: "poll-target.txt")
        XCTAssertTrue(created, "Polling fallback should emit a created event for new file")

        // In-place rewrite with a different size: must surface as a
        // modification even though the path never changed.
        try Data("poll-rewritten".utf8).write(to: target)
        try await Task.sleep(nanoseconds: 400_000_000)
        let modified = await collector.containsModified(suffix: "poll-target.txt")
        XCTAssertTrue(modified, "Polling fallback should emit a modified event for in-place rewrite")

        try FileManager.default.removeItem(at: target)
        try await Task.sleep(nanoseconds: 400_000_000)
        let removed = await collector.containsRemoved(path: "poll-target.txt")
        XCTAssertTrue(removed, "Polling fallback should emit a removed event for deleted file")

        task.cancel()
        monitor.stop()
    }

    /// The polling fallback is reduced-fidelity watching: it must flag
    /// itself as degraded and open the stream with a reconcile signal so
    /// the consumer runs a full scan instead of trusting incremental
    /// state.
    func testPollingFallbackReportsDegradedAndEmitsPollingGapReconcile() async throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FSMonitorDegraded-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let monitor = FileSystemMonitor(
            paths: [temporaryDirectory.path],
            latency: 0.1,
            forcePollingOnly: true
        )
        let stream = monitor.start()

        var firstOutput: FileSystemMonitorOutput?
        for await output in stream {
            firstOutput = output
            break
        }

        guard case .reconcileRequired(let reason) = firstOutput else {
            XCTFail("Polling fallback must open with a reconcile signal, got \(String(describing: firstOutput))")
            monitor.stop()
            return
        }
        XCTAssertEqual(reason, .pollingGap)
        XCTAssertTrue(monitor.isDegraded, "Polling fallback must report degraded watching")

        monitor.stop()
        XCTAssertFalse(monitor.isDegraded, "Degraded flag clears on stop")
    }

    /// Regression for PHASE2_FINDINGS.md NEW23 — when a watched root
    /// disappears (volume ejected, parent dir deleted), the naive diff
    /// would emit one `isRemoved` event per previously-seen descendant.
    /// Collapsed flood: single `isRemoved` event on the root itself.
    func testPollingEventsCollapsesRootDisappearanceIntoOneRemovedEvent() {
        let previous: [String: PollingStamp] = [
            "/Volumes/Drive": PollingStamp(isFile: false),
            "/Volumes/Drive/photo1.jpg": PollingStamp(isFile: true, sizeBytes: 1, modifiedAt: 1),
            "/Volumes/Drive/photo2.jpg": PollingStamp(isFile: true, sizeBytes: 2, modifiedAt: 2),
            "/Volumes/Drive/nested": PollingStamp(isFile: false),
            "/Volumes/Drive/nested/photo3.jpg": PollingStamp(isFile: true, sizeBytes: 3, modifiedAt: 3),
        ]
        let current: [String: PollingStamp] = [:]  // entire root unmounted
        let events = FileSystemMonitor.pollingEvents(
            previous: previous,
            current: current,
            roots: ["/Volumes/Drive"]
        )
        XCTAssertEqual(events.count, 1, "Disappeared-root flood must collapse")
        XCTAssertEqual(events[0].path, "/Volumes/Drive")
        XCTAssertTrue(events[0].isRemoved)
    }

    /// Sanity: when `roots` isn't passed, behavior matches the
    /// pre-NEW23 contract — every removed path produces an event.
    func testPollingEventsWithoutRootsHintProducesPerPathRemovals() {
        let previous: [String: PollingStamp] = [
            "/a/file1.jpg": PollingStamp(isFile: true, sizeBytes: 1, modifiedAt: 1),
            "/a/file2.jpg": PollingStamp(isFile: true, sizeBytes: 2, modifiedAt: 2),
        ]
        let current: [String: PollingStamp] = [:]
        let events = FileSystemMonitor.pollingEvents(previous: previous, current: current)
        XCTAssertEqual(events.count, 2)
        XCTAssertTrue(events.allSatisfy { $0.isRemoved })
    }

    func testPollingEventsReturnsNoEventsForUnchangedSnapshot() {
        let snapshot: [String: PollingStamp] = [
            "/tmp/folder": PollingStamp(isFile: false),
            "/tmp/folder/photo.heic": PollingStamp(isFile: true, sizeBytes: 9, modifiedAt: 9)
        ]

        XCTAssertTrue(FileSystemMonitor.pollingEvents(previous: snapshot, current: snapshot).isEmpty)
    }

    // MARK: - FSEvents flag classification (pure)

    func testOutputsClassifiesPlainFileEvents() {
        let created = UInt32(kFSEventStreamEventFlagItemCreated) | UInt32(kFSEventStreamEventFlagItemIsFile)
        let removed = UInt32(kFSEventStreamEventFlagItemRemoved) | UInt32(kFSEventStreamEventFlagItemIsFile)

        let outputs = FileSystemMonitor.outputs(
            eventPaths: ["/w/a.jpg", "/w/b.jpg"],
            eventFlags: [created, removed]
        )

        XCTAssertEqual(outputs.count, 1)
        guard case .events(let events) = outputs[0] else {
            return XCTFail("Expected a single events batch")
        }
        XCTAssertEqual(events.map(\.path), ["/w/a.jpg", "/w/b.jpg"])
        XCTAssertTrue(events[0].isCreated)
        XCTAssertTrue(events[1].isRemoved)
        XCTAssertTrue(events.allSatisfy(\.isFile))
    }

    /// Dropped-event flags mean FSEvents lost data — incremental state
    /// can no longer be trusted and the consumer must reconcile.
    func testOutputsSurfacesDroppedEventsAsReconcileRequired() {
        for droppedFlag in [
            UInt32(kFSEventStreamEventFlagUserDropped),
            UInt32(kFSEventStreamEventFlagKernelDropped)
        ] {
            let outputs = FileSystemMonitor.outputs(
                eventPaths: ["/w"],
                eventFlags: [droppedFlag]
            )
            XCTAssertEqual(outputs.count, 1)
            guard case .reconcileRequired(let reason) = outputs[0] else {
                return XCTFail("Expected reconcileRequired for dropped-event flag \(droppedFlag)")
            }
            XCTAssertEqual(reason, .droppedEvents)
        }
    }

    func testOutputsSurfacesMustScanSubDirsAsReconcileRequired() {
        let outputs = FileSystemMonitor.outputs(
            eventPaths: ["/w/sub"],
            eventFlags: [UInt32(kFSEventStreamEventFlagMustScanSubDirs)]
        )
        XCTAssertEqual(outputs.count, 1)
        guard case .reconcileRequired(let reason) = outputs[0] else {
            return XCTFail("Expected reconcileRequired for MustScanSubDirs")
        }
        XCTAssertEqual(reason, .mustScanSubDirs)
    }

    /// With `kFSEventStreamCreateFlagWatchRoot`, a rename or move of the
    /// watched root arrives as a RootChanged event — the path we were
    /// watching no longer means what it did.
    func testOutputsSurfacesRootChangedAsReconcileRequired() {
        let outputs = FileSystemMonitor.outputs(
            eventPaths: ["/w"],
            eventFlags: [UInt32(kFSEventStreamEventFlagRootChanged)]
        )
        XCTAssertEqual(outputs.count, 1)
        guard case .reconcileRequired(let reason) = outputs[0] else {
            return XCTFail("Expected reconcileRequired for RootChanged")
        }
        XCTAssertEqual(reason, .rootChanged)
    }

    /// A mixed batch keeps reconcile signals first (deduplicated) and
    /// the surviving per-file events in one trailing batch.
    func testOutputsOrdersDeduplicatedReconcileSignalsBeforeEvents() {
        let created = UInt32(kFSEventStreamEventFlagItemCreated) | UInt32(kFSEventStreamEventFlagItemIsFile)
        let outputs = FileSystemMonitor.outputs(
            eventPaths: ["/w/x", "/w/a.jpg", "/w/y", "/w/b.jpg"],
            eventFlags: [
                UInt32(kFSEventStreamEventFlagMustScanSubDirs),
                created,
                UInt32(kFSEventStreamEventFlagMustScanSubDirs),
                created
            ]
        )

        XCTAssertEqual(outputs.count, 2, "Duplicate reconcile reasons must collapse")
        guard case .reconcileRequired(let reason) = outputs[0] else {
            return XCTFail("Reconcile signal must come first")
        }
        XCTAssertEqual(reason, .mustScanSubDirs)
        guard case .events(let events) = outputs[1] else {
            return XCTFail("Expected trailing events batch")
        }
        XCTAssertEqual(events.map(\.path), ["/w/a.jpg", "/w/b.jpg"])
    }
}
