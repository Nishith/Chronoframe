import SwiftUI
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

enum SetupScreenTone: String, Equatable {
    case idle
    case ready
    case warning
    case success
    case sky
    case amber
    case muted

    var color: SwiftUI.Color {
        switch self {
        case .idle:
            return DesignTokens.Status.idle
        case .ready:
            return DesignTokens.Status.ready
        case .warning:
            return DesignTokens.Status.warning
        case .success:
            return DesignTokens.Status.success
        case .sky:
            return DesignTokens.Color.sky
        case .amber:
            return DesignTokens.Color.amber
        case .muted:
            return DesignTokens.Color.inkMuted
        }
    }
}

enum SetupStepState: Equatable {
    case ready(String, SetupScreenTone)
    case active(String, SetupScreenTone)
    case needed(String, SetupScreenTone)

    var title: String {
        switch self {
        case let .ready(title, _), let .active(title, _), let .needed(title, _):
            return title
        }
    }

    var tone: SetupScreenTone {
        switch self {
        case let .ready(_, tone), let .active(_, tone), let .needed(_, tone):
            return tone
        }
    }
}

enum SetupPrimaryAction: Equatable {
    case chooseSource
    case chooseDestination
    case preview

    var title: String {
        switch self {
        case .chooseSource:
            return String(localized: "Add Folders", bundle: .module)
        case .chooseDestination:
            return String(localized: "Choose Destination", bundle: .module)
        case .preview:
            return String(localized: "Preview Plan", bundle: .module)
        }
    }

    var systemImage: String {
        switch self {
        case .chooseSource:
            return "folder.badge.plus"
        case .chooseDestination:
            return "externaldrive.badge.plus"
        case .preview:
            return "eye"
        }
    }
}

struct SetupSourceItemRow: Identifiable, Equatable {
    let id: String
    let name: String
    let parent: String
    let isFolder: Bool
}

struct SetupScreenContext {
    var sourcePath: String
    var destinationPath: String
    var deduplicateDestinationPath: String
    var selectedProfileName: String
    var activeProfile: Profile?
    var usingDroppedSource: Bool
    var droppedSourceLabel: String?
    var droppedSourceItemCount: Int
    var workerCount: Int
    var verifyCopies: Bool
    var isRunInProgress: Bool
    var availableProfileCount: Int
    var sourceItems: [SetupSourceItemRow]

    init(
        sourcePath: String,
        destinationPath: String,
        deduplicateDestinationPath: String = "",
        selectedProfileName: String,
        activeProfile: Profile? = nil,
        usingDroppedSource: Bool = false,
        droppedSourceLabel: String? = nil,
        droppedSourceItemCount: Int = 0,
        workerCount: Int = 4,
        verifyCopies: Bool = true,
        isRunInProgress: Bool = false,
        availableProfileCount: Int = 0,
        sourceItems: [SetupSourceItemRow] = []
    ) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.deduplicateDestinationPath = deduplicateDestinationPath.isEmpty ? destinationPath : deduplicateDestinationPath
        self.selectedProfileName = selectedProfileName
        self.activeProfile = activeProfile
        self.usingDroppedSource = usingDroppedSource
        self.droppedSourceLabel = droppedSourceLabel
        self.droppedSourceItemCount = droppedSourceItemCount
        self.workerCount = workerCount
        self.verifyCopies = verifyCopies
        self.isRunInProgress = isRunInProgress
        self.availableProfileCount = availableProfileCount
        self.sourceItems = sourceItems
    }
}

struct SetupScreenModel {
    let context: SetupScreenContext

    @MainActor
    init(
        setupStore: SetupStore,
        preferencesStore: PreferencesStore,
        isRunInProgress: Bool
    ) {
        let dedupePath = !preferencesStore.lastDeduplicateDestinationPath.isEmpty
            ? preferencesStore.lastDeduplicateDestinationPath
            : setupStore.destinationPath

        self.init(
            context: SetupScreenContext(
                sourcePath: setupStore.sourcePath,
                destinationPath: setupStore.destinationPath,
                deduplicateDestinationPath: dedupePath,
                selectedProfileName: setupStore.selectedProfileName,
                activeProfile: setupStore.activeProfile,
                usingDroppedSource: setupStore.usingDroppedSource,
                droppedSourceLabel: setupStore.droppedSourceLabel,
                droppedSourceItemCount: setupStore.droppedSourceItemCount,
                workerCount: preferencesStore.workerCount,
                verifyCopies: preferencesStore.verifyCopies,
                isRunInProgress: isRunInProgress,
                availableProfileCount: setupStore.profiles.count,
                sourceItems: Self.sourceItemRows(for: setupStore)
            )
        )
    }

    /// The listed folders, or the single plain source path (profile and
    /// legacy single-folder cases). A selected profile hides the manual list
    /// without deleting it (D-CLP-21), so its folder is the one row. A staging
    /// path alone is not a folder the user chose and yields no row.
    @MainActor
    private static func sourceItemRows(for setupStore: SetupStore) -> [SetupSourceItemRow] {
        if setupStore.activeProfile == nil, !setupStore.sourceItems.isEmpty {
            return setupStore.sourceItems.map(row(for:))
        }
        let sourcePath = setupStore.sourcePath
        if !sourcePath.isEmpty, !DroppedItemStager.isStagingPath(sourcePath) {
            return [row(for: URL(fileURLWithPath: sourcePath))]
        }
        return []
    }

