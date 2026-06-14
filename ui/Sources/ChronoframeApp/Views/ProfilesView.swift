#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

struct ProfilesView: View {
    enum DisplayMode {
        case main
        case settings
    }

    let appState: AppState
    let displayMode: DisplayMode
    @ObservedObject private var setupStore: SetupStore

    init(appState: AppState, displayMode: DisplayMode = .main) {
        self.appState = appState
        self.displayMode = displayMode
        self._setupStore = ObservedObject(wrappedValue: appState.setupStore)
    }

    var body: some View {
        content
            .modifier(ProfilesPresentationModifier(displayMode: displayMode))
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionSpacing) {
                headerStrip
                saveCurrentPaths
                savedProfilesGrid
            }
            .padding(DesignTokens.Layout.contentPadding)
            .frame(maxWidth: DesignTokens.Layout.archiveMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    // MARK: - Header strip (replaces hero card)

    private var headerStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Profiles")
                    .scaledFont(.title)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

                Text(summaryMessage)
                    .scaledFont(.subtitle)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            if displayMode == .main {
                Button("Return to Setup") {
                    appState.navigate(to: .organize(.setup))
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var summaryMessage: String {
        if setupStore.profiles.isEmpty {
            return "Save the current source and destination to create your first reusable profile."
        }
        if setupStore.usingProfile {
            return "Active profile: \(setupStore.selectedProfileName)."
        }
        return "\(setupStore.profiles.count) saved · manual paths in use."
    }

    // MARK: - Save current paths

    private var saveCurrentPaths: some View {
        DarkroomPanel(variant: .panel) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                SectionHeading(
                    title: "Save Current Paths",
                    message: "Capture the source and destination configured in Setup."
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        TextField("Profile name", text: $setupStore.newProfileName)
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            appState.saveCurrentPathsAsProfile()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                        TextField("Profile name", text: $setupStore.newProfileName)
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            appState.saveCurrentPathsAsProfile()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                VStack(alignment: .leading, spacing: 0) {
                    currentPathRow(label: "Source", value: setupStore.sourcePath)
                    Rectangle()
                        .fill(DesignTokens.ColorSystem.hairline)
                        .frame(height: 0.5)
                    currentPathRow(label: "Destination", value: setupStore.destinationPath)
                }
            }
        }
    }

    private func currentPathRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            Text(label)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.captionText)
                .tracking(0.6)
                .frame(width: 96, alignment: .leading)

            Text(value.isEmpty ? "Not set" : value)
                .scaledFont(.mono)
                .foregroundStyle(value.isEmpty ? DesignTokens.ColorSystem.captionText : DesignTokens.ColorSystem.inkPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    // MARK: - Saved profiles grid

    private var savedProfilesGrid: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
            SectionHeading(
                title: "Saved Profiles",
                message: setupStore.profiles.isEmpty
                    ? "No profiles yet — save one above to reuse it later."
                    : "Use activates a profile in Setup. Overwrite refreshes it with the current paths."
            )

            if setupStore.profiles.isEmpty {
                EmptyStateView(
                    title: "No Saved Profiles",
                    message: "Save the current source and destination to create a reusable setup that works in both the app and the CLI.",
                    systemImage: "bookmark"
                )
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 280, maximum: 380), spacing: DesignTokens.Layout.cardSpacing, alignment: .top)
                    ],
                    alignment: .leading,
                    spacing: DesignTokens.Layout.cardSpacing
                ) {
                    ForEach(setupStore.profiles) { profile in
                        ProfileTile(
                            profile: profile,
                            isActive: profile.name == setupStore.selectedProfileName && setupStore.usingProfile,
                            onUse: {
                                appState.useProfile(named: profile.name)
                                appState.navigate(to: .organize(.setup))
                            },
                            onOverwrite: { appState.overwriteProfile(named: profile.name) },
                            onDelete: { appState.deleteProfile(named: profile.name) }
                        )
                    }
                }
            }
        }
    }
}

private struct ProfilesPresentationModifier: ViewModifier {
    let displayMode: ProfilesView.DisplayMode

    func body(content: Content) -> some View {
        switch displayMode {
        case .main:
            content
                .darkroom()
                .navigationTitle("Profiles")
        case .settings:
            content
        }
    }
}

// MARK: - Profile tile

private struct ProfileTile: View {
    let profile: Profile
    let isActive: Bool
    let onUse: () -> Void
    let onOverwrite: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        DarkroomPanel(variant: .panel) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
                    Text(profile.name)
                        .scaledFont(.cardTitle)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .accessibilityIdentifier(AccessibilityIdentifiers.profileName(profile.name))

                    Spacer(minLength: DesignTokens.Spacing.sm)

                    if isActive {
                        Circle()
                            .fill(DesignTokens.ColorSystem.statusActive)
                            .frame(width: 7, height: 7)
                            .accessibilityIdentifier(AccessibilityIdentifiers.activeProfileBadge)
                            .accessibilityLabel("Active")
                            // A graphical status dot → image role. `.isStaticText`
                            // on a text-less shape gets pruned (it dropped the
                            // element from the AX tree and broke the XCUITest
                            // query); `.isImage` keeps it present and queryable.
                            .accessibilityAddTraits(.isImage)
                    }

                    Menu {
                        Button("Overwrite with Current Paths", action: onOverwrite)
                        Divider()
                        Button("Delete", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DesignTokens.ColorSystem.captionText)
                            .frame(width: 22, height: 22)
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .opacity(isHovering || isActive ? 1 : 0.5)
                    .accessibilityActionsMenu(
                        label: "Actions for \(profile.name)",
                        hint: "Overwrite or delete this saved profile."
                    )
                }

                VStack(alignment: .leading, spacing: 0) {
                    pathRow(icon: "arrow.up.forward", label: "From", spokenLabel: "Source folder", value: profile.sourcePath)
                    Rectangle()
                        .fill(DesignTokens.ColorSystem.hairline)
                        .frame(height: 0.5)
                    pathRow(icon: "arrow.down.forward", label: "To", spokenLabel: "Destination folder", value: profile.destinationPath)
                }

                Button(action: onUse) {
                    Text(isActive ? "Open in Setup" : "Use")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }
        }
        .onHover { isHovering = $0 }
        .accessibilityElement(children: .contain)
    }

    private func pathRow(icon: String, label: String, spokenLabel: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(DesignTokens.ColorSystem.captionText)
                .frame(width: 14)
                .accessibilityHidden(true)

            Text(label)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.captionText)
                .tracking(0.6)
                .frame(width: 36, alignment: .leading)

            Text(value)
                .scaledFont(.mono)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}
