#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import Security

// MARK: - Trial usage witness (free-trial step 3)
//
// `ledger.db` is a file, and a file can be deleted. Without something outside
// it, quitting the app and removing
// `~/Library/Application Support/Chronoframe/trial/ledger.db` hands back a full
// allowance — which is exactly the reset the fail-closed corrupt-ledger posture
// exists to prevent, arrived at by an easier route.
//
// The witness is a small record of the last usage the ledger reported, kept in
// the login Keychain, keyed by Apple Account. On read, usage is the HIGHER of
// what the ledger says and what the witness remembers, so a ledger that has lost
// its history cannot report less than was already spent.
//
// It is a floor, not a high-water mark, and the difference matters: usage
// legitimately goes DOWN when a revert refunds allowance, when a reservation is
// released, and when a run finalizes below what it reserved. Every one of those
// writes the new, lower value through to the witness immediately, so the floor
// tracks the ledger rather than ratcheting against it. A pure high-water mark
// would quietly break the settled "revert refunds allowance" policy.
//
// WHAT THIS DOES NOT DO. It is not tamper-proof and must not be described as
// such. Someone who deletes the Keychain item as well as the database still gets
// a fresh allowance, and no purely local scheme can prevent that — StoreKit
// cannot either. What it buys is that deleting the database alone, or the whole
// Application Support folder, no longer resets anything.
//
// FAILURE POSTURE IS DELIBERATELY OPEN. If the Keychain cannot be read or
// written, the ledger's own number stands. A locked or unavailable Keychain must
// never lock a customer out of a trial they have not spent; the cost of the
// other choice is far higher than the cost of this one.

/// A record of the last usage the ledger reported for an account.
public protocol TrialUsageWitness: Sendable {
    /// The last usage recorded for `accountKey`, or `nil` when nothing has been
    /// recorded or the store could not be read.
    func recordedUsage(accountKey: String) -> TrialUsage?

    /// Record `usage` as the current truth for `accountKey`. Best-effort: a
    /// failure is swallowed rather than propagated, because no ledger operation
    /// should fail on account of the witness.
    func record(usage: TrialUsage, accountKey: String)
}

/// In-memory witness for tests and for builds that opt out of the Keychain.
public final class InMemoryTrialUsageWitness: TrialUsageWitness, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: TrialUsage]

    public init(storage: [String: TrialUsage] = [:]) {
        self.storage = storage
    }

    public func recordedUsage(accountKey: String) -> TrialUsage? {
        lock.lock()
        defer { lock.unlock() }
        return storage[accountKey]
    }

    public func record(usage: TrialUsage, accountKey: String) {
        lock.lock()
        defer { lock.unlock() }
        storage[accountKey] = usage
    }
}

/// A witness that never remembers anything. Composing with it is exactly
/// equivalent to using the ledger on its own.
public struct NullTrialUsageWitness: TrialUsageWitness {
    public init() {}
    public func recordedUsage(accountKey: String) -> TrialUsage? { nil }
    public func record(usage: TrialUsage, accountKey: String) {}
}

/// Keychain-backed witness.
///
/// A sandboxed Mac App Store app gets its own keychain access group without any
/// additional entitlement, and the item travels with the user through Migration
/// Assistant alongside Application Support — so the common legitimate paths keep
/// the witness and the ledger in step, and the reset path does not.
///
/// Not covered by unit tests: a SwiftPM test binary has no app identity, so
/// keychain calls from CI would fail for reasons unrelated to this logic. Every
/// decision this type feeds is tested through `InMemoryTrialUsageWitness`, and
/// the failure posture here is to return `nil` / do nothing, which degrades to
/// the ledger-only behaviour rather than to a lockout.
public struct KeychainTrialUsageWitness: TrialUsageWitness {
    private struct Payload: Codable {
        let organizeUsed: Int
        let dedupeUsed: Int
    }

    private let service: String

    public init(service: String = "com.nishith.chronoframe.trial") {
        self.service = service
    }

    private func baseQuery(accountKey: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
        ]
    }

    public func recordedUsage(accountKey: String) -> TrialUsage? {
        var query = baseQuery(accountKey: accountKey)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else {
            return nil
        }
        return TrialUsage(organizeUsed: payload.organizeUsed, dedupeUsed: payload.dedupeUsed)
    }

    public func record(usage: TrialUsage, accountKey: String) {
        guard let data = try? JSONEncoder().encode(
            Payload(organizeUsed: usage.organizeUsed, dedupeUsed: usage.dedupeUsed)
        ) else {
            return
        }

        let query = baseQuery(accountKey: accountKey)
        let update: [String: Any] = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        guard status == errSecItemNotFound else { return }

        var insert = query
        insert[kSecValueData as String] = data
        // The allowance is per Mac, so the item must not sync to other devices,
        // and it has to be readable on a headless first launch after restart.
        insert[kSecAttrSynchronizable as String] = false
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(insert as CFDictionary, nil)
    }
}

