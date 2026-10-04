import AppKit
import SwiftUI
import ChronoframeAppCore
import ChronoframeCore
import Vision
import XCTest
@testable import ChronoframeApp

@MainActor
final class UnlockSheetLayoutTests: XCTestCase {
    func testPurchaseLabelHasRoomForProductNameAndLocalizedPrice() async throws {
        let store = EntitlementStore(
            storeKit: LayoutStore(), appTransactionClient: LayoutTransaction(), defaults: .standard
        )
        await store.loadProduct()
        let view = NSHostingView(rootView: UnlockSheet(
            refusal: .allowanceSpent(TrialRefusal(meter: .organize, requested: 1, remaining: 0)),
            entitlementStore: store, onUnlocked: {}, onDismiss: {}
        ))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
            styleMask: [.borderless], backing: .buffered, defer: false
        )
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.cgImage)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        try VNImageRequestHandler(cgImage: image).perform([request])
        let visibleText = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(visibleText.contains("14.99"),
            "The actual rendered purchase price must remain readable: \(visibleText)")
        XCTAssertTrue(visibleText.contains("Chronoframe Unlock"))
        XCTAssertTrue(visibleText.contains("Restore Purchases"))
    }
}

private struct LayoutStore: StoreKitClient {
    func product(for productID: String) async -> StoreProductInfo? {
        StoreProductInfo(productID: productID, displayName: "Chronoframe Unlock", displayPrice: "$14.99")
    }
    func ownedProducts() async -> Result<[OwnedProduct], EntitlementLookupFailure> { .success([]) }
    func purchase(productID: String) async -> PurchaseOutcome { .userCancelled }
    func sync() async throws {}
    func transactionUpdates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}

private struct LayoutTransaction: AppTransactionClient {
    func appTransaction() async -> Result<AppTransactionInfo, EntitlementLookupFailure> { .failure(.unavailable) }
}
