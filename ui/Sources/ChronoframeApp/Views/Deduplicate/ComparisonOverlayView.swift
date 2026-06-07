#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit
import SwiftUI

struct ComparisonOverlayView: View {
    let leftPath: String
    let rightPath: String
    @State private var mode: ComparisonMode = .slider
    @State private var sliderPosition: CGFloat = 0.5
    @Environment(\.dismiss) private var dismiss

    enum ComparisonMode: String, CaseIterable {
        case slider
        case difference
        case flicker

        var label: String {
            switch self {
            case .slider: return "Slider"
            case .difference: return "Difference"
            case .flicker: return "Flicker"
            }
        }

        var icon: String {
            switch self {
            case .slider: return "rectangle.split.2x1"
            case .difference: return "square.stack.3d.up"
            case .flicker: return "bolt.square"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            comparisonContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(DesignTokens.ColorSystem.imageStage)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(DesignTokens.ColorSystem.canvas)
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                imagePairLabel
                Spacer()
                modePicker
                Button("Done") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
                imagePairLabel
                HStack {
                    modePicker
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(.bar)
    }

    private var modePicker: some View {
        Picker("Mode", selection: $mode) {
            ForEach(ComparisonMode.allCases, id: \.self) { m in
                Label(m.label, systemImage: m.icon).tag(m)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: 300)
        .accessibilityLabel("Comparison mode")
    }

    private var imagePairLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            Label(URL(fileURLWithPath: leftPath).lastPathComponent, systemImage: "a.circle")
                .lineLimit(1)
                .truncationMode(.middle)
            Image(systemName: "arrow.left.arrow.right")
                .font(.caption)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            Label(URL(fileURLWithPath: rightPath).lastPathComponent, systemImage: "b.circle")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .font(.caption)
        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
    }

    @ViewBuilder
    private var comparisonContent: some View {
        switch mode {
        case .slider:
            SliderComparisonView(leftPath: leftPath, rightPath: rightPath, position: $sliderPosition)
        case .difference:
            DifferenceComparisonView(leftPath: leftPath, rightPath: rightPath)
        case .flicker:
            FlickerComparisonView(leftPath: leftPath, rightPath: rightPath)
        }
    }
}

// MARK: - Slider Comparison

private struct SliderComparisonView: View {
    let leftPath: String
    let rightPath: String
    @Binding var position: CGFloat
    @State private var leftImage: NSImage?
    @State private var rightImage: NSImage?
    @State private var leftFinishedLoading = false
    @State private var rightFinishedLoading = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let rightImage {
                    Image(nsImage: rightImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                }
                if let leftImage {
                    Image(nsImage: leftImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipShape(
                            HorizontalClip(fraction: position)
                        )
                }
                if leftFinishedLoading && rightFinishedLoading && leftImage == nil && rightImage == nil {
                    ComparisonUnavailableView(title: "Could not load comparison images")
                } else {
                    if leftFinishedLoading && leftImage == nil {
                        comparisonStatusLabel("Keeper preview unavailable", systemImage: "photo.badge.exclamationmark")
                            .position(x: max(104, geometry.size.width * 0.25), y: geometry.size.height / 2)
                    }
                    if rightFinishedLoading && rightImage == nil {
                        comparisonStatusLabel("Compare preview unavailable", systemImage: "photo.badge.exclamationmark")
                            .position(x: min(geometry.size.width - 112, geometry.size.width * 0.75), y: geometry.size.height / 2)
                    }
                }
                Rectangle()
                    .fill(DesignTokens.ColorSystem.dividerEmphasis)
                    .frame(width: 2)
                    .position(x: geometry.size.width * position, y: geometry.size.height / 2)
                    .shadow(radius: 2)

                comparisonLabel("Keeper", systemImage: "star.fill")
                    .position(x: 56, y: geometry.size.height - 28)

                comparisonLabel("Compare", systemImage: "circle.dashed")
                    .position(x: geometry.size.width - 62, y: geometry.size.height - 28)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        position = ComparisonSlider.fraction(forLocationX: value.location.x, width: geometry.size.width)
                    }
            )
            // Keyboard: nudge the divider with the arrow keys. Two invisible
            // buttons because stacking `.keyboardShortcut` on one button drops
            // all but the last (see RapidTriageView / ClusterDetailPane).
            .background {
                Group {
                    Button { position = ComparisonSlider.adjusted(position, by: -ComparisonSlider.step) } label: { EmptyView() }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                    Button { position = ComparisonSlider.adjusted(position, by: ComparisonSlider.step) } label: { EmptyView() }
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
            }
            // VoiceOver: expose the divider as an adjustable value.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Comparison divider")
            .accessibilityValue(ComparisonSlider.accessibilityValue(position))
            .accessibilityHint("Reveals more of the keeper or compare image. Use the arrow keys to adjust.")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: position = ComparisonSlider.adjusted(position, by: ComparisonSlider.step)
                case .decrement: position = ComparisonSlider.adjusted(position, by: -ComparisonSlider.step)
                @unknown default: break
                }
            }
        }
        .task(id: leftPath) {
            leftFinishedLoading = false
            leftImage = await loadImage(at: leftPath)
            leftFinishedLoading = true
        }
        .task(id: rightPath) {
            rightFinishedLoading = false
            rightImage = await loadImage(at: rightPath)
            rightFinishedLoading = true
        }
    }

    private func comparisonLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.black.opacity(0.44), in: Capsule())
    }

    private func comparisonStatusLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.78))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.black.opacity(0.36), in: Capsule())
    }
}

private struct HorizontalClip: Shape {
    var fraction: CGFloat

