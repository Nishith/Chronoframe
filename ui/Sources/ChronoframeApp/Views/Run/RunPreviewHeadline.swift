import Foundation
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif

/// The one-sentence answer shown when a preview finishes, plus the short list of
/// exceptions behind it. Pure: built only from `RunMetrics` and
/// `PreviewReviewSummary` (D-CLP-14).
struct RunPreviewHeadline: Equatable {
    struct Exception: Identifiable, Equatable {
        let id: String
        let count: Int
        let text: String
        let systemImage: String
        let opensReview: Bool
    }

    let sentence: String
    let exceptions: [Exception]

    init(
        metrics: RunMetrics,
        review: PreviewReviewSummary,
        isStale: Bool,
        locale: Locale = .current,
        localizationBundle: Bundle = .module
    ) {
        func number(_ value: Int) -> String {
            value.formatted(.number.locale(locale))
        }

        if isStale {
            sentence = String(localized: "You changed some dates. Rebuild the preview so the copy matches your changes.", bundle: localizationBundle)
        } else if metrics.plannedCount == 0 {
            sentence = String(localized: "Everything here is already in your organized library. Nothing needs copying.", bundle: localizationBundle)
        } else {
            let planned = metrics.plannedCount
            let sidecars = min(max(0, metrics.plannedCompanionCount), planned)
            let span = Self.span(from: metrics.dateHistogram, locale: locale, localizationBundle: localizationBundle)
            if sidecars > 0 {
                sentence = String(
                    format: AppLocalization.string("%1$@, %2$@ will be copied%3$@. Nothing has been copied yet.", bundle: localizationBundle),
                    PluralPhrases.photosAndVideos(planned - sidecars, locale: locale, bundle: localizationBundle),
                    PluralPhrases.sidecarFiles(sidecars, locale: locale, bundle: localizationBundle),
                    span
                )
            } else {
                let subject = planned == 1 ? String(localized: "1 photo or video", bundle: localizationBundle) : String(localized: "\(String(number(planned))) photos and videos", bundle: localizationBundle)
                sentence = String(localized: "\(String(subject)) will be copied\(String(span)). Nothing has been copied yet.", bundle: localizationBundle)
            }
        }

        var found: [Exception] = []
        if review.unknownDateCount > 0 {
            let n = review.unknownDateCount
            found.append(Exception(
                id: "unknown",
                count: n,
                text: n == 1
                    ? String(localized: "1 has no date and will go to the Unknown_Date folder unless you set one.", bundle: localizationBundle)
                    : String(localized: "\(number(n)) have no date and will go to the Unknown_Date folder unless you set one.", bundle: localizationBundle),
                systemImage: "calendar.badge.exclamationmark",
                opensReview: true
            ))
        }
        if review.lowConfidenceDateCount > 0 {
            let n = review.lowConfidenceDateCount
            found.append(Exception(
                id: "unsure",
                count: n,
                text: n == 1
                    ? String(localized: "1 has a date Chronoframe is unsure about.", bundle: localizationBundle)
                    : String(localized: "\(number(n)) have a date Chronoframe is unsure about.", bundle: localizationBundle),
                systemImage: "questionmark.circle",
                opensReview: true
            ))
        }
        if metrics.duplicateCount > 0 {
            let n = metrics.duplicateCount
            found.append(Exception(
                id: "copies",
                count: n,
                text: n == 1
                    ? String(localized: "1 is an exact copy of another file here and will be set aside in the Duplicate folder.", bundle: localizationBundle)
                    : String(localized: "\(number(n)) are exact copies of another file here and will be set aside in the Duplicate folder.", bundle: localizationBundle),
                systemImage: "doc.on.doc",
                opensReview: false
            ))
        }
        if metrics.alreadyInDestinationCount > 0 {
            let n = metrics.alreadyInDestinationCount
            found.append(Exception(
                id: "already",
                count: n,
                text: n == 1
                    ? String(localized: "1 is already in your organized library and will be skipped.", bundle: localizationBundle)
                    : String(localized: "\(number(n)) are already in your organized library and will be skipped.", bundle: localizationBundle),
                systemImage: "checkmark.circle",
                opensReview: false
            ))
        }
        if review.hashErrorCount > 0 {
            let n = review.hashErrorCount
            found.append(Exception(
                id: "unreadable",
                count: n,
                text: String(localized: "\(String(number(n))) could not be read and will be skipped.", bundle: localizationBundle),
                systemImage: "exclamationmark.triangle",
                opensReview: true
            ))
        }
        if metrics.unresolvedCompanionCount > 0 {
            found.append(Exception(
                id: "sidecarsNotCopied",
                count: metrics.unresolvedCompanionCount,
                text: PluralPhrases.sidecarFilesNotCopied(metrics.unresolvedCompanionCount, locale: locale, bundle: localizationBundle),
                systemImage: "exclamationmark.circle",
                opensReview: false
            ))
        }
        exceptions = found
    }

    // MARK: - Date span

    private struct ParsedKey {
        let year: Int
        let month: Int?
    }

    /// `yyyy`, `yyyy-MM` or `yyyy-MM-dd`; anything else (for example "Unknown") is nil.
    private static func parse(_ key: String) -> ParsedKey? {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        guard parts[0].count == 4, parts[0].allSatisfy(\.isASCIIDigit), let year = Int(parts[0]) else {
            return nil
        }
        if parts.count == 1 { return ParsedKey(year: year, month: nil) }
        guard parts[1].count == 2, parts[1].allSatisfy(\.isASCIIDigit),
              let month = Int(parts[1]), (1...12).contains(month) else {
            return nil
        }
        if parts.count == 3 {
            guard parts[2].count == 2, parts[2].allSatisfy(\.isASCIIDigit),
                  let day = Int(parts[2]), (1...31).contains(day) else {
                return nil
            }
        }
        return ParsedKey(year: year, month: month)
    }

    private static func label(for key: ParsedKey, locale: Locale) -> String {
        guard let month = key.month else { return String(key.year) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        var components = DateComponents()
        components.year = key.year
        components.month = month
        components.day = 1
        components.hour = 12
        guard let date = calendar.date(from: components) else {
            return "\(month)/\(key.year)"
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMMyyyy")
        return formatter.string(from: date)
    }

    private static func span(from buckets: [DateHistogramBucket], locale: Locale, localizationBundle: Bundle) -> String {
        let parsed = buckets.compactMap { parse($0.key) }
        guard let first = parsed.first, let last = parsed.last else { return "" }
        let firstLabel = label(for: first, locale: locale)
        let lastLabel = label(for: last, locale: locale)
        return firstLabel == lastLabel ? String(localized: ", all from \(String(firstLabel))", bundle: localizationBundle) : String(localized: ", from \(String(firstLabel)) to \(String(lastLabel))", bundle: localizationBundle)
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
}
