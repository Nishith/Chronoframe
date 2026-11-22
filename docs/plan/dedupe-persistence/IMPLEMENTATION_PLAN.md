# Dedupe persistence — implementation plan

Status: shipped in PR #267 (WP-00 to WP-05, gates G1 and G2). Hardware rows H-DDP-1 to H-DDP-5 are still owner-only.

Condensed 2026-11-21: per-step instructions removed; the full text is in git history before the docs cleanup.
Contracts: `CONTRACTS.md`. Decisions: `DECISIONS.md`. Results: `PROGRESS.md`. Test traceability: `ACCEPTANCE_MATRIX.md`. Owner hardware rows: `EVIDENCE_LEDGER.md`.

## Work packages and gates

- WP-00 — Branch and baseline (orchestrator)
- WP-01 — Core model, keys, fingerprint, restorer
  Contracts: C-01, C-02. Decisions: D-DDP-02…04, D-DDP-10.
- WP-02 — Snapshot store and session-store integration
  Contracts: C-03, C-04. Decisions: D-DDP-05…09.
- Gate G1 — Invariant and coverage (orchestrator)
- WP-03 — UI: banner, saved-review card, focus, termination flush
  Contracts: C-05, C-06. Decisions: D-DDP-08, D-DDP-09.
- WP-04 — Documentation and string list
  Contracts: C-08, C-09. Done when `git diff --check` exit 0 and the reviewer confirms each sentence against the code.
- Gate G2 — Final (orchestrator)
- WP-05 — Counts cover reviewed groups only (added 2026-11-12, D-DDP-119)
  Contracts: C-10. Decisions: D-DDP-119, D-DDP-101.
