# Chronoframe Remaining Production-Readiness Work

**510 hold:** its recorded 101-removal Deduplicate request was refused safely but did not present the unlock offer. The fresh tester remains unpurchased. The root view's missing observation of the dedupe store is being corrected and regression-tested; a signed replacement and recording are required. [Finding and correction](app-review-dedupe-offer-2026-10-21.md).

**October 21 resubmission:** PR #251 is merged; clean source `573682d` has successful CI/CodeQL and the License safety correction absent from 508. Replacement **2.0 (510)** passed archive/export/signature/package validation, uploaded, processed and is installed through TestFlight with About/receipt/signature verified. Explicit License Restore changed Free trial to Unlocked using the existing purchased sandbox tester and cleared a pending Organize refusal without copying or changing any fixture bytes. The fresh-account negative Restore and real $14.99 product discovery also pass. Signed fresh purchase/pending-operation verification, completed recording, store preparation, owner Go and resubmission remain pending. Signed 508 did pass real purchase/cancellation and unlock persistence. Live review submission selects rejected 507 plus Unlock Ready for Review; draft-501 statements below are historical. See [the current replacement and outstanding gates](app-review-resubmission-2026-10-21.md).

**October 19 App Review update:** app 2.0 (507) was rejected under 2.1(b) because
Chronoframe Unlock could not be found. The IAP remains Ready for Review in the
same submission. Prioritize the direct License purchase entry and the
[replacement-build sandbox/recording checklist](app-review-iap-rejection-2026-10-19.md).
The older candidate paragraphs below are history. Public-release product-proof
verification remains deferred until the app is approved and publicly available.

