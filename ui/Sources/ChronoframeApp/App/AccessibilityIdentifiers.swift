import Foundation

/// Single source of truth for accessibility identifiers used by interactive and
/// structural UI elements.
///
/// These identifiers are consumed by the XCUITest target
/// (`ui/Xcode/UITests/ChronoframeUITests.swift`) to locate elements. Keeping
/// them centralized — rather than scattered as bare string literals across the
/// view layer — prevents silent drift between a view and the test that looks it
/// up, and lets `AccessibilityTests` assert they are non-empty, space-free, and
/// unique.
///
/// String values must remain byte-identical to the literals that previously
/// lived inline, so existing XCUITest queries keep matching.
enum AccessibilityIdentifiers {

    // MARK: - Setup

    static let chooseSourceButton = "chooseSourceButton"
    static let chooseDestinationButton = "chooseDestinationButton"
    static let dropZone = "dropZone"
    static let folderStructurePicker = "folderStructurePicker"
    static let profilePicker = "profilePicker"
    static let previewButton = "previewButton"
    static let transferButton = "transferButton"
    static let setupPreflightChecklist = "setupPreflightChecklist"
    static let setupSafetyDetailsDisclosure = "setupSafetyDetailsDisclosure"

    // MARK: - Run

    static let consoleScrollView = "consoleScrollView"
    static let openDestinationButton = "openDestinationButton"
    static let openReportButton = "openReportButton"
    static let openLogsButton = "openLogsButton"
    static let startTransferFromPreviewButton = "startTransferFromPreviewButton"
    static let runWorkspaceTabs = "runWorkspaceTabs"
    static let runIdleOnboardingCard = "runIdleOnboardingCard"
    static let runOutcomeSummaryCard = "runOutcomeSummaryCard"
    static let previewReviewFilter = "previewReviewFilter"

    // MARK: - Organize

    static let refreshLibraryHealthButton = "refreshLibraryHealthButton"
    static let reorganizeDestinationButton = "reorganizeDestinationButton"

    // MARK: - Deduplicate

    static let dedupeAcceptAllSuggestionsButton = "dedupeAcceptAllSuggestionsButton"
    static let dedupeAcceptClusterSuggestionButton = "dedupeAcceptClusterSuggestionButton"
    static let dedupeAcceptHighConfidenceButton = "dedupeAcceptHighConfidenceButton"
    static let dedupeCancelCommitButton = "dedupeCancelCommitButton"
    static let dedupeChangeFolderButton = "dedupeChangeFolderButton"
    static let dedupeCommitButton = "dedupeCommitButton"
    static let dedupeCommitFooter = "dedupeCommitFooter"
    static let dedupeCommitReviewedButton = "dedupeCommitReviewedButton"
    static let dedupeFolderHistorySection = "dedupeFolderHistorySection"
    static let dedupeMemberStrip = "dedupeMemberStrip"
    static let dedupeOpenRunHistoryButton = "dedupeOpenRunHistoryButton"
    static let dedupePausedScanSection = "dedupePausedScanSection"
    static let dedupeRapidTriageButton = "dedupeRapidTriageButton"
    static let dedupeResumePausedScanButton = "dedupeResumePausedScanButton"
    static let dedupeReviewActionsMenu = "dedupeReviewActionsMenu"
    static let dedupeReviewChangeFolderButton = "dedupeReviewChangeFolderButton"
    static let dedupeReviewClusterList = "dedupeReviewClusterList"
    static let dedupeReviewDetail = "dedupeReviewDetail"
    static let dedupeReviewSettingsButton = "dedupeReviewSettingsButton"
    static let dedupeUseHistoryFolderButton = "dedupeUseHistoryFolderButton"

    // MARK: - History

    static let historyFilterControl = "historyFilterControl"
    static let recoveryCenterSection = "recoveryCenterSection"
    static let useHistoricalSourceButton = "useHistoricalSourceButton"
    static let revealHistoricalSourceButton = "revealHistoricalSourceButton"

    // MARK: - Profiles

    static let activeProfileBadge = "activeProfileBadge"

    // MARK: - Settings

    static let diagnosticsLogBufferStepper = "diagnosticsLogBufferStepper"
    static let smartEventSuggestionsToggle = "smartEventSuggestionsToggle"

    // MARK: - Per-row dynamic identifiers

    // Accept any `CustomStringConvertible` so these reproduce the original
    // string-interpolation behavior exactly — the row identifiers were keyed by
    // a `UUID` (`"openArtifact_\(entry.id)"`), whose interpolation equals its
    // `uuidString` — while still working with `String` keys (e.g. profile names).

    /// Identifier for the "Open" action of a history artifact row.
    static func openArtifact(_ id: some CustomStringConvertible) -> String { "openArtifact_\(id)" }
    /// Identifier for the "Reveal in Finder" action of a history artifact row.
    static func revealArtifact(_ id: some CustomStringConvertible) -> String { "revealArtifact_\(id)" }
    /// Identifier for the "Revert" action of a history artifact row.
    static func revertArtifact(_ id: some CustomStringConvertible) -> String { "revertArtifact_\(id)" }
    /// Identifier for the "Copy Path" action of a history artifact row.
    static func copyArtifactPath(_ id: some CustomStringConvertible) -> String { "copyArtifactPath_\(id)" }
    /// Identifier for a saved-profile row, keyed by profile name.
    static func profileName(_ name: some CustomStringConvertible) -> String { "profileName-\(name)" }
    /// Identifier for a primary sidebar destination, keyed by its raw value.
    static func sidebarDestination(_ id: some CustomStringConvertible) -> String { "sidebarDestination-\(id)" }

    // MARK: - Enumeration

    /// All static (non-parameterized) identifiers. Used by `AccessibilityTests`
    /// to assert non-emptiness, absence of spaces, and uniqueness. Parameterized
    /// identifiers (e.g. per-row artifact actions) are intentionally excluded.
    static let all: [String] = [
        chooseSourceButton, chooseDestinationButton, dropZone, folderStructurePicker,
        profilePicker, previewButton, transferButton, setupPreflightChecklist,
        setupSafetyDetailsDisclosure,
        consoleScrollView, openDestinationButton, openReportButton, openLogsButton,
        startTransferFromPreviewButton, runWorkspaceTabs, runIdleOnboardingCard,
        runOutcomeSummaryCard, previewReviewFilter,
        refreshLibraryHealthButton, reorganizeDestinationButton,
        dedupeAcceptAllSuggestionsButton, dedupeAcceptClusterSuggestionButton,
        dedupeAcceptHighConfidenceButton, dedupeCancelCommitButton, dedupeChangeFolderButton,
        dedupeCommitButton, dedupeCommitFooter, dedupeCommitReviewedButton,
        dedupeFolderHistorySection, dedupeMemberStrip, dedupeOpenRunHistoryButton,
        dedupePausedScanSection, dedupeRapidTriageButton, dedupeResumePausedScanButton,
        dedupeReviewActionsMenu, dedupeReviewChangeFolderButton, dedupeReviewClusterList,
        dedupeReviewDetail, dedupeReviewSettingsButton, dedupeUseHistoryFolderButton,
        historyFilterControl, recoveryCenterSection, useHistoricalSourceButton,
        revealHistoricalSourceButton,
        activeProfileBadge,
        diagnosticsLogBufferStepper, smartEventSuggestionsToggle,
    ]
}
