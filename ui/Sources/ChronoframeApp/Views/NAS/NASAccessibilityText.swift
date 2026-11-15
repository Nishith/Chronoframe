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
        AccessibilityIdentifiers.NAS.chooseFolder: "Choose Folder…. Pick the top folder of your photo library on a network share.",
        AccessibilityIdentifiers.NAS.startAssessment: "Assess Library. Chronoframe reads the library to find identical copies and changes nothing on the NAS.",
        AccessibilityIdentifiers.NAS.stop: "Stop. Stops the assessment.",
        AccessibilityIdentifiers.NAS.reconnect: "Reconnect. Checks the connection to your NAS again.",
        AccessibilityIdentifiers.NAS.confirmIdentity: "This Is the Same Library. Confirms this share is the library you assessed before.",
        AccessibilityIdentifiers.NAS.groupList: "Groups of identical files",
        AccessibilityIdentifiers.NAS.groupRow: "Group of identical files",
        AccessibilityIdentifiers.NAS.loadPreview: "Load Preview. Shows the first file in this group. This may read the whole file over the network.",
        AccessibilityIdentifiers.NAS.keeperPicker: "Choose which copy you prefer to keep. The choice is saved on this Mac and nothing on the NAS changes.",
        AccessibilityIdentifiers.NAS.folderSummary: "Folder summary",
        AccessibilityIdentifiers.NAS.stateBanner: "Assessment status",
    ]

    /// The label for a control. `visibleTitle` is the title currently on screen for a button
    /// whose title changes (Assess Library becomes Assess Again); the label starts with it.
    static func label(forIdentifier identifier: String, visibleTitle: String? = nil) -> String {
        guard let base = controlLabels[identifier] else { return "" }
        guard let visibleTitle, let defaultTitle = visibleTitles[identifier], base.hasPrefix(defaultTitle) else { return base }
        return visibleTitle + base.dropFirst(defaultTitle.count)
    }

    /// The spoken status line for the state banner.
    static func stateBanner(_ state: NASWorkspaceState) -> String {
        NASLibraryCopy.bannerText(for: state)
    }

    /// One spoken line for a group row in the list.
    static func groupRow(group: NASExactGroup, keeper: String?, isChoiceStale: Bool) -> String {
        let count = group.memberRelativePaths.count
        let name = group.memberRelativePaths.sorted().first.map { fileName($0) } ?? "file"
        let size = ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file)
        var parts = ["\(count) identical copies of \(name), \(size) each"]
        if isChoiceStale {
            parts.append("Your earlier choice no longer matches these files")
        } else if let keeper {
            parts.append("Keeper chosen: \(fileName(keeper))")
        } else {
            parts.append(NASLibraryCopy.keeperNone)
        }
        return parts.joined(separator: ". ") + "."
    }

    /// The spoken folder summary. It says the byte total is a logical size, not freed space.
    static func folderSummary(_ summary: NASScanSummary) -> String {
        let folders = summary.counts.directoriesAssessed
        let media = summary.counts.mediaFiles
        let groups = summary.exactGroupCount
        let folderPhrase = folders == 1 ? "1 folder" : "\(folders) folders"
        let mediaPhrase = media == 1 ? "1 photo or video" : "\(media) photos and videos"
        let groupPhrase = groups == 1 ? "1 group of identical files" : "\(groups) groups of identical files"
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
