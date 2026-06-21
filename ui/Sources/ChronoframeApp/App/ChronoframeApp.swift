import AppKit
import SwiftUI
@preconcurrency import UserNotifications
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
        #if DEBUG
        let scenario = UITestScenario.current()
        self.uiTestScenario = scenario
        self._appState = StateObject(
            wrappedValue: scenario.map { UITestAppStateFactory.make(scenario: $0) } ?? AppState()
        )
        #else
        self.uiTestScenario = nil
        self._appState = StateObject(wrappedValue: AppState())
        #endif
        RunSessionStore.requestNotificationPermission()
        TipConfiguration.configureIfNeeded(isUITest: uiTestScenario != nil)
    }

    var body: some Scene {
        Window("Chronoframe", id: ChronoframeApp.mainWindowID) {
            mainWindowContent
        }
        .commands {
            AppCommands(appState: appState)
        }
        .windowResizability(.contentMinSize)

        Settings {
            SettingsView(appState: appState)
                .accessibilityLabel("Settings")
        }

        Window("Chronoframe Help", id: ChronoframeApp.helpWindowID) {
            HelpView()
                .accessibilityLabel("Chronoframe Help")
        }
        .windowResizability(.contentMinSize)
    }

    static let mainWindowID = "chronoframe-main"
    static let helpWindowID = "chronoframe-help"

    @ViewBuilder
    private var mainWindowContent: some View {
        if uiTestScenario?.opensSettingsOnLaunch == true {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityHidden(true)
                .task {
                    guard !didOpenScenarioSettings else { return }
                    didOpenScenarioSettings = true
                    appState.openSettingsWindow()
                }
        } else {
            RootSplitView(appState: appState)
                .accessibilityLabel("Chronoframe")
                .frame(
                    minWidth: DesignTokens.Window.mainMinWidth,
                    idealWidth: DesignTokens.Window.mainIdealWidth,
                    minHeight: DesignTokens.Window.mainMinHeight,
                    idealHeight: DesignTokens.Window.mainIdealHeight
                )
        }
    }
}

@MainActor
final class ChronoframeAppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        guard !Self.isRunningUITestScenario else { return }

        if let existingApplication = Self.alreadyRunningApplication() {
            existingApplication.activate(options: [.activateAllWindows])
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        #if DEBUG
        if UITestScenario.current()?.opensSettingsOnLaunch == true {
            return
        }
        #endif
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

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await activateFromNotification()
    }

    private func activateMainWindow() {
        let mainWindow = NSApp.windows.first { $0.title == "Chronoframe" } ?? NSApp.windows.first
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static func alreadyRunningApplication() -> NSRunningApplication? {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return nil }
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { application in
                application.processIdentifier != currentProcessIdentifier && !application.isTerminated
            }
            .min { lhs, rhs in
                lhs.processIdentifier < rhs.processIdentifier
            }
    }

    private static var isRunningUITestScenario: Bool {
        #if DEBUG
        UITestScenario.isRunningScenario()
        #else
        false
        #endif
    }

    private nonisolated func activateFromNotification() async {
        await MainActor.run {
            activateMainWindow()
        }
    }
}
