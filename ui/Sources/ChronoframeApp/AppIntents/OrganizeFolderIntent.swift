import AppIntents
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation

enum OrganizeIntentFailureMessage {
    static func message(summary: RunSummary?, lastErrorMessage: String?) -> String {
        summary?.failureMessage
            ?? lastErrorMessage
            ?? "Chronoframe could not complete the transfer. Check that both folders are available and try again."
    }
}

// MARK: - Purchase refusals in a background intent (free-trial step 4, T11)
//
// An intent can run from a Shortcut, an automation, or a Focus trigger, with
// nobody watching. THIS PATH MUST NEVER ATTEMPT AN INTERACTIVE PURCHASE: a
// StoreKit sheet needs a foreground app and a person to answer it, so from here
// it would either fail silently or hang an automation waiting on a window that
// no one can see. `script/check_app_intents_never_purchase.sh` fails CI if a
// purchase or restore call appears under `AppIntents/`.
//
// So the only correct move is to stop and say where to go. The message names the
// reason, because "could not complete the transfer" would send someone hunting
// through folder permissions for a problem that is actually a paywall.

enum OrganizeIntentPurchaseMessage {
    /// What to tell an unattended automation that hit the gate.
    ///
    /// Never phrased as a transfer failure — nothing failed, and nothing was
    /// copied. Each case says what is true and where to resolve it, and
    /// `purchaseUnconfirmed` in particular must not accuse a customer who may
    /// well have paid of having spent a trial.
    static func message(for refusal: TrialAuthorizationRefusal) -> String {
        switch refusal {
        case let .allowanceSpent(details):
            return allowanceSpentMessage(details)
        case .purchaseUnconfirmed:
            return "Chronoframe could not confirm your purchase, so this shortcut did not copy anything. "
                + "Open Chronoframe to check your purchase, then run this shortcut again."
        case .requiresUnlock:
            return "This action needs Chronoframe unlocked. "
                + "Open Chronoframe to unlock it, then run this shortcut again."
        }
    }

    /// Says how much allowance is actually left.
    ///
    /// A refusal does NOT mean the balance is zero: the policy refuses whenever
    /// the run is bigger than what remains, so a shortcut asking for 40 files
    /// with 12 left is refused with 12 still available. Telling that customer
    /// their allowance is "used up" is simply false, and it hides the fact that
    /// a smaller batch would still run.
    ///
    /// Deliberately not shared with `TrialAuthorizationError`'s copy, which says
    /// the same arithmetic differently: that one is read inside the app, where
    /// "Open Chronoframe" would be nonsense.
    private static func allowanceSpentMessage(_ refusal: TrialRefusal) -> String {
        let noun = refusal.meter == .organize ? "file" : "duplicate"
        let opening: String
        if refusal.remaining == 0 {
            opening = "Chronoframe's free allowance is used up, so this shortcut did not copy anything."
        } else {
            let plural = refusal.remaining == 1 ? "" : "s"
            opening = "Chronoframe's free allowance has \(refusal.remaining) \(noun)\(plural) left "
                + "and this shortcut needed \(refusal.requested), so it did not copy anything."
        }
        return opening + " Open Chronoframe to unlock it, then run this shortcut again."
    }
}

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
        
        let engine = SwiftOrganizerEngine(authorizer: TrialComposition.authorizer)
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
            // Checked before the generic failure branch. A refused run reaches
            // `.failed` like any other unstarted run, but it is not a failure —
            // nothing broke, nothing was copied, and the fix is a purchase
            // rather than a retry. Its own code so a Shortcut can branch on it.
            if let refusal = session.lastRefusal {
                throw NSError(
                    domain: "com.chronoframe.AppIntents",
                    code: 1004,
                    userInfo: [
                        NSLocalizedDescriptionKey: OrganizeIntentPurchaseMessage.message(for: refusal)
                    ]
                )
            }
            let errorMsg = OrganizeIntentFailureMessage.message(
                summary: session.summary,
                lastErrorMessage: session.lastErrorMessage
            )
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
