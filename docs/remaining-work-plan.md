# Chronoframe — Remaining Review-Remediation Work

> Implementation plan for a fresh Claude Code session **running on macOS** (full
> Swift/Xcode toolchain). Assumes no memory of the prior remediation sessions, so
> it carries its own context. Read `AGENTS.md` (authoritative project memory +
> Safety Invariants) and `CLAUDE.md` (commands) before starting.

## 0. Context — what's already done

A code review produced findings #1–#9 plus a "missing tests" list. Findings
**#1, #2, #3, #4, #6, #7, #8, #9** and the missing-tests group are **already
implemented and merged to `main`** (PRs #152–#158). Do not redo them.

**Remaining work, in priority order:**

1. **Finding #5 — crash-window journaling** (Medium, safety-critical, deferred).
   The real engineering task.
2. **Offset-EXIF UTC-vs-local-day bucketing** — a product decision; only act on
   an explicit owner decision.
3. **Environment-gated items** — need credentials/hardware, not pure coding.

Repo layout (Swift-only):

- `ui/Sources/ChronoframeCore` — pure domain engine (no AppKit/SwiftUI).
- `ui/Sources/ChronoframeAppCore` — `@MainActor` stores/services + `OrganizerEngine`.
- `ui/Sources/ChronoframeApp` — SwiftUI views + `AppState`.
- `ui/Sources/ChronoframeCLIKit` / `ChronoframeCLI` — CLI.

## 1. Environment & validation — run locally before every push

```bash
# Authoritative unit tests (sandbox-safe HOME/cache prefix from CLAUDE.md)
/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache swift test --package-path ui"

# Filter while iterating, e.g. --filter DeduplicateExecutorFaultInjectionTests

# Xcode build (CodeQL builds this, not SwiftPM — keep them in sync)
xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug \
  -derivedDataPath .tmp/ChronoframeDerivedData -destination "generic/platform=macOS" \
  CODE_SIGNING_ALLOWED=NO build

# Gates
script/check_agents_invariants_have_tests.sh
script/check_app_layer_changes_have_tests.sh   # only if you touch App-layer source
script/swift_meaningful_coverage.sh            # 95% on deterministic domain logic
git diff --check
```

The prior sessions ran on Linux and **could not compile Swift**, so several PRs
needed CI round-trips for `@MainActor` / `nonisolated` / `Sendable` /
async-in-autoclosure errors. You have the toolchain — compile and run the full
suite locally before every push.

## 2. Discipline rules (non-negotiable)

- **Surgical changes in safety-critical code.** Executor/revert/dedupe diffs are
  audited. Every changed line must trace to the task; don't opportunistically
  refactor adjacent code.
- **Goal-driven for invariants.** Finding #5 touches Safety Invariant **#9**
  ("Organize, dedupe, and reorganize receipts are written before mutation where
  possible…"). Definition of done = *the invariant script passes with a new/
  updated `// AGENTS-INVARIANT: 9` test that failed before the fix.* Write the
  failing fault-injection test first, then fix.
- **New source files** must be added to **both** `ui/Package.swift` and
  `ui/Chronoframe.xcodeproj/project.pbxproj` (CodeQL builds the Xcode project; a
  file missing there fails silently). Test files don't need pbxproj edits.
- **Receipts are durable, cross-version artifacts.** Any new receipt/spool field
  or record kind must decode tolerantly so an older build can still revert (see
  the tolerant enums in `DeduplicateModels.swift`).
- Branch per task; commit trailers matching repo history; open PRs ready for
  review.

---

## 3. WORK ITEM 1 — Finding #5: crash-window journaling

### Defect

Each destructive executor **mutates first, records second**. A crash (power loss
/ `SIGKILL`) between the mutation and the durable record leaves an item that
actually moved/copied/trashed but is absent from recoverable receipt state, so
Run History can't reliably revert it.

Mutation sites (grep the symbols — line numbers drift):

- **`DeduplicateExecutor.swift`** — `fileOperations.trashItem(at:)` then
  `appendSpoolRecord(...)`. The Trash URL only exists *after* the trash call, so
  it can't be pre-recorded. (search: `func commit(plan:`, `trashItem`,
  `appendSpoolRecord`, `recoverInterruptedRuns`, `consolidatePendingReceipt`)
- **`TransferExecutor.swift`** — `finalizePreparedCopy(...)` (atomic temp→final
  rename) then `database.updateJobStatus(.copied)` then streaming receipt append.
  (search: `func apply(outcome:`, `finalizePreparedCopy`,
  `StreamingAuditReceiptWriter`, `recoverInterruptedRuns`)
- **`ReorganizeExecutor.swift`** — move then record. (search:
  `recoverInterruptedRuns`, the move call near the receipt write)

Existing recovery + tests to extend (don't reinvent):

- `DeduplicateExecutor.recoverInterruptedRuns(at:)`,
  `TransferExecutor.recoverInterruptedRuns(at:)`
- `DeduplicateExecutorFaultInjectionTests.swift`,
  `TransferExecutorCrashRecoveryTests.swift`,
  `DeduplicateExecutorRealFileManagerTests.swift`

### Recommended scope (PR 1 first; PRs 2–3 optional follow-ups)

**PR 1 — Dedupe Trash quarantine + WAL (highest value, most destructive path).**
The clean fix for Trash (whose result URL is unknown beforehand) is an
**app-owned quarantine**:

1. Before mutating, append an `INTENT` spool record
   `{originalPath, quarantinePath}`, where `quarantinePath` is a unique
   same-directory name you control (e.g. `<path>.<uuid>.cfquarantine` or
   `<dir>/.chronoframe-quarantine/<uuid>-<basename>`).
2. `rename(originalPath → quarantinePath)` (atomic within a volume).
3. Append `COMPLETED`/trash record after `trashItem(quarantinePath)` returns,
   recording the real Trash URL.
4. **Startup reconciliation** (`recoverInterruptedRuns`): for any `INTENT`
   without `COMPLETED`:
   - quarantine entry still exists → restore it to `originalPath` (the safest
     "undo the partial op" choice — document the policy) or finish the trash.
   - quarantine gone but Trash URL recorded → already trashed; finalize receipt.
   - Must be **idempotent** (recovery may run more than once).

   Keep the existing `PENDING`-receipt-before-mutation behavior; this adds
   per-item INTENT/COMPLETED granularity inside it.

- **Tests** (`DeduplicateExecutorFaultInjectionTests`, tag
  `// AGENTS-INVARIANT: 9`): use a `DeduplicateFileOperations` test double that
  aborts at each boundary — after INTENT-before-rename, after rename-before-trash,
  after trash-before-COMPLETED — then run `recoverInterruptedRuns` and assert the
  item is either fully trashed-and-recorded or safely restored, **never silently
  lost**. Add a same-dir quarantine-name-collision case. Each test must fail
  before the fix.

**PR 2 — Transfer copy INTENT/reconcile (lower urgency).** Copy leaves the source
intact, so the worst case is an un-revertable extra file in the destination, not
data loss. The destination path is known before the rename, so persist an INTENT
before `finalizePreparedCopy`, mark COMPLETED after the receipt append; on
startup reconcile a copied-but-unrecorded file (dest exists + matches planned
hash → add to receipt; else clean up the temp). The executor already uses a
SQLite `CopyJobs` status + streaming receipt + `.tmp` cleanup — extend those, do
not add a parallel journal. Extend `TransferExecutorCrashRecoveryTests`.

**PR 3 — Reorganize move INTENT/reconcile.** Move is destructive to the original
location → treat closer to PR 1's rigor. Same INTENT→mutate→COMPLETED + startup
reconcile pattern. Tag `// AGENTS-INVARIANT: 9`.

**Architectural note (do NOT fold in):** the three executors have separate
receipt/recovery code. A *shared durable mutation journal* would unify this and
is worth a tracked follow-up issue, but do not attempt the unification in the
same PRs as the behavior fix — keep diffs auditable.

### Definition of done (per PR)

Failing-first fault-injection test → fix → `swift test` green →
`script/check_agents_invariants_have_tests.sh` passes with the new
`AGENTS-INVARIANT: 9` test → coverage gate green → Xcode build green.

---

## 4. WORK ITEM 2 — Offset-EXIF date bucketing (product decision required)

`DateClassification.bucket` (`MediaDateResolver.swift`) keys folders on the
**UTC** calendar day. For EXIF timestamps carrying an explicit offset, the file
is bucketed by the resulting **UTC instant**, not the photographer's local day —
so a photo shot at `02:00 +05:00` (locally Jan 1) lands in the **Dec 31** folder.
`ChronoframeCoreMediaDateTests.testOffsetExifNearLocalMidnightBucketsByUTCInstant`
pins this current behavior.

**Only proceed on an explicit owner decision that local-day bucketing is wanted.**
If so: bucket offset-bearing dates by the date's components *in the EXIF offset's
timezone* (carry the offset through, or compute the local day at parse time),
update that characterization test to the new expectation, and add boundary tests.
⚠️ This changes folder layout for offset-tagged libraries — call it out in the
PR. If status-quo is preferred, leave it; the test already documents the behavior.

---

## 5. WORK ITEM 3 — Environment-gated items (not pure coding)

"Not evaluable" in the review; need resources, not just a Mac:

- **Release signing / notarization / stapling / production App Sandbox** — needs
  Developer ID credentials + distribution setup. Validate with
  `swift run --package-path ui ChronoframePackagingTool ui/build/Chronoframe.app`
  and a real signed archive.
- **Perceptual-video precision/recall** — needs the labeled calibration corpus
  (local-only, absent from repo).
- **Max-library scalability** — needs an agreed file-count/latency target + large
  fixtures.
- **Signed-sandbox tests** (bookmark restoration, external volumes, Trash) — need
  the signed app + real volumes.

Don't stub these; flag what's missing.

---

## 6. Suggested order

1. Finding #5 PR 1 (dedupe quarantine) — highest value, most destructive path.
2. Finding #5 PRs 2 & 3 (transfer, reorganize) — if pursuing full coverage.
3. Work item 2 only on an explicit product decision.
4. Work item 3 when environment/credentials are available.

Start every task by reading `AGENTS.md` §Safety Invariants and the target
executor's existing receipt/recovery code, write the failing fault-injection
test, then make the surgical fix.
