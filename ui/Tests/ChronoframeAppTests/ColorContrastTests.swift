#if canImport(AppKit)
import AppKit
#endif
import SwiftUI
import XCTest
@testable import ChronoframeApp

/// Verifies the custom "Meridian / Darkroom" palette against WCAG 2.1 contrast
/// targets, independent of Apple's runtime accessibility audit (which only runs
/// on a GUI XCUITest runner). This is the deterministic, headless safety net:
/// it catches a token regression that quietly drops text below the readable
/// threshold long before the GUI audit would.
///
/// WCAG 2.1 AA thresholds used here:
///   - 4.5:1 for normal-size body text,
///   - 3.0:1 for large text and non-text UI (icons, the "muted" caption tier).
///
/// Contrast is appearance-specific, so the headline text-on-canvas pairs are
/// checked in *both* light and dark. The sRGB triples below mirror the token
/// definitions in `DesignTokens.ColorSystem`; `testLiteralTriplesTrackLiveTokens`
/// guards against drift between this table and the live tokens.
final class ColorContrastTests: XCTestCase {

    // MARK: - WCAG math

    /// Relative luminance per WCAG 2.1, for an sRGB color with components in 0...1.
    private func relativeLuminance(_ c: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(c.r) + 0.7152 * linear(c.g) + 0.0722 * linear(c.b)
    }

