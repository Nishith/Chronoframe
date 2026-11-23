import Foundation

/// Count-dependent phrases for the Run timeline. A count of 1 chooses a
/// complete singular phrase instead of "1 planned files" or "across 1 months",
/// and each phrase is looked up whole so languages with case and number
/// agreement (German: "von 1 geplanten Datei", "in 3 Monaten") can translate
/// it. Phrases are context-specific on purpose: "planned files" and "of planned
/// files" are different cases in German.
enum TimelinePlurals {
    static func plannedFiles(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 planned file", other: "%@ planned files", bundle: bundle)
    }

    static func ofPlannedFiles(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "of 1 planned file", other: "of %@ planned files", bundle: bundle)
    }

    static func acrossMonths(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "across 1 month", other: "across %@ months", bundle: bundle)
    }

    static func filesToCopy(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 file to copy", other: "%@ files to copy", bundle: bundle)
    }

    private static func phrase(_ count: Int, one: String, other: String, bundle: Bundle) -> String {
        count == 1
            ? AppLocalization.string(one, bundle: bundle)
            : AppLocalization.format(other, count.formatted(), bundle: bundle)
    }
}
