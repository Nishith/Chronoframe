# Chronoframe Remaining Production-Readiness Work

Status date: 2026-06-20

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

## Mandatory Release Gates Still Open

### 1. Developer ID Distribution

Required inputs are external to the repository:

- Install a `Developer ID Application` identity.
- Set `CHRONOFRAME_TEAM_ID`.
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
