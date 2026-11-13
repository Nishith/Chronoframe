#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// User-facing wording for a restored or saved Deduplicate review.
///
/// Every sentence is a format key in `Localizable.xcstrings`; the counts are
/// `%lld` and the date is a pre-formatted `%@`. The functions take a locale and
/// time zone so tests are deterministic.
enum DeduplicateReviewCopy {
    static let restoredTitle = "Your earlier review was restored."
    static let settingsChanged = "Deduplicate settings changed since that review; groups may differ."
    static let savedTitle = "Pick up where you left off"
    static let resumeButtonTitle = "Scan and Restore Review"
    static let discardButtonTitle = "Discard Saved Review"

    private static let restoredFormat = "%@ across %@ from %@."
    private static let savedFormat = "%@ and %@ saved %@. Scanning again restores them for files that haven't changed. Nothing is moved to the Trash until you review and confirm."

    static func restoredBody(
        _ restoration: DeduplicateReviewRestoration,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var sentences = [
            formatted(
                restoredFormat,
                countPhrase(restoration.restoredDecisionCount, one: "1 choice", many: "%lld choices"),
                countPhrase(restoration.restoredGroupCount, one: "1 group", many: "%lld groups"),
                dateText(restoration.savedAt, locale: locale, timeZone: timeZone)
            )
        ]
        let changed = restoration.changedGroupCount
        if changed > 0 {
            sentences.append(countPhrase(
                changed,
                one: "1 group changed since then and needs another look.",
                many: "%lld groups changed since then and need another look."
            ))
        }
        let dropped = restoration.droppedDecisionCount
        if dropped > 0 {
            sentences.append(countPhrase(
                dropped,
                one: "1 file changed, so its choice was cleared.",
                many: "%lld files changed, so their choices were cleared."
            ))
        }
        return sentences.joined(separator: " ")
    }

    static func savedBody(
        _ snapshot: DeduplicateReviewSnapshot,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        formatted(
            savedFormat,
            countPhrase(snapshot.reviewedDecisionCount, one: "1 choice", many: "%lld choices"),
            countPhrase(snapshot.approvals.count, one: "1 reviewed group", many: "%lld reviewed groups"),
            dateText(snapshot.savedAt, locale: locale, timeZone: timeZone)
        )
    }

    /// One explicit key for a count of exactly 1, another for every other count.
    private static func countPhrase(_ count: Int, one: String, many: String) -> String {
        count == 1 ? localized(one) : formatted(many, count)
    }

    /// Month, day, hour and minute in the user's locale (for example "Nov 14, 10:13 PM").
    private static func dateText(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        date.formatted(
            Date.FormatStyle(locale: locale, timeZone: timeZone)
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
        )
    }

    private static func localized(_ key: String) -> String {
        String(localized: String.LocalizationValue(key), bundle: Bundle.module)
    }

    private static func formatted(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: localized(key), arguments: arguments)
    }
}
