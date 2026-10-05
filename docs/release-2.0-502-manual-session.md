# Chronoframe 2.0 (502) — cancellation replacement

Prepared October 4, 2026. **Signed archive and App Store upload package prepared and validated locally. Not uploaded or installed through TestFlight; no review submission or owner Go.**

## Candidate

- Runtime source: `4868b4b` on `codex/fix-cancellation-summary`; [PR #241](https://github.com/Nishith/Chronoframe/pull/241).
- Actual archived and exported version: **2.0 (502)**, universal arm64/x86_64, macOS 14+.
- `CHRONOFRAME_BUILD_NUMBER=502` is required: the project's stamp script overrides `CURRENT_PROJECT_VERSION` without this environment variable.
- Package: `release-artifacts/2.0-502/mas-export/Chronoframe.pkg`.
- Package SHA-256: `e28da69d7031e441aa2a4e9763912ad9777f96bef7a04f3256716cbcff293093`.
- Apple Distribution signing, team EB2YPF68XZ, hardened runtime and sealed resources verified. The app extracted from the actual upload package passes `ChronoframePackagingTool --app-store`. A local Gatekeeper rejection is not an App Store processing or TestFlight result.
- Compiled cutoff unchanged: **2026-10-26T07:00Z**, October 26 at 00:00 PDT.

## Fix and evidence

The [owner's signed 501 test](release-2.0-501-manual-session.md) displayed Cancelled at 108 copied, while the ABORTED receipt and destination contained 844 verified copies. All 10,000 originals were unchanged. Build 501 remains held.

Cancellation now keeps the session busy (Stopping…), retains folder access and the destination lock, and continues consuming events until the engine supplies its final committed counts. Repeated cancel requests are ignored, another operation cannot replace a stopping run, and a completed transfer stays completed when the cancel click arrives late. Fresh/resumed transfer and revert/reorganize results carry final executor counts. Planning-only cancellation waits for the stream to end.

All **1,729 Swift tests** pass via `script/run_swift_test_suites.sh`; universal Release MAS_BUILD compilation, signed archive/export, package validation, invariant tags and whitespace checks pass. Regression coverage includes stale 108→844 progress, lock/access retention, late buffered completion, real cancelled fresh/resumed receipts, and late cancellation after a real COMPLETED receipt. These are source/local-package checks, not signed TestFlight manual results.

## Remaining release steps

- [ ] PR #241 hosted checks and CodeQL green, then merge. It includes the pending release evidence from #240; a separate #240 merge is unnecessary if #241 is merged.
- [ ] Upload 2.0 (502), confirm processing/export compliance, assign internal testers, install through TestFlight and verify the installed bundle version.
- [ ] Replace selected 501 in the existing macOS 2.0 draft with 502; retain Chronoframe Unlock in the same draft and the prepared screenshots/preview/IAP evidence.
- [ ] Repeat owner cancellation on a fresh empty disposable destination. Wait for Stopping to finish, then compare final UI count/status with receipt/files and verify original source hashes. Do not mark this passed from the local unit tests.
- [ ] Assess the remaining signed scenarios and record actual results or accepted limitations: Photos import, watched partial batch, old receipt upgrade, pair/sidecar retention, fresh/unavailable folders, signed StoreKit purchase/restore/cancel/offline, usability and real external-drive behavior where advertised.
- [ ] Owner Go with exact candidate identity, date and accepted residuals, then submit app and first IAP together.

The known last-in-flight crash-receipt gap remains documented in the 500/501 records. Keep production release manual and initially paid. For October 26 free pricing, paid V2 must be live by October 18 at 07:00 PDT to complete the project's seven-day hold before the earliest regional transition. Validate real paid-purchaser grandfathering; postpone pricing and ship an updated cutoff if approval slips. Hold website/free-launch announcements until the storefront is actually free and production checks pass.