    /// WCAG contrast ratio between two colors, always >= 1.
    private func contrastRatio(_ a: RGB, _ b: RGB) -> Double {
        let la = relativeLuminance(a)
        let lb = relativeLuminance(b)
        let lighter = max(la, lb)
        let darker = min(la, lb)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// Pins the math to known references: pure black on white is the maximum
    /// 21:1, and a color against itself is the minimum 1:1.
    func testContrastMathMatchesKnownReferenceRatios() {
        XCTAssertEqual(contrastRatio(.init(0, 0, 0), .init(1, 1, 1)), 21, accuracy: 0.01)
        XCTAssertEqual(contrastRatio(.init(1, 1, 1), .init(1, 1, 1)), 1, accuracy: 0.0001)
        XCTAssertEqual(contrastRatio(.init(0, 0, 0), .init(0, 0, 0)), 1, accuracy: 0.0001)
        // Ratio is symmetric.
        let fg = RGB(0.2, 0.4, 0.6)
        let bg = RGB(0.95, 0.95, 0.95)
        XCTAssertEqual(contrastRatio(fg, bg), contrastRatio(bg, fg), accuracy: 0.0001)
    }

    // MARK: - Palette AA compliance (light)

    func testLightModeTextTiersMeetWCAG() {
        let canvas = Palette.Light.canvas
        // Primary ink is the strongest tier — comfortably AAA (7:1) for body text.
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.inkPrimary, canvas), 7.0)
        // Secondary ink (default body copy / labels) must clear AA for normal text.
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.inkSecondary, canvas), 4.5)
        // Muted ink is the least-prominent caption / eyebrow tier, but it must
        // still clear the 4.5:1 normal-text AA bar (it was retuned to ~5.2:1).
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.inkMuted, canvas), 4.5)
    }

    // MARK: - Palette AA compliance (dark)

    func testDarkModeTextTiersMeetWCAG() {
        let canvas = Palette.Dark.canvas
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Dark.inkPrimary, canvas), 7.0)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Dark.inkSecondary, canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Dark.inkMuted, canvas), 4.5)
    }

    /// Guards the muted-ink retune: every ink tier now clears the 4.5:1 AA bar
    /// for normal-size text on canvas, in both appearances. Muted remains the
    /// least-prominent tier (lowest ratio of the three) without dropping below
    /// readable — so a regression that darkens contrast hierarchy away *or* one
    /// that pushes muted back under AA both surface here.
    func testMutedInkIsLeastProminentButStillMeetsAA() {
        for (muted, secondary, canvas) in [
            (Palette.Light.inkMuted, Palette.Light.inkSecondary, Palette.Light.canvas),
            (Palette.Dark.inkMuted, Palette.Dark.inkSecondary, Palette.Dark.canvas),
        ] {
            let mutedRatio = contrastRatio(muted, canvas)
            XCTAssertGreaterThanOrEqual(mutedRatio, 4.5, "Muted ink must meet the 4.5:1 normal-text AA bar")
            XCTAssertLessThanOrEqual(mutedRatio, contrastRatio(secondary, canvas), "Muted ink should stay the least-prominent text tier")
        }
    }

    // MARK: - Drift guard

    /// Best-effort cross-check that the literal triples above still match the
    /// live `DesignTokens.ColorSystem` tokens. `resolveSRGB` pins the Aqua
    /// (light) appearance before resolving, so the dynamic tokens resolve to
    /// their light variant deterministically regardless of the host/CI
    /// appearance (a Dark Aqua runner would otherwise yield the dark variant and
    /// false-fail). If the platform can't resolve a token to sRGB in this
    /// environment, the check is skipped rather than producing a false failure.
    func testLiteralTriplesTrackLiveTokens() throws {
        let pairs: [(name: String, token: SwiftUI.Color, expected: RGB)] = [
            ("canvas", DesignTokens.ColorSystem.canvas, Palette.Light.canvas),
            ("inkPrimary", DesignTokens.ColorSystem.inkPrimary, Palette.Light.inkPrimary),
            ("inkSecondary", DesignTokens.ColorSystem.inkSecondary, Palette.Light.inkSecondary),
            ("inkMuted", DesignTokens.ColorSystem.inkMuted, Palette.Light.inkMuted),
        ]
        for pair in pairs {
            guard let resolved = Self.resolveSRGB(pair.token) else {
                throw XCTSkip("sRGB resolution unavailable for \(pair.name) in this environment")
            }
            // Generous tolerance (~6/255 per channel): tight enough to catch a
            // real token change, loose enough to absorb color-space rounding.
            XCTAssertEqual(resolved.r, pair.expected.r, accuracy: 0.025, "\(pair.name) red drifted from DesignTokens")
            XCTAssertEqual(resolved.g, pair.expected.g, accuracy: 0.025, "\(pair.name) green drifted from DesignTokens")
            XCTAssertEqual(resolved.b, pair.expected.b, accuracy: 0.025, "\(pair.name) blue drifted from DesignTokens")
        }
    }

    // MARK: - Helpers

    private struct RGB {
        let r: Double
        let g: Double
        let b: Double
        init(_ r: Double, _ g: Double, _ b: Double) {
            self.r = r
            self.g = g
            self.b = b
        }
        /// Convenience for the 0...255 values copied from `DesignTokens`.
        static func bits(_ r: Double, _ g: Double, _ b: Double) -> RGB {
            RGB(r / 255, g / 255, b / 255)
        }
    }

    /// sRGB triples mirroring `DesignTokens.ColorSystem`. Keep in sync with that
    /// file; `testLiteralTriplesTrackLiveTokens` enforces the light variants.
    private enum Palette {
        enum Light {
            static let canvas = RGB.bits(246, 245, 242)
            static let inkPrimary = RGB.bits(14, 17, 22)
            static let inkSecondary = RGB.bits(71, 80, 99)
            static let inkMuted = RGB.bits(95, 103, 120)
        }
        enum Dark {
            static let canvas = RGB.bits(14, 15, 18)
            static let inkPrimary = RGB.bits(237, 238, 242)
            static let inkSecondary = RGB.bits(169, 175, 188)
            static let inkMuted = RGB.bits(124, 130, 144)
        }
    }

    /// Resolves a SwiftUI color to sRGB components under the Aqua (light)
    /// appearance, so dynamic tokens resolve to their light variant regardless
    /// of the host appearance. Returns `nil` if the platform cannot convert it.
    private static func resolveSRGB(_ color: SwiftUI.Color) -> RGB? {
        #if canImport(AppKit)
        guard let appearance = NSAppearance(named: .aqua) else { return nil }
        var components: RGB?
        appearance.performAsCurrentDrawingAppearance {
            if let srgb = NSColor(color).usingColorSpace(.sRGB) {
                components = RGB(
                    Double(srgb.redComponent),
                    Double(srgb.greenComponent),
                    Double(srgb.blueComponent)
                )
            }
        }
        return components
        #else
        return nil
        #endif
    }
}
