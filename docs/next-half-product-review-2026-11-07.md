# Chronoframe: next-half product recommendations

Status: **revised proposal**. Prepared November 7, 2026. No product or design approval is implied.

Revision: the edits/NAS follow-up below supersedes Round 2's ranking. Round 1 and Round 2 remain the record of the initial challenge process.

## Product judgment

Make Chronoframe the easiest way to finish a trustworthy, usable photo archive. The strongest delight is relief: my work survived, my dates are right, my photos are accounted for, and I can find them again.

The current product already has substantial organizing, deduplication and recovery machinery. Invest in completing customer jobs across that machinery before adding new ways to analyze pictures.

## DECISION_LOG — review assumptions

- “Next half” means the next six months, approximately November 2026–April 2027, rather than a fixed calendar half.
- Use the repository's one-maintainer constraint until staffing is explicitly changed. Ten recommendations are an ordered investment list, not a promise that ten projects fit the capacity available.
- Primary customer: a Mac owner consolidating years of family photos/videos from folders, drives and Photos. A professional digital asset manager is a different product.
- Recommendations must preserve read-only Organize sources and Apple Photos, verified copies, review gates, Trash-only dedupe, pair/sidecar retention and content-safe undo. Existing user-approved policies remain in force.
- Demand and willingness to pay are hypotheses. No interviews, conversion funnel or support corpus was supplied. Source inspection establishes implementation gaps, not their prevalence among customers.
- Keep the existing no-analytics/no-upload promise. Measure proposed outcomes through recruited usability sessions and local QA fixtures; any product telemetry would require a separate privacy decision.
- Evaluate candidates by severity/frequency of the customer job, utility and delight, fit to Chronoframe, incremental value over existing capabilities, and build/support/safety cost. Do not fabricate numeric impact scores.
- Keep an idea only when its *bounded deliverable* has a stronger expected customer benefit than its strongest objection and opportunity cost. A tie goes to deferral. This is a product judgment, not empirical proof.

## Current capability baseline

| Area | Present in this checkout | Consequence for the roadmap |
|---|---|---|
| Organize | Date-based layouts; verified copies; content-based skip/collision handling; review overrides; profiles; resume/recovery; receipts and revert | “Safe imports,” “undo,” or “profiles” are not new feature proposals. |
| Dates and events | Per-item date/event edits; Smart Event suggestions; this branch also implements conflicting-date warnings and an alternative-date action | Batch clock correction is the gap, not basic date detection or editing. |
| Deduplicate | Exact/similar photos; RAW/Live Photo units; sidecar retention; quality and match explanations; rapid triage; comparison modes; optional review-only similar videos | More comparison modes and automatic near-duplicate deletion lose to continuity and customer control. |
| Review continuity | Pause/resume in memory; persistent folder run history | Relaunch-safe saved review decisions are a real delta. |
| Watched folders | Multiple registered sources; conservative arrival estimates; per-source Review & Import | Folder watching already exists. Unattended importing changes the consent model. |
| Photos | Album browsing, cross-album selection, original-resource export, shared capture dates, transactional Live Photos, reviewed verified import | Preparation currently starts fresh after purging abandoned staging. Progress/cancel/checkpointing improves an existing flow. |
| Health and History | Aggregate results, issue views, receipt viewer, artifact search, undo, receipt Spotlight indexing | Completion accounting must connect every item to evidence; search must search media mappings rather than repeat artifact-title search. |
| Sidecars | Dedupe discovers and retains shared XMP owners; Organize discovery admits only photo/video extensions | Copying existing XMP files alongside organized photos is new work. |
| Folder preferences | Core supports additional dedupe sources and keeper priority; the app does not expose them | Keeper preference has a substrate. A protected folder still requires an explicit planner-enforced guarantee. |
| Guardian | Integrity baseline, scrub, verified mirror, restore and in-app/catch-up scheduling implemented; `GuardianCapability.isEnabled = false` | This is a finish-and-validate launch investment, not an already-shipped feature or merely a dashboard refresh. |

Availability above describes this source checkout. Store availability and physical-device verification are not inferred. The local release ledgers retain signed test/purchase/restore and other open gates; do not treat their historical dates as current App Store status.

## Round 1 — the initial ten and their strongest objections

