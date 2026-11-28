# NAS public — progress

Status: shipped in PR #266 together with NAS v1; WP-00 to WP-05 and gates G2 and G3 done. Hardware: H1 fail-hardware (2026-11-08), H-NASP-1 and H-NASP-2 pass-hardware (2026-11-08, Nishith); H2, H6 and H8 have agent-run results awaiting the owner; H3, H4, H5, H7, H-NASP-3 and the FLAG row are `todo-hardware`.

Prefix `NASP`. Status values: todo, in-progress, review, done, blocked.

## Baseline
- 2026-11-08 HEAD `c82b369` (descendant of `4b992a4`), branch `feature/nas-v1`, no tracked modifications.
- `docs/plan/next-half/bin/cf_swift.sh build` → exit 0
- `docs/plan/next-half/bin/cf_swift.sh suite` → exit 0 (no failing shards)

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Baseline | done | 0 | suite 0 | n/a | | |
| WP-01 | Deduplicate refuses network folders | done | 0 | 4+2+17+33 pass | approve (round 1) | a6fc3d8 | INV-12 tags |
| WP-02 | Internalize execute(queuedJobs:) | done | 0 | 37+2 pass | approve (round 1) | e6fa2e6 | safety-critical, one line |
| WP-03 | Validate timeout, keeper save failure | done | 0 | 30+3+15 pass | approve (round 2) | abde28b | |
| WP-04 | Comment fix, errata, docs, string lists | done | 0 | n/a (docs) | approve (round 1) | 8be8322 | |
| G2 | Strings, suite, guards, evidence | done | xcode 0 | suite 0 | n/a | ca02a5a | |

## Outcome
- G2 (ca02a5a): `suite` 0, `coverage` 0, `guards` 0 (14/14), `xcode` 0. First pass failed because the new key "Choose Folder…" collided with "Choose Folder" as a generated symbol (D-NASP-112). G3 after WP-05 (076329e): `suite` 0 (464 shard summaries), `coverage` 0 (meaningful 95.98%; `NASCopyDestinationQualifier` 71.9% 46/64, the live `renamex_np` closure and mkdir/open failure branches are uncovered).
- INV-12 and INV-28 test tags: `ChronoframeCoreNASDeduplicateFolderRefusalTests.swift:28`, `DeduplicateEngineNetworkRefusalTests.swift:69`, `ChronoframeCoreNASCopyDestinationQualifierTests.swift:107`, `OrganizerEnginePrepareNetworkGateTests.swift:116`.
- D-NASP-05: `NativeDeduplicateEngine.networkAdvisory` is now unreachable for remote folders and was left in place deliberately (surgical change).
- WP-05 was added after H1 failed on the Synology profile (P03 unsupported): Organize preview and transfer refuse a network destination without atomic no-replace rename (D-NASP-115, owner chose option A).
- H6 observation (D-NASP-129): the space preflight printed "Disk space check passed. Resuming run." at 61 MB free with 106 MB needed.
- Agent-run H2/H6/H8 results are recorded in `EVIDENCE_LEDGER.md` under D-NASP-125 (owner sets pass).

Per-step log condensed 2026-11-21 (failing-first output, reviewer rounds, Done-when commands are in git history before the docs cleanup).
