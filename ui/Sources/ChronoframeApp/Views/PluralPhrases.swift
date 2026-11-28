import Foundation

/// Count-dependent phrases for views. A count of 1 chooses a complete singular
/// phrase ("1 frame", "Show this file") instead of "1 frames", and each phrase
/// is looked up whole so German can agree in case and number ("in 1 Kopie",
/// "von 1 Gruppe"). Zero stays plural. Phrases that carry a second count are
/// composed from two phrases so each count agrees on its own. The Run timeline
/// has its own set in `TimelinePlurals`.
enum PluralPhrases {
    // MARK: Noun phrases

    static func files(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 file", other: "%@ files", bundle: bundle)
    }

    static func folders(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 folder", other: "%@ folders", bundle: bundle)
    }

    static func frames(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 frame", other: "%@ frames", bundle: bundle)
    }

    static func copies(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 copy", other: "%@ copies", bundle: bundle)
    }

    static func months(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 month", other: "%@ months", bundle: bundle)
    }

    static func photosAndVideos(_ count: Int, locale: Locale = .current, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 photo or video", other: "%@ photos and videos", locale: locale, bundle: bundle)
    }

    static func sidecarFiles(_ count: Int, locale: Locale = .current, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 sidecar file", other: "%@ sidecar files", locale: locale, bundle: bundle)
    }

    static func sidecarFilesNotCopied(_ count: Int, locale: Locale = .current, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 sidecar file not copied", other: "%@ sidecar files not copied", locale: locale, bundle: bundle)
    }

    static func workers(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 worker", other: "%@ workers", bundle: bundle)
    }

    // MARK: History

    /// "3 reports and logs · 2 reusable folders."
    static func historySummary(reports: Int, folders: Int, bundle: Bundle = .module) -> String {
        let reportsPhrase = phrase(reports, one: "1 report or log", other: "%@ reports and logs", bundle: bundle)
        let foldersPhrase = phrase(folders, one: "1 reusable folder", other: "%@ reusable folders", bundle: bundle)
        return "\(reportsPhrase) · \(foldersPhrase)."
    }

    static func archiveOverview(frames frameCount: Int, copies copyCount: Int, bundle: Bundle = .module) -> String {
        String(
            localized: "Archive overview: \(String(frames(frameCount, bundle: bundle))) archived across \(String(copies(copyCount, bundle: bundle))).",
            bundle: bundle
        )
    }

    // MARK: Timelines

    /// `countPhrase` is a finished phrase such as `copies(3)` or
    /// `TimelinePlurals.plannedFiles(40)`.
    static func timelineSelectedValue(
        month: String,
        countPhrase: String,
        monthCount: Int,
        bundle: Bundle = .module
    ) -> String {
        String(
            localized: "Selected month: \(month), \(String(countPhrase)). Timeline contains \(String(months(monthCount, bundle: bundle))).",
            bundle: bundle
        )
    }

    static func timelineUnselectedValue(countPhrase: String, monthCount: Int, bundle: Bundle = .module) -> String {
        String(
            localized: "Timeline containing \(String(countPhrase)) \(String(TimelinePlurals.acrossMonths(monthCount, bundle: bundle))). Unselected.",
            bundle: bundle
        )
    }

    // MARK: Contact sheet

    static func contactSheetShowing(_ visible: Int, bundle: Bundle = .module) -> String {
        visible == 1
            ? String(localized: "Contact sheet showing 1 preview frame from the source.", bundle: bundle)
            : String(localized: "Contact sheet showing \(String(visible.formatted())) preview frames from the source.", bundle: bundle)
    }

    // MARK: Deduplicate

    static func groupsWillBeProcessed(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 group will be processed.", other: "%@ groups will be processed.", bundle: bundle)
    }

    static func unreviewedGroupsUntouched(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(
            count,
            one: "1 unreviewed group remains completely untouched.",
            other: "%@ unreviewed groups remain completely untouched.",
            bundle: bundle
        )
    }

    static func groupsReviewedLabel(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 group reviewed.", other: "%@ groups reviewed.", bundle: bundle)
    }

    static func groupsUntouchedLabel(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 group untouched.", other: "%@ groups untouched.", bundle: bundle)
    }

    /// "2 of 6 groups reviewed"; the noun follows the total.
    static func triageProgress(current: Int, total: Int, bundle: Bundle = .module) -> String {
        total == 1
            ? String(localized: "\(String(current.formatted())) of 1 group reviewed", bundle: bundle)
            : String(localized: "\(String(current.formatted())) of \(String(total.formatted())) groups reviewed", bundle: bundle)
    }

    // MARK: Free test batch

    static func showTheseFiles(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "Show this file", other: "Show these %@ files", bundle: bundle)
    }

    static func copyTheseFiles(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "Copy This File", other: "Copy These %@ Files", bundle: bundle)
    }

    // MARK: Photos import

    static func editedPhotosWillAlsoBeSaved(_ count: Int, locale: Locale = .current, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 edited photo will also be saved", other: "%@ edited photos will also be saved", locale: locale, bundle: bundle)
    }

    static func editedVideosNotIncluded(_ count: Int, locale: Locale = .current, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 edited video or Live Photo not included", other: "%@ edited videos and Live Photos not included", locale: locale, bundle: bundle)
    }

    // MARK: NAS

    static func foldersChecked(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 folder checked", other: "%@ folders checked", bundle: bundle)
    }

    static func photosAndVideos(count: Int, size: String, bundle: Bundle = .module) -> String {
        count == 1
            ? String(localized: "1 photo or video, \(String(size))", bundle: bundle)
            : String(localized: "\(String(count.formatted())) photos and videos, \(String(size))", bundle: bundle)
    }

    static func groupsOfIdenticalFiles(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(count, one: "1 group of identical files", other: "%@ groups of identical files", bundle: bundle)
    }

    /// "12 folders, 1 file" while a scan runs.
    static func scanProgress(folders folderCount: Int, files fileCount: Int, bundle: Bundle = .module) -> String {
        "\(folders(folderCount, bundle: bundle)), \(files(fileCount, bundle: bundle))"
    }

    // MARK: Preview review

    static func itemsNeedAttention(_ count: Int, bundle: Bundle = .module) -> String {
        phrase(
            count,
            one: "1 item needs attention. Originals stay untouched.",
            other: "%@ items need attention. Originals stay untouched.",
            bundle: bundle
        )
    }

    private static func phrase(_ count: Int, one: String, other: String, locale: Locale? = nil, bundle: Bundle) -> String {
        count == 1
            ? AppLocalization.string(one, bundle: bundle)
            : AppLocalization.format(other, count.formatted(.number.locale(locale ?? .current)), bundle: bundle)
    }
}