| Candidate | Strongest case for | Strongest case against | Decision |
|---|---|---|---|
| 1. Guided first successful archive | A novice should see a small, real, verified result before trusting years of memories to a utility. | Setup guidance and a free test batch already exist; another wizard could add friction. | **Retain narrowly:** preflight capacity/access and show the existing sample flow's result, not a new tutorial. |
| 2. Dedupe review that survives quitting | Reviewing thousands of groups is work done over days; losing judgment is expensive. | Saved Delete choices can become stale and unsafe. | **Retain:** persist decisions by content identity and invalidate changed items; never replay a destructive commit automatically. |
| 3. Batch camera-clock/date correction | One wrong camera clock can misfile a whole trip; per-item correction does not scale. | A bad batch correction can create thousands of wrong dates. | **Retain:** explicit selection, before/after preview, undo and relative-time-preserving shifts. |
| 4. Resilient large Photos imports | iCloud downloads and exports are long operations where progress, cancellation and resumption matter. | Safe checkpoints, staging cleanup and destination pinning add complexity. | **Retain:** checkpoint complete assets in export preparation and reuse the existing transfer pipeline. |
| 5. Google Takeout rescue | People migrating archives need exported metadata associated with the correct media. | Audience size is unproven; ambiguous names and format changes can cause silent misassociation. | **Retain narrowly:** extracted local folders and unambiguous associations; unresolved cases go to review. Validate demand before committing the adapter. |
| 6. Customer-ready Guardian | A verified archive should remain recoverable after silent corruption or a missing file. Much of the engine exists. | This expands the responsibility to continuing protection; disabled code is not proof of readiness, and a mirror is not a complete backup strategy. | **Retain as the later investment:** ship only after explicit integrity/mirror/restore gates; describe coverage and limitations factually. |
| 7. Multi-source migration workspace | A household's archive is spread across many drives; a single project could track the whole job. | A durable queue, unplugged drives and per-source approval create a new orchestration system; profiles and watched sources already provide a usable sequence. | **Remove:** useful, but its incremental value is below its scope for this half. |
| 8. Unattended watched-folder import | Reduces repeat visits and feels effortless after setup. | Consent, arrival windows, allowance handling and run receipts all need new policy; incorrect automatic filing weakens a defining trust boundary. | **Remove:** saving a click does not justify changing the product's review contract now. |
| 9. Semantic photo search | “Find the beach photo with Dad” is an immediately understandable benefit. | Builds indexing, model support and search-quality obligations while competing with dedicated photo libraries; it does not finish the archiving job. | **Remove:** retrieval is valuable, but the full semantic product has the wrong cost and scope. |
| 10. Metadata-complete Apple Photos export | Albums, captions, favorites and edits are part of a family's collection, not just the original bytes. | It implies a fidelity/round-trip promise that the current original-resource seam does not establish; metadata availability and edited render handling need separate research. | **Remove:** too much implied completeness for a six-month commitment. |

Six survived. Add four replacements: item-level archive reconciliation, preferred/protected keeper folders, existing XMP companion preservation, and receipt-backed file lookup. Challenge the complete ten again below; the replacements do not get a free pass.

## Round 2 — final ranked ten, re-challenged

### 1. Save my dedupe review across relaunches

**Build:** Save choices, reviewed groups and the current position. Restore only against matching content; changed files require another review. Keep final Trash approval explicit.

**For:** This protects the customer's most costly input: their judgment. It makes large libraries manageable in short sessions.

**Against:** Stale decisions and versioned snapshots can introduce a dangerous new recovery surface.

**Why it stays:** Fail closed on identity changes and restore review state, never execution authority. This directly removes repeated work without changing deletion policy.

**Measure:** In a multi-session fixture, unchanged decisions survive quit/relaunch and changed files lose deletion eligibility; observe how many groups users must review twice. Proposed acceptance: zero lost unchanged choices and zero silently retained stale Delete approvals in that fixture.

### 2. Make large Photos imports visible, cancellable and resumable

**Build:** Show preparation progress by asset, waiting-for-iCloud state and failures. Offer cancellation and explicit resume using complete-asset checkpoints. Account for staging and destination capacity separately; expire abandoned staging visibly. Revalidate access, selected resources and the pinned destination on resume.

**For:** The customer can finish an import rather than repeating downloads and wondering whether the app has stalled.

**Against:** Staged originals are sensitive and large; checkpoints complicate cancellation, cleanup and identity validation.

**Why it stays:** A bounded export-preparation checkpoint solves a predictable failure of large imports while preserving original-only, read-only PhotoKit and the existing reviewed transfer path. Failed and cancelled exports must never publish partial Live Photos.

**Measure:** An interrupted export resumes completed eligible assets without re-exporting them, explains every failure, and retains no staging beyond the documented completion/abandonment policy. Test iCloud waiting, revoked access and changed destination explicitly.

### 3. Correct a camera's clock across a selected batch

**Build:** Choose a folder/camera/date-filtered selection, shift capture time by an explicit amount or apply a date, inspect before/after dates and destination folders, then accept. Clock shifts preserve relative capture times. Support one-step undo of the review change.

**For:** A repetitive repair becomes one understandable action, and the archive ends up in the right years and days.

**Against:** An incorrect selection or offset magnifies a single mistake across the archive.

**Why it stays:** Selection, preview, explicit acceptance and unchanged source metadata constrain the risk. Existing durable overrides make this a focused extension rather than a metadata editor.

**Measure:** Completion time and errors for a deliberately mis-set camera batch versus per-item editing. QA covers midnight/timezone boundaries, preserved time spacing and Live Photo units.

### 4. Account for every item after an archive run

**Build:** Reconcile the frozen selection against the executed result: copied and verified, identical destination located, intentionally excluded, failed, changed or unresolved. Each row links to its destination or reason and a next action. Keep photo assets and file resources distinct in the totals. Retry unresolved items through a fresh preview.

**For:** “All finished” becomes an answer the customer can inspect, not a count they must trust. It resolves the fear that some memories went missing.

**Against:** Counts, issue panels, reports and receipts already exist; this could be another redundant report with false reassurance.

**Why it stays:** The new value is joining outcome, identity and location for every selected item, across preflight exclusions and execution changes. It must say incomplete when evidence is missing. It never declares a source safe to erase or infers unrecorded successful transfers.

**Measure:** Users can locate a named imported file and explain every non-copy result without opening logs. Fixture counts reconcile even after cancellation, free-batch replanning and partial failures; unreadable subtrees remain explicitly unassessed.

