#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation

/// User-facing copy for Photos import preparation and resume. Pure functions so
/// the exact wording is unit-tested. Counts are decimal-formatted; the optional
/// `locale` / `timeZone` parameters exist so tests are deterministic.
enum PhotosPreparationText {
    static func progressLine(_ p: PhotosPreparationProgress, locale: Locale = .current) -> String {
        String(localized: "Preparing \(String(count(p.completed, locale: locale))) of \(String(count(p.total, locale: locale)))…", bundle: .module)
    }

    static func failuresLine(_ failed: Int, locale: Locale = .current) -> String {
        if failed == 1 {
            return String(localized: "1 item couldn't be read and will be skipped.", bundle: .module)
        }
        return String(localized: "\(String(count(failed, locale: locale))) couldn't be read and will be skipped.", bundle: .module)
    }

    static func resumeBody(
        _ r: PhotosResumableImport,
        locale: Locale = .current,
        timeZone: TimeZone = .current,
        bundle: Bundle = .module
    ) -> String {
        var style = Date.FormatStyle().month().day().hour().minute().locale(locale)
        style.timeZone = timeZone
        let date = r.interruptedAt.formatted(style)
        if r.totalCount == 1 {
            return String(localized: "\(String(count(r.readyCount, locale: locale))) of 1 item from Photos was prepared on \(String(date)) and is ready to import. Your Photos library was not changed.", bundle: bundle)
        }
        return String(localized: "\(String(count(r.readyCount, locale: locale))) of \(String(count(r.totalCount, locale: locale))) items from Photos were prepared on \(String(date)) and are ready to import. Your Photos library was not changed.", bundle: bundle)
    }

    static func supersedeMessage(readyCount: Int, locale: Locale = .current, bundle: Bundle = .module) -> String {
        if readyCount == 1 {
            return String(localized: "Starting a new import discards the prepared item from the interrupted one. Your Photos library is not affected either way.", bundle: bundle)
        }
        return String(localized: "Starting a new import discards the \(String(count(readyCount, locale: locale))) prepared items from the interrupted one. Your Photos library is not affected either way.", bundle: bundle)
    }

    static let destinationMismatch =
        String(localized: "This import was prepared for a different destination. Choose that destination again to resume, or discard it.", bundle: .module)

    static let waitingForCloud = String(localized: "Downloading from iCloud…", bundle: .module)

    private static func count(_ value: Int, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = locale
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
