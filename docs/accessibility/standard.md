# Chronoframe Accessibility Standard

Chronoframe's accessibility bar is: core organize and deduplicate flows must be completable with keyboard, VoiceOver, Switch Control-compatible focus movement, and macOS system accessibility settings enabled.

## Audit Gate

The Xcode UI accessibility audit is a hard gate by default. Local discovery runs may set `CHRONOFRAME_A11Y_AUDIT_WARN_ONLY=1`, but CI must fail on any non-baselined issue.

Known platform false positives live in `docs/accessibility/audit-baseline.json`. The file must stay reviewable and narrow:

- `scenario`: one of the UI-test scenarios.
- `auditType`: the XCTest audit type, or `*` only when the issue signature is audit-type agnostic.
- `signature`: a stable substring from the XCTest issue description.
- `severity`, `owner`, `reason`, `expiration`, `trackingIssue`: ownership and expiry metadata.

Do not add app regressions to the baseline. Missing labels, poor contrast, insufficient hit regions, text clipping, and incorrect traits should be fixed in product code.

## Phase 1 Ship Bar

- Audit gate fails closed by default.
- CI publishes the audit JSONL artifact for triage.
- macOS-specific `action` and `parentChild` audit types are included alongside the cross-platform audit set.
- `PathControl` exposes a native focus ring and spoken label/value/help.
- Shared focus-ring decisions are centralized for custom keyboard controls.
- Reduce Transparency material gaps remain guarded through `accessibleMaterialBackground`.

## macOS-Specific Acceptance

Chronoframe is a macOS app, so larger-text validation should be grounded in macOS behavior: Display Zoom, Hover Text, keyboard focus, VoiceOver, and clipping checks in representative UI tests. SwiftUI scaled typography remains useful hygiene, but `.accessibility1` previews alone are not evidence that the shipped Mac app meets the larger-text bar.
