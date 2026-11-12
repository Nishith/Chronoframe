import SwiftUI

struct RunNextStepCard: View {
    let model: RunWorkspaceModel
    let appState: AppState

    var body: some View {
        MeridianSurfaceCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Next: remove extra copies")
                    .scaledFont(.cardTitle)

                Text(model.nextStepBody)
                    .scaledFont(.body)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Find Duplicates") {
                    appState.navigate(to: .deduplicate)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityIdentifiers.runNextStepFindDuplicates)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.runNextStepCard)
    }
}
