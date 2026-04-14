import Foundation
import XCTest
@testable import ChronoframeAppCore

final class ModelAndServiceTests: XCTestCase {
    func testRunStatusMappingAndIssueRendering() {
        XCTAssertEqual(RunStatus(backendStatus: "dry_run_finished"), .dryRunFinished)
        XCTAssertEqual(RunStatus(backendStatus: "finished"), .finished)
        XCTAssertEqual(RunStatus(backendStatus: "nothing_to_copy"), .nothingToCopy)
        XCTAssertEqual(RunStatus(backendStatus: "cancelled"), .cancelled)
        XCTAssertEqual(RunStatus(backendStatus: "idle"), .idle)
        XCTAssertEqual(RunStatus(backendStatus: "mystery"), .failed)

        XCTAssertEqual(RunIssue(severity: .info, message: "Started").renderedLine, "ℹ Started")
        XCTAssertEqual(RunIssue(severity: .warning, message: "Slow disk").renderedLine, "⚠ Slow disk")
        XCTAssertEqual(RunIssue(severity: .error, message: "Copy failed").renderedLine, "ERROR: Copy failed")
    }

    func testPhaseAndSidebarMetadataAreNonEmpty() {
        for phase in RunPhase.allCases {
            XCTAssertFalse(phase.title.isEmpty)
            XCTAssertFalse(phase.runningTitle.isEmpty)
        }

        for destination in SidebarDestination.allCases {
            XCTAssertFalse(destination.title.isEmpty)
            XCTAssertFalse(destination.subtitle.isEmpty)
            XCTAssertFalse(destination.systemImage.isEmpty)
        }

        for kind in RunHistoryEntryKind.allCases {
            XCTAssertFalse(kind.title.isEmpty)
        }
    }

    func testOrganizerEngineErrorsExposeDescriptions() {
        let errors: [OrganizerEngineError] = [
            .backendUnavailable,
            .pythonUnavailable,
            .profileNotFound("travel"),
            .sourceDoesNotExist("/tmp/source"),
            .destinationMissing,
            .missingDependencies(["rich"]),
            .failedToLaunch("boom"),
            .invalidPreflight("bad input"),
            .invalidOutput("not json"),
        ]

        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty)
        }
    }

    @MainActor
    func testFinderServiceIgnoresEmptyPaths() {
        let service = FinderService()
        service.openPath("")
        service.revealInFinder("")
    }

    @MainActor
    func testFolderAccessServiceFallsBackForInvalidBookmark() {
        let service = FolderAccessService()
        let bookmark = FolderBookmark(key: "manual.source", path: "/tmp/fallback", data: Data([0x00, 0x01]))

        XCTAssertEqual(service.resolveBookmark(bookmark)?.path, "/tmp/fallback")
    }
}
