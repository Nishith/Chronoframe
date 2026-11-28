# Chronoframe: next-half product recommendations

> **Status (2026-11-21): proposal record, partly executed. No product or design approval is implied by this document.** Prepared 2026-11-07, revised through Round 4 (2026-11-10). The Round 3 ranking drives `docs/plan/next-half/` (plan folders `nas-public`, `dedupe-persistence`, `photos-import-resume`, `clear-path`, `find-and-account`, `first-ten-minutes`). Shortened 2026-11-21: Round 1, Round 2 and the edits/NAS follow-up (superseded by Round 3), the capability baseline table (stale) and the per-recommendation write-ups were removed; full text is in git history (`git log -- docs/next-half-product-review-2026-11-07.md`).
>
> **What became of it (verified against `git log` and open PRs on 2026-11-21):**
>
> | Rank | Recommendation | State |
> |---|---|---|
> | 1 | Take NAS v1 public | Built and merged behind the disabled `NASCapability.isEnabled` flag (#266, #275). Not public: owner hardware checks H1 to H8 and the flag flip remain. Deduplicate on network volumes is refused by the network-volume refusals in #266 (closes the D-NAS-135 gap; the refusal is covered by `NASDeduplicateFolderRefusal`). |
> | 2 | Dedupe review survives relaunch | Done: #267 (UI-test isolation #276). |
> | 3 | Visible, cancellable, resumable Photos import | Done in part: #268 "Stop and resume a Photos import", #270. Whether bounded staging and checkpoint-by-complete-asset are fully delivered is unverified; see `docs/plan/photos-import-resume/PROGRESS.md`. |
> | 4 | Find and account (item-level reconciliation plus original-name lookup) | Not started on main (plan folder only). |
> | 5 | First ten minutes (preflight, free batch, proof) | Not delivered as scoped; only wording changes landed (#278). |
> | 6 (B11) | Already-archived view and date-range selection in Photos import | Not started. |
> | 7 to 11 | Batch clock correction, protected folders then keeper preference, XMP companions, verify-my-archive (scrub-only Guardian), Takeout rescue | Not started. The conflicting-date review these build on shipped: #261, #272, #273. |
>
> Preconditions in the review are met or changed: build 508 is superseded; V2 is public and Free with a $14.99 unlock since 2026-10-22 (see `docs/APP_STORE_RELEASE.md`). Open PRs right now (#282 run-outcome accuracy, #283 marketing tooling, #284 German UI fit) are not part of this list.

## Product judgment

Make Chronoframe the easiest way to finish a trustworthy, usable photo archive. The strongest delight is relief: my work survived, my dates are right, my photos are accounted for, and I can find them again. The product already has substantial organizing, deduplication and recovery machinery; invest in completing customer jobs across it before adding new ways to analyze pictures.

## DECISION_LOG: review assumptions (still apply)

- "Next half" means roughly November 2026 to April 2027. One-maintainer constraint: the ranked list is an ordered investment list, not a promise that every item fits.
- Primary customer: a Mac owner consolidating years of family photos and videos from folders, drives and Photos. A professional digital asset manager is a different product.
- Recommendations preserve read-only Organize sources and Apple Photos, verified copies, review gates, Trash-only dedupe, pair/sidecar retention and content-safe undo.
- Demand and willingness to pay are hypotheses. No interviews, conversion funnel or support corpus was supplied; source inspection shows implementation gaps, not prevalence.
- Keep the no-analytics, no-upload promise. Measure through recruited usability sessions and local QA fixtures; telemetry would need a separate privacy decision.
- Keep an idea only when its bounded deliverable beats its strongest objection and opportunity cost. A tie goes to deferral. This is product judgment, not proof.

## Ranking after Round 4 (current order)

| Rank | Recommendation | Why it survived the strongest objection |
|---|---|---|
| 1 | Take NAS v1 public | Mostly sunk cost, bounded remainder, closes the Deduplicate-on-network-share Trash gap regardless. |
| 2 | Dedupe review persistence | Restore review state by content identity, never execution authority; changed items re-enter review; Trash stays explicit. |
| 3 | Resumable, bounded Photos import | The 501/502 incidents show Photos import is where real failures surface. Checkpoint only complete assets; reuse the verified transfer path. |
| 4 | Find and account: one media-mapping index, two faces ("where did this photo go", "find by original name") | Nothing today answers "where did IMG_1234 go" without opening a receipt. Missing evidence stays "unresolved". |
| 5 | First ten minutes: capacity and access preflight, the existing free verified batch, show the result and undo | No customers yet, so conversion depends on the first verified batch. Extend existing cards; no new wizard; label estimates and recheck at execution. |
| 6 | B11: already-archived view and date-range selection in Photos import (Round 4) | Repeat offload is the top job in the r/ApplePhotos evidence. Mark only assets whose recorded destination still passes an identity check, otherwise "not confirmed"; never imply "safe to delete". |
| 7 | B6: batch camera-clock correction | Explicit selection, before/after preview, undo, relative-time-preserving shifts; source metadata unchanged. |
| 8 | B7: protected folders first (a planner constraint), keeper preference second | Pair and sidecar Keep-wins rules unchanged. Do not let preference read as protection. |
| 9 | B8: keep existing XMP companions with organized photos | Leaving a Lightroom user's ratings and edits behind is silent data loss. Copy only unambiguous owners; report the rest. |
| 10 | B9: verify my archive (Guardian scrub-only) | Names the exact changed or missing file and date so a backup can restore it; no mirror, restore or "safe" score. |
| 11 | B10: Takeout rescue, narrow | Match `name.ext` to its JSON only when unambiguous, feed `photoTakenTime` into the conflicting-date review as a hint. First to drop under capacity pressure. |

Decided against, with reasons that still hold:
- Edited-appearance import from Photos: expands the originals-only contract and storage; Photos' own export of edited versions is an adequate workaround this half. Revisit after rank 3.
- Guardian mirror and restore: largest expansion of responsibility; a same-drive mirror is not a backup. Deferred until a public customer base exists and signed interruption and external-volume evidence is recorded. The r/ApplePhotos thread is demand evidence for when it re-enters.
- Filename templates, semantic search, unattended watched-folder import, multi-source migration workspace, metadata-complete Photos export, space report, junk classes, "reviewed through" calendar, video compression and HEIC transcode: removed for scope, safety or overlap with existing capability (the Round 1/3/4 tables in git history carry each argument).

Standing bar, not roadmap slots: close D-NAS-135 (done by #266), localize NAS strings (D-NAS-51, D-NAS-130) and keep VoiceOver coverage of Review and Deduplicate flows as release criteria, and keep cheap platform delight (Finder Quick Action, drop targets, more Shortcuts intents) in a maintenance bucket.

## Round 4 evidence and limits

An r/ApplePhotos thread, "iCloud users: How do you manage your growing Photos library?" (posted 2026-11-04, 117 comments read), plus the listings of the apps it names. Limits: iPhone-first iCloud users, not Mac folder archivists; roughly a dozen comments are developers promoting their own apps; tallies are approximate hand counts. Top jobs: move photos out of iCloud to a drive, NAS or self-host (about 20 comments); shrink large videos (8); pick best of bursts (6, shipped in Deduplicate); remove screenshots and chat saves (6, system smart albums already selectable); review in small sessions (6, rank 2); non-iCloud backup (5). This is qualitative evidence for which jobs exist, not for prevalence or willingness to pay. No reply was posted to the thread. B11 depends on plans 3 and 4; whether the Photos asset identifier is persisted alongside the destination mapping is unverified.

## Evidence and research limits (original review)

Static review only: no build, runtime session, customer interview or new signed verification. Repository anchors used (paths from the repo root; line numbers were valid on 2026-11-07 and may have moved): `ui/Sources/ChronoframeAppCore/Stores/DeduplicateSessionStore.swift` (review pause/resume), `PhotosImportStore.swift` (staging and abandoned-staging purge), `ui/Sources/ChronoframeCore/DeduplicateModels.swift` (cross-folder priority substrate), `MediaDateResolver.swift` and `MediaDiscovery.swift` (the Organize extension allowlist excludes XMP), `ui/Sources/ChronoframeApp/Views/RunHistoryView.swift` (artifact-title search only), `SpotlightIndexer.swift` (receipt indexing, not media lookup), `GuardianCapability.swift` (disabled), `GuardianScheduler.swift`.

External primary sources checked:
- [Apple: remove duplicate photos and videos](https://support.apple.com/en-lamr/guide/photos/pht5a3157c1d/mac): Photos already merges duplicates, so duplicate detection alone is not a differentiator.
- [PhotoSweeper release notes](https://overmacs.com/?p=releasenotes): quality scoring, keeper rules and folder comparison are established category capabilities; the opportunity is a trustworthy end-to-end archive.
- [Google: download your data](https://support.google.com/accounts/answer/3024190?hl=en-en): embedded photo timestamps plus secondary JSON; a format problem, not proof of demand.
- [Apple: export photos and videos](https://support.apple.com/en-mide/guide/photos/pht6e157c5f/mac): original-file and IPTC-as-XMP exports; does not show Chronoframe's PhotoKit seam can export every field or reconstruct edits.
