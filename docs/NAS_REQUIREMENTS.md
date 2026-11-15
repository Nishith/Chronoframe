# Chronoframe NAS requirements

**Status:** approved, v1.0 — owner approved scope on November 7, 2026 (section 17.1, gate 1). Release Go (gate 7) still requires the evidence in section 17.  
**Date:** November 7, 2026.  
**Primary customer:** a Mac owner whose large photo/video collection already lives on a NAS, distributed across many folders.  
**Initial validation target:** Synology over a Finder-mounted SMB share, operated from one coordinating Mac.  
**Planning owner:** Nishith; engineering and QA ownership assigned at implementation planning.  
**Related proposal:** [next-half product review](next-half-product-review-2026-11-07.md).  
**Review history:** [appendix: dispositions by revision](NAS_REQUIREMENTS_REVIEW_LOG.md).  
**Implementation plan:** [NAS v1 plan](plan/nas-v1/IMPLEMENTATION_PLAN.md) (slices 0, 1a, 1b, 1c).  
**Separate review prerequisite:** permanent invariant IDs and their coverage guard are isolated on `codex/stable-invariant-ids`; they are not a merged change to the current checkout.

This document specifies intended behavior and release evidence. It does not assert that the requirements are implemented, that NAS behavior has been verified, or that a particular Synology configuration is currently supported. Existing safety invariants remain binding. Conflicts require an explicit product decision; implementation must not silently reinterpret them.

## 1. Product outcome

Let someone understand and compare a fragmented NAS photo collection from their Mac without downloading the whole collection or losing their review work, and optionally use the existing verified-copy flow into a disjoint destination. **NAS duplicate cleanup is an explicit v1 non-goal.** Existing user-requested, receipt-bound copy revert remains available on qualified profiles; it may remove only matching copies created by that run. A later duplicate-cleanup proposal must satisfy the existing Trash-only contract or obtain explicit approval for a changed safety policy.

The primary experience starts with **the collection already on the NAS**, not with importing a new collection from the Mac. The customer should be able to:

1. Select the parent folder containing their collection and inspect its nested folders as one library.
2. Understand what was checked, what was excluded and what could not be read.
3. Find identical files across folder boundaries, even when filenames and folder dates differ.
4. Review which copies they would keep with the original folder context visible; v1 saves decisions but offers no NAS dedupe delete action.
5. Leave and return to a long scan or review without starting over unnecessarily.
6. Use only qualified, explicitly approved copy operations and recover from interruptions; assessment/review remains non-mutating.
7. Optionally copy files into a separate organized destination on the NAS or elsewhere, with verification and honest capacity requirements.

**Success is a completed, explainable task on a real large NAS library.** A fast happy-path transfer alone is insufficient.

## 2. Customer profile and jobs

### 2.1 Primary profile

The customer has accumulated years of photos and videos from phones, cameras, old computers and repeated backups. Some folders are curated; others are imports or uncertain copies. They remember folder names and occasions more often than exact filenames. The collection exceeds the Mac's available storage. They may use the NAS through Wi-Fi, close the Mac's lid, or disconnect between sessions.

Illustrative scale for planning, not measured customer data: 100,000 media files, 1 TiB of content, 10,000 directories, and limited free Mac storage. A separate stress tier covers larger collections. Exact qualification corpora are defined in section 15.

Example:

```text
FamilyArchive/
  Curated/2018 Japan/
  Old Mac/Pictures/
  Phone Exports/2020/
  Camera Cards/DCIM/
  Backup Copy/Photos/
  Unsorted Videos/
  @eaDir/                  # NAS-generated metadata, excluded
  #recycle/                # NAS recycle content, excluded
```

The customer must not have to move these folders together, flatten them, or make a local copy before checking for duplicates.

### 2.2 Jobs and observable outcomes

| Job | Customer question | Successful outcome |
|---|---|---|
| Understand | “What is spread across these folders?” | A navigable folder inventory with media counts, logical bytes, scan coverage and exceptions. |
| Compare | “Does this old backup contain anything different?” | Exact duplicate groups span folders; unique/unassessed items remain distinguishable. No blanket claim that a folder is safe to erase. |
| Preserve | “Never remove my curated collection.” | V1 does not remove pre-existing NAS media; explicit copy revert remains limited to matching run-created copies. P1 protected-folder rules must exclude direct and pair/sidecar destructive targets. |
| Decide | “Which copy is where, and why keep it?” | V1 shows original paths, sizes/formats and exact-match evidence, with on-demand previews. Rich quality/similarity and keeper-preference controls are P1. |
| Continue | “Can I stop now and finish tomorrow?” | Eligible scan work and review decisions survive a restart; changed items require fresh validation. |
| Consolidate | “Can I build a cleaner collection on the NAS?” | A previewed, verified copy into a disjoint destination; sources unchanged and sufficient capacity explained. |
| Recover | “The connection failed. What actually happened?” | Evidence-backed completed/unfinished outcomes and a safe recovery action, without guessed success. |

### 2.3 Secondary profiles

- A customer adding media from a Mac/local drive to an existing NAS archive.
- A customer exporting from Apple Photos to the NAS with less local free space than the selection requires today. This is a follow-on delivery slice, not a prerequisite for assessing an existing NAS collection.
- A technical customer using the CLI: v1 permits NAS sources with a local destination under existing read-only source rules, but refuses CLI operations that write remote destination state. Cross-app/CLI remote mutation support requires a P1 shared-namespace design; it is not guaranteed by using similarly named Application Support paths.

## 3. Scope and operating modes

### 3.1 Priority definitions

- **P0:** new work required for v1: local-state read-only recursive assessment, an explicit cross-folder exact-only review path, saved progress/review, a measured exact-assessment byte limit, explicit per-group previews, and qualification/adaptation of the existing app verified-copy flow. No new general-purpose copy engine or state migration project is implied.
- **B:** inherited baseline contract/regression gate, not a new P0 feature or an invitation to reimplement it. The referenced AGENTS.md invariants own the rule.
- **P1:** separately gated follow-on work: cleanup, richer similarity, keeper/protection rules, legacy-state migration, full-scale/soak certification, cross-app/CLI remote coordination, metered preview/rendering consolidation and bounded Photos staging. It must not be implied by v1 release claims.
- **Deferred:** excluded unless separately approved. A requirement referring to P1 cleanup does not authorize changing the Trash-only invariant.

V1 is a bounded delivery: assess and compare files already on one NAS root, then optionally copy a reviewed selection using existing Organize behavior. If the copy prerequisites cannot be qualified, ship the assessment/review capability with copying explicitly unavailable on that profile; never claim copying support merely because an existing local code path compiles.

### 3.2 Modes and authority

| Mode | Priority | NAS access | Consent and destination |
|---|---|---|---|
| Assess existing collection | P0 | Read media/metadata; no intentional Chronoframe writes to the assessed NAS tree, including caches, lock files, reports or markers | Selecting a scope authorizes assessment only. Store assessment state locally. OS/server-managed access timestamps are outside this application-write guarantee. |
| Review duplicate groups | P0 | Read candidate content as needed; save review locally | No mutation permission follows from a scan. A read-only share remains useful. |
| Apply reviewed dedupe | P1; excluded from v1 | No NAS delete or quarantine-of-user-media action in v1 | Requires a separate cleanup decision and evidence. Existing Trash-only policy remains in force. |
| Organize by copying | P0 qualification of existing flow | Read source; write verified copies and operation evidence only to a separate destination | Existing preview/consent; the explicit remote flush, metadata and atomic no-overwrite contract below must pass on the offered profile. |
| Revert supported copies | B regression gate | Existing matching-receipt copy revert only | Existing ungated content verification; no NAS Trash-restore promise in v1. |
| Bounded Apple Photos → NAS import | P1 | Read-only PhotoKit export and verified NAS writes | Separate reviewed import with pinned destination and bounded local staging. |
| Reorganize/Guardian on NAS | Deferred qualification | Existing features may exist, but this document does not certify their NAS mutation paths | Separate evidence is required before advertising support. |

**Cleanup decision:** do not expose NAS dedupe commit in v1. Assume ordinary SMB shares do not provide the recoverable macOS Trash contract needed by the existing executor. A real-share probe may refine that platform finding; it does not automatically add cleanup to this release. A Chronoframe-owned recovery folder is a separate P1 product/safety proposal, not a fallback approved by this document.

### 3.3 Initial supported boundary

- One mounted SMB library root, recursively scanned with fixed safety/system exclusions. User-selectable include/exclude subtree controls are P1; v1 does not require a new scope editor.
- One coordinating signed app installation on one Mac performs remote mutations in v1. Its participating processes must resolve the same app-container lease namespace. CLI remote-destination writes are refused; a separate process/Intent host that cannot prove common lease access must also refuse remote mutation. Cross-app/CLI remote coordination is P1.
- Proposed protocol target: negotiated SMB 3.x. Record exact DSM, macOS, SMB and hardware combinations that pass qualification; “all Synology NAS devices” is not a valid claim.
- Existing macOS minimum and distribution channels remain unchanged. Qualification includes signed, sandboxed application behavior, not only a development executable.
- Existing folder-copy directions to qualify: NAS → Mac, Mac → NAS, and NAS → separate NAS destination, including separate folders on the same share. Qualify a representative bounded workload in v1; full 1 TiB certification is P1.
- Other clients may read. If they edit media, Chronoframe must detect relevant changes at validation boundaries; it does not provide a server-wide snapshot or lock other software out. Concurrent mutation by another Chronoframe installation, legacy CLI or other process that writes Chronoframe operational records is unsupported; v1 cannot retrofit a refusal into an old binary.

### 3.4 Explicit non-goals

