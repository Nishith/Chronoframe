import Foundation
import XCTest
@testable import ChronoframeAppCore

@MainActor
final class WatchedScanSchedulerTests: XCTestCase {
    /// Records every requested sleep without actually waiting, so tests
    /// can assert debounce/backoff arithmetic deterministically.
    private final class SleepRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [TimeInterval] = []

        func record(_ seconds: TimeInterval) {
            lock.lock()
            defer { lock.unlock() }
            recorded.append(seconds)
        }

        var delays: [TimeInterval] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }
    }

    /// MainActor-bound label log: scheduler work closures are
    /// `@MainActor`, and `waitForCondition` polls a synchronous
    /// MainActor closure, so both sides can touch this directly.
    @MainActor
    private final class Runs {
        var labels: [String] = []
        func bump(_ label: String) { labels.append(label) }
        var startedCount: Int { labels.filter { $0.hasPrefix("start-") }.count }
        var endedCount: Int { labels.filter { $0.hasPrefix("end-") }.count }
    }

    func testDebouncedScheduleCoalescesToTheLatestRequest() async {
        let recorder = SleepRecorder()
        let scheduler = WatchedScanScheduler(
            configuration: .init(maxConcurrent: 2, debounce: 3.0, backoffSteps: []),
            sleeper: { recorder.record($0) }
        )
        let id = UUID()
        let runs = Runs()

        scheduler.schedule(id: id) { runs.bump("first") }
        scheduler.schedule(id: id) { runs.bump("second") }
        scheduler.schedule(id: id) { runs.bump("third") }

        let done = await waitForCondition { runs.labels.count >= 1 }
        XCTAssertTrue(done)
        // Give any (incorrectly) surviving earlier tasks a chance to run.
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(runs.labels, ["third"], "Newer requests replace pending ones")
        XCTAssertTrue(recorder.delays.allSatisfy { $0 == 3.0 })
    }

    func testImmediateScheduleSkipsDebounceAndBackoff() async {
        let recorder = SleepRecorder()
        let scheduler = WatchedScanScheduler(
            configuration: .init(maxConcurrent: 2, debounce: 3.0, backoffSteps: [30]),
            sleeper: { recorder.record($0) }
        )
        let id = UUID()
        scheduler.noteChurn(id: id)
        let runs = Runs()

        scheduler.schedule(id: id, immediate: true) { runs.bump("immediate") }

        let done = await waitForCondition { runs.labels.count == 1 }
        XCTAssertTrue(done)
        XCTAssertTrue(recorder.delays.isEmpty, "Immediate scans never sleep")
    }

    func testBackoffEscalatesPerChurnAndCapsAtLastStep() {
        let scheduler = WatchedScanScheduler(
            configuration: .init(maxConcurrent: 2, debounce: 3.0, backoffSteps: [30, 60, 120])
        )
        let id = UUID()
        XCTAssertEqual(scheduler.backoffDelay(for: id), 0)

        scheduler.noteChurn(id: id)
        XCTAssertEqual(scheduler.backoffDelay(for: id), 30)
        scheduler.noteChurn(id: id)
        XCTAssertEqual(scheduler.backoffDelay(for: id), 60)
        scheduler.noteChurn(id: id)
        XCTAssertEqual(scheduler.backoffDelay(for: id), 120)
        scheduler.noteChurn(id: id)
        XCTAssertEqual(scheduler.backoffDelay(for: id), 120, "Backoff caps at the last step")

        scheduler.noteQuiet(id: id)
        XCTAssertEqual(scheduler.backoffDelay(for: id), 0, "A settled scan resets backoff")
    }

    func testBackoffDelayIsAddedToDebounce() async {
        let recorder = SleepRecorder()
        let scheduler = WatchedScanScheduler(
            configuration: .init(maxConcurrent: 2, debounce: 3.0, backoffSteps: [30]),
            sleeper: { recorder.record($0) }
        )
        let id = UUID()
        scheduler.noteChurn(id: id)
        let runs = Runs()

        scheduler.schedule(id: id) { runs.bump("scan") }
        let done = await waitForCondition { runs.labels.count == 1 }
        XCTAssertTrue(done)

        XCTAssertEqual(recorder.delays, [33.0])
    }

    /// The concurrency cap bounds simultaneous scans across ALL sources;
    /// a third scan waits until one of the first two finishes.
    func testConcurrencyCapHoldsThirdScanUntilSlotFrees() async {
        let scheduler = WatchedScanScheduler(
            configuration: .init(maxConcurrent: 2, debounce: 0, backoffSteps: []),
            sleeper: { _ in }
        )
        let gate = AsyncGate()
        let runs = Runs()

        for label in ["a", "b", "c"] {
            scheduler.schedule(id: UUID(), immediate: true) {
                runs.bump("start-\(label)")
                await gate.wait()
                runs.bump("end-\(label)")
            }
        }

        let twoStarted = await waitForCondition { runs.startedCount == 2 }
        XCTAssertTrue(twoStarted)
        // The third must be parked on the slot gate.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(runs.startedCount, 2, "Cap of 2 must hold the third scan back")

        await gate.open()
        let allDone = await waitForCondition { runs.endedCount == 3 }
        XCTAssertTrue(allDone)
    }

    func testCancelAllStopsPendingWork() async {
        let scheduler = WatchedScanScheduler(
            configuration: .init(maxConcurrent: 1, debounce: 5.0, backoffSteps: []),
            sleeper: { seconds in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
        )
        let runs = Runs()
        scheduler.schedule(id: UUID()) { runs.bump("never") }

        scheduler.cancelAll()
        try? await Task.sleep(nanoseconds: 150_000_000)

        XCTAssertEqual(runs.labels.count, 0, "Cancelled pending scans must not run")
    }

    /// Suspends waiters until opened; used to hold scans "running".
    private actor AsyncGate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            let parked = waiters
            waiters = []
            for waiter in parked {
                waiter.resume()
            }
        }
    }
}
