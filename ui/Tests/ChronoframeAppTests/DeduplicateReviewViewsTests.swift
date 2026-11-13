import Foundation
import SwiftUI
import XCTest
@testable import ChronoframeApp
@testable import ChronoframeCore

@MainActor
final class DeduplicateReviewViewsTests: XCTestCase {
    private let savedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private var restoration: DeduplicateReviewRestoration {
        DeduplicateReviewRestoration(
            decisions: DedupeDecisions(byPath: [:]),
            approvedClusterIDs: [],
            focusClusterID: nil,
            restoredDecisionCount: 4,
            droppedDecisionCount: 1,
            restoredGroupCount: 2,
            changedGroupCount: 1,
            settingsChanged: true,
            savedAt: savedAt
        )
    }

    private var snapshot: DeduplicateReviewSnapshot {
        DeduplicateReviewSnapshot(
            folderPath: "/dest",
            savedAt: savedAt,
            configurationFingerprint: "fp",
            decisions: [],
            approvals: [DeduplicateSavedGroupApproval(groupKey: "k", memberCount: 2)],
            focusGroupKey: nil
        )
    }

    func testBannerAndCardExposeIdentifiers() {
        XCTAssertEqual(AccessibilityIdentifiers.dedupeRestoredBanner, "dedupe.restored.banner")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeRestoredBannerDismiss, "dedupe.restored.dismiss")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeSavedReviewResume, "dedupe.saved.resume")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeSavedReviewDiscard, "dedupe.saved.discard")
        for id in [
            AccessibilityIdentifiers.dedupeRestoredBanner,
            AccessibilityIdentifiers.dedupeRestoredBannerDismiss,
            AccessibilityIdentifiers.dedupeSavedReviewResume,
            AccessibilityIdentifiers.dedupeSavedReviewDiscard,
        ] {
            XCTAssertTrue(AccessibilityIdentifiers.all.contains(id), id)
        }

        let banner = DeduplicateRestoredReviewBanner(restoration: restoration, onDismiss: {})
        _ = banner.body
        let card = DeduplicateSavedReviewCard(snapshot: snapshot, resume: {}, discard: {})
        _ = card.body
    }

    func testCardButtonsCallClosures() {
        var resumed = 0
        var discarded = 0
        var dismissed = 0
        let card = DeduplicateSavedReviewCard(
            snapshot: snapshot,
            resume: { resumed += 1 },
            discard: { discarded += 1 }
        )
        let banner = DeduplicateRestoredReviewBanner(restoration: restoration, onDismiss: { dismissed += 1 })

        card.resume()
        XCTAssertEqual(resumed, 1)
        XCTAssertEqual(discarded, 0)
        card.discard()
        XCTAssertEqual(discarded, 1)
        XCTAssertEqual(resumed, 1)

        banner.onDismiss()
        XCTAssertEqual(dismissed, 1)

        // Both views build their bodies with the closures wired in.
        _ = card.body
        _ = banner.body
    }

    // MARK: - Vocabulary (C-01: "cluster" is "group")

    private func vocabularyFixtures() -> [DuplicateCluster] {
        func member(_ name: String, _ kind: MediaKind) -> PhotoCandidate {
            PhotoCandidate(path: "/dest/\(name)", size: 1, modificationTime: 0, mediaKind: kind)
        }
        return [
            DuplicateCluster(
                kind: .exactDuplicate,
                members: [member("a.jpg", .photo), member("b.jpg", .photo)],
                suggestedKeeperIDs: ["/dest/a.jpg"],
                bytesIfPruned: 1,
                annotation: ClusterAnnotation(confidence: .high, matchReason: MatchReason(kind: .exactDuplicate))
            ),
            DuplicateCluster(
                kind: .nearDuplicate,
                members: [member("c.mov", .video), member("d.mov", .video)],
                suggestedKeeperIDs: [],
                bytesIfPruned: 1,
                annotation: ClusterAnnotation(confidence: .medium, matchReason: MatchReason(kind: .nearDuplicate))
            ),
        ]
    }

    /// Text of every string literal on a non-comment line, with `\( … )`
    /// interpolations removed (they hold code such as `mediaNoun(cluster)`).
    private func literalTexts(inSource source: String) -> [String] {
        var results: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
            let chars = Array(line)
            var i = 0
            var current: String?
            while i < chars.count {
                let c = chars[i]
                if current == nil {
                    if c == "\"" { current = "" }
                    i += 1
                    continue
                }
                if c == "\\", i + 1 < chars.count {
                    if chars[i + 1] == "(" {
                        var depth = 0
                        i += 1
                        while i < chars.count {
                            if chars[i] == "(" { depth += 1 }
                            if chars[i] == ")" { depth -= 1; if depth == 0 { break } }
                            i += 1
                        }
                        i += 1
                        continue
                    }
                    current?.append(chars[i + 1])
                    i += 2
                    continue
                }
                if c == "\"" {
                    if let text = current { results.append(text) }
                    current = nil
                } else {
                    current?.append(c)
                }
                i += 1
            }
        }
        return results
    }

    func testNoVisibleDedupeStringSaysCluster() throws {
        // Helper strings the views expose.
        var strings: [String] = []
        let fixtures = vocabularyFixtures()
        let lanes = DeduplicateReviewLanes(clusters: fixtures, reviewedIDs: [])
        let reviewedAll = DeduplicateReviewLanes(clusters: fixtures, reviewedIDs: Set(fixtures.map(\.id)))
        strings += [lanes.safeText, lanes.checkText, lanes.doneText, reviewedAll.doneText].compactMap { $0 }
        strings += [
            TipCopy.AcceptSafeSuggestions.title,
            TipCopy.AcceptSafeSuggestions.message,
            TipCopy.DeduplicateWorkspace.title,
            TipCopy.DeduplicateWorkspace.message,
        ]
        let summary = DeduplicateCommitSummary(
            deletedCount: 2, failedCount: 1, bytesReclaimed: 10, receiptPath: nil, hardDelete: false
        )
        for copy in [DeduplicateView.completedStatusCopy(for: summary), DeduplicateView.revertedStatusCopy(for: summary)] {
            strings += [copy.message, copy.warning].compactMap { $0 }
        }
        strings += [
            DeduplicateView.trashCommitMessage(byteCount: 20_000_000_000, availableCapacity: 1_000),
            DeduplicateView.committingTitle(fileCount: 3),
            DeduplicateView.commitFooterTitle(fileCount: 3, hardDelete: false),
            DeduplicateView.commitFooterDetail(byteCount: 0, hardDelete: false),
        ]
        for cluster in fixtures {
            let member = try XCTUnwrap(cluster.members.first)
            strings += [
                DeduplicateAccessibilityText.memberCountPhrase(cluster),
                DeduplicateAccessibilityText.membersInGroupLabel(cluster),
                DeduplicateAccessibilityText.keepAllHelp(cluster),
                DeduplicateAccessibilityText.deleteAllHelp(cluster),
                DeduplicateAccessibilityText.selectedPreviewLabel(cluster),
                DeduplicateAccessibilityText.intentionallyDifferentNote(cluster),
                DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster),
                DeduplicateAccessibilityText.clusterRowValue(cluster: cluster, isApproved: false, recoverableBytes: 1),
                DeduplicateAccessibilityText.rapidTriageLabel(cluster: cluster, currentIndex: 0, totalCount: 2),
                DeduplicateAccessibilityText.rapidTriageValue(cluster: cluster, reclaimableBytes: 1),
                DeduplicateAccessibilityText.selectsForKeyboardActionsHint(member),
                DeduplicateAccessibilityText.selectsForComparisonHint(member),
                DeduplicateAccessibilityText.detailsLabel(member),
                DeduplicateAccessibilityText.focusActionName(member),
            ]
        }
        for string in strings {
            XCTAssertFalse(string.lowercased().contains("cluster"), "Visible string says cluster: \(string)")
        }

        // Literals in the Deduplicate views, tip copy and sidebar-visible text.
        let testFile = URL(fileURLWithPath: #filePath)
        let sources = testFile
            .deletingLastPathComponent()      // ChronoframeAppTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // ui
            .appendingPathComponent("Sources/ChronoframeApp")
        let dedupeDir = sources.appendingPathComponent("Views/Deduplicate")
        var files = try FileManager.default.contentsOfDirectory(at: dedupeDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        files.append(sources.appendingPathComponent("App/Tips.swift"))
        XCTAssertGreaterThan(files.count, 5)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for literal in literalTexts(inSource: source) where literal.lowercased().contains("cluster") {
                XCTFail("\(file.lastPathComponent) has a visible literal that says cluster: \(literal)")
            }
        }
    }
}
