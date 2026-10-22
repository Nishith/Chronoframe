# Free Trial Plan

Chronoframe V2 launches directly as a **free download plus one non-consumable lifetime unlock**, with a metered free tier. On October 16, 2026 the owner confirmed there are no existing customers and approved removing the paid migration. This decision supersedes the historical paid-window and grandfathering instructions. No customer settings or allowance ledgers need resetting.

Grounded against the tree as of the 2026-09-07 IAP engineering refresh.

## Status

**Current candidate 511:** the Deduplicate observation correction is uploaded and installed; all 24 hosted checks on frozen source `3b38279` pass. Its signed refusal shows the actual purchase offer without mutation. Explicit negative Restore, a recorded no-charge sandbox purchase through License, stopped pending Organize operation with unchanged fixture hashes and persisted Unlocked after relaunch pass. Positive owned Restore remains a separately verified signed 510 result. The disclosed, inspected 3:21 video includes the supplemental desktop launch and is attached; direct notes and the real signed IAP screenshot are saved. The unsubmitted combined draft has **511 + Unlock ready to submit**, with manual release selected; owner Go and submission remain open. See [the active 511 ledger](app-review-replacement-511-2026-10-21.md). The earlier 510 paragraph below is historical; both testers now own the purchase and their records are preserved.

October 21: PR #251 is merged, and clean candidate **2.0 (510)** passed archive/export/signature/package validation, uploaded, processed and is installed through TestFlight. Explicit License Restore changed Free trial to Unlocked with the purchased sandbox tester and cleared a pending Organize refusal without any fixture mutation. Fresh-account negative Restore and real $14.99 product discovery pass. Signed 508 already passed actual sandbox purchase/cancellation/persistence, but it predates the final License pending-operation correction. Fresh signed purchase/pending-operation verification, completed requested recording, final store preparation and owner Go remain open in [the replacement ledger](app-review-resubmission-2026-10-21.md). This does not change the settled policy below.

