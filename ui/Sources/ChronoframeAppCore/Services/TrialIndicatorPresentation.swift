#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - The remaining-allowance indicator (free-trial step 5, T16)
//
// A small line in the Run and Deduplicate workspaces saying how much of the
// free tier is left, so nobody meets the limit for the first time as a refusal
// halfway through organising a card.
//
// Absent when unlocked. A customer who paid should never see trial furniture,
// and "unlimited" is not a number worth a row.

public struct TrialIndicatorModel: Equatable, Sendable {
    /// The whole indicator, e.g. "380 of 500 files left".
    public let text: String
    /// True once the meter is empty, so the view can draw attention without
    /// deciding for itself what "low" means.
    public let isSpent: Bool

    public init(text: String, isSpent: Bool) {
        self.text = text
        self.isSpent = isSpent
    }

    /// The indicator for one meter, or nil when there is nothing to say.
    ///
    /// Nil in four situations, each for its own reason:
    ///
    ///   - **Unlocked.** Settled policy: no trial furniture for someone who
    ///     paid.
    ///   - **Unlimited.** Same thing seen from the allowance side.
    ///   - **Not resolved yet.** A workspace that flashed "checking…" on every
    ///     launch would be noise, and the number arrives moments later anyway.
    ///   - **Unreadable ledger.** The honest thing here is a sentence, not a
    ///     number, and this is a one-line indicator with no room for it — the
    ///     License tab says it properly. Showing zeroes instead would repeat
    ///     the mistake T6 was built to prevent: an unreadable ledger reads as a
    ///     spent trial. Silence is the safe failure here, because the gate
    ///     still refuses and explains itself if a run is attempted.
    ///
    /// - Parameter isAppStoreChannel: false for the Developer ID build, which
    ///   is unrestricted by settled policy. Its authorizer meters nothing, so a
    ///   remaining count there would describe a limit that does not exist.
    ///   Passed as a value rather than read from `#if MAS_BUILD`, so both
    ///   branches stay compiled in every lane — same reason as T14.
    public static func make(
        status: TrialStatus,
        meter: TrialMeter,
        isAppStoreChannel: Bool = true
    ) -> TrialIndicatorModel? {
        guard isAppStoreChannel else { return nil }
        guard !status.isUnlocked else { return nil }
        guard case let .remaining(balance) = status.allowance else { return nil }

        let remaining = balance.remaining(for: meter)
        let cap = cap(of: balance, for: meter)

        return TrialIndicatorModel(
            text: "\(remaining) of \(cap) \(noun(for: meter, count: cap)) left",
            isSpent: remaining <= 0
        )
    }

    private static func cap(of balance: TrialBalance, for meter: TrialMeter) -> Int {
        switch meter {
        case .organize:
            return balance.caps.organizeFiles
        case .dedupe:
            return balance.caps.dedupeFiles
        }
    }

    /// Plural agrees with the cap, not the remainder: the phrase is "1 of 500
    /// files left", never "1 of 500 file left".
    private static func noun(for meter: TrialMeter, count: Int) -> String {
        switch meter {
        case .organize:
            return count == 1 ? "file" : "files"
        case .dedupe:
            return count == 1 ? "duplicate" : "duplicates"
        }
    }
}
