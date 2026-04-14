import ChronoframeAppCore
import SwiftUI

struct RunHistoryView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Run History")
                    .font(.largeTitle.weight(.bold))
                Text("Chronoframe reads existing artifacts from the destination root without changing them.")
                    .foregroundStyle(.secondary)
            }

            if appState.historyStore.entries.isEmpty {
                EmptyStateView(
                    title: "No Artifacts Yet",
                    message: "Run a preview or transfer, then open this section to inspect reports, receipts, and logs.",
                    systemImage: "clock.arrow.circlepath"
                )
            } else {
                List(appState.historyStore.entries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.title)
                                .font(.headline)
                            Text(entry.path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }

                        Spacer()

                        Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Open") {
                            appState.openHistoryEntry(entry)
                        }

                        Button("Reveal") {
                            appState.revealHistoryEntry(entry)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(24)
        .navigationTitle("Run History")
    }
}
