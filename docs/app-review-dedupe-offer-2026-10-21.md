# Deduplicate unlock-offer regression — October 21, 2026

**Status (2026-11-21). Resolved.** Records the finding on signed 510 and its source correction. The correction (PR #252, merged 2026-11-16 as `03e8d1a`) shipped in 2.0 (511), where the signed retest passed; see [app-review-replacement-511-2026-10-21.md](app-review-replacement-511-2026-10-21.md). `RootSplitView` must keep observing both `RunSessionStore` and `DeduplicateSessionStore`.

## Signed finding

During the physical-Mac screen recording on TestFlight **2.0 (510)**, 102 exact duplicate PNG fixtures formed one group. The reviewed plan selected 101 removals against 100 remaining. Confirming cleanup twice returned to a paused review without the expected purchase offer. Both attempts failed closed: every fixture retained its baseline SHA-256 and no dedupe audit receipt was created. The fresh recording tester did not purchase.

The same session completed a one-file verified organize copy, consumed one copy allowance, and explicitly verified **Match** in History. The source and destination bytes match. Settings → License displayed the real lifetime product and $14.99 price. A changed-layout Reorganize request reached its unlock offer with **Nothing was changed**, was dismissed, and the original date-folder preference was restored. These passes do not close the missing Deduplicate purchase entrance or recorded-purchase gate.

The owner stopped and saved the recording. Original videos, account information, screenshots, full test logs and SHA-256 inventories remain local and ignored. This attempt must not be submitted as successful purchase proof.

## Cause and correction

`RootSplitView` presented the operation unlock sheet using `AppState.unlockRefusal`, a computed property reading two independent observable stores. The view observed `RunSessionStore`, but not `DeduplicateSessionStore`. A dedupe refusal could update the child workspace without refreshing the root's sheet presentation.

The root now observes both stores and reads their refusals directly through its presentation property. Authorization, allowance, retry and file-mutation behavior are unchanged.

## Regression verification

The new macOS UI regression confirms reviewed cleanup through its real confirmation dialog, injects a deterministic asynchronous allowance refusal, waits for the actual product/Restore/dismiss controls, and verifies that dismissal preserves the reviewed cleanup and exhausted allowance. The uncorrected app failed at the missing purchase control. The fixture uses isolated test defaults and fake StoreKit; it neither touches customer libraries nor proves a signed sandbox purchase.

The new UI regression passes on the corrected app (1 test, zero failures), after failing at the missing purchase control on the uncorrected app. Existing License purchase/cancellation/Restore UI tests pass (2 tests). All 37 focused `SettingsUnlockSafetyTests`, `DeduplicateSessionStoreTests` and `DeduplicateEngineTrialGateTests` passed, then the expanded Settings suite passed all 3 tests: its additional case verifies voluntary purchase, sheet Restore and direct License Restore clear a pending dedupe refusal before ownership publication and never recommit it. Whitespace, UI-test membership, navigation-title and XCTest-await guards pass.

Local logs: `.tmp/logs/dedupe-refusal-red-confirmed.log`, `dedupe-refusal-green-final.log`, `dedupe-refusal-green.log` (the existing License tests passed; the initial new test needed an exhausted-indicator selector correction), and `dedupe-refusal-unit.log`. macOS UI confirmation also exposes a Touch Bar copy; the regression explicitly chooses the on-screen control.

Build 510 was held and replaced by 511. The explicit signed 510 Restore and source-preservation results stay as build-specific history. No owner Go, App Review resubmission or public release occurred on 510.
