#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import SwiftUI

/// The groups of identical files, largest redundant total first as the store delivers them.
/// Selecting a row only remembers the selection; it never reads a file.
struct NASExactGroupListView: View {
    @ObservedObject var store: NASWorkspaceStore
    let viewModel: NASLibraryViewModel

    var body: some View {
        List(selection: selection) {
            ForEach(store.snapshot?.groups ?? []) { group in
                row(group)
                    .tag(group.digest)
            }
        }
        .listStyle(.inset)
        .accessibilityIdentifier(AccessibilityIdentifiers.NAS.groupList)
        .accessibilityLabel(NASAccessibilityText.label(forIdentifier: AccessibilityIdentifiers.NAS.groupList))
    }

    private var selection: Binding<String?> {
        Binding(
            get: { store.snapshot?.selectedDigest },
            set: { viewModel.select(digest: $0) }
        )
    }

    private func row(_ group: NASExactGroup) -> some View {
        let keeper = store.snapshot?.choices[group.digest]?.keeperRelativePath
        let stale = store.isChoiceStale(group)
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: Self.fileName(group.memberRelativePaths.sorted().first ?? ""))
                .scaledFont(.body, weight: .semibold)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: "\(group.memberRelativePaths.count) copies, \(ByteCountFormatter.string(fromByteCount: group.size, countStyle: .file)) each")
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            if stale {
                Text(LocalizedStringKey(NASLibraryCopy.keeperStale), bundle: .module)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
            } else if keeper == nil {
                Text(LocalizedStringKey(NASLibraryCopy.keeperNone), bundle: .module)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            } else if let keeper {
                Text(verbatim: Self.fileName(keeper))
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NASAccessibilityText.groupRow(group: group, keeper: keeper, isChoiceStale: stale))
        .accessibilityIdentifier(AccessibilityIdentifiers.NAS.groupRow)
    }

    private static func fileName(_ relativePath: String) -> String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }
}
