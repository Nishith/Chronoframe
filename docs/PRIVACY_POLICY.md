# Chronoframe Privacy Policy

Effective date: 2026-09-29

Chronoframe is designed to organize and deduplicate photo and video files on your Mac without uploading your library or collecting analytics.

## Data Collection

Chronoframe does not collect, transmit, sell, or share personal data.

Chronoframe does not include telemetry, analytics, advertising SDKs, tracking SDKs, or third-party crash reporting services.

## Photo And Video Files

Chronoframe works with folders you choose through the macOS folder picker and, if you authorize Photos access, with photos and videos you select from your Apple Photos library. Because macOS has no read-only Photos permission, Chronoframe requests read/write authorization, but it only reads and exports your originals and never adds to, modifies, or deletes anything in your Photos library. Files are processed on-device and stay on your Mac.

Chronoframe may read file contents, file names, paths, metadata, hashes, timestamps, and image or video features to provide its organize, preview, deduplicate, health, history, reorganize, and revert features. This information is not sent off-device by Chronoframe.

## Local Storage

Chronoframe stores app preferences and folder-access bookmarks on your Mac. Local Application Support data also includes watched-folder checkpoints, temporary Apple Photos exports, and a trial-usage ledger associated with an Apple-provided purchase identifier. These records are not sent to a Chronoframe server.

For each destination folder you choose, Chronoframe may create local support files such as:

- `.organize_cache.db`
- `.organize_logs/`
- `.organize_log.txt`

These files may include validated file identities, photo/video analysis features, copy-queue state, operation-lock diagnostics, receipts, and temporary recovery journals. They support previews, interruption recovery, history, revert, and faster future scans. They stay in the destination folder you selected and are never uploaded.

## Network Use

Chronoframe does not use the network for analytics, advertising, or tracking, and it never uploads your library.

There is one exception, for importing from Apple Photos: if you import photos or videos whose originals are stored only in iCloud, macOS downloads those originals through Apple's PhotoKit over your network connection so Chronoframe can copy them. This transfer happens between your Mac and your own iCloud account through the system, and Chronoframe does not send your media anywhere else.

The Mac App Store and Apple's StoreKit handle app downloads, the optional one-time unlock, restoring purchases, and verifying access. These operations may contact Apple. Chronoframe does not receive your payment-card details. Cloud storage services may separately sync folders you choose, under their own settings.

## Deletion Behavior

Chronoframe does not permanently delete duplicates. Deduplicate may temporarily rename approved files to a hidden same-folder quarantine path so it can verify and recover the mutation as a unit, then moves the verified files to the macOS Trash. Recovery metadata and filesystem bookmarks remain on-device.

## Contact

For privacy or support questions, contact us at support@chronoframe.app.
