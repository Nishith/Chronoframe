#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import SwiftUI

/// Totals for the latest assessment, the folders that were checked, and everything that
/// wasn't checked. Collapsed by default so the groups stay in front.
struct NASFolderSummaryView: View {
    let snapshot: NASAssessmentSnapshot
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                totals
                if !snapshot.issues.isEmpty {
                    issues
                }
                if !snapshot.directories.isEmpty {
                    directories
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(NASLibraryCopy.summaryTitle), bundle: .module)
                    .scaledFont(.body, weight: .semibold)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                Text(verbatim: NASLibraryCopy.redundantBytesLabel(bytes: snapshot.summary.redundantLogicalBytes))
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.NAS.folderSummary)
        .accessibilityLabel(NASAccessibilityText.folderSummary(snapshot.summary))
    }

    private var totals: some View {
        let counts = snapshot.summary.counts
        return VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(counts.directoriesAssessed) folders checked")
            Text(verbatim: "\(counts.mediaFiles) photos and videos, \(ByteCountFormatter.string(fromByteCount: counts.mediaBytes, countStyle: .file))")
            Text(verbatim: "\(snapshot.summary.exactGroupCount) groups of identical files")
        }
        .scaledFont(.body)
        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
    }

    private var issues: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(NASLibraryCopy.issuesTitle), bundle: .module)
                .scaledFont(.label, weight: .semibold)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(snapshot.issues.enumerated()), id: \.offset) { _, issue in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(verbatim: issue.relativePath.isEmpty ? "/" : issue.relativePath)
                                .scaledFont(.body)
                                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(verbatim: issue.detail)
                                .scaledFont(.label)
                                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 140)
        }
    }

    private var directories: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(Array(snapshot.directories.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(verbatim: row.relativePath.isEmpty ? "/" : row.relativePath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(verbatim: "\(row.mediaFileCount)")
                            .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    }
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
            }
        }
        .frame(maxHeight: 140)
    }
}
