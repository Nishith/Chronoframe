import SwiftUI
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Darkroom Panel (the new preferred surface component)

/// Variant of the new Darkroom-language panel.
enum DarkroomPanelVariant {
    /// Sits directly on the window canvas; transparent, no chrome.
    case canvas
    /// Vibrant panel with hairline border. The default.
    case panel
    /// Nested inset area: no background, just an indent.
    case inset
    /// Quiet elevated popover-style (used sparingly).
    case elevated
}

/// The new Darkroom panel. Replaces ``MeridianSurfaceCard``.
///
/// Rules:
/// - One elevated surface per screen max.
/// - Inner groupings use hairlines instead of nested panels.
/// - Shadows are reserved for modals/popovers.
struct DarkroomPanel<Content: View>: View {
    let variant: DarkroomPanelVariant
    let content: Content
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(variant: DarkroomPanelVariant = .panel, @ViewBuilder content: () -> Content) {
        self.variant = variant
        self.content = content()
    }

    var body: some View {
        let corner = cornerRadius
        let shape = RoundedRectangle(cornerRadius: corner, style: .continuous)

        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                backgroundView
                    .clipShape(shape)
            }
            .overlay(borderView(shape: shape))
    }

    private var cornerRadius: CGFloat {
        switch variant {
        case .canvas, .inset:
            return 0
        case .panel:
            return DesignTokens.Corner.card
        case .elevated:
            return DesignTokens.Corner.hero
        }
    }

    private var padding: CGFloat {
        switch variant {
        case .canvas, .inset:
            return 0
        case .panel:
            return DesignTokens.Layout.cardPadding
        case .elevated:
            return DesignTokens.Layout.heroPadding
        }
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch variant {
        case .canvas, .inset:
            Color.clear
        case .panel:
            if reduceTransparency {
                DesignTokens.ColorSystem.panel
            } else {
                Rectangle().fill(.thinMaterial)
            }
        case .elevated:
            if reduceTransparency {
                DesignTokens.ColorSystem.elevated
            } else {
                ZStack {
                    DesignTokens.ColorSystem.elevated
                    Rectangle().fill(.regularMaterial)
                }
            }
        }
    }

    @ViewBuilder
    private func borderView(shape: RoundedRectangle) -> some View {
        switch variant {
        case .canvas, .inset:
            EmptyView()
        case .panel, .elevated:
            shape.strokeBorder(
                AccessibleDesign.borderColor(
                    tint: nil,
                    style: .standard,
                    contrast: colorSchemeContrast
                ),
                lineWidth: AccessibleDesign.hairlineWidth(contrast: colorSchemeContrast)
            )
        }
    }
}

// MARK: - MeridianSurfaceCard (legacy — routed through DarkroomPanel)

enum MeridianSurfaceCardStyle {
    case hero
    case standard
    case inner
    case section

    var cornerRadius: CGFloat {
        switch self {
        case .hero:
            return DesignTokens.Corner.hero
        case .standard:
            return DesignTokens.Corner.card
        case .inner:
            return DesignTokens.Corner.innerCard
        case .section:
            return 0
        }
    }

    var padding: CGFloat {
        switch self {
        case .hero, .standard:
            return DesignTokens.Layout.cardPadding
        case .inner:
            return DesignTokens.Layout.compactPadding
        case .section:
            return 0
        }
    }
}

/// Legacy card component. Kept for source compatibility; visuals are now
/// routed through the Darkroom surface system — no gradients, no shadows,
/// just vibrancy + hairline.
struct MeridianSurfaceCard<Content: View>: View {
    let style: MeridianSurfaceCardStyle
    let tint: SwiftUI.Color?
    let content: Content
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(
        style: MeridianSurfaceCardStyle = .standard,
        tint: SwiftUI.Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.style = style
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)

