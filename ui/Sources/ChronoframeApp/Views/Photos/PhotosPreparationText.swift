#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation

/// User-facing copy for Photos import preparation and resume. Pure functions so
/// the exact wording is unit-tested. Counts are decimal-formatted; the optional
/// `locale` / `timeZone` parameters exist so tests are deterministic.
enum PhotosPreparationText {
    static func progressLine(_ p: PhotosPreparationProgress, locale: Locale = .current) -> String {
        "Preparing \(count(p.completed, locale: locale)) of \(count(p.total, locale: locale))…"
    }

    static func failuresLine(_ failed: Int, locale: Locale = .current) -> String {
        if failed == 1 {
            return "1 item couldn't be read and will be skipped."
        }
        return "\(count(failed, locale: locale)) couldn't be read and will be skipped."
    }

    static func resumeBody(
        _ r: PhotosResumableImport,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        var style = Date.FormatStyle().month().day().hour().minute().locale(locale)
        style.timeZone = timeZone
        let date = r.interruptedAt.formatted(style)
        return "\(count(r.readyCount, locale: locale)) of \(count(r.totalCount, locale: locale)) items from Photos were prepared on \(date) and are ready to import. Your Photos library was not changed."
    }

    static func supersedeMessage(readyCount: Int, locale: Locale = .current) -> String {
        "Starting a new import discards the \(count(readyCount, locale: locale)) prepared items from the interrupted one. Your Photos library is not affected either way."
    }

    static let destinationMismatch =
        "This import was prepared for a different destination. Choose that destination again to resume, or discard it."

    static let waitingForCloud = "Downloading from iCloud…"

    private static func count(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
