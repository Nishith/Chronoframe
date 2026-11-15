# NAS requirements review appendix

Status: proposal review history, not separate implementation approval. [Current requirements](NAS_REQUIREMENTS.md) own active scope; later revisions supersede earlier dispositions.

## 22. Review dispositions — v0.2

| Feedback | Disposition | Change / qualification |
|---|---|---|
| 1. Decide cleanup | Accept scope decision | Excluded from v1; P1 actual-share probe remains unrun. No custom recovery folder is implicitly approved. |
| 2. Define remote durability | Accept with correction | Descriptor fsync/flush + client readback is the proposed SMB contract; F_FULLFSYNC is not APFS-only and Apple SMB supports it conditionally. Atomic exclusive install remains a stop condition. |
| 3. Add read-byte budgets | Accept with correction | Size-prefilter exact-only photos/videos; candidate-relative byte budget and bounded embedded previews. Do not mandate a universal single sequential hash/decode pass or assert unmeasured full network-pass counts. |
| 4. Cut P0 | Accept | Bounded v1 assessment/review + qualified existing copy; cleanup, advanced UI/similarity, migration, full 1-TiB certification and soak are P1. |
| 5. Reference invariants | Accept | B rows cite owning invariants and retain only NAS regression deltas; existing contracts are not new implementation scope. |
| 6. State source blockers | Accept with correction | Concrete table above. Placeholder fallback exists, but whether SMB uses it requires a probe. |
| 7. Propose identity tuple | Accept as candidate | statfs-derived server/share, relative root, observations and bookmark/local ID; ambiguity invalidates continuity. Marker only in explicitly authorized mutation flow. |
| 8. Add sleep contract | Accept; implementation partly exists | Reuse execution idle-sleep assertions; specify assessment lifetime, lid/forced sleep and wake revalidation. |
| 9. Define SMB metadata fidelity | Accept | Bytes/embedded metadata required; xattrs/source ACL reproduction/filesystem timestamps best-effort with visible omissions and separate errors. |


## 23. Review dispositions — v0.3

| Feedback | Disposition | Affected sections / reason |
|---|---|---|
| 1. Preview consolidation and measurable input | Accept | NAS-UX-03/NFR-10, section 13.1, T21 and section 21.1 now cover the separate ClusterDetailPane loader, metered descriptor/provider input, bypass detection and one preview per exact group/render key. The previous single-entry assumption was incorrect. Always-create requests pixel thumbnail generation; it does not establish a measured full-file network pass. |
| 2. Decide the ENOTSUP policy | Accept the need for a decision; reject the recommended race exception | ADR-NAS-03, NAS-CPY-03, T11 and section 19 select native atomic no-replace. Copying may not ship on an unsupported profile. Foreign edits are currently allowed by section 3.3, and the overwrite race conflicts with INV-04. No implicit safety waiver. |
| 3. Give the DB ADR a candidate and test real contention | Accept | ADR-NAS-02 selects DELETE/FULL as the first candidate, local canonical-identity serialization plus existing destination lock, verified journal transition and actual same-Mac app/CLI SMB contention in T06/T14. EXCLUSIVE WAL is documented as an alternative requiring its own ownership proof; no corruption is claimed without evidence. |
| 4. Stable invariant numbers | Accept, with guard change | AGENTS.md uses permanent INV-NN labels without changing rule text. The invariant guard resolves test tags by those labels rather than ordinal position and rejects missing/duplicate IDs. This is more than a cosmetic numbering edit because the old guard parsed bullet position. |
| 5. Define stable size and counting point | Accept, strengthened | NAS-NFR-09 and section 13.1 require enumeration/pre/post-fstat agreement and consumed-byte parity; mismatches remain unresolved with fault reads separately visible. Count actual positive hasher read/pread returns. Known size must be checked, not trusted. |
| 6. Reachable-NAS picker start | Accept | NAS-CON-01 becomes P0 adaptation; T05 covers bounded off-main probing, start at a validated reachable mount and fast fallback/stale-result protection. |
| 7. Remove rebuttal from copy requirement | Accept | NAS-CPY-03 states only the remote/local flush requirements; the APFS-only correction remains in historical review/source context. |

## Review dispositions — v0.4

| Feedback | Disposition | Change / qualification |
|---|---|---|
| 1. App/CLI local lease is not shared | Accept recommended v1 refusal | Entitlements/RuntimePaths confirm separate process contexts. NAS-CON-06 and ADR-NAS-02 refuse CLI remote state writes, including metadata-writing dry-runs/maintenance/recovery, before opening destination records. App participants must prove their own shared container namespace. P1 adds common app/CLI access and real contention; no app-group entitlement is introduced now. |
| 2. Video preview rule | Accept | All videos default to placeholders. Frame loading requires explicit per-group consent that may read the full original; image-provider metering does not cover AVFoundation/QuickLook. Custom video resource loading/budgets are P1. |
| 3. Defer metered previews | Accept as revised proposal | NFR-10 and render-path consolidation move to P1. V1 preserves recognition through an explicit per-group preview request, without claiming an 8 MiB guarantee. Zero automatic preview IO remains a P0 test. |
| 4. Record SQLite locking style and read stalls | Accept with evidence qualification | P0 T06 records installed system SQLite/VFS/actual locking evidence and held-writer background-read/busy/cancel/UI latency. Unknown strategy stays an evidence gap; no unverified claim that all SMB readers use whole-file exclusive locking. App/CLI simultaneous write contention is P1 after namespace support. |
| 5. Separate invariant commit | Accept | The actual current checkout was marketing/phase0-campaign-links. AGENTS.md labeling and the guard are isolated in commit e2570034ea71ba7c2ccfc2075c11d2cb2afea776 on codex/stable-invariant-ids, parent main 566b6ba. Exactly those two paths are committed; their owned working-tree changes were removed after byte/commit verification. No checkout switch, worktree, push or NAS implementation. |
| 6. Data contract and appendix | Accept | Separate P0 local assessment/non-mutating review/coordination lease records from inherited copy evidence and P1 protection/destructive approvals. Move prior dispositions to this appendix; current scope remains in the requirements document. |

## Review dispositions — v1.0 (final)

| Check | Result |
|---|---|
| v0.3 findings 1–6 | All closed in v0.4 with the dispositions above. |
| App Intents namespace | `ChronoframeApp/AppIntents` compiles into the app target and no app extension exists, so Intents share the app-container lease namespace that NAS-CON-06 requires. |
| Cross-references | NFR-10 and its preview-consolidation work are P1 everywhere they appear. P0 gates cite only NFR-09 byte limits and zero automatic preview IO. No stale references to the moved review sections remain. |
| Invariant references | Section 4.1 defines bare numbers and `INV-NN` labels as the same stable IDs. Both styles stay valid once `codex/stable-invariant-ids` merges. |
| Open items carried as evidence, not review gaps | The SMB Trash probe and the slice 0 copy probes need a mounted, authorized share. Owner approval under section 17.1 is pending. |

No further requirements changes. The next step is owner approval, then slice 0 and slice 1a.