- A Synology package, server daemon, administrator integration, credentials manager or direct DSM API client.
- Concurrent mutation from multiple Macs, distributed locking, automatic takeover from another Mac, shared app-group entitlements, or supported CLI remote-destination writes in v1. P1 must prove signed/sandboxed and CLI access to a common coordination namespace before enabling the latter.
- A cross-share/multi-NAS migration queue or one-click orchestration of many source roots. A single common parent covers the primary scattered-folder scenario; an advanced subtree editor can follow.
- Moving or deleting Organize sources to avoid copy-space requirements; replacing copies with hard links or pretending a same-NAS copy is free.
- NAS duplicate cleanup in v1, automatic near-duplicate deletion, unattended watched imports, automatic source erasure, or emptying Trash/snapshots to reclaim space. Existing receipt-bound copy revert is not duplicate cleanup.
- AFP, NFS, WebDAV, Internet/VPN-specific certification, or guaranteed WAN throughput in the initial release.
- Hosting or traversing an Apple `.photoslibrary` package on the NAS. Apple Photos exports ordinary media through PhotoKit from a supported library location.
- Reconstructing Apple Photos edit history, implementing Photos/Synology Photos synchronization, or preserving albums stored only in Synology's application database. Existing baked-in image edits remain in the copied bytes.

## 4. Core customer journeys

### A. Assess without changing anything

1. Choose the existing NAS collection root using a system-authorized folder picker.
2. Confirm library identity, root scope, fixed exclusions and single-Mac limitation. P1 adds a subtree scope editor.
3. Start assessment. See discovered items and current activity before a complete total is known.
4. Browse folder-level findings and exceptions as coverage becomes available.
5. Leave/relaunch; resume eligible work after reconnect/identity validation.
6. Read a completion summary that states precisely which subtrees were assessed.

### B. Review duplicates across folders

1. Choose the new exact-only assessment path; the existing Strict preset is not a substitute because it can still perform photo similarity work.
2. Review exact groups with both full relative paths and content evidence visible. Load previews on demand.
3. Save keeper decisions and return later. Revalidate observations when reopening; no Delete/Trash button is available for NAS targets in v1.
4. Read/export findings locally, with excluded/unreadable scope still visible. Do not describe the report as completed cleanup or reclaimed space.
5. P1 may add preferred/protected folders, similarity and approved cleanup after their own gates. These are not dependencies of the initial exact-review release.

### C. Copy into an organized archive

1. Choose a source and disjoint destination. Both may be on the same NAS.
2. Review the existing copy plan, duplicate routing and capacity/error information. P1 adds aggregate volume/quota preflight; v1 does not promise that new dashboard.
3. Review dates, output layout, collisions and unresolved metadata/companions.
4. Approve verified copying. See copy and verification progress separately.
5. If disconnected, reconcile before resuming. Final counts come from executed results and receipts.
6. Inspect per-item outcomes. Source files remain unchanged; no source-removal shortcut is offered.

For copy operations, `Family/Incoming` → `Family/Organized` is potentially valid because the roots are siblings. `Family` → `Family/Organized` is rejected even when an exclusion hides `Organized` during discovery. Filtering must not weaken the existing engine overlap guard.

### 4.1 Inherited contracts, not new feature work

