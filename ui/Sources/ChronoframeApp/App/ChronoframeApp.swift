import AppKit
import SwiftUI
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

@main
struct ChronoframeApp: App {
    @NSApplicationDelegateAdaptor(ChronoframeAppDelegate.self) private var appDelegate
    @StateObject private var appState: AppState
    @State private var didOpenScenarioSettings = false
    private let uiTestScenario: UITestScenario?

    init() {
        let scenario = UITestScenario.current()
        self.uiTestScenario = scenario
        self._appState = StateObject(
            wrappedValue: scenario.map { UITestAppStateFactory.make(scenario: $0) } ?? AppState()
        )
        RunSessionStore.requestNotificationPermission()
    }

    var body: some Scene {
        Window("Chronoframe", id: ChronoframeApp.mainWindowID) {
            RootSplitView(appState: appState)
                .frame(
                    minWidth: DesignTokens.Window.mainMinWidth,
                    idealWidth: DesignTokens.Window.mainIdealWidth,
                    minHeight: DesignTokens.Window.mainMinHeight,
                    idealHeight: DesignTokens.Window.mainIdealHeight
                )
                .task {
                    guard uiTestScenario?.opensSettingsOnLaunch == true, !didOpenScenarioSettings else { return }
                    didOpenScenarioSettings = true
                    appState.openSettingsWindow()
                }
        }
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            SettingsView(appState: appState)
                .frame(
                    minWidth: DesignTokens.Window.settingsMinWidth,
                    idealWidth: DesignTokens.Window.settingsIdealWidth,
                    minHeight: DesignTokens.Window.settingsMinHeight
                )
                .padding()
        }

        Window("Chronoframe Help", id: ChronoframeApp.helpWindowID) {
            HelpView()
        }
        .windowResizability(.contentMinSize)
    }

    static let mainWindowID = "chronoframe-main"
    static let helpWindowID = "chronoframe-help"
}

@MainActor
final class ChronoframeAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            self.activateMainWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            activateMainWindow()
        }
        return true
    }

    private func activateMainWindow() {
        let mainWindow = NSApp.windows.first { $0.title == "Chronoframe" } ?? NSApp.windows.first
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
