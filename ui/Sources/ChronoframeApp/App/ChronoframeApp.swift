import SwiftUI

@main
struct ChronoframeApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup("Chronoframe") {
            RootSplitView(appState: appState)
                .frame(minWidth: 1_100, minHeight: 760)
        }
        .commands {
            AppCommands(appState: appState)
        }

        Settings {
            SettingsView(appState: appState)
                .frame(width: 420, height: 280)
                .padding()
        }
    }
}
