# NAS v1 blocked items

Rule: when blocked, add an entry here, then continue with the next WP whose dependencies are met. Never work around a blocker by editing outside owned paths or by weakening a rule.

## Template

### B-<n> — <short title>
- **Task:** WP-<id> / gate / hardware row
- **Command:** `<exact command>`
- **Error:** `<exact output, trimmed to the relevant lines>`
- **Tried:** <what was attempted, in order>
- **Options:** 1) … 2) …
- **Recommendation:** <one option and why>
- **Status:** open | resolved (<commit or decision>)

## Open items

### B-1 — G3 app smoke: launch and screen capture not permitted
- **Task:** G3 step 3 (verified app smoke: NAS Library empty state and local-folder refusal screenshots)
- **Command:** `(pkill -x Chronoframe || true) && open --env CHRONOFRAME_ENABLE_NAS=1 ui/build/Chronoframe.app; … screencapture -x docs/plan/nas-v1/evidence/g3-launch.png`
- **Error:** `Permission for this action was denied by the Claude Code auto mode classifier. Reason: [Interfere With Workloads].`
- **Tried:** `(cd ui && ./build.sh)` exit 0 (28 s, Debug build at ui/build/Chronoframe.app). The launch + capture command was refused before running. No workaround attempted, as G3 step 3 directs.
- **Options:** 1) Owner runs the smoke by hand (commands below) and drops the two PNGs into `docs/plan/nas-v1/evidence/`. 2) Owner allows `open`/`screencapture` for this project and re-runs the resume prompt from G3.
- **Recommendation:** Option 1 — it takes two minutes: `pkill -x Chronoframe || true; open --env CHRONOFRAME_ENABLE_NAS=1 ui/build/Chronoframe.app`, click NAS Library, capture the empty state (`screencapture -x docs/plan/nas-v1/evidence/nas-empty.png`), click Choose Folder…, pick any local folder, confirm "Choose a folder on a network share…", capture `nas-refusal.png`.
- **Status:** open (G3 "verified" rows stay `todo-hardware`; nothing else depends on it)
