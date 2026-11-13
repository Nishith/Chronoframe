import ChronoframeCore
import XCTest
@testable import ChronoframeApp

final class PreviewReviewDateTextTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private var originalDefaultTimeZone: TimeZone!

    override func setUp() {
        super.setUp()
        originalDefaultTimeZone = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
    }

    override func tearDown() {
        NSTimeZone.default = originalDefaultTimeZone
        super.tearDown()
    }

    private func utcMidnight(_ iso: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: iso))
    }

    func testFilenameDateShowsItsUTCDayEvenWhenTheMacIsWestOfUTC() throws {
        let filenameDate = try utcMidnight("2019-07-14T00:00:00Z")

        XCTAssertEqual(
            PreviewReviewDateText.string(for: filenameDate, source: .filename, locale: enUS),
            "Jul 14, 2019"
        )
        // The naive local-zone format is the regression this guards against.
        var localCalendar = Calendar(identifier: .gregorian)
        localCalendar.timeZone = NSTimeZone.default
        XCTAssertEqual(localCalendar.component(.day, from: filenameDate), 13)
    }

    func testMetadataDateShowsTheDayInItsKnownOffset() throws {
        // 2026-01-01 02:00 +05:00 is 2025-12-31 21:00 UTC and 13:00 in Los Angeles.
        let instant = try XCTUnwrap(ISO8601DateFormatter().date(from: "2025-12-31T21:00:00Z"))

        XCTAssertEqual(
            PreviewReviewDateText.string(
                for: instant,
                source: .photoMetadata,
                bucketTimeZoneOffsetSeconds: 5 * 3600,
                locale: enUS
            ),
            "Jan 1, 2026"
        )
    }

    func testOffsetLessMetadataDateShowsTheUTCDayItBucketsInto() throws {
        let instant = try utcMidnight("2000-01-01T00:00:00Z")

        XCTAssertEqual(
            PreviewReviewDateText.string(for: instant, source: .photoMetadata, locale: enUS),
            "Jan 1, 2000"
        )
    }

    func testFilenameDateIgnoresAnyOffset() throws {
        let filenameDate = try utcMidnight("2019-07-14T00:00:00Z")

        XCTAssertEqual(
            PreviewReviewDateText.string(
                for: filenameDate,
                source: .filename,
                bucketTimeZoneOffsetSeconds: -8 * 3600,
                locale: enUS
            ),
            "Jul 14, 2019"
        )
    }

    func testUserPickedDateStaysInTheViewersLocalZone() throws {
        // Local midnight in Los Angeles, as a DatePicker would produce.
        let picked = try XCTUnwrap(ISO8601DateFormatter().date(from: "2019-07-14T07:00:00Z"))

        XCTAssertEqual(
            PreviewReviewDateText.string(for: picked, source: .userOverride, locale: enUS),
            "Jul 14, 2019"
        )
    }
}
