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

    func testSemanticTextTokensMeetAAOnWorstCaseSurfaces() {
        for palette in [Palette.Light.self, Palette.Dark.self] as [any ContrastPalette.Type] {
            for background in palette.textSurfaces {
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(palette.captionText, background.color),
                    4.5,
                    "\(palette.name) caption text must clear AA on \(background.name)"
                )
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(palette.metadataText, background.color),
                    4.5,
                    "\(palette.name) metadata text must clear AA on \(background.name)"
                )
                XCTAssertGreaterThanOrEqual(
                    contrastRatio(palette.separatorText, background.color),
                    4.5,
                    "\(palette.name) separator text must clear AA on \(background.name)"
                )
            }
        }
    }

    func testDeduplicateInspectorMetadataMeetsAAOnImageStagePanel() {
        for palette in [Palette.Light.self, Palette.Dark.self] as [any ContrastPalette.Type] {
            XCTAssertGreaterThanOrEqual(
                contrastRatio(palette.textOnImageStage, palette.imageStage),
                4.5,
                "\(palette.name) deduplicate inspector metadata must clear AA on the image-stage panel"
            )
        }
    }

    func testTextOnImageStageMeetsAA() {
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.textOnImageStage, Palette.Light.imageStage), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Dark.textOnImageStage, Palette.Dark.imageStage), 4.5)
    }

    /// The muted ink also serves as the idle status tone, which tints fallback
    /// symbols on the dark `imageStage` tile (e.g. `NowCopyingThumbnail` before a
    /// run starts). That is a non-text icon, so it must clear the 3:1 AA floor
    /// against `imageStage` — the constraint that pulls the light muted value up
    /// from the other direction while `testLightModeTextTiersMeetWCAG` pins it
    /// down against the canvas. Both must hold simultaneously.
    func testMutedInkClearsIconContrastOnImageStage() {
        XCTAssertGreaterThanOrEqual(
            contrastRatio(Palette.Light.inkMuted, Palette.Light.imageStage), 3.0,
            "Idle/muted fallback icons must clear the 3:1 non-text floor on the image stage"
        )
    }

    func testLightModeStatusColorsMeetWCAG() {
        let canvas = Palette.Light.canvas
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.statusActive, canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.statusSuccess, canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.statusWarning, canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.statusDanger, canvas), 4.5)
    }

    func testDarkModeStatusColorsMeetWCAG() {
        let canvas = Palette.Dark.canvas
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Dark.statusActive, canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Dark.statusSuccess, canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Dark.statusWarning, canvas), 4.5)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Dark.statusDanger, canvas), 4.5)
    }

    func testNonTextStatusColorsMeetWCAG() {
        let canvas = Palette.Light.canvas
        // Dynamic non-text status elements (such as borders, icon overlays) must clear 3:1 against light canvas.
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.statusActive, canvas), 3.0)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.statusSuccess, canvas), 3.0)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.statusWarning, canvas), 3.0)
        XCTAssertGreaterThanOrEqual(contrastRatio(Palette.Light.statusDanger, canvas), 3.0)
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
            ("captionText", DesignTokens.ColorSystem.captionText, Palette.Light.captionText),
            ("separatorText", DesignTokens.ColorSystem.separatorText, Palette.Light.separatorText),
            ("textOnImageStage", DesignTokens.ColorSystem.textOnImageStage, Palette.Light.textOnImageStage),
            ("statusActive", DesignTokens.ColorSystem.statusActive, Palette.Light.statusActive),
            ("statusSuccess", DesignTokens.ColorSystem.statusSuccess, Palette.Light.statusSuccess),
            ("statusWarning", DesignTokens.ColorSystem.statusWarning, Palette.Light.statusWarning),
            ("statusDanger", DesignTokens.ColorSystem.statusDanger, Palette.Light.statusDanger),
            ("accentAction", DesignTokens.ColorSystem.accentAction, Palette.Light.accentAction),
            ("accentWaypoint", DesignTokens.ColorSystem.accentWaypoint, Palette.Light.accentWaypoint),
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
        enum Light: ContrastPalette {
            static let name = "light"
            static let canvas = RGB.bits(246, 245, 242)
            static let panel = RGB.bits(255, 255, 255)
            static let elevated = RGB.bits(255, 255, 255)
            static let utilityBand = RGB.bits(238, 237, 234)
            static let inkPrimary = RGB.bits(14, 17, 22)
            static let inkSecondary = RGB.bits(55, 62, 78)
            static let inkMuted = RGB.bits(97, 108, 118)
            static let captionText = RGB.bits(55, 62, 78)
            static let metadataText = captionText
            static let separatorText = RGB.bits(85, 93, 104)
            static let textOnImageStage = RGB.bits(244, 246, 250)
            /// Neutral dark tile behind previews / fallback symbols. Dark even in
            /// the light appearance, so muted-tinted icons land on it.
            static let imageStage = RGB.bits(31, 33, 38)
            static let statusActive = RGB.bits(25, 115, 100)
            static let statusSuccess = RGB.bits(30, 105, 63)
            static let statusWarning = RGB.bits(145, 90, 5)
            static let statusDanger = RGB.bits(175, 45, 35)
            static let accentAction = RGB.bits(62, 91, 255)
            static let accentWaypoint = RGB.bits(232, 163, 23)
            static let textSurfaces: [(name: String, color: RGB)] = [
                ("canvas", canvas),
                ("panel", panel),
                ("elevated", elevated),
                ("utilityBand", utilityBand),
            ]
        }
        enum Dark: ContrastPalette {
            static let name = "dark"
            static let canvas = RGB.bits(14, 15, 18)
            static let panel = RGB.bits(23, 24, 28)
            static let elevated = RGB.bits(32, 34, 40)
            static let utilityBand = RGB.bits(24, 25, 29)
            static let inkPrimary = RGB.bits(237, 238, 242)
            static let inkSecondary = RGB.bits(169, 175, 188)
            static let inkMuted = RGB.bits(124, 130, 144)
            static let captionText = RGB.bits(210, 214, 224)
            static let metadataText = captionText
            static let separatorText = RGB.bits(181, 187, 199)
            static let textOnImageStage = RGB.bits(244, 246, 250)
            static let imageStage = RGB.bits(8, 9, 11)
            static let statusActive = RGB.bits(75, 208, 182)
            static let statusSuccess = RGB.bits(88, 201, 140)
            static let statusWarning = RGB.bits(240, 180, 89)
            static let statusDanger = RGB.bits(244, 113, 102)
            static let accentAction = RGB.bits(123, 142, 255)
            static let textSurfaces: [(name: String, color: RGB)] = [
                ("canvas", canvas),
                ("panel", panel),
                ("elevated", elevated),
                ("utilityBand", utilityBand),
            ]
        }
    }

    private protocol ContrastPalette {
        static var name: String { get }
        static var elevated: RGB { get }
        static var imageStage: RGB { get }
        static var inkPrimary: RGB { get }
        static var captionText: RGB { get }
        static var metadataText: RGB { get }
        static var separatorText: RGB { get }
        static var textOnImageStage: RGB { get }
        static var textSurfaces: [(name: String, color: RGB)] { get }
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
