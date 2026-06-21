import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreMediaDateTests: XCTestCase {
    func testExtensionSetsAndSkipRulesRemainStable() {
        XCTAssertTrue(MediaLibraryRules.isPhotoFile(path: "/photos/test.jpg"))
        XCTAssertTrue(MediaLibraryRules.isPhotoFile(path: "/photos/test.HEIC"))
        XCTAssertTrue(MediaLibraryRules.isPhotoFile(path: "/photos/test.CR3"))
        XCTAssertTrue(MediaLibraryRules.isPhotoFile(path: "/photos/test.RW2"))
        XCTAssertTrue(MediaLibraryRules.isVideoFile(path: "/videos/test.mov"))
        XCTAssertTrue(MediaLibraryRules.isSupportedMediaFile(path: "/videos/test.mp4"))
        XCTAssertFalse(MediaLibraryRules.isSupportedMediaFile(path: "/docs/readme.txt"))
        XCTAssertTrue(MediaLibraryRules.shouldSkipDiscoveredFile(named: ".DS_Store"))
        XCTAssertTrue(MediaLibraryRules.shouldSkipDiscoveredFile(named: "profiles.yaml"))
        XCTAssertFalse(MediaLibraryRules.shouldSkipDiscoveredFile(named: "IMG_20240101_120000.jpg"))
    }

    /// Regression for review rec #2: `DeduplicatePairDetector` advertises
    /// `.cr3` (modern Canon) and `.rw2` (Panasonic Lumix) RAW formats,
    /// but discovery filters through `photoExtensions` first. If they
    /// were omitted from the photo set, those files would never become
    /// dedupe candidates and pair-as-unit handling would be broken for
    /// the most common modern Canon and all Lumix RAWs.
    func testPhotoExtensionsCoverModernCanonAndLumixRaw() {
        XCTAssertTrue(MediaLibraryRules.isPhotoFile(path: "/photos/IMG.CR3"))
        XCTAssertTrue(MediaLibraryRules.isPhotoFile(path: "/photos/IMG.cr3"))
        XCTAssertTrue(MediaLibraryRules.isPhotoFile(path: "/photos/P1000001.RW2"))
        XCTAssertTrue(MediaLibraryRules.isPhotoFile(path: "/photos/P1000001.rw2"))
        XCTAssertTrue(MediaLibraryRules.isSupportedMediaFile(path: "/photos/IMG.CR3"))
        XCTAssertTrue(MediaLibraryRules.isSupportedMediaFile(path: "/photos/P1000001.RW2"))
    }

    func testFilenameDateParserMatchesChronoframePatterns() {
        XCTAssertEqual(dayString(FilenameDateParser.parse(from: "/photos/IMG_20210417_120000.jpg")), "2021-04-17")
        XCTAssertEqual(dayString(FilenameDateParser.parse(from: "/photos/VID_20200101_235959.mp4")), "2020-01-01")
        XCTAssertEqual(dayString(FilenameDateParser.parse(from: "/photos/PANO_20190615_080000.jpg")), "2019-06-15")
        XCTAssertEqual(dayString(FilenameDateParser.parse(from: "/photos/BURST_20180312_143000.jpg")), "2018-03-12")
        XCTAssertEqual(dayString(FilenameDateParser.parse(from: "/photos/MVIMG_20170820_090000.jpg")), "2017-08-20")
        XCTAssertEqual(dayString(FilenameDateParser.parse(from: "/photos/20210101_120000.jpg")), "2021-01-01")
        XCTAssertEqual(dayString(FilenameDateParser.parse(from: "/photos/signal_20201225_photo.jpg")), "2020-12-25")
        XCTAssertEqual(dayString(FilenameDateParser.parse(from: "/photos/scan_19700101_001.jpg")), "1970-01-01")
        XCTAssertEqual(dayString(FilenameDateParser.parse(from: "/photos/export_20310101_001.jpg")), "2031-01-01")
    }

    func testFilenameDateParserRejectsInvalidAndOutOfRangeDates() {
        XCTAssertNil(FilenameDateParser.parse(from: "/photos/IMG_20211301_120000.jpg"))
        XCTAssertNil(FilenameDateParser.parse(from: "/photos/IMG_20210132_120000.jpg"))
        XCTAssertNil(FilenameDateParser.parse(from: "/photos/IMG_18990101_120000.jpg"))
        XCTAssertNil(FilenameDateParser.parse(from: "/photos/IMG_21010101_120000.jpg"))
        XCTAssertNil(FilenameDateParser.parse(from: "/photos/family_photo.jpg"))
        XCTAssertNil(FilenameDateParser.parse(from: "/photos/DSC_1234.jpg"))
    }

    func testDateClassificationUsesUnknownDateForNilAndOldYears() {
        XCTAssertEqual(DateClassification.bucket(for: nil), "Unknown_Date")
        XCTAssertEqual(DateClassification.bucket(for: makeDate("1899-12-31")), "Unknown_Date")
        XCTAssertEqual(DateClassification.bucket(for: makeDate("1970-01-01")), "1970-01-01")
        XCTAssertEqual(DateClassification.bucket(for: makeDate("2023-06-15")), "2023-06-15")
    }

    // MARK: - Date-bucketing boundaries (missing-test coverage)

    /// Filename dates land in the right day folder across year/month/leap-day
    /// rollovers — the time-of-day component must never bump the bucket.
    func testFilenameDateBucketingAcrossYearAndMonthBoundaries() {
        let cases: [(String, String)] = [
            ("/p/IMG_20231231_235959.jpg", "2023-12-31"), // last second of the year
            ("/p/IMG_20240101_000000.jpg", "2024-01-01"), // first second of the year
            ("/p/IMG_20240229_120000.jpg", "2024-02-29"), // valid leap day
            ("/p/IMG_20240301_000000.jpg", "2024-03-01"), // month rollover
        ]
        for (path, expected) in cases {
            XCTAssertEqual(
                DateClassification.bucket(for: FilenameDateParser.parse(from: path)),
                expected,
                "Filename \(path) should bucket to \(expected)"
            )
        }
        // 2023 is not a leap year — Feb 29 must be rejected, not rolled to Mar 1.
        XCTAssertNil(FilenameDateParser.parse(from: "/p/IMG_20230229_120000.jpg"))
    }

    /// `DateClassification.bucket` keys on the UTC calendar day. An instant at
    /// exactly UTC midnight belongs to the new day; one second earlier belongs
    /// to the previous day.
    func testDateBucketUsesUTCCalendarDayAtMidnight() {
        let utcMidnight = makeDate("2024-01-01") // 2024-01-01T00:00:00Z
        XCTAssertEqual(DateClassification.bucket(for: utcMidnight), "2024-01-01")
        XCTAssertEqual(DateClassification.bucket(for: utcMidnight.addingTimeInterval(-1)), "2023-12-31")
        XCTAssertEqual(DateClassification.bucket(for: utcMidnight.addingTimeInterval(-86_400)), "2023-12-31")
    }

    /// EXIF timestamps without an offset are read as UTC wall-clock, so a late
    /// evening shot keeps its own day rather than rolling forward.
    func testNoOffsetExifNearMidnightKeepsWallClockDay() {
        let lateNight = NativeMediaMetadataDateReader.parseImagePropertyDate("2023:12:31 23:59:00")
        XCTAssertEqual(DateClassification.bucket(for: lateNight), "2023-12-31")
        let earlyMorning = NativeMediaMetadataDateReader.parseImagePropertyDate("2024:01:01 00:30:00")
        XCTAssertEqual(DateClassification.bucket(for: earlyMorning), "2024-01-01")
    }

    /// When EXIF carries an explicit UTC offset, Chronoframe buckets by the
    /// photographer's **local calendar day**, not the UTC instant. A 02:00 shot
    /// at +05:00 (still "Jan 1" locally) is 21:00 the previous day in UTC but is
    /// filed under **Jan 1**; a 22:00 shot at -05:00 (still "Dec 31" locally) is
    /// the next UTC day but is filed under **Dec 31**. The resolved `date`
    /// remains the true UTC instant — only the folder day follows the offset.
    func testOffsetExifNearLocalMidnightBucketsByLocalDay() {
        let earlyLocalJan1 = NativeMediaMetadataDateReader.parseImagePropertyDateWithOffset("2024:01:01 02:00:00", offset: "+05:00")
        XCTAssertEqual(earlyLocalJan1?.bucketTimeZoneOffsetSeconds, 5 * 3600)
        XCTAssertEqual(
            DateClassification.bucket(for: earlyLocalJan1?.date, timeZoneOffsetSeconds: earlyLocalJan1?.bucketTimeZoneOffsetSeconds),
            "2024-01-01"
        )
        // The instant itself is the previous UTC day — sorting/clustering unaffected.
        XCTAssertEqual(dayString(earlyLocalJan1?.date), "2023-12-31")

        let lateLocalDec31 = NativeMediaMetadataDateReader.parseImagePropertyDateWithOffset("2023:12:31 22:00:00", offset: "-05:00")
        XCTAssertEqual(lateLocalDec31?.bucketTimeZoneOffsetSeconds, -5 * 3600)
        XCTAssertEqual(
            DateClassification.bucket(for: lateLocalDec31?.date, timeZoneOffsetSeconds: lateLocalDec31?.bucketTimeZoneOffsetSeconds),
            "2023-12-31"
        )
        XCTAssertEqual(dayString(lateLocalDec31?.date), "2024-01-01")

        // An offset shot away from midnight keeps its local day either way.
        let middayJan1 = NativeMediaMetadataDateReader.parseImagePropertyDateWithOffset("2024:01:01 12:00:00", offset: "+05:00")
        XCTAssertEqual(
            DateClassification.bucket(for: middayJan1?.date, timeZoneOffsetSeconds: middayJan1?.bucketTimeZoneOffsetSeconds),
            "2024-01-01"
        )
    }

    /// `bucket(timeZoneOffsetSeconds:)` files by the day in that offset's zone,
    /// while a `nil` offset keeps the historical UTC-day behavior byte-for-byte.
    func testDateBucketOffsetParameterMatchesLocalDay() {
        // 2023-12-31T21:00:00Z == 2024-01-01 02:00 at +05:00.
        let instant = makeDateTimeUTC("2023-12-31T21:00:00Z")
        XCTAssertEqual(DateClassification.bucket(for: instant), "2023-12-31")
        XCTAssertEqual(DateClassification.bucket(for: instant, timeZoneOffsetSeconds: 5 * 3600), "2024-01-01")
        XCTAssertEqual(DateClassification.bucket(for: instant, timeZoneOffsetSeconds: 0), "2023-12-31")
        // A malformed/absent offset falls back to UTC.
        XCTAssertEqual(DateClassification.bucket(for: instant, timeZoneOffsetSeconds: nil), "2023-12-31")
    }

    /// EXIF offset strings parse to signed seconds; malformed offsets yield nil
    /// so bucketing safely falls back to UTC.
    func testExifOffsetStringParsing() {
        XCTAssertEqual(NativeMediaMetadataDateReader.offsetSeconds(from: "+05:00"), 5 * 3600)
        XCTAssertEqual(NativeMediaMetadataDateReader.offsetSeconds(from: "-05:30"), -(5 * 3600 + 30 * 60))
        XCTAssertEqual(NativeMediaMetadataDateReader.offsetSeconds(from: "+0000"), 0)
        XCTAssertEqual(NativeMediaMetadataDateReader.offsetSeconds(from: "Z"), 0)
        XCTAssertNil(NativeMediaMetadataDateReader.offsetSeconds(from: ""))
        XCTAssertNil(NativeMediaMetadataDateReader.offsetSeconds(from: "garbage"))
        XCTAssertNil(NativeMediaMetadataDateReader.offsetSeconds(from: "+5:00"))
    }

    /// The resolver carries the EXIF offset through `ResolvedMediaDate` so the
    /// planner buckets by local day, while the resolved instant stays UTC.
    func testResolverCarriesExifOffsetForLocalDayBucketing() {
        let instant = makeDateTimeUTC("2023-12-31T21:00:00Z") // 02:00 Jan 1 at +05:00
        let reader = OffsetStubMetadataReader(
            resolved: PhotoMetadataDate(date: instant, bucketTimeZoneOffsetSeconds: 5 * 3600)
        )
        let resolver = FileDateResolver(metadataReader: reader)
        let resolved = resolver.resolveResolvedDate(for: "/photos/IMG_offset.jpg")

        XCTAssertEqual(resolved.date, instant, "Resolved instant must stay the true UTC instant")
        XCTAssertEqual(resolved.bucketTimeZoneOffsetSeconds, 5 * 3600)
        XCTAssertEqual(
            DateClassification.bucket(for: resolved.date, timeZoneOffsetSeconds: resolved.bucketTimeZoneOffsetSeconds),
            "2024-01-01"
        )
    }

    /// An offset-less photo metadata date carries no bucket offset, so it keeps
    /// UTC-day bucketing (no regression for the common case).
    func testResolverWithoutOffsetKeepsUtcDayBucketing() {
        let instant = makeDateTimeUTC("2023-12-31T23:30:00Z")
        let reader = OffsetStubMetadataReader(
            resolved: PhotoMetadataDate(date: instant, bucketTimeZoneOffsetSeconds: nil)
        )
        let resolver = FileDateResolver(metadataReader: reader)
        let resolved = resolver.resolveResolvedDate(for: "/photos/IMG_plain.jpg")

        XCTAssertNil(resolved.bucketTimeZoneOffsetSeconds)
        XCTAssertEqual(
            DateClassification.bucket(for: resolved.date, timeZoneOffsetSeconds: resolved.bucketTimeZoneOffsetSeconds),
            "2023-12-31"
        )
    }

    func testFileDateResolverUsesPhotoMetadataForPhotosBeforeFilenameFallback() {
        let reader = StubMetadataReader(
            photoDate: makeDate("2023-06-15"),
            creationDate: makeDate("2020-01-01"),
            modificationDate: makeDate("2024-01-01")
        )
        let resolver = FileDateResolver(metadataReader: reader)

        XCTAssertEqual(dayString(resolver.resolveDate(for: "/photos/IMG_20210501_120000.jpg")), "2023-06-15")
        XCTAssertEqual(reader.photoMetadataCallCount, 1)
    }

    func testResolvedDateReportsSourceAndConfidence() {
        let metadataReader = StubMetadataReader(
            photoDate: makeDate("2023-06-15"),
            creationDate: makeDate("2020-01-01"),
            modificationDate: makeDate("2024-01-01")
        )
        let metadataResult = FileDateResolver(metadataReader: metadataReader)
            .resolveResolvedDate(for: "/photos/IMG_20210501_120000.jpg")

        XCTAssertEqual(dayString(metadataResult.date), "2023-06-15")
        XCTAssertEqual(metadataResult.source, .photoMetadata)
        XCTAssertEqual(metadataResult.confidence, .high)

        let filenameReader = StubMetadataReader(
            photoDate: nil,
            creationDate: makeDate("2020-01-01"),
            modificationDate: makeDate("2024-01-01")
        )
        let filenameResult = FileDateResolver(metadataReader: filenameReader)
            .resolveResolvedDate(for: "/photos/IMG_20210501_120000.jpg")

        XCTAssertEqual(dayString(filenameResult.date), "2021-05-01")
        XCTAssertEqual(filenameResult.source, .filename)
        XCTAssertEqual(filenameResult.confidence, .medium)

        let filesystemResult = FileDateResolver(metadataReader: filenameReader)
            .resolveResolvedDate(for: "/photos/random_name.jpg")
        XCTAssertEqual(filesystemResult.source, .fileSystemCreation)
        XCTAssertEqual(filesystemResult.confidence, .low)
    }

    func testFileDateResolverUsesFilenameWhenMetadataUnavailable() {
        let reader = StubMetadataReader(
            photoDate: nil,
            creationDate: makeDate("2020-06-15"),
            modificationDate: makeDate("2024-01-01")
        )
        let resolver = FileDateResolver(metadataReader: reader)

        XCTAssertEqual(dayString(resolver.resolveDate(for: "/photos/IMG_20210501_120000.jpg")), "2021-05-01")
        XCTAssertEqual(reader.creationDateCallCount, 0)
    }

    func testFileDateResolverUsesCreationDateWhenFilenameFails() {
        let reader = StubMetadataReader(
            photoDate: nil,
            creationDate: makeDate("2020-06-15"),
            modificationDate: makeDate("2024-01-01")
        )
        let resolver = FileDateResolver(metadataReader: reader)

        XCTAssertEqual(dayString(resolver.resolveDate(for: "/photos/random_name.jpg")), "2020-06-15")
        XCTAssertEqual(reader.creationDateCallCount, 1)
    }

    func testFileDateResolverRejectsPreArchivalCreationDateAndFallsBackToModificationDate() {
        let reader = StubMetadataReader(
            photoDate: nil,
            creationDate: makeDate("1899-12-31"),
            modificationDate: makeDate("2024-01-01")
        )
        let resolver = FileDateResolver(metadataReader: reader)

        XCTAssertEqual(dayString(resolver.resolveDate(for: "/photos/random_name.jpg")), "2024-01-01")
        XCTAssertEqual(reader.creationDateCallCount, 1)
        XCTAssertEqual(reader.modificationDateCallCount, 1)
    }

    func testFileDateResolverSkipsPhotoMetadataLookupForVideos() {
        let reader = StubMetadataReader(
            photoDate: makeDate("2023-06-15"),
            creationDate: nil,
            modificationDate: makeDate("2024-01-01")
        )
        let resolver = FileDateResolver(metadataReader: reader)

        XCTAssertEqual(dayString(resolver.resolveDate(for: "/videos/IMG_20230615_120000.mov")), "2023-06-15")
        XCTAssertEqual(reader.photoMetadataCallCount, 0)
    }

    // MARK: - Complete fallback chain coverage

    /// All metadata sources are unavailable → resolver returns nil → bucket = Unknown_Date.
    func testFileDateResolverReturnsNilWhenAllSourcesUnavailable() {
        let reader = StubMetadataReader(
            photoDate: nil,
            creationDate: nil,
            modificationDate: nil
        )
        let resolver = FileDateResolver(metadataReader: reader)
        let result = resolver.resolveDate(for: "/photos/DSC_4321.jpg")

        XCTAssertNil(result, "Expected nil when no date source is available")
        XCTAssertEqual(DateClassification.bucket(for: result), "Unknown_Date")
    }

    /// Modification date is also outside the archival range → resolver returns nil.
    func testFileDateResolverReturnsNilWhenModificationDateIsAlsoPreArchival() {
        let reader = StubMetadataReader(
            photoDate: nil,
            creationDate: makeDate("1899-12-31"),
            modificationDate: makeDate("1899-12-31")
        )
        let resolver = FileDateResolver(metadataReader: reader)
        let result = resolver.resolveDate(for: "/photos/no_date.jpg")

        XCTAssertNil(result)
        XCTAssertEqual(DateClassification.bucket(for: result), "Unknown_Date")
    }

    /// Verifies the full priority order on a photo: EXIF > filename > creation > mtime.
    /// Removing higher-priority sources one by one should fall through to the next.
    func testFileDateResolverFullFallbackOrderForPhoto() {
        // 1. EXIF beats filename.
        let r1 = StubMetadataReader(photoDate: makeDate("2022-03-01"), creationDate: makeDate("2020-01-01"), modificationDate: makeDate("2019-01-01"))
        XCTAssertEqual(dayString(FileDateResolver(metadataReader: r1).resolveDate(for: "/photos/IMG_20210101_120000.jpg")), "2022-03-01")

        // 2. No EXIF → filename wins over creation date.
        let r2 = StubMetadataReader(photoDate: nil, creationDate: makeDate("2020-01-01"), modificationDate: makeDate("2019-01-01"))
        XCTAssertEqual(dayString(FileDateResolver(metadataReader: r2).resolveDate(for: "/photos/IMG_20210101_120000.jpg")), "2021-01-01")

        // 3. No EXIF, no filename date → creation date.
        let r3 = StubMetadataReader(photoDate: nil, creationDate: makeDate("2020-01-01"), modificationDate: makeDate("2019-01-01"))
        XCTAssertEqual(dayString(FileDateResolver(metadataReader: r3).resolveDate(for: "/photos/DSC_4321.jpg")), "2020-01-01")

        // 4. No EXIF, no filename, pre-archival creation → mtime.
        let r4 = StubMetadataReader(photoDate: nil, creationDate: makeDate("1899-12-31"), modificationDate: makeDate("2019-06-15"))
        XCTAssertEqual(dayString(FileDateResolver(metadataReader: r4).resolveDate(for: "/photos/DSC_4321.jpg")), "2019-06-15")

        // 5. All unavailable/pre-archival → nil → Unknown_Date.
        let r5 = StubMetadataReader(photoDate: nil, creationDate: makeDate("1899-12-31"), modificationDate: makeDate("1899-12-31"))
        XCTAssertNil(FileDateResolver(metadataReader: r5).resolveDate(for: "/photos/DSC_4321.jpg"))
    }

    /// Video files should NOT consult EXIF metadata (expensive + unreliable for video).
    func testFileDateResolverDoesNotCallPhotoMetadataForMp4() {
        let reader = StubMetadataReader(
            photoDate: makeDate("2023-01-01"),
            creationDate: nil,
            modificationDate: makeDate("2021-01-01")
        )
        let resolver = FileDateResolver(metadataReader: reader)
        _ = resolver.resolveDate(for: "/videos/clip.mp4")

        XCTAssertEqual(reader.photoMetadataCallCount, 0, "EXIF lookup must not be invoked for .mp4 files")
    }

    private func makeDate(_ rawValue: String) -> Date {
        Self.dayFormatter.date(from: rawValue)!
    }

    private func makeDateTimeUTC(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso8601)!
    }

    private func dayString(_ date: Date?) -> String? {
        guard let date else { return nil }
        return Self.dayFormatter.string(from: date)
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private final class StubMetadataReader: MediaMetadataDateReading, @unchecked Sendable {
    var photoDate: Date?
    var creationDate: Date?
    var modificationDate: Date?
    private(set) var photoMetadataCallCount = 0
    private(set) var creationDateCallCount = 0
    private(set) var modificationDateCallCount = 0

    init(photoDate: Date?, creationDate: Date?, modificationDate: Date?) {
        self.photoDate = photoDate
        self.creationDate = creationDate
        self.modificationDate = modificationDate
    }

    func photoMetadataDate(at url: URL) -> Date? {
        photoMetadataCallCount += 1
        return photoDate
    }

    func fileSystemCreationDate(at url: URL) -> Date? {
        creationDateCallCount += 1
        return creationDate
    }

    func fileSystemModificationDate(at url: URL) -> Date? {
        modificationDateCallCount += 1
        return modificationDate
    }
}

/// Stub reader that exercises the offset-aware metadata path directly, so the
/// resolver-plumbing tests don't need a real on-disk image with EXIF.
private final class OffsetStubMetadataReader: MediaMetadataDateReading, @unchecked Sendable {
    let resolved: PhotoMetadataDate?

    init(resolved: PhotoMetadataDate?) {
        self.resolved = resolved
    }

    func photoMetadataDate(at url: URL) -> Date? { resolved?.date }
    func photoMetadataResolvedDate(at url: URL) -> PhotoMetadataDate? { resolved }
    func fileSystemCreationDate(at url: URL) -> Date? { nil }
    func fileSystemModificationDate(at url: URL) -> Date? { nil }
}
