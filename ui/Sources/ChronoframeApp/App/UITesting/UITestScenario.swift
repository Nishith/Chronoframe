import AppKit
import Foundation

enum UITestScenario: String, CaseIterable {
    case setupReady
    case runPreviewReview
    case historyPopulated
    case profilesPopulated
    case settingsSections

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> UITestScenario? {
        guard let rawValue = environment["CHRONOFRAME_UI_TEST_SCENARIO"] else { return nil }
        return UITestScenario(rawValue: rawValue)
    }

    var opensSettingsOnLaunch: Bool {
        self == .settingsSections
    }

    private var preferredMainWindowSize: NSSize {
        switch self {
        case .setupReady, .runPreviewReview, .historyPopulated, .profilesPopulated:
            return NSSize(width: 1360, height: 920)
        case .settingsSections:
            return NSSize(width: 1360, height: 920)
        }
    }

    private var preferredSettingsWindowSize: NSSize {
        NSSize(width: 760, height: 900)
    }

    @MainActor
    static func configureCurrentWindow(for scenario: UITestScenario?, isSettings: Bool = false) {
        guard let scenario else { return }

        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.last else { return }
            let size = isSettings ? scenario.preferredSettingsWindowSize : scenario.preferredMainWindowSize
            var frame = window.frame
            frame.size = size
            window.setFrame(frame, display: true, animate: false)
            window.center()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