    private static func row(for url: URL) -> SetupSourceItemRow {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let name = url.lastPathComponent
        return SetupSourceItemRow(
            id: url.path,
            name: name.isEmpty ? url.path : name,
            parent: (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath,
            isFolder: exists ? isDirectory.boolValue : true
        )
    }

    init(context: SetupScreenContext) {
        self.context = context
    }

    var canStartRun: Bool {
        !context.selectedProfileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (!context.sourcePath.isEmpty && !context.destinationPath.isEmpty)
    }

    var displayedSourcePath: String {
        if context.usingDroppedSource {
            return context.droppedSourceLabel ?? context.sourcePath
        }
        return context.sourcePath
    }

    var sourceStepState: SetupStepState {
        if context.usingDroppedSource || !context.sourcePath.isEmpty {
            return .ready("", .success)
        }
        return .needed(String(localized: "Add a folder", bundle: .module), .warning)
    }

    var destinationStepState: SetupStepState {
        if !context.destinationPath.isEmpty {
            return .ready("", .success)
        }
        return .needed(String(localized: "Choose a destination", bundle: .module), .warning)
    }

    var heroTone: SetupScreenTone {
        if canStartRun {
            return .ready
        }
        if context.usingDroppedSource || !context.sourcePath.isEmpty || !context.destinationPath.isEmpty {
            return .warning
        }
        return .idle
    }

    var heroBadgeTitle: String {
        if context.activeProfile != nil {
            return String(localized: "Profile ready", bundle: .module)
        }
        if canStartRun {
            return String(localized: "Ready to preview", bundle: .module)
        }
        if context.usingDroppedSource || !context.sourcePath.isEmpty || !context.destinationPath.isEmpty {
            return String(localized: "One more step", bundle: .module)
        }
        return String(localized: "Start here", bundle: .module)
    }

    var heroBadgeSymbol: String {
        if canStartRun {
            return "checkmark.circle.fill"
        }
        if context.usingDroppedSource {
            return "square.and.arrow.down.on.square.fill"
        }
        return "circle.dashed"
    }

    var sourceSummaryValue: String {
        if let profile = context.activeProfile {
            return profile.sourcePath
        }
        switch context.sourceItems.count {
        case 0: return String(localized: "Needed", bundle: .module)
        case 1: return String(localized: "Ready", bundle: .module)
        case let count: return SourceItemList.summaryLabel(count: count)
        }
    }

    var destinationSummaryValue: String {
        if let profile = context.activeProfile {
            return profile.destinationPath
        }
        return context.destinationPath.isEmpty ? String(localized: "Needed", bundle: .module) : String(localized: "Ready", bundle: .module)
    }

    var modeSummaryValue: String {
        if context.activeProfile != nil {
            return String(localized: "Saved profile: \(String(context.selectedProfileName))", bundle: .module)
        }
        return String(localized: "Folders you chose", bundle: .module)
    }

    var nextStepSummary: String {
        if context.sourcePath.isEmpty {
            return String(localized: "Add the folders to organize", bundle: .module)
        }
        if context.destinationPath.isEmpty {
            return String(localized: "Choose where the copies go", bundle: .module)
        }
        return String(localized: "Preview the plan", bundle: .module)
    }

    var configurationSummary: String {
        if context.activeProfile != nil {
            return String(localized: "Using the saved profile \(String(context.selectedProfileName))", bundle: .module)
        }
        return String(localized: "Folders you chose", bundle: .module)
    }

    var performanceSummary: String {
        String(localized: "\(String(context.workerCount)) workers", bundle: .module)
    }

    var safetySummary: String {
        context.verifyCopies
            ? String(localized: "Verification is enabled after copy", bundle: .module)
            : String(localized: "Verification is disabled for faster throughput", bundle: .module)
    }

    var readinessMessage: String {
        canStartRun
            ? String(localized: "A preview copies nothing. It shows where every file would go, and you decide after that.", bundle: .module)
            : String(localized: "Add a folder and choose a destination to see a preview.", bundle: .module)
    }

    /// Profiles are earned complexity: a first-time user has none and should
    /// not see the section at all. It appears once any profile exists or one
    /// is selected; creation lives in the Profiles workspace.
    var showsSavedSetupSection: Bool {
        context.availableProfileCount > 0
            || context.activeProfile != nil
            || !context.selectedProfileName.isEmpty
    }

    var savedSetupBadgeTitle: String {
        context.activeProfile != nil ? String(localized: "Active", bundle: .module) : String(localized: "Optional", bundle: .module)
    }

    var savedSetupBadgeSymbol: String {
        context.activeProfile != nil ? "checkmark.circle.fill" : "bookmark"
    }

    var savedSetupTone: SetupScreenTone {
        context.activeProfile != nil ? .success : .idle
    }

    var sourcePathHelper: String {
        switch context.sourceItems.count {
        case 0: return ""
        case 1: return String(localized: "Chronoframe reads this folder and never changes what is in it.", bundle: .module)
        case let count:
            return String(localized: "Chronoframe reads these \(String(count.formatted())) folders together and never changes what is in them.", bundle: .module)
        }
    }

    var destinationPathHelper: String {
        String(localized: "Chronoframe creates dated folders here and keeps a receipt of each copy so you can undo it from History.", bundle: .module)
    }

    var primaryAction: SetupPrimaryAction {
        if context.sourcePath.isEmpty {
            return .chooseSource
        }
        if context.destinationPath.isEmpty {
            return .chooseDestination
        }
        return .preview
    }

    var primaryActionDisabled: Bool {
        context.isRunInProgress
    }
}
