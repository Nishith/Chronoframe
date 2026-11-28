# Clear path — implementation plan

Status: shipped in PR #269 (WP-00 to WP-16, gates G1 and G2) with follow-up PR #274. Hardware rows H-CLP-1 to H-CLP-7 are still owner-only.

Condensed 2026-11-21: per-step instructions removed; the full text is in git history before the docs cleanup.
Contracts: `CONTRACTS.md`. Decisions: `DECISIONS.md`. Results: `PROGRESS.md`. Test traceability: `ACCEPTANCE_MATRIX.md`. Owner hardware rows: `EVIDENCE_LEDGER.md`.

## Work packages and gates

- WP-00 — Branch, baseline, plan commit (orchestrator)
- WP-01 — Core titles and tab order
  Contracts: C-02. Decisions: D-CLP-02, D-CLP-03, D-CLP-07.
- WP-02 — Staged sources are checked against the destination (safety-critical: INV-21)
  Contracts: C-03. Decisions: D-CLP-20, D-CLP-23.
- WP-03 — Folder list model, store state, multi-folder picker
  Contracts: C-04. Decisions: D-CLP-04, D-CLP-18, D-CLP-19.
- WP-04 — Setup coordinator, bookmarks, AppState forwarders
  Contracts: C-05. Decisions: D-CLP-18, D-CLP-19, D-CLP-21.
- Gate G1 — Core and AppCore (orchestrator)
- WP-05 — Setup screen: folder list, one primary action, plain copy
  Contracts: C-06, C-01. Decisions: D-CLP-07, D-CLP-09, D-CLP-10, D-CLP-27.
- WP-06 — Folder layout picker and example in Setup
  Contracts: C-07. Decisions: D-CLP-12, D-CLP-13.
- WP-07 — Organize chrome, toolbar, prompts
  Contracts: C-08, C-01. Decisions: D-CLP-02, D-CLP-10, D-CLP-11.
- WP-08 — Preview & Copy workspace: headline, exceptions, plain copy
  Contracts: C-09, C-01. Decisions: D-CLP-07, D-CLP-14.
- WP-09 — Next step after a copy
  Contracts: C-10. Decisions: D-CLP-15.
- WP-10 — Deduplicate review: two lanes, one vocabulary (dedupe UI; no store, planner or executor edits)
  Contracts: C-11, C-01. Decisions: D-CLP-16, D-CLP-17.
- WP-11 — Health: plain cards, no score before the first copy
  Contracts: C-12, C-01. Decisions: D-CLP-22.
- WP-12 — UI-test scenarios and string lists
  Contracts: C-13, C-14 (lists). The implementer adds the scenarios; `cf-data-entry` then compiles the two string lists from the diff text the orchestrator gives it (`git diff feature/photos-import-resume -- ui/Sources`).
- WP-13 — XCUITest expectations and accessibility baseline (orchestrator)
- WP-14 — Documentation
  Contracts: C-14 (docs). Decisions: D-CLP-03. Every sentence must be checkable against the code as committed; the reviewer verifies each claim and each quoted label against `ui/Sources`.
- Gate G2 — Final (orchestrator)
- WP-15 — Bulk accept skips reviewed groups (added 2026-11-12, D-CLP-123; BLOCKED B-1, B-2)
  Contracts: C-15. Decisions: D-CLP-123.
- WP-16 — Leftover engine words (added 2026-11-12, D-CLP-124; BLOCKED B-3)
  Contracts: C-16, C-01. Decisions: D-CLP-124, D-CLP-03.
