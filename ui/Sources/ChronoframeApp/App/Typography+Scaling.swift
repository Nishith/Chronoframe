import SwiftUI

extension DesignTokens.Typography {
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
        static let heroTitle = TypeStyle(baseSize: 34, weight: .semibold, design: .default, relativeTo: .largeTitle)
        static let statusValue = TypeStyle(baseSize: 40, weight: .semibold, design: .default, relativeTo: .largeTitle)
        static let metricValue = TypeStyle(baseSize: 28, weight: .semibold, design: .default, relativeTo: .title)
    }
}

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
    func scaledFont(_ style: DesignTokens.Typography.TypeStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFontModifier(style: style, weightOverride: weight))
    }
}
