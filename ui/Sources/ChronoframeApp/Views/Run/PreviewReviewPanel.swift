#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit
import SwiftUI
import QuickLook

struct PreviewReviewPanel: View {
    let model: RunWorkspaceModel
    @ObservedObject var store: PreviewReviewStore
    let appState: AppState

    @State private var selectedItemPath: String? = nil
    @State private var quickLookURL: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeridianSurfaceCard(style: .inner, tint: model.context.previewReviewIsStale ? DesignTokens.Color.warning : DesignTokens.Color.sky) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Review Before Transfer")
                                .scaledFont(.cardTitle)
                            Text(headerMessage)
                                .scaledFont(.subtitle)
                                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        }

                        Spacer()

                        Button {
                            Task { await appState.startPreview() }
                        } label: {
                            Label("Rebuild Preview", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(!model.context.canStartRun)

                        Button {
                            Task { await store.acceptVisibleSuggestions() }
                        } label: {
                            Label("Accept Visible Events", systemImage: "text.badge.checkmark")
                        }
                        .disabled(!store.filteredItems.contains { $0.eventSuggestion?.suggestedName != nil })
                    }

                    HStack(spacing: 10) {
                        ForEach(model.previewReviewSummaryTiles) { tile in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(tile.title)
                                    .scaledFont(.label)
                                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                                Text(tile.value)
                                    .scaledFont(.cardTitle)
                                    .monospacedDigit()
                                    .foregroundStyle(tile.tone.color)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }

            Picker("Review Filter", selection: $store.filter) {
                ForEach(PreviewReviewFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(AccessibilityIdentifiers.previewReviewFilter)

            if store.isLoading {
                ProgressView("Loading review items...")
            } else if let errorMessage = store.errorMessage {
                EmptyStateView(
                    title: "Review Could Not Load",
                    message: errorMessage,
                    systemImage: "exclamationmark.triangle"
                )
            } else if store.items.isEmpty {
                EmptyStateView(
                    title: "No Review Artifact Yet",
                    message: "Run a preview to generate reviewable copy decisions.",
                    systemImage: "doc.text.magnifyingglass"
                )
            } else if store.filteredItems.isEmpty {
                EmptyStateView(
                    title: "Nothing in This Filter",
                    message: "Choose a different filter to inspect more preview items.",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(store.filteredItems.prefix(250)) { item in
                        PreviewReviewRow(
                            item: item,
                            store: store,
                            isSelected: selectedItemPath == item.sourcePath,
                            onSelect: { selectedItemPath = item.sourcePath }
                        )
                    }
                }
                .background {
                    Button("") {
                        if let path = selectedItemPath {
                            quickLookURL = URL(fileURLWithPath: path)
                        }
                    }
                    .keyboardShortcut(.space, modifiers: [])
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .quickLookPreview($quickLookURL)
            }
        }
    }

    private var headerMessage: String {
        if store.isStale {
            return "Corrections are saved. Rebuild the preview before transfer."
        }
        let summary = store.summary
        if summary.needsAttentionCount > 0 {
            return "\(summary.needsAttentionCount.formatted()) items need attention. Originals stay untouched."
        }
        return "The plan is ready to inspect. Originals stay untouched."
    }
}

private struct PreviewReviewRow: View {
    let item: PreviewReviewItem
    @ObservedObject var store: PreviewReviewStore
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var selectedDate: Date
    @State private var eventName: String

    init(item: PreviewReviewItem, store: PreviewReviewStore, isSelected: Bool, onSelect: @escaping () -> Void) {
        self.item = item
        self.store = store
        self.isSelected = isSelected
        self.onSelect = onSelect
        self._selectedDate = State(initialValue: item.resolvedDate ?? Date())
        self._eventName = State(initialValue: item.acceptedEventName ?? item.eventSuggestion?.suggestedName ?? "")
    }

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: isSelected ? DesignTokens.Color.sky : tint) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    PreviewReviewThumbnail(path: item.sourcePath)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(URL(fileURLWithPath: item.sourcePath).lastPathComponent)
                            .scaledFont(.subtitle, weight: .semibold)
                            .lineLimit(1)

                        Text(item.sourcePath)
                            .scaledFont(.mono)
                            .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
                            Label(item.status.title, systemImage: statusSymbol)
                            Text("\(item.dateSource.title) · \(item.dateConfidence.title)")
                            if !item.issues.isEmpty {
                                Text(item.issues.map(\.title).joined(separator: ", "))
                            }
                        }
                        .scaledFont(.label)
                        .foregroundStyle(tint)

                    }

                    Spacer(minLength: 12)
                }

                visualPlan

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .center, spacing: 10) {
                        editorControls
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        editorControls
                    }
                }
            }
        }
        // Resync @State after Save. SwiftUI initialises @State only on
        // first construction, so when the store rebuilds `item` with a
        // new `acceptedEventName`/`resolvedDate` and the row keeps the
        // same identity (same `item.id`), the DatePicker/TextField
        // bindings stay attached to the stale values. Mirror the
        // backing values from `item` whenever it changes.
        //
        // Using the single-arg `onChange(of:perform:)` form because
        // the package targets macOS 13 and the two-arg form is 14+.
        .onChange(of: item) { newItem in
            selectedDate = newItem.resolvedDate ?? selectedDate
            eventName = newItem.acceptedEventName
                ?? newItem.eventSuggestion?.suggestedName
                ?? eventName
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onSelect()
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(item.sourcePath, inFileViewerRootedAtPath: "")
            }
        }
    }

    private var visualPlan: some View {
        HStack(alignment: .top, spacing: 10) {
            planEndpoint(title: "Source", path: item.sourcePath, systemImage: "folder")
            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .padding(.top, 18)
            planEndpoint(
                title: destinationTitle,
                path: item.plannedDestinationPath ?? destinationFallback,
                systemImage: item.status == .alreadyInDestination ? "tray.full" : "folder.badge.plus"
            )
        }
        .padding(8)
        .background(DesignTokens.ColorSystem.hairline.opacity(0.35), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Preview plan from \(item.sourcePath) to \(item.plannedDestinationPath ?? destinationFallback)")
    }

    private var destinationTitle: String {
        switch item.status {
        case .ready:
            return "Will Copy To"
        case .alreadyInDestination:
            return "Already Exists"
        case .duplicate:
            return "Duplicate Route"
        case .hashError:
            return "Needs Attention"
        }
    }

    private var destinationFallback: String {
        switch item.status {
        case .alreadyInDestination:
            return "Destination already contains a matching file"
        case .duplicate:
            return "Duplicate handling will route this away from the main archive"
        case .hashError:
            return "Chronoframe needs a readable file before it can plan this item"
        case .ready:
            return "Destination path will appear after preview rebuild"
        }
    }

    private func planEndpoint(title: String, path: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(.label, weight: .semibold)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                Text(path)
                    .scaledFont(.mono)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var editorControls: some View {
        DatePicker("Date", selection: $selectedDate, displayedComponents: [.date])
            .labelsHidden()
            .frame(width: 150)

        TextField("Event", text: $eventName)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 140, maxWidth: 220)

        Button {
            Task {
                await store.saveOverride(for: item, captureDate: selectedDate, eventName: eventName)
            }
        } label: {
            Label("Save", systemImage: "checkmark.circle")
        }
        .disabled(item.identityRawValue == nil)

        if item.eventSuggestion?.suggestedName != nil {
            Button {
                Task { await store.acceptSuggestion(for: item) }
            } label: {
                Label("Accept Event", systemImage: "text.badge.checkmark")
            }
        }
    }

    private var tint: Color {
        if item.issues.contains(.hashError) {
            return DesignTokens.Color.danger
        }
        if item.needsAttention || item.status == .duplicate {
            return DesignTokens.Color.warning
        }
        if item.status == .alreadyInDestination {
            return DesignTokens.Color.inkMuted
        }
        return DesignTokens.Status.ready
    }

    private var statusSymbol: String {
        switch item.status {
        case .ready:
            return "checkmark.circle"
        case .alreadyInDestination:
            return "tray.full"
        case .duplicate:
            return "doc.on.doc"
        case .hashError:
            return "exclamationmark.triangle"
        }
    }
}

private struct PreviewReviewThumbnail: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: path) {
            image = nil
            guard let cgImage = await ThumbnailRenderer.cgImage(
                for: URL(fileURLWithPath: path),
                size: CGSize(width: 52, height: 52),
                scale: NSScreen.main?.backingScaleFactor ?? 2
            ) else {
                return
            }
            image = NSImage(cgImage: cgImage, size: NSSize(width: 52, height: 52))
        }
    }
}
