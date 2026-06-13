import SwiftUI
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

// MARK: - Badge text contrast

/// WCAG-aware foreground derivation for `MeridianStatusBadge`. The status
/// accents are tuned as *fills and icons* (3:1 non-text tier); used directly as
/// 12pt label text on the light canvas most of them sit between 2.6:1 and
/// 4.5:1, below the normal-text AA bar. The pure helpers below darken a tint
/// only as far as needed to read at AA against the badge's own fill — they are
/// deterministic and unit-tested in `ColorContrastTests`.
extension AccessibleDesign {

    struct SRGB: Equatable {
        var r: Double
        var g: Double
        var b: Double
    }

    /// The badge capsule fill opacity (tint over the surface behind it).
    static let badgeFillOpacity: Double = 0.18

    /// Contrast target for badge text: 4.5:1 AA plus headroom for the slightly
    /// darker utility-band surfaces the badge can sit on.
    static let badgeTextContrastTarget: Double = 4.6

    /// Relative luminance per WCAG 2.1 for sRGB components in 0...1.
    static func relativeLuminance(_ c: SRGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// WCAG contrast ratio between two colors, always >= 1.
    static func contrastRatio(_ a: SRGB, _ b: SRGB) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// Simple sRGB-space alpha compositing, matching how the system blends the
    /// badge's translucent tint fill over the surface behind it.
    static func composited(_ top: SRGB, over base: SRGB, alpha: Double) -> SRGB {
        SRGB(
            r: top.r * alpha + base.r * (1 - alpha),
            g: top.g * alpha + base.g * (1 - alpha),
            b: top.b * alpha + base.b * (1 - alpha)
        )
    }

    /// Darkens `tint` toward black (preserving hue) until it reads at
    /// `badgeTextContrastTarget` against the badge fill (`tint` at
    /// `badgeFillOpacity` over `surface`). Identity when the tint already
    /// passes. Light-appearance use only — light tints on the dark canvas
    /// already clear AA by a wide margin.
    static func badgeReadableTint(_ tint: SRGB, surface: SRGB) -> SRGB {
        let fill = composited(tint, over: surface, alpha: badgeFillOpacity)
        var adjusted = tint
        var scale = 1.0
        while contrastRatio(adjusted, fill) < badgeTextContrastTarget && scale > 0 {
            scale = max(0, scale - 0.02)
            adjusted = SRGB(r: tint.r * scale, g: tint.g * scale, b: tint.b * scale)
        }
        return adjusted
    }

    /// Dynamic badge text color: the tint itself in dark mode, the AA-adjusted
    /// darkened variant in light mode.
    static func badgeForeground(for tint: SwiftUI.Color) -> SwiftUI.Color {
        #if !canImport(AppKit)
        return tint
        #else
        let base = NSColor(tint)
        let surfaceToken = NSColor(DesignTokens.ColorSystem.canvas)
        let dynamic = NSColor(name: nil) { appearance in
            var resolvedTint: NSColor?
            var resolvedSurface: NSColor?
            appearance.performAsCurrentDrawingAppearance {
                resolvedTint = base.usingColorSpace(.sRGB)
                resolvedSurface = surfaceToken.usingColorSpace(.sRGB)
            }
            guard let tintColor = resolvedTint, let surfaceColor = resolvedSurface else {
                return base
            }
            let match = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .aqua, .vibrantLight])
            if match == .darkAqua || match == .vibrantDark {
                return tintColor
            }
            let adjusted = badgeReadableTint(
                SRGB(
                    r: Double(tintColor.redComponent),
                    g: Double(tintColor.greenComponent),
                    b: Double(tintColor.blueComponent)
                ),
                surface: SRGB(
                    r: Double(surfaceColor.redComponent),
                    g: Double(surfaceColor.greenComponent),
                    b: Double(surfaceColor.blueComponent)
                )
            )
            return NSColor(
                srgbRed: CGFloat(adjusted.r),
                green: CGFloat(adjusted.g),
                blue: CGFloat(adjusted.b),
                alpha: tintColor.alphaComponent
            )
        }
        return SwiftUI.Color(nsColor: dynamic)
        #endif
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
        .foregroundStyle(AccessibleDesign.badgeForeground(for: tint))
        .background(tint.opacity(AccessibleDesign.badgeFillOpacity), in: Capsule())
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
                // Secondary (not muted): these labels sit on tinted inner cards
                // where the muted tier dropped below AA. inkSecondary keeps
                // headroom over the tint overlay.
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)

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

