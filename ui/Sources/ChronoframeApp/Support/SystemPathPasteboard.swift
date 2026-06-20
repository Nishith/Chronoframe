import AppKit
import ChronoframeAppCore

/// Production `PathPasteboard` backed by the system general pasteboard.
/// Thin adapter — all copy policy lives in `PathClipboard` so this stays
/// untested glue.
struct SystemPathPasteboard: PathPasteboard {
    static let shared = SystemPathPasteboard()

    func writePath(_ path: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(path, forType: .string)
    }
}