### 5. Make the first archive feel safe before it starts

**Build:** Add a clear capacity/access assessment to existing setup, explain which volume needs space, and lead naturally into the existing small verified test batch. Show the actual files created and the available undo action. Keep experienced users on their current direct path.

**For:** The user gets evidence on their own files and avoids preventable failures before committing to a large copy.

**Against:** Existing onboarding and sample flows already cover much of this; another wizard delays success and capacity estimates can become inaccurate.

**Why it stays:** Extend existing surfaces rather than add a wizard. Label capacity estimates and unknowns, include Photos staging where relevant, and recheck at execution. The value is preparedness and proof, not more explanation.

**Measure:** Unassisted first verified archive completion, preventable storage/access failures, and whether users understand that originals remain untouched. Compare with the current flow in observed sessions.

### 6. Let customers prefer a keeper folder and protect curated folders

**Build:** Within the selected dedupe root, let users prefer a subfolder when choosing among equivalents and separately mark a subfolder protected from Trash targets. Show how each rule affects the plan. Protection is a planner constraint; preference alone is not protection.

**For:** “Keep my curated album; remove redundant backup copies” matches how people reason about their archives.

**Against:** Folder rules may keep a technically worse image, complicate pair ownership and create a false sense that a preference guarantees safety.

**Why it stays:** Make the two controls distinct, respect pair/sidecar Keep-wins, and leave near-duplicate decisions review-only. Bound v1 to the chosen root; cross-drive reference-root management can wait. Organize source folders gain no mutation permission.

**Measure:** Fewer corrected keeper suggestions in a curated-folder task; zero protected paths or retained pair/sidecar units enter the destructive plan in fixtures.

### 7. Keep existing XMP companions with organized photos

**Build:** Copy recognized, unambiguously owned XMP files unchanged alongside their parent photos; preserve shared RAW/JPEG ownership through destination naming, verify and receipt the copies, and revert matching copies safely. Explain unresolved companions. Do not promise rendering edits or reconstructing Apple Photos metadata.

**For:** An archive should retain the existing files that can carry ratings, edits and descriptive metadata, not just the image bytes.

**Against:** One sidecar can have multiple owners, and independent collision names can break ownership. Sidecar presence does not prove that another app will interpret it.

**Why it stays:** Scope to preserving existing supported files, with shared-basename ownership an acceptance condition. This repairs an archive-fidelity gap without expanding into editing or claiming application-level round trips.

**Measure:** Known XMP/RAW/JPEG ownership fixtures preserve content and associations after copy, collision handling and revert. Unsupported or ambiguous companions remain visibly unresolved.

### 8. Find an imported file by its original name

**Build:** Search media mappings from trusted run records by original filename and source, with import-date filtering and Reveal in Finder. Show moved/missing/unavailable destinations honestly. Handle multiple imports and matching filenames explicitly.

**For:** Renaming and date folders help organization but can make a remembered `IMG_1234` difficult to find. This closes the loop from importing to using the archive.

**Against:** A catalog adds indexing and staleness complexity; Finder, artifact search and receipt viewers already exist.

**Why it stays:** Search the media entries across recorded runs, not just artifact titles. Reuse receipt mappings and exclude semantic search, face recognition, offline thumbnail libraries and undocumented whole-library claims. Coverage is only as complete as the recorded evidence.

**Measure:** Time to locate an old file using its original filename compared with current History/Finder. No result presents a disconnected or absent file as available, and large receipt lookups do not block the UI.

### 9. Rescue an extracted Google Takeout archive

**Build:** A local-folder adapter associates supported JSON sidecars with media unambiguously, surfaces date conflicts for review, preserves sidecars/provenance and routes media through normal preview and verified transfer. Keep embedded dates unless a reviewed rule resolves a conflict. No Google login or cloud connector in v1.

**For:** This turns a confusing export into a usable archive and fits Chronoframe's consolidation job. Google documents secondary JSON files for additional photo metadata.

**Against:** Demand is not established; export variants and duplicated/truncated names make incorrect association costly. A long format-support tail can overwhelm one maintainer.

**Why it stays:** Narrow the supported formats, test consented real exports before staffing implementation, reject ambiguous matches, and publish limitations. It deserves a ranked slot because it solves the core migration job better than a general search or gallery expansion, but it is the first candidate to drop if recruitment finds no demand or the parser cannot be bounded.

**Measure:** On labeled real-export fixtures, correct associations, unhandled formats and unknown/conflicting dates. Proposed shipping gate: no silently wrong associations in the supported fixture corpus; unsupported cases remain reviewable. Do not assume all original capture dates have been lost.

### 10. Finish Guardian as a comprehensible protection feature

**Build:** Validate and launch the currently disabled feature. Show trusted-baseline coverage, last complete verification, verified mirror coverage and drive availability separately. Offer the relevant next action, and make selected-file restore understandable and evidence-backed. Retain in-app scheduling and launch/wake catch-up; defer a closed-app daemon.

**For:** Discovering damage is useful only if the customer understands what can be recovered. Much of the hard machinery is already present.

**Against:** This is the largest expansion of product responsibility. A green indicator can overpromise, a same-drive mirror does not cover drive loss, and restore is safety-critical.

