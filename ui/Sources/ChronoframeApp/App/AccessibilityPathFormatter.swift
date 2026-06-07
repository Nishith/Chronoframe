import Foundation

/// Helper to generate screen-reader friendly summaries of directory and file paths.
/// Instead of spelling out long absolute paths (e.g. `/Users/name/Pictures/Vacation`),
/// it speaks a natural description using the base name (e.g. `Vacation folder`).
enum AccessibilityPathFormatter {
    /// Returns a localized/spoken representation of the given file system path.
    static func spokenDescription(for path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Not set"
        }

        let url = URL(fileURLWithPath: trimmed)
        let name = url.lastPathComponent
        if name.isEmpty || name == "/" {
            return "Root folder"
        }

        // If the path component lacks an extension, treat it as a folder for VoiceOver clarity.
        if url.pathExtension.isEmpty {
            return "\(name) folder"
        } else {
            return name
        }
    }
}