| # | Phase | State |
|---|---|---|
| 1 | Settle policy | Done — see [Settled policy](#settled-policy) |
| 2 | StoreKit seams + entitlement state machine | **Merged.** Used by enforcement and UI |
| 3 | Durable reservation ledger | **Merged.** T1–T6 |
| 4 | Enforcement at the mutation surfaces | **Merged.** T7–T12 |
| 5 | Unlock UI + free test batch | **Merged.** T13–T16 |
| 6 | Test matrices | **Merged.** T17–T19 |
| 7 | App Store Connect product creation | Verified October 19: correct non-consumable ID, $14.99 US, Family Sharing and all regions; Ready for Review |
| 8 | Direct free V2 launch | App 507 rejected under 2.1(b); direct License purchase correction and replacement sandbox/recording evidence required |
| 9 | Release monitoring | Not started |

The launch target remains October 26, 2026, subject to final testing and App Review. There is no seven-day paid rollout or compiled acquisition-date cutoff. `ChronoframeUnlock.defaultPolicy()` disables both live and cached legacy grants. App transactions still supply the account identity for the allowance; verified ownership of the non-consumable unlock confers unrestricted access. Existing test-build legacy grants do not confer access, even offline. Test data and usage ledgers are not reset.

## Risk markers

Each task is marked with how much care it needs:

- **Routine** — specified end to end; implement and test against the acceptance criteria.
- **Careful review** — specified, but the failure modes are subtle. Read the diff closely.
- **Safety-critical** — touches an audited path (executors, revert, the gates themselves, the
  entitlement policy). Diffs here are reviewed line by line; automated tests do not replace review.
- **Manual** — App Store Connect or release execution. Not a code change.

## Settled policy

Not open for reinterpretation during implementation. Raise a question rather than deviating.

| Question | Decision |
|---|---|
| Allowance | 500 files organized, 100 duplicates trashed (cumulative, lifetime) |
| Free and unlimited | preview, plan, dry-run CSV, dedupe scan and review, Health, History |
| Product | `com.nishith.chronoframe.unlock`, one non-consumable |
| Price | Free download; $14.99 US one-time lifetime unlock; no subscription |
| Family Sharing | ON — irreversible, so it is set at product creation |
| Quota scope | per Apple Account, per Mac — `AppTransactionInfo.ledgerAccountKey` |
| Revert refunds allowance | yes — per restored item, so partial and repeated reverts are exact |
| Revert gating | never, all three receipt kinds |
| Reorganize | requires unlock (a gate, not a reservation) |
| Developer ID build | internal/testing only, explicitly unrestricted |
| Launch | Direct free download; no paid rollout or date-based legacy unlock |

The legacy migration types remain for explicit historical-policy tests. They are disabled in the shipping default. Purchase, restore, transaction updates, account-scoped metering, refund-on-revert and unrestricted Developer ID testing retain their existing behavior. Family Sharing and the actual price must also be verified in App Store Connect; local code cannot configure them.

## Ground rules

1. **No task may weaken a safety invariant.** `AGENTS.md` → `## Safety Invariants` is binding. If a
   change touches behaviour under one of those bullets, add or update a test tagged
   `// AGENTS-INVARIANT: N` and re-run `script/check_agents_invariants_have_tests.sh`.
2. **Revert is never gated.** Revert entry points take no authorizer parameter. This is structural,
   not a convention — there must be nothing to gate. A paywall must never be able to strand a
   library mid-migration.
3. **Surgical diffs in safety-critical code.** In the executors, every changed line must trace to
   the task. No opportunistic cleanups, renames, or error-handling tightening.
4. **New pure `ChronoframeCore` files** go in `MEANINGFUL_BASENAMES` in
   `script/swift_meaningful_coverage.sh` — an explicit allowlist with a 95% threshold.
5. **Never surface raw `NSError`, POSIX codes, or SQLite messages to users.** See
   `ui/Sources/ChronoframeAppCore/Support/UserFacingErrorMessage.swift`.
6. **Never claim a guarantee that has not been verified.** This project has been bitten repeatedly
   by false assurances — documentation claiming CI catches something it does not, purchase copy
   claiming no charge was taken when one may have been. If you write "X is guaranteed", prove it.

---

# Step 3 — Durable reservation ledger

**Why:** recording usage after the filesystem work finishes is exploitable. A user could cancel
after 499 copies, forever. Recording in a store's completion handler also loses usage on crash,
cancel-after-partial-success, partial failure, concurrent balance reads, a stream ending without a
final event, or an App Intent racing the app.

Replace *check → mutate → record* with **reserve → mutate → finalize → reconcile**:

1. Reserve the full requested count **before** enqueueing jobs, writing a receipt, or touching media.
2. Persist the reservation against work that already survives a crash.
3. Finalize with the actual successful mutation count.
4. Reconcile on cancellation, failure, and at startup.

**A crash leaves the reservation fully charged until recovery proves how many mutations actually
occurred.** This matches the fail-closed posture everywhere else in the codebase.

**There is no usable reservation key today — it has to be plumbed (T3).** The schema looks
ready and is not:

- `CopyJobs.run_id` exists and `enqueueQueuedJobs` binds it, but `enqueuePlannedTransfers`
  constructs `QueuedCopyJob` without a `runID`, and that parameter defaults to `nil`. Every row
  enqueued by a transfer therefore has a **null** `run_id`.
- `TransferExecutor` mints its own UUID for the execution context, and the streaming receipt writer
  mints a **second, different** one.
- `DeduplicateExecutor.commit` mints its receipt `runID` internally, **after** the point where a
  reservation must already exist.

So a reservation taken at the gate could not be matched to the crash-recovery rows or to the
receipt, and both reconciliation (T5) and refunds (T12) would silently fail. One ID must be minted
at the reservation point and threaded down through enqueueing, both executors, and both receipt
writers.

`RevertReceipt` additionally carries no run ID at all (T4).

**Scope boundary: build the ledger, gate nothing.** Ship dark, as step 2 did.

## T1 — Pure allowance policy · Routine

**File:** `ui/Sources/ChronoframeCore/TrialAllowance.swift` (new)

```swift
public enum TrialMeter: String, Sendable, Codable, CaseIterable { case organize, dedupe }

public struct TrialAllowanceCaps: Sendable, Equatable {
    public let organizeFiles: Int
    public let dedupeFiles: Int
    public static let standard = TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100)
    public func cap(for meter: TrialMeter) -> Int
}

/// Cumulative usage, never "remaining", so a later cap change is deterministic.
public struct TrialUsage: Sendable, Equatable {
    public let organizeUsed: Int
    public let dedupeUsed: Int
    public func used(for meter: TrialMeter) -> Int
}

public struct TrialBalance: Sendable, Equatable {
    public let caps: TrialAllowanceCaps
    public let usage: TrialUsage
    /// Never negative — an over-charged meter reads as zero.
    public func remaining(for meter: TrialMeter) -> Int
}

public struct TrialRefusal: Sendable, Equatable {
    public let meter: TrialMeter
    public let requested: Int
    public let remaining: Int
}

public enum ReservationDecision: Sendable, Equatable {
    case permitted
    case refused(TrialRefusal)
}

public enum TrialAllowancePolicy {
    /// Pure. `requested <= 0` is PERMITTED — a no-op run must never be refused.
    public static func decide(requested: Int, meter: TrialMeter, balance: TrialBalance) -> ReservationDecision
}
```

Add `TrialAllowance` to `MEANINGFUL_BASENAMES`.

**Tests:** partial spend; exact-boundary spend (`requested == remaining` permitted); over-spend by
one; `requested == 0` permitted; `requested < 0` permitted; usage exceeding cap gives remaining 0,
not negative; raising a cap does not change stored usage; refusal carries the right
requested/remaining.

**Acceptance:** pure (no I/O); every branch covered; coverage gate passes with the new entry.

## T2 — SQLite ledger · Careful review

**Files (new):** `TrialLedgerPaths.swift`, `TrialLedger.swift` (protocol plus in-memory double),
`TrialLedgerDatabase.swift`, all under `ui/Sources/ChronoframeAppCore/Support/`.

**Location:** `~/Library/Application Support/Chronoframe/trial/ledger.db` via
`RuntimePaths.applicationSupportDirectory()`. Follow `GuardianPaths.swift` for shape.
**Global, not per-destination** — the allowance spans destinations.

```sql
PRAGMA journal_mode = WAL;
PRAGMA user_version = 1;

CREATE TABLE IF NOT EXISTS Reservations (
    run_id           TEXT PRIMARY KEY,
    account_key      TEXT NOT NULL,
    meter            TEXT NOT NULL,      -- 'organize' | 'dedupe'
    reserved_count   INTEGER NOT NULL,
    finalized_count  INTEGER,            -- NULL while open
    state            TEXT NOT NULL,      -- 'open' | 'finalized' | 'released'
    destination_root TEXT,
    created_at       TEXT NOT NULL,
    updated_at       TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_reservations_state ON Reservations(state);
CREATE INDEX IF NOT EXISTS idx_reservations_account ON Reservations(account_key);

-- Item-level, NOT one row per receipt. Reverts are routinely partial: the
-- invariant "revert deletes only destination files whose current hash still
-- matches the receipt" means a changed or unavailable file is preserved and
-- skipped. A per-receipt row with INSERT OR IGNORE would freeze the first
-- partial refund forever, so a later revert that restores the remaining items
-- would be silently dropped. Recording each restored item makes repeat and
-- partial reverts exact and still idempotent.
CREATE TABLE IF NOT EXISTS RefundedItems (
    receipt_run_id  TEXT NOT NULL,
    item_path       TEXT NOT NULL,
    account_key     TEXT NOT NULL,
    meter           TEXT NOT NULL,
    created_at      TEXT NOT NULL,
    PRIMARY KEY (receipt_run_id, item_path)
);
CREATE INDEX IF NOT EXISTS idx_refunded_account ON RefundedItems(account_key, meter);
```

**The usage query is where fail-closed comes from. Do not "simplify" it:**

```sql
SELECT COALESCE(SUM(COALESCE(finalized_count, reserved_count)), 0)
FROM Reservations WHERE account_key = ? AND meter = ? AND state IN ('open','finalized');

SELECT COUNT(*) FROM RefundedItems WHERE account_key = ? AND meter = ?;
```

`usage = charged − refunded`. An **open** reservation counts at its **full reserved amount**, so a
crash consumes the allowance until reconciliation proves otherwise — with no special-case code.

```swift
public struct OpenReservation: Sendable, Equatable {
    public let runID: UUID
    public let accountKey: String
    public let meter: TrialMeter
    public let reservedCount: Int
    public let destinationRoot: String?
    public let createdAt: Date
}

public protocol TrialLedger: Sendable {
    func balance(accountKey: String) throws -> TrialBalance

    /// Atomic check-and-insert in ONE `BEGIN IMMEDIATE` transaction. Returns `.refused`
    /// WITHOUT writing when the meter cannot cover `count`. Re-reserving an existing
    /// runID returns the stored decision unchanged.
    func reserve(runID: UUID, accountKey: String, meter: TrialMeter,
                 count: Int, destinationRoot: String?) throws -> ReservationDecision

    /// Idempotent: transitions `open → finalized` only. A second call is a no-op, so
    /// duplicate completion handling cannot double-charge.
    func finalize(runID: UUID, actualCount: Int) throws

    /// Idempotent `open → released`. ONLY for reservations that provably never mutated
    /// anything. Never call this on an ambiguous outcome.
    func release(runID: UUID) throws

    /// Records the items a revert actually restored or removed. Idempotent per
    /// (receiptRunID, itemPath) via INSERT OR IGNORE, so a partial revert followed
    /// later by a fuller one refunds exactly the newly restored items — and
    /// re-running the same revert refunds nothing extra.
    ///
    /// Takes paths, not a count, on purpose: a count cannot distinguish "two more
    /// items restored" from "the same two items reported twice".
    func refund(receiptRunID: UUID, accountKey: String, meter: TrialMeter, itemPaths: [String]) throws

    func openReservations() throws -> [OpenReservation]
}
```

**Concurrency:** WAL plus `BEGIN IMMEDIATE` gives cross-process write serialization, and every
ledger mutation is a single transaction. **Do not add a separate advisory lock file** — it would
add a deadlock surface for nothing. Where a destination lease and a ledger transaction are both
held, the order is **destination lease first, then ledger**, and a ledger transaction is never held
across filesystem work.

**Corrupt ledger fails closed** — zero remaining, not a fresh balance. This is the deliberate
inversion of `GuardianFileSchedulePersistence`, whose "corrupt reads as fresh" default would hand
out a free reset. Surface it distinctly enough that the UI can say purchasing unlocks the app;
Restore Purchases does not repair this for someone who never bought.

**Tests:** reserve then finalize with fewer than reserved; **duplicate finalize does not
double-charge**; finalize on a released or already-finalized row is a no-op; re-reserving an
existing runID does not stack; a refusal writes nothing (assert row count unchanged); concurrent
organize and dedupe reservations; two reservations on one meter cannot jointly exceed the cap;
**a partial refund followed by a fuller one refunds only the newly restored items**; re-running an
identical refund adds nothing; refund for an unknown receipt is harmless; corrupt ledger reports
zero remaining; `openReservations()` returns only open rows.

## T3 — Plumb one reservation run ID · Safety-critical

**Prerequisite for T5, T8, T9 and T12.** Without it, a reservation cannot be matched to the rows
or receipts that prove what happened, and reconciliation and refunds fail silently.

Mint the ID **at the reservation point** and thread it downward. Nothing below the gate may mint
its own.

| Site | Change |
|---|---|
| `OrganizerDatabase.enqueuePlannedTransfers` | Take a `runID: UUID` and set it on every `QueuedCopyJob`. It currently omits the argument, and `QueuedCopyJob.runID` defaults to `nil`, so today every enqueued row has a null `run_id`. |
| `TransferExecutor` execution context | Accept an injected run ID instead of minting one. |
| Streaming audit receipt writer | Use the same injected ID rather than minting a second one. |
| `DeduplicateExecutor.commit` | Accept an injected run ID instead of minting the receipt `runID` internally, which currently happens after the reservation point. |

**Acceptance:** for a completed organize run, the ledger's `run_id`, every `CopyJobs.run_id` for
that run, and the audit receipt's run ID are the **same value**. Same for a dedupe commit and its
receipt. Add a test asserting that equality directly — it is the property everything downstream
depends on.

Keep the diffs surgical; these are audited executor paths.

## T4 — `RevertReceipt` schema version 3 · Safety-critical

**File:** `ui/Sources/ChronoframeCore/RevertExecutor.swift`

`RevertReceipt` carries no `runID`, so organize reverts have no idempotency key for refunds. Add an
**optional** `run_id`:

- Bump `maxSupportedSchemaVersion` to 3; the writer emits `schemaVersion: 3` and `run_id`.
- The reader uses `decodeIfPresent` so v1 and v2 receipts still load. The existing decoder is
  already fully optional-tolerant.
- **Legacy receipts without `run_id` are not refundable.** No fallback heuristic on timestamp or
  file path — guessing an idempotency key is how double-refunds happen.

**Tests:** round-trip v3; decode a v1 receipt (no `schemaVersion`, no `status`) unchanged; decode a
v2 receipt unchanged; a v3 receipt missing `run_id` decodes with a nil run ID.

Keep the diff minimal. This file's revert hash-check behaviour must not shift.

## T5 — Reconciler · Careful review

**File:** `ui/Sources/ChronoframeAppCore/Support/TrialLedgerReconciler.swift` (new)

`MutationRecoveryCoordinator` (Core) stays ignorant of the ledger. Run the reconciler **after**
`MutationRecoveryCoordinator.recover(destinationRoot:)`.

**Centralize rather than enumerate.** There are eight `MutationRecoveryCoordinator()` call sites
today — `OrganizerEngine.prepare`, three in `RunSessionStore`, `AppState`'s post-bootstrap launch
recovery, `DeduplicateEngine`, `HistoryStore`, and `CLI.swift`. Wiring the reconciler into a
hand-picked subset guarantees drift, and a missed site means filesystem recovery completes at
launch while the reservation stays fully charged — so the balance UI, or the next dedupe attempt,
refuses work the customer is entitled to.

Introduce a single "recover and reconcile" entry point and route **every** call site through it.
Add a test (or a small guard script) asserting no direct `MutationRecoveryCoordinator().recover`
call survives outside that helper.

For each open reservation:

| Meter | Reconcile from | Finalize with |
|---|---|---|
| `organize` | `CopyJobs` rows where `run_id = R` | count of rows whose status / `mutation_state` prove the copy completed |
| `dedupe` | dedupe receipt plus `.spool` journal for `runID = R` | count of items in a trashed terminal state |

All three rules are load-bearing:

- If the destination is **unreachable, leave the reservation open** and retry later. It stays fully
  charged. Never infer that an inaccessible path means nothing happened.
- Reconciliation is idempotent; running it twice must not change a finalized row.
- Never delete receipts, journals, or quarantine paths.

**Tests:** open reservation plus completed `CopyJobs` finalizes at the true count; unreachable
destination stays open and fully charged; crash after mutation before finalize reconciles to the
correct count; reconciling twice is idempotent; dedupe reconciliation from receipt plus spool.

## T6 — Compose entitlement and ledger · Routine

**File:** `ui/Sources/ChronoframeAppCore/Services/TrialStatusStore.swift` (new)

```swift
public struct TrialStatus: Sendable, Equatable {
    public let entitlement: EntitlementState
    public let balance: TrialBalance?   // nil when unlocked or unresolved
}
```

A `@MainActor` type reading `EntitlementStore.ledgerAccountKey` and `TrialLedger.balance`.
`.unlocked` short-circuits — an unlocked customer never consults the ledger. Wire into `AppState`.
**Nothing calls `reserve` yet.**

**Acceptance:** the app builds and behaves identically; existing `AppStateTests` still pass.

---

# Step 4 — Enforcement

Do not start until step 3 is merged. Gating against an unmerged ledger produces untestable
half-states.

## T7 — Require an explicit authorizer everywhere · Safety-critical

Remove any default argument for the authorizer on production engine initializers. A default makes
every forgotten or future constructor a silent licensing bypass. Let the compiler enumerate the
composition roots:

| Composition root | Policy |
|---|---|
| Mac App Store app (`AppState`) | entitlement-backed authorizer |
| CLI (`ChronoframeCLIKit/CLI.swift`) | explicitly unrestricted |
| Developer ID build | explicitly unrestricted |
| Tests | explicit fake |

**Acceptance:** no default argument exists; removing an argument at a call site fails to compile.

## T8 — Gate organize · Safety-critical

`ui/Sources/ChronoframeAppCore/Services/SwiftOrganizerEngine.swift`

- **`startTransfer`** — after `planAsync`, after the existing zero-transfer branches, immediately
  before `enqueuePlannedTransfers`. Reserve `result.transferCount` against `.organize`. On refusal:
  enqueue nothing, write no receipt, finish cleanly.
- **`resumeTransfer`** — has its **own** `executeQueuedJobs` call and bypasses the fresh-run gate
  entirely. Reconcile against the reservation already keyed by the queued jobs' `run_id`; do not
  double-reserve a resume.
- Finalize with the executor's actual copied count in both paths.

**Do not add a `RunStatus` case.** It is `String, Codable` with twelve cases and nine switch sites,
and is persisted into receipts and history — a refusal must not masquerade as a completed run. Use
a typed authorization outcome that the store converts into an unlock prompt.

**Required test:** a refused transfer leaves **no queued `CopyJobs` rows, no receipt, no spool, and
no media changes**. Do not assert whole-destination byte-identity — planning legitimately writes
`.organize_cache.db` and logs.

## T9 — Gate dedupe · Safety-critical

`NativeDeduplicateEngine.commit` — the **engine**, not `DeduplicateSessionStore`, which is a UI
gate that callers can route around. Reserve `plan.count` against `.dedupe` before
`executor.commit(...)`; finalize with the deleted count.

**Required test:** a refused commit moves nothing to Trash and writes no receipt or spool journal.

## T10 — Gate reorganize · Routine, after T6–T8

`SwiftOrganizerEngine.reorganize` requires an unlock. Metered at zero — a gate, not a reservation.

## T11 — App Intent and CLI · Careful review

`ui/Sources/ChronoframeApp/AppIntents/OrganizeFolderIntent.swift` builds its own engine and
auto-confirms every non-blocking prompt. Add an explicit purchase branch that throws an intent
error telling the user to open Chronoframe. **Background intents must never attempt interactive
in-app purchase.** Wire the CLI's unrestricted authorizer explicitly and document why.

## T12 — Refund allowance on revert · Careful review

Defining `TrialLedger.refund` is not enough — something has to call it. Without this task the
settled "revert refunds allowance" policy is unimplemented and customers stay charged for work
they undid, which is the opposite of the reason revert is ungated in the first place.

Consume each revert result and record **only the mutations actually undone**:

| Path | Consume | Meter |
|---|---|---|
| Organize revert | `RevertExecutionResult` — the destination files actually removed | `.organize` |
| Dedupe revert | the Trash items actually restored | `.dedupe` |
| Reorganize revert | nothing — reorganize is gated, not metered | — |

Pass the **paths** that were undone, not a count. Reverts are routinely partial: a destination file
whose hash no longer matches the receipt is preserved and skipped by design, so a user can revert,
fix the conflict, and revert again. Item-level records make the second pass refund exactly the
newly restored items.

**Do not add an authorizer to any revert path.** This task reads revert *outcomes*; it must not
gate revert or change its behaviour in any way.

**Tests:** a full revert refunds every item; a partial revert refunds only the restored subset; a
second revert restoring the remainder refunds only the new items; re-running an identical revert
refunds nothing further; a revert of a legacy receipt with no run ID refunds nothing and does not
throw.

---

# Step 5 — Unlock UI

## T13 — Unlock sheet · Routine

`ui/Sources/ChronoframeApp/Views/Purchase/UnlockSheet.swift` (new). It must:

- Show `Product.displayPrice` — never a hardcoded price.
- Offer **Restore Purchases**; App Review requires it.
- Handle product-load failure with Retry and Restore.
- Release the destination operation lease **before** presenting the App Store sheet.
- Discard the prepared run and **re-run preflight and planning after purchase** — never confirm a
  stale plan.
- Write no run-history entry and post no completion notification.

Follow the Meridian language: native controls, no decorative gradients, no instructional text
describing obvious mechanics.

## T14 — Settings License tab · Routine

October 19 App Review correction: Settings → License now offers Unlock Chronoframe…
to confirmed non-owners before they spend any allowance. It opens the existing
StoreKit-priced purchase/restore sheet without inventing an operation refusal or
starting work after purchase. See `docs/app-review-iap-rejection-2026-10-19.md` for
the replacement’s signed sandbox and recording requirements.

Add `case license` to `SettingsTab`. Shows entitlement state, remaining allowance, and Restore
Purchases.

## T15 — Free test batch · Careful review

Blocking a large library's first transfer and telling the user to build a smaller folder in Finder
is a bad trial. When a plan exceeds the remaining allowance, offer **"Run a free test batch"**:

1. The user selects up to the remaining allowance from the already-reviewed plan.
2. Chronoframe **rebuilds and displays the exact reduced plan**.
3. Execution happens only after that reduced plan is confirmed.

**Never silently truncate.** The preview/execution agreement holds only because the reduced plan is
itself previewed and confirmed.

## T16 — Trial indicators · Routine

Remaining-allowance display in the Run and Deduplicate workspaces. Absent when unlocked.

Tasks T13–T16 touch `ChronoframeApp/**`, so `script/check_app_layer_changes_have_tests.sh`
requires a test with each change.

---

# Step 6 — Test matrices

## T17 — Mac App Store build lane · Routine

`MAS_BUILD` is defined only in `ui/archive-mas.sh`. Neither `swift test` nor the CodeQL
`xcodebuild` sets it, so any `#if MAS_BUILD` code is compiled by **zero** lanes. Add a CI job
building with `SWIFT_ACTIVE_COMPILATION_CONDITIONS=MAS_BUILD`.

### The metered variants are covered deterministically

Completed in the 2026-09-07 engineering refresh. The accessibility audit still runs as an ordinary
debug build rather than under `MAS_BUILD`, so it never depends on StoreKit, signing, or an App Store
account. Selected UI-test scenarios inject a locked entitlement and a production-ledger-derived
partial balance through `AppState`; the License pane therefore renders its allowance rows and
Restore button, and the Run and Deduplicate workspaces render their remaining-allowance indicators.
An explicit UI test asserts all four surfaces before the same scenarios enter the accessibility
audit.

## T18 — StoreKit configuration file · Routine

The Xcode StoreKit configuration file drives local purchase and restore tests. App acquisition
dates and original versions never confer access under the shipping policy, including synthesized
sandbox values. Keep Xcode-StoreKit, sandbox, TestFlight and production results separate.

## T19 — Manual matrix · Routine

Extend the TestFlight matrix in `docs/APP_STORE_RELEASE.md`: cached legacy grants ignored; product-load
failure; pending purchase; user cancellation; unverified transaction; refund; Family Sharing
revocation; Apple Account change; restore authentication failure; allowance survives reinstall;
refused run leaves originals untouched.

---

# Steps 7–9 — Release

## T20 — Create the in-app purchase · Manual

App Store Connect: non-consumable `com.nishith.chronoframe.unlock` at $14.99, **Family Sharing ON
(irreversible)**. Apple requires the first non-consumable to be submitted **with** a new app
version.

## T21 — Direct free access policy · Safety-critical

The owner approved the direct-free rules on October 16. No acquisition date, including an old sandbox date or a cached legacy grant, unlocks the app under the shipping default. Only the verified non-consumable entitlement does. Do not reintroduce the October 26 cutoff. Regressions cover the shipping policy, old cached test grants, purchase cancellation, purchase, relaunch and restore. Signed StoreKit and production verification remain separate release gates.

## T22 — Marketing and metadata copy · Routine

**Merged.** The free-tier variants are staged in documentation but must not be published before the
App Store price actually becomes free.

`site/index.html`, `site/faq.html`, `README.md`, `docs/APP_STORE_RELEASE.md`,
`docs/APP_STORE_METADATA.md`. "Free to try · $14.99 to unlock". **"No subscription, ever" stays
true** and is worth keeping prominent. Review notes must disclose the trial limits explicitly.

## T23 — Execute the release · Manual

1. Archive the final source with a new build number and install through TestFlight. Complete the focused signed checks.
2. Configure the app as Free and the non-consumable as $14.99 US with Family Sharing. Coordinate pricing with V2 availability if the older paid version is still listed.
3. Submit the app and first non-consumable together, retaining manual release.
4. Once approved, release V2, verify public pricing, allowance, purchase and restore, then publish website and marketing. There is no paid holding period.

---

# Carry-forward notes from step 2

- StoreKit's `AppTransaction` does not expose `revocationDate`; that property belongs to product
  `Transaction`. The live app-transaction adapter therefore supplies `nil`. Product refunds and
  Family Sharing revocations continue to flow through `Transaction.currentEntitlements`.
- The live adapter uses `AppTransaction.appTransactionID` when compiled with Swift 6.1 or newer.
  The older Swift 6.0 CI toolchain retains the signed `originalPurchaseDate` fallback, so both SDK
  generations compile while current release builds get Apple's stable account-scoped identifier.
- Step 2 implements `EntitlementState.locked` rather than the originally planned
  `.trial(allowance)`. The allowance belongs to the ledger, and wiring it into `EntitlementStore`
  would blur the two responsibilities. The UI composes them in T6 and step 5.

# Verification

```bash
/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache script/run_swift_test_suites.sh"
script/swift_meaningful_coverage.sh
script/check_agents_invariants_have_tests.sh
script/check_app_layer_changes_have_tests.sh
xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug \
  -derivedDataPath .tmp/ChronoframeDerivedData -destination "generic/platform=macOS" \
  CODE_SIGNING_ALLOWED=NO build
```
