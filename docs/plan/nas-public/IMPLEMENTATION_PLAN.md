# NAS public — implementation plan

Status: shipped in PR #266 together with NAS v1 (WP-00 to WP-05, gates G2 and G3). The NAS Library flag stays off until every hardware row reads `pass-hardware`.

Condensed 2026-11-21: per-step instructions removed; the full text is in git history before the docs cleanup.
Contracts: `CONTRACTS.md`. Decisions: `DECISIONS.md`. Results: `PROGRESS.md`. Test traceability: `ACCEPTANCE_MATRIX.md`. Owner hardware rows: `EVIDENCE_LEDGER.md`.

## Work packages and gates

- WP-00 — Baseline (orchestrator)
- WP-01 — Deduplicate refuses network folders
  Contracts: C-01, C-02, C-03. Decisions: D-NASP-02…05, D-NASP-09, D-NASP-10.
- WP-02 — Internalize `execute(queuedJobs:)` (safety-critical)
  Contracts: C-04.
- WP-03 — Workspace validate timeout and keeper save failure
  Contracts: C-05. Decisions: D-NASP-06.
- WP-04 — Comment fix, errata, docs, string lists
  Contracts: C-06, C-07, C-08, C-09.
- Gate G2 — Final (orchestrator)
- WP-05 — Copy-destination preflight (safety-adjacent; approved 2026-11-08)
  Contracts: C-10, C-11, C-12, C-13. Decisions: D-NASP-115…118.
- Gate G3 — Final after WP-05 (orchestrator)