The authoritative [AGENTS.md safety invariants](../AGENTS.md#safety-invariants) and [Safety and Recovery](SAFETY_AND_RECOVERY.md) are inherited. Numeric invariant references below refer to the permanent `INV-NN` labels in AGENTS.md, not bullet positions; that file remains the source of truth. `// AGENTS-INVARIANT: N` uses the same stable numeric ID. IDs are never renumbered or reused. Requirements marked **B** retain IDs for regression traceability but cite the contract and describe only NAS-specific coverage. They are not added to the implementation backlog as new features. In particular: source/overlap (1, 21), copy/verification/no-overwrite (2–4, 7), receipt/revert (8–9), failure thresholds (11), Trash/commit/pairs (12–14, 17–20), traversal/cache (15–16), Photos read-only (22), and metadata-file safety (26).

## 5. Functional requirements: scope and discovery

Each requirement has a stable ID. Acceptance tests in section 16 reference these IDs. Requirements specify outcomes; they do not imply that current public engine APIs already support the necessary behavior.

| ID | Priority | Requirement |
|---|---|---|
| NAS-SCP-01 | P0 | Select one existing directory as the library root; recursively discover supported media across its folder tree without flattening, relocating or fully downloading the collection. |
| NAS-SCP-02 | P1 | Add include/exclude subtree controls beyond the v1 selected root and fixed safety/system exclusions. Persist scope without parent/child double counting; filtering cannot change mutation authority or overlap checks. |
| NAS-SCP-03 | P0 | Distinguish intentional exclusions, unsupported files, unreadable subtrees, safely skipped containers and not-yet-assessed work. Do not invent file counts inside an unreadable/excluded subtree. |
| NAS-SCP-04 | B | Inherit AGENTS.md invariant 15 for traversal. NAS delta: do not cross an unexpected nested mount/share boundary; expose skipped scope under NAS-SCP-03. |
| NAS-SCP-05 | P0 | Skip recognized Synology-generated thumbnail, recycle and snapshot containers by default, including qualified `@eaDir`, `#recycle` and `#snapshot` names. Match documented path components, not arbitrary substrings such as every folder containing “backup.” Show exclusions; do not allow unsafe system-container mutation through an override. |
| NAS-SCP-06 | P1 | Add advanced folder drill-down and path search over the inventory. V1 needs only a folder-level counts/coverage summary and full relative paths in exact review; it must not build a general photo browser. |
| NAS-SCP-07 | P0 | Checkpoint enumeration and analysis in bounded units. On resume, reconcile directories/files that may have changed; a directory cursor alone must not establish completeness. A scan is not an instantaneous NAS snapshot. |
| NAS-SCP-08 | B | Reuse current supported media/path handling. NAS regression cases cover deep/non-ASCII paths, case/Unicode collisions and large files; unsupported/path-limit cases remain visible, never silently renamed. |

Assessment is read-only at the application layer. It may consume server I/O or cause OS-managed access metadata changes; it must not call APIs to create/change NAS-side metadata merely to enable assessment.

## 6. Connection, identity and authorization

| ID | Priority | Requirement |
|---|---|---|
| NAS-CON-01 | P0 | Reuse system/security-scoped authorization, but fix NAS reselection: asynchronously probe the last authorized mount/root off the main thread with a bounded wait and stale-result generation check; if identity/access are valid, start the folder picker there rather than at home. On timeout/unavailable identity fall back promptly with a reconnect/reselect explanation. Do not collect credentials, mount a replacement directory or block the UI while probing. |
| NAS-CON-02 | P0 | Identify a library using validated share/root identity plus the local library record, not a display name, IP address or `/Volumes` path alone. If available identifiers cannot establish continuity, require user reselection/reconfirmation and fresh validation before mutation. |
| NAS-CON-03 | P0 | A remount under a different path may reconnect to the same verified library. A different server/share/root reusing a name must not inherit cached trust, review approvals, pending mutations or write authority. |
| NAS-CON-04 | P0 | Never create a local replacement directory at a missing mount path or redirect output there. Revalidate that the intended remote destination remains mounted before scheduling new writes and before finalization/recovery. |
| NAS-CON-05 | P0 | Classify unavailable, authentication needed, access revoked, read-only, quota/full, busy and identity-ambiguous states separately where evidence permits. Unknown network status must not silently become “local and safe.” |
| NAS-CON-06 | P0 | V1 remote mutation is app-only: coordinate participating app/Intent/recovery processes through a lease in the same sandbox container keyed by canonical library identity. Prove common namespace; otherwise refuse that surface. Refuse CLI operations on remote destinations before creating/opening any DB/log/lock or modifying media, including metadata-writing dry-run, rebuild-cache, start-fresh, resume/revert and recovery paths. Allow read-only NAS sources with local destinations under existing rules. Retain the destination lock for compatibility; do not infer shared app/CLI access from identically named Application Support folders. |
| NAS-CON-07 | B | Retain the existing single-Mac network advisory and invariant 19 compatibility. A local lock/warning must not be presented as distributed exclusion; show the same limit on the new assessment screen. |

Library identity design is an engineering decision subject to the constraints in section 13. Do not add an on-NAS identity marker as an undocumented side effect of a read-only assessment.

## 7. Cross-folder duplicate review and approved cleanup

| ID | Priority | Requirement |
|---|---|---|
| NAS-DED-01 | P0 | Provide an explicit exact-only path across all included folders, independent of names/dates. Enumerate stable sizes first; full-hash only sizes occurring at least twice within scope, including photo candidates as already done for videos. Unreadable/changing sizes remain unresolved. Do not decode features, score quality or generate thumbnails during this stage. |
| NAS-DED-02 | P0 | Show original relative paths, file sizes/types and exact-match evidence. V1 review is path-based with image/video placeholders, no automatic group thumbnails or video frame extraction. One explicit per-group preview request may invoke existing rendering, labeled as potentially reading the whole original over the network and carrying no thumbnail-byte guarantee. Keep per-file path/context and reuse the requested preview across byte-identical members. Folder names never imply deletion consent. |
| NAS-DED-03 | P1 | Add separately labeled preferred keeper folders and planner-enforced protected subfolders before offering cleanup. Changing protection invalidates conflicting approvals; no cleanup permission follows from v1 saved keeper choices. |
| NAS-DED-04 | B | Inherit invariants 14, 17 and 18 for pair/sidecar ownership and mutation evidence. P1 NAS delta: protected-folder exclusions must cover pair/sidecar fanout as well as direct targets. |
| NAS-DED-05 | P0 | Persist exact-review decisions, group membership, scope/version and position locally. Reconcile changed/renamed/unavailable observations before reuse. Saved v1 choices are review state only; they cannot become approval for a future cleanup feature. |
| NAS-DED-06 | P1 | Inherit invariant 17 for plan/footer/executor parity. Before future NAS cleanup, show all fanout/protection outcomes and revalidate keeper/dependency evidence; an unavailable retained copy cannot justify deletion. |
| NAS-DED-07 | B | Inherit invariant 6 and the Perceptual video matching contract for automatic eligibility. A NAS optimization may not relax them. V1 exact-only assessment does no similarity/video feature extraction. |
| NAS-DED-08 | P1 | V1 offers no NAS cleanup. Before any later cleanup release, satisfy invariants 12, 13, 18 and 20 on the qualified share or secure separate explicit approval for a new recovery-folder product/safety contract. Never substitute hard delete or assume Synology recycle-bin equivalence. |
| NAS-DED-09 | P1 | Inherit invariants 9, 18 and 20 for journaled quarantine/Trash/recovery. Any future NAS cleanup must prove rollback and content-bound restore under disconnect/permission faults; no ambiguous success outcome. |

A P1 Trash feasibility probe may use explicitly disclosed Chronoframe-owned test artifacts only on an authorized disposable test share. It is not part of read-only assessment and cannot enable v1 cleanup. No mounted SMB share was available during this revision; the probe remains unrun, not passed.

## 8. Copying and archive completeness

| ID | Priority | Requirement |
|---|---|---|
| NAS-CPY-01 | B | Qualify the existing NAS → Mac, Mac → NAS and NAS → NAS flow under NAS-CPY-03/09; do not implement a second copy engine. Same-NAS copies require space and may traverse the Mac; no offload promise. |
| NAS-CPY-02 | B | Inherit invariants 1 and 21 for read-only sources and root overlap. NAS delta: subtree exclusions and remount aliases cannot bypass the guard. |
| NAS-CPY-03 | P0 | For SMB destinations accept successful fsync on the open temporary-file descriptor (OS SMB flush path), then client content readback and native atomic no-replace install; propagate flush/I/O errors. F_FULLFSYNC is not mandatory for SMB; preserve the existing qualified stronger local flush behavior. No NAS hardware power-loss claim. Selected rule: if native atomic no-replace is unavailable, copying is not offered on that profile; never enable the placeholder check-then-rename path as an accepted NAS residual limit. See ADR-NAS-03 and section 19. |
| NAS-CPY-04 | B | Inherit invariants 4 and 7 for collisions/verification and existing execution revalidation. NAS regression: content changed since planning remains stale; collision handling cannot overwrite another client's file. |
| NAS-CPY-05 | B | Inherit invariants 1–4 and 7 for media content and existing capture-date/pair behavior. NAS regression: copy naming and SMB metadata fallback must not change embedded content, dates or pair associations. |
| NAS-CPY-06 | P1 | Add companion-aware preview/accounting when integrating the separate XMP-preservation feature. V1 reports unsupported file classes and does not claim application-edit archive completeness. |
| NAS-CPY-07 | P1 | Add joined per-item selection/execution reconciliation, including free-batch replans and asset/resource counts. V1 retains existing receipt-backed results and explicitly reports incomplete/error outcomes; a new accounting UI is not its launch gate. |
| NAS-CPY-08 | B | Inherit invariants 8 and 9 and the Deduplicate Workspace recovery contract for verified resume/revert and receipt evidence. NAS regression: reconnect must not duplicate finalized work or infer receipt entries from queue intent. |
| NAS-CPY-09 | P0 | Implement and test the SMB metadata contract below: bytes are verified; xattrs/source ACLs/filesystem timestamps are best-effort with explicit omissions, without confusing metadata errors and data-copy errors. |

Ordinary byte copies preserve edits already embedded in the file. Neither a NAS destination nor a successful hash comparison implies that external application catalogs, non-copied sidecars, or Photos adjustment history were preserved.

SMB metadata contract: verified media bytes and embedded metadata are required; source xattrs, ACL reproduction and filesystem timestamps are best-effort and must be reported when omitted. Destination access controls remain valid under its normal authorization. A metadata-only failure may fall back to a bytes-only copy with a visible warning, never hide a data-copy failure or silently retry with unsafe permissions. Report any AppleDouble `._` files created by OS metadata representation separately from media counts; do not manufacture them to claim metadata fidelity. Current `COPYFILE_ALL` behavior is not already this contract.

## 9. State, indexing and recovery evidence

| ID | Priority | Requirement |
|---|---|---|
| NAS-DAT-01 | P0 | Use app-container-local state for new read-only assessment/review, with no NAS root cache/log/lock creation. Existing app Organize operational state stays in place: candidate remote policy is DELETE journal/FULL synchronous, applied/verified under the app-container identity lease plus destination lock. CLI remote writes are refused in v1, not coordinated through a separate user Application Support file. Disable copy qualification if the app policy cannot be made safe; state relocation and shared app/CLI access are P1. |
| NAS-DAT-02 | P0 | Distinguish rebuildable caches from durable review decisions, overrides, copy queues, reservations and mutation state. Cache eviction/rebuild must not delete the latter or alter purchase/allowance state. |
| NAS-DAT-03 | P0 | Key state by stable library identity, relative paths, observed attributes and content identities where required. Record scope, scan generation, schema/algorithm versions, coverage, exclusions and read errors. Paths alone are insufficient identity. |
| NAS-DAT-04 | B | Inherit INV-19 for existing shared engine/local workflows. NAS delta is explicit app-only remote mutation in v1, with common app-container lease proof for participating hosts; CLI remote writes are refused. Preserving the existing on-destination lock is compatibility, not proof of a common app/CLI local lease. P1 enables cross-namespace coordination only after a common location/access model passes signed tests. |
| NAS-DAT-05 | B | Inherit invariant 9 and current spool/receipt durability/authority ordering. NAS regression: disconnect/local success alone cannot establish remote finalization. No new portable assessment journal is required in v1. |
| NAS-DAT-06 | B | Inherit invariant 26 for metadata files and existing corruption/recovery evidence handling. Apply the same helpers to the new local assessment store; no silent reset of durable review/work state. |
| NAS-DAT-07 | P1 | Relocate/migrate existing operational state only under an accepted ADR, preserving queues/overrides/history/locking and restartable reconciliation. V1 assessment uses a new local namespace and leaves legacy state intact; no migration is needed to start read-only assessment. |
| NAS-DAT-08 | B | Preserve existing evidence-bound recovery under local cache/state loss or reinstall. Never invent approvals from cache/queue rows; new local exact-review state lost without backup requires fresh review, not cross-Mac resume. |

No NAS delete/organize operation may rely on a disposable performance cache as its sole mutation evidence. The existing database contains operational state, so “move the cache locally” is not a complete migration design.

## 10. Interruptions and cancellation

| ID | Priority | Requirement |
|---|---|---|
| NAS-REC-01 | P0 | Detect disconnects/stalls without blocking the main UI thread. Stop scheduling dependent mutations; preserve evidence and distinguish waiting for network from an ordinary item error. Server-side effects may have completed before the client saw an error, so reconcile before retrying. |
| NAS-REC-02 | P0 | Resume only after re-establishing identity, scope, authorization, locks and operation state. Reconcile in-flight targets before fresh discovery/copy/deletion. Never continue merely because the old path exists again. |
| NAS-REC-03 | B | Inherit existing cancellation/finalization lifecycle across the new assessment path. No new units after stop; remain Stopping with scope/lease alive until active work stops. NAS-NFR-02 sets responsiveness targets; final results are evidence-bound. |
| NAS-REC-04 | B | Inherit invariant 11 for mutation failure thresholds and existing bounded retry policy. NAS delta: network errors cannot reset thresholds or create an uncancellable/infinite retry loop. |
| NAS-REC-05 | B | Inherit the existing inaccessible-versus-missing recovery distinction. New NAS assessment keeps partial/unreadable/unassessed coverage explicit; it does not certify absence, complete coverage or safe source removal. |
| NAS-REC-06 | B | Inherit invariants 8, 9 and 20 and existing idempotent recovery semantics. NAS copy regression: recover twice after reconnect without duplicate mutation; Trash restore belongs to P1 cleanup qualification. |
| NAS-REC-07 | B | Inherit existing mutation journaling/rollback and safe artifact retention. V1 fault-test copy temp/flush/install/spool/receipt boundaries; quarantine/Trash/restore fault qualification is P1. |
| NAS-REC-08 | P1 | Before future cleanup, reconcile an interrupted mutation and require explicit confirmation of the remaining destructive plan. V1 saved review state does not authorize it. Existing reviewed/pinned Organize resume semantics remain baseline. |
| NAS-REC-09 | P0 | Reuse executor idle-system-sleep assertions during active copy/recovery; hold a corresponding user-initiated assessment activity only while read work is active. Release on pause, waiting-for-network or terminal state; during Stopping retain only until active work actually stops. Never disable display sleep or override explicit/lid sleep. Treat forced/lid sleep as an interruption, checkpoint safely, and validate identity/connection/state after wake before more work. |

### 10.1 Required user-visible states

| State | Meaning | Available next action |
|---|---|---|
| Ready | Identity/access resolved; no active operation | Assess, review, or prepare a supported operation |
| Assessing / analyzing | Active read work; total may still be unknown | Stop; inspect assessed findings |
| Complete assessment | Every included supported subtree assessed for the stated analysis scope | Review findings or deliberately rescan |
| Incomplete assessment | Some scope remains unreadable, changed or unassessed | Inspect exceptions, reconnect/re-authorize, retry |
| Review saved | Decisions retained, not fresh mutation authority | Reopen, validate and confirm a plan |
| Applying / verifying | Authorized mutations in progress | Cancel request; inspect progress |
| Waiting for NAS | Required I/O unavailable; completion unknown for in-flight work | Reconnect, inspect evidence or request stop |
| Needs authorization / identity confirmation | Cannot establish access or intended library | Reselect/confirm through system access flow |
| Stopping | No new work scheduled; active work/finalization still pending | Remain informed; no premature new run |
| Recovery required | Pending evidence must be reconciled before more mutation | Run safe recovery; inspect blocked items |
| Completed / completed with issues / aborted / failed | Final receipt-backed execution result, not a progress guess | Inspect outcomes, fresh preview/retry, supported revert |

Persist enough state to distinguish these after relaunch. Scan-generation tokens prevent an old result from replacing a new scope/result. Background filesystem calls may remain blocked beyond the requested cancellation deadline; show that honestly and keep the UI responsive rather than claiming the operation has stopped.

## 11. Capacity and storage reporting

| ID | Priority | Requirement |
|---|---|---|
| NAS-SPC-01 | P0 | Assessment and duplicate analysis must not require a full local or second NAS media copy. Local index/cache usage is visible and bounded as specified in section 15; persistent operational records have an explicit budget/retention policy. |
| NAS-SPC-02 | P1 | Add aggregate preflight output/temporary/evidence budgets across volumes and quotas. V1 keeps existing per-file destination capacity checks and clear unknown/error reporting; no new capacity dashboard is required. |
| NAS-SPC-03 | B | Retain existing per-file capacity checks and safe failure handling under NAS quota/full/read-only errors. A smaller reviewed batch/another destination is acceptable; source deletion or skipped verification is not a capacity remedy. |
| NAS-SPC-04 | P1 | Before cleanup reporting, separate logical duplicate/Trash bytes from observed free capacity and snapshot/shared-block effects. V1 labels duplicate byte totals as logical redundant bytes, never space freed. |
| NAS-SPC-05 | B | Retain separation of evictable caches from durable evidence/user media. A full local assessment store fails safely with a clear explanation; eviction cannot remove saved review decisions or pending operation records. |

In-place duplicate review does not need room for a second library, but quarantine/journal operations still require working metadata capacity and supported permissions. Copy consolidation on the same NAS is not an answer to insufficient NAS free capacity; those extra copies must fit unless a qualified storage primitive demonstrably changes the requirement.

## 12. Experience, privacy and compatibility

| ID | Priority | Requirement |
|---|---|---|
| NAS-UX-01 | P0 | Show library/server/share display identity, mode and effective folder scope. Keep “assess,” “copy,” and “move reviewed duplicates to Trash” distinct; no scan action silently escalates to mutation. |
| NAS-UX-02 | P0 | Show stage, current relative path, discovered/processed counts and meaningful byte progress. Separate discovery, hashing, copying, verification and finalization. Do not show a completion percentage or ETA before a defensible denominator/rate exists. |
| NAS-UX-03 | P0 | Keep the folder summary and exact review usable through lazy views with placeholders by default. No preview IO on selection, scrolling or relaunch. A per-group Load preview action explains that it can read the entire remote original; only that action starts image/video rendering, which remains off-main and cancellable under existing semantics. Metered provider work and consolidation of the existing separate render paths are P1, not a hidden v1 dependency. |
| NAS-UX-04 | B | Apply existing plain-language error, keyboard/VoiceOver, scaled-text and reduced-motion contracts to the new NAS assessment/review surfaces. NAS regression: paths/details are copyable and low-level codes are supplementary. |
| NAS-UX-05 | B | Reuse Organize, Deduplicate and History concepts. V1 adds a basic scope/folder-summary surface rather than a general photo browser or migration-project workspace. |
| NAS-PRV-01 | B | Inherit the product privacy and OS credential contract: no uploads/external analysis/analytics/admin connection. NAS assessment adds only local state, no new remote account. |
| NAS-PRV-02 | P0 | Logs/support export omit credentials and authentication tokens. Paths, server names, image names and thumbnails are private data; diagnostic export is explicitly initiated, inspectable and redactable. No support bundle auto-sends itself. |
| NAS-PRV-03 | B | Inherit the settled free-trial plan: scan/review/history policy, exact reservation accounting and ungated revert. NAS retry/recovery regression must not double-charge; no pricing change. |
| NAS-PRV-04 | B | Inherit shared core entry-point safety, invariant 19, sandbox access lifetimes and legacy receipt compatibility. NAS changes must pass affected local/APFS regressions; no duplicate implementation of these contracts. |

## 13. Engineering constraints and proposed ADR answers

Reuse the Swift core. Each ADR starts from the following candidate answer and has a stop condition; these are not unresolved invitations to broaden v1.

| ADR | Proposed answer | Evidence and stop condition |
|---|---|---|
| ADR-NAS-01 | Minimum identity observation tuple: SMB filesystem type; parsed server/share from `statfs.f_mntfromname`; root path relative to that share; observed root directory resource/file identity and available creation/device attributes; local library UUID plus security-scoped bookmark. Treat aliases, credentials/user-info in mount strings, transient device IDs and DNS/IP changes conservatively. A user-visible random library marker may strengthen continuity only in a later explicitly mutation-authorized flow, never read-only assessment. | The tuple is a candidate correlation key, not cryptographic proof against a replacement server. On missing/changed/contradictory observations, require reselection and invalidate stale review/mutation authority. Reject unresolved alias/overlap copy targets. Test same-name shares, aliases, remount paths and replaced roots. |
| ADR-NAS-02 | V1 remote mutations use the signed app only. Its assessment state and identity lease live in its sandbox container; no app-group entitlement or shared CLI lease is assumed. Refuse CLI remote-destination state writes before opening the DB. For existing app remote operational opens, propose journal_mode=DELETE and synchronous=FULL; retain data in place and serialize app participants through the common app-container identity lease plus the destination lock. Transition/read back journal settings only under proven operation ownership; never delete recovery sidecars. | P0 T06 proves CLI refusal, same-container app/host contention, and SQLite held-writer/read-latency behavior on actual SMB; T14 covers journal transition/recovery. Record actual system SQLite/VFS/locking evidence, not assumptions about journal mode. A failed ownership/flush/latency/recovery gate disables app copy qualification. P1 T06 adds simultaneous app+CLI mutation only after a shared namespace/access design. EXCLUSIVE WAL remains an alternative requiring separate ownership proof, not a runtime fallback. |
| ADR-NAS-03 | Selected proposal: temporary write → successful descriptor fsync/OS SMB flush → content readback → native atomic no-replace rename → durable evidence finalization. Preserve qualified local flushing. Do not accept the placeholder fallback race as a NAS residual limit. Other clients may edit media under section 3.3; only concurrent multi-Mac Chronoframe mutation is excluded. | If RENAME_EXCL returns ENOTSUP and no separately proved native atomic no-replace primitive is available, copying does not ship on that profile; journeys C and copy directions apply only to qualified profiles. Assessment/review still ships independently. Changing this to accept a check/rename overwrite window requires an explicit owner-approved change to INV-04; this revision rejects that exception. Server power-loss persistence is outside the client readback contract. |
| ADR-NAS-04 | V1 cleanup is out of scope regardless of a probe result. P1 first tests ordinary SMB Trash using owned fixtures; do not assume it exists. A custom on-NAS recovery folder requires a separate approved safety/product proposal before design/implementation. | Record exact result/error, receipt and restore evidence from an authorized test share. No share was mounted for this revision. Probe absence does not block read-only v1 and does not authorize a new deletion path. |
| ADR-NAS-05 | V1 exact-only pipeline = stable-size enumeration → candidate-size hashing → local grouping, with no feature/preview work. Review starts with placeholders; one explicit per-group action may load an image or video frame with a potentially-full-original warning. Metered provider/consolidation and video resource loading are P1. | Prove exact-group parity, NAS-NFR-09 read budget, zero automatic preview reads, consent before each new group acquisition and off-main responsiveness. No NFR-10 claim in v1. Do not interpret a data provider for still images as an AVFoundation/QuickLook video budget. |
| ADR-NAS-06 | P1 Photos keeps bounded complete-asset checkpoints and explicit per-batch reviewed/pinned transfer boundaries. | Preserve invariant 22 and existing date/allowance rules. Stop if a changing staging source would be passed through already-approved immutable planning. |

### 13.1 Measurement and connection contracts

**Exact candidate stability.** `knownSize` is an expected value, not authority. Future NAS hashing must open no-follow, verify the same descriptor's size against enumeration before hashing, verify bytes consumed and post-read size/observations, and move mismatches to unresolved. Changes to observed identity/mtime or read failures also invalidate the observation. Same-size/same-mtime concurrent edits are not proved absent by these checks; assessment is not a filesystem snapshot or an integrity scrub. Singleton-size items remain “unique by observed size within assessed scope,” not full-hash verified. Any later operation applies its own commit-time identity checks.

**V1 previews and videos.** Selection, scrolling, restoring a review and exact hashing cause no preview IO. All media kinds default to placeholders; Load preview is an explicit per-group action warning that existing rendering may read the whole original and may be slow. Video frame extraction may seek an end-of-file index and read a keyframe; it has no 8 MiB guarantee. Reuse a successfully requested preview for the same exact identity/render configuration and do not silently start acquisition for the next group. Keep UI/cancellation honest if an underlying framework call is delayed. Record preview requests as separate operations, with bytes marked unknown when framework access is opaque; never subtract estimated preview bytes from the exact-hasher counters or claim complete framework-level byte accounting in v1.

**P1 measured preview input.** The descriptor/provider approach in NAS-NFR-10 applies to still-image inputs; its callbacks must cap/count every read, including seek/reopen and fallback behavior. It requires consolidating the currently separate list/detail paths and bypass tests. AVFoundation/QuickLook video paths need their own custom resource-loader/equivalent measurement design. Until each path qualifies, it remains explicit-request-only without the metered guarantee.

**Operational database and namespace candidate.** The app's sandboxed Application Support and the unsandboxed CLI's user Application Support are different locations; a path helper does not create a shared lease. V1 therefore refuses CLI remote-destination writes and does not add app-group entitlements. Record/prove the resolved lease namespace for app, Intent and recovery hosts before permitting their remote mutation. Apply the DELETE/FULL candidate consistently to app remote operational connections, including background reads/maintenance. Failed journal transition, pending ownership or unidentified legacy activity blocks transition; retain WAL/journal evidence and let SQLite recover it. Do not claim source review proves existing corruption.

**SQLite read-latency qualification.** T06 records sqlite3 library version, compile options (including locking-style support), selected VFS and the actual effective locking strategy plus how it was established. VFS name or SQLITE_FCNTL_LOCKSTATE alone is not proof of a concrete OS locking implementation. If the installed system library does not expose enough evidence, record unknown as an open evidence gap requiring explicit disposition, never guess that all SMB uses whole-file exclusive locks. On the actual app SMB profile, hold write transactions/locks and measure independent background read elapsed time, busy/timeout result, cancellation and p95 UI latency with the configured busy_timeout (currently 30 s). No SQLite lock wait may block the main thread; UI must meet NAS-NFR-01 and show waiting/busy status rather than a silent stall. P1 repeats this across app/CLI once a genuinely shared namespace exists.

### 13.2 Minimum persisted data contract

Separate new v1 records from inherited operation records and P1 additions; do not implement P1 approval/protection state in the v1 assessment store.

| Record | Scope | Minimum data |
|---|---|---|
| Library | P0 | Local ID; validated share/root observations; display identity; authorized bookmarks; root/fixed exclusions; capability/version results. No credentials. |
| Scan/item | P0 | Generation/mode/version; scope and start/end; directory coverage/checkpoints/issues; relative path/type/observed attributes; full digest and freshness where computed; stable-size and read-byte outcomes. |
| Exact review | P0 | Content-bound exact group membership; non-mutating keeper choices; current position; last observation/validation; explicit per-group preview request/cache key. No Delete/commit approvals. |
| Coordination lease | P0 | Canonical library/root key; app-container namespace and authorized participating host identity; protected local lease path/format version; diagnostic process/operation fields. The live OS-held descriptor lock is authority, never a saved PID/timestamp. Record active/waiting/recovery transitions; no CLI-shared location is assumed. |
| Copy operation/evidence | B | Existing immutable copy plan/identities, authorization, lease lifetime, mutation/receipt/final outcomes. Reuse current operation artifacts rather than duplicate them in the assessment DB. |
| Protection/cleanup review | P1 | Preferred/protected scopes, pair/companion mutation dependencies, explicit destructive approval and last commit validation. V1 saved keeper choices cannot populate this approval automatically. |
| Metrics | P0 / P1 | P0 exact byte ledger/observed latency/capacity unknowns and preview request events. P1 metered preview/similarity counters and expanded qualification metrics. Metrics never substitute for content/receipt evidence. |

Directory size/mtime, FSEvents, SMB notifications and last-seen file IDs may accelerate scheduling but do not establish that content is unchanged. Existing size/mtime cache validation remains a cache rule; integrity checks and destructive commit checks still require their existing full content evidence. Guardian scrub must not inherit a metadata-only shortcut.

## 14. P1: bounded Apple Photos import to NAS

This slice addresses the related capacity problem without distracting from the primary existing-NAS-library release. It depends on the NAS copy/recovery contract and the Photos import improvements in the roadmap.

| ID | Priority | Requirement |
|---|---|---|
| NAS-PHO-01 | P1 | Export and transfer in bounded, complete-asset batches so the whole selection need not fit in Chronoframe's local staging. Keep original-only behavior until the separately proposed edited-version option is approved and implemented. |
| NAS-PHO-02 | P1 | Configure/describe a local staging budget and safety reserve; admit an asset only when all its resources can be safely staged. Handle an oversized single asset explicitly. Never split a Live Photo publication across partial successful exports. |
| NAS-PHO-03 | P1 | Preserve review consent, pinned destination, content-bound capture dates and verified transfer semantics across batch boundaries. Show asset/resource totals; use bounded per-batch review when needed rather than pretend unexported bytes have already been verified. |
| NAS-PHO-04 | P1 | Resume eligible completed checkpoints after interruption; revalidate asset resources, access and destination. Reclaim only verified/completed or explicitly abandoned staging under the defined policy. Cancel remains busy until exporters/workers stop; never delete active staging. |
| NAS-PHO-05 | P1 | Measure PhotoKit/iCloud local downloads separately from Chronoframe-owned staging; explain storage use outside direct control. Maintain strictly read-only PhotoKit access and deterministic limited-library authorization. Do not host the Photos library package on the NAS. |

## 15. Nonfunctional requirements and qualification targets

All numeric values below are **proposed acceptance targets**, not achieved benchmarks or public claims. Fix the reference hardware/configuration before implementation benchmarking; changes require a recorded rationale, not post-hoc relaxation to hide a failure.

### 15.1 Corpora and configurations

| Tier | Corpus / environment | Gate |
|---|---|---|
| Functional | Labeled small fixtures: duplicates across folders, unique sizes, same-size distinct bytes, zero-byte and changing/unreadable files, intentional variants, pair/companion context, excluded containers and path/identity faults | P0 automated + signed SMB functional gate. Full-hash ground truth establishes exact-group parity. |
| V1 reference | 10,000 media files, approximately 100 GiB, at least 1,000 directories; record the sum of size-colliding bytes. At least three matched exact-assessment runs; representative verified-copy batch of at least 100 files / 10 GiB, including a large file. Use the smaller applicable corpus limit only with explicit owner disposition, not a hidden waived gate. | P0 assessment/review and qualified existing-copy evidence. App owns no full local replica. This does not establish 100,000-file/1-TiB support. |
| Capacity/fault | V1 corpus with Mac free storage below corpus bytes; separate local-state exhaustion and remote quota/full faults; interrupt at applicable copy boundaries and recover twice | P0 resource/recovery gate. No eight-hour duration requirement. |
| Full-scale qualification | 100,000 files / approximately 1 TiB / at least 10,000 directories, plus complete 1 TiB verified-copy evidence for that copy claim and the eight-hour soak | P1, separately staffed/evidenced. Prior June deferrals are not erased or relabeled by shrinking v1. |
| Stress / Photos | 1 million files / multi-TiB / 50,000 directories; separately a Photos selection exceeding staging budget | P1 exploration or Photos gate. Do not advertise untested scale or capabilities. |

Record NAS model, DSM/SMB versions, filesystem/disk layout, snapshots/recycle settings, ACL/quota, Mac/RAM/macOS/signing, negotiated SMB security, network, corpus composition and cache conditions. Keep normal security/services enabled. V1 uses one named signed reference Mac/Synology profile with wired 1 GbE and a representative variable Wi-Fi run; affected compatibility tests still cover supported architectures/macOS. Additional hardware profiles and scale claims require their own evidence, not a full Cartesian certification matrix before v1.

The resource/latency targets below apply to the **v1 reference corpus**. Full-scale memory/cache limits must be requalified in P1 rather than inferred from v1.

### 15.2 Measurable targets

| ID | Priority | Target / measurement |
|---|---|---|
| NAS-NFR-01 | P0 | Local UI actions acknowledge within 250 ms at p95 during the v1 reference workload; no blocking NAS I/O on the main thread. Show first scan activity within 5 s on a healthy reference share, even if the total is unknown. |
| NAS-NFR-02 | P0 | A cancel request acknowledges within 1 s and stops scheduling new units within 2 s. If an OS call remains blocked, show truthful “Stopping / waiting for network” within 10 s and keep the UI responsive. Final completion is evidence-bound, not time-bound fiction. |
| NAS-NFR-03 | P0 | Peak app resident memory stays below 1 GiB on the v1 reference workload, including supported folder/review views. Bound thumbnails and workers independently; no memory growth proportional to all decoded images. Record OS/QuickLook contributions separately rather than omit them. |
| NAS-NFR-04 | P0 | Default rebuildable local media/index cache budget is at most 2 GiB for the v1 reference corpus, excluding explicitly reported durable operational records. Never retain a full-library media cache for NAS-native assessment/copy. Bounded buffers may scale with worker count/largest in-flight unit, not whole-library bytes. |
| NAS-NFR-05 | P1 | For richer similarity, reuse valid feature-cache entries and avoid unconditional repeat remote acquisitions. Use a bounded seekable/shared data provider or budgeted representation for hash+decode where feasible; do not mandate one sequential read for seeking decoders. Declare/measure format-specific exceptions. V1 exact-only path produces no features. |
| NAS-NFR-06 | P1 | Broader stage-time/concurrency optimization compares cold/warm, small/large-file throughput and I/O with matched verified workflows; investigate >10% median regressions. V1 still records metrics for its exact read-byte/preview/latency gates, but generalized optimization and a hardware matrix are not launch prerequisites. |
| NAS-NFR-07 | P1 | Qualify an eight-hour mixed workload soak before making sustained-operation/large-scale qualification claims. It is not a v1 gate; retain v1 fault-boundary/idempotent recovery tests on the bounded corpus. |
| NAS-NFR-08 | P1 | For Photos, measure peak Chronoframe staging against the configured budget plus the explicitly admitted largest complete asset, and separately measure PhotoKit-managed storage. Publish tested limits rather than promise a collection-independent total Mac footprint. |
| NAS-NFR-09 | P0 | For a cold, stable exact-only scan let H be sum(file sizes) for included regular supported candidates whose size occurs at least twice. For a hashed candidate, stable means enumeration size equals fstat on the opened hashed descriptor before and after reading, and bytes consumed equal that size; disagreement is unresolved and excluded from H, never accepted via trusted knownSize. Unique-size items receive no full-content reads. Count media bytes as the sum of positive read/pread return values at the hasher wrapper, including repeats/short reads, not requested buffer lengths or EOF calls. Stable automatic assessment must read ≤ H + max(1% of H, 8 MiB), with no decode/thumbnail reads. Record changed/unresolved/retry bytes separately and in the total run ledger; changing/fault trials cannot silently become clean budget passes. Actual SMB payload/readahead is a separate metric. |
| NAS-NFR-10 | P1 | Before adding automatic/budgeted image thumbnails, consolidate NAS list/detail acquisition through a descriptor-backed seekable data provider with all reads/preads counted/capped; retain the proposed 8 MiB default consumer-read allowance and placeholder/full-preview consent boundary. Ban unmetered URL-loader bypasses only for this future metered path. V1 uses explicit per-group potentially full-original previews without claiming this bound. Videos keep a placeholder until explicit request; metered video frames require a separately tested P1 AVFoundation resource-loader/equivalent contract that budgets index seeks/keyframe data, not an image-provider assumption. |

Do not set an absolute MB/s promise without a recorded hardware/network baseline. Network reads for source identity, copying and destination verification are not free; any optimization that combines/eliminates passes must demonstrate equivalent expected-identity, mutation-detection and verified-destination guarantees. Hash readback over SMB may be served from caches and is not proof of survival after NAS power loss.

## 16. Acceptance and fault matrix

Evidence must include the exact command or manual procedure, build/commit, setup, expected/actual result and receipt/log/screenshot/hash artifacts as appropriate. “Compiled,” “automated tests passed,” “signed SMB functional pass,” and “scale qualified” are separate statuses.

| Test | Requirements | Scenario and required result |
|---|---|---|
| T01 | NAS-SCP-01–03, NAS-UX-01 | P0: select the scattered tree; recursively assess the root with fixed exclusions and no media copies/moves. P1: scope-editor changes update counts without parent/child double counting. |
| T02 | NAS-SCP-03–05, NAS-REC-05 | Add unreadable subtrees, packages, links/aliases, nested mounts and NAS-generated containers. Record each category distinctly; no escapes, ordinary duplicate groups from recycle/snapshot contents, or false “complete.” |
| T03 | NAS-SCP-06–08, NAS-UX-03 | P0/B: basic folder summary and exact review remain usable on deep/Unicode/case-collision fixtures; checkpoint resume reconciles coverage. P1: advanced drill-down/path search. Folder display never limits global exact matching. |
| T04 | NAS-CON-01, NAS-DAT-01, NAS-PRV-01 | Assess a read-only share. Observe no Chronoframe create/write/rename/delete calls inside the assessed NAS tree; local state alone enables scan/review. Distinguish server-managed access changes. |
| T05 | NAS-CON-01–05, NAS-REC-02 | Remount under another path, replace with a same-name share, revoke access and create a local old-mount-path directory. Resume only on proved identity. Picker reselection starts at the validated reachable mount; unavailable/stalled probes time out off-main and cannot apply stale results or cause fallback writes. |
| T06 | NAS-CON-06–07, NAS-DAT-01, NAS-PRV-04 | P0: CLI remote dry-run/copy/maintenance/resume/revert/recovery are refused before state writes, even while the app is active. Test same-container app/host contention through aliases, owner termination and recovery, verified DELETE/FULL settings and actual SQLite VFS/locking evidence. Hold a writer and measure background-read elapsed/busy/cancel results plus p95 UI response at the actual busy_timeout; no main-thread stall. P1: real simultaneous app+CLI SMB contention only after proving shared namespace access. |
| T07 | NAS-DED-01–02, NAS-DED-07 | Identical bytes under different names/years/folders group exactly; same-name different bytes and intentional variants remain distinguishable. Weak/photo/video similarity respects existing automatic-eligibility rules. |
| T08 | NAS-DED-03–04 | P1 cleanup/protection qualification: Prefer one folder and protect another. Protected files and kept RAW/Live Photo/shared-sidecar units never enter destructive plans, including via fanout and after preference changes. |
| T09 | NAS-DED-05–06 | P0: persist/reopen exact review with unchanged, changed, renamed and unavailable files; no cleanup action exists. P1: additionally invalidate stale commit dependencies and test the remaining immutable plan. |
| T10 | NAS-DED-08–09, NAS-REC-07 | P1 only; not a v1 cleanup promise. On an authorized test SMB share, move owned test artifacts through macOS Trash and restore with identity checks. Repeat with unsupported Trash, revoked permissions and failure after quarantine. Unsupported cases touch no user targets or retain recorded recoverable state. |
| T11 | NAS-CPY-01–05, NAS-CPY-09 | Verify all copy directions and same-share disjoint roots. Sources retain recorded digests; collisions never overwrite; unsupported flush/exclusive-install behavior refuses finalization; pairs remain associated. Test fsync, metadata warnings, destination ACLs and AppleDouble separately. Force RENAME_EXCL/qualified-native-install ENOTSUP: copy offer is disabled and neither existing final data nor a placeholder-fallback path is used. Race a foreign final-path creator and prove it is not overwritten. |
| T12 | NAS-CPY-02, NAS-SCP-02 | Reject equal/nested source/destination roots at preview/start/resume, including link-resolved and remounted cases. Excluding a nested destination does not bypass rejection. |
| T13 | NAS-CPY-06–08, NAS-PRV-03 | B: existing verified outcomes/allowance/revert regressions. P1: new joined accounting/companion UI. Reconcile copied/already-present/excluded/stale/failed outcomes and free-batch replans. Distinguish assets/resources, reveal actual destinations, retain sidecar limitations, refund supported revert exactly once and never alter sources. |
| T14 | NAS-DAT-02–07 | P0/B: local assessment isolation, the remote journal-policy transition/readback and existing evidence regressions; P1: operational-state relocation. Inject faults at local/remote evidence appends; inject corruption, unsafe record links and conflicting legacy state. No silent reset, lost durable work or trusted receipt inferred from intent; recovery remains idempotent. |
| T15 | NAS-DAT-08, NAS-REC-06 | Remove a rebuildable cache; separately simulate local-state loss/reinstall. Recover only from actual retained evidence. Require fresh review when context is gone; do not repeat proven mutations. |
| T16 | NAS-REC-01–04, NAS-REC-08–09 | Disconnect/sleep/wake during discovery/hash/copy; acknowledge cancel and preserve stopping state. Retry remains bounded, thresholds are preserved, reconnect reconciles before scheduling, and P0 NAS review never gains destructive authority; P1 destructive continuation needs a fresh confirmed remaining plan. Verify existing executor idle-sleep assertions, assessment assertion lifetime and forced/lid-sleep reconnect behavior without overriding user sleep. |
| T17 | NAS-REC-05–07, NAS-CPY-08 | Kill the process or disconnect at temp write, flush, exclusive rename, spool append, receipt finalization, quarantine, Trash and restore (the last three are P1). Recover twice; outcomes agree with actual bytes, with no guessed success/absence. Preserve documented last-in-flight receipt limitations rather than inventing entries. |
| T18 | NAS-SPC-01–03, NAS-NFR-04 | P0/B: run NAS-native assessment/representative copy with free Mac space below collection size; inject local-state and remote quota faults. No full local replica or false completed writes. P1: aggregate capacity-preflight UI. |
| T19 | NAS-SPC-04–05 | P0/B: logical duplicate-byte labeling and safe cache eviction. P1: Trash/free-space reporting with snapshots/hard links present. Do not claim physical reclamation from nominal bytes. Cache eviction leaves journals, receipts, decisions and user media intact. |
| T20 | NAS-UX-02–05, NAS-PRV-02 | Test long/stalled work with keyboard/VoiceOver/reduced motion. Progress/uncertainty and recovery actions remain understandable; diagnostics are opt-in and redactable, with no credential leakage. |
| T21 | NAS-NFR-01–07, NAS-NFR-09–10, NAS-DED-02, NAS-UX-03 | P0: bounded corpus/exact parity and NFR-09 counters; inject size/descriptor changes, growth/truncation, short reads/EOF and keep unresolved bytes visible. Assert no image/video preview read on scan/selection/scroll/relaunch; each new group needs explicit potentially-full-original consent, with shared preview reuse and responsive UI. P1: bounded providers, repeated seeks/bypass traps and video index/keyframe resource-loader evidence for NFR-10, richer similarity, scale and soak. |
| T22 | NAS-PHO-01–05, NAS-NFR-08 | P1: export a selection exceeding staging budget, including iCloud items and multi-resource assets. Revalidate pinned destination, dates, access, consent and allowance across interruption; never publish half an asset or delete active staging. |

Additional variants for applicable cases: zero-byte/unreadable/changing files; content changed while preserving size/mtime; a selected keeper disappearing before commit; share read-only transition; quota that differs from volume free space; original path recreated during rollback; journal directory becoming unwritable; altered/replaced Trash contents; filename/path length limits; new files arriving mid-scan; root renamed during work; host clock/timezone changes; failed metadata reads with preserved media bytes. Keep size/mtime-preserving corruption tests on full-integrity/commit paths; a metadata cache scan alone must not be described as detecting it.

No destructive fault test runs against the owner's only copy of the library. Use a labeled disposable corpus on a separately authorized test share. Real owner-library assessment may supply usability/performance observations without mutation, with permission and private evidence handling.

## 17. Release evidence and go/no-go

### 17.1 Mandatory v1 gates

1. Accept the explicit v1 boundary: recursive exact assessment/review with local state, plus qualified existing app copying. NAS cleanup, metered previews/consolidation, cross-app/CLI remote writes, similarity, new protection/accounting UI, 1 TiB copy certification and the eight-hour soak are not v1 gates or claims.
2. Applicable existing Swift/safety/coverage/sandbox regression checks pass on the candidate; B requirements are inherited regressions, not new implementations. New exact/identity/storage paths have targeted fault tests.
3. On the named signed Synology profile, pass P0 portions of T01–T09 and T11–T21. P1 portions, T10 cleanup and T22 Photos are explicitly deferred. Use the bounded v1 corpus; publish the exact assessed/copied limits rather than 100,000-file/1-TiB certification.
4. Prove no assessment writes to the NAS, group parity against exhaustive hashes, NAS-NFR-09 assessment byte limit, zero automatic preview IO, explicit per-group preview consent, saved review/reconnect behavior and truthful incomplete coverage. No source-only assertion establishes actual network-byte performance.
5. Before offering copying on a profile, accept ADR-NAS-01–03, including app-container-only lease visibility, CLI refusal, actual SQLite held-writer read-latency evidence, descriptor fsync/error handling, metadata omissions and atomic no-overwrite foreign-writer behavior. If unresolved, assessment/review can ship alone; the UI must not imply qualified copying there.
6. Assert the v1 NAS cleanup action is absent/disabled regardless of the Trash probe. Store/help copy must say assess/review/copy as applicable, never completed NAS cleanup or reclaimed storage.
7. Owner records Go against build, P0 evidence, tested configuration and residual limits. No credible unresolved wrong-file mutation, overwrite, fabricated completion or lost unique-media risk is acceptable for offered operations.

P1 has separate gates: approved cleanup policy + real recovery evidence (T10); proven cross-app/CLI shared namespace and real SMB contention (T06 P1); metered still/video previews and consolidation (T21 P1); legacy migration; richer similarity/read budgets; new review/protection/accounting work; full-scale/soak (T21 P1); Photos (T22). Reorganize/Guardian qualification remains separate. Historical deferred release gates are not relabeled PASS by this narrower release.

### 17.2 Required release record

Maintain a NAS evidence ledger with: requirement/test ID; capability/profile; commit/build/signing; date/operator; exact procedure/command; corpus manifest/digests; Mac/NAS/network settings; expected/actual behavior; duration/memory/local footprint/I/O; before/after hashes and counts; receipts/journals/screenshots; recovery rerun result; limitation or failure disposition. Redact private paths/server names in any public copy.

## 18. Executable delivery slices

| Slice | Priority | Bounded deliverable | Exit / stop condition |
|---|---|---|---|
| 0 — establish copy prerequisites | P0 for offered copying | Probe identity, descriptor fsync, atomic no-replace install and current operational DB behavior on one authorized profile; record source-confirmed blockers in section 21. No deletion experiment is a v1 dependency. | Accept ADR-NAS-01–03 or disable that profile's copy offer while continuing read-only delivery. No broad state migration in this slice. |
| 1a — local exact assessment | P0 | New local assessment store; recursive stable-size inventory, coverage/exclusions and exact candidate hashing; basic folder summary. Reuse traversal rules, not the root-writing dedupe scanner unchanged. | T01–T07/T14 P0 and exact hash-parity/read-budget gate. No feature decoding/QL during the scan. |
| 1b — saved exact review | P0 | Paths/sizes/exact evidence, local saved choices/position, placeholders and explicit per-group potentially-full-original preview, resume/reconnect and no-cleanup state. No metered provider or render-path merge. | T09/T15/T16/T20, zero automatic image/video preview IO, consent and UI/resource gates. |
| 1c — qualify existing copy | P0 if offered | Minimal SMB adaptations to existing Organize: declared flush/metadata contract, app-container lease and CLI refusal, measured SQLite reader stalls, proven atomic no-overwrite installation and existing receipt/recovery regression. | Applicable T11–T19 plus representative signed copy batch. If unsafe primitives/state remain unresolved, release assessment/review only on that profile. |
| 2 — optional expansion | P1 | Separate cleanup-policy proposal/probe, metered still/video preview/consolidation, shared app/CLI coordination, protected folders, richer similarity, state relocation and joined accounting/companion UI. | Explicitly accepted scope and each requirement's own tests; not an automatic continuation of v1 saved decisions. |
| 3 — large-scale qualification | P1 | 100,000-file/1-TiB corpus, complete copy claim and eight-hour soak; additional hardware/network profiles. | T21 P1, with published limits and genuine evidence. |
| 4 — Photos bridge | P1 | Bounded transactional staging integrated with resumable import. | ADR-NAS-06 and T22. Edited-version support remains separate. |

Implement in this order with one maintainer: 1a → 1b; investigate slice 0 in bounded experiments; add 1c only when its prerequisites pass. Reuse implemented verification, retry, bookmark, lock and receipt contracts rather than counting them as new features. The exact-assessment byte budget is a v1 outcome; metered previews, shared CLI remote mutation and generalized scheduling/similarity optimization are not.

## 19. Risks and unresolved decisions

| Risk / decision | Required resolution |
|---|---|
| NAS cleanup decision / actual Trash result | **Decided for v1: no NAS cleanup.** Treat ordinary SMB Trash as unavailable for planning; actual API probe on this owner's Synology remains unrun because `mount -t smbfs` listed no mounted SMB volume during revision. P1 procedure: on an explicitly authorized disposable share, create an owned fixture, call `FileManager.trashItem`, record result/error/resulting URL, then prove hash-safe restore if it succeeds. Never test on the only media copy. A successful probe would inform a later scope decision, not enable v1 deletion. |
| Copy-install policy / owner exception | **Selected proposal: require native atomic no-replace installation.** ENOTSUP with no qualified equivalent means no copying on that profile, while assessment/review remains available. Reject accepting the check-then-rename window: INV-04 promises no overwrite and section 3.3 does not exclude foreign media writers. Only explicit owner approval of a changed product safety contract could accept that residual risk. |
| Reliable share/root identity unavailable through sandboxed APIs | Conservative reselection/revalidation; no pathname-only automatic resume or alias-safe claim. |
| App/CLI lease namespace mismatch | **Selected proposal: refuse CLI remote-destination writes in v1.** The sandboxed app has no app-group entitlement; RuntimePaths resolves different Application Support locations by process context. P1 must prove a common authorized namespace (for example a correctly provisioned app group) before permitting cross-app/CLI remote mutation. Do not assume an unsandboxed executable automatically gets equivalent container access. |
| SQLite effective locking strategy / reader stalls | Record actual system-library/VFS/locking evidence and held-writer reader/UI latency in T06. Network whole-file exclusive locking is a hypothesis, not a verified installed-library fact; unknown evidence requires explicit disposition and no main-thread wait. |
| Local operational state conflicts with portability/legacy coordination | Accepted authority/migration ADR and signed relevant-host evidence before moving state; cross-app/CLI sharing is P1. |
| Other apps modify the library during long analysis | Conservative checkpoints and commit-time validation. No snapshot-consistent completeness promise; no stale keeper-based deletion. |
| Same-NAS consolidation exceeds quota | Explain required additional capacity; offer smaller reviewed copies/another destination or in-place review if supported. Do not weaken source immutability. |
| NAS library contains catalog-only edits/albums | Explain raw-file scope and companion gaps. Preserve existing supported bytes; separate metadata/catalog integration from NAS support. |
| Very large libraries exceed proposed targets | Publish tested limits, record bottlenecks, preserve safe partial work; do not infer stress certification from smaller runs. |
| Existing release/monetization gates remain open | Recheck current candidate records; this project does not close earlier gates or authorize pricing/policy changes. |
| Actual owner setup not recorded | Before real-NAS validation, record model, DSM, filesystem, SMB, Mac/macOS, network, root layout, capacity/quota, Trash/snapshot settings and authorized test share. No credentials belong in this document. |

## 20. DECISION_LOG — proposed scope choices

These resolve specification gaps for planning. They are proposals, not changes to approved production policy.

- **D01:** Prioritize a fragmented library already on NAS; Apple Photos export is a P1 bridge.
- **D02:** One recursive common root with fixed safety exclusions is v1; a user subtree editor is P1. Disjoint multi-share projects and migration orchestration are deferred.
- **D03:** Read-only assessment is an independent useful mode and must work without writable NAS metadata or deletion permission.
- **D04:** V1 has no NAS in-place dedupe commit. Copy consolidation uses its existing explicit authority; assessment selection grants none.
- **D05:** One signed app installation on one Mac is the v1 remote-mutation boundary. Participating hosts prove the same app-container lease namespace; CLI remote-state writes are refused. Shared app/CLI access and its SMB contention gate are P1; distributed locking remains excluded.
- **D06:** V1 app assessment/review uses its container-local store; app remote operational opens propose DELETE/FULL under its identity lease plus destination lock. Verify journal transition, participating-host ownership and actual SQLite read latency. No shared CLI lease is claimed; state relocation remains P1.
- **D07:** NAS cleanup is an explicit v1 non-goal. A P1 recovery-folder proposal would require explicit safety-policy approval; this revision authorizes neither it nor hard delete. Actual Trash probe remains unrun, not an open v1 feasibility dependency.
- **D08:** Source/destination overlap remains prohibited even if scope excludes the nested output. Copy consolidation requires additional destination capacity.
- **D09:** V1 qualification uses 10,000 files/approximately 100 GiB/1,000 folders and a representative 100-file/10-GiB copy batch. Full 100,000-file/1-TiB qualification and eight-hour soak are P1; historical deferrals remain open. No larger-scale support claim follows from v1.
- **D10:** Preserve intentional variants and surface companion/catalog limitations. NAS work alone does not provide Apple Photos edits or XMP-copy integration.
- **D11:** Use private local QA/observed-session evidence; no telemetry or upload is introduced.
- **D12:** Capability support is published per tested workflow/configuration, not generalized from a single successful transfer.
- **D13:** SMB copy accepts descriptor fsync/SMB flush plus client readback under a separate explicit remote contract; retain stronger qualified local flushing. No hardware power-loss guarantee follows.
- **D14:** Exact-only assessment size-prefilters photos and videos, does no feature decoding, and has a candidate-byte-relative budget. Preview and future similarity have separate bounded acquisition policies.
- **D15:** B requirements reference AGENTS.md/established contracts; they are regression obligations, not new P0 scope.
- **D16:** Existing executor idle-sleep handling is reused; explicit/lid sleep is an interruption, not something the app may override. Metadata fidelity on SMB is bytes-required, auxiliary attributes best-effort/reported.
- **D17:** Reject a NAS placeholder-race exception to INV-04. Require native atomic no-replace; copying can be unavailable on an unsupported profile. Probes discover capability; they do not choose or waive the policy.
- **D18:** V1 uses placeholders plus explicit per-group potentially-full-original previews for both images and videos. Metered still providers, separate video resource-loader budgeting and render-path consolidation are P1. One preview per exact identity/render configuration suffices.
- **D19:** Invariant references/test tags bind to permanent INV-NN labels, not AGENTS.md bullet position. The guard must parse explicit labels and reject unlabeled/duplicate IDs without renumbering existing rules.
- **D20:** Size stability and H are defined by enumeration/descriptor/consumed-byte checks; count positive read/pread returns. Picker reselection is a new bounded off-main NAS adaptation, not unchanged baseline reuse.
- **D21:** Treat system SQLite's effective SMB locking strategy as observed evidence, not an assumption. Capture held-writer reader latency/busy behavior and UI response; retain the proposed DELETE/FULL candidate only if its profile gate passes.
- **D22:** Stable invariant labeling/guard belongs on its own main-based review branch, not the unrelated current feature/marketing branch. Its commit is a separate prerequisite, not part of NAS implementation approval.

## 21. Source basis and current-state limits

### 21.1 Concrete implementation blockers and reuse

| Finding | Source-confirmed fact | V1 implication |
|---|---|---|
| Current dedupe assessment writes to root | `DeduplicateScanner.swift:92–95` opens/initializes `<root>/.organize_cache.db`. | Read-only assessment cannot call this path unchanged; use the separate local store/path in slice 1a. |
| Cold photo hashing lacks size prefilter | `DeduplicateScanner.swift:145–156` submits all image paths, while videos use size-collision candidates (`:747`). Valid cache hits can avoid hashing. | Add explicit exact-only photo/video candidate sizing; do not claim every warm scan rehashes all images. |
| Feature/preview work uses separate URL reads | `DeduplicateScanner.swift:1095` opens ImageIO and `:1151` creates a URL-based Vision request; `ThumbnailRenderer.swift:21–29` invokes QuickLook, and ClusterDetailPane has the separate still-preview path listed below. | Separate acquisitions exist, but two-to-three *full network passes* is not measured fact. Enforce scan/preview budgets rather than infer physical traffic from source calls. |
| Separate comparison preview bypasses shared renderer | `ClusterDetailPane.swift:1037–1047` creates a URL-based ImageIO source and requests `kCGImageSourceCreateThumbnailFromImageAlways`; still comparison rendering is outside ThumbnailRenderer. | The renderer is currently a shared QuickLook path, not a single entry point for all previews. Consolidation and metered input are new P1 work; v1 uses explicit preview consent instead. Source calls do not prove a measured full-file network read. |
| Caller-supplied hash size is trusted | `FileIdentityHasher.swift:41–53` accepts knownSize; the path opens its descriptor later. The descriptor hashing loop consumes reads but does not check the supplied size against fstat before/after. | Implement the stable-size/byte counter contract for NAS assessment; a stale size prefix cannot be accepted as verified identity. |
| Picker avoids reachable network start paths | `FolderAccessService.swift:131–134` chooses home for non-local volumes. | NAS-CON-01 requires a bounded off-main reachability/identity check and reachable-mount reselection; retain fast fallback for stale/stalled mounts. |
| App/CLI share code, not an on-Mac container | `Chronoframe.entitlements` enables sandboxing without application-groups; RuntimePaths uses process-resolved user Application Support. `CLI.swift:540` also opens OrganizerDatabase, whose writable init requests WAL. | The proposed generic local lease would resolve to different app/CLI files. V1 must refuse CLI remote writes before DB/log/lock access. A common namespace and true cross-app/CLI SMB contention are P1. |
| Unknown volume becomes local | `DestinationOperationLock.swift:91–92` returns false when remote attributes are unknown. | NAS-CON-05 requires unknown/ambiguous identity handling; do not inherit this boolean as proof of safe local fallback. |
| Copy requires F_FULLFSYNC | `TransferExecutor.swift:1091` throws on failure without a descriptor-fsync SMB contract. | Adapt only the remote path under ADR-NAS-03; server-specific ENOTSUP must be measured, not presumed universal. |
| Exclusive-install fallback has a race | `TransferExecutor.swift:1111–1114` uses the placeholder fallback on ENOTSUP; `:1129–1140` documents its foreign-writer check/rename window. | It is not acceptable evidence of atomic NAS no-overwrite. Whether the target SMB profile enters this path is a probe result, not a source-established “normal SMB path.” |
| Metadata behavior differs from proposed contract | `TransferExecutor.swift:68` requests COPYFILE_ALL; `:79` requests STAT/XATTR/ACL on clone metadata. Non-clone failures throw; clone metadata return is ignored (`:1070–1075`). | Distinguish/report metadata omissions and data failures under NAS-CPY-09; actual AppleDouble/xattr behavior requires the target share. |
| Sleep support already exists | `TransferExecutor.swift:447–452, 511–516` and dedupe/revert/reorganize executors hold idle-system-sleep activities. | Reuse existing execution assertions; add the explicit assessment/lid/wake lifecycle and tests, not a duplicate assertion system. |

### 21.2 Source references

Repository sources used to distinguish existing behavior from proposed work:

- [AGENTS.md](../AGENTS.md), [Safety and Recovery](SAFETY_AND_RECOVERY.md), [Technical Documentation](TECHNICAL.md): source immutability, verified copying, mutation plans, pairing, locks, recovery and artifact contract.
- [MediaDiscovery.swift](../ui/Sources/ChronoframeCore/MediaDiscovery.swift), [MediaDateResolver.swift](../ui/Sources/ChronoframeCore/MediaDateResolver.swift): recursive discovery and current supported-media filtering.
- [DestinationOperationLock.swift](../ui/Sources/ChronoframeCore/DestinationOperationLock.swift), [NetworkDestinationAdvisory.swift](../ui/Sources/ChronoframeAppCore/Support/NetworkDestinationAdvisory.swift): network detection/advisory and current per-machine lock limitations.
- [OrganizerDatabase.swift](../ui/Sources/ChronoframeCore/OrganizerDatabase.swift): destination database, WAL request and operational state. Its existence is an investigation input, not evidence of NAS corruption.
- [TransferExecutor.swift](../ui/Sources/ChronoframeCore/TransferExecutor.swift): source validation, copy/flush/verification, exclusive install, capacity checks, retries and bounded workers.
- [DeduplicateExecutor.swift](../ui/Sources/ChronoframeCore/DeduplicateExecutor.swift): receipt/journal preflight, quarantine and macOS Trash path.
- [FolderAccessService.swift](../ui/Sources/ChronoframeAppCore/Services/FolderAccessService.swift): folder selection, security-scoped access and unavailable-folder behavior.
- [DeduplicateSessionStore.swift](../ui/Sources/ChronoframeAppCore/Stores/DeduplicateSessionStore.swift): current in-memory review continuation versus persisted folder history.
- [PhotosImportStore.swift](../ui/Sources/ChronoframeAppCore/Stores/PhotosImportStore.swift), [PhotosResourceExportService.swift](../ui/Sources/ChronoframeAppCore/Services/PhotosResourceExportService.swift): full-selection staging and original-only read-only export.
- [Remaining work plan](remaining-work-plan.md): historical scale/soak deferrals. This document proposes new NAS gates; it does not relabel earlier evidence.

External primary sources:

- [SQLite: write-ahead logging, including section 8](https://www.sqlite.org/wal.html) — documents EXCLUSIVE-before-first-access WAL without shared memory. That alternative requires guaranteed connection/process ownership; it is not an automatic network-safety guarantee.
- [SQLite: journal_mode pragma](https://www.sqlite.org/pragma.html#pragma_journal_mode) and [rollback locking](https://www.sqlite.org/lockingv3.html) — basis for the proposed DELETE journal and returned-mode verification. Rollback journaling still relies on correct filesystem locking/durability.
- [Synology: SMB service settings](https://kb.synology.com/en-us/DSM/help/SMBService/smbservice_smb_settings?version=7) — configuration context. Exact tested settings belong in the qualification ledger.
- [Synology: USB Copy filtering notes](https://kb.synology.com/en-me/DSM/help/USBCopy/usbcopy_general?version=6) — examples of NAS-generated `@eaDir`, `#recycle` and `#snapshot` containers. Chronoframe's exclusions require independent tests on supported DSM configurations.
- [Apple: move a Photos library](https://support.apple.com/en-sg/108345) — distinguishes a supported Photos library location from an ordinary exported-media archive on a network share.

- [Apple SMB client source](https://github.com/apple-oss-distributions/SMBClient/blob/main/kernel/smbfs/smbfs_vnops.c) — `smbfs_vnop_fsync` forces a flush; the F_FULLFSYNC handler checks server full-sync/continuous-availability capabilities and can return ENOTSUP. This source disproves “APFS-only,” but does not establish behavior of the owner's installed OS/server combination.
- [Apple FileManager.trashItem](https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)) — API contract, not evidence that it works on the target share.

Evidence status: repository and primary-source review only. `mount -t smbfs` returned no mounted SMB entries; no real-share flush/Trash/rename probe, benchmark, customer-media mutation or signed NAS verification was performed.

## Appendix A. Review history

[Versioned review dispositions](NAS_REQUIREMENTS_REVIEW_LOG.md) preserve the v0.2/v0.3 decisions and the v0.4 superseding scope choices. The active requirements above take precedence over older review-log statements.
