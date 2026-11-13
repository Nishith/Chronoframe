#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit
import SwiftUI

enum ChronoframeLinks {
    static let website = URL(string: "https://chronoframe.app/")!
    static let privacy = URL(string: "https://chronoframe.app/privacy.html")!
    static let support = URL(string: "https://chronoframe.app/support.html")!
}

struct AppCommands: Commands {
    @ObservedObject private var appState: AppState
    @ObservedObject private var setupStore: SetupStore
    @ObservedObject private var runSessionStore: RunSessionStore
    @Environment(\.openWindow) private var openWindow

    static let addFoldersCommandTitle = "Add Folders…"
    static let previewCommandTitle = "Preview Plan"
    static let startCopyingCommandTitle = "Start Copying"

    init(appState: AppState) {
        self._appState = ObservedObject(wrappedValue: appState)
        self._setupStore = ObservedObject(wrappedValue: appState.setupStore)
        self._runSessionStore = ObservedObject(wrappedValue: appState.runSessionStore)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Chronoframe") {
                AboutPanel.show()
            }
        }

        CommandMenu("Library") {
            Button(LocalizedStringKey(Self.addFoldersCommandTitle)) {
                Task { await appState.chooseSourceFolder() }
            }
            .keyboardShortcut("o", modifiers: [.command])

            Button("Choose Destination…") {
                Task { await appState.chooseDestinationFolder() }
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Refresh Profiles") {
                appState.refreshProfiles()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
        }

        CommandMenu("Organize") {
            // Preview/Transfer act on the Organize flow only. Gate them to the
            // Organize section so their shortcuts (⌘R, ⌘↩) don't shadow the
            // primary buttons on the Deduplicate screen — ⌘↩ in particular is
            // also the Deduplicate scan/commit shortcut, and a main-menu key
            // equivalent would otherwise win and launch an organize Transfer.
            Button(LocalizedStringKey(Self.previewCommandTitle)) {
                Task { await appState.startPreview() }
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!isOrganizeSelected || !canStartRun || runSessionStore.isRunning)

            Button(LocalizedStringKey(Self.startCopyingCommandTitle)) {
                Task { await appState.startTransfer() }
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(!isOrganizeSelected || !canStartRun || runSessionStore.isRunning)

            Divider()

            Button("Stop") {
                appState.cancelRun()
            }
            .disabled(!runSessionStore.isRunning || runSessionStore.isCancelling)
        }

        CommandGroup(replacing: .help) {
            Button("Chronoframe Help") {
                openWindow(id: ChronoframeApp.helpWindowID)
            }
            .keyboardShortcut("?", modifiers: [.command])

            Button("Keyboard Shortcuts") {
                openWindow(id: ChronoframeApp.helpWindowID)
            }

            Divider()

            Button("Chronoframe Website") {
                NSWorkspace.shared.open(ChronoframeLinks.website)
            }

            Button("Privacy Policy") {
                NSWorkspace.shared.open(ChronoframeLinks.privacy)
            }

            Button("Support") {
                NSWorkspace.shared.open(ChronoframeLinks.support)
            }

            Divider()

            Button("Reveal Profiles File…") {
                let url = RuntimePaths.profilesFileURL()
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            Button("Reveal App Support Folder…") {
                let url = RuntimePaths.applicationSupportDirectory()
                try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }

            Divider()

            Button("Acknowledgments") {
                openWindow(id: ChronoframeApp.helpWindowID)
            }
        }
    }

    private var canStartRun: Bool {
        setupStore.usingProfile || (!setupStore.sourcePath.isEmpty && !setupStore.destinationPath.isEmpty)
    }

    private var isOrganizeSelected: Bool {
        appState.selection == .organize
    }
}
