import Foundation

/// Centralized accessibility labels and hints for elements whose spoken
/// description is non-trivial or shared across surfaces.
///
/// Trivial, locally-obvious labels (a button whose title already reads well to
/// VoiceOver) stay inline. This enum is the home for descriptions that benefit
/// from a single definition — drop targets, custom controls, and any text that
/// pairs a control with its keyboard equivalent — so they can be reviewed and,
/// later, localized from one place.
enum AccessibilityLabels {

    // MARK: - Setup

    /// Label for the source drag-and-drop target.
    static let dropZone = "Drop photos, videos, or folders to use as source"
    /// Hint that points VoiceOver/keyboard users at the equivalent button, since
    /// the drop target itself cannot be activated from the keyboard.
    static let dropZoneHint = "Or use the Choose Source button to pick a folder"
}
