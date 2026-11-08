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
            let gate = ProbeGate(continuation)
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
}

/// Resumes its continuation exactly once; the first result wins.
private final class ProbeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String?, Never>?

    init(_ continuation: CheckedContinuation<String?, Never>) {
        self.continuation = continuation
    }

    func finish(_ value: String?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: value)
    }
}