**Current candidate — October 17:** replacement **2.0 (507)** has passed archive/export/signature validation, uploaded, processed and is installed through TestFlight. Signed 506 opened and verified all 344 files in the cancelled receipt, but its 9,656-item receipt viewer rendered blank with excessive memory use. Build 507 moves receipt read/decode off the UI thread and renders rows lazily; 53 focused tests and a 10,000-item macOS UI regression pass. On signed 507 the owner confirms the 9,656-item receipt loads and scrolls with every destination status Match and survives an app restart; the cancelled-run Revert removes exactly its 344 destinations while all 9,656 retained copies and all 10,000 originals keep their recorded digests; preview, re-copy and a final repeat preview after Revert behave; and an eight-file exact-duplicate review → Trash → receipt → restore smoke passes. [PR #246](https://github.com/Nishith/Chronoframe/pull/246) merged on October 17. Earlier signed 504 allowance, purchase, relaunch and cancellation/resume evidence remains valid for unchanged behavior; Restore Purchases, pair/sidecar retention, trial dedupe allowance, remaining recovery/Photos/external-volume coverage, final hosted candidate checks and owner Go still need their own results. The App Store draft still selects 501 with older paid-transition copy; final build/copy/free-pricing configuration is pending. See [the 507 signed-session ledger](release-2.0-507-manual-session.md). Older candidate records below are historical.

**October 16 access-policy update:** the owner confirmed no existing users and approved a direct free launch. The app download is Free; the lifetime non-consumable is $14.99 US with Family Sharing. The 500/100 cumulative allowance and ungated refunding revert remain. Shipping policy disables acquisition-date and cached legacy grants. Historical paid-window, October 18 deadline, October 26 compiled cutoff and production-grandfathering gates below are superseded. Final-source CI, a new signed build, signed functional/StoreKit retests, store configuration and owner Go still gate release. No upload, price change, submission or publication is claimed by this update. See [the current launch sequence](APP_STORE_RELEASE.md#direct-free-launch).

Status date: 2026-10-05 (release scope for version 2.0 revised 2026-09-28)

This is the current follow-up plan after PR #160. The earlier review-remediation
plan described destination locking, immutable dedupe plans, quarantine,
mutation journaling, recovery coordination, and bounded Live Photo metadata as
future work. Those items are now implemented. Do not recreate them from the old
design notes in `prodsec/Chronoframe/`.

Authoritative current references:

- `AGENTS.md` — architecture, safety invariants, build and CI memory.
- `docs/SAFETY_AND_RECOVERY.md` — product and technical safety contract.
- `docs/TECHNICAL.md` — current modules, artifacts, and developer workflows.
- `docs/production-readiness-certification.md` — release gates and evidence.

**New release hold, October 4:** signed 502 Photos import copied 8 additional resources safely, but two Live Photo pairs were split across date folders and standalone movies were filed by import date despite embedded capture timestamps. The split pairs cannot be recognized by the same-directory pair detector. Fix capture-date handling and retest a replacement signed candidate; do not submit 502. See [the 502 session](release-2.0-502-manual-session.md).

**October 5 source fix complete:** `6a847f1` adds offset-aware video capture metadata and content-bound per-asset Photos date snapshots. Generated export → preview → verified transfer → final metadata-pair regressions pass, with 1,742 Swift tests, final 95.86% meaningful coverage, guards and universal Release MAS_BUILD compilation passing. Local signed replacement **503** archive/export and package validation/signatures pass; **not uploaded**. Remaining work is final-head hosted checks and [the exact signed TestFlight retests](release-2.0-503-manual-session.md). Build 502 stays held; no upload/submission/pricing/publication is authorized by this source-fix session.

## October 4 release evidence

Candidate **2.0 (501)** is uploaded, processed, selected in the App Store draft and installed through TestFlight. Runtime source is `6df85b4`. Its signed verified-copy/repeat/persistence and one-file watched-import smoke checks pass. Build 500 provides the unchanged-engine Trash/restore/hash-safe revert and crash-recovery evidence. The final checklist and honest remaining gates are in [V2_LAUNCH_CHECKLIST.md](V2_LAUNCH_CHECKLIST.md) and [release-2.0-501-manual-session.md](release-2.0-501-manual-session.md).

Build 501 is held: the owner's October 4 mid-copy cancellation displayed 108 copied while the ABORTED receipt and destination contain 844 verified copies. All 10,000 originals are unchanged. The source fix keeps the consumer, folder access and destination lease alive while stopping, then uses the engine's receipt-backed final result; signed replacement **2.0 (502)** is now installed and its October 4 owner mid-copy cancellation retest passes. The UI, finalized ABORTED receipt and actual destination agree at 311 verified copies; all 10,000 originals match the saved baseline. See [the 502 session](release-2.0-502-manual-session.md). This closes the stale terminal-count cancellation gate. Cross-album Photos, multi-item watched partial-batch retention, fresh/unavailable-folder, pair/sidecar retention, full old-receipt upgrade, signed StoreKit and usability/external-drive checks are not all recorded. They need actual results or the owner’s explicit assessment; no Go is recorded. Production paid-purchaser grandfathering occurs during the paid rollout, before free pricing.

## Completed In PR #160

- Immutable `DeduplicateScanSnapshot` and `DeduplicationPlan` evidence.
- Exact commit-footer/executor parity with missing identities failing closed.
- Dedupe same-directory quarantine, `O_NOFOLLOW` descriptor verification,
  Keep-wins pair/sidecar units, and rollback.
- Versioned dedupe journal with expected identity, quarantine state, predicted
  and actual Trash locations, and bookmark recovery data.
- Organize and reorganize mutation intent plus idempotent reconciliation.
- Cross-process destination operation lock across GUI, CLI, App Intent,
  recovery, scan, commit, revert, and reorganize paths.
- Sandbox-aware recovery states: needs volume, Trash location unverified, and
  manual action required.
- Bounded Live Photo metadata loading with four workers, per-item timeout,
  circuit breaker, cancellation, and external-reference restrictions.
- Fault-injection, process-boundary, lock-race, stale-identity, recovery,
  accessibility, and user-facing-copy regression coverage.
- Hosted CI green at implementation commit `80ff492`; hosted CodeQL is tracked
  separately in the certification report until it completes.

## Version 2.0 Release Scope (revised 2026-09-28)

After the September 2026 release bug bash, the owner set the scope for version
2.0: **one developer, Mac App Store distribution only.** The four June gates
below were written for a broader, team-staffed release. For 2.0 they apply as
follows. Their original text is kept below as a record; nothing in it is
relabelled PASS.

| June gate | Status for 2.0 |
|---|---|
| 1. Developer ID distribution | **Out of scope.** 2.0 ships only through the Mac App Store. Revisit if a direct-download build is planned. |
| 2. Signed App Sandbox matrix | **Replaced** by the focused manual session below, run on a signed TestFlight build. |
| 3. 100,000-file / 1-TB certification | **Deferred**, with the eight-hour soak. Replaced by the realistic performance check below. Do not advertise certified performance at the 100,000-file / 1-TB scale. |
| 4. Human sign-off | **Removed.** The owner records one Go decision (below). |

A concrete safety failure is never deferred by this revision. A failing
migration or a wrong-file deletion still blocks the release.

### What blocks 2.0

A credible unresolved risk of corrupting or deleting the wrong files; broken
copy, verification or recovery; an unusable core workflow; broken App Store
installation, purchase or access; or a new, unexplained safety-test failure.
Cosmetic defects, untested hardware combinations and small performance changes
do not block on their own; record them.

### Automated baseline (on the final merged commit)

- `script/run_swift_test_suites.sh`, the invariant, app-layer, Photos
  read-only, StoreKit and other CI guards, `script/swift_meaningful_coverage.sh`
  and `git diff --check`.
- The full UI suite and the accessibility audit. Record narrow exceptions with
  evidence rather than disabling checks.
- A Mac App Store Release build from clean tracked source with the 2.0 version
  and an explicit build number; confirm architectures, minimum macOS and
  sandbox entitlements.
- Hosted CI and CodeQL on the final commit.

### Focused manual session (signed TestFlight build)

The ad hoc QA build cannot prove bookmark or StoreKit behaviour, so these run on
TestFlight with the real bundle identity.

| Check | Pass condition |
|---|---|
| Fresh install and persistence | Correct version shown; folders and preferences survive relaunch; unavailable folders explain what to do. |
| Copy, repeat, revert | Source hashes unchanged; copies match; nothing overwritten; a repeat copies nothing new; revert removes only matching copies. |
| Dedupe and restore | Exactly the reviewed files go to the Trash; kept pair halves and sidecars survive; restored bytes match. |
| Interrupt and recover | Force quit mid-run, relaunch and recover twice: sources untouched, honest partial result, retry is idempotent. |
| Upgrade from 1.x | Settings, folder access and existing receipts still work after upgrading from the current public version. |
| Photos and watched batch | Cross-album import matches the review; the Photos library is untouched; a one-file watched batch leaves the other file pending. |
| StoreKit (sandbox) | New user gets the free allowance regardless of acquisition date; an old test-build legacy grant confers no access; purchase, restore, cancellation, offline relaunch and an exhausted allowance behave; revert works without unlocking. |
| Usability | Small window, light and dark, keyboard and VoiceOver through preview, review, confirmation and recovery. |
| External drive (if advertised) | One real drive: organize, disconnect and reconnect, bookmark restore. Record the drive and format tested and what was not. |

### Realistic performance check

Repeat the 1,000-file regression on an idle Mac, and run a representative
mixed-media library of roughly 10,000 files (record the real count and bytes):
cold/warm correctness, memory and cancellation. Block on corruption, hangs,
unbounded memory or unusable cancellation, not on modest latency.

### Go decision

The owner records the exact candidate commit, version/build and archive identity; disabled legacy-unlock shipping policy; checks passed with evidence links; accepted residual risks with impact and workaround; and the decision and date. Signed 504 with the October 16 direct-free policy was uploaded, processed and installed through TestFlight. October 17 testing exposed a History receipt-viewer permission bug; a replacement signed candidate and focused receipt/recovery retest are now required. See [the signed-session evidence](release-2.0-504-manual-session.md). There is no compiled acquisition cutoff, customer settings migration or seven-day paid window. See [the access-rule record](release-2.0-direct-free-access.md).

## Original June 2026 Release Gates (superseded for 2.0)

### 1. Developer ID Distribution

Required inputs are external to the repository:

- Install a `Developer ID Application` identity.
- Set `CHRONOFRAME_DEVELOPMENT_TEAM`.
- Configure `CHRONOFRAME_NOTARY_PROFILE`.
- Run the non-local `ui/archive.sh` path.
- Preserve notarization submission/result, stapling validation, Gatekeeper
  assessment, and the final artifact SHA-256.

An ad hoc `--local` archive is useful for structure validation but is not
release evidence.

### 2. Signed App Sandbox Matrix

Run the exact signed and stapled candidate on:

- Internal APFS.
- External APFS.
- External exFAT.

Cover bookmark restore, organize and verification, dedupe Trash and revert,
forced termination at each journal boundary, external-volume disconnect,
reconnect, and repeated idempotent recovery. Record the app commit, artifact
checksum, volume format, macOS version, and result for every row in the
certification report.

### 3. 100,000-File / 1-TB Certification

This requires real allocated media and sufficient storage; sparse files are not
valid throughput evidence. Record:

- Dataset construction and correctness manifest.
- Filesystem and volume model.
- Direct sequential BLAKE2b baseline.
- Cold and warm Chronoframe commands.
- `/usr/bin/time -l` output and peak RSS.
- Warm-scan latency, cancellation latency, and cold/warm decision parity.

Required thresholds remain in `docs/production-readiness-certification.md`.

### 4. Human Sign-Off

- Engineering owner.
- Security/privacy reviewer.
- Accessibility release owner (automated audit is already green).
- Release owner.
- Final candidate commit and artifact checksum.

## Follow-Up Confidence Work

The 2026-06-20 perceptual-video calibration passed its current acceptance
thresholds. The implementation fixes and the `0.25s` frame-time tolerance are
well supported, but the labeled corpus is still small for threshold confidence.
Before changing `frameHammingThreshold`, `aggregateMedianThreshold`, or another
default, expand the hard-negative set and follow
`docs/video-dedupe-calibration-rubric.md` §6.

## Product Decision Resolved — Local-Day EXIF Bucketing (implemented 2026-06-21)

**Decision (owner):** explicit-offset EXIF timestamps now bucket by the
photographer's **local calendar day**, not the UTC instant. A `02:00 +05:00`
shot (locally Jan 1) files under **Jan 1**; a `22:00 -05:00` shot (locally
Dec 31) files under **Dec 31**.

**Implementation.** `NativeMediaMetadataDateReader` retains the EXIF UTC offset
(`parseImagePropertyDateWithOffset` / `offsetSeconds`) and surfaces it via
`PhotoMetadataDate`. `ResolvedMediaDate.bucketTimeZoneOffsetSeconds` carries it
through `FileDateResolver` into `DryRunPlanner` (and `CopyPlanBuilder`), where
`DateClassification.bucket(for:timeZoneOffsetSeconds:)` formats the folder day in
that offset's timezone. The resolved `date` stays a **true UTC instant**, so
sorting, capture-date clustering, and dedupe proximity are unchanged. Offset-less
EXIF (UTC wall-clock), filename, filesystem, and user-override dates keep their
prior UTC-day bucketing byte-for-byte. New `Codable`/protocol fields are
optional/defaulted, so older persisted review rows and external readers stay
compatible. Covered by `ChronoframeCoreMediaDateTests` (updated characterization
test `testOffsetExifNearLocalMidnightBucketsByLocalDay` plus `+`/`-` boundary,
offset-string-parsing, and resolver-plumbing tests).

> ⚠️ **Release note required.** This changes destination folder layout for
> offset-tagged libraries organized before this change. A re-run/reorganize is
> needed to move affected near-midnight files into their new local-day folders;
> call this out in the release notes.

## Validation Before Every Push

```bash
/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache script/run_swift_test_suites.sh"

script/check_agents_invariants_have_tests.sh
script/check_app_layer_changes_have_tests.sh
script/swift_meaningful_coverage.sh

xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe \
  -configuration Debug -derivedDataPath .tmp/ChronoframeDerivedData \
  -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build

git diff --check
```

When a new Swift source file is used by the app, keep SwiftPM and
`ui/Chronoframe.xcodeproj/project.pbxproj` membership synchronized.
