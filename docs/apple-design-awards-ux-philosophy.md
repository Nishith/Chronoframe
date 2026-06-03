# Apple Design Awards UX Playbook

Research basis: Apple Design Awards winners and finalists from 2024, 2025, and 2026, with special attention to Mac/macOS-compatible nominees and winners. This is a synthesis of Apple's public award rationale and Human Interface Guidelines, not a full hands-on teardown of every app.

Primary sources:

- [Apple Design Awards 2026 winners and finalists](https://developer.apple.com/design/awards/)
- [Apple Design Awards 2025 winners and finalists](https://developer.apple.com/design/awards/2025/)
- [Apple Design Awards 2024 winners and finalists](https://developer.apple.com/design/awards/2024/)
- [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines)
- [Apple HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)
- [Apple HIG Layout](https://developer.apple.com/design/human-interface-guidelines/layout)

## How to Use This Playbook

This document is two things in one. The first half is a philosophy — six principles describing how Chronoframe should feel and what it should optimize for. The second half is a pattern library: specific design moves observed in awarded apps that we can adopt, adapt, or audit against. Use the philosophy to evaluate proposals; use the patterns when you need a concrete next step.

## Executive Takeaway

The recent Apple Design Awards reward apps that make sophisticated work feel humane. The best experiences are not visually loud by default. They are clear, platform-native, emotionally legible, highly responsive, and — increasingly — built on **on-device intelligence as a privacy guarantee**. Their personality shows up through precise pacing, carefully chosen feedback, rich but restrained visuals, and a deep respect for user context.

A small-team craft signal runs through every recent cycle: Apple repeatedly names solo developers and small studios by name (Hearing Buddy, Caradise, Spilled!, Sunlitt, SmartGym, Moonlitt). Depth-over-breadth and noticeable polish are read by Apple as evidence of caring.

For Chronoframe, the lesson is not "make it prettier." The lesson is: make the safe path feel self-evident, make complex media decisions feel calm and reversible, prove the local-first promise at every decision point, and let the interface disappear until it needs to reassure, explain, or delight.

## What Apple Is Rewarding

### 1. Clarity Before Decoration

Apple repeatedly praises apps where people can understand the next action without decoding the interface. Crouton (2024 Interaction winner) is recognized for organization and information hierarchy: recipe steps, ingredients, and grocery actions are where people need them. Procreate Dreams (2024 Innovation winner) is praised because complex animation tools are immediately usable through intuitive gestures and Apple Pencil behaviors. Tide Guide (2026 double winner — Interaction *and* Visuals/Graphics) presents dense marine and weather data in full-screen charts that remain crisp and understandable. The double win is the single clearest signal of the cycle: clarity-first design can also be the most visually distinctive.

Observed patterns:

- **Persistent context surface** (Crouton). A counter view stays visible while users work in another screen, so eyes stay on the task — not the chrome.
- **Single canonical artifact** (Tide Guide). Dense data is anchored to one full-screen chart that scales across iPhone, Mac, and widget; secondary views are drill-downs, not parallel sources of truth.
- **Mode-shifted layout** (Mela's cooking mode). Same data, different layout, triggered by intent — only the step and measurement that matter right now are elevated.

Design implication: beauty is downstream of comprehension. A beautiful interface that slows task understanding is not Apple-quality. In operational software, clarity is the primary aesthetic.

For Chronoframe:

- The user should always know what folder is being read, what folder will be written, what will happen next, and what will never happen.
- Safety promises should be visible at decision points, not buried in help text.
- Every destructive-adjacent action should show scope, reversibility, and current confidence.

### 2. Native Fluency Beats Novel Chrome

Apple rewards apps that feel tailored to their platform. The HIG frames this as hierarchy, harmony, and consistency: controls should establish clear structure, align with system design, and adapt across window sizes and displays. The 2026 cycle introduces a new system material — **Liquid Glass** — and Moonlitt and Tide Guide are both cited for *"best-in-class Liquid Glass integration."* The pattern is not to chase the new material; it is to adopt it where it clarifies depth and hierarchy.

Apple also treats performance as a UX feature. Cyberpunk 2077's 2026 win specifically calls out *"For This Mac"* per-device optimization — the app right-sizes itself rather than ship one preset.

Observed patterns:

- **Liquid Glass at hierarchy boundaries**, not as decoration. Moonlitt uses it to separate phase data from background sky; Tide Guide uses it to layer current conditions over its full-screen chart.
- **Per-device responsiveness as a UX feature.** Large library scans, dedupe scoring, thumbnail generation should feel sized to the machine running them.
- **Native macOS chrome by default.** Sidebars, toolbars, inspectors, standard tables, menu commands, drag/drop, Finder reveal, context menus, keyboard navigation.

For Chronoframe:

- Prefer native macOS window structure and standard controls over custom chrome.
- Use system materials sparingly and intentionally, especially around long-running tasks and confirmation flows.
- Treat scan/copy/dedupe latency on large libraries as a UX deliverable, not just a perf metric.
- Make macOS affordances complete: menu commands, undo/revert where appropriate, Help, drag/drop, context menus, Finder reveal, and keyboard navigation.

### 3. On-Device Intelligence Is a Privacy Promise

The 2026 cycle marks a shift Apple now rewards openly: on-device Foundation Models are treated as a UX value, not just a technical detail. Hearing Buddy (2026 Inclusivity finalist) uses on-device models for real-time captions and conversation summaries. Structured (2026 Inclusivity finalist) uses them for task suggestions inside a simple, scannable layout. Harvee (2026 Social Impact finalist) is cited specifically because *"on-device foundation models keep sensitive health data secure."*

That single sentence is the closest analog Apple has yet given for Chronoframe's "your photos never leave this Mac" promise. The award language treats *"never leaves the device"* as a designed outcome — surfaced in copy, visible at decision points, and made provable.

Observed patterns:

- **Privacy claims placed near data.** Harvee surfaces "on-device" wording near the metrics it derives from, not in a generic privacy footer.
- **Capability tied to context.** Detail (2026 Innovation finalist) ties Foundation Models to the script-generation capability, so the AI output appears in the same context as the user intent.
- **Sensitive metrics aggregated locally.** Structured shows AI-generated suggestions but never networks the source data.

For Chronoframe:

- Treat "originals stay on this Mac" and "no network calls during scan/copy/dedupe" as first-class UX claims, not boilerplate.
- Surface the promise at setup, scan, transfer, dedupe, and receipt views — wherever the user would reasonably wonder if a file moved off-device.
- If we ever add ML scoring (dedupe similarity, scene tagging, smart suggestions), state that it runs locally at the moment the user sees its output.

### 4. Trust Is a Designed Outcome

Apple has begun naming trust as a design deliverable. Ground News (2025 Social Impact finalist) is praised because its color-coded bias markers, user-friendly layouts, multi-perspective comparison, and third-party-evaluated ratings are crafted to inspire trust and transparency. Watch Duty (2025 Social Impact winner) is described as an essential, sometimes life-saving information source — its volunteer-run, real-time wildfire updates are evaluated as design because lives depend on user confidence in the data.

Chronoframe sits in this same category: the user is handing the app their irreplaceable archive. Trust is the product, not a side benefit.

Observed patterns:

- **Show provenance, not just results.** Ground News pairs every story with its sources and their political lean.
- **Make provenance part of the trust story.** Watch Duty's volunteer-run operation and real-time guidance make source credibility part of the experience.
- **Calm confidence over urgency.** Even in life-critical contexts (Watch Duty), the tone is steady and specific, not alarmist.

For Chronoframe:

- Replace generic reassurance with sourced reassurance: "Originals at /Users/.../Source — last read at 14:02, no writes" beats "Your files are safe."
- Make destructive recommendations inspectable: confidence score, what evidence produced it, what would change the recommendation.
- Reserve urgent tones for true risk (failed verification, low disk, source-write attempt).

### 5. Delight Is a Functional Detail

The award language for delight is rarely about spectacle alone. Bears Gratitude (2024 Delight winner) uses characters as a welcoming way into reflection. Blippo+ (2026 Delight finalist) uses world-building detail to make simple interactions memorable. (Not Boring) Camera (2026 Visuals finalist) uses oversized tactile controls and haptic-style behavior, but still supports SuperRAW and serious photography. PowerWash Simulator and Is This Seat Taken? (both 2026) turn repeated actions into satisfying feedback loops.

Delight is strongest when it makes the task easier to start, easier to continue, or easier to emotionally tolerate.

Observed patterns:

- **Oversized affordances signal "this is the moment."** (Not Boring) Camera's large shutter and dial reward a serious capture; Crouton's big-text counter rewards a serious cook.
- **Animated arrival** (CapWords). Each captured object animates into the learning shelf — placement gets ceremony.
- **Character or motif as orientation, not decoration.** Bears Gratitude's bear isn't a mascot; it's a navigation anchor.

For Chronoframe:

- Delight should reduce anxiety, not distract from safety.
- The amber waypoint motif can mark progress, arrival, and verified placement — not every screen.
- Microcopy, animation, and progress feedback should make the user feel accompanied through uncertainty.

### 6. Accessibility Is Product Quality, Not Compliance

Recent winners and finalists are recognized for accessibility as core experience design. Guitar Wiz (2026 Inclusivity winner) uses VoiceOver, Dynamic Type, Increased Contrast, and Differentiate Without Color to help musicians play with autonomy. oko (2024 Inclusivity winner) uses audio and haptic feedback for low-vision pedestrians. Crayola Adventures (2024) includes inclusive character options and narration for non-readers. Structured (2026) is praised for a simple, scannable layout that helps neurodivergent users manage time and downtime. Pine Hearts (2026 Inclusivity winner) *"clearly communicates inclusivity options before play"* — accessibility surfaced at the moment of meaningful choice.

Apple's accessibility guidance defines accessible interfaces as intuitive, perceivable, and adaptable. That maps directly to Chronoframe's trust problem: people need to perceive risk, understand choices, and adapt the app to their confidence level.

Observed patterns:

- **Surface accessibility settings before commitment** (Pine Hearts). Don't bury them in a deep Settings menu after the user has already committed to a flow.
- **Status by shape + text + position, never by color alone** (Guitar Wiz).
- **Cognitive accessibility as layout discipline** (Structured): one decision per screen, generous whitespace, plain nouns.

For Chronoframe:

- Never rely on color alone for status, confidence, warnings, or deletion recommendations.
- Provide visible text, symbols, and state changes for all safety-critical decisions.
- Support keyboard traversal, VoiceOver labels, larger text, contrast, reduce motion, and clear focus states.
- Treat cognitive load as an accessibility concern: fewer simultaneous concepts, stronger grouping, plain language.
- Make accessibility-affecting choices visible before long or high-stakes flows, and honor system accessibility settings without extra setup.

### 7. Data Should Become Guidance

Many recognized apps transform complex data into decision support. Moonlitt (2026 Interaction winner) and Lumy (2025 Delight finalist) turn celestial data into useful timing. Tide Guide (2026) turns weather, swell, tide, and temperature into readable charts and widgets. Harvee turns health metrics into recovery guidance through a central avatar. Crouton (2024) and Mela (2025 Interaction finalist) turn recipe text into stepwise cooking actions. Copilot Money (2024 Innovation finalist) and SmartGym (2024 Innovation finalist) translate domain data into actionable, personal next steps.

The awarded pattern is not "show all data." It is "show the data that helps the next decision."

Observed patterns:

- **Question-shaped headlines.** Moonlitt's primary surface answers "when is the best window tonight?" before showing the raw ephemeris.
- **One avatar, many metrics** (Harvee). A single character carries the rolled-up state; the underlying metrics live behind it.
- **Scan → review → act** (Mela's Vision-framework recipe scanning; Copilot Money's transaction review). Same three-step shape repeats across recipe, finance, and fitness apps.

For Chronoframe:

- File counts, hashes, EXIF dates, duplicates, confidence, and receipt status should be translated into choices.
- The UI should answer: "What is safe to do now?", "What needs my attention?", and "What changed?"
- Use progressive disclosure: summary first, evidence on demand, audit details when needed.

### 8. The Interface Should Respect the User's Emotional State

Social Impact winners and finalists show a consistent sensitivity to emotion. Gentler Streak (2024 Social Impact winner) avoids punitive fitness language and frames health as progress. The Wreck (2024 Social Impact winner) uses interaction to express stress and grief. Neva (2025 Social Impact winner) connects visual language to emotional stakes. Consume Me (2026 Social Impact winner) uses mechanics to make a difficult subject visceral without trivializing it. Apple rewards products that understand UX is not only efficiency — it is emotional pacing.

Chronoframe users may arrive with a messy, precious archive and a fear of losing memories. The product's tone should be calm, specific, and protective.

Observed patterns:

- **Frame progress, not deficit** (Gentler Streak). "Three days of recovery" not "missed your goal."
- **Tempo matches subject** (The Wreck, Neva). Slower transitions where the user is making heavy decisions.
- **Mechanics carry meaning** (Consume Me). What the user *does*, not just what they read, expresses the stakes.

For Chronoframe:

- Replace uncertainty with staged confidence.
- Use reassuring copy only when the system can prove it.
- Put proof near reassurance: "Originals are untouched" is stronger when paired with what the app is actually doing.
- Avoid alarmist language. Reserve red and urgent motion for true risk.

### 9. Let the Domain Create the Visuals

The best visual systems emerge from the work itself. Tide Guide's palette follows the sky and sea, tying visuals directly to its domain. Neva's color palettes and camera movement carry emotional meaning. Rooms (2024 Visuals winner) uses nostalgic 8-bit detail because it is a creative world.

The lesson is not to borrow these aesthetics. It is to do for our domain — time, memory, paths, verification, and safe arrival — what these apps do for theirs.

For Chronoframe:

- Use the Meridian language as a calm operational base.
- Let the amber waypoint be the meaningful flourish, not a decoration applied everywhere.
- Build visual hierarchy around chronology, confidence, and destination.
- Photo/video thumbnails should remain the richest visual material in the app.

### 10. Motion Should Explain, Not Perform

Awarded apps use animation as feedback, spatial orientation, or emotional storytelling. CapWords turns object capture into animated learning. Denim (2025 Delight finalist) uses transitions and haptics to make cover creation feel playful. Procreate Dreams uses polished interactions to make animation creation approachable. Tide Guide uses custom animations to reinforce data presentation.

Observed patterns:

- **Animate placement, not motion for its own sake.** CapWords animates the *arrival* of a captured word, not the capture itself.
- **Haptics paired with state, not gesture** (Denim). A haptic confirms a discrete event ("cover saved"), not every drag.
- **Reduce Motion as a first-class path**, not a fallback. Apple has cited this in nearly every recent Inclusivity rationale.

For Chronoframe:

- Motion should clarify progression through scan, preview, copy, verify, receipt, and completion.
- State transitions should be steady and reversible-feeling, never frantic.
- Use animation to show "this file found its place" only when placement is verified.

## Mac-First Precedent Apps

Apple's Mac-compatible roll-call spans many categories. For Chronoframe, the most useful precedents are operational/data-organizing apps where users do consequential desktop work — not AAA games, however well-rendered.

**Direct precedents (operational, data-organizing, desktop-depth):**

- **Crouton** (2024 Interaction winner) — hierarchy, persistent counter view
- **Mela** (2025 Interaction finalist) — cooking mode, Vision-framework recipe scanning, RSS ingestion
- **iA Writer** (2025 Interaction finalist) — distraction-free editing, intuitive swipe gestures, customizable keyboard
- **Copilot Money** (2024 Innovation finalist) — financial data, trust-building disclosure
- **SmartGym** (2024 Innovation finalist) — fitness data as actionable next steps
- **Structured** (2026 Inclusivity finalist) — calm scannable layout for cognitive accessibility
- **Harvee** (2026 Social Impact finalist) — on-device Foundation Models for sensitive data
- **Tide Guide** (2026 double winner) — dense data made crisp
- **Moonlitt** (2026 Interaction winner) — Liquid Glass integration, broad platform support
- **Bears Gratitude** (2024 Delight winner) — emotional welcome into a serious practice

**Secondary precedents (Mac-rendered games — technical polish only):**

djay, Balatro, Thank Goodness You're Here!, Play, DREDGE, Neva, Blippo+, Guitar Wiz, Is This Seat Taken?, Blue Prince, Consume Me, Despelote.

The macOS pattern across both lists is consistent:

- Respect the desktop as a place for depth, comparison, and sustained attention.
- Use native structure so the app feels at home beside Finder, Photos, Preview, and professional creative tools.
- Make large datasets or complex artifacts navigable through hierarchy, not through visual density alone.
- Let performance and technical polish be part of the design. On Mac, responsiveness is a UX feature.
- Give advanced users leverage without making new users feel exposed.

## The Philosophy

### Calm Mastery

Our apps should help people do consequential work with calm mastery.

Calm means the interface is steady, legible, and emotionally considerate. It does not shout. It does not decorate uncertainty. It reduces anxiety by making state, risk, and reversibility visible.

Mastery means the app grows with the user. First-time workflows should be obvious, but expert workflows should be fast, inspectable, and precise. The product should earn trust by showing its reasoning and by giving people control at the right moments.

This philosophy has six principles.

### Principle 1: Make the Safe Path Obvious

The primary path should be visually and behaviorally clear. If the user must understand safety before acting, safety belongs in the main flow.

Observed patterns:

- **Crouton's prominent next-step surface** keeps the current cooking step visible while everything else recedes.
- **Pine Hearts' pre-play accessibility prompt** raises consequential settings *before* the user commits.
- **Mela's cooking mode** elevates one decision (the current step) and pushes the rest of the recipe behind it.

Review prompts:

- Can a first-time user predict what will happen before pressing the primary button?
- Does every risky action name its scope?
- Is the safest recommendation also the easiest one to follow?

### Principle 2: Process Locally; Make Privacy Legible

The 2026 cycle reframes on-device processing as a UX deliverable. If Chronoframe's data never leaves the user's Mac, that fact should be present in the interface — not buried in a privacy policy.

Observed patterns:

- **Harvee** surfaces "on-device" near the metrics it computes, not in a generic settings page.
- **Structured** and **Hearing Buddy** disclose Foundation Models use at the moment AI output appears, so the user can connect privacy to capability.
- **Detail** ties Foundation Models output to a specific creative capability rather than treating AI as a generic app-wide feature.

Review prompts:

- Where does the user encounter data that could plausibly leave the device? Is the local-only promise visible there?
- Do we surface the promise at scan, transfer, dedupe, and receipt — or only on the marketing site?
- If we add ML scoring later, where will its locality be stated?

### Principle 3: Show Evidence at the Moment of Trust

People trust software when claims are paired with proof. A promise without evidence is marketing. A promise with nearby evidence becomes UX.

Observed patterns:

- **Ground News** pairs every story with its sources and their political lean — trust is the layout, not a footer.
- **Watch Duty** names the volunteer reporter behind a wildfire update — provenance over abstraction.
- **Tide Guide** anchors widgets and forecasts to a single canonical chart, so disagreements between surfaces are impossible.

Review prompts:

- Where do we claim something is safe, verified, reversible, or unchanged?
- What proof can we show there without overwhelming the user?
- Can the user inspect the technical basis if they need to?

### Principle 4: Reduce Cognitive Load Before Adding Capability

Powerful apps become usable when they stage complexity. The first screen should answer the user's current question; deeper details should remain available without dominating.

Observed patterns:

- **Skate City: New York** (2025) is praised for *"smartly-spaced lessons"* — onboarding paced to mastery, not crammed up front.
- **Crouton** uses progressive disclosure of ingredient lists, conversions, and shopping actions.
- **iA Writer** hides every control until the user needs it, then surfaces them via consistent gestures.

Review prompts:

- What is the one decision this screen asks the user to make?
- Which details are necessary now, and which can be revealed later?
- Are repeated concepts named consistently across the app?

### Principle 5: Make Feedback Tactile, Specific, and Reassuring

Feedback should acknowledge user action immediately, explain long work honestly, and close loops with proof. "Done" is weaker than "Copied and verified 1,248 items. Originals were untouched." And on failure, "didn't move 3 items" is weaker than "3 items remained in source; nothing was overwritten."

Observed patterns:

- **CapWords** animates each captured object into a learning shelf — completion is shown, not just stated.
- **Denim** pairs haptics with discrete events (save, share), not continuous motion.
- **Watch Duty** closes loops with specific provenance even in failure states ("no new reports since 14:02 from County Fire").

Review prompts:

- Does each long-running phase show progress and current work?
- Are failures specific and action-oriented?
- Does completion state explain what happened and what remains possible?
- Does failure copy preserve the user's mental model of safety — what *didn't* happen, where originals are?

### Principle 6: Let the Domain Create the Beauty

The best visual systems emerge from the work itself. For Chronoframe, the domain is memory, time, evidence, and safe organization. The UI should frame photos and videos clearly, express chronology naturally, and use the waypoint motif to mark verified movement.

Observed patterns:

- **Tide Guide's palette** matches sky color through the day — the visual system *is* the data.
- **Neva's per-level color palette** carries narrative — the look means something.
- **(Not Boring) Camera's oversized controls** earn their style because they reward serious capture.

Review prompts:

- Does this visual treatment clarify time, confidence, or destination?
- Are thumbnails and media previews given enough respect?
- Is the brand motif helping orientation, or merely adding color?

## Observed Pattern Library

Cross-cutting design moves that recur across awarded apps. Use these as starting points; adapt to Chronoframe's domain.

### Onboarding & First Use

- **Pre-commit accessibility surfacing** (Pine Hearts) — raise inclusivity/setup choices before the user is invested.
- **Smartly-spaced lessons** (Skate City: New York) — teach a new mechanic just before it's needed, not before play.
- **Empty-state as invitation** (Bears Gratitude, Crouton) — first launch shows what the app *will* hold, not a generic placeholder.

### Status, Confidence & Risk

- **Shape + text + position, never color alone** (Guitar Wiz).
- **Source-named provenance** (Watch Duty, Ground News) — every claim cites its origin.
- **Confidence as a value, not a vibe** — show the number that produced the recommendation, and what would change it.

### Progress & Long Work

- **Phase-shaped progress** (Tide Guide forecasts, Procreate Dreams renders) — name what is happening now, not just a percent.
- **Animated arrival** (CapWords) — placement gets ceremony only when verified.
- **Live Activity / widget surfacing** (Mela's Dynamic Island timers) — long work follows the user out of the app.

### Privacy & Local Processing

- **Disclosure at the point of capability** (Detail, Structured) — say "on-device" where the output appears.
- **Locality in the headline, not the footer** (Harvee) — privacy as the leading sentence.
- **No network for sensitive paths** — if a flow doesn't touch the network, design so the user can tell.

### Visual Distinctiveness

- **Domain-derived palette** (Tide Guide's sky, Neva's seasons).
- **One motif, used sparingly** (Chronoframe's amber waypoint; Bears Gratitude's bear).
- **Liquid Glass at hierarchy boundaries** (Moonlitt, Tide Guide) — material to separate depth, not as ornament.

### Motion & Haptics

- **Haptics for discrete state, not continuous gesture** (Denim).
- **Reduce Motion as a first-class path**, not a fallback.
- **Slow tempo for heavy decisions** (The Wreck) — make destructive flows feel deliberate.

### Performance as UX

- **Per-device responsiveness** (Cyberpunk 2077's "For This Mac"). Right-size scan, dedupe, and thumbnail work to the machine.
- **Apple Silicon as a design feature** — heavy lifting that completes in seconds is itself a calmness signal.

### Craft Signals

- **Solo / small-team polish is read as caring** (Hearing Buddy, Caradise, Spilled!, Sunlitt, SmartGym, Moonlitt). Chronoframe is in this lineage; depth-over-breadth is the right posture.

## Application Checklist

Use this checklist before proposing or accepting UX changes:

- The next action is clear without explanatory prose.
- The interface distinguishes source, destination, preview, mutation, verification, and receipt.
- The primary action is the safest action.
- Any destructive or irreversible-looking action includes scope, evidence, and recovery information.
- Status is conveyed with text and shape/iconography, not color alone.
- The local-only promise is visible at the decision points where data could plausibly leave the device.
- The screen supports keyboard and VoiceOver use.
- Motion communicates state change and respects Reduce Motion.
- Empty, loading, error, and completion states are specific and reassuring.
- Failure copy preserves the user's mental model of safety — what didn't happen, where originals are.
- Advanced detail exists, but does not crowd the default view.
- The visual language is native macOS first, Meridian second, decorative never.

## Open Review Questions

- Should "Calm Mastery" become the named product design philosophy for Chronoframe, or should it remain internal framing?
- Which Chronoframe workflow most needs this philosophy first: setup, preview, dedupe review, transfer progress, completion, or run history?
- Where do users currently need more proof before trusting the app?
- Where is the app asking users to understand implementation details instead of translating them into decisions?
- Where do we currently ask the user to trust an unverifiable claim, and what would proof at that point look like?
- Which small delight would reduce anxiety rather than add noise?

## Next Step After Review

After this document is reviewed, use it to create a Chronoframe UX improvement plan that audits current screens against the six principles and the observed pattern library, and ranks changes by user trust, safety impact, implementation cost, and regression risk.
