# V2 direct-free access rules — October 16, 2026

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

Local App Store metadata JSON and adjacent text files now describe the approved free offer. They have not been pasted into App Store Connect. The website and social publication remain separate launch actions.

## Verification

- Focused entitlement, default-store integration and License presentation suite: **98 tests passed**, zero failures. Includes old acquisition dates, stale cached test grants offline, initial 500/100 allowance, purchase cancellation, purchase, relaunch and restore.
- StoreKit configuration guard, all 26 invariant-tag checks and whitespace validation pass. The app-layer guard passes for the branch; relevant default-store and presentation regressions are included in this change.
- Universal arm64/x86_64 Release `MAS_BUILD` compilation with signing disabled: **PASS**, after allowing Xcode's SwiftUI macro service outside the sandbox. This is compilation evidence, not a signed archive or TestFlight result.
- Full Swift suite with coverage: **1,748 tests passed in 31 shards**, zero failures. Meaningful coverage **95.80% (17,301/18,059 selected deterministic lines)**, above the 95% gate; raw Swift coverage is 71.65%, not the same metric.
- The initial restricted run encountered macOS package recognition, Trash and socket failures and stalled at a filesystem-monitor test. It was stopped. The isolated package check and full coverage suite both pass with host services available; no traversal, Trash, socket or monitor code was changed to obtain that result.

Local logs: `.tmp/direct-free-focused.log`, `.tmp/direct-free-all-suites.log`, `.tmp/direct-free-coverage.log`, `.tmp/direct-free-mas-build-unsandboxed.log`.

## Next release step

Review and merge this access-policy change with green hosted checks, then build a new signed candidate containing all final fixes. Complete signed allowance, purchase/restore and focused Photos/cancel/recovery checks on that candidate. Verify the free app price and $14.99 unlock with Family Sharing in App Store Connect, update the draft copy, submit app and first IAP together, and retain manual release. No upload, pricing change, review submission, website deployment or public post was performed in this access-rule step.
