# Mac App Store Release Checklist

This checklist is the release source of truth for the next Chronoframe Mac App Store candidate.

## Release Gate

Chronoframe is ready to submit only when all items below are complete:

- Every mandatory row in [production-readiness-certification.md](production-readiness-certification.md) is `PASS`, with the final candidate commit and artifact checksum recorded.
- `script/run_swift_test_suites.sh` passes with the local cache/home environment from `AGENTS.md`.
- `script/check_agents_invariants_have_tests.sh` and `script/swift_meaningful_coverage.sh` pass.
- `xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug -derivedDataPath .tmp/ChronoframeDerivedData -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build` passes.
- The macOS UI/accessibility suite passes without regressing the stored baseline.
- `./ui/archive-mas.sh --local` passes bundle structure validation.
- A signed non-local `./ui/archive-mas.sh` archive exports successfully with Apple Distribution or 3rd Party Mac Developer Application signing.
- The exported build uploads to App Store Connect and processes successfully.
- Internal TestFlight passes the manual matrix below.
- App Store metadata, screenshots, privacy policy URL, support URL, and pricing are complete in App Store Connect.

## App Store Connect Metadata

Recommended initial listing:

- Name: Chronoframe
- Subtitle: Safe photo organizer
- Category: Photo & Video
- Price: USD 14.99 introductory; move to USD 19.99 after launch reviews accumulate.
- Copyright: 2026 Nishith Nand
- Privacy policy URL: https://chronoframe.app/privacy.html (live, verified 2026-05-23).
- Support URL: https://chronoframe.app/support.html (live, verified 2026-05-23).
- Marketing URL: https://chronoframe.app/ (live, verified 2026-05-23).

Short description:

> Organize messy photo and video folders without changing the originals, then review and remove duplicates safely through Trash.

Keywords:

> photo organizer, duplicate photos, dedupe, media organizer, EXIF, photo cleanup, Mac photos, folder organizer, backup cleanup

Review notes:

> Chronoframe is a sandboxed macOS photo/video organizer. It only accesses folders selected by the reviewer through the standard macOS folder picker. Organize copies files into a chosen destination and does not modify originals. Deduplicate moves reviewer-approved files to the macOS Trash only; it does not hard delete. Approved mutation units may be temporarily renamed inside the selected folder for content verification and interruption recovery. The app runs on-device, does not upload photos, and does not include analytics, telemetry, advertising, or crash reporting services. Local cache, lock, journal, log, and receipt files are created in the selected destination to support preview, recovery, history, and revert.

## Screenshot Set

Create 6-8 Mac App Store screenshots from a clean, realistic sample library:

- Organize setup with source, destination, and layout selected.
- Organize preview showing files that will copy and any review-needed items.
- Transfer complete with receipt/history visibility.
- Deduplicate scan summary.
- Duplicate cluster review with keep/delete choices.
- Commit footer showing Trash-only behavior.
- Run History showing revert availability.
- Privacy/help screen showing on-device processing.

Avoid screenshots with personal photos, real names, real file paths, pricing claims, or unsupported promises.

## Local StoreKit Testing

`ui/Chronoframe.storekit` models the one non-consumable unlock, and the shared
Chronoframe scheme references it, so a debug run from Xcode has a working store
without an App Store Connect round-trip. **Before trusting any local purchase result, verify the configuration is
actually loaded:** Product → Scheme → Edit Scheme → Run → Options →
StoreKit Configuration should name `Chronoframe.storekit`. If it is empty,
purchases fail as unavailable and every local result below is meaningless.
This check belongs here and nowhere else — a signed TestFlight or App Store
build takes its products from App Store Connect and ignores this file
completely.
`script/check_storekit_config_matches_policy.sh` keeps the file and that
reference honest in CI, but only Xcode can confirm it is actually loaded.

**Three environments, three different truths. Do not merge their results.**

| Environment | What it is good for | What it lies about |
|---|---|---|
| Xcode StoreKit configuration | Purchase, restore, refund, revocation, Ask to Buy — all on demand | `AppTransaction` is synthesized, so grandfathering is whatever the local config says |
| Sandbox (App Store Connect tester) | Real Apple accounts, real receipt signing | **`originalAppVersion` is always `1.0`** |
| TestFlight | Closest to production | Slow to iterate; refunds and revocations are not on demand |

### The sandbox grandfathering trap

**The sandbox always reports `originalAppVersion` as `1.0`.** A fresh install by
a brand-new sandbox tester therefore looks like an ancient purchase. Anything
keyed to that field reads "bought long ago", and a naive test concludes
grandfathering works when it has proved nothing.

Chronoframe does not key on that field — grandfathering is anchored to the
signed `originalPurchaseDate` against `ChronoframeUnlock.grandfatherCutover`, precisely
because a version boundary misclassifies customers in both rollout windows. But
the trap still catches the *test*: a sandbox account's `originalPurchaseDate` is
the date that account first downloaded the app, which is today, so a sandbox
tester is correctly **not** grandfathered and it is easy to misread that as a
bug.

To exercise both sides deliberately, inject `AppTransactionClient` rather than
trusting the environment. It exists for this: supply an `AppTransactionInfo`
with an `originalPurchaseDate` either side of the cutover and assert the
resolver's answer. That is a unit test, it runs in CI, and it does not depend on
which store environment happens to be attached.

## TestFlight Matrix

