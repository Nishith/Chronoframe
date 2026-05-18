import ChronoframeCLIKit
import Foundation
import Dispatch

// PHASE2_FINDINGS.md NEW22 — install signal sources for SIGINT and
// SIGTERM. The default disposition would kill the process immediately
// without flushing stdout, so a JSON consumer downstream might miss
// the last buffered event. Take over via DispatchSource, flush both
// stdout and stderr, and exit with the conventional signal-derived
// codes (130 for SIGINT, 143 for SIGTERM).
//
// We don't attempt cooperative cancellation of the in-flight engine
// Task from the signal handler — Swift Tasks aren't safely
// cancellable from a signal context. The engine is already crash-safe
// (audit receipts use atomic writes; partial transfers are reflected
// in PENDING receipt state), so exit-on-signal is acceptable.
@MainActor
final class SignalHandlerInstaller {
    private var sources: [DispatchSourceSignal] = []

    func install() {
        let entries: [(Int32, Int32)] = [
            (SIGINT, 130),
            (SIGTERM, 143),
        ]
        for (sig, code) in entries {
            // Ignore default disposition so DispatchSource can deliver.
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                fflush(stdout)
                fflush(stderr)
                Foundation.exit(code)
            }
            source.resume()
            sources.append(source)
        }
    }
}

let signalHandlers = SignalHandlerInstaller()
signalHandlers.install()

let exitCode = await ChronoframeCLI.run(arguments: Array(CommandLine.arguments.dropFirst()))
Foundation.exit(exitCode)