// MARK: - Trust Proof Systems & Sandbox Popovers (ADA visual experience improvements)

enum TrustProofTone: String, Equatable {
    case neutral
    case success
    case warning
    case danger

    var color: SwiftUI.Color {
        switch self {
        case .neutral: return DesignTokens.ColorSystem.inkPrimary
        case .success: return DesignTokens.ColorSystem.statusSuccess
        case .warning: return DesignTokens.ColorSystem.statusWarning
        case .danger: return DesignTokens.ColorSystem.statusDanger
        }
    }
}

struct TrustProofItem: Identifiable, Equatable {
    let id: String
    let title: String
    let message: String
    let symbol: String
    let tone: TrustProofTone
    let accessibilityLabel: String
    let actionLabel: String?

    static func == (lhs: TrustProofItem, rhs: TrustProofItem) -> Bool {
        lhs.id == rhs.id && lhs.title == rhs.title && lhs.message == rhs.message && lhs.symbol == rhs.symbol && lhs.tone == rhs.tone && lhs.accessibilityLabel == rhs.accessibilityLabel && lhs.actionLabel == rhs.actionLabel
    }
}

struct TrustProofModel {
    static func setupSafetySummary(source: String, destination: String, verifyCopies: Bool) -> [TrustProofItem] {
        var items: [TrustProofItem] = []

        // 1. Local Processing Guarantee
        items.append(TrustProofItem(
            id: "local_only",
            title: "Local-First Processing",
            message: "All photo analysis and copies run strictly on this Mac. No files or paths are sent to any server.",
            symbol: "network.slash",
            tone: .success,
            accessibilityLabel: "Verified local processing. Photos stay on this Mac.",
            actionLabel: nil
        ))

        // 2. Source Safe Protection
        let sourceName = source.isEmpty ? "library" : URL(fileURLWithPath: source).lastPathComponent
        items.append(TrustProofItem(
            id: "source_safe",
            title: "Original Photos Protected",
            message: "Your source \(sourceName) is opened as read-only. Original files are never modified, moved, or deleted.",
            symbol: "lock.shield",
            tone: .success,
            accessibilityLabel: "Source files are read-only and safe",
            actionLabel: nil
        ))

        // 3. Copy Verification Status
        if verifyCopies {
            items.append(TrustProofItem(
                id: "verification",
                title: "Copy Verification Enabled",
                message: "Every file written to the destination will be hash-checked against the original. Corrupted copies are auto-removed.",
                symbol: "checkmark.shield",
                tone: .success,
                accessibilityLabel: "Hash verification is active",
                actionLabel: nil
            ))
        } else {
            items.append(TrustProofItem(
                id: "verification",
                title: "Verification Off",
                message: "Copies will not be hash-checked. Originals remain untouched either way.",
                symbol: "speedometer",
                tone: .warning,
                accessibilityLabel: "Warning: hash verification is disabled",
                actionLabel: nil
            ))
        }

        return items
    }

    static func runSafetySummary(isTransfer: Bool) -> [TrustProofItem] {
        return [
            TrustProofItem(
                id: "active_run",
                title: isTransfer ? "Transfer In Progress" : "Preview In Progress",
                message: isTransfer ? "Writing copies to destination. Source files stay untouched." : "Reading and planning copy routes only. No files are modified or written.",
                symbol: isTransfer ? "arrow.right.circle.fill" : "eye.fill",
                tone: isTransfer ? .success : .neutral,
                accessibilityLabel: isTransfer ? "Active transfer. Originals stay safe." : "Active preview. Read only.",
                actionLabel: nil
            )
        ]
    }

