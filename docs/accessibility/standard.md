# Chronoframe Accessibility Standard

Chronoframe's accessibility bar is: core organize and deduplicate flows must be completable with keyboard, VoiceOver, Switch Control-compatible focus movement, and macOS system accessibility settings enabled.

## Audit Gate

The Xcode UI accessibility audit supports two modes:

- Discovery/bootstrap mode runs the audit and uploads JSONL evidence without failing an empty, not-yet-verified baseline.
- Strict mode fails on every non-baselined issue. Set `CHRONOFRAME_A11Y_AUDIT_STRICT=1` after the baseline is verified clean or populated only with reviewed platform false positives.

Local exploratory runs may set `CHRONOFRAME_A11Y_AUDIT_WARN_ONLY=1` to suppress strict failures while investigating audit output.

Known platform false positives live in `docs/accessibility/audit-baseline.json`. The file must stay reviewable and narrow:

- `scenario`: one of the UI-test scenarios.
- `auditType`: the XCTest audit type, or `*` only when the issue signature is audit-type agnostic.
- `signature`: a stable substring from the XCTest issue description.
- `severity`, `owner`, `reason`, `expiration`, `trackingIssue`: ownership and expiry metadata.

Do not add app regressions to the baseline. Missing labels, poor contrast, insufficient hit regions, text clipping, and incorrect traits should be fixed in product code.

## Phase 1 Ship Bar

- Audit gate fails closed in strict mode and once a verified baseline exists; an empty baseline stays in bootstrap mode until the audit has been observed clean or populated deliberately.
- CI publishes the audit JSONL artifact for triage.
- Native macOS `action` and `parentChild` audit types are included alongside the cross-platform audit set. XCTest exposes `textClipped` and `trait` for iOS, tvOS, watchOS, and simulator SDKs, not native macOS in the current SDK.
- `PathControl` exposes a native focus ring only when interactive, plus caller-specific spoken label/value/help before production adoption.
- `PathValueView`, the currently rendered path display, exposes semantic label/value text instead of relying on bare text and tooltips.
- Shared focus-ring decisions are centralized for custom keyboard controls.
- Known direct dedupe material sites route through `accessibleMaterialBackground`, with source tests guarding the three Reduce Transparency gaps identified in the review.

## Phase 2 Dedupe Review Ship Bar

- Dedupe review member thumbnails and side-by-side comparison panes are real SwiftUI focus targets, not pointer-only hit regions.
- Focused clusters, focused members, and selected comparison panes use the shared visible focus-ring treatment.
- Row-level dedupe actions are always reachable through a visible Actions menu; hover affordances may only duplicate actions that remain keyboard reachable.
- Keyboard shortcuts remain available, but every shortcut-backed dedupe review action must also have a visible focusable control or menu item.

This is the dedupe-review slice of Phase 2. Keyboard traversal and modal focus placement for Setup, Run, Preview, History, Profiles, Settings, and destructive confirmation flows remain follow-up Phase 2 work.

## Phase 3 Announcement And Progress Bar

- Run and Deduplicate status changes use pure announcement planners so wording and throttling stay testable.
- VoiceOver announcements are reserved for phase changes and terminal outcomes such as preview ready, scan complete, transfer complete, restore complete, and failures.
- Per-item progress is not announced as milestones. Progress surfaces expose completed/total counts through `accessibilityValue` so users can query current progress on demand without speech spam.
- Failure announcements must reassure users when originals were left untouched.

## Phase 4 Typography Bar

- Core workflow chrome and review rows should use semantic `scaledFont` roles instead of raw `.font(...)` modifiers.
- Dedupe remains covered by the stricter source guard from earlier phases; this phase extends coverage to Setup, Run History, Sidebar navigation, onboarding, and workspace tabs.
- Geometry-bound image placeholders may keep size-derived glyph rendering only when the glyph is part of a thumbnail canvas, not user-facing text.

## Phase 5 System Settings Bar

- System accessibility settings must visibly change more than dedupe review. Health, run, setup, and navigation surfaces should encode status with shape, iconography, labels, or pattern in addition to color.
- Differentiate Without Color must remove color-only meaning from dashboard summaries; severity charts need non-color encodings such as symbols, labels, dash patterns, or text marks.
- Increased Contrast should strengthen focus rings, dividers, and status marks without changing the workflow or hiding information.
- Phase 5 currently hardens the Health dashboard; sidebar status dots, run/progress phase states, setup status marks, and broader navigation indicators remain follow-up surfaces for the same standard.

## Phase 6 Modal Focus Bar

- Sheets and overlays must place initial keyboard and accessibility focus on a meaningful control instead of leaving users at an undefined window root.
- Dismissing a modal workflow should return focus to the invoking review context when the source view owns explicit focus state.
- Escape/Done paths must remain visible, labeled, and keyboard reachable.

## Phase 7 Destructive Confirmation Bar

- High-consequence actions must have confirmation copy that names scope, outcome, and source-file safety before the user commits.
- Shortcut or button entry points into destructive confirmations need accessibility hints that make the upcoming confirmation discoverable.
- Confirmation wording should live behind pure helpers where practical so safety claims and spoken context are covered by unit tests.
- Phase 7 currently hardens the Reorganize confirmation; delete profile, discard paused review, transfer cancel, revert, and moving focus to recovery actions on error remain follow-up destructive-path surfaces.

## Phase 8 Settings Typography Bar

- Settings and profile-management controls should use semantic `scaledFont` roles instead of raw `.font(...)` modifiers.
- Dense preference captions may use compact roles such as `label`, but they should still route through the scalable typography layer.
- Source tests should guard Settings and Profiles alongside core workflow chrome so future preference additions do not reintroduce fixed fonts.

## Phase 9 Run And Organize Typography Bar

- Run and Organize status panels should use semantic `scaledFont` roles for visible labels, metrics, hints, and timeline markers.
- Fixed monospaced fonts are allowed only for dense console or issue-log text where character alignment is the accessibility affordance.
- Because those console and issue-log exceptions intentionally do not scale, low-vision acceptance for them relies on macOS Display Zoom, Hover Text, and selectable/copyable text instead of SwiftUI text-size scaling.
- Source tests should guard representative Run and Organize status files and keep console-only fixed-font exceptions narrow.

## macOS-Specific Acceptance

Chronoframe is a macOS app, so larger-text validation should be grounded in macOS behavior: Display Zoom, Hover Text, keyboard focus, VoiceOver, and clipping checks in representative UI tests. SwiftUI scaled typography remains useful hygiene, but `.accessibility1` previews alone are not evidence that the shipped Mac app meets the larger-text bar.
