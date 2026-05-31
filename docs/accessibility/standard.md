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

## macOS-Specific Acceptance

Chronoframe is a macOS app, so larger-text validation should be grounded in macOS behavior: Display Zoom, Hover Text, keyboard focus, VoiceOver, and clipping checks in representative UI tests. SwiftUI scaled typography remains useful hygiene, but `.accessibility1` previews alone are not evidence that the shipped Mac app meets the larger-text bar.
