import AppKit
import Foundation

enum UITestScenario: String, CaseIterable {
    case setupIncompleteRun
    case setupReady
    case runPreviewReview
    case healthDashboard
    case watchedSources
    case photosImport
    case historyPopulated
    case profilesPopulated
    case settingsSections
    case settingsLayout
    case settingsPerformance
    case settingsDeduplicate
    case settingsLicense
    case settingsDiagnostics
    case deduplicateReviewWide
    case deduplicateReviewCompact

    static func current(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> UITestScenario? {
        let rawValue = environment["CHRONOFRAME_UI_TEST_SCENARIO"]
            ?? argumentValue(after: "--chronoframe-ui-test-scenario", in: arguments)
        guard let rawValue else { return nil }
        return UITestScenario(rawValue: rawValue)
    }

    static func isRunningScenario(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        current(environment: environment, arguments: arguments) != nil
    }

    private static func argumentValue(after option: String, in arguments: [String]) -> String? {
        guard let optionIndex = arguments.firstIndex(of: option) else { return nil }
        let valueIndex = arguments.index(after: optionIndex)
        guard valueIndex < arguments.endIndex else { return nil }
        return arguments[valueIndex]
    }

    var opensSettingsOnLaunch: Bool {
        switch self {
        case .profilesPopulated, .settingsSections, .settingsLayout, .settingsPerformance, .settingsDeduplicate, .settingsLicense, .settingsDiagnostics:
            return true
        default:
            return false
        }
    }

    /// Scenarios that exercise the Mac App Store-only allowance presentation.
    /// Their entitlement and ledger are injected by `UITestAppStateFactory`, so
    /// the audit never depends on StoreKit, signing, or a test account.
    var usesMeteredTrialUI: Bool {
        switch self {
        case .runPreviewReview, .settingsLicense, .deduplicateReviewWide, .deduplicateReviewCompact:
            return true
        default:
            return false
        }
    }

    private var preferredMainWindowSize: NSSize {
        switch self {
        case .historyPopulated:
            return NSSize(width: 1360, height: 1200)
        case .setupIncompleteRun, .setupReady, .runPreviewReview, .healthDashboard, .watchedSources, .photosImport, .profilesPopulated:
            return NSSize(width: 1360, height: 920)
        case .settingsSections, .settingsLayout, .settingsPerformance, .settingsDeduplicate, .settingsLicense, .settingsDiagnostics:
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

    /// Content-height floor for the main window while a scenario runs.
    ///
    /// The shipping floor (`DesignTokens.Window.mainMinHeight`, 700pt) plus the
    /// titlebar and toolbar is taller than the visible area of a small runner
    /// display (the macOS 15 runners), which left the bottom of the window
    /// under the Dock where nothing is hittable. Scenarios lower it so the window can shrink to fit;
    /// every scenario's content scrolls, so nothing is lost.
    static let mainWindowMinHeight: CGFloat = 520

    /// Overrides the display's visible area, as `WIDTHxHEIGHT` in points, so a
    /// large development display can reproduce a small CI runner's geometry.
    static let visibleSizeOverrideKey = "CHRONOFRAME_UI_TEST_VISIBLE_SIZE"

    /// Forces the app to `light` or `dark` regardless of the machine's appearance, so a
    /// development Mac in dark mode can reproduce a runner's light-mode audit.
    static let appearanceOverrideKey = "CHRONOFRAME_UI_TEST_APPEARANCE"

    /// The content size to ask the window for: the scenario's preferred size,
    /// reduced to whatever fits inside `visible` once the window chrome is
    /// counted. Never below `minimum`, because the hosted view cannot lay out
    /// smaller; an unavoidable overflow is left to the caller.
    static func fittedContentSize(
        preferred: NSSize,
        chrome: NSSize,
        visible: NSSize,
        minimum: NSSize
    ) -> NSSize {
        NSSize(
            width: max(minimum.width, min(preferred.width, visible.width - chrome.width)),
            height: max(minimum.height, min(preferred.height, visible.height - chrome.height))
        )
    }

    /// Moves `frame` the least distance that puts it inside `visible`; a frame
    /// larger than `visible` is pinned to its top-left corner.
    static func frame(_ frame: NSRect, clampedTo visible: NSRect) -> NSRect {
        var origin = frame.origin
        origin.x = max(visible.minX, min(origin.x, visible.maxX - frame.width))
        origin.y = min(visible.maxY - frame.height, max(origin.y, visible.minY))
        return NSRect(origin: origin, size: frame.size)
    }

    static func visibleSizeOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NSSize? {
        guard let raw = environment[visibleSizeOverrideKey] else { return nil }
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return NSSize(width: parts[0], height: parts[1])
    }

    static func appearanceOverride(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NSAppearance.Name? {
        switch environment[appearanceOverrideKey]?.lowercased() {
        case "light": return .aqua
        case "dark": return .darkAqua
        default: return nil
        }
    }

    @MainActor
    static func configureCurrentWindow(for scenario: UITestScenario?, isSettings: Bool = false) {
        guard let scenario else { return }

        DispatchQueue.main.async {
            if let name = appearanceOverride() {
                NSApp.appearance = NSAppearance(named: name)
            }
            guard let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.last else { return }
            let preferred = isSettings ? scenario.preferredSettingsWindowSize : scenario.preferredMainWindowSize

            // The preferred sizes assume a desktop-class display. On a smaller
            // one (the macOS 15 runners, whose window was placed at x = -168) a fixed-size
            // window spills past the screen edge and under the Dock, and the
            // controls there stop being hittable. Fit it to the visible area.
            let screenVisible = (window.screen ?? NSScreen.main)?.visibleFrame
            let visible: NSRect? = screenVisible.map { area in
                guard let override = visibleSizeOverride() else { return area }
                return NSRect(
                    x: area.minX, y: area.maxY - override.height,
                    width: override.width, height: override.height
                )
            }
            var size = preferred
            if let visible {
                let chrome = NSSize(
                    width: window.frame.width - window.contentRect(forFrameRect: window.frame).width,
                    height: window.frame.height - window.contentRect(forFrameRect: window.frame).height
                )
                size = fittedContentSize(
                    preferred: preferred,
                    chrome: chrome,
                    visible: visible.size,
                    minimum: window.contentMinSize
                )
            }
            window.setContentSize(size)
            window.center()
            if let visible {
                window.setFrame(frame(window.frame, clampedTo: visible), display: true)
            }
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
