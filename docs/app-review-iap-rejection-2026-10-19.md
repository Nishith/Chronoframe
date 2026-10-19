# App Review purchase discovery correction — October 19, 2026

## Status

Apple rejected app **2.0 (507)** under **2.1(b), App Completeness** on October 19:
the reviewer could not find “Chronoframe Unlock” in the binary. Review device:
MacBook Air (15-inch, M3, 2024). Submission:
`cdf1ea79-235f-4faa-8743-40ab920109f4`.

The owner authorized the focused fix, configuration verification, sandbox evidence
preparation and resubmission work. Source changes are isolated from the primary
checkout’s uncommitted design changes on `codex/direct-license-purchase`, based on
main `8c6948c`. Build 507 remains the last uploaded build observed in TestFlight;
**508 is the intended replacement number**, not a claim of upload or approval.
Physical-Mac signed sandbox purchase/restore and the requested recording remain pending.

## Findings and correction

Build 507’s License tab has Restore Purchases but no direct purchase entry. Its
purchase sheet requires an operation refusal (over allowance or locked Reorganize).
This is a concrete discovery gap; it does not prove that Apple encountered no
other StoreKit availability issue.

The replacement adds **Chronoframe → Settings… → License → Unlock Chronoframe…**.
The sheet fetches the actual product and localized price before showing the buy
button. Voluntary purchase explains the lifetime unlock without inventing a
refused run, used-up allowance or Reorganize request. Success updates License and
closes the sheet; it never starts or retries a file operation. The existing
operation-triggered sheet and free-batch flow remain available.

Purchase is offered only to confirmed non-owners in the App Store channel, even
with a full allowance or unavailable ledger. Loading/unconfirmed entitlements
lead to checking/restoration, and already-unlocked or Developer ID users are not
offered another purchase. Settings and the operation sheet observe the same
entitlement store. UI fixtures inject a fake store rather than contacting Apple.

## App Store Connect observations (read-only, October 19)

- The current submission contains two items: app **2.0 (507), Rejected** and
  **Chronoframe Unlock, Ready for Review**. The IAP itself was not shown Rejected.
- Product ID matches the binary: `com.nishith.chronoframe.unlock`.
  Apple IAP ID: `6819083459`; type: Non-Consumable.
- All 175 countries/regions selected; not removed from sale. United States current
  price is **$14.99**. Family Sharing is enabled.
- Paid Apps Agreement is **Active (New Agreement Available)**. No new terms were
  accepted. The active agreement observation is not a successful transaction test.
- The saved app/IAP notes describe the direct-free policy, but the purchase path
  depends on exceeding allowance. App notes have no recording attached. Manual
  version release is selected. No pricing, agreement, submission or product changes
  were made during this inspection.

Apple’s [sandbox review guidance](https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases)
states that IAPs can function during review before approval. The first non-consumable
must be included with an app version in the same submission:
[submission guidance](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/).

## Validation ledger

- Initial focused Swift tests: **58 passed**, covering License eligibility,
  optional-refusal purchase wording and localized price, fake purchase/restore
  propagation without starting an operation, and actual rendered price layout.
- Existing entitlement/restore, free-batch and trial-status suites: **84 passed**.
- The three new macOS UI cases pass: direct purchase before exhaustion,
  cancellation followed by explicit restore, and unavailable-product Retry/Restore.
  The existing metered License/workspace indicator case also passes.
  The purchase-sheet contrast, element detection and description audit passes
  within the modal. Its handler scopes out the inactive, dimmed Settings underlay
  (which has a separate scenario audit), and only excludes the native unlabeled
  hosting group exactly matching the sheet bounds. Every purchase control and
  unidentified audit issue remains fatal. Initial runs exposed container identifier
  propagation; explicit accessible containment preserves each button’s identifier.
- Full sharded Swift tests and meaningful coverage are running. Signed replacement
  archive/export and hosted checks are not yet recorded.
- Signed Release MAS_BUILD, replacement upload, sandbox transaction and physical-Mac
  recording: pending. Local fake transactions never count as sandbox/production evidence.

## Physical-Mac evidence session

Use the replacement installed through TestFlight on a real Mac, a sandbox test
account and disposable source/destination folders. Preserve existing owner settings,
bookmarks, allowance records and purchases. Use a fresh sandbox account for a new
purchase; reinstalling does not reset allowance or purchase ownership.

1. Start a screen recording from the Mac desktop, launch Chronoframe and show
   About’s actual version/build. Record the account’s storefront, without showing
   credentials or personal media.
2. Demonstrate choosing separate folders, Preview Plan, approving a small verified
   copy and inspecting History. Show duplicate review/Trash/recovery on disposable
   copies if demonstrating those core flows; do not empty Trash.
3. Open Settings → License with free allowance still remaining. Click
   Unlock Chronoframe… and show the product’s localized price and Restore Purchases.
   Cancel one Apple sandbox purchase and confirm access/allowance is unchanged.
4. Complete a new **sandbox** purchase. Capture Apple’s sandbox success and License
   becoming Unlocked, then quit/relaunch and confirm the verified unlock persists.
5. Exercise **Restore Purchases explicitly**, using a signed test installation that
   has not already recovered ownership automatically. If launch recovery already
   shows Unlocked, record that separately; it is not a button-driven restore test.
   Do not reset the owner’s ledger or entitlement to force the screen.
6. Demonstrate the other purchase entrances (an over-allowance operation and locked
   Reorganize) with a separate unowned sandbox state as needed. They use the same
   single product; there is no subscription, second SKU or Chronoframe login.

Record actual results, build/source/package identities and recording path before
claiming completion. Have the owner confirm any remaining signed release gates.

## Resubmission preparation

The exact purchase navigation is prepared in `docs/APP_STORE_METADATA.md`.
After the signed checks and recording are complete, select the validated replacement
build, update the app and IAP review notes, replace the IAP review screenshot with
the real signed purchase screen, and attach the requested physical-Mac recording
in App Review Information. Keep Chronoframe Unlock and the app together in the
submission; retain manual release. Public app Free pricing remains coordinated
with approved V2 release, not changed as part of this code correction.

Draft reply — send only after the replacement and real recording are attached:

> Thank you. We have added a direct purchase entry at Chronoframe → Settings… →
> License → Unlock Chronoframe…. The sheet displays Chronoframe Unlock
> (com.nishith.chronoframe.unlock) and the localized App Store price. Reviewers do
> not need to exhaust the free allowance or configure a library to reach it.
> Restore Purchases is available from License and the purchase sheet while locked.
> No Chronoframe sign-in or demo account is required. The replacement build and
> attached physical-Mac recording demonstrate the sandbox purchase and access flow.

Do not send this draft with placeholders or infer a completed restore from automatic
entitlement recovery. Record the tested build and recording filename alongside it.
