import AppKit
import SwiftUI
import ChronoframeAppCore
import ChronoframeCore
import XCTest
@testable import ChronoframeApp

/// The purchase button sits on its own line so the localized product name and
/// price never share the sheet's width with Restore and Not Now. When they did,
/// the label was compressed until the price disappeared.
///
/// This measures layout instead of reading pixels. An earlier version rendered the
/// sheet offscreen and OCR'd it, which depended on how the runner draws a default
/// button in a window that is not key, and the macOS 15 runner drew the purchase
/// button's label in a way Vision could not read.
@MainActor
final class UnlockSheetLayoutTests: XCTestCase {
    private static let sheetWidth: CGFloat = 420

    /// Widths of the sheet's buttons as laid out by SwiftUI, widest first, or an
    /// empty list if this OS does not expose them. SwiftUI backs each focusable
    /// control with a proxy view whose frame is the control's frame.
    private func buttonWidths(
        displayName: String, displayPrice: String, appearance: NSAppearance.Name
    ) async -> [CGFloat] {
        let store = EntitlementStore(
            storeKit: LayoutStore(displayName: displayName, displayPrice: displayPrice),
            appTransactionClient: LayoutTransaction(),
            defaults: .standard
        )
        await store.loadProduct()
        let view = NSHostingView(rootView: UnlockSheet(
            refusal: .allowanceSpent(TrialRefusal(meter: .organize, requested: 1, remaining: 0)),
            entitlementStore: store, onUnlocked: {}, onDismiss: {}
        ))
        view.appearance = NSAppearance(named: appearance)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.sheetWidth, height: 260),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        var widths: [CGFloat] = []
        func visit(_ node: NSView) {
            let name = String(describing: type(of: node))
            if name.contains("FocusRingView") || name.contains("KeyViewProxy") {
                widths.append(node.frame.width)
            }
            node.subviews.forEach(visit)
        }
        visit(view)
        return widths.sorted(by: >)
    }

    /// What the label needs on one line: the text at the standard control font plus
    /// the bezel's horizontal padding. A coarse floor for when SwiftUI's own frames
    /// are not visible; the layout measurement above is the real check.
    private func naturalButtonWidth(displayName: String, displayPrice: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let text = "\(displayName) · \(displayPrice)"
        return ceil(NSAttributedString(string: text, attributes: [.font: font]).size().width) + 24
    }

    func testPurchaseLabelHasRoomForProductNameAndLocalizedPrice() async throws {
        // Content width inside the sheet's 20pt padding.
        let contentWidth = Self.sheetWidth - 40
        let name = "Chronoframe Unlock"
        // The price formats this app can meet: symbol first, symbol last, an ISO code
        // prefix, and a long currency symbol.
        let prices = ["$14.99", "14,99 €", "CHF 14.90", "R$ 79,90", "¥2,400", "US$ 14.99"]

        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for price in prices {
                XCTAssertLessThanOrEqual(
                    naturalButtonWidth(displayName: name, displayPrice: price), contentWidth,
                    "\"\(name) · \(price)\" cannot fit on one line of the sheet"
                )
            }

            // Control: a label that cannot fit is laid out at the widest width a
            // button can have in this sheet. Real labels must stay below it.
            let overflowing = await buttonWidths(
                displayName: "\(name) with a deliberately overlong product name",
                displayPrice: "$14.99", appearance: appearance
            )
            guard let cap = overflowing.first else {
                // Not observable on this OS; the width floor above still ran.
                print("UnlockSheetLayoutTests: no control frames exposed in \(appearance.rawValue)")
                continue
            }
            XCTAssertGreaterThan(
                cap, naturalButtonWidth(displayName: name, displayPrice: "$14.99"),
                "The overlong control label must stretch its button to the sheet's width"
            )
            for price in prices {
                let widest = await buttonWidths(displayName: name, displayPrice: price, appearance: appearance).first
                XCTAssertNotNil(widest)
                XCTAssertLessThan(
                    widest ?? .infinity, cap - 1,
                    "\"\(name) · \(price)\" fills the sheet's width, so its label is being compressed in \(appearance.rawValue)"
                )
            }
        }
    }
}

private struct LayoutStore: StoreKitClient {
    let displayName: String
    let displayPrice: String
    func product(for productID: String) async -> StoreProductInfo? {
        StoreProductInfo(productID: productID, displayName: displayName, displayPrice: displayPrice)
    }
    func ownedProducts() async -> Result<[OwnedProduct], EntitlementLookupFailure> { .success([]) }
    func purchase(productID: String) async -> PurchaseOutcome { .userCancelled }
    func sync() async throws {}
    func transactionUpdates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private struct LayoutTransaction: AppTransactionClient {
    func appTransaction() async -> Result<AppTransactionInfo, EntitlementLookupFailure> { .failure(.unavailable) }
}