    static func deduplicateSafetySummary(reviewedGroups: Int, unreviewedGroups: Int, willDeleteCount: Int) -> [TrustProofItem] {
        var items: [TrustProofItem] = [
            TrustProofItem(
                id: "trash_only",
                title: "Trash-Only Safeguard",
                message: "Deduplication moves duplicates only to the macOS Trash, never hard-deletes them.",
                symbol: "trash.fill",
                tone: .success,
                accessibilityLabel: "Safe trash-only mode is verified",
                actionLabel: nil
            ),
            TrustProofItem(
                id: "reviewed_only",
                title: "Reviewed Groups Only",
                message: "\(reviewedGroups) groups will be processed. \(unreviewedGroups) unreviewed groups remain completely untouched.",
                symbol: "checklist",
                tone: unreviewedGroups > 0 ? .warning : .success,
                accessibilityLabel: "\(reviewedGroups) groups reviewed. \(unreviewedGroups) groups untouched.",
                actionLabel: nil
            )
        ]

        if willDeleteCount > 0 {
            items.append(TrustProofItem(
                id: "receipt_write",
                title: "Revertible Recovery",
                message: "A revert receipt will be written to .organize_logs before trashing, allowing full restore from Run History.",
                symbol: "arrow.uturn.backward.circle.fill",
                tone: .success,
                accessibilityLabel: "Revert receipt active",
                actionLabel: nil
            ))
        }

        return items
    }
}

struct LocalSafetyIndicator: View {
    @State private var showPopover = false
    let sourcePath: String
    let destinationPath: String
    let deduplicatePath: String

    init(sourcePath: String, destinationPath: String, deduplicatePath: String = "") {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.deduplicatePath = deduplicatePath.isEmpty ? destinationPath : deduplicatePath
    }

    var body: some View {
        Button(action: { showPopover = true }) {
            HStack(spacing: 6) {
                Circle()
                    .fill(DesignTokens.ColorSystem.statusSuccess)
                    .frame(width: 6, height: 6)
                Text("Local-Only")
                    .scaledFont(.label, weight: .semibold)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(DesignTokens.ColorSystem.statusSuccess.opacity(0.3), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Local-only processing verified")
        .accessibilityHint("Opens detailed security sandbox status")
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            SandboxDetailPopover(sourcePath: sourcePath, destinationPath: destinationPath, deduplicatePath: deduplicatePath)
        }
    }
}

struct SandboxDetailPopover: View {
    let sourcePath: String
    let destinationPath: String
    let deduplicatePath: String

    enum TestStatus: Equatable {
        case untested
        case testing
        case success(String)
        case failure(String)

        var description: String {
            switch self {
            case .untested: return "Untested"
            case .testing: return "Testing..."
            case .success(let msg): return msg
            case .failure(let msg): return msg
            }
        }
    }

    @State private var sourceStatus: TestStatus = .untested
    @State private var destinationStatus: TestStatus = .untested
    @State private var deduplicateStatus: TestStatus = .untested
    @State private var activeBookmarksCount: Int = 0

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("App Sandbox & Locality")
                    .scaledFont(.body, weight: .semibold)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                Spacer()
                Button(action: runInteractiveCheck) {
                    Label("Verify Scopes", systemImage: "arrow.clockwise.circle")
                        .scaledFont(.label)
                }
                .buttonStyle(.plain)
                .foregroundStyle(DesignTokens.ColorSystem.accentAction)
            }

            Text("Chronoframe operates inside a secure OS-level sandbox. It only accesses the specific folders you explicitly select.")
                .font(.caption)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                folderRow(title: "Source Folder", path: sourcePath, status: sourceStatus, isWrite: false)
                folderRow(title: "Destination Folder", path: destinationPath, status: destinationStatus, isWrite: true)
                folderRow(title: "Deduplicate Folder", path: deduplicatePath, status: deduplicateStatus, isWrite: true)
            }
            .padding(.vertical, 4)

            Divider()

