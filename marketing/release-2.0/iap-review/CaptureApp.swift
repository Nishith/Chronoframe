import SwiftUI
import ChronoframeAppCore
import ChronoframeCore

// Isolated developer fixture: real production UnlockSheet and EntitlementStore;
// deterministic metadata, no live StoreKit requests or financial actions.
struct CaptureStore: StoreKitClient {
    func product(for productID: String) async -> StoreProductInfo? {
        StoreProductInfo(productID: productID, displayName: "Chronoframe Unlock", displayPrice: "$14.99")
    }
    func ownedProducts() async -> Result<[OwnedProduct], EntitlementLookupFailure> { .success([]) }
    func purchase(productID: String) async -> PurchaseOutcome { .userCancelled }
    func sync() async throws {}
    func transactionUpdates() -> AsyncStream<Void> { AsyncStream { $0.finish() } }
}
struct CaptureTransaction: AppTransactionClient {
    func appTransaction() async -> Result<AppTransactionInfo, EntitlementLookupFailure> { .failure(.unavailable) }
}
@main
struct CaptureApp: App {
    @StateObject private var store = EntitlementStore(
        storeKit: CaptureStore(), appTransactionClient: CaptureTransaction(),
        defaults: .standard
    )
    var body: some Scene {
        WindowGroup("Chronoframe — Unlock") {
            UnlockSheet(
                refusal: .allowanceSpent(TrialRefusal(meter: .organize, requested: 1, remaining: 0)),
                entitlementStore: store, onUnlocked: {}, onDismiss: {}
            )
            .frame(width: 720, height: 422)
        }
        .windowResizability(.contentSize)
    }
}
