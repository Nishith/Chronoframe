import AppKit
import Foundation

enum UITestScenario: String, CaseIterable {
    case setupIncompleteRun
    case setupReady
    case runPreviewReview
    case healthDashboard
    case historyPopulated
    case profilesPopulated
    case settingsSections
    case settingsLayout
    case settingsPerformance
    case settingsDeduplicate
    case settingsDiagnostics
    case deduplicateReviewWide
    case deduplicateReviewCompact

    static func current(environment: [String: String] = ProcessInfo.processInfo.environment) -> UITestScenario? {
        guard let rawValue = environment["CHRONOFRAME_UI_TEST_SCENARIO"] else { return nil }
        return UITestScenario(rawValue: rawValue)
    }

    var opensSettingsOnLaunch: Bool {
        switch self {
        case .profilesPopulated, .settingsSections, .settingsLayout, .settingsPerformance, .settingsDeduplicate, .settingsDiagnostics:
            return true
        default:
            return false
        }
    }

    private var preferredMainWindowSize: NSSize {
        switch self {
        case .setupIncompleteRun, .setupReady, .runPreviewReview, .healthDashboard, .historyPopulated, .profilesPopulated:
            return NSSize(width: 1360, height: 920)
        case .settingsSections, .settingsLayout, .settingsPerformance, .settingsDeduplicate, .settingsDiagnostics:
            return NSSize(width: 1360, height: 920)
        case .deduplicateReviewWide:
            return NSSize(width: 1180, height: 820)
        case .deduplicateReviewCompact:
            return NSSize(width: 900, height: 700)
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
            window.setContentSize(size)
            window.center()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
