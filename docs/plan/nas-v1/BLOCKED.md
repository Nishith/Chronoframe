# NAS v1 blocked items

Status: shipped in PR #266. No open items.

Entry format: see "Blocked items" in `docs/plan/next-half/AGENT_RULES.md`. Only Nishith marks an item resolved.

## B-1 — G3 app smoke: launch and screen capture not permitted (resolved)
The permission classifier refused `open --env CHRONOFRAME_ENABLE_NAS=1 ui/build/Chronoframe.app` and `screencapture` during G3. Resolved 2026-11-07: the owner ran a Debug build at 54bee13 with `CHRONOFRAME_ENABLE_NAS=1`; the workspace renders, and choosing a local folder shows "Choose a folder on a network share. For folders on this Mac, use Deduplicate." The screenshot was shared in the session and not saved to `evidence/`.
