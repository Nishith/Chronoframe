import Foundation

// MARK: - Trial allowance policy (free-trial step 3)
//
// The metered free tier, expressed as pure value types with no I/O and no
// knowledge of where usage is stored. The durable ledger (ChronoframeAppCore)
// supplies the numbers; this file decides what they mean.
//
// Two deliberate choices shape everything here:
//
// 1. Usage is recorded CUMULATIVELY, never as "remaining". A stored remaining
//    count would freeze today's caps into the on-disk state, so raising the
//    allowance later would either need a migration or silently fail to reach
//    customers who had already spent some of it. Cumulative usage plus a cap
//    read at decision time makes a cap change deterministic and retroactive.
//
// 2. A reservation is decided BEFORE any mutation happens, from a snapshot of
//    the balance. See `TrialLedger` for why recording usage afterwards is
//    exploitable.

/// The two metered surfaces. Everything else in the app — preview, planning,
/// dry-run export, dedupe scanning and review, Health, History — is free and
/// unlimited, and must never consult this type.
public enum TrialMeter: String, Sendable, Codable, CaseIterable {
    case organize
    case dedupe
}

/// The lifetime cumulative allowance for each meter.
public struct TrialAllowanceCaps: Sendable, Equatable {
    /// Files copied into the destination by an organize run.
    public let organizeFiles: Int
    /// Duplicate files moved to the Trash by a deduplicate commit.
    public let dedupeFiles: Int

    public init(organizeFiles: Int, dedupeFiles: Int) {
        self.organizeFiles = organizeFiles
        self.dedupeFiles = dedupeFiles
    }

    /// The shipping allowance: 500 files organized, 100 duplicates trashed.
    public static let standard = TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100)

    public func cap(for meter: TrialMeter) -> Int {
        switch meter {
        case .organize: return organizeFiles
        case .dedupe: return dedupeFiles
        }
    }
}

/// Cumulative usage, never "remaining", so a later cap change is deterministic.
public struct TrialUsage: Sendable, Equatable {
    public let organizeUsed: Int
    public let dedupeUsed: Int

    public init(organizeUsed: Int, dedupeUsed: Int) {
        self.organizeUsed = organizeUsed
        self.dedupeUsed = dedupeUsed
    }

    public static let none = TrialUsage(organizeUsed: 0, dedupeUsed: 0)

    public func used(for meter: TrialMeter) -> Int {
        switch meter {
        case .organize: return organizeUsed
        case .dedupe: return dedupeUsed
        }
    }
}

/// Caps paired with the usage measured against them.
public struct TrialBalance: Sendable, Equatable {
    public let caps: TrialAllowanceCaps
    public let usage: TrialUsage

    public init(caps: TrialAllowanceCaps, usage: TrialUsage) {
        self.caps = caps
        self.usage = usage
    }

    /// A fresh, wholly unspent balance.
    public static func unspent(caps: TrialAllowanceCaps = .standard) -> TrialBalance {
        TrialBalance(caps: caps, usage: .none)
    }

    /// A balance with nothing left on either meter.
    ///
    /// This is the fail-closed reading used when the ledger cannot be read: an
    /// unreadable ledger must not hand out a fresh allowance, because deleting
    /// or corrupting a file would then be a free reset.
    public static func exhausted(caps: TrialAllowanceCaps = .standard) -> TrialBalance {
        TrialBalance(
            caps: caps,
            usage: TrialUsage(organizeUsed: caps.organizeFiles, dedupeUsed: caps.dedupeFiles)
        )
    }

    /// Never negative — an over-charged meter reads as zero.
    ///
    /// Usage can legitimately exceed a cap: a cap can be lowered between
    /// releases, and a reservation is charged in full while it is open. Neither
    /// should produce a negative remaining that arithmetic elsewhere then
    /// treats as extra headroom.
    public func remaining(for meter: TrialMeter) -> Int {
        max(0, caps.cap(for: meter) - usage.used(for: meter))
    }
}

/// Why a reservation was refused, carrying everything a message needs.
public struct TrialRefusal: Sendable, Equatable {
    public let meter: TrialMeter
    public let requested: Int
    public let remaining: Int

    public init(meter: TrialMeter, requested: Int, remaining: Int) {
        self.meter = meter
        self.requested = requested
        self.remaining = remaining
    }
}

public enum ReservationDecision: Sendable, Equatable {
    case permitted
    case refused(TrialRefusal)

    public var isPermitted: Bool {
        if case .permitted = self { return true }
        return false
    }

    public var refusal: TrialRefusal? {
        if case .refused(let refusal) = self { return refusal }
        return nil
    }
}

public enum TrialAllowancePolicy {
    /// Whether `requested` units may be reserved on `meter` against `balance`.
    ///
    /// Pure. `requested <= 0` is PERMITTED — a run with nothing to do must never
    /// be refused, or a customer with a spent allowance could not even complete
    /// a no-op run whose plan turned out empty.
    public static func decide(
        requested: Int,
        meter: TrialMeter,
        balance: TrialBalance
    ) -> ReservationDecision {
        guard requested > 0 else { return .permitted }
        let remaining = balance.remaining(for: meter)
        guard requested <= remaining else {
            return .refused(TrialRefusal(meter: meter, requested: requested, remaining: remaining))
        }
        return .permitted
    }
}