Run these against the signed App Store build:

- Fresh install on a clean macOS account.
- Existing install upgrade from the latest GitHub release build, if applicable.
- Organize from an internal folder to an internal destination.
- Organize from an external drive to an internal destination.
- Organize from iCloud Drive with originals downloaded locally.
- Deny folder access, then retry with valid access.
- Quit during preview and transfer; relaunch and verify user-facing recovery.
- Force termination after each organize, deduplicate, and reorganize journal boundary; relaunch and verify idempotent recovery.
- Start competing app, CLI, and App Intent mutations against one destination; verify exactly one lease succeeds and every loser fails before touching media.
- Deduplicate exact duplicates, similar photos, RAW+JPEG pairs, and Live Photo pairs.
- Change a planned dedupe target, pair partner, and sidecar after scan; verify every stale unit is preserved.
- Confirm dedupe moves to Trash and Run History can restore supported receipts.
- Unplug or unmount a selected drive during pending recovery; verify **Needs Drive**, reconnect, and verify recovery remains idempotent.
- Scan a large library of at least 25,000 files.
- Verify no network connections are required for organize, dedupe, history, help, or settings.

### Free trial and unlock

Each line names the behaviour being checked, because several of these look like
bugs when they are working correctly. Run them against a **Mac App Store**
build: the Developer ID build is unrestricted by settled policy and meters
nothing, so it can only ever pass these vacuously.

- **The unlock is purchasable at all.** Before anything else, open the unlock
  sheet and confirm the product appears with a price from App Store Connect. A
  signed build ignores the local StoreKit configuration entirely, so a missing
  product here means an App Store Connect problem — not a scheme problem.
- **Offline legacy access, warm cache.** A grandfathered customer runs once
  online, then launches with the network off. They stay **unlocked** —
  `EntitlementResolver` falls back to the cached legacy grant and returns
  `.unlocked(reason: .legacyPurchase)`. No allowance indicator, no metering,
  nothing describing them as a trial user.
- **Offline legacy access, cold or stale cache.** The same customer on a Mac
  that has never resolved online, or with a cached grant older than 90 days
  (`GrandfatherPolicy.defaultMaximumCacheAge`). There is no cache to lean on, so
  the entitlement resolves to `verificationUnavailable`: metered, and a large
  run **is** refused. Verify the refusal says the purchase could not be
  confirmed and offers Restore — it must never say the free trial is used up,
  because this customer paid.
- **Product-load failure.** Refuse a run with the store unreachable. The sheet
  offers Try Again and Restore, shows **no price at all** rather than a guess,
  and the free test batch stays *pressable* — it needs no price, so a stalled
  lookup must not disable it.
- **Pending purchase (Ask to Buy).** Buy on a managed account and leave the
  request pending. Nothing unlocks, and nothing claims the purchase failed.
  Approve from the organizer's device: the app unlocks without a relaunch.
- **User cancellation.** Cancel the payment sheet. No charge, and no copy
  saying a charge was taken. The refused run is still un-run — it does not
  start on the way back.
- **Unverified transaction.** A transaction that fails signature verification
  leaves the customer locked, but the sheet leads with **Restore, never Buy**,
  and nothing anywhere calls it a spent trial. They may already own it.
- **Refund.** Have a purchase refunded through App Store Connect. The
  entitlement reverts, the allowance indicators reappear in the Run and
  Deduplicate workspaces, and Settings → License updates **without a
  relaunch** — the transaction observer drives it.
- **Family Sharing revocation.** The organizer removes sharing. Same
  expectation as a refund, arriving by a different route.
- **Apple Account change.** Sign out, sign in as a different account, and check
  the remaining allowance. Quota is per Apple Account per Mac, so the new
  account starts fresh and cannot inherit the previous one's spend.
- **Restore authentication failure.** Start Restore Purchases and cancel the
  authentication prompt. It reports plainly that the restore did not complete —
  it must **not** conclude the purchase does not exist.
- **Allowance survives reinstall.** Spend part of the allowance, delete the
  app, reinstall, and check the remaining count. The ledger lives at
  `~/Library/Application Support/Chronoframe/trial/ledger.db`, outside the app
  bundle, so deleting the app must not reset the meter.
- **A refused run leaves originals untouched.** Exceed the remaining allowance
  on a real card. Nothing is copied, no receipt is written, Run History gains
  no entry, and every source file is byte-identical afterwards. Confirm the
  message says the originals were untouched, and that it is true.
- **The free test batch copies exactly what it showed.** Refuse a large run,
  open the batch offer, note the file list, and run it. Only those files land.
  Then repeat, moving or editing one of the listed files between confirming and
  running: it is skipped, and the run says how many it could not copy rather
  than quietly copying fewer.

## Launch Tasks

- Publish privacy policy, support, FAQ, and troubleshooting pages. (Done: privacy and support pages live at https://chronoframe.app/privacy.html and https://chronoframe.app/support.html, verified 2026-05-23.)
- Build a landing page around the safety promise: originals untouched, preview before changes, Trash-only dedupe, on-device processing. (Done: https://chronoframe.app/ live, verified 2026-05-23.)
- Record a 60-second demo video.
- Recruit 20-50 TestFlight users with messy real-world libraries before public launch.
- Prepare launch posts for Mac utility communities, photography groups, and personal archive workflows.
- Monitor App Store reviews and support email daily during launch week.
