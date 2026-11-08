import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class NASReconnectProbeTests: XCTestCase {
    func testValidatedStartPathForSameLibrary() async {
        let record = nasTestRecord()
        let url = URL(fileURLWithPath: "/Volumes/photo/Photos", isDirectory: true)
        let recorded = record.lastObservation
        let path = await NASReconnectProbe.validatedStartPath(
            for: record,
            resolve: { _ in url },
            observe: { _ in recorded }
        )
        XCTAssertEqual(path, url.path)

        var remounted = recorded
        remounted.volume.mountPoint = "/Volumes/photo-1"
        let moved = remounted
        let remountedPath = await NASReconnectProbe.validatedStartPath(
            for: record,
            resolve: { _ in url },
            observe: { _ in moved }
        )
        XCTAssertEqual(remountedPath, url.path)
    }

    func testValidatedStartPathNilOnMismatch() async {
        let record = nasTestRecord()
        let url = URL(fileURLWithPath: "/Volumes/photo/Photos", isDirectory: true)
        var different = record.lastObservation
        different.rootFileID = 999
        let mismatch = different
        let mismatchPath = await NASReconnectProbe.validatedStartPath(for: record, resolve: { _ in url }, observe: { _ in mismatch })
        XCTAssertNil(mismatchPath)

        var ambiguous = record.lastObservation
        ambiguous.volume.serverHost = "other.local"
        let changedHost = ambiguous
        let ambiguousPath = await NASReconnectProbe.validatedStartPath(for: record, resolve: { _ in url }, observe: { _ in changedHost })
        XCTAssertNil(ambiguousPath, "An ambiguous share needs the user's confirmation, so it is not a trusted start path")

        let unresolved = await NASReconnectProbe.validatedStartPath(for: record, resolve: { _ in nil }, observe: { _ in mismatch })
        XCTAssertNil(unresolved)
        let unobserved = await NASReconnectProbe.validatedStartPath(for: record, resolve: { _ in url }, observe: { _ in nil })
        XCTAssertNil(unobserved)
    }

    @MainActor
    func testValidatedStartPathTimesOutWithoutBlockingMainActor() async {
        let record = nasTestRecord()
        let url = URL(fileURLWithPath: "/Volumes/photo/Photos", isDirectory: true)
        let recorded = record.lastObservation
        let start = Date()

        let probe = Task {
            await NASReconnectProbe.validatedStartPath(
                for: record,
                resolve: { _ in url },
                observe: { _ in
                    Thread.sleep(forTimeInterval: 5)
                    return recorded
                }
            )
        }

        var mainActorRan = false
        let mainTask = Task { @MainActor in mainActorRan = true }
        await mainTask.value
        XCTAssertTrue(mainActorRan)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0, "The main actor must stay free while the probe waits")

        let result = await probe.value
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.5, "The probe must give up at its timeout, not wait for the share")
    }
}
