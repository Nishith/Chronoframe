#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import XCTest
@testable import ChronoframeApp

final class RunPreviewHeadlineTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    private func buckets(_ keys: [String]) -> [DateHistogramBucket] {
        keys.map { DateHistogramBucket(key: $0, plannedCount: 1) }
    }

    private func headline(
        planned: Int,
        keys: [String] = [],
        duplicates: Int = 0,
        already: Int = 0,
        review: PreviewReviewSummary = PreviewReviewSummary(),
        stale: Bool = false,
        locale: Locale? = nil
    ) -> RunPreviewHeadline {
        RunPreviewHeadline(
            metrics: RunMetrics(
                plannedCount: planned,
                alreadyInDestinationCount: already,
                duplicateCount: duplicates,
                dateHistogram: buckets(keys)
            ),
            review: review,
            isStale: stale,
            locale: locale ?? enUS
        )
    }

    // MARK: - Sentence

    func testSentenceWithDateSpan() {
        let value = headline(planned: 64_212, keys: ["2009-03", "2015-07", "2026-10"])
        XCTAssertEqual(
            value.sentence,
            "64,212 photos and videos will be copied, from Mar 2009 to Oct 2026. Nothing has been copied yet."
        )
    }

    func testSentenceSingleMonth() {
        let value = headline(planned: 12, keys: ["2009-03", "2009-03-15"])
        XCTAssertEqual(
            value.sentence,
            "12 photos and videos will be copied, all from Mar 2009. Nothing has been copied yet."
        )
    }

    func testSentenceOmitsSpanWhenKeysDoNotParse() {
        let value = headline(planned: 5, keys: ["Unknown"])
        XCTAssertEqual(value.sentence, "5 photos and videos will be copied. Nothing has been copied yet.")

        let empty = headline(planned: 5, keys: [])
        XCTAssertEqual(empty.sentence, "5 photos and videos will be copied. Nothing has been copied yet.")

        // Unparseable keys are skipped; the first and last that parse are used.
        let mixed = headline(planned: 5, keys: ["Unknown", "2010-02", "2012", "Unknown"])
        XCTAssertEqual(
            mixed.sentence,
            "5 photos and videos will be copied, from Feb 2010 to 2012. Nothing has been copied yet."
        )

        let yearOnly = headline(planned: 5, keys: ["2010", "2012"])
        XCTAssertEqual(
            yearOnly.sentence,
            "5 photos and videos will be copied, from 2010 to 2012. Nothing has been copied yet."
        )
    }

    func testSentenceSingular() {
        let value = headline(planned: 1, keys: ["2009-03"])
        XCTAssertEqual(
            value.sentence,
            "1 photo or video will be copied, all from Mar 2009. Nothing has been copied yet."
        )
    }

    func testSentenceNothingToCopy() {
        let value = headline(planned: 0, keys: ["2009-03"])
        XCTAssertEqual(
            value.sentence,
            "Everything here is already in your organized library. Nothing needs copying."
        )
    }

    func testSentenceStale() {
        let value = headline(planned: 42, keys: ["2009-03"], stale: true)
        XCTAssertEqual(
            value.sentence,
            "You changed some dates. Rebuild the preview so the copy matches your changes."
        )
        // Stale wins over the nothing-to-copy sentence too.
        XCTAssertEqual(
            headline(planned: 0, stale: true).sentence,
            "You changed some dates. Rebuild the preview so the copy matches your changes."
        )
    }

    // MARK: - Exceptions

    private var everyException: RunPreviewHeadline {
        headline(
            planned: 100,
            duplicates: 7,
            already: 29,
            review: PreviewReviewSummary(
                unknownDateCount: 3,
                lowConfidenceDateCount: 4,
                hashErrorCount: 2
            )
        )
    }

    func testExceptionsOnlyForNonZeroCountsInContractOrder() {
        let all = everyException.exceptions
        XCTAssertEqual(all.map(\.id), ["unknown", "unsure", "copies", "already", "unreadable"])
        XCTAssertEqual(all.map(\.count), [3, 4, 7, 29, 2])
        XCTAssertEqual(all.map(\.text), [
            "3 have no date and will go to the Unknown_Date folder unless you set one.",
            "4 have a date Chronoframe is unsure about.",
            "7 are exact copies of another file here and will be set aside in the Duplicate folder.",
            "29 are already in your organized library and will be skipped.",
            "2 could not be read and will be skipped.",
        ])
        XCTAssertTrue(all.allSatisfy { !$0.systemImage.isEmpty })

        XCTAssertTrue(headline(planned: 10).exceptions.isEmpty)

        let some = headline(
            planned: 10,
            duplicates: 1,
            review: PreviewReviewSummary(lowConfidenceDateCount: 2)
        )
        XCTAssertEqual(some.exceptions.map(\.id), ["unsure", "copies"])
    }

    func testExceptionSingularForms() {
        let value = headline(
            planned: 10,
            duplicates: 1,
            already: 1,
            review: PreviewReviewSummary(
                unknownDateCount: 1,
                lowConfidenceDateCount: 1,
                hashErrorCount: 1
            )
        )
        XCTAssertEqual(value.exceptions.map(\.text), [
            "1 has no date and will go to the Unknown_Date folder unless you set one.",
            "1 has a date Chronoframe is unsure about.",
            "1 is an exact copy of another file here and will be set aside in the Duplicate folder.",
            "1 is already in your organized library and will be skipped.",
            "1 could not be read and will be skipped.",
        ])
    }

    func testOnlyDateAndUnreadableExceptionsOpenReview() {
        let opens = Dictionary(uniqueKeysWithValues: everyException.exceptions.map { ($0.id, $0.opensReview) })
        XCTAssertEqual(opens, [
            "unknown": true,
            "unsure": true,
            "copies": false,
            "already": false,
            "unreadable": true,
        ])
    }

    func testCountsUseGroupingSeparators() {
        let value = headline(
            planned: 1_234_567,
            duplicates: 12_345,
            review: PreviewReviewSummary(unknownDateCount: 9_876)
        )
        XCTAssertTrue(value.sentence.hasPrefix("1,234,567 photos and videos"))
        XCTAssertTrue(value.exceptions.map(\.text).contains(where: { $0.hasPrefix("9,876 have no date") }))
        XCTAssertTrue(value.exceptions.map(\.text).contains(where: { $0.hasPrefix("12,345 are exact copies") }))

        let german = headline(planned: 64_212, locale: Locale(identifier: "de_DE"))
        XCTAssertTrue(german.sentence.hasPrefix("64.212 photos and videos"))
    }
}
