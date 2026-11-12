#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import XCTest
@testable import ChronoframeApp

final class RunWorkspaceModelTests: XCTestCase {
    func testPreviewReviewStateComputesTransferReadinessAndIssueSummary() {
        let model = RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .dryRunFinished,
                currentMode: .preview,
                currentTaskTitle: "Preview complete",
                currentPhase: .classification,
                progress: 1,
                metrics: RunMetrics(
                    discoveredCount: 84,
                    plannedCount: 42,
                    alreadyInDestinationCount: 29,
                    duplicateCount: 7,
                    hashErrorCount: 1,
                    copiedCount: 0,
                    failedCount: 0,
                    errorCount: 1
                ),
                summary: RunSummary(
                    status: .dryRunFinished,
                    title: "Preview complete",
                    metrics: RunMetrics(plannedCount: 42),
                    artifacts: RunArtifactPaths(destinationRoot: "/Volumes/Archive")
                ),
                lastErrorMessage: nil,
                warningCount: 1,
                errorCount: 1,
                issueCount: 1,
                logEntries: [
                    RunWorkspaceLogLine(id: 1, text: "WARNING: review metadata"),
                    RunWorkspaceLogLine(id: 2, text: "ERROR: hashing failed"),
                ],
                historyDestinationRoot: "/Volumes/Archive",
                currentSourceRoot: "/Volumes/Ingest",
                canStartRun: true
            )
        )

        XCTAssertEqual(model.heroState.badgeTitle, "Preview ready")
        XCTAssertTrue(model.showsPreviewReview)
        XCTAssertTrue(model.canStartTransferFromPreview)
        XCTAssertEqual(model.issueSummaryValue, "1 warning, 1 error, 1 other problem")
        XCTAssertEqual(model.tabTitle(.issues), "Problems (2)")
        XCTAssertEqual(model.sourceSummaryValue, "/Volumes/Ingest")
    }

    func testFailedStateRoutesToIssuesAndFormatsArtifactsFallback() {
        let model = RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .failed,
                currentMode: .transfer,
                currentTaskTitle: "Failed",
                currentPhase: .copy,
                progress: 0.5,
                metrics: RunMetrics(failedCount: 3, errorCount: 2),
                summary: nil,
                lastErrorMessage: "Disk became unavailable",
                warningCount: 0,
                errorCount: 2,
                issueCount: 3,
                logEntries: [
                    RunWorkspaceLogLine(id: 1, text: "ERROR: disk unavailable"),
                ],
                historyDestinationRoot: "/Volumes/Fallback",
                currentSourceRoot: "",
                canStartRun: true
            )
        )

        XCTAssertEqual(model.heroState.primaryAction, .showIssues)
        XCTAssertEqual(model.heroState.message, "Disk became unavailable")
        XCTAssertEqual(model.destinationSummaryValue, "/Volumes/Fallback")
        XCTAssertEqual(model.sourceSummaryValue, "Your folders will appear here once you choose them.")
        XCTAssertEqual(model.issueEntries.count, 1)
        XCTAssertEqual(model.issueTone, .danger)
    }

    func testRunningTransferFormatsVisibleProgressDetails() {
        let model = RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .running,
                currentMode: .transfer,
                currentTaskTitle: "Copying files...",
                currentPhase: .copy,
                progress: 0.85,
                metrics: RunMetrics(
                    plannedCount: 8_271,
                    copiedCount: 7_064,
                    bytesCopied: 1_500_000,
                    bytesTotal: 3_000_000,
                    speedMBps: 12.3,
                    etaSeconds: 95
                ),
                summary: nil,
                lastErrorMessage: nil,
                warningCount: 0,
                errorCount: 0,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "/Volumes/Archive",
                currentSourceRoot: "/Volumes/Ingest",
                canStartRun: true
            )
        )

        XCTAssertTrue(model.showsCopyProgressDetails)
        XCTAssertEqual(model.fileProgressSummaryValue, "7,064 of 8,271 files · 85%")
        XCTAssertEqual(model.throughputSummaryValue, "12.3 MB/s · 1m 35s")
        XCTAssertNotEqual(model.byteProgressSummaryValue, "Measuring")
    }

    func testStalePreviewReviewDisablesTransfer() {
        let model = RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .dryRunFinished,
                currentMode: .preview,
                currentTaskTitle: "Preview complete",
                currentPhase: .classification,
                progress: 1,
                metrics: RunMetrics(plannedCount: 3),
                summary: nil,
                lastErrorMessage: nil,
                warningCount: 0,
                errorCount: 0,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "/Volumes/Archive",
                currentSourceRoot: "/Volumes/Ingest",
                canStartRun: true,
                previewReviewIsStale: true,
                previewReviewSummary: PreviewReviewSummary(totalCount: 3, readyCount: 3),
                previewReviewPath: "/Volumes/Archive/.organize_logs/preview_review.jsonl"
            )
        )

        XCTAssertFalse(model.canStartTransferFromPreview)
        XCTAssertTrue(model.previewHeadline.sentence.contains("Rebuild the preview"))
        XCTAssertEqual(model.tabTitle(.review), "Review")
    }

    // MARK: - Plain copy (C-09)

    private struct HeroRow {
        let label: String
        let status: RunStatus
        let mode: RunMode?
        let canStart: Bool
        let title: String
        let message: String
        let badge: String
    }

    private func heroModel(
        status: RunStatus,
        mode: RunMode? = nil,
        canStart: Bool = true,
        copied: Int = 0,
        planned: Int = 0,
        lastError: String? = nil
    ) -> RunWorkspaceModel {
        RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: status,
                currentMode: mode,
                currentTaskTitle: "",
                currentPhase: nil,
                progress: 0,
                metrics: RunMetrics(plannedCount: planned, copiedCount: copied),
                summary: nil,
                lastErrorMessage: lastError,
                warningCount: 0,
                errorCount: 0,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "",
                currentSourceRoot: "",
                canStartRun: canStart
            )
        )
    }

    func testHeroCopyMatchesContractForEveryStatus() {
        let rows: [HeroRow] = [
            HeroRow(label: "idle can start", status: .idle, mode: nil, canStart: true,
                    title: "Preview the plan first",
                    message: "A preview copies nothing. It shows where every photo and video would go, so you can check before copying.",
                    badge: "Not started"),
            HeroRow(label: "idle cannot", status: .idle, mode: nil, canStart: false,
                    title: "Choose your folders first",
                    message: "Add the folders to organize and a destination, then come back here to preview and copy.",
                    badge: "Not started"),
            HeroRow(label: "preflighting", status: .preflighting, mode: nil, canStart: true,
                    title: "Getting ready",
                    message: "Chronoframe is checking your folders before it starts.",
                    badge: "Preparing"),
            HeroRow(label: "running preview", status: .running, mode: .preview, canStart: true,
                    title: "Building the preview",
                    message: "You can keep using your Mac. Nothing is being copied.",
                    badge: "Previewing"),
            HeroRow(label: "running transfer", status: .running, mode: .transfer, canStart: true,
                    title: "Copying your photos",
                    message: "You can keep using your Mac. Originals are only read, never changed.",
                    badge: "Copying"),
            HeroRow(label: "finished", status: .finished, mode: nil, canStart: true,
                    title: "Copy complete",
                    message: "64,212 photos and videos are in your organized library. Your originals were not changed.",
                    badge: "Done"),
            HeroRow(label: "nothingToCopy", status: .nothingToCopy, mode: nil, canStart: true,
                    title: "Already up to date",
                    message: "Everything in these folders is already in your organized library. Nothing was copied.",
                    badge: "Up to date"),
            HeroRow(label: "cancelled", status: .cancelled, mode: nil, canStart: true,
                    title: "Stopped",
                    message: "Chronoframe stopped before finishing. Files already copied stay in place and your originals were not changed. Preview again when you are ready.",
                    badge: "Stopped"),
            HeroRow(label: "failed default", status: .failed, mode: nil, canStart: true,
                    title: "Something needs attention",
                    message: "Chronoframe could not finish. Your originals were not changed. Check that both folders are available, then try again.",
                    badge: "Needs attention"),
            HeroRow(label: "reverted", status: .reverted, mode: nil, canStart: true,
                    title: "Undo complete",
                    message: "Chronoframe removed the copies listed in that receipt. Copies changed since then were kept.",
                    badge: "Undone"),
            HeroRow(label: "revertEmpty", status: .revertEmpty, mode: nil, canStart: true,
                    title: "Nothing to undo",
                    message: "That receipt lists no copies.",
                    badge: "Empty"),
            HeroRow(label: "reorganized", status: .reorganized, mode: nil, canStart: true,
                    title: "Layout updated",
                    message: "Chronoframe moved the files in your organized library into the new folder layout.",
                    badge: "Updated"),
            HeroRow(label: "nothingToReorganize", status: .nothingToReorganize, mode: nil, canStart: true,
                    title: "Layout already matches",
                    message: "Every file is already in the chosen layout. Nothing was moved.",
                    badge: "Up to date"),
        ]
        for row in rows {
            let model = heroModel(status: row.status, mode: row.mode, canStart: row.canStart, copied: 64_212)
            let hero = model.heroState
            XCTAssertEqual(hero.title, row.title, row.label)
            XCTAssertEqual(hero.message, row.message, row.label)
            XCTAssertEqual(hero.badgeTitle, row.badge, row.label)
        }

        // dryRunFinished: the message is the headline sentence.
        let preview = heroModel(status: .dryRunFinished, mode: .preview, planned: 3)
        XCTAssertEqual(preview.heroState.title, "Preview ready")
        XCTAssertEqual(preview.heroState.message, preview.previewHeadline.sentence)
        XCTAssertEqual(preview.heroState.badgeTitle, "Preview ready")

        // finished: singular form.
        XCTAssertEqual(
            heroModel(status: .finished, copied: 1).heroState.message,
            "1 photo or video is in your organized library. Your originals were not changed."
        )

        // failed: the recorded error message wins.
        XCTAssertEqual(
            heroModel(status: .failed, lastError: "The destination disk is full.").heroState.message,
            "The destination disk is full."
        )
    }

    func testHeroCopyNeverSaysTransferOrRun() {
        let statuses: [RunStatus] = [
            .idle, .preflighting, .running, .dryRunFinished, .finished, .nothingToCopy,
            .cancelled, .failed, .reverted, .revertEmpty, .reorganized, .nothingToReorganize,
        ]
        var models: [(String, RunWorkspaceModel)] = []
        for status in statuses {
            for canStart in [true, false] {
                models.append(("\(status) canStart=\(canStart)", heroModel(status: status, mode: .transfer, canStart: canStart, copied: 5, planned: 5)))
            }
        }
        models.append(("running preview", heroModel(status: .running, mode: .preview)))
        let banned = try! NSRegularExpression(pattern: "\\b(transfer|run)\\b", options: [.caseInsensitive])
        for (label, model) in models {
            let hero = model.heroState
            for text in [hero.title, hero.message, hero.badgeTitle] {
                let range = NSRange(text.startIndex..., in: text)
                XCTAssertNil(banned.firstMatch(in: text, range: range), "\(label): \"\(text)\"")
            }
        }
    }

    // AGENTS-INVARIANT: 10
    func testFailureAndStopCopySayOriginalsNotChanged() {
        for status in [RunStatus.failed, .cancelled] {
            let message = heroModel(status: status).heroState.message
            XCTAssertTrue(
                message.localizedCaseInsensitiveContains("originals were not changed"),
                "\(status): \(message)"
            )
        }
    }

    func testMetricTileTitlesMatchContract() {
        let tiles = heroModel(status: .dryRunFinished).metrics
        XCTAssertEqual(tiles.map(\.title), ["Found", "To Copy", "Already There", "Exact Copies", "Problems", "Copied"])
        XCTAssertEqual(tiles.map(\.caption), [
            "Photos and videos in your folders.",
            "New files in the plan.",
            "Skipped because the same file is already in the library.",
            "Set aside in the Duplicate folder.",
            "Warnings and files that could not be copied or checked.",
            "Files copied so far.",
        ])

        let review = heroModel(status: .dryRunFinished).previewReviewSummaryTiles
        XCTAssertEqual(review.map(\.title), ["Ready", "Needs Attention", "No Date", "Exact Copies"])
        XCTAssertEqual(review.map(\.caption), [
            "Ready to copy.",
            "No date, an unsure date, or unreadable.",
            "Go to the Unknown_Date folder unless you set a date.",
            "Exact copies, set aside in the Duplicate folder.",
        ])
    }

    func testTabTitlesMatchContract() {
        let quiet = heroModel(status: .dryRunFinished)
        XCTAssertEqual(quiet.tabTitle(.overview), "Overview")
        XCTAssertEqual(quiet.tabTitle(.review), "Review")
        XCTAssertEqual(quiet.tabTitle(.issues), "Problems")
        XCTAssertEqual(quiet.tabTitle(.console), "Activity")

        let busy = RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .dryRunFinished,
                currentMode: .preview,
                currentTaskTitle: "",
                currentPhase: nil,
                progress: 1,
                metrics: RunMetrics(),
                summary: nil,
                lastErrorMessage: nil,
                warningCount: 2,
                errorCount: 1,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "",
                currentSourceRoot: "",
                canStartRun: true,
                previewReviewSummary: PreviewReviewSummary(needsAttentionCount: 4)
            )
        )
        XCTAssertEqual(busy.tabTitle(.review), "Review (4)")
        XCTAssertEqual(busy.tabTitle(.issues), "Problems (3)")
    }

    func testThroughputSaysDoneWhenFinishedAndStartingOtherwise() {
        for status in [RunStatus.finished, .nothingToCopy, .reverted, .reorganized] {
            XCTAssertEqual(heroModel(status: status).throughputSummaryValue, "Done", "\(status)")
        }
        for status in [RunStatus.running, .preflighting, .idle, .dryRunFinished, .failed, .cancelled] {
            XCTAssertEqual(heroModel(status: status).throughputSummaryValue, "Starting…", "\(status)")
        }
    }

    func testOutcomeSummaryMessagesMatchContract() {
        XCTAssertEqual(
            heroModel(status: .finished).outcomeSummaryMessage,
            "Your originals were not changed. The report and the receipt for undoing this copy are in History."
        )
        XCTAssertEqual(heroModel(status: .nothingToCopy).outcomeSummaryMessage, "Nothing needed copying.")
        XCTAssertEqual(
            heroModel(status: .reverted).outcomeSummaryMessage,
            "Copies changed since the original copy were kept."
        )
        XCTAssertEqual(
            heroModel(status: .reorganized).outcomeSummaryMessage,
            "Files were moved into the chosen layout and a receipt was saved."
        )
        XCTAssertEqual(
            heroModel(status: .nothingToReorganize).outcomeSummaryMessage,
            "The library already matches the chosen layout."
        )
    }

    func testPlainCopyForSupportingPanelsHasNoEngineVocabulary() {
        let quiet = heroModel(status: .failed)
        XCTAssertEqual(quiet.issueSummaryValue, "No problems reported")
        XCTAssertEqual(
            quiet.issueWorkspaceSummary,
            "No warnings or errors have been reported yet. If something changes, this view will pull the important problems out of the full activity log."
        )
        XCTAssertEqual(
            heroModel(status: .failed).sourceSummaryValue,
            "Your folders will appear here once you choose them."
        )
        XCTAssertEqual(
            heroModel(status: .failed).destinationSummaryValue,
            "Your destination will appear here once you choose one."
        )
    }

    func testNowLineReadsNotStartedWhenTaskIsEmptyOrIdle() {
        func now(_ title: String) -> String {
            RunWorkspaceModel(
                context: RunWorkspaceContext(
                    status: .idle, currentMode: nil, currentTaskTitle: title, currentPhase: nil,
                    progress: 0, metrics: RunMetrics(), summary: nil, lastErrorMessage: nil,
                    warningCount: 0, errorCount: 0, issueCount: 0, logEntries: [],
                    historyDestinationRoot: "", currentSourceRoot: "", canStartRun: false
                )
            ).nowSummaryValue
        }
        XCTAssertEqual(now(""), "Not started")
        XCTAssertEqual(now("Idle"), "Not started")
        XCTAssertEqual(now("Copying files..."), "Copying files...")
    }

    // MARK: - isBlankIdle (design-critique fix #7)

    func testIsBlankIdleRequiresBothIdleStatusAndZeroDiscoveredFiles() {
        // Idle with nothing discovered → blank idle (show onboarding card, not empty sections)
        XCTAssertTrue(makeModel(status: .idle, discoveredCount: 0).isBlankIdle)

        // Idle but files were already discovered in this session → not blank
        XCTAssertFalse(makeModel(status: .idle, discoveredCount: 1).isBlankIdle)
        XCTAssertFalse(makeModel(status: .idle, discoveredCount: 200).isBlankIdle)

        // Active/terminal states are never blank idle regardless of count
        XCTAssertFalse(makeModel(status: .running, discoveredCount: 0).isBlankIdle)
        XCTAssertFalse(makeModel(status: .preflighting, discoveredCount: 0).isBlankIdle)
        XCTAssertFalse(makeModel(status: .finished, discoveredCount: 0).isBlankIdle)
        XCTAssertFalse(makeModel(status: .dryRunFinished, discoveredCount: 0).isBlankIdle)
        XCTAssertFalse(makeModel(status: .failed, discoveredCount: 0).isBlankIdle)
    }

    // MARK: - Helpers

    private func makeModel(status: RunStatus, discoveredCount: Int = 0) -> RunWorkspaceModel {
        RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: status,
                currentMode: nil,
                currentTaskTitle: "",
                currentPhase: nil,
                progress: 0,
                metrics: RunMetrics(discoveredCount: discoveredCount),
                summary: nil,
                lastErrorMessage: nil,
                warningCount: 0,
                errorCount: 0,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "",
                currentSourceRoot: "",
                canStartRun: false
            )
        )
    }
}
