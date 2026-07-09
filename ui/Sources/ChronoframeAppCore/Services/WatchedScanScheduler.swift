import Foundation

/// Bounds the freshness-scan workload across all watched sources:
/// per-source debounce after filesystem activity, a global concurrency
/// cap, and adaptive backoff for sources that churn continuously (a
/// long sync writing thousands of files should not trigger a scan per
/// event batch).
///
/// Scheduling only — the scheduler never decides *what* a scan does or
/// whether its result applies; generation guards in the coordinator
/// handle staleness.
@MainActor
public final class WatchedScanScheduler {
    public struct Configuration: Sendable {
        public var maxConcurrent: Int
        public var debounce: TimeInterval
        /// Extra delay per consecutive churned (invalidated) scan:
        /// level 1 → steps[0], level 2 → steps[1], … capped at the last.
        public var backoffSteps: [TimeInterval]

        public init(
            maxConcurrent: Int = 2,
            debounce: TimeInterval = 3.0,
            backoffSteps: [TimeInterval] = [30, 60, 120, 300]
        ) {
            self.maxConcurrent = maxConcurrent
            self.debounce = debounce
            self.backoffSteps = backoffSteps
        }
    }

    private let configuration: Configuration
    private let sleeper: @Sendable (TimeInterval) async -> Void
    private var pendingTasks: [UUID: Task<Void, Never>] = [:]
    private var churnLevels: [UUID: Int] = [:]
    private var runningCount = 0
    private var slotWaiters: [CheckedContinuation<Void, Never>] = []

    public init(
        configuration: Configuration = Configuration(),
        sleeper: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    ) {
        self.configuration = configuration
        self.sleeper = sleeper
    }

    /// Schedules (or re-schedules, coalescing) a scan for `id`. A newer
    /// request replaces a pending one — the debounce window restarts.
    /// `immediate` skips debounce AND backoff (launch catch-up, manual
    /// refresh, reconcile signals); the concurrency cap always applies.
    public func schedule(
        id: UUID,
        immediate: Bool = false,
        _ work: @escaping @MainActor () async -> Void
    ) {
        pendingTasks[id]?.cancel()
        let delay = immediate ? 0 : configuration.debounce + backoffDelay(for: id)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                await self.sleeper(delay)
            }
            guard !Task.isCancelled else { return }
            await self.acquireSlot()
            defer { self.releaseSlot() }
            guard !Task.isCancelled else { return }
            await work()
        }
        pendingTasks[id] = task
    }

    /// The scan for `id` completed but was already stale (events arrived
    /// while it ran) — escalate its backoff so a continuously-changing
    /// source settles into a slower cadence.
    public func noteChurn(id: UUID) {
        churnLevels[id, default: 0] += 1
    }

    /// The source produced a scan that stuck — reset its backoff.
    public func noteQuiet(id: UUID) {
        churnLevels[id] = nil
    }

    public func backoffDelay(for id: UUID) -> TimeInterval {
        guard let level = churnLevels[id], level > 0, !configuration.backoffSteps.isEmpty else {
            return 0
        }
        return configuration.backoffSteps[min(level - 1, configuration.backoffSteps.count - 1)]
    }

    public func cancel(id: UUID) {
        pendingTasks[id]?.cancel()
        pendingTasks[id] = nil
        churnLevels[id] = nil
    }

    public func cancelAll() {
        for task in pendingTasks.values {
            task.cancel()
        }
        pendingTasks.removeAll()
        churnLevels.removeAll()
        // Resume anyone parked on the concurrency gate so no continuation
        // leaks; their tasks are cancelled and bail before doing work.
        let waiters = slotWaiters
        slotWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func acquireSlot() async {
        if runningCount < configuration.maxConcurrent {
            runningCount += 1
            return
        }
        await withCheckedContinuation { continuation in
            slotWaiters.append(continuation)
        }
        runningCount += 1
    }

    private func releaseSlot() {
        runningCount = max(0, runningCount - 1)
        if !slotWaiters.isEmpty {
            slotWaiters.removeFirst().resume()
        }
    }
}
