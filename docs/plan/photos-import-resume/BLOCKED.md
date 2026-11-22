# Photos import resume — blocked items

Status: shipped in PR #268; one item open (owner-only).

Entry format: see "Blocked items" in `docs/plan/next-half/AGENT_RULES.md`. Only Nishith marks an item resolved.

## Open items
### B-1 — G2 app smoke: screen access declined
- **WP:** G2 step 3.
- **What happened:** `ui/build.sh` exit 0; a seeded `.stopped` checkpoint (3 planned, 0 completed) at `.tmp/pir-smoke/staging/7B0E4C0A-3C1D-4E55-9A51-5E0C7A1D2F10/`; the Debug build launched with `CHRONOFRAME_PHOTOS_STAGING_DIR`, but the computer-use access request for `com.nishith.chronoframe` returned `user_denied`, so there is no UI observation.
- **Recommendation:** the owner runs row H-PIR-6 together with H-PIR-1 to H-PIR-5; the card appears only once Photos access is granted on this Mac.
- **Status:** open
