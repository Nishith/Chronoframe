# Photos import resume — implementation plan

Status: shipped in PR #268 (WP-00 to WP-07, gates G1 and G2). Hardware rows H-PIR-1 to H-PIR-6 are still owner-only.

Condensed 2026-11-21: per-step instructions removed; the full text is in git history before the docs cleanup.
Contracts: `CONTRACTS.md`. Decisions: `DECISIONS.md`. Results: `PROGRESS.md`. Test traceability: `ACCEPTANCE_MATRIX.md`. Owner hardware rows: `EVIDENCE_LEDGER.md`.

## Work packages and gates

- WP-00 — Branch and baseline (orchestrator)
- WP-01 — Checkpoint model and store
  Contracts: C-01. Decisions: D-PIR-06, D-PIR-10.
- WP-02 — Executor events, reserved names, free-space floor (safety-critical: INV-22)
  Contracts: C-02, C-03 (protocol + extension only; the service is WP-03). Decisions: D-PIR-05, D-PIR-11, D-PIR-12.
- WP-03 — Service forwards PhotoKit progress (safety-critical: INV-22; no unit test possible without PhotoKit)
  Contracts: C-03.
- WP-04 — Store: checkpoint, cancel, resume, purge policy
  Contracts: C-04, C-06. Decisions: D-PIR-07, D-PIR-08, D-PIR-10, D-PIR-13.
- Gate G1 — Core/AppCore (orchestrator)
- WP-05 — Photos UI: preparation panel, resume card, dialog
  Contracts: C-05, C-06. Decisions: D-PIR-08, D-PIR-09.
- WP-06 — App wiring
  Contracts: C-07. Decisions: D-PIR-14.
- WP-07 — Documentation
  Contracts: C-08 (docs part). Every sentence must be checkable against the code as committed; the reviewer verifies each claim.
- Gate G2 — Final (orchestrator)
