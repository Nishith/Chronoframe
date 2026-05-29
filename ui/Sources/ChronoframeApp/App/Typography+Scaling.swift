import SwiftUI

// MARK: - Dynamic Type support for the Typography scale
//
// `Font.system(size:)` produces a FIXED font that does not respond to the
// user's accessibility text-size preference. To keep the design's custom point
// sizes *and* let them scale, each typography role is described by a
// `TypeStyle` (a base size plus the text style it scales relative to) and
// applied through `.scaledFont(_:)`, which is backed by `@ScaledMetric`.
//
// macOS note: unlike iOS, macOS has no system-wide Dynamic Type slider, so on a
// stock system the visible effect is modest. This still removes the "frozen
// font" defect and makes text honor `dynamicTypeSize` wherever it is provided
// (previews, tests, and any future in-app control).

extension DesignTokens.Typography {

    /// A scalable type style: the design's base point size plus the semantic
    /// text style it should scale relative to under Dynamic Type.
    struct TypeStyle: Equatable {
        let baseSize: CGFloat
        let weight: Font.Weight
        let design: Font.Design
        let relativeTo: Font.TextStyle

        static let display = TypeStyle(baseSize: 40, weight: .semibold, design: .default, relativeTo: .largeTitle)
        static let title = TypeStyle(baseSize: 22, weight: .semibold, design: .default, relativeTo: .title)
        static let cardTitle = TypeStyle(baseSize: 20, weight: .semibold, design: .default, relativeTo: .title2)
        static let subtitle = TypeStyle(baseSize: 15, weight: .regular, design: .default, relativeTo: .callout)
        static let body = TypeStyle(baseSize: 13, weight: .regular, design: .default, relativeTo: .body)
        static let label = TypeStyle(baseSize: 12, weight: .medium, design: .default, relativeTo: .caption)
        static let metric = TypeStyle(baseSize: 32, weight: .light, design: .default, relativeTo: .largeTitle)
        static let mono = TypeStyle(baseSize: 12, weight: .regular, design: .monospaced, relativeTo: .caption)

        // Legacy aliases, kept in sync with the fixed `Font` constants.
        static let heroTitle = TypeStyle(baseSize: 34, weight: .semibold, design: .default, relativeTo: .largeTitle)
        static let statusValue = TypeStyle(baseSize: 40, weight: .semibold, design: .default, relativeTo: .largeTitle)
        static let metricValue = TypeStyle(baseSize: 28, weight: .semibold, design: .default, relativeTo: .title)

        /// All named styles, paired with their role name, for table-validation
        /// tests (see `TypographyTests`).
        static let all: [(name: String, style: TypeStyle)] = [
            ("display", display), ("title", title), ("cardTitle", cardTitle),
            ("subtitle", subtitle), ("body", body), ("label", label),
            ("metric", metric), ("mono", mono),
            ("heroTitle", heroTitle), ("statusValue", statusValue), ("metricValue", metricValue),
        ]
    }
}

// MARK: - Dynamic Type clamp

extension DesignTokens {
    /// Upper bound on Dynamic Type for the dense, fixed-width pro surfaces
    /// (metric tiles, console). Applied at workspace roots so text scales for
    /// readability without breaking layouts that assume compact metrics.
    static let maxDynamicType: DynamicTypeSize = .accessibility1
}

// MARK: - scaledFont modifier

private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let design: Font.Design

    init(style: DesignTokens.Typography.TypeStyle, weightOverride: Font.Weight?) {
        _size = ScaledMetric(wrappedValue: style.baseSize, relativeTo: style.relativeTo)
        weight = weightOverride ?? style.weight
        design = style.design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight, design: design))
    }
}

extension View {
    /// Applies a typography role as a Dynamic Type-aware font. Prefer this over
    /// `.scaledFont(.x)` so text scales with the user's
    /// accessibility text-size preference.
    ///
    /// - Parameters:
    ///   - style: the typography role to apply.
    ///   - weight: optional override for the role's default weight.
    func scaledFont(_ style: DesignTokens.Typography.TypeStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFontModifier(style: style, weightOverride: weight))
    }
}
