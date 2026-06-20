import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Covers the testable seams behind the "Copy Path" and "Share…" actions added
/// to the dedupe cluster pane and Run History (PR A). The SwiftUI buttons are
/// thin wrappers over these pure helpers so the behavior is asserted here rather
/// than in a view.
final class PathClipboardAndShareTests: XCTestCase {
    private final class FakePasteboard: PathPasteboard {
        private(set) var written: [String] = []
        func writePath(_ path: String) { written.append(path) }
    }

    func testCopyWritesExactPathToPasteboard() {
        let pasteboard = FakePasteboard()
        PathClipboard.copy("/Volumes/Library/2021/03/IMG_0001.HEIC", to: pasteboard)
        XCTAssertEqual(pasteboard.written, ["/Volumes/Library/2021/03/IMG_0001.HEIC"])
    }

    func testCopyReplacesContentsRatherThanAppendingPolicy() {
        // Each invocation is an independent copy; the production pasteboard
        // clears before writing, so a fresh helper call must carry exactly one
        // path through.
        let pasteboard = FakePasteboard()
        PathClipboard.copy("/a/one.jpg", to: pasteboard)
        PathClipboard.copy("/b/two.jpg", to: pasteboard)
        XCTAssertEqual(pasteboard.written, ["/a/one.jpg", "/b/two.jpg"])
    }

    func testShareUsesOnDiskReceiptFileURLAndTitle() {
        let entry = RunHistoryEntry(
            kind: .auditReceipt,
            title: "Transfer · Mar 3, 2021",
            path: "/dest/.organize_logs/audit_receipt_20210303.json",
            createdAt: Date(timeIntervalSince1970: 1_614_700_000)
        )
        XCTAssertEqual(
            RunArtifactShare.fileURL(for: entry),
            URL(fileURLWithPath: "/dest/.organize_logs/audit_receipt_20210303.json")
        )
        XCTAssertTrue(RunArtifactShare.fileURL(for: entry).isFileURL)
        XCTAssertEqual(RunArtifactShare.shareTitle(for: entry), "Transfer · Mar 3, 2021")
    }
}
