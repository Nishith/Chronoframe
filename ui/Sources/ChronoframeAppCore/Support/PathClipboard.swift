import Foundation

/// Seam over the system pasteboard so "Copy Path" actions can be unit-tested
/// without reaching into `NSPasteboard.general`. The concrete AppKit-backed
/// writer lives in `ChronoframeApp`; tests inject a fake.
public protocol PathPasteboard {
    /// Replace the pasteboard contents with a single filesystem path string.
    func writePath(_ path: String)
}

/// Pure entry point for copying a path to a pasteboard. Centralizes the
/// (currently trivial) policy of what string lands on the clipboard so views
/// don't each reimplement it and so the behavior is covered by a test.
public enum PathClipboard {
    public static func copy(_ path: String, to pasteboard: PathPasteboard) {
        pasteboard.writePath(path)
    }
}
