# Shedi-Inspired Design Plan

Date: October 18, 2026

Status: Website work is published through PRs #226, #248 and #249. W1 mobile preview and W3 Support improvements are merged and deployed (`8c6948c`; Pages run `39197482632` succeeded). Live homepage, Support and first-run guide were verified. W2 public app/offer proof remains pending. The captioned recorded walkthrough is the selected delivery; the interactive simulator is cut. App work remains paused during review of 2.0 (507), with earlier uncommitted accuracy changes preserved. See the [implementation record](shedi-design-implementation.md) and [live website review](website-follow-up-review-2026-10-18.md).

## Outcome

Make Chronoframe easier to understand at first glance and more reassuring at each decision: one clear result, visible evidence, a predictable next action, and a distinctive photographic identity.

The reference is [Shedi](https://shedi.app/), inspected in this conversation on October 18. Useful observations include its large result metric, short explanations beside categories, persistent selection/action summary, expressive website artwork, prominent product screenshot, and browser demo entry point. Its app presentation was inspected through the website; this was not a hands-on audit of the installed Shedi app.

Chronoframe keeps its Meridian design language: warm paper/graphite, amber waypoint, indigo actions, SF typography, native Mac controls, and generous media surfaces. Expressive photographic artwork belongs on the website. In the app, depth comes from hierarchy, semantic surfaces, spacing, and hairlines. The earlier suggestion of decorative app gradients is narrowed to match the existing design contract.

## Existing foundations to refine

The current source already implements much of the underlying interaction. Checked-in marketing screenshots can lag the app; capture the running app before designing.

| Useful idea | Current foundation | Planned improvement |
|---|---|---|
| One dominant result | `RunHeroSection`, `RunWorkspaceModel`, outcome summary | Lead with the most useful state-specific count; reduce competing summaries. |
| A visual explanation of the result | `RunTimelineView`, `InteractiveTimelineView`, contact sheet, preview review rows | Compare planned date distribution, destination examples and attention-led evidence; connect summaries to existing review views. |
| Evidence beside decisions | `MatchReasonFormatter`, cluster list/detail, warnings | Put a short reason next to each recommendation, with detail available on demand. |
| Visible reassurance | `TrustProofModel`, `TrustProofSurface`, run copy | Consolidate repeated promises into precise statements appropriate to the actual state. |
| Persistent selection and action | `DeduplicateView.commitFooter`, `reviewedDeletionPlan()` | Improve hierarchy and compactness while keeping plan/executor parity. |
| Approachable setup | Source/destination steps, drop support, contact sheet | Emphasize folder roles and the next step; reduce repetitive readiness information. |
| Consistent craft | `DesignTokens`, shared panels, motion/accessibility helpers | Standardize spacing, type hierarchy, focus and surface treatment on touched screens. |
| An expressive product website | Existing hero, app screenshots, safety/features pages | Shorter introduction, one large proof image, original photographic artwork, clearer free-download offer. |
| A browser demonstration | Existing marketing recordings and provenance notes | Start with one accessible, explicitly labeled Organize sample journey; evaluate dedupe separately. |

## Boundaries

- Preserve all `AGENTS.md` safety invariants, planner decisions, locks, verification, receipts, recovery, permissions, and trial enforcement. This is a presentation project.
- "Presentation only" does not exempt this plan from the invariant procedure in `CLAUDE.md`. Much of the copy it rewrites is the user-facing statement of an invariant, so each phase below names the `AGENTS.md` invariant numbers its wording depends on, and every one of them needs a test tagged `// AGENTS-INVARIANT: N` that asserts the new wording and fails before the change. `script/check_agents_invariants_have_tests.sh` cannot be the evidence that this plan preserved them: it only proves each invariant bullet has at least one tagged test, every bullet already does, and it therefore passes whether or not the rewritten strings are covered at all.
- Keep organizing, deduplicating, and reverting distinguishable. A source-original promise must not imply dedupe never changes the selected library.
- Keep native navigation, keyboard shortcuts, inspectors, large comparison images, folder access, and preview/consent steps. Preserve existing accessibility identifiers.
- No matching-threshold changes, automatic imports, broader automatic acceptance, new media indexing, or new telemetry.
- Do not adopt Shedi's cleaning metaphor, teal identity, mascot, hands/bubbles artwork, purchase urgency, or unconditional claims of safety.
- Bytes moved to Trash are not necessarily immediately available disk space. Label selected file size accurately; do not celebrate it as space already freed.
- Do not rebuild the completed historical redesign or expand this into a redesign of every workspace. Photos, Sources, Guardian and History receive shared-component regression checks; redesign their layouts only if a concrete dependency requires it.

## Commitment levels

These are the original commitment levels. The website was subsequently prioritized
and published; current status is recorded in the delivery table and Phases 4–5.

This plan is larger than the capacity available to it. Build 507 is in App Review with open gates in [remaining release work](remaining-work-plan.md), the work is owned by one developer, and independent completion boundaries are not a priority order. So the slices carry explicit commitment levels, and the plan does not fail if the lower ones are never built.

- **Committed — Slice 2, presentation accuracy.** It corrects statements the app currently makes that are untrue, inside the existing layout. It needs no visual selection, no task walkthrough, no fixture matrix and no website change: the specific defects named in Phases 1 and 2 are each reproducible from the current source. If nothing else here is ever built, this still should be. One item inside it — the `barFills` timeline reversal in Phase 1 — changes an approved design decision rather than fixing an untrue statement, so it ships with the slice only once the owner signs off on that reversal; the rest of the slice does not wait for it.
- **Next, if capacity allows — Slices 1, 4 and 6.** The evidence specification and fixtures, Deduplicate evidence wording, and the website offer correction. Each is self-contained, and each has a reason to exist that predates this plan.
- **Opportunistic — Slices 3, 5, 7 and 8.** The Organize hierarchy rework, cross-screen consistency pass, photographic artwork and browser demo. These are improvements rather than corrections. They are expected to slip, and any of them can be dropped without the rest becoming incoherent.

Prioritize accurate evidence and state presentation, then validate the preview hierarchy. Artwork and demo work do not hold up a completed app slice.

## Phase 0 — Establish the visual target and state contract

**Deliverables**

1. Capture the current app in Setup, completed preview, active transfer, stopping, partial/failure, finished, dedupe review and receipt states. Extend the app-owned fixture seam for missing states as specified below; capture the website at desktop and mobile widths.
2. Record the real information hierarchy and duplication. Complete the presentation data contract below: for each headline, count, reassurance and action, name the authoritative input, observation owner, unknown/stale fallback and expected visible/spoken output. Include preview, transfer, verification off, completion, partial completion, stopping, cancellation, failure, unavailable folders and stale preview.
3. Produce three screenshot-grounded Organize preview directions for visual selection: timeline-led, destination-layout-led and attention-led. All use the existing palette, the same realistic fixture and existing controls. Include a representative source → planned destination example from existing review data. Compare hierarchy, density and evidence placement before selecting a layout.
4. Compare the current preview and each direction with the same short task walkthrough. The method is defined here and nowhere else; there is no separate design-process document to defer to. Against a static screenshot, with no narration, ask each participant: how many files are planned, where will they go, which date needs attention, and what action starts copying. Record each answer, whether it was correct, visible hesitation and any assistance given. Target five participants who have not seen the app, recruited from people the owner can ask directly. Three is the floor; below three, the result is the owner's own judgement and must be recorded as that rather than reported as comprehension evidence. A direction passes when every participant answers all four questions correctly unaided. If more than one passes, select on visual quality. If none passes, the specification is wrong and the work returns to deliverable 2 instead of proceeding to a layout.
5. Establish adopted type/spacing/surface rules in `DESIGN_SYSTEM.md`, using actual `DesignTokens.swift` values where documentation has drifted. Carry the rules into separate dedupe and website mockups when those slices begin; their delivery does not depend on shipping the Organize layout first.

Presentation accuracy fixes may use the existing layout before visual selection. Production hierarchy and styling changes wait for the selected direction.

**Presentation data contract**

`RunWorkspaceContext` currently has no explicit verification-mode, stopping or import-origin fields. Plan the small app-layer wiring needed to supply these, using existing run/import evidence; do not infer them from a generic status or introduce engine behavior changes.

| UI value or decision | Authoritative evidence | Fallback and transition rule |
|---|---|---|
| Preview headline and secondary counts | Planner metrics and the matching preview-review artifact/summary | Name the scope as planned files. Do not sum overlapping categories or show unloaded review data as zero issues. Mark stale evidence and require rebuilding where already required. |
| Source/destination identity and display name | Captured run configuration/resolved roots plus Photos or watched-import context | Show the user's source identity, not an internal Photos staging path. Setup edits cannot retarget or relabel the captured run. Missing access explains reconnection. |
| Approved scope | Confirmed free-batch selection or prepared dedupe plan, as applicable | Distinguish full-preview scope from the approved subset. Keep the existing re-plan and identity checks; selection counts are not completed counts. |
| Progress and stopping | Observed `RunSessionStore` phase, metrics and `isCancelling` | Show an unknown denominator when necessary. Keep “Stopping…” until the engine supplies its terminal outcome; do not publish a terminal result from the last progress sample. |
| Completed/partial outcome | Finalized `RunSummary.metrics`, run completion record and actual receipt status | Show actual copied/failed/skipped counts. A zero-copy batch whose inputs changed is not proof the whole destination is up to date. |
| Verification reassurance | Effective verification setting captured for that run, combined with its finalized copy result | During work say copies will be checked. Claim completed verification only for copies supported by that result; unknown evidence gets neutral wording. Changing Setup afterward cannot change the claim. |
| Dedupe action and recovery | Reviewed/prepared `DeduplicationPlan`, finalized commit summary and receipt eligibility | Footer and confirmation use the relevant plan snapshot; outcomes use actual results. No inferred restore guarantee or view-local mutation calculation. |

Include a concrete free-batch case: a full preview plans 1,200 files, the user approves a 200-file batch within their remaining allowance, and 1,000 are deferred. If 10 approved files change or vanish before execution and 190 copy successfully, the terminal result and receipt show 190 actual copies. Do not imply all 1,200 were organized or silently acknowledge the excluded files. Display a changed/deferred detail only when existing evidence supports its count; otherwise explain the limitation without inventing a total.

**Deterministic fixture matrix**

Extend `UITestScenario`/`UITestAppStateFactory` or focused app-layer fixtures as appropriate; the existing single Organize preview scenario does not supply all these states. Record each fixture's stable name, inputs, expected headline/counts/action/warnings, spoken output and screenshot paths. Names below describe required coverage, not scenarios that already exist.

| Fixture group | Required evidence/assertions |
|---|---|
| Setup empty/ready; preview mixed media | Folder roles, file/resource units, planned destination example, next action and overlapping attention counts are understandable. |
| Preview all-unknown/long date range; unavailable thumbnails | Unknown dates stay inspectable; months and labels fit or have an accessible bounded fallback; absent thumbnails do not hide file evidence or block review. |
| Stale preview/unavailable folder | Correct rebuild or reconnect action; no apparently ready action based on stale or missing evidence. |
| Active transfer with verification on/off | Correct phase and denominator; promised versus completed verification remain distinct; later Setup edits do not change the run's meaning. |
| Stopping/partial/failed/cancelled | No premature terminal result; actual outcome, partial destination changes and source protection are visible and spoken consistently. |
| Zero-copy/resumed/free-batch | No false whole-library completion; full preview, approved subset, remaining queue and actual copies retain their proper scope. Include the 1,200/200/190 example above. |
| Photos/watched import | User-facing source identity and pinned destination survive unrelated Setup edits; Photos staging is not presented as the user's library. |
| Dedupe exact/confirmed similar/weak/video; pairs/sidecars | Evidence wording, automatic eligibility, Keep-wins protection and reviewed-plan totals agree without relying on color. |
| Large receipt/large dedupe selection | Reuse the existing 10,000-record receipt regression; shared changes preserve bounded rows, dismissal and responsive selection updates. |

Use injected entitlement/allowance data for metered states. Keep these fixtures deterministic, outside `MAS_BUILD`, and independent of an App Store account. Run relevant app captures at 900×700 minimum, 1180×820 default and a recorded wide size; record appearance, text size and accessibility settings with each capture.

**Acceptance**

- The task walkthrough records whether users can identify the planned count, output location, attention item and copying action without assistance, compared with the current preview. Remaining ambiguity has an explicit disposition before layout selection.
- Preview counts, selected counts, actual completed counts and estimated counts are explicitly distinguished.
- Every proposed claim/action has a named input and fallback, and every fixture has expected visible/spoken output rather than only a screenshot.
- The target works at 900×700 and 1180×820, in light/dark appearance and with larger text. No blanket increase in font sizes or radii is required.

**Primary files:** `DesignTokens.swift`, `SharedViews.swift`, `RunWorkspaceModel.swift`, `SetupScreenModel.swift`, `App/UITesting/UITestScenario.swift`, `UITestAppStateFactory.swift`, `docs/DESIGN_SYSTEM.md` and focused presentation tests.

## Phase 1 — Organize result hierarchy and setup

**Preview**

- Replace the generic leading status with an outcome-led heading such as “1,248 files planned for copying.” Use “files” when resources include photos, videos or paired halves; use a narrower media noun only when the data supports it.
- Beneath it, show compact counts for new copies, already present items and items needing attention. These are not necessarily mutually exclusive categories: use a segmented breakdown only if the underlying groups form a disjoint partition of a named total.
- Use the evidence hierarchy selected in Phase 0. Show a representative source → planned destination path from existing review rows and allow inspecting its date decision. Where existing filters support it, make attention counts open the relevant review view. Preserve unknown-date and override handling; label paths as planned because execution revalidation and collisions can change the final result.
- Label the timeline as the date distribution of planned transfers. Its histogram is built from planned transfers, not the entire source library; resumed runs may reconstruct only queued work. Use the scope actually available and provide a neutral unavailable state when evidence is absent.
- Keep one visually dominant next action. Stale plans must still require rebuilding; counts must not imply that a pending execution re-plan is already final.
- Show the pinned source and destination clearly, including Photos and watched-import contexts, without exposing implementation details.

**Setup**

- Keep a readable source/destination form with the contact sheet absorbing available width.
- Reduce repeated “Ready” badges and repeated preview buttons. Retain status information that changes what the user can do.
- Keep the first-use drop/choose-folder invitation short and dismissible. Never imply that folder selection begins copying.

**Progress and outcomes**

- During execution, emphasize actual progress and current phase; show a denominator only when known. Do not animate counters or timelines ahead of reported work.
- Remove the current `RunTimelineView.barFills` inference that distributes global `copiedCount` across months from left to right and forces bars full for terminal success states. Aggregate copies do not establish per-month completion. This reverses a deliberate decision from the shipped redesign — [the execution record](redesign-execution-state.md) describes that timeline as "driven by copied/planned ratio" — so it is the owner's call rather than a defect cleanup, and it should be presented with before/after captures. Keep the chart as a planned distribution and show aggregate progress separately; per-month completion is deferred unless authoritative evidence already supports it without new engine instrumentation. Histogram selection/highlighting must not look like verified completion.
- While cancelling, retain “Stopping…” until receipt finalization returns the actual outcome.
- After completion, lead with actual copied count, keep issues/partial outcomes visible, and offer the appropriate destination/history action. Avoid a generic success treatment when work only partially completed.

**Invariants touched:** 3 and 7 (copy verification defaults on; written files are re-hashed and a bad copy is removed) for every verification claim, and 10 (an aborted run makes clear source files were left untouched) for the preview, stopping, partial and failed copy. Numbers are 1-indexed bullet positions under `## Safety Invariants` in `AGENTS.md`, which is how `script/check_agents_invariants_have_tests.sh` resolves a tag; count the bullets rather than trusting a grep line number.

The organize preview reassurance in `SharedViews.swift` currently tells the user "No files are modified or written." That is false: planning writes `dry_run_report_*.csv`, `preview_review_*.jsonl` and cache rows. Correct it to promise no media added to the destination and no change to source files, without claiming zero disk writes. Check the existing coverage before assuming a guard protects this: no test anywhere asserts that preview string; invariant 10's single tagged test (`UserFacingErrorMessageTests`) asserts only the error-path wording; and `RunAnnouncementPlannerTests` does assert the spoken failure and cancellation strings but carries no invariant tag at all, so rewording them trips nothing. Tag what you change.

**Acceptance:** default and minimum-size layouts preserve the selected evidence surface and primary action; no duplicated dominant action; stale preview, zero-copy, free-batch, resumed, partial and cancelled runs satisfy the fixture contract. Timeline labels and rendering cannot imply unsupported month-level completion or whole-source coverage. Existing execution and consent behavior remains intact.

**Primary files:** `Views/Setup/SetupView.swift`, `SetupSectionViews.swift`, `SetupScreenModel.swift`, `Views/Run/CurrentRunView.swift`, `RunSectionViews.swift`, `RunWorkspaceModel.swift`, `RunTimelineView.swift`.

## Phase 2 — Evidence and selection in Deduplicate

- Keep the comparison images dominant. Use a short, persistent match explanation near the group or recommendation, following the evidence contract below. Burst/variant descriptions and keeper-quality factors add context; they do not prove identical content.
- Review whether the current “Safe” label implies a deletion guarantee. Select wording that describes recommendation confidence without promising equivalence or recoverability, then update badges, filters, bulk actions, help and spoken labels together. Confidence wording must never substitute for `isAutomaticCommitEligible`; keep eligibility and matching behavior unchanged. “Safe” has no single source of truth: `ClusterListPane` and `MatchReasonFormatter` each return it independently, and a third copy is hard-coded in the `ClusterListPane` accessibility rotor (“Safe Matches”). Change all three together, or consolidate them first and then change one.
- `DeduplicateAccessibilityText` deliberately speaks a “high / medium / low” confidence vocabulary instead of the visible “Safe / Check / Risky” labels, and says so in the file. Preserve that divergence. Updating spoken labels “together” means keeping the spoken wording accurate to the same evidence, not unifying the two vocabularies.
- Replace unexplained photo similarity percentages with concrete evidence wording. `MatchReasonFormatter.similarityPercentage` currently displays `(1 − averageVisionDistance) × 100`; that transformation is not a calibrated probability of duplication or safe deletion. Do not promote it as one or substitute an invented percentage for missing evidence. It also has a live defect to remove in the same change: `ClusterAnnotator` leaves `averageVisionDistance` nil whenever a cluster has no Vision distances, so `similarityPercentage` returns `"~"` and the UI renders “~ visually similar” and “~ similar burst” — in precisely the dHash-only weak-match state invariant 10 governs. A nil distance means there is no confirmation to describe, not an unknown number to print.
- Expose keeper reasons and pair/sidecar protection consequences near the decision. Long warnings may expand, but decision-changing warnings remain visible without hover.
- Refine the existing footer into a stable summary of reviewed-plan scope, selected file count/bytes and “Move to Trash.” Keep secondary settings and bulk-review controls visually secondary and keyboard reachable.
- Derive mutation counts from the existing reviewed/prepared plan, including partner files and sidecars. If those are included in the count, explain the inclusion without displaying a conflicting second total.
- Show potential candidate size separately from selected mutation size if both are useful. Zero selected files is a valid, clear state, not an invitation to auto-select weak matches.
- Keep the confirmation, free-allowance flow, and current prepared-plan handling intact. Preserve the Trash/capacity explanation and route completion to the actual receipt/history flow.

| Evidence available | Required wording and limits |
|---|---|
| Exact content identity | “Identical file content.” Reserve exact/identical wording for content-identity evidence. |
| Valid Vision confirmation | Describe a confirmed visual match while making clear the files may differ. Do not imply byte identity or a probability that deletion is safe. |
| Weak similarity without valid confirmation | Describe possible visual similarity and the need for review. dHash-only evidence remains review-only with no automatic deletions. |
| Sampled-video agreement | State agreeing/usable sample frames and duration difference from `VideoMatchEvidence`. State review-only status; sampled agreement does not prove the entire recording is identical. |

**Invariants touched:** 6 (dHash-only similarity is never enough for automatic deletion; non-exact weak matches stay review-only with zero preselected deletions), 12 (Trash only; no hard delete), 14 (pair-as-unit Keep-wins, and sidecars travel with their parent) and 20 (dedupe revert restores a Trash item only while it still hashes to the recorded identity). Each wording change in the table below restates one of these, so each needs a test tagged with that invariant asserting the new wording.

**Acceptance:** footer, confirmation and committed scope agree; evidence-specific visible/spoken wording is covered by formatter tests, including missing confirmation; no uncalibrated probability or unconditional safety claim is shown. Unreviewed weak matches and perceptual videos contribute zero automatic deletions; Keep-wins units and sidecars produce honest totals. Short windows retain useful image space and an accessible action bar.

**Primary files:** `DeduplicateView.swift`, `ClusterListPane.swift`, `ClusterDetailPane.swift`, `MatchReasonFormatter.swift`, `DeduplicateAccessibilityText.swift`, `DeduplicateStatusView.swift`. Reuse `DeduplicateSessionStore` plan accessors; do not introduce a parallel mutation calculation in views.

## Phase 3 — Reassurance and shared visual polish

Apply these rules as Phases 1 and 2 land; complete the cross-screen consistency pass afterward.

| Situation | Required meaning |
|---|---|
| Organize preview | No media added to the destination by this preview. Do not claim no disk writes: planning can write cache/report records. |
| Photos preview | Photos library unchanged; originals have been exported to staging. Avoid saying no files have been copied anywhere. |
| Transfer with verification on | Copies will be checked; claim they were verified only after the finalized result supports it. |
| Verification skipped | Say verification was skipped; never show the same verified-success wording. |
| Dedupe review/commit | Only the approved plan moves to Trash; retain the current recovery limitations. |
| Partial/cancelled run | State actual completed work and that source originals were untouched. Do not imply the destination was unchanged. |
| Receipt/revert | Show actual receipt status and eligibility. Do not promise every file can always be restored or reverted. |

- Prefer one concise reassurance at the decision point, with further details available through existing help, disclosure or receipt affordances. Remove redundant chips only when they carry no additional state.
- Use semantic panel/elevated surfaces, hairlines and spacing consistently. Keep shadows for appropriate overlays and popovers. Avoid nested cards and decorative app gradients.
- Use scaled typography, readable metadata and monospaced digits for changing counts. Preserve contrast, focus visibility and standard Mac control behavior.
- Specify keyboard operation for promoted custom controls: the timeline must support focus, previous/next bucket, clearing selection and reaching the corresponding review detail without dragging. Keep focus predictable when opening/closing detail, rebuilding a preview or receiving a terminal outcome. Route changing run announcements through `RunAnnouncementPlanner` so routine progress does not interrupt reading.
- Keep motion brief and meaningful: state transitions or verified completion. Respect reduced motion/transparency and differentiate-without-color settings. Do not add an ambient animation loop.
- Regression-check shared consumers in Photos, Sources, Guardian and History. Receipt lists must retain lazy, bounded rendering.

**Invariants touched:** 3, 7, 8, 10, 12, 20 and 22 — verification defaults and re-hashing, revert's hash check, abort wording, Trash-only deletion, dedupe revert's identity check, and Photos read-only for the Photos preview row. The table above is those invariants restated in user-facing words, so every row needs a tagged test asserting the row's wording — not only a test that the underlying behavior still holds, which already exists and will keep passing through a wrong sentence.

**Acceptance:** each reassurance can be traced to runtime evidence; no success/verification claim leaks into an unsupported state; keyboard and VoiceOver expose the same scope and consequences visible on screen.

## Phase 4 — Website identity and product proof

**Status: published, with public-app proof follow-ups.** PRs #226 and #248 are merged.
The final website merge is `c6546b715af4db482f468eb24bc842ab9296cad8`;
Pages run `39186449345` succeeded. Live checks passed for all seven content pages,
the updated stylesheet, product-proof manifest and video byte-range delivery.

**Delivered**

- Shortened “A lifetime of photos, finally in order.” introduction, original
  photographic artwork with recorded provenance, and the Meridian palette.
- Large Organize preview with full-size access, a keyboard-scrollable region and
  readable sample details; a separate dedupe review → Trash → conditional restore story.
- Choose folders → preview → approve copies → inspect History workflow.
- Direct-free V2 offer across the affected pages and metadata: cumulative 500/100
  allowance per Apple Account per Mac; unlimited scanning/preview/review/History;
  $14.99 US lifetime unlock with Family Sharing; ungated Revert with allowance refunds.
- Captioned, user-initiated film, transcript, chapter shortcuts, native playback
  and no-enhancement/error fallbacks. Actual film publication date: October 18.
- Responsive/keyboard/contrast checks and automated accessibility checks, with
  their limits recorded. Source origins and delivered asset checksums are checked.
- Pages runs `check_site.py --release` before artifact upload/deployment. Four
  regressions exercise the actual workflow command and reject unapproved held work.

**Publication decision**

The owner explicitly approved publishing ahead of public V2 and accepts a
temporarily unavailable/mismatched App Store link because there are no active users
or traffic. This replaces the earlier website/public-storefront merge hold.
The manifest records `owner_approved_prelaunch`; it does not claim the public app,
purchase/restore, or September capture builds have been verified.

**Website follow-ups — implementation status**

| Item | Priority / timing | Change and completion evidence |
|---|---|---|
| W1. Mobile product proof | Published in #249; live page verified | CSS shows a focused crop of the unchanged original preview panel/timeline. Always-visible HTML gives 4,000 planned, zero copied, 153 needing review, destination and next action before the image. Full-size native links and sample/development labels remain. Browser checks cover 320/390/768/1280 frames, doubled text and keyboard access. |
| W2. Public V2 proof and offer | When V2 is publicly available; accepted follow-up, not a website publication blocker | Verify the download destination, free app, local unlock price, Family Sharing and production purchase/restore. Refresh or identify the screenshot/film builds, record real capture dates/build/source and public-version mapping, and check labels against the public app. Preserve unknown fields until evidence exists. |
| W3. Help navigation | Published in #249; live navigation verified | Support has six topic shortcuts, native troubleshooting disclosures, recovery/purchase answers and a blank diagnostic email template. New `quick-start.html` supplies the concise four-step on-site guide. Public docs remain the source; deeper GitHub links, `#purchases` and unpublished `site/guides/` work are preserved. |

W1 is supported by a new live screenshot, not an automated overflow failure:
there is no document-wide horizontal overflow, but the useful image content starts
offscreen. W3 is a usability opportunity, not a broken-link finding. The entry
page and recorded-film controls do not need another redesign.

W1/W3 were implemented on `codex/mobile-preview-support` (`ac6f628`,
[PR #249](https://github.com/Nishith/Chronoframe/pull/249)) in the isolated checkout.
The new evidence is `.tmp/shedi-website/docs/website-mobile-support-2026-10-18.md`
and its JSON/captures. The owner merged #249 as `8c6948cb54d504609477083f13c42bd045bba913`
at 04:02:07 UTC on October 19 (October 18 locally). Pages run `39197482632`
succeeded; live navigation confirmed the new homepage summary, stylesheet,
six Support topics, twelve troubleshooting disclosures and four-step guide.
W2 remains the only open item in this website follow-up list.

Full notes, four accepted captures, priorities and accessibility limits are in the
[live website review](website-follow-up-review-2026-10-18.md). The shipped implementation
and prior QA records are in `.tmp/shedi-website/docs/website-design-2026-10-18.md`
and `.tmp/shedi-website/docs/website-qa-2026-10-18.json`.

**Primary files for future website work:** `site/index.html`, `site/styles.css`,
`site/support.html`, public guidance and screenshot/film provenance. Keep app
source and the submitted build unchanged by website-only work.

## Phase 5 — Walkthrough delivery

**Status: delivered as the recorded, captioned fallback.** The existing film,
native player, English captions, descriptive transcript, chapter shortcuts and
direct-video link satisfy this delivery. Playback is user-initiated and does not
access visitor files. No browser simulator, Node test dependency or new JavaScript
CI lane is adopted. The interactive Organize simulator is **cut from this delivery**;
an interactive dedupe extension is **deferred**, not unfinished required work.

Playback, keyboard entry, transcript disclosure, seeking, error and no-enhancement
fallbacks were checked in PR #248. The October 18 follow-up review confirms the
mobile controls and transcript remain usable. Film build/public-version proof
stays in W2 above; website publication is already owner-approved.

### Deferred interactive option — reference contract only

The following specification is retained for a future explicit decision to reopen
the simulator. Its simulated-state/reset/test requirements do not apply to the
completed recorded walkthrough.

If this option is reopened, build a small deterministic Organize walkthrough in the existing static website. Label it “Interactive demo · sample library” and explain that it does not access the visitor's files. It demonstrates selected behavior of the publicly available app version recorded in the product-proof manifest; it is not a browser implementation of the organizer.

1. Start with a curated, licensed sample library and an illustrative dated-folder destination.
2. Preview its date layout and show new, already present and attention states. Allow inspecting a date decision and its source.
3. Let the visitor approve a simulated transfer, then inspect the simulated verified outcome and receipt. Provide a reset/replay control.

Dedupe selection, Trash and restoration are a deferred extension, excluded from the first demo's acceptance. Add that journey only as a separate slice if walkthrough testing identifies a useful comprehension gap; record the decision. Its future contract must cover exact versus review-only similar groups, plan-backed totals and receipt-backed restoration.

Keep all mutations inside in-memory sample state. No file picker, upload, login, purchase flow, real media access, algorithm downloads or new analytics. Never imply the browser performed real hashing, Vision analysis or a speed benchmark. Sample outcomes are predetermined and labeled as such.

The demo's test requirement is a new dependency, not a free addition. The site is static: no `package.json`, no test runner, and no JavaScript lane in CI (`ci.yml` is repository guards plus SwiftPM; `codeql.yml` analyses Swift only). “Deterministic tests” therefore means introducing Node, a test runner, a new CI job and a third-party dependency surface into a Swift-only repository, and then maintaining them. Price that in before starting this slice. If it is not worth paying, cut the slice to a recorded, captioned walkthrough — which serves the same comprehension goal and needs no toolchain — and drop the interactive demo.

**Deferred interactive acceptance (only if reopened):** the Organize journey is complete from the sample library through preview, approval, outcome/receipt and reset; controls work with keyboard/touch and screen readers; focus remains sensible between steps; no fake unsupported buttons; reduced motion and a static/recorded alternative are available; refreshing/resetting gives a clean sample session. Deterministic tests cover Organize transitions, totals, simulated verification and reset. Demonstrated labels and behavior match the recorded public app version; fixture claims remain clearly simulated. Completion does not require a dedupe journey.

**Deferred implementation files:** proposed `site/demo.html`, scoped demo script/styles and licensed sample assets, plus — if the interactive version proceeds — a JavaScript test runner, its `package.json` and a new CI lane. Keep existing static hosting; no backend or hosting migration is needed.

## Delivery order and release integration

| Slice | Original commitment | Current implementation status | Completion evidence / remaining work |
|---|---|---|---|
| 1. Evidence specification and fixtures | Next | App work paused; partial focused contract exists | Full state contract and deterministic fixture matrix remain pending. |
| 2. Presentation accuracy | Committed | Initial uncommitted app changes preserved; not submitted | Focused/full unit validation exists; UI automation and timeline owner decision remain open. See the implementation record. |
| 3. Organize and Setup | Opportunistic | Not started; app work paused | Still needs the complete contract, fixtures and selected/tested direction. |
| 4. Deduplicate | Next | Initial evidence wording belongs to Slice 2; broader layout pending | Plan-backed footer and full dedupe matrix remain app follow-up work. |
| 5. Shared consistency | Opportunistic | Deferred app work | Consumer, keyboard and accessibility regressions are required when shared components change. |
| 6. Website offer corrections | Next | **Published** in #226/#248 | Owner-approved early publication; public-store verification is W2, not a merge hold. |
| 7. Website artwork and product proof | Opportunistic | **Artwork/website QA and mobile improvement published; public proof pending** | W1 is deployed in #249 and live-verified. Released-app build mapping is W2. |
| 8. Organize browser demo | Opportunistic | **Recorded fallback delivered; interactive simulator cut** | Native film, captions, transcript, chapters and fallbacks shipped. Interactive dedupe remains deferred. |

The current app release plan remains authoritative. These presentation improvements are not new app launch blockers. App changes stay separate from the submitted candidate and need fresh validation before any later app release. Website slices have already deployed under the owner's explicit early-publication decision. Future site deployments run the release validator before upload; a held manifest needs either verified release proof or recorded owner approval. W1/W3 are now published and live-verified. Public V2/offer verification remains W2. An interactive simulator is not required.

Use separately reviewable changes for specification/fixtures, accuracy fixes, Organize, Deduplicate, shared consistency, website offer, artwork/proof and demo. Track each slice's status, commit/build, screenshot paths, check results and deferred decisions as it is implemented. Do not mark an app change validated using evidence from an earlier build.

## Validation and completion

- Add focused regressions for changed presentation logic and app/store observation behavior. Extend existing `RunWorkspaceModelTests`, formatter, accessibility, dedupe view/session, trial and contrast suites as appropriate; avoid tests that merely reproduce styling code.
- Exercise minimum/default/wide layouts, light/dark, larger text, Increased Contrast, Reduce Motion, Reduce Transparency, keyboard-only and VoiceOver. Include empty, stale, partial, stopping and failed states, mixed media and pair/sidecar selections.
- Use the named fixture matrix and expected outputs to make checks reproducible. Test observation transitions as well as static values, including changing Setup during/after a captured run, stopping followed by an already-committed success, and a batch reduced by execution revalidation. Verify timeline scope and evidence wording through meaningful presentation regressions.
- Run the required app-layer, title, animation, invariant and other applicable repository guards. Treat `script/check_agents_invariants_have_tests.sh` as a tag presence check, not as evidence that reworded copy still states its invariant truthfully; the named tagged tests in each phase are that evidence. For an app implementation candidate, run the prescribed Swift suites, meaningful-coverage gate, Xcode build/UI tests and accessibility audit. A documentation-only plan needs no app test run.
- Confirm original-file hashes, reviewed-plan/receipt counts and recovery behavior through existing meaningful safety regressions and the release's required signed smoke checks. Do not mutate user media for visual QA.
- On the website, validate links, asset loading, responsive layouts, accessibility and recorded-video interactions; keep offer wording aligned with `free-trial-plan.md`. The owner approved publication before public V2, so keep that exception and unknown app-proof fields explicit. Complete W2 against the public app when available; a local or TestFlight-only build does not establish public availability. Deterministic simulated-state tests apply only if the interactive option is reopened.
- Update `DESIGN_SYSTEM.md` for adopted rules, relevant public guidance for changed labels, and `AGENTS.md` only if architecture/workflow assumptions change. Keep this plan's phase status current during implementation.

Each slice is done when its completion evidence above is recorded, its applicable fixture/accessibility/performance checks pass, and its documentation reflects the delivered behavior. Counts and claims must remain evidence-based; comparison and receipt rendering remain bounded; visuals are inspected with the fixtures used to approve that slice. App slices can complete without website/artwork/demo work; website offer corrections can complete without a redesign; the first demo can complete without dedupe. Deferred extensions remain explicitly deferred rather than unfinished requirements of a completed slice.

## References

- [Design system](DESIGN_SYSTEM.md) and [design tokens](../ui/Sources/ChronoframeApp/App/DesignTokens.swift).
- [Safety and recovery](SAFETY_AND_RECOVERY.md).
- [Free-trial policy](free-trial-plan.md).
- [Remaining app release work](remaining-work-plan.md), [the launch checklist](V2_LAUNCH_CHECKLIST.md), and the [October 18 website follow-up review](website-follow-up-review-2026-10-18.md). Website PRs #226/#248 are merged; their former hold is superseded by the owner's decision.
- [Redesign execution record](redesign-execution-state.md) — historical; the source of the timeline decision this plan reverses.
- [Existing App Store preview and provenance](../marketing/app-preview/README.md) — current checkout work; verify availability before reuse.