**Why it stays:** Make claims about specific verified files at specific times, distinguish untrusted from damaged and configured from recoverable, and explicitly explain failure-domain limitations. Require signed external-volume and interruption/restore evidence before enabling the flag. If those gates do not pass, it remains disabled; no deadline overrides them.

**Measure:** Users can explain what is protected and restore a known damaged/missing selected file in a controlled test. Newly observed files never gain trust automatically; bad mirror bytes and changed primary files remain blocked; interrupted restore recovery preserves originals.

All ten survive the second comparison **as bounded proposals**. The original objections remain recorded; the revised scopes reduce those costs instead of pretending the objections disappeared. This stopping point expresses stronger expected value under the assumptions above, not certainty about demand.

## Follow-up challenge — edited photos and Synology NAS

The owner's follow-up supplies a concrete NAS capacity use case. This strengthens NAS priority relative to the previously hypothetical Takeout audience. It also reveals that the rejected “metadata-complete Photos export” bundled two different jobs: preserving the current edited appearance, and reconstructing an editable library. The first deserves a roadmap slot; the second remains deferred.

### Current preservation behavior

- Folder imports copy file content. Edits already baked into an exported JPEG/HEIC/TIFF remain in the copied file. Edits stored in a separate XMP, adjustment file or application catalog are not thereby captured. Existing XMP companions are currently excluded from Organize discovery.
- Apple Photos import deliberately selects only `.photo`, `.video`, and `.pairedVideo`. `PhotosResourceExportService.swift:84–94` explicitly excludes modified resources and adjustment data. Edits made inside Photos, such as crops, filters and retouching, therefore do not accompany the imported originals. The original Photos library and its edits remain untouched.
- Preserving a rendered edited version preserves its visible result. It does not promise editable sliders, edit history or a lossless round trip into Photos. Preserving XMP is complementary and does not reconstruct Photos edits.

### New candidate: preserve originals and the edited appearance

**Build:** Add an explicit “Originals + edited versions” import option alongside Originals. For edited assets, request the current full-resolution appearance through supported read-only PhotoKit resource/render paths; export it as a separate, linked intentional variant. Keep the original unchanged, retain capture-date provenance and show the extra storage cost in preview. Do not assume every asset exposes an already-materialized full-size edited resource. Scope and validate Live Photo/video behavior explicitly before making broader preservation claims.

**For:** The version a user has cropped, straightened or color-corrected is often the version they care about seeing again. Archiving only the pre-edit capture can violate their practical expectation of preservation.

**Against:** Extra variants increase storage, complicate dedupe and require fidelity testing across formats, HDR, orientation and third-party edits. Keeping visible results still does not preserve future editability.

**Verdict:** **Keep; rank 3.** The deliverable is specific and understandable: retain both the capture and how it currently looks. Pair/group variants explicitly so dedupe does not silently suggest discarding an intentional edit. Failed renders must be visible; no silent fallback to “edits preserved.” This would be a proposed expansion of the original-only import contract, requiring explicit approval before implementation, while retaining strictly read-only PhotoKit access.

**Acceptance:** On edited/unedited, cropped/rotated, color-adjusted, HDR/RAW and third-party-edited fixtures, original bytes remain identical; the edited export matches the supported current Photos appearance within a documented output/color policy; both versions have correct dates and distinct identities. Unsupported or failed variants are reported. Validate video/Live Photo claims separately; do not infer complete edit-history fidelity.

### New candidate: first-class NAS archiving

Detailed scope, requirements and release gates: [NAS requirements — revised proposal](NAS_REQUIREMENTS.md), focused on an existing large collection distributed across NAS folders.

The requirements review narrows v1 to local-state read-only assessment, cross-folder exact review and qualified use of the existing copy flow. NAS duplicate cleanup is excluded from v1; full 1-TiB certification, soak and richer workflows are follow-on work. The broader candidate below describes the investment direction, not the v1 shipping commitment.

**Build:** Establish a Synology SMB support contract for one coordinating Mac, then improve capacity, interruption handling and measured throughput. Include NAS sources, destinations and NAS-to-NAS workflows. A full local copy of the archive must not be a prerequisite.

**For:** NAS capacity serves the core large-library customer. It is an existing owner use case and a constraint on whether the organizing job is possible at all.

**Against:** Network disconnects, permissions, flush/rename behavior, remote Trash and database semantics create a substantial support matrix. Tuning concurrency alone cannot establish safe behavior.

**Verdict:** **Keep; rank 2.** Bound v1 to tested Synology SMB configurations and a single coordinating Mac; multi-host mutation remains unsupported. Establish correctness before throughput claims. This outranks a standalone onboarding project and Takeout expansion.

**Work in order:**

1. Validate metadata/recovery storage on SMB. The destination database currently requests WAL (`OrganizerDatabase.swift:167`); SQLite documents network-filesystem limitations. Evaluate keeping high-churn indexes/operational databases locally under a stable library identity, while preserving durable receipts, recovery evidence and app/CLI coordination. Do not treat the current database as a disposable cache: it also contains queues and overrides. Architecture choice and migration remain open.
2. Replace whole-selection Photos staging with bounded, checkpointed batches. `PhotosImportStore.swift:190–209` currently finishes exporting the selection locally before handing off to transfer. Preserve reviewed consent, asset transactions, identity validation and the pinned destination across batches. Account for PhotoKit/iCloud's own downloads as well as Chronoframe staging; do not promise a hard total local-storage bound without measuring both.
3. Handle disconnect, reconnect, sleep/wake, changed mount paths, permission loss and quota exhaustion with explicit incomplete/recoverable state. Reconfirm the intended share before resuming. Validate SMB flush/no-overwrite install and actual macOS Trash/restore support; do not equate Synology's server recycle bin with macOS Trash. Where reversible Trash cannot be provided, explain the unsupported operation rather than hard-delete.
4. Measure cold/warm scan latency, network metadata operations, bytes transferred and verified-copy throughput. Existing caching and bounded copy concurrency already exist. Investigate batching, network-aware concurrency and eliminating provably redundant I/O while retaining source identity checks and destination verification. No benchmark or speedup is established by source inspection.

