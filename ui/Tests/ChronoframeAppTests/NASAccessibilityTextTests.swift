#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import XCTest
@testable import ChronoframeApp

final class NASAccessibilityTextTests: XCTestCase {
    func testAccessibilityLabelsCoverEveryControl() {
        let identifiers = AccessibilityIdentifiers.NAS.all
        XCTAssertEqual(
            Set(identifiers),
            [
                "nas.chooseFolder", "nas.startAssessment", "nas.stop", "nas.reconnect", "nas.confirmIdentity",
                "nas.groupList", "nas.groupRow", "nas.loadPreview", "nas.keeperPicker", "nas.folderSummary",
                "nas.stateBanner",
            ]
        )
        XCTAssertEqual(Set(identifiers).count, identifiers.count, "NAS identifiers are unique")
        XCTAssertEqual(Set(NASAccessibilityText.controlLabels.keys), Set(identifiers), "Every control has a label, and only controls do")
        for identifier in identifiers {
            XCTAssertFalse(identifier.contains(" "))
            let label = NASAccessibilityText.controlLabels[identifier] ?? ""
            XCTAssertFalse(label.isEmpty, "\(identifier) needs a VoiceOver label")
        }
        // Each label starts with the control's visible title, so VoiceOver and Voice Control agree.
        let visibleTitles: [String: String] = [
            AccessibilityIdentifiers.NAS.chooseFolder: NASLibraryCopy.chooseButton,
            AccessibilityIdentifiers.NAS.startAssessment: NASLibraryCopy.startButton,
            AccessibilityIdentifiers.NAS.stop: NASLibraryCopy.stopButton,
            AccessibilityIdentifiers.NAS.reconnect: NASLibraryCopy.reconnectButton,
            AccessibilityIdentifiers.NAS.confirmIdentity: NASLibraryCopy.confirmButton,
            AccessibilityIdentifiers.NAS.loadPreview: NASLibraryCopy.loadPreviewButton,
        ]
        for (identifier, title) in visibleTitles {
            let label = NASAccessibilityText.controlLabels[identifier] ?? ""
            XCTAssertTrue(label.hasPrefix(title), "\(identifier) label \"\(label)\" must start with \"\(title)\"")
        }
        XCTAssertTrue(NASAccessibilityText.label(forIdentifier: AccessibilityIdentifiers.NAS.startAssessment).hasPrefix("Assess Library"))
        // The shared identifier table includes the NAS identifiers.
        for identifier in identifiers {
            XCTAssertTrue(AccessibilityIdentifiers.all.contains(identifier), identifier)
        }
    }

    func testGroupRowDescribesCopiesAndChoiceInPlainWords() {
        let group = NASExactGroup(digest: "d", size: 2_000_000, kind: .photo, memberRelativePaths: ["a/x.jpg", "b/x.jpg", "c/x.jpg"])
        let withoutChoice = NASAccessibilityText.groupRow(group: group, keeper: nil, isChoiceStale: false)
        XCTAssertTrue(withoutChoice.contains("3 identical copies"), withoutChoice)
        XCTAssertTrue(withoutChoice.contains("No choice yet"), withoutChoice)

        let withChoice = NASAccessibilityText.groupRow(group: group, keeper: "b/x.jpg", isChoiceStale: false)
        XCTAssertTrue(withChoice.contains("Keeper chosen: x.jpg"), withChoice)

        let stale = NASAccessibilityText.groupRow(group: group, keeper: "gone/x.jpg", isChoiceStale: true)
        XCTAssertTrue(stale.contains("no longer matches"), stale)
    }

    func testFolderSummaryIsSpokenWithoutSayingSpaceWasFreed() {
        let summary = NASScanSummary(
            generation: 1, mode: .exactOnly, startedAt: Date(timeIntervalSince1970: 1), finishedAt: nil,
            outcome: .complete,
            counts: NASScanCounts(directoriesAssessed: 12, mediaFiles: 340, mediaBytes: 10_000_000),
            ledger: NASByteLedger(), exactGroupCount: 4, redundantLogicalBytes: 8_000_000
        )
        let spoken = NASAccessibilityText.folderSummary(summary)
        XCTAssertTrue(spoken.contains("12 folders"), spoken)
        XCTAssertTrue(spoken.contains("340 photos and videos"), spoken)
        XCTAssertTrue(spoken.contains("4 groups"), spoken)
        XCTAssertTrue(spoken.contains("not space freed"), spoken)
    }

    func testBannerIsSpokenWithItsText() {
        let spoken = NASAccessibilityText.stateBanner(.waitingForNAS)
        XCTAssertEqual(spoken, NASLibraryCopy.bannerText(for: .waitingForNAS))
    }
}
