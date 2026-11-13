#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// Formats review-row dates on the calendar day Chronoframe will actually use.
///
/// `DateClassification.bucket` files by the UTC day unless an EXIF offset is known,
/// and filename dates are midnight UTC (`FilenameDateParser`), so formatting them in
/// the Mac's local zone shows the previous day for anyone west of UTC. Only a date the
/// user picked in the date picker is shown in their local zone, as it was entered.
enum PreviewReviewDateText {
    static func string(
        for date: Date,
        source: DateResolutionSource,
        bucketTimeZoneOffsetSeconds: Int? = nil,
        locale: Locale = .current
    ) -> String {
        guard let timeZone = timeZone(for: source, bucketTimeZoneOffsetSeconds: bucketTimeZoneOffsetSeconds) else {
            return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale))
        }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone))
    }

    /// `nil` means "the viewer's local zone".
    private static func timeZone(for source: DateResolutionSource, bucketTimeZoneOffsetSeconds: Int?) -> TimeZone? {
        if source == .userOverride {
            return nil
        }
        if source != .filename,
           let offset = bucketTimeZoneOffsetSeconds,
           let timeZone = TimeZone(secondsFromGMT: offset) {
            return timeZone
        }
        return TimeZone(secondsFromGMT: 0)
    }
}