**Acceptance:** On an actual Synology SMB share, archive a selection larger than available local staging capacity with a bounded staging footprint; verify content and unchanged originals; interrupt/reconnect and resume without false completion or overwrites; exercise quota failure, remount identity, receipt recovery and supported Trash/revert. Report model, DSM/macOS, protocol, network and corpus for throughput results. NAS server crash/power-loss durability requires its own evidence and is not proved by a client hash match.

### Revised ranked ten

| Rank | Recommendation | Change from Round 2 |
|---|---|---|
| 1 | Dedupe review persistence | Retained |
| 2 | First-class NAS archiving | Added; includes network storage architecture and bounded Photos staging |
| 3 | Originals plus current edited versions from Photos | Added; narrower than a metadata/edit-history round trip |
| 4 | Visible, cancellable, resumable Photos import | Retained; shares checkpoint/staging work with NAS |
| 5 | Batch capture-date correction | Retained |
| 6 | Item-level completion reconciliation | Retained |
| 7 | Preferred/protected keeper folders | Retained |
| 8 | Existing XMP companion preservation | Retained; complementary to edited Photos exports |
| 9 | Original-filename lookup across runs | Retained |
| 10 | Validated, comprehensible Guardian launch | Retained |

**Remove the standalone first-archive project:** capacity/access assessment belongs in NAS/import delivery and the existing onboarding/test-batch surfaces. A separate project now has weaker incremental value than the two additions.

**Defer Takeout:** the migration problem remains plausible, but actual NAS need and missing edited appearances have stronger evidence and broader relevance to current workflows. Reconsider after customer recruitment establishes demand.

The other eight retain their Round 2 arguments and scope boundaries. Re-challenging their opportunity cost keeps them ahead of the two displaced projects. NAS and Photos import share infrastructure and must not be estimated as independent implementations.

DECISION_LOG additions: use the owner's Synology NAS scenario as qualitative evidence, not a benchmark; preserve visible edits separately from editability; treat NAS metadata placement and PhotoKit rendition details as open engineering decisions; all changes remain proposals, with no source behavior or safety invariant changed.

