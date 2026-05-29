import Foundation

/// Pairs a deduplication decision with a symbol *and* a text label so the
/// keep/delete state is never communicated by color alone (WCAG 1.4.1). Views
/// render the glyph and feed the label to VoiceOver; tests assert the mapping is
/// total and non-empty.
enum DedupeDecisionGlyph: Equatable {
    case keep
    case delete
    case undecided

    /// SF Symbol name representing the decision.
    var symbolName: String {
        switch self {
        case .keep: return "checkmark.circle.fill"
        case .delete: return "trash.circle.fill"
        case .undecided: return "circle"
        }
    }

    /// Spoken/visible label for the decision.
    var label: String {
        switch self {
        case .keep: return "Keep"
        case .delete: return "Delete"
        case .undecided: return "Not yet decided"
        }
    }

    /// All cases, for total-mapping tests.
    static let all: [DedupeDecisionGlyph] = [.keep, .delete, .undecided]
}