    func path(in rect: CGRect) -> Path {
        Path(CGRect(x: 0, y: 0, width: rect.width * fraction, height: rect.height))
    }
}

// MARK: - Difference Comparison

private struct DifferenceComparisonView: View {
    let leftPath: String
    let rightPath: String
    @State private var differenceImage: NSImage?
    @State private var loading = true

    var body: some View {
        ZStack {
            if let differenceImage {
                Image(nsImage: differenceImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if loading {
                ProgressView("Computing difference…")
            } else {
                Text("Could not generate difference image")
                    // On the dark image stage — keep light in both appearances.
                    .foregroundStyle(Color.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.lg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Difference comparison")
        .accessibilityValue(loading ? "Computing difference image" : (differenceImage == nil ? "Difference image unavailable" : "Difference image ready"))
        .task {
            differenceImage = await DifferenceImageGenerator.generate(
                leftURL: URL(fileURLWithPath: leftPath),
                rightURL: URL(fileURLWithPath: rightPath)
            )
            loading = false
        }
    }
}

// MARK: - Flicker Comparison

private struct FlickerComparisonView: View {
    let leftPath: String
    let rightPath: String
    @State private var showingLeft = true
    @State private var leftImage: NSImage?
    @State private var rightImage: NSImage?
    @State private var leftFinishedLoading = false
    @State private var rightFinishedLoading = false
    @State private var flickerTask: Task<Void, Never>?
    @State private var wantsPlayback = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isPlaying: Bool {
        FlickerComparisonPlayback.effectiveIsPlaying(
            requestedPlaying: wantsPlayback,
            reduceMotion: reduceMotion
        )
    }

    var body: some View {
        ZStack {
            if showingLeft, let leftImage {
                Image(nsImage: leftImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if !showingLeft, let rightImage {
                Image(nsImage: rightImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if currentSideFinishedLoading {
                ComparisonUnavailableView(
                    title: showingLeft ? "Keeper preview unavailable" : "Compare preview unavailable"
                )
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Spacing.lg)
        .overlay(alignment: .bottom) {
            HStack(spacing: 8) {
                Button {
                    showingLeft = true
                } label: {
                    Label("Keeper", systemImage: "a.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.leftArrow, modifiers: [])

                Text(showingLeft ? "A (Keeper)" : "B")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.44), in: Capsule())

                Button {
                    showingLeft = false
                } label: {
                    Label("Compare", systemImage: "b.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.rightArrow, modifiers: [])

                Button {
                    wantsPlayback.toggle()
                    updateFlickerTask()
                } label: {
                    Label(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(reduceMotion)
                .keyboardShortcut(.space, modifiers: [])
                .accessibilityHint(reduceMotion ? "Automatic flicker is disabled because Reduce Motion is on" : "Starts or pauses automatic comparison flicker")
            }
            .padding(.bottom, 12)
        }
        .task(id: leftPath) {
            leftFinishedLoading = false
            leftImage = await loadImage(at: leftPath)
            leftFinishedLoading = true
        }
        .task(id: rightPath) {
            rightFinishedLoading = false
            rightImage = await loadImage(at: rightPath)
            rightFinishedLoading = true
        }
        .onAppear { updateFlickerTask() }
        .onChange(of: reduceMotion) { _ in updateFlickerTask() }
        .onDisappear { flickerTask?.cancel() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Flicker comparison")
        .accessibilityValue(FlickerComparisonPlayback.accessibilityValue(
            isShowingKeeper: showingLeft,
            isPlaying: isPlaying
        ))
        .accessibilityHint(reduceMotion ? "Automatic flicker is disabled because Reduce Motion is on" : "Use Play to start automatic flicker, or use the Keeper and Compare buttons manually")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                showingLeft = false
            case .decrement:
                showingLeft = true
            @unknown default:
                break
            }
        }
    }

    private var currentSideFinishedLoading: Bool {
        showingLeft ? leftFinishedLoading : rightFinishedLoading
    }

    private func updateFlickerTask() {
        if !isPlaying {
            flickerTask?.cancel()
            flickerTask = nil
            return
        }

        // Cancel any previous task before starting a new one. SwiftUI may
        // call `.onAppear` again before `.onDisappear` runs the
        // cancellation, and a parent re-evaluation can also drop and
        // re-create this body — both situations would otherwise leak an
        // orphaned task that keeps toggling `showingLeft` and doubles
        // the visible flicker rate.
        flickerTask?.cancel()
        flickerTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(FlickerComparisonPlayback.automaticIntervalMilliseconds))
                guard !Task.isCancelled else { break }
                showingLeft.toggle()
            }
        }
    }
}

// MARK: - Helpers

private struct ComparisonUnavailableView: View {
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.white.opacity(0.48))
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
        }
        .padding(DesignTokens.Spacing.lg)
    }
}

/// Asynchronous image loader for the comparison overlays. `NSImage(contentsOfFile:)`
/// is blocking and can take hundreds of milliseconds to seconds for
/// multi-megapixel RAW/HEIC inputs; running it inside a MainActor-isolated
/// `.task { … }` would freeze the UI. Read the file bytes off the main
/// thread (Data is Sendable), then hand them to `NSImage(data:)` back
/// on the main actor — keeps the heavy I/O off the main thread without
/// dragging non-Sendable `NSImage` across an actor boundary.
@MainActor
private func loadImage(at path: String) async -> NSImage? {
    let data = await Task.detached(priority: .userInitiated) {
        try? Data(contentsOf: URL(fileURLWithPath: path))
    }.value
    guard let data else { return nil }
    return NSImage(data: data)
}
