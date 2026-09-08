#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - What the License tab says (free-trial step 5, T14)
//
// `TrialStatus` already draws the distinctions that matter — unlimited, not yet
// known, unreadable, and a real balance. This turns them into words, as a pure
// function so the wording is unit-tested rather than eyeballed in a settings
// pane nobody opens twice.
//
// The rule this exists to protect: "the ledger could not be read" and "your
// trial is used up" produce the same number — zero remaining — and must never
// produce the same sentence.

public struct LicenseStatusModel: Equatable, Sendable {
    /// One line, suitable as the pane's status row.
    public let headline: String
    /// The explanation under it. Empty when the headline says everything.
    public let detail: String
    /// Per-meter remaining counts, in display order. Empty when there is no
    /// readable balance to show — never zeroes standing in for "unknown".
    public let allowanceRows: [Row]
    /// Restore Purchases is offered to everyone who is not already unlocked.
    /// App Review requires it to be reachable outside a purchase flow.
    public let showsRestore: Bool

    public struct Row: Equatable, Sendable {
        public let label: String
        public let value: String

        public init(label: String, value: String) {
            self.label = label
            self.value = value
        }
    }

    public init(headline: String, detail: String, allowanceRows: [Row], showsRestore: Bool) {
        self.headline = headline
        self.detail = detail
        self.allowanceRows = allowanceRows
        self.showsRestore = showsRestore
    }

    /// - Parameter isAppStoreChannel: false for the Developer ID build, which
    ///   is unrestricted by settled policy and has no App Store licence to
    ///   describe. Passed as a value rather than read from `#if MAS_BUILD`
    ///   here, so both branches stay compiled in every lane — the same reason
    ///   `TrialComposition.isMacAppStoreBuild` is a boolean.
    /// - Parameters cutover/now: whether the App Store price has actually
    ///   dropped to free yet. A legacy unlock means two different things on
    ///   either side of that moment, and only one of them is true at a time —
    ///   see `unlockedDetail`.
    public static func make(
        status: TrialStatus,
        isAppStoreChannel: Bool = true,
        cutover: Date = ChronoframeUnlock.grandfatherCutover,
        now: Date = Date()
    ) -> LicenseStatusModel {
        // Nothing to license, so nothing to sell, restore, or meter. Saying
        // "Checking your purchase…" in a channel that cannot have one — and
        // offering Restore Purchases beside it — would be inviting the customer
        // to fix a problem that does not exist.
        guard isAppStoreChannel else {
            return LicenseStatusModel(
                headline: "Unlocked",
                detail: "This build is not distributed through the App Store, so it has no purchase to check. "
                    + "Every feature is available, with no limits.",
                allowanceRows: [],
                showsRestore: false
            )
        }

        if status.isUnlocked {
            return LicenseStatusModel(
                headline: "Unlocked",
                detail: unlockedDetail(
                    status.entitlement,
                    hasPriceDropped: now >= cutover
                ),
                allowanceRows: [],
                showsRestore: false
            )
        }

        switch status.allowance {
        case .unlimited:
            // Unreachable in practice — `.unlimited` only comes from an
            // unlocked entitlement, handled above — but stating it beats
            // falling through to a trial description.
            return LicenseStatusModel(
                headline: "Unlocked",
                detail: "",
                allowanceRows: [],
                showsRestore: false
            )

        case .unknown:
            return LicenseStatusModel(
                headline: "Checking your purchase…",
                detail: "",
                allowanceRows: [],
                showsRestore: true
            )

        case .unavailable:
            // NOT "your trial is used up". The gate refuses because the
            // fail-closed stand-in reports zero remaining, but zero-because-
            // unreadable is a different fact from zero-because-spent, and only
            // one of them is about the customer.
            return LicenseStatusModel(
                headline: "Free trial",
                detail: "Chronoframe could not read its record of how much of the free trial you have used, "
                    + "so it cannot show what is left. Unlocking Chronoframe removes the limit entirely.",
                allowanceRows: [],
                showsRestore: true
            )

        case let .remaining(balance):
            return LicenseStatusModel(
                headline: "Free trial",
                detail: status.describesASpentTrial
                    ? "Your free allowance is used up. Unlock Chronoframe to keep organizing."
                    : unconfirmedDetail(status.entitlement),
                allowanceRows: [
                    Row(
                        label: "Files organized",
                        value: "\(balance.remaining(for: .organize)) of \(balance.caps.organizeFiles) left"
                    ),
                    Row(
                        label: "Duplicates removed",
                        value: "\(balance.remaining(for: .dedupe)) of \(balance.caps.dedupeFiles) left"
                    ),
                ],
                showsRestore: true
            )
        }
    }

    /// - Parameter hasPriceDropped: whether the App Store price has actually
    ///   reached free yet.
    ///
    /// `legacyPurchase` is granted to everyone who acquired the app before
    /// `grandfatherCutover`, and that constant sits far in the future for the
    /// whole paid window — so during that window EVERY paying customer resolves
    /// to `.legacyPurchase`. Telling them they bought "before it moved to a
    /// free download" would announce a price drop that has not happened, to
    /// someone who has just paid full price for the app. The store listing is
    /// already careful to make no pricing claim until the cutover; this is the
    /// same rule applied in-app.
    private static func unlockedDetail(
        _ entitlement: EntitlementState,
        hasPriceDropped: Bool
    ) -> String {
        guard case let .unlocked(reason) = entitlement else { return "" }
        switch reason {
        case .inAppPurchase:
            return "Thank you. Every feature is available, with no limits."
        case .legacyPurchase:
            guard hasPriceDropped else {
                // True on both sides of the cutover, and it makes no claim
                // about a price this customer has not seen.
                return "Thank you. Chronoframe is unlocked permanently for this Apple Account, "
                    + "with no limits."
            }
            return "You bought Chronoframe before it moved to a free download, so it is unlocked permanently."
        }
    }

    /// A metered-but-unconfirmed customer is shown their balance, because that
    /// is what the gate is using — but is never told the trial is theirs.
    private static func unconfirmedDetail(_ entitlement: EntitlementState) -> String {
        switch entitlement {
        case .verificationUnavailable:
            return "Chronoframe could not reach the App Store to check your purchase, "
                + "so it is using the free allowance for now. Your access is unchanged."
        case .unverified:
            return "Chronoframe could not verify your purchase on this Mac. "
                + "Try Restore Purchases, and contact support if it keeps happening."
        case .locked, .loading, .unlocked:
            return ""
        }
    }
}
