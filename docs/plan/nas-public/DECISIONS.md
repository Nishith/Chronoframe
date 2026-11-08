# NAS public — decisions

Prefix `NASP`. Runtime decisions are appended as `D-NASP-1NN`.

## Tie-break rule for new gaps
Same as every next-half plan: keep every invariant and every `docs/NAS_REQUIREMENTS.md` requirement; fewest changed lines; copy the named reference pattern; fail closed. Log as `D-NASP-1NN`. Safety weakening goes to `BLOCKED.md`.

- **D-NASP-01 Branch.** Work continues on `feature/nas-v1` on top of `4b992a4`. Never push. The owner merges after the hardware rows pass.
- **D-NASP-02 Refuse, don't warn.** The Deduplicate network warning (`NetworkDestinationAdvisory`) was never rendered and Trash on SMB is unverified (ADR-NAS-04). Deduplicate refuses non-local folders at the picker, the history shortcut, the scan entry and inside the engine. Refusal is a product decision recorded in the Round 3 review and `FINAL_REPORT` item 1.
- **D-NASP-03 Unknown is refused.** `NASVolumeKind.unknown` (statfs failed) is refused like the CLI does. External USB/Thunderbolt drives classify as `.local` (`MNT_LOCAL` set) and stay allowed.
- **D-NASP-04 Message depends on the flag.** The refusal mentions NAS Library only when `NASCapability.isEnabled` is true, so a release build with the flag off never points at a hidden tab.
- **D-NASP-05 Leave the advisory in place.** `networkAdvisory` in `NativeDeduplicateEngine` becomes unreachable for remote folders but is not removed in this plan (surgical change). Follow-up card in the README backlog is not needed; note it in `PROGRESS.md` Log.
- **D-NASP-06 Validate timeout scope.** Only the `observe` call in `validate` gets the 2-second gate; bookmark resolution stays main-actor (it does not touch the network for a stale bookmark in practice; if H5 shows otherwise the owner reopens D-NAS-124).
- **D-NASP-07 Flag flip is owner-only.** The release value at `NASModels.swift:15–16` is edited by Nishith after `EVIDENCE_LEDGER.md` rows H1–H8 read `pass-hardware`; the exact edit and the docs lines to update are listed there. Agents never edit it.
- **D-NASP-08 Strings.** New and existing NAS literals get English catalog keys at G2 via `add_xcstrings_keys.py`; this supersedes D-NAS-51's "no hand-edit" for the orchestrator only, because no extraction script exists. Translations are owner work.
- **D-NASP-09 Invariant tags.** Refusal tests are tagged `// AGENTS-INVARIANT: 12` (Trash-only) because the refusal exists to keep deletes on volumes where macOS Trash is verified. No new invariant.
- **D-NASP-10 Test seam for AppState.** `AppStateHarness.makeAppState` passes `NASVolumeClassifier { _ in nil }`-style stubs through the new init parameter; a `NASStatfsSnapshot` with `fileSystemType: "smbfs"` yields `.remote`, `"apfs"` with `MNT_LOCAL` yields `.local` (see `NASVolumeClassifier.swift:97–104`).

## Runtime decisions
- **D-NASP-101 Scan refusal placement (WP-01).** In `NativeDeduplicateEngine.scan` the refusal sits after the existing `activeLease?.release()` and immediately before `DestinationOperationLock.acquire`. C-02 says "after the guard, before acquire"; releasing a prior lease writes nothing, and checking earlier would keep a stale lease across a refused scan.
- **D-NASP-102 AppState message tests pin the flag (WP-01).** The three AppState refusal tests set `NASCapability.isEnabledOverride = false` (DEBUG only, restored with `defer`) so `transientErrorMessage` is compared to the exact C-01 flag-off text. The history-shortcut refusal shows the C-01 text, not the "no longer available" copy.
- **D-NASP-103 Harness classifier default is local (WP-01).** `AppStateHarness.makeAppState` defaults `volumeClassifier:` to `AppStateHarness.localClassifier` (apfs, `MNT_LOCAL`) so existing `/Volumes/...` fixture paths are not refused; `AppStateHarness.remoteClassifier` (smbfs) is opt-in. Both are `nonisolated static let`.
- **D-NASP-104 WP-02 grep form.** The `execute` signature is multi-line, so the plan's literal grep `public func execute(queuedJobs` never matches. Equivalent checks used: `grep -n "public func execute($"` prints nothing; `grep -n "func execute($"` prints one line (447).
