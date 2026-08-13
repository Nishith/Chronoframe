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

    public static func make(status: TrialStatus) -> LicenseStatusModel {
        if status.isUnlocked {
            return LicenseStatusModel(
                headline: "Unlocked",
                detail: unlockedDetail(status.entitlement),
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

    private static func unlockedDetail(_ entitlement: EntitlementState) -> String {
        guard case let .unlocked(reason) = entitlement else { return "" }
        switch reason {
        case .inAppPurchase:
            return "Thank you. Every feature is available, with no limits."
        case .legacyPurchase:
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
