# Photos import resume — blocked items

Rule: log it, then continue with the next independent WP. Only Nishith marks an item resolved.

## Template
### B-<n> — <short title>
- **WP:** <id>
- **Command:** `<exact command>`
- **Error:** <exact text>
- **Tried:** <what, in order>
- **Options:** 1) … 2) …
- **Recommendation:** <one option, one sentence>
- **Status:** open | resolved (<commit or decision>)

## Open items
### B-1 — G2 app smoke: screen access declined
- **WP:** G2 step 3
- **Command:** `open -n --env CHRONOFRAME_PHOTOS_STAGING_DIR="$PWD/.tmp/pir-smoke/staging" ui/build/Chronoframe.app`, then a computer-use access request for Chronoframe
- **Error:** access request returned `user_denied` for `com.nishith.chronoframe`
- **Tried:** `ui/build.sh` (exit 0); seeded a `.stopped` checkpoint (3 planned, 0 completed) at `.tmp/pir-smoke/staging/7B0E4C0A-3C1D-4E55-9A51-5E0C7A1D2F10/`; launched the Debug build with the staging override (exit 0, process started); requested access once; not retried. The seeded directory was still present after the launch refresh, which is consistent with the checkpoint being judged resumable but is not a UI observation.
- **Options:** 1) Owner runs row H-PIR-6 and saves the screenshot. 2) Owner allows the access prompt in a later session and the orchestrator captures it.
- **Recommendation:** Option 1, alongside H-PIR-1…5, since the card only appears once Photos access is granted on this Mac.
- **Status:** open
