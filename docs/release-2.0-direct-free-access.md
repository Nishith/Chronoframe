# V2 direct-free access rules — October 16, 2026

**Status (2026-11-21).** Records the October 16 owner decision and its implementation (merged as PR #244, `5f10b17`, 2026-10-17). The rules shipped in 2.0 (511). The current policy statement is in [free-trial-plan.md](free-trial-plan.md); launch status is in [V2_LAUNCH_CHECKLIST.md](V2_LAUNCH_CHECKLIST.md).

The owner confirmed there are no existing users and approved launching V2 directly as a free download. This supersedes the paid-to-free migration, seven-day paid rollout and October 26 acquisition cutoff. October 26 remains a target launch date, subject to testing and App Review.

## Approved behavior

- Free download; no subscription.
- 500 organized files and 100 duplicates moved to Trash, cumulatively per Apple Account on each Mac.
- Unlimited scanning, preview, duplicate review and history.
- $14.99 US non-consumable lifetime unlock with Family Sharing removes limits. Reorganizing an existing destination continues to require the unlock.
- Revert remains ungated and refunds corresponding allowance.
- Neither app acquisition dates nor cached legacy grants confer an unlock under the shipping policy.
- Purchase, restore and relaunch continue to resolve the owned non-consumable entitlement.

## Implementation

`ChronoframeUnlock.defaultPolicy()` now returns `GrandfatherPolicy.disabled`, which explicitly rejects live and cached legacy grants regardless of the date. Historical migration policies remain opt-in for deterministic tests. App transactions still identify the allowance account; usage records, bookmarks, personal settings and customer media are not reset or migrated. Settings License copy no longer depends on the clock or announces a price transition.

Local App Store metadata JSON and adjacent text files describe the approved free offer (see [APP_STORE_METADATA.md](APP_STORE_METADATA.md)).

## Verification

- Focused entitlement, default-store integration and License presentation suite: **98 tests passed**, zero failures. Includes old acquisition dates, stale cached test grants offline, initial 500/100 allowance, purchase cancellation, purchase, relaunch and restore.
- StoreKit configuration guard, all 26 invariant-tag checks and whitespace validation pass. The app-layer guard passes for the branch; relevant default-store and presentation regressions are included in this change.
- Universal arm64/x86_64 Release `MAS_BUILD` compilation with signing disabled: **PASS**, after allowing Xcode's SwiftUI macro service outside the sandbox. This is compilation evidence, not a signed archive or TestFlight result.
- Full Swift suite with coverage: **1,748 tests passed in 31 shards**, zero failures. Meaningful coverage **95.80% (17,301/18,059 selected deterministic lines)**, above the 95% gate; raw Swift coverage is 71.65%, not the same metric.
- The initial restricted run encountered macOS package recognition, Trash and socket failures and stalled at a filesystem-monitor test. It was stopped. The isolated package check and full coverage suite both pass with host services available; no traversal, Trash, socket or monitor code was changed to obtain that result.

Local logs: `.tmp/direct-free-focused.log`, `.tmp/direct-free-all-suites.log`, `.tmp/direct-free-coverage.log`, `.tmp/direct-free-mas-build-unsandboxed.log`.

## Outcome

The access-policy change merged in PR #244; signed builds from 504 onward contain it and 2.0 (511) shipped with it. The App Store download price was set to Free on 2026-10-22 after it was found still at $14.99 ([511 ledger](app-review-replacement-511-2026-10-21.md)). No upload, pricing change, review submission, website deployment or public post was performed by this access-rule step itself.
