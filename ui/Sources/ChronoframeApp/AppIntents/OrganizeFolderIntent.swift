import AppIntents
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation

@available(macOS 14.0, *)
public struct OrganizeFolderIntent: AppIntent {
    public static let title: LocalizedStringResource = "Organize Folder with Chronoframe"
    public static let description = IntentDescription("Organizes an unsorted source directory into a date-based structure.")

    @Parameter(title: "Source Folder")
    public var sourceFolder: URL

    @Parameter(title: "Destination Folder")
    public var destinationFolder: URL

    public static var parameterSummary: some ParameterSummary {
        Summary("Organize \(\.$sourceFolder) into \(\.$destinationFolder)")
    }

    public init() {}

    public init(sourceFolder: URL, destinationFolder: URL) {
        self.sourceFolder = sourceFolder
        self.destinationFolder = destinationFolder
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let sourcePath = sourceFolder.path
        let destinationPath = destinationFolder.path
        
        let config = RunConfiguration(
            mode: .transfer,
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            profileName: nil,
            verifyCopies: true,
            parallelTransferEnabled: true,
            workerCount: 8,
            folderStructure: .default
        )
        
        let sourceStart = sourceFolder.startAccessingSecurityScopedResource()
        let destStart = destinationFolder.startAccessingSecurityScopedResource()
        defer {
            if sourceStart { sourceFolder.stopAccessingSecurityScopedResource() }
            if destStart { destinationFolder.stopAccessingSecurityScopedResource() }
        }
        
        let engine = SwiftOrganizerEngine()
        let runLogStore = RunLogStore(capacity: 100)
        let historyStore = HistoryStore()
        let session = RunSessionStore(engine: engine, logStore: runLogStore, historyStore: historyStore)
        
        await session.requestRun(mode: .transfer, configuration: config)
        
        // Poll for preflight completion or prompt
        while session.status == .preflighting && session.prompt == nil {
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
        
        if let prompt = session.prompt {
            if prompt.kind == .blockingError {
                throw NSError(
                    domain: "com.chronoframe.AppIntents",
                    code: 1001,
                    userInfo: [NSLocalizedDescriptionKey: prompt.message]
                )
            }
            session.confirmPrompt()
        }
        
        // Poll until execution completes
        while session.status == .running || session.status == .preflighting {
            try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        }
        
        switch session.status {
        case .finished:
            return .result(value: "Successfully organized folder. Transferred \(session.metrics.copiedCount) files.")
        case .nothingToCopy:
            return .result(value: "No files to copy. Everything is already organized.")
        case .failed:
            let errorMsg = session.lastErrorMessage ?? "Unknown error"
            throw NSError(
                domain: "com.chronoframe.AppIntents",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "Transfer failed: \(errorMsg)"]
            )
        case .cancelled:
            throw NSError(
                domain: "com.chronoframe.AppIntents",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "Transfer was cancelled."]
            )
        default:
            return .result(value: "Organize run ended with status: \(session.status)")
        }
    }
}
