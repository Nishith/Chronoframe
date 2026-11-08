#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// Decides whether the folder picker may open at a saved NAS library's location.
/// Resolving a bookmark and looking at a dead network mount can block for a long time,
/// so the work runs on a background queue and is raced against a timeout. It never runs
/// on the main actor, and a late answer is discarded.
public enum NASReconnectProbe {
    public static func validatedStartPath(
        for record: NASLibraryRecord,
        resolve: @escaping @Sendable (FolderBookmark) -> URL?,
        observe: @escaping @Sendable (URL) -> NASLibraryObservation?,
        timeoutSeconds: Double = 2.0
    ) async -> String? {
        await withCheckedContinuation { continuation in
            let gate = ProbeGate<String?>(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                guard let url = resolve(record.bookmark),
                      let observed = observe(url)
                else {
                    gate.finish(nil)
                    return
                }
                switch NASLibraryIdentity.compare(recorded: record.lastObservation, observed: observed) {
                case .same, .remounted:
                    gate.finish(url.path)
                case .mismatch, .ambiguous:
                    gate.finish(nil)
                }
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(timeoutSeconds, 0)) {
                gate.finish(nil)
            }
        }
    }

    /// Observes `url` on a background queue and races it against a timeout, so a dead mount
    /// can't hold the caller. The outer `nil` means the timeout won; the inner `nil` means
    /// the observation itself found nothing. A late answer is discarded.
    static func observeWithTimeout(
        _ url: URL,
        observe: @escaping @Sendable (URL) -> NASLibraryObservation?,
        timeoutSeconds: Double = 2.0
    ) async -> NASLibraryObservation?? {
        await withCheckedContinuation { continuation in
            let gate = ProbeGate<NASLibraryObservation??>(continuation)
            DispatchQueue.global(qos: .userInitiated).async {
                gate.finish(.some(observe(url)))
            }
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(timeoutSeconds, 0)) {
                gate.finish(.none)
            }
        }
    }
}

/// Resumes its continuation exactly once; the first result wins.
private final class ProbeGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: Value) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