            HStack {
                Text("Active Bookmarks: \(activeBookmarksCount)")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundStyle(DesignTokens.ColorSystem.statusSuccess)
                    Text("Verified Local-First")
                        .scaledFont(.label, weight: .semibold)
                }
            }
        }
        .padding(16)
        .frame(width: 440)
        .background(reduceTransparency ? DesignTokens.ColorSystem.panel : Color.clear)
        .background {
            if reduceTransparency {
                Color.clear
            } else {
                Color.clear.background(.ultraThinMaterial)
            }
        }
        .onAppear {
            runInteractiveCheck()
        }
    }

    private func runInteractiveCheck() {
        sourceStatus = .testing
        destinationStatus = .testing
        deduplicateStatus = .testing

        Task.detached(priority: .userInitiated) {
            let srcOK = sourcePath.isEmpty ? false : FileManager.default.isReadableFile(atPath: sourcePath)
            let srcMsg = srcOK ? "Read Access OK" : (sourcePath.isEmpty ? "Not Configured" : "Access Denied")
            let srcStatus: TestStatus = srcOK ? .success(srcMsg) : .failure(srcMsg)

            let destOK = destinationPath.isEmpty ? false : (FileManager.default.isReadableFile(atPath: destinationPath) && FileManager.default.isWritableFile(atPath: destinationPath))
            let destMsg = destOK ? "Read/Write OK" : (destinationPath.isEmpty ? "Not Configured" : "Access Denied")
            let destStatus: TestStatus = destOK ? .success(destMsg) : .failure(destMsg)

            let dedOK = deduplicatePath.isEmpty ? false : (FileManager.default.isReadableFile(atPath: deduplicatePath) && FileManager.default.isWritableFile(atPath: deduplicatePath))
            let dedMsg = dedOK ? "Read/Write OK" : (deduplicatePath.isEmpty ? "Not Configured" : "Access Denied")
            let dedStatus: TestStatus = dedOK ? .success(dedMsg) : .failure(dedMsg)

            var count = 0
            if !sourcePath.isEmpty { count += 1 }
            if !destinationPath.isEmpty { count += 1 }
            if !deduplicatePath.isEmpty && deduplicatePath != destinationPath { count += 1 }

            await MainActor.run {
                self.sourceStatus = srcStatus
                self.destinationStatus = destStatus
                self.deduplicateStatus = dedStatus
                self.activeBookmarksCount = count
            }
        }
    }

    private func folderRow(title: String, path: String, status: TestStatus, isWrite: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isWrite ? "externaldrive.fill" : "folder.fill")
                .font(.title3)
                .foregroundStyle(DesignTokens.ColorSystem.accentWaypoint)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(.body, weight: .semibold)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

                if path.isEmpty {
                    Text("Not selected")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                } else {
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    Text(path)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            statusBadge(for: status)
        }
        .padding(8)
        .background(DesignTokens.ColorSystem.panel)
        .cornerRadius(8)
    }

    @ViewBuilder
    private func statusBadge(for status: TestStatus) -> some View {
        switch status {
        case .untested:
            Text("Untested")
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.12), in: Capsule())
        case .testing:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.small)
                Text("Verifying...")
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.accentWaypoint)
            }
        case .success(let msg):
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.ColorSystem.statusSuccess)
                Text(msg)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.statusSuccess)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DesignTokens.ColorSystem.statusSuccess.opacity(0.12), in: Capsule())
        case .failure(let msg):
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
                Text(msg)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(DesignTokens.ColorSystem.statusWarning.opacity(0.12), in: Capsule())
        }
    }
}

struct TrustProofSurface: View {
    let items: [TrustProofItem]

    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(items) { item in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(item.tone.color)
                        .frame(width: 16)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .scaledFont(.body, weight: .semibold)
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

                        Text(item.message)
                            .scaledFont(.body)
                            .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DesignTokens.ColorSystem.panel)
                .cornerRadius(DesignTokens.Corner.innerCard)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Corner.innerCard, style: .continuous)
                        .strokeBorder(item.tone.color.opacity(differentiateWithoutColor ? 0.55 : 0.18), lineWidth: differentiateWithoutColor ? 1.2 : 0.5)
                )
                .accessibilityElement(children: .combine)
                .accessibilityLabel(item.accessibilityLabel)
            }
        }
    }
}
