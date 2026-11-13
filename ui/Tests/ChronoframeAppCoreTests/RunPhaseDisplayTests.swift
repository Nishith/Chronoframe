import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class RunPhaseDisplayTests: XCTestCase {
    func testEveryPhaseHasDisplayTitlesFromContract() {
        let expected: [RunPhase: (title: String, running: String)] = [
            .discovery: ("Find Files", "Finding files…"),
            .sourceHashing: ("Read Originals", "Reading your originals…"),
            .destinationIndexing: ("Check Destination", "Checking the destination…"),
            .classification: ("Sort by Date", "Sorting by date…"),
            .copy: ("Copy", "Copying files…"),
            .revert: ("Undo", "Undoing…"),
            .reorganize: ("Reorganize", "Reorganizing files…"),
        ]

        XCTAssertEqual(Set(RunPhase.allCases), Set(expected.keys))
        for phase in RunPhase.allCases {
            XCTAssertEqual(phase.displayTitle, expected[phase]?.title, "\(phase)")
            XCTAssertEqual(phase.displayRunningTitle, expected[phase]?.running, "\(phase)")
        }
    }

    func testDisplayTitlesContainNoBannedWord() {
        let banned = ["hash", "index", "transfer", "revert", "classif", "source"]
        for phase in RunPhase.allCases {
            for text in [phase.displayTitle, phase.displayRunningTitle] {
                for word in banned {
                    XCTAssertFalse(text.lowercased().contains(word), "\"\(text)\" contains \"\(word)\"")
                }
            }
        }
    }

    /// The command-line tool prints `title` and `runningTitle` (D-CLP-03), so
    /// the Core strings must not move when the app's display wording does.
    func testCoreTitlesAreUnchangedForTheCLI() {
        XCTAssertEqual(RunPhase.sourceHashing.title, "Hash Source")
        XCTAssertEqual(RunPhase.copy.title, "Transfer")
        XCTAssertEqual(RunPhase.sourceHashing.runningTitle, "Hashing source...")
        XCTAssertEqual(RunPhase.destinationIndexing.title, "Index Destination")
    }

    func testModeDisplayTitlesAvoidEngineVocabulary() {
        let titles = [RunMode.preview, .transfer, .revert, .reorganize].map(\.displayTitle)
        XCTAssertEqual(titles, ["Preview", "Copy", "Undo", "Reorganize"])
        for title in titles {
            let words = title.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init)
            for banned in ["transfer", "source", "revert", "hash", "index"] {
                XCTAssertFalse(words.contains(banned), "\(title) contains \(banned)")
            }
        }
    }

    func testCoreModeTitlesAreUnchangedForTheCLI() {
        XCTAssertEqual(RunMode.transfer.title, "Transfer")
        XCTAssertEqual(RunMode.revert.title, "Revert")
    }
}
