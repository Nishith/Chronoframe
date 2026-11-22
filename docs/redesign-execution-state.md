# Chronoframe Redesign — Execution State

> **Historical record. Superseded by [`DESIGN_SYSTEM.md`](DESIGN_SYSTEM.md)** and the "UI language" notes in `AGENTS.md`; kept for the decisions below. All six phases completed in April 2026 (last updated 2026-04-18) and the redesign has shipped. Specifics captured mid-effort have since evolved (for example, Settings has grown past the three tabs noted in Phase 5). Per-phase file lists, checklists and test counts were removed in the 2026-11 docs cleanup; use `git log` for those.

Planning source: `~/.claude/plans/vivid-crafting-firefly.md` (local planning artifact, not in this repository).

## Phase outcomes

| Phase | Outcome |
|---|---|
| 1 · Foundation | Semantic palette (`ColorSystem.*`) on dynamic `NSColor` providers, SF Pro instead of SF Rounded, `Spacing` enum, `Motion` plus the Reduce-Motion-aware `.motion(_:value:)` modifier, `.darkroom()` canvas modifier. Legacy token names kept as aliases. Console font 12 to 13pt; corner radii tightened. |
| 2 · Surface system + chrome | `DarkroomPanel` is the preferred surface. `MeridianSurfaceCard` demoted (no gradient or shadow, hairline border). `DetailHeroCard` retuned, not removed. Hero eyebrows deleted; sidebar rows single-line. |
| 3 · Setup | `PathControl` (`NSPathControl` wrapper), `ContactSheetView` (QuickLook thumbnails), full-window drop overlay. |
| 4 · Run timeline | `RunTimelineView` proxy dot grid, `RunPhaseStrip`, `NowCopyingCard`, `TickerRow` replacing the metric grid, completion haptic. |
| 5 · History, Profiles, Settings | Native `TabView` Settings, `LazyVGrid` profile tiles with hover-reveal menus, History flattened to hairline-separated rows in one panel per section. |
| 6 · Accessibility, copy, onboarding | VoiceOver hints and Issues rotor, copy trimmed, one-shot `OnboardingCard` gated by `@AppStorage("didOnboard")`, dead `RunPhaseTimeline` removed. |

## Decisions that still matter

- Use `.motion(_:value:)` instead of `.animation(_:value:)` for anything that should respect Reduce Motion (the repo now also enforces no raw animations via `script/check_no_raw_animations.sh`).
- Keep accessibility identifiers on interactive controls; UI tests depend on them.
- `NSColor(name:dynamicProvider:)` was chosen over `Color(light:dark:)`; keep it unless the design system deliberately migrates.
- `ContactSheetView` enumerates files by extension on its own, capped at 12, and is deliberately not routed through `MediaDiscovery` (the engine pipeline is expensive and async).
- `ContactSheetLoader` is `@MainActor` while its enumeration helpers are `nonisolated`, as Swift 6 strict concurrency requires.
- The run timeline is a proxy dot grid because the engine does not stream per-(year, month) aggregates and `RunMetrics` carries flat counts. A real aggregator would replace only the index computations in `RunTimelineView`.
- `NowCopyingCard` uses an SF Symbol placeholder because the engine exposes `currentTaskTitle`, not a current-file URL.
- The history filter keeps `HistoryFilter` (All/Reports/Receipts/Logs/Other), because the planned "Preview/Transfer/With errors" categories do not map to `RunHistoryEntryKind`.
- Row-level overflow menus use a borderless ⋯ menu with `menuIndicator(.hidden)` and `.fixedSize()`.
- `DetailHeroCard` still has callers; audit them before deleting it.

## Deferred at the time of completion (check before relying on these)

- Dynamic Type: fixed-point fonts at the time; a scaling layer has since been added in `ui/Sources/ChronoframeApp/App/Typography+Scaling.swift`.
- No interactive Accessibility Inspector or contrast audit was run. Expected finding: low-contrast `MeridianStatusBadge` pills on warning tones in light mode.
- `docs/screenshots/` regeneration was not done as part of the redesign.