        content
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                backgroundView
                    .clipShape(shape)
            }
            .overlay(
                shape.strokeBorder(
                    borderColor,
                    lineWidth: AccessibleDesign.hairlineWidth(contrast: colorSchemeContrast)
                )
                .allowsHitTesting(false)
            )
    }

    @ViewBuilder
    private var backgroundView: some View {
        switch style {
        case .hero:
            if reduceTransparency {
                Rectangle().fill(DesignTokens.ColorSystem.panel)
                    .overlay {
                        if let tint {
                            Rectangle().fill(tint.opacity(AccessibleDesign.tintOverlayOpacity(
                                style: .hero,
                                contrast: colorSchemeContrast
                            )))
                        }
                    }
            } else {
                ZStack {
                    Rectangle().fill(.thinMaterial)
                    if let tint {
                        Rectangle().fill(tint.opacity(AccessibleDesign.tintOverlayOpacity(
                            style: .hero,
                            contrast: colorSchemeContrast
                        )))
                    }
                }
            }
        case .standard:
            if reduceTransparency {
                Rectangle().fill(DesignTokens.ColorSystem.panel)
            } else {
                Rectangle().fill(.thinMaterial)
            }
        case .inner:
            if let tint {
                Rectangle().fill(tint.opacity(AccessibleDesign.tintOverlayOpacity(
                    style: .inner,
                    contrast: colorSchemeContrast
                )))
            } else {
                Rectangle().fill(DesignTokens.ColorSystem.hairline.opacity(
                    AccessibleDesign.neutralOverlayOpacity(contrast: colorSchemeContrast)
                ))
            }
        case .section:
            Rectangle().fill(.clear)
        }
    }

    private var borderColor: SwiftUI.Color {
        if style == .section {
            return .clear
        }
        return AccessibleDesign.borderColor(tint: tint, style: style, contrast: colorSchemeContrast)
    }
}

enum AccessibleDesign {
    static func isIncreasedContrast(_ contrast: ColorSchemeContrast) -> Bool {
        contrast == .increased
    }

    static func hairlineWidth(contrast: ColorSchemeContrast) -> CGFloat {
        isIncreasedContrast(contrast) ? 1 : 0.5
    }

    static func tintOverlayOpacity(style: MeridianSurfaceCardStyle, contrast: ColorSchemeContrast) -> Double {
        switch style {
        case .hero:
            return isIncreasedContrast(contrast) ? 0.12 : 0.06
        case .inner:
            return isIncreasedContrast(contrast) ? 0.12 : 0.05
        case .standard, .section:
            return 0
        }
    }

    static func neutralOverlayOpacity(contrast: ColorSchemeContrast) -> Double {
        isIncreasedContrast(contrast) ? 0.9 : 0.6
    }

    static func borderColor(
        tint: SwiftUI.Color?,
        style: MeridianSurfaceCardStyle,
        contrast: ColorSchemeContrast
    ) -> SwiftUI.Color {
        if let tint, style == .inner {
            return tint.opacity(isIncreasedContrast(contrast) ? 0.42 : 0.18)
        }
        return DesignTokens.ColorSystem.hairline.opacity(isIncreasedContrast(contrast) ? 1.6 : 1)
    }
}

enum AccessibleMaterialKind {
    case thin
    case regular
    case ultraThin
}

private struct AccessibleMaterialBackgroundModifier: ViewModifier {
    let kind: AccessibleMaterialKind
    let fallback: SwiftUI.Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                fallback
            } else {
                material
            }
        }
    }

    @ViewBuilder
    private var material: some View {
        switch kind {
        case .thin:
            Rectangle().fill(.thinMaterial)
        case .regular:
            Rectangle().fill(.regularMaterial)
        case .ultraThin:
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

extension View {
    func accessibleMaterialBackground(
        _ kind: AccessibleMaterialKind,
        fallback: SwiftUI.Color = DesignTokens.ColorSystem.panel
    ) -> some View {
        modifier(AccessibleMaterialBackgroundModifier(kind: kind, fallback: fallback))
    }
}

enum AccessibleDecisionVisuals {
    static func thumbnailOpacity(decision: DedupeDecision, differentiateWithoutColor: Bool) -> Double {
        if differentiateWithoutColor {
            return 1
        }
        return decision == .delete ? 0.55 : 1
    }

    static func compactThumbnailOpacity(decision: DedupeDecision, differentiateWithoutColor: Bool) -> Double {
        if differentiateWithoutColor {
            return 1
        }
        return decision == .delete ? 0.45 : 1
    }
}

// MARK: - Lead icon

struct MeridianLeadIcon: View {
    let systemImage: String
    let tint: SwiftUI.Color
    var usesBrandMark = false
    var size: CGFloat = DesignTokens.Layout.heroIconSize

    var body: some View {
        if usesBrandMark {
            // The brand mark IS the app icon — render it at full size with no
            // tinted backdrop so we don't nest its rounded rect inside another.
            MeridianMark()
                .frame(width: size, height: size)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .strokeBorder(tint.opacity(0.22), lineWidth: 0.5)
                    )

                Image(systemName: systemImage)
                    .font(.system(size: size * 0.44, weight: .medium))
                    .foregroundStyle(tint)
            }
            .frame(width: size, height: size)
        }
    }
}

