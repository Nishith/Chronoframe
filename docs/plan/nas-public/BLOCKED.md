# NAS public — blocked items

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
### B-1 — `docs/SAFETY_AND_RECOVERY.md` still describes the old Deduplicate network warning
- **WP:** WP-04 (found by reviewer; file not in any WP's owned paths)
- **Command:** `sed -n 114,118p docs/SAFETY_AND_RECOVERY.md`
- **Error:** Text says Deduplicate on a network share "shows only a one-time network warning"; since NASP WP-01 (`a6fc3d8`) it refuses non-local folders. The doc is now false.
- **Tried:** nothing — outside owned paths (AGENT_RULES hard rule).
- **Options:** 1) Owner approves a one-sentence edit: "…if you point it at a folder on a mounted network share it refuses the folder, because Chronoframe has not verified that files moved to the Trash on a network share can be put back." 2) Leave until the release docs pass.
- **Recommendation:** Option 1 before merging `feature/nas-v1`; it is a one-line doc fix with no code impact.
- **Status:** resolved (Nishith approved option 1, 2026-11-08; see commit "NASP B-1")
