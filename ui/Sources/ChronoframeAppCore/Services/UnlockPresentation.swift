#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - What the unlock sheet offers (free-trial step 5, T13)
//
// The decision of what to show is a pure function of the refusal, the loaded
// product, and whether a purchase or restore is already running. Keeping it out
// of the SwiftUI view is what makes it testable — the coverage gate does not
// meaningfully reach view bodies, and the rules here are the ones that decide
// whether a customer is asked to pay twice.

/// A button the unlock sheet can offer.
public enum UnlockSheetAction: Equatable, Sendable {
    /// Buy the unlock. Carries Apple's localized price string, which is the
    /// ONLY price the sheet ever shows — a hardcoded one goes stale on every
    /// storefront, currency, and price change, and App Review rejects it.
    case buy(displayName: String, displayPrice: String)
    /// Try loading the product again. Offered only when the load failed.
    case retryProductLoad
    /// Restore Purchases. App Review requires this wherever a purchase is
    /// offered, and it is the primary action for someone who has already paid.
    case restore
    case dismiss
}

public struct UnlockSheetModel: Equatable, Sendable {
    public let title: String
    public let message: String
    public let actions: [UnlockSheetAction]
    /// True while StoreKit is working, so the view can disable its buttons
    /// without inventing its own notion of "busy".
    public let isBusy: Bool

    public init(title: String, message: String, actions: [UnlockSheetAction], isBusy: Bool) {
        self.title = title
        self.message = message
        self.actions = actions
        self.isBusy = isBusy
    }

    /// Build the sheet's contents.
    ///
    /// - Parameters:
    ///   - refusal: why the run was refused. This decides the copy, and in one
    ///     case the actions: a customer whose purchase could not be CONFIRMED
    ///     must not be invited to buy again — they may already own it — so that
    ///     case leads with Restore.
    ///   - product: nil means the product has not loaded, or could not be.
    ///   - isLoadingProduct: distinguishes "still loading" from "load failed",
    ///     which is the difference between a spinner and a Retry button.
    public static func make(
        refusal: TrialAuthorizationRefusal,
        product: StoreProductInfo?,
        isLoadingProduct: Bool,
        isPurchasing: Bool,
        isRestoring: Bool
    ) -> UnlockSheetModel {
        let busy = isPurchasing || isRestoring
        let title = Self.title(for: refusal)
        let message = Self.message(for: refusal)

        // Never offer a purchase this customer may not need. `purchaseUnconfirmed`
        // means Chronoframe could not verify an entitlement that may well exist,
        // so the honest move is to re-check rather than to sell.
        if case .purchaseUnconfirmed = refusal {
            return UnlockSheetModel(
                title: title,
                message: message,
                actions: [.restore, .dismiss],
                isBusy: busy
            )
        }

        if let product {
            return UnlockSheetModel(
                title: title,
                message: message,
                actions: [
                    .buy(displayName: product.displayName, displayPrice: product.displayPrice),
                    .restore,
                    .dismiss,
                ],
                isBusy: busy
            )
        }

        if isLoadingProduct {
            // No Buy button yet — there is no price to put on it, and a button
            // labelled with a guess is exactly what must never ship.
            return UnlockSheetModel(
                title: title,
                message: message,
                actions: [.dismiss],
                isBusy: true
            )
        }

        // The product could not be loaded. Retry, and Restore for the customer
        // who already owns it and does not need the product at all.
        return UnlockSheetModel(
            title: title,
            message: "Chronoframe could not reach the App Store to check the price. "
                + "Check your internet connection and try again.",
            actions: [.retryProductLoad, .restore, .dismiss],
            isBusy: busy
        )
    }

    private static func title(for refusal: TrialAuthorizationRefusal) -> String {
        switch refusal {
        case .allowanceSpent:
            return "Unlock Chronoframe"
        case .purchaseUnconfirmed:
            return "Purchase Not Confirmed"
        case .requiresUnlock:
            return "Unlock Chronoframe"
        }
    }

    private static func message(for refusal: TrialAuthorizationRefusal) -> String {
        switch refusal {
        case let .allowanceSpent(details):
            return Self.allowanceMessage(details)
        case .purchaseUnconfirmed:
            return "Chronoframe could not confirm your purchase, so this run did not start. "
                + "Restoring purchases usually fixes it. Nothing was changed."
        case .requiresUnlock:
            return "Reorganize is available once Chronoframe is unlocked. Nothing was changed."
        }
    }

    /// Says how much allowance is actually left.
    ///
    /// A refusal does not mean the balance is zero — the policy refuses whenever
    /// the run is larger than what remains — so a customer with room for a
    /// smaller batch must not be told their allowance is gone.
    private static func allowanceMessage(_ refusal: TrialRefusal) -> String {
        let noun = refusal.meter == .organize ? "file" : "duplicate"
        let verb = refusal.meter == .organize ? "copy" : "remove"
        let nothingHappened = refusal.meter == .organize
            ? "Nothing was copied and your originals were left untouched."
            : "Nothing was moved to the Trash."

        if refusal.remaining == 0 {
            return "Your free allowance is used up, and this run would \(verb) \(refusal.requested) "
                + "\(noun)\(refusal.requested == 1 ? "" : "s"). \(nothingHappened)"
        }
        return "Your free allowance has \(refusal.remaining) \(noun)"
            + "\(refusal.remaining == 1 ? "" : "s") left, and this run would \(verb) "
            + "\(refusal.requested). \(nothingHappened)"
    }
}