// MARK: - Brand mark

/// Renders the actual Chronoframe app icon. Using `NSImage.applicationIconName`
/// means this mark stays in sync with whatever icon the app is currently
/// shipping — no drift between the Dock icon and in-app brand glyphs.
struct MeridianMark: View {
    var body: some View {
        #if canImport(AppKit)
        appIconImage
        #else
        fallbackMark
        #endif
    }

    #if canImport(AppKit)
    @ViewBuilder
    private var appIconImage: some View {
        if let icon = NSImage(named: NSImage.applicationIconName) {
            Image(nsImage: icon)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            fallbackMark
        }
    }
    #endif

    private var fallbackMark: some View {
        ZStack {
            Image(systemName: "camera.aperture")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary.opacity(0.95))

            Circle()
                .fill(DesignTokens.ColorSystem.accentWaypoint)
                .frame(width: 6, height: 6)
                .offset(x: 10, y: 10)
        }
    }
}

// MARK: - Status badge

struct MeridianStatusBadge: View {
    let title: String
    let systemImage: String?
    let tint: SwiftUI.Color

    init(title: String, systemImage: String? = nil, tint: SwiftUI.Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
            } else {
                Circle()
                    .fill(tint)
                    .frame(width: 5, height: 5)
            }
            Text(title)
                .scaledFont(.label)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .foregroundStyle(tint)
        .background(tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.28), lineWidth: 0.5))
        .motion(Motion.instant, value: title)
    }
}

// MARK: - Section heading

struct SectionHeading: View {
    let eyebrow: String?
    let title: String
    let message: String

    init(eyebrow: String? = nil, title: String, message: String) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let eyebrow, !eyebrow.isEmpty {
                Text(eyebrow.uppercased())
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                    .tracking(0.8)
            }

            Text(title)
                .scaledFont(.cardTitle)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

            if !message.isEmpty {
                Text(message)
                    .scaledFont(.subtitle)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Hero card

/// Compact hero card. Retuned for Darkroom: no colored gradient, no oversized
/// icon block, shorter titles. Still useful as a top-of-screen anchor until
/// fully replaced by toolbar-embedded status in later phases.
struct DetailHeroCard<Summary: View, Actions: View>: View {
    let eyebrow: String?
    let title: String
    let message: String
    let badgeTitle: String
    let badgeSystemImage: String?
    let tint: SwiftUI.Color
    let systemImage: String
    let usesBrandMark: Bool
    let summary: Summary
    let actions: Actions

    init(
        eyebrow: String? = nil,
        title: String,
        message: String,
        badgeTitle: String,
        badgeSystemImage: String? = nil,
        tint: SwiftUI.Color,
        systemImage: String,
        usesBrandMark: Bool = false,
        @ViewBuilder summary: () -> Summary,
        @ViewBuilder actions: () -> Actions
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.message = message
        self.badgeTitle = badgeTitle
        self.badgeSystemImage = badgeSystemImage
        self.tint = tint
        self.systemImage = systemImage
        self.usesBrandMark = usesBrandMark
        self.summary = summary()
        self.actions = actions()
    }

    var body: some View {
        MeridianSurfaceCard(style: .section) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                HStack(alignment: .center, spacing: 14) {
                    MeridianLeadIcon(
                        systemImage: systemImage,
                        tint: tint,
                        usesBrandMark: usesBrandMark,
                        size: usesBrandMark ? DesignTokens.Layout.heroIconSize : 36
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .scaledFont(.title)
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

                        if !message.isEmpty {
                            Text(message)
                                .scaledFont(.subtitle)
                                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 12)

                    MeridianStatusBadge(title: badgeTitle, systemImage: badgeSystemImage, tint: tint)
                }

                summary
                actions
            }
            .padding(.bottom, DesignTokens.Spacing.sm)
            .overlay(alignment: .bottom) {
                ZStack(alignment: .trailing) {
                    Rectangle()
                        .fill(DesignTokens.ColorSystem.hairline)
                        .frame(height: 0.5)

                    Circle()
                        .fill(DesignTokens.ColorSystem.accentWaypoint)
                        .frame(width: 5, height: 5)
                        .shadow(color: DesignTokens.ColorSystem.accentWaypoint.opacity(0.35), radius: 5)
                }
            }
        }
    }
}

// MARK: - Summary line

struct SummaryLine: View {
    let title: String
    let value: String
    let valueColor: SwiftUI.Color?
    let onTap: (() -> Void)?

