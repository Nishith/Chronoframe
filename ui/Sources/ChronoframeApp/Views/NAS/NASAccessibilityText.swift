#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import SwiftUI

/// The spoken VoiceOver descriptions for the NAS Library workspace.
///
/// Pure functions and a fixed table (no view state) so the wording can be unit-tested
/// without a running UI. Every control in the workspace has an entry in `controlLabels`;
/// there is intentionally no entry for an action that changes files on a NAS, because
/// the workspace offers none.
enum NASAccessibilityText {
    /// The visible title of each button. A control's label starts with it, so what
    /// VoiceOver says and what Voice Control hears match what is on screen.
    private static let visibleTitles: [String: String] = [
        AccessibilityIdentifiers.NAS.chooseFolder: NASLibraryCopy.chooseButton,
        AccessibilityIdentifiers.NAS.startAssessment: NASLibraryCopy.startButton,
        AccessibilityIdentifiers.NAS.stop: NASLibraryCopy.stopButton,
        AccessibilityIdentifiers.NAS.reconnect: NASLibraryCopy.reconnectButton,
        AccessibilityIdentifiers.NAS.confirmIdentity: NASLibraryCopy.confirmButton,
        AccessibilityIdentifiers.NAS.loadPreview: NASLibraryCopy.loadPreviewButton,
    ]

    /// One label per accessibility identifier in `AccessibilityIdentifiers.NAS`.
    static let controlLabels: [String: String] = [
        AccessibilityIdentifiers.NAS.chooseFolder: String(localized: "Choose Folder…. Pick the top folder of your photo library on a network share.", bundle: .module),
        AccessibilityIdentifiers.NAS.startAssessment: String(localized: "Assess Library. Chronoframe reads the library to find identical copies and changes nothing on the NAS.", bundle: .module),
        AccessibilityIdentifiers.NAS.stop: String(localized: "Stop. Stops the assessment.", bundle: .module),
        AccessibilityIdentifiers.NAS.reconnect: String(localized: "Reconnect. Checks the connection to your NAS again.", bundle: .module),
        AccessibilityIdentifiers.NAS.confirmIdentity: String(localized: "This Is the Same Library. Confirms this share is the library you assessed before.", bundle: .module),
        AccessibilityIdentifiers.NAS.groupList: String(localized: "Groups of identical files", bundle: .module),
        AccessibilityIdentifiers.NAS.groupRow: String(localized: "Group of identical files", bundle: .module),
        AccessibilityIdentifiers.NAS.loadPreview: String(localized: "Load Preview. Shows the first file in this group. This may read the whole file over the network.", bundle: .module),
        AccessibilityIdentifiers.NAS.keeperPicker: String(localized: "Choose which copy you prefer to keep. The choice is saved on this Mac and nothing on the NAS changes.", bundle: .module),
        AccessibilityIdentifiers.NAS.folderSummary: String(localized: "Folder summary", bundle: .module),
        AccessibilityIdentifiers.NAS.stateBanner: String(localized: "Assessment status", bundle: .module),
    ]

    /// The label for a control. `visibleTitle` is the title currently on screen for a button
    /// whose title changes (Assess Library becomes Assess Again); the label starts with it.
    static func label(forIdentifier identifier: String, visibleTitle: String? = nil) -> String {
        guard let base = controlLabels[identifier] else { return "" }
        guard let visibleTitle, let defaultKey = visibleTitles[identifier] else { return base }
        let defaultTitle = String(localized: String.LocalizationValue(defaultKey), bundle: .module)
        guard base.hasPrefix(defaultTitle) else { return base }
        return String(localized: String.LocalizationValue(visibleTitle), bundle: .module) + base.dropFirst(defaultTitle.count)
    }

    /// The spoken status line for the state banner.
    static func stateBanner(_ state: NASWorkspaceState) -> String {
        String(localized: String.LocalizationValue(NASLibraryCopy.bannerText(for: state)), bundle: .module)
    }

    /// One spoken line for a group row in the list.
    static func groupRow(group: NASExactGroup, keeper: String?, isChoiceStale: Bool) -> String {
        let count = group.memberRelativePaths.count
        let name = group.memberRelativePaths.sorted().first.map { fileName($0) } ?? String(localized: "file", bundle: .module)
        let size = ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file)
        var parts = [String(localized: "\(String(count)) identical copies of \(String(name)), \(String(size)) each", bundle: .module)]
        if isChoiceStale {
            parts.append(String(localized: "Your earlier choice no longer matches these files", bundle: .module))
        } else if let keeper {
            parts.append(String(localized: "Keeper chosen: \(String(fileName(keeper)))", bundle: .module))
        } else {
            parts.append(String(localized: String.LocalizationValue(NASLibraryCopy.keeperNone), bundle: .module))
        }
        return parts.joined(separator: ". ") + "."
    }

    /// The spoken folder summary. It says the byte total is a logical size, not freed space.
    static func folderSummary(_ summary: NASScanSummary) -> String {
        let folders = summary.counts.directoriesAssessed
        let media = summary.counts.mediaFiles
        let groups = summary.exactGroupCount
        let folderPhrase = folders == 1 ? String(localized: "1 folder", bundle: .module) : String(localized: "\(String(folders)) folders", bundle: .module)
        let mediaPhrase = media == 1 ? String(localized: "1 photo or video", bundle: .module) : String(localized: "\(String(media)) photos and videos", bundle: .module)
        let groupPhrase = groups == 1 ? String(localized: "1 group of identical files", bundle: .module) : String(localized: "\(String(groups)) groups of identical files", bundle: .module)
        return "\(folderPhrase), \(mediaPhrase), \(groupPhrase). "
            + NASLibraryCopy.redundantBytesLabel(bytes: summary.redundantLogicalBytes)
    }

    private static func fileName(_ relativePath: String) -> String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }
}

extension View {
    /// Applies a NAS control's accessibility identifier and its VoiceOver label together,
    /// so no control can carry one without the other.
    func nasControl(_ identifier: String, visibleTitle: String? = nil) -> some View {
        self
            .accessibilityIdentifier(identifier)
            .accessibilityLabel(NASAccessibilityText.label(forIdentifier: identifier, visibleTitle: visibleTitle))
    }
}
