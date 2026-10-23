# Shedi design implementation record

Date: October 18, 2026

**Current status:** website delivery is published. App implementation is paused
during review of 2.0 (507). The [updated plan](shedi-inspired-design-plan.md) now
marks the website slices delivered and the interactive simulator cut. W1 (mobile
preview) and W3 (Support) are now published through
[PR #249](https://github.com/Nishith/Chronoframe/pull/249) (`8c6948c`), with successful Pages deployment and live verification. The implementation
and QA record is `.tmp/shedi-website/docs/website-mobile-support-2026-10-18.md`.
W2, public app/offer and capture-build verification, remains pending.

**Priority update:** the owner has submitted the app for review and asked to focus
on the website first. Further app implementation is on hold; the uncommitted app
edits below remain preserved. The owner merged website PR #226 during the QA pass;
Pages deployed it on October 18. Final website fixes are in PR #248 from the
isolated checkout `.tmp/shedi-website` on `codex/shedi-website`. Its review record is
`.tmp/shedi-website/docs/website-design-2026-10-18.md`. The follow-up changes no app
source. The owner subsequently approved early website publication and a temporary
unavailable/mismatched download link because there are no active users or traffic;
the follow-up was merged by the owner after checks. Public app/proof verification stays
outstanding. The original website commit
`2f936e52e80a6c8b54d110132d245717422f075a` supplied the photographic
hero, large preview, responsive inspection, policy corrections and provenance.
Follow-through commits `35397b7` and `676e2ac` in PR #248 finish the browser QA pass,
fix inline-link and enlarged-text accessibility issues, select the recorded
walkthrough fallback, and check proof asset origins/checksums. Commit `c83be21`
records the owner's approval of early website publication. The per-page
record is `.tmp/shedi-website/docs/website-qa-2026-10-18.json`. Public free V2,
production offer verification, matching build-identified screenshots/film and
matching public app proof remain release-dependent. The owner merged #226 during
this QA pass; Pages deployed it on October 18 and the film's actual publication
date is now recorded. #248 merged as `c6546b7` on October 18. No app source was changed by either
website increment.

Review follow-up `d3ed201` validates and fixes PR #248's deployment-gate comment:
Pages now runs `check_site.py --release` before uploading/deploying, and the
website CI job runs four regressions against the actual workflow command. The
held-state case reproduced the gap before the fix; all cases and the hosted
website check pass afterward. The owner's early-publication approval is retained.

The owner confirmed the merge. Pages run `39186449345` completed successfully for
`c6546b715af4db482f468eb24bc842ab9296cad8`. Live checks passed for the homepage,
features, safety, FAQ, support, privacy and 404 pages; the updated proof group and
stylesheet; the owner-approved prelaunch manifest; and a 1,024-byte video range
request. The website follow-up is deployed. Public V2 app/offer and capture-build
verification remain recorded follow-ups under the owner's accepted launch decision.

## Website follow-ups after publication

The live review identified W1 and W3, which the owner then requested together.
Both are implemented below; public-release verification remains a separate follow-up:

- **W1 — published in #249; live-verified:** a CSS crop of the unchanged
  original now opens on the preview panel and timeline. An always-visible HTML
  summary gives planned/copied/review counts, destination and next action before
  the image. Full-size keyboard access and sample/development labels remain.
  Narrow-width, doubled-text, link and keyboard checks pass.
- **W2 — when V2 is public:** refresh/identify app screenshot and film builds,
  record their public-version mapping, and verify the production download and
  unlock/Family Sharing/purchase/restore offer. This is not a publication hold.
- **W3 — published in #249; live-verified:** Support has six topic shortcuts,
  problem-oriented native disclosures, on-site answers and a blank diagnostic
  email template. `quick-start.html` supplies a four-step first-run guide sourced
  from public docs. Deeper GitHub references and `#purchases` remain. Existing
  unpublished `site/guides/` work is preserved.

The desktop entry and recorded walkthrough controls were healthy in this review.
No additional interactive demo or app changes are required by these findings.
This is a fresh visual/DOM review with selected keyboard checks; it does not
repeat the full prior accessibility matrix or establish public app availability.

The owner merged #249 at 04:02:07 UTC on October 19 (October 18 locally) as
`8c6948cb54d504609477083f13c42bd045bba913`. Pages run `39197482632` succeeded.
Live browser navigation confirmed the new homepage summary and stylesheet,
six Support shortcuts, twelve troubleshooting disclosures and four-step
`quick-start.html` guide. W1/W3 are delivered. W2 remains the release-dependent
follow-up; the submitted app and unrelated primary-checkout changes are untouched.

Slice 2 (presentation accuracy) is in progress in the working tree based on `64affe40dec072b84db26267da2f65eee5d45fdc`. This is an initial implementation, not a release-candidate certification or completion of the whole design plan. No release build, implementation commit, publication or owner Go is assigned to these changes. The local Debug app used for captures identifies itself as 2.0 (452), automatically stamped from commit count; it is unrelated to signed release build 507.

## Initial scope

- Preview reassurance promises no destination media added and untouched sources; it no longer claims planning performs no writes. The wording also works after Photos has exported originals into staging.
- Run verification uses `lastPreflight.configuration` while active and the configuration captured in `lastRunCompletion` after completion. Missing evidence gets neutral wording; later Setup edits cannot change the claim. Copy checking is described in the future tense while active and in the past tense only for finalized, successfully copied files.
- Finished, cancelled and failed transfer summaries use finalized summary metrics ahead of the last progress sample. Failed copies and issues remain visible. Zero-copy wording, including its notification and current-focus line, makes no whole-library completeness claim. A 190-copy result stays 190 even if a full preview planned 1,200 and an approved batch contained 200; no unsupported changed/deferred total is inferred.
- Stopping stays active until the execution result returns. The shared announcement planner speaks the same outcome as the hero and suppresses routine progress while stopping. The second progress-announcement path in `NowCopyingCard` is removed to avoid duplicate/premature completion announcements.
- Timeline wording describes the planned transfer distribution, including the possibility of a resumed queue, and uses a neutral fallback for absent evidence.
- Dedupe photo descriptions use content identity, confirmed visual-match evidence, or possible similarity requiring review. Missing, negative or non-finite Vision distance cannot produce a percentage or confirmation. A non-finite distance previously crashed the percentage formatter; a regression now covers it.
- Perceptual-video wording includes sample agreement, duration difference and review-only limits. Sample agreement is not described as identity of the whole recording.
- Visible confidence vocabulary is **Strong / Check / Careful**, shared by filters and badges. Bulk actions, the rotor, tip and undo action use the corresponding wording. VoiceOver retains **high / medium / low** confidence.
- Dedupe reassurance describes Trash-only mutation and receipt-backed restoration conditional on content identity, without promising a full restore.
- Public app guidance tracks the renamed bulk action. The website and ongoing marketing work were outside this initial app-accuracy increment; the separate website delivery is recorded above.

## Presentation contract implemented here

| Value | Evidence / observation owner | Fallback |
|---|---|---|
| Copy verification | Captured preflight/completion configuration; `CurrentRunView` observes `RunSessionStore` | Unknown status is explicit; no completed verification claim without a finalized summary and positive copied count |
| Stopping | Observed `RunSessionStore.isCancelling` while status remains running | No terminal treatment before the final event |
| Actual copies / failed copies / already present | `RunSummary.metrics`, with session metrics only when no summary exists | Never infer all-library completeness or missing batch totals |
| Timeline | `RunMetrics.dateHistogram`, which describes planned work | No planned distribution available; no assertion that the source has no dated files |
| Photo-match explanation | `MatchReason.kind` and finite, non-negative Vision distance recorded by clustering | Possible visual similarity; review required |
| Video-match explanation | `VideoMatchEvidence` | Photo weak-evidence fallback when no confirming evidence exists |
| Dedupe mutation and recovery | Existing reviewed/prepared plan and receipt behavior | No changes to eligibility, pairing, execution, receipts or locks |

## Validation

The first focused run passed 104 tests across `RunWorkspaceModelTests`, `RunAnnouncementPlannerTests`, `MatchReasonFormatterBranchTests`, `SetupScreenModelTests`, `DeduplicateStatusViewTests`, `DeduplicateAccessibilityTextTests` and `TipsTests`. Tagged wording assertions cover invariants 3, 6, 7, 10, 12 and 20. Regression tests reproduced the old missing-confirmation strings, non-finite-distance crash, cancellation counts and whole-library zero-copy claims before correction.

The local Xcode Debug build passed outside the restricted execution sandbox (the sandbox prevented Swift macro plugins from running). The final full SwiftPM lane ran **1,766 tests in 31 fresh-process shards**, all passing; the meaningful-coverage gate passed at **95.82% (17,304/18,059 lines)**. This is the script's selected domain-code metric, not project-wide coverage. The first sandboxed coverage attempt failed macOS package classification in `ChronoframeCoreMediaDiscoveryTests.testWalkEntriesSkipsSymbolicLinksAndPackages`; the unchanged test passed outside the sandbox, as did the subsequent full lane.

The invariant-tag, detail-title, animation, UI-test membership, Photos read-only and whitespace guards pass. The app-layer guard was invoked but compares committed history only; it reported no app changes on this documentation branch. The working diff independently contains app changes alongside eight SwiftPM test files and the existing UI-test source.

The selected Xcode UI lane compiled but could not run: `ChronoframeUITests-Runner` timed out while enabling automation mode, before any test began. The timeline interaction, compact/wide dedupe interaction, 10,000-record receipt check and accessibility audit therefore remain **unverified**. Result bundle: `.tmp/ShediPresentationTests3.xcresult`; log: `.tmp/shedi-ui-tests.log`. Screenshot assertions/attachments were added to the existing UI-test source for the next working automation session. No UI-test success or accessibility certification is claimed.

Direct app-owned fixture checks used the same local Debug app with `CHRONOFRAME_UI_TEST_SCENARIO`, mock data and no user-media mutations. Captures were inspected in dark appearance at normal text size; their new wording is readable, the weak-evidence row fits, and the footer actions remain within the captured windows. They do not establish keyboard/VoiceOver audit results or the full state matrix. Media thumbnails are intentionally unavailable in these fake-path fixtures. Local proof paths:

| Scenario | Content size | Capture |
|---|---|---|
| `runPreviewReview` | 1360×920 | `.tmp/shedi-captures/organize-preview-dark-1360x920.png` |
| `deduplicateReviewWide` | 1180×820 | `.tmp/shedi-captures/dedupe-wide-dark-1180x820.png` |
| `deduplicateReviewCompact` | 900×700 | `.tmp/shedi-captures/dedupe-compact-dark-900x700.png` |

The captures are internal evidence from an uncommitted working tree, not public product-proof assets. The subsequent final-source `xcodebuild build-for-testing` passed, including compilation of the updated UI-test assertions; it is logged in `.tmp/shedi-final-xcode-build.log`. Full Swift logs: `.tmp/shedi-coverage.log`.

## Remaining app work and decisions — paused

- **Owner decision remains open:** `RunTimelineView.barFills` still uses the previously approved aggregate fill approximation. This increment changes its scope wording only. Removing the approximation still needs the before/after captures and explicit owner decision specified by the plan; the accuracy slice is not declared complete while that decision is open.
- Finish Slice 1's full presentation data contract and deterministic fixture matrix, including Photos/watched source identity, approved versus full-preview scope, resumed work, unavailable access and stale evidence. Current focused app-layer regressions do not replace that matrix.
- Complete the remaining minimum/default/wide, light appearance, larger-text and reduced-sensory checks beyond the three dark captures above. Full fixture-based visual acceptance and owner/participant layout selection are outstanding.
- Keep broader Organize/Setup hierarchy, dedupe/footer layout and shared app polish separate. No new app type/spacing/surface rule is adopted by this accuracy increment. Website artwork and the recorded walkthrough have already shipped separately.
- New copy currently falls back to English where translations have not been supplied. Retained old localization catalog entries are not used by the renamed bulk/undo actions. Translation review remains before release.
- Website PRs #226/#248/#249 are merged and deployed; the former public-launch merge hold is superseded by the owner's approval. W1/W3 are published and live-verified; W2 remains open, separate from these paused app changes.
