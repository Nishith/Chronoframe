# NAS v1 — implementation plan

Status: shipped in PR #266 behind the disabled `NASCapability.isEnabled` flag (WP-00 to WP-12, gates G2 and G3). Hardware rows H1 to H8 are still owner-only.

Condensed 2026-11-21: per-step instructions removed; the full text is in git history before the docs cleanup.
Contracts: `CONTRACTS.md`. Decisions: `DECISIONS.md`. Results: `PROGRESS.md`. Test traceability: `ACCEPTANCE_MATRIX.md`. Owner hardware rows: `EVIDENCE_LEDGER.md`.

## Work packages and gates

- WP-00 — Branch, shared models and baseline (orchestrator)
  Contracts: C-01. Decisions: D-NAS-01, 02, 03.
- WP-01 — Volume classifier and system-container rules
  Contracts: C-02, C-03. Decisions: D-NAS-15, 33.
- WP-02 — Library identity and share lease key
  Contracts: C-04 (uses C-02). Decisions: D-NAS-30, 31, 32.
- WP-03 — Metered file reader
  Contracts: C-05. Decisions: D-NAS-11.
- WP-04 — Assessment store
  Contracts: C-06. Decisions: D-NAS-20, 21.
- WP-05 — Assessment scanner
  Contracts: C-07 (uses C-01 to C-06). Decisions: D-NAS-10, 12–19, 22.
- WP-06 — Remote copy policy in TransferExecutor (safety-critical)
  Contracts: C-08. Decisions: D-NAS-40–43. Change discipline: CLAUDE.md "Surgical changes in safety-critical code": every changed line traces to a C-08 item. No renames, no refactors, no tightening elsewhere.
- WP-07 — Remote journal policy and share lease
  Contracts: C-09, C-10. Decisions: D-NAS-32, 33, 44.
- WP-08 — CLI refuses remote destinations
  Contracts: C-11. Decisions: D-NAS-34.
- Gate G2 — Core and safety (orchestrator)
- WP-09 — Probe, parity and corpus tool
  Contracts: C-14. Decisions: D-NAS-60, 61.
- WP-10 — App Core services and workspace store
  Contracts: C-12. Decisions: D-NAS-21, 22, 30, 31, 52.
- WP-11 — NAS Library workspace UI
  Contracts: C-13. Decisions: D-NAS-05, 06, 50, 51.
- WP-12 — Documentation
  Contracts: C-01, C-08–C-13. Decisions: D-NAS-06, 07, 40.
- Gate G3 — Final (orchestrator)

Slice mapping (used by `docs/NAS_REQUIREMENTS.md`): slice 0 = WP-09; slice 1a = WP-01 to WP-05; slice 1b = WP-10, WP-11; slice 1c = WP-06 to WP-08.