    init(title: String, value: String, valueColor: SwiftUI.Color? = nil, onTap: (() -> Void)? = nil) {
        self.title = title
        self.value = value
        self.valueColor = valueColor
        self.onTap = onTap
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .scaledFont(.body)
                .foregroundStyle(DesignTokens.ColorSystem.inkMuted)

            Spacer(minLength: 12)

            if let onTap {
                Button(action: onTap) {
                    Text(value)
                        .scaledFont(.body)
                        .foregroundStyle(valueColor ?? DesignTokens.ColorSystem.inkPrimary)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                }
                .buttonStyle(.plain)
            } else {
                Text(value)
                    .scaledFont(.body)
                    .foregroundStyle(valueColor ?? DesignTokens.ColorSystem.inkPrimary)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
        }
    }
}

// MARK: - Metric tile

struct MetricTile: View {
    let title: String
    let value: String
    let caption: String
    let tint: SwiftUI.Color

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: tint) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title.uppercased())
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                    .tracking(0.6)

                Text(value)
                    .scaledFont(.metric)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                Text(caption)
                    .scaledFont(.body)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(caption)")
    }
}

// MARK: - Path value view

struct PathValueView: View {
    let title: String
    let value: String
    let helper: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                .tracking(0.6)

            Text(value.isEmpty ? "Not set" : value)
                .scaledFont(.mono)
                .foregroundStyle(value.isEmpty ? DesignTokens.ColorSystem.inkMuted : DesignTokens.ColorSystem.inkPrimary)
                .lineLimit(DesignTokens.Layout.pathLineLimit)
                .truncationMode(.middle)
                .help(value.isEmpty ? "" : value)

            if !helper.isEmpty {
                Text(helper)
                    .font(.footnote)
                    .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String
    var actionLabel: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        MeridianSurfaceCard(style: .standard) {
            VStack(spacing: 10) {
                ZStack {
                    EmptyPreviewGrid()
                        .frame(width: 128, height: 68)
                        .opacity(0.68)

                    MeridianLeadIcon(systemImage: systemImage, tint: DesignTokens.ColorSystem.accentAction, size: 40)
                }
                Text(title)
                    .scaledFont(.cardTitle)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                Text(message)
                    .scaledFont(.subtitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                if let actionLabel, let action {
                    Button(actionLabel, action: action)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        }
    }
}

private struct EmptyPreviewGrid: View {
    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<4, id: \.self) { index in
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(index == 1 ? DesignTokens.ColorSystem.accentWaypoint.opacity(0.18) : DesignTokens.ColorSystem.hairline.opacity(0.5))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(DesignTokens.ColorSystem.hairline, lineWidth: 0.5)
                    }
                    .frame(width: index == 1 ? 34 : 24, height: index == 1 ? 52 : 44)
                    .offset(y: index == 1 ? 0 : 4)
            }
        }
    }
}