Sources: [Apple resource types](https://developer.apple.com/documentation/photos/phassetresourcetype/fullsizephoto) distinguish original, modified and adjustment resources; [Apple adjustment-data documentation](https://developer.apple.com/documentation/photos/phadjustmentdata) describes application-defined edit recipes; [SQLite WAL documentation](https://www.sqlite.org/wal.html) describes shared-memory/network limitations. Source inspection identifies risks to investigate, not observed NAS corruption or measured performance failures.

## Staffing and sequence — revised ranking

1. **Before expanding scope:** revalidate outstanding release gates against the actual current release candidate. The repository records unresolved checks; this review does not close them or assume present Store approval.
2. **First investment:** #1 and the NAS correctness/capacity work in #2, followed by the shared Photos export work in #3–#4. Prototype edited-rendition fidelity early, before promising format coverage. Establish baseline throughput and local storage needs on the actual Synology configuration.
3. **Next investment:** #5–#9 as capacity permits. Keep folder protection within one root. Share outcome mappings between completion accounting and file lookup; keep XMP preservation separate from any promise of reconstructing Photos edits.
4. **Safety-gated bet:** #10. Validate Guardian alongside delivery planning, not by enabling hidden code and hoping it is ready. Takeout and a standalone onboarding project are deferred.
5. **Capacity rule:** reserve explicit time for maintenance and signed validation. Estimate the first delivery slices before promising dates; with one maintainer, pull the next ranked item only when capacity remains. Do not advertise ten independently staffed launches. If leadership requires all ten in the half, resolve capacity or reduce the scopes rather than promise an unsupported schedule.

## Evidence and research limits

Static review only; no build, runtime session, customer interview or new signed verification was performed for this roadmap. Read-only inventory/search commands returned the evidence summarized below. Documentation changes are checked separately; prior test results belong to their cited ledgers, not this review.

Repository anchors (paths relative to the repository root):

- `README.md`, `docs/TECHNICAL.md:122` — current organizing, review, Smart Events, Health and dedupe capabilities.
- `PROGRESS.md:3`, `DECISIONS.md:3` — implemented conflicting-date branch work and its verification limitations.
- `ui/Sources/ChronoframeAppCore/Stores/DeduplicateSessionStore.swift:501` — in-memory review pause/resume; history persistence is separate.
- `ui/Sources/ChronoframeApp/Views/Run/PreviewReviewPanel.swift:293` — per-item date editing.
- `ui/Sources/ChronoframeAppCore/Stores/PhotosImportStore.swift:190` — new staging per import and abandoned-staging purge.
- `ui/Sources/ChronoframeApp/Views/Photos/PhotosImportView.swift:285` — preparation presentation.
- `ui/Sources/ChronoframeApp/Views/Components/OnboardingCard.swift:3` and `ui/Sources/ChronoframeApp/Views/Setup/SetupSectionViews.swift` — existing onboarding/setup; `ui/Sources/ChronoframeApp/Views/Purchase/UnlockSheet.swift` — existing free-batch flow.
- `ui/Sources/ChronoframeCore/DeduplicateModels.swift:81` — existing cross-folder priority substrate; protection is a proposed additional contract.
- `ui/Sources/ChronoframeCore/MediaDateResolver.swift:4` and `ui/Sources/ChronoframeCore/MediaDiscovery.swift:114` — Organize extension allowlist excludes XMP.
- `ui/Sources/ChronoframeApp/Views/RunHistoryView.swift:826` — current artifact-title/path/kind search; `ui/Sources/ChronoframeAppCore/Services/SpotlightIndexer.swift:9` — receipt indexing, not media lookup.
- `ui/Sources/ChronoframeCore/GuardianCapability.swift:12` — disabled feature; `ui/Sources/ChronoframeAppCore/Support/GuardianScheduler.swift:7` — in-app/catch-up scheduling already implemented.
- `docs/remaining-work-plan.md`, `docs/app-review-iap-rejection-2026-10-19.md` — local release evidence limits. The latter records build 508; older build-507 summaries must not be treated as the latest upload evidence.

External primary-source context checked for this review:

- [Apple: remove duplicate photos and videos](https://support.apple.com/en-lamr/guide/photos/pht5a3157c1d/mac) documents existing Photos duplicate merging. This supports the inference that duplicate detection alone is not a sufficient differentiator.
- [PhotoSweeper release notes](https://overmacs.com/?p=releasenotes) document quality scoring, keeper rules and folder comparison. Those are established category capabilities; Chronoframe's opportunity is a trustworthy end-to-end archive, not simply having more analysis controls.
- [Google: download your data](https://support.google.com/accounts/answer/3024190?hl=en-en) documents embedded photo timestamps and secondary JSON for additional metadata. This establishes a format problem, not customer demand or a guarantee that every Takeout date needs repair.
- [Apple: export photos and videos](https://support.apple.com/en-mide/guide/photos/pht6e157c5f/mac) documents original-file and IPTC-as-XMP exports. It does not establish that Chronoframe's PhotoKit seam can export every library field or reconstruct edits.

Representative inspection commands: `rg --files ...`, targeted `sed -n` ranges in the files above, and `rg -n` searches for persistence, staging, supported extensions, folder priorities and Guardian enablement. These confirmed the specific deltas; they did not verify live behavior. An attempted public App Store page fetch was unavailable, so no current publication claim is made.

## Round 3 — independent re-review after NAS v1 (November 7, 2026, later)

Status: **revised proposal**. This round was generated without reading the Round 2 list first, then reconciled against it. It supersedes the "Revised ranked ten" above.

### What changed since the revision above

- NAS v1 is built on `feature/nas-v1` through gate G3 (`docs/plan/nas-v1/FINAL_REPORT.md`). Hardware checks H1–H8 are owner-only and unrun. The branch is not pushed. "First-class NAS archiving" is therefore no longer a greenfield rank-2 bet; it is finishing work with a small, known remainder.
- The final report records that **Deduplicate can still Trash files on a mounted network share** (D-NAS-135) while recoverable SMB Trash is unverified. That is a safety gap, not a roadmap item, and it is fixed regardless of ranking.
- Build 508 is uploaded but not approved; there are still zero public customers. Every slot below is conditional on 508 shipping first. A free download with a $14.99 unlock lives or dies on the first verified batch, which raises the weight of first-run work.
- This branch already implements conflicting-date warnings and an alternative-date action. A Google Takeout adapter now needs a date-hint source and a sidecar rule, not a new review surface.

### Independent top ten before challenge

1. Take NAS v1 public: run H1–H8, close the Deduplicate-on-NAS Trash gap with the NAS workspace's refusal, flip the flag.
2. Dedupe review that survives relaunch.
3. Visible, cancellable, resumable Photos import with bounded staging (shared with NAS P1).
4. **Find and account** — one media-mapping index behind two faces: "where did this photo go" after a run, and "find my file by its original name" across runs. Merges Round 2's #4 and #8.
5. Batch camera-clock correction.
6. Originals plus current edited appearance from Photos (carried from the revision above).
7. Protected folders and keeper preference in Deduplicate.
8. Keep existing XMP companions with organized photos.
9. Validated Guardian launch.
10. Filename templates in Organize and Reorganize (new; the common category request Chronoframe lacks).

### Round 3a — argue against each

| # | Strongest case against | Verdict |
|---|---|---|
| 1 NAS public | It is finishing work, not new value; NAS owners are a minority of a consumer audience; hardware checks are owner-only. | **Keep.** Ninety percent of the cost is sunk, the remainder is bounded, and the Trash gap must close anyway. Cheapest differentiating capability on the list. |
| 2 Persistence | Saved Delete choices go stale when files change. | **Keep.** Restore review state by content identity, never execution authority; changed items re-enter review; Trash stays explicit. |
| 3 Photos import | Checkpoints complicate cancel, cleanup and identity; staging is large and sensitive. | **Keep.** The 501/502 incidents show Photos import is where real failures surface. Checkpoint only complete assets; reuse the verified transfer path. Shares staging work with NAS P1. |
| 4 Find and account | Receipts, Health, artifact search and Finder already exist; an index can grow without bound. | **Keep.** Nothing today answers "where did IMG_1234 go" without opening a receipt. One bounded index serves both questions, so the merge halves the cost of two Round 2 items. Missing evidence stays "unresolved". |
| 5 Clock correction | A wrong offset applied to a wrong selection misfiles thousands of files at once. | **Keep.** Selection, before/after preview, undo, unchanged source metadata. Dead-battery resets and travel time zones are among the most common archive defects. |
| 6 Edited appearance | Expands the originals-only contract; doubles storage for edited assets; dedupe sees two variants of one capture; fidelity across HEIC/HDR/third-party edits needs a test matrix; Photos itself exports edited versions, and that folder can be organized today. | **Remove.** The workaround is native and adequate for this half; the contract change and fidelity matrix are not. Revisit once #3 lands. |
| 7 Protected/keeper | Preference can keep a technically worse image; users may read preference as protection. | **Keep, narrowed.** Ship *protection* first as a planner constraint; *preference* second. Pair and sidecar Keep-wins rules unchanged. |
| 8 XMP companions | Shared RAW/JPEG sidecars have ambiguous ownership; copying a sidecar does not guarantee another app reads it. | **Keep.** Leaving a Lightroom user's ratings and edits behind is silent data loss, not a missing feature. Copy only unambiguous owners; report the rest. |
| 9 Guardian launch | Largest expansion of responsibility in the product; a same-drive mirror is not a backup; restore is safety-critical; one maintainer; no public customer has yet asked for protection. | **Remove as scoped.** The against is stronger for a half that must also ship 508 and certify NAS. Re-enter in a narrower form below. |
| 10 Filename templates | Renames touch pair and sidecar naming in safety-critical paths, change collision and revert behavior, and open a template-syntax tail; demand for *this* product is unknown. | **Remove.** Keep date folders as the identity until a customer asks. |

Three removed. Replacements, drawn from the Round 2 list and the Guardian remainder:

- **Make the first ten minutes feel safe** (Round 2's #5, narrowed). Capacity and access check before a run, including Photos staging; then the existing free verified batch; then show the files that now exist and the undo. No new wizard.
- **Verify my archive** (Guardian scrub-only). Trusted baseline plus read-only scrub, reporting changed, missing and unchanged files with dates. No mirror, no restore, no "safe" score.
- **Rescue an extracted Google Takeout folder** (Round 2's #9, narrowed). Match `name.ext` to its JSON sidecar only when unambiguous, feed `photoTakenTime` into the branch's existing conflicting-date review as a hint, copy the sidecar under the XMP companion rule. No Google login.

### Round 3b — argue against the full ten again

| Rank | Recommendation | Strongest case against | Why it survives |
|---|---|---|---|
| 1 | Take NAS v1 public | Finishing work; minority audience. | Sunk cost, bounded remainder, closes a live safety gap. |
| 2 | Dedupe review persistence | Stale decisions. | Content-identity gating; review state only. |
| 3 | Resumable, bounded Photos import | Checkpoint complexity. | Proven failure site; shares NAS staging work. |
| 4 | Find and account | Overlaps existing surfaces. | Answers the one question they do not; one index, two faces. |
| 5 | First ten minutes | Onboarding exists; estimates go stale. | Zero customers yet; conversion depends on the first verified batch. Extend existing cards, label estimates, recheck at execution. |
| 6 | Batch clock correction | Blast radius. | Preview plus undo; very common defect. |
| 7 | Protected folders, then keeper preference | Confusion between the two. | Protection is a planner constraint and ships alone first. |
| 8 | XMP companions | Ownership ambiguity. | Silent loss otherwise; unambiguous owners only. |
| 9 | Verify my archive (scrub-only Guardian) | Finding damage without a restore path is anxiety without remedy; Health already exists. | It names the exact file and date so Time Machine or a backup can restore it; most of the engine exists; no protection claim is made. Mirror and restore stay flagged off. |
| 10 | Takeout rescue, narrow | Demand unproven for this product; format tail. | External demand is visible in the tool ecosystem around Takeout dates; the branch's conflicting-date review and the XMP rule make the adapter small. First to drop under capacity pressure. |

All ten survive. The argument against each is recorded, not dismissed.

### Reconciliation with the Round 2 list

| Round 2 suggestion | Outcome |
|---|---|
| Save dedupe reviews across restarts | Kept, rank 2 |
| Visible, cancellable, resumable Photos imports | Kept, rank 3 |
| Batch clock correction | Kept, rank 6 |
| Account for every item after a run | Merged into rank 4 |
| First archive feels safe | Kept narrowed, rank 5 (reversed the earlier removal: no customers yet makes first-run the funnel) |
| Keeper and protected folders | Kept, rank 7, protection first |
| XMP companions | Kept, rank 8 |
| Find files by original name | Merged into rank 4 |
| Google Takeout rescue | Kept narrowed, rank 10 |
| Finish Guardian | Narrowed to scrub-only, rank 9; mirror and restore deferred |
| Originals + edited appearance (revision) | Removed this half |
| First-class NAS archiving (revision) | Became rank 1 as "take v1 public"; P1 staging folded into rank 3 |

### Preconditions and standing bar, not slots

- Ship 508. Nothing above is scheduled before App Review approval and the signed sandbox purchase/restore evidence.
- Close D-NAS-135 (Deduplicate Trash on network shares) as a safety fix on the NAS branch before anything else.
- Localize the NAS strings (D-NAS-51, D-NAS-130) and keep VoiceOver coverage of Review and Deduplicate flows as release criteria, not roadmap items.
- Cheap platform delight (Finder Quick Action "Organize with Chronoframe", Dock and window drop targets, Deduplicate and Health Shortcuts intents beside the existing Organize intent) goes in a maintenance bucket, no slot.

### DECISION_LOG additions

- NAS v1's built state and its recorded Trash gap are treated as facts of this checkout, not as evidence that hardware checks pass.
- Guardian's restore and mirror remain deferred until a public customer base exists and signed interruption/external-volume evidence is recorded.
- Edited-appearance import is deferred on the strength of the native Photos export workaround, not because the need is unreal.
- First-run work re-entered because the product has no customers yet; this reverses the revision's removal and is a judgment about the funnel, not new data.

## Round 4 — challenge from external demand evidence (November 10, 2026)

Status: **revised proposal**. Adds one backlog card and reorders the tail. Ranks 1–5 and their plan folders are unchanged.

### Evidence

An r/ApplePhotos thread, "iCloud users: How do you manage your growing Photos library?" (posted 2026-11-04, 117 comments read), plus the listings of the apps it names. This is the first demand evidence in this review that does not come from the owner. Limits: iPhone-first iCloud users, not Mac folder archivists; roughly a dozen comments are developers promoting their own apps; comment counts below are approximate hand tallies.

| Job in the thread | Approx. comments | Existing coverage |
|---|---|---|
| Move photos out of iCloud to a drive, NAS or self-host, then delete from iCloud | 20 | Photos import (ranks 1, 3); no way to see what is already archived |
| Shrink or remove large videos | 8 | None |
| Pick the best of bursts and near-duplicates | 6 | Shipped in Deduplicate |
| Remove screenshots, screen recordings, chat-app saves | 6 | System smart albums are already selectable in Photos import |
| Review in small sessions with saved progress | 6 | Rank 2 |
| Backup that is not iCloud; mirror that handles deletions | 5 | B9 scrub-only; mirror deferred |

### Six candidates, argued against

| Candidate | Strongest case against | Verdict |
|---|---|---|
| A. Show what is already archived in Photos import, select by date range, skip archived assets before export | Needs a durable Photos-asset-to-verified-copy mapping; a stale mapping could show "archived" for a file since moved or lost; users may read the mark as "safe to delete". | **Keep, new card B11.** Repeat offload is the top job in the thread, and today every repeat import re-exports and re-downloads assets that the copy step then skips. Mark only assets whose recorded destination still passes an identity check; otherwise "not confirmed". The app states what is verified and where; it never says a source is safe to erase (Round 2 #4 boundary stands) and never writes to Photos. |
| B. Space report (bytes by year and type, largest first) | PhotoKit has no public pre-export size (D-PIR-05); for folders, Finder and disk tools already answer it. | **Remove.** Not buildable for Photos on the supported API; redundant for folders. |
| C. Junk classes (screenshots, screen recordings, chat saves) | Photos import already lists the system smart albums; folder-side detection is heuristic and can misfile. | **Remove.** An exclude-by-type control folds into B11's selection if it proves cheap. |
| D. "Reviewed through" coverage by month on top of rank 2 | Dedupe groups are not time-sliced; a coverage calendar is a second progress model. | **Remove.** The thread confirms rank 2 as scoped. |
| E. Guardian mirror with a retention folder for deletions | Round 3's gates (signed external-volume and interruption evidence, a public customer base) are unchanged by five comments. | **Remove.** B9 stays scrub-only. Record the thread as demand evidence for when mirror re-enters. |
| F. Video compression, JPEG-to-HEIC transcode, timestamp filename templates | Lossy output conflicts with verified bit-for-bit copies; the category is crowded with $5–10 apps; Round 3 already removed filename templates until a customer asks, and one forum comment is not that. | **Remove.** |

### Revised order

| Rank | Recommendation | Change |
|---|---|---|
| 1–5 | NAS public; dedupe persistence; resumable Photos import; find and account; first ten minutes | Unchanged |
| 6 | **B11 — Already-archived view and date-range selection in Photos import** | New |
| 7 | B6 batch clock correction | Down one |
| 8 | B7 protected folders, then keeper preference | Down one |
| 9 | B8 XMP companions | Down one |
| 10 | B9 verify my archive (scrub-only) | Down one |
| 11 | B10 Takeout rescue, narrow | Down one; still first to drop. The thread is not evidence against it: an Apple Photos forum would not raise Takeout. |

B11 ranks above B6 because it extends the two flows the thread's largest group needs (ranks 3 and 4) and has external evidence; B6–B10 still rest on judgment alone.

### DECISION_LOG additions

- One forum thread is qualitative evidence for which jobs exist, not for their prevalence or willingness to pay.
- B11 depends on plans 3 and 4. Whether the Photos asset identifier is persisted alongside the destination mapping today is unverified and is the first question for its plan.
- No reply was posted to the thread; it is retained as launch-post evidence only.
