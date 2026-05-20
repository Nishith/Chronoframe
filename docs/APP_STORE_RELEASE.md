# Mac App Store Release Checklist

This checklist is the release source of truth for Chronoframe's first Mac App Store submission.

## Release Gate

Chronoframe is ready to submit only when all items below are complete:

- PR #83 or equivalent app icon cleanup is merged to the release branch.
- `swift test --package-path ui` passes with the local cache/home environment from `AGENTS.md`.
- `xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug -derivedDataPath .tmp/ChronoframeDerivedData -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build` passes.
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
- Privacy policy URL: publish `docs/PRIVACY_POLICY.md` as a web page before submission.
- Support URL: publish FAQ and troubleshooting pages from `docs/`.
- Marketing URL: product page with screenshots, demo video, pricing, privacy promise, and support links.

Short description:

> Organize messy photo and video folders without changing the originals, then review and remove duplicates safely through Trash.

Keywords:

> photo organizer, duplicate photos, dedupe, media organizer, EXIF, photo cleanup, Mac photos, folder organizer, backup cleanup

Review notes:

> Chronoframe is a sandboxed macOS photo/video organizer. It only accesses folders selected by the reviewer through the standard macOS folder picker. Organize copies files into a chosen destination and does not modify originals. Deduplicate moves reviewer-approved files to the macOS Trash only; it does not hard delete. The app runs on-device, does not upload photos, and does not include analytics, telemetry, advertising, or crash reporting services. Local cache, log, and receipt files are created in the selected destination to support preview, history, and revert.

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

## TestFlight Matrix

Run these against the signed App Store build:

- Fresh install on a clean macOS account.
- Existing install upgrade from the latest GitHub release build, if applicable.
- Organize from an internal folder to an internal destination.
- Organize from an external drive to an internal destination.
- Organize from iCloud Drive with originals downloaded locally.
- Deny folder access, then retry with valid access.
- Quit during preview and transfer; relaunch and verify user-facing recovery.
- Deduplicate exact duplicates, similar photos, RAW+JPEG pairs, and Live Photo pairs.
- Confirm dedupe moves to Trash and Run History can restore supported receipts.
- Unplug or unmount a selected drive before scan/transfer and verify plain-language failure copy.
- Scan a large library of at least 25,000 files.
- Verify no network connections are required for organize, dedupe, history, help, or settings.

## Launch Tasks

- Publish privacy policy, support, FAQ, and troubleshooting pages.
- Build a landing page around the safety promise: originals untouched, preview before changes, Trash-only dedupe, on-device processing.
- Record a 60-second demo video.
- Recruit 20-50 TestFlight users with messy real-world libraries before public launch.
- Prepare launch posts for Mac utility communities, photography groups, and personal archive workflows.
- Monitor App Store reviews and support email daily during launch week.
