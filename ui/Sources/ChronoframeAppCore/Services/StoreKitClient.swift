#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

#if canImport(StoreKit)
import StoreKit
#endif

// MARK: - StoreKit seams (free-trial step 2)
//
// Everything StoreKit touches lives behind these two protocols. The reason is
// testability: `Transaction.currentEntitlements`, `AppTransaction.shared`, and
// `Product.purchase()` cannot be driven from a unit test without a StoreKit
// configuration file and an Xcode host, and several of the states that matter
// most — refund, Family Sharing revocation, failed signature verification,
// offline — are impractical to reproduce on demand even then.
//
// So the protocols are the test surface and the live implementations stay as
// thin as possible: map Apple's types to the plain value types in
// `ChronoframeCore/Entitlement.swift`, and hold no policy of their own.

public enum PurchaseOutcome: Equatable, Sendable {
    /// Verified and finished.
    case purchased
    /// Ask-to-buy or SCA. Entitlement may arrive later via `transactionUpdates`.
    case pending
    case userCancelled
    /// A signature did not verify. Never treat as a purchase.
    case unverified
    case failed(message: String)
}

public protocol StoreKitClient: Sendable {
    /// Display metadata for one product, or nil when the product cannot be
    /// loaded (bad ID, App Store unreachable, product not yet approved).
    func product(for productID: String) async -> StoreProductInfo?

    /// Currently-owned non-consumables, verified only.
    ///
    /// Refunded and Family-Sharing-revoked products are absent rather than
    /// flagged, so callers must treat absence as revocation.
    func ownedProducts() async -> Result<[OwnedProduct], EntitlementLookupFailure>

    func purchase(productID: String) async -> PurchaseOutcome

    /// `AppStore.sync()`. May prompt for App Store authentication, so it must
    /// only ever be called from an explicit user action — never on launch.
    func sync() async throws

    /// Fires whenever entitlements may have changed. Carries no payload: the
    /// receiver re-reads `ownedProducts()` rather than trusting a diff.
    func transactionUpdates() -> AsyncStream<Void>
}

public protocol AppTransactionClient: Sendable {
    func appTransaction() async -> Result<AppTransactionInfo, EntitlementLookupFailure>
}

// MARK: - Live implementations

#if canImport(StoreKit)

/// ⚠️ UNCOMPILED. Written on Linux with no Swift toolchain and no StoreKit SDK,
/// so the exact API surface below is unverified. Build this on a Mac before
/// trusting it; expect signature-level fixes. The logic it feeds — everything
/// in `ChronoframeCore/Entitlement.swift` — is pure and fully covered by tests
/// that do not depend on any of these calls being right.
public struct LiveStoreKitClient: StoreKitClient {
    public init() {}

    public func product(for productID: String) async -> StoreProductInfo? {
        guard let product = try? await Product.products(for: [productID]).first else {
            return nil
        }
        return StoreProductInfo(
            productID: product.id,
            displayName: product.displayName,
            displayPrice: product.displayPrice
        )
    }

    public func ownedProducts() async -> Result<[OwnedProduct], EntitlementLookupFailure> {
        var owned: [OwnedProduct] = []
        var sawUnverified = false

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                // Belt and braces: revoked transactions should already be
                // absent from `currentEntitlements`, but a refund that has not
                // finished propagating must not unlock the app.
                guard transaction.revocationDate == nil else { continue }
                owned.append(
                    OwnedProduct(
                        productID: transaction.productID,
                        purchaseDate: transaction.purchaseDate
                    )
                )
            case .unverified:
                sawUnverified = true
            }
        }

        // An unverified transaction alongside no verified unlock is a signal we
        // must not paper over: report it so the caller can surface a distinct
        // state instead of silently showing a paywall to someone who paid.
        if owned.isEmpty && sawUnverified {
            return .failure(.unverified)
        }
        return .success(owned)
    }

    public func purchase(productID: String) async -> PurchaseOutcome {
        guard let product = try? await Product.products(for: [productID]).first else {
            return .failed(message: "The unlock could not be loaded from the App Store.")
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    // Finishing is required; an unfinished transaction is
                    // redelivered forever.
                    await transaction.finish()
                    return .purchased
                case .unverified:
                    return .unverified
                }
            case .pending:
                return .pending
            case .userCancelled:
                return .userCancelled
            @unknown default:
                return .failed(message: "The App Store returned an unexpected response.")
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    public func sync() async throws {
        try await AppStore.sync()
    }

    public func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await _ in Transaction.updates {
                    continuation.yield(())
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// ⚠️ UNCOMPILED — see `LiveStoreKitClient`.
public struct LiveAppTransactionClient: AppTransactionClient {
    public init() {}

    public func appTransaction() async -> Result<AppTransactionInfo, EntitlementLookupFailure> {
        do {
            switch try await AppTransaction.shared {
            case .verified(let appTransaction):
                var transactionID: String?
                if #available(macOS 15.4, *) {
                    transactionID = appTransaction.appTransactionID
                }
                return .success(
                    AppTransactionInfo(
                        originalPurchaseDate: appTransaction.originalPurchaseDate,
                        originalAppVersion: appTransaction.originalAppVersion,
                        appTransactionID: transactionID,
                        // See AppTransactionInfo.revocationDate: not wired
                        // pending confirmation of the API surface.
                        revocationDate: nil
                    )
                )
            case .unverified:
                return .failure(.unverified)
            }
        } catch {
            // `AppTransaction.shared` throws when the App Store account or the
            // network is unavailable. That is emphatically not "did not pay".
            return .failure(.unavailable)
        }
    }
}

#endif

// MARK: - Unrestricted client

/// Resolves to unlocked without contacting StoreKit.
///
/// Used by the CLI and the Developer ID build, both of which are explicitly
/// unrestricted channels. It exists as a named type rather than a default
/// argument so every unrestricted channel is a visible, greppable decision at
/// its composition root — a default would let a future constructor ship a
/// licensing bypass silently.
public struct UnrestrictedAppTransactionClient: AppTransactionClient {
    private let originalPurchaseDate: Date

    public init(originalPurchaseDate: Date = Date(timeIntervalSince1970: 0)) {
        self.originalPurchaseDate = originalPurchaseDate
    }

    public func appTransaction() async -> Result<AppTransactionInfo, EntitlementLookupFailure> {
        .success(
            AppTransactionInfo(
                originalPurchaseDate: originalPurchaseDate,
                originalAppVersion: "0",
                appTransactionID: nil,
                revocationDate: nil
            )
        )
    }
}