// MARK: - Composition

/// Wraps a ledger so its usage can never read lower than the witness remembers.
///
/// The witness is consulted on reads and written through on every mutation. It
/// deliberately sits OUTSIDE the SQLite transaction: a ledger transaction is
/// never held across other I/O, and the ordering — commit the ledger, then
/// record the witness — is what keeps the failure mode safe. A crash in between
/// leaves the witness stale, and a stale witness is only ever the PREVIOUS
/// usage, so it can over-charge by the size of one operation but can never
/// under-charge. The next mutation rewrites it.
public struct WitnessedTrialLedger: TrialLedger {
    private let base: any TrialLedger
    private let witness: any TrialUsageWitness

    public init(base: any TrialLedger, witness: any TrialUsageWitness) {
        self.base = base
        self.witness = witness
    }

    public func balance(accountKey: String) throws -> TrialBalance {
        let balance = try base.balance(accountKey: accountKey)
        guard let recorded = witness.recordedUsage(accountKey: accountKey) else { return balance }
        return TrialBalance(
            caps: balance.caps,
            usage: TrialUsage(
                organizeUsed: max(balance.usage.organizeUsed, recorded.organizeUsed),
                dedupeUsed: max(balance.usage.dedupeUsed, recorded.dedupeUsed)
            )
        )
    }

    public func reserve(
        runID: UUID,
        accountKey: String,
        meter: TrialMeter,
        count: Int,
        destinationRoot: String?
    ) throws -> ReservationDecision {
        // Re-reserving a run that is already open adds no charge — it is how a
        // resumed transfer re-enters the gate. It must reach the base ledger's
        // idempotent path untouched: applying the floor here would compare the
        // reservation against a balance that ALREADY includes it and refuse a
        // resume the customer has already paid for.
        let isAlreadyOpen = ((try? base.openReservations()) ?? []).contains { $0.runID == runID }

        if !isAlreadyOpen {
            // Decide against the floored balance. The base ledger's own atomic
            // check runs on un-floored numbers and would permit more, so this
            // pre-check is the binding one. It is not in the same transaction as
            // the insert, which is acceptable: the worst a race can do is let
            // through a reservation that a moment later would have been refused.
            let decision = TrialAllowancePolicy.decide(
                requested: count,
                meter: meter,
                balance: try balance(accountKey: accountKey)
            )
            guard decision.isPermitted else { return decision }
        }

        let inner = try base.reserve(
            runID: runID,
            accountKey: accountKey,
            meter: meter,
            count: count,
            destinationRoot: destinationRoot
        )
        if inner.isPermitted { recordCurrentUsage(accountKey: accountKey) }
        return inner
    }

    public func finalize(runID: UUID, actualCount: Int) throws {
        // Resolve the account BEFORE the mutation. `finalize` and `release` are
        // keyed by run, and both move the row out of the open set — so looking
        // the account up afterwards finds nothing and the witness silently
        // stops tracking.
        let accountKey = accountKey(forOpenRun: runID)
        try base.finalize(runID: runID, actualCount: actualCount)
        if let accountKey { recordCurrentUsage(accountKey: accountKey) }
    }

    public func release(runID: UUID) throws {
        let accountKey = accountKey(forOpenRun: runID)
        try base.release(runID: runID)
        if let accountKey { recordCurrentUsage(accountKey: accountKey) }
    }

    public func refund(
        receiptRunID: UUID,
        accountKey: String,
        meter: TrialMeter,
        itemPaths: [String]
    ) throws {
        try base.refund(
            receiptRunID: receiptRunID,
            accountKey: accountKey,
            meter: meter,
            itemPaths: itemPaths
        )
        // Writing the lower number through immediately is what keeps this a
        // floor rather than a ratchet, so a revert still refunds allowance.
        recordCurrentUsage(accountKey: accountKey)
    }

    public func accountKey(forRunID runID: UUID) throws -> String? {
        try base.accountKey(forRunID: runID)
    }

    public func openReservations() throws -> [OpenReservation] {
        try base.openReservations()
    }

    private func accountKey(forOpenRun runID: UUID) -> String? {
        ((try? base.openReservations()) ?? [])
            .first { $0.runID == runID }?
            .accountKey
    }

    private func recordCurrentUsage(accountKey: String) {
        // Read the BASE ledger, not `self`: recording the floored value would
        // pin a stale witness in place forever and stop refunds from ever
        // lowering it.
        guard let usage = try? base.balance(accountKey: accountKey).usage else { return }
        witness.record(usage: usage, accountKey: accountKey)
    }
}
