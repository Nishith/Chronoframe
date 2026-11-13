# NAS v1 decisions

Status: approved plan decisions for `docs/NAS_REQUIREMENTS.md` v1.0. These resolve every gap the requirements leave open for the v1 P0 slices (0, 1a, 1b, 1c). Requirements IDs (`NAS-…`, `T…`, `ADR-NAS-…`) refer to that document.

## Tie-break rule for new gaps

When a gap appears that no contract or decision covers, choose the option that, in this order:
1. keeps every AGENTS.md safety invariant and every requirement in `docs/NAS_REQUIREMENTS.md`;
2. changes the fewest existing files and lines;
3. copies an existing pattern from the reference file the work package names;
4. fails closed (refuse, mark unresolved, or stop) rather than guess.

Log it under "Runtime decisions" at the bottom as `D-NAS-1NN` with the WP ID, the options, and the choice. Never use the tie-break to weaken a safety rule; log that case in `BLOCKED.md` instead.

## Scope and process

- **D-NAS-01 Branch.** Work happens on `feature/nas-v1`, created from `codex/stable-invariant-ids` (commit `e257003`, which is `main` 566b6ba plus the permanent `INV-NN` labels). Never push. The owner opens the pull request.
- **D-NAS-02 Plan location.** Plan files live in `docs/plan/nas-v1/`. The root `AGENTS.md` and `CLAUDE.md` stay authoritative project memory; this plan adds `NAS_AGENT_RULES.md` instead of replacing them.
- **D-NAS-03 Checkout hygiene.** The checkout may hold unrelated untracked marketing files and a modified `.gitignore`. Agents never stage, stash, restore or delete them. Stage explicit paths only; `git add -A` and `git add .` are forbidden.
- **D-NAS-04 Test placement.** Core tests go in `ui/Tests/ChronoframeAppCoreTests/` named `ChronoframeCoreNAS<Thing>Tests.swift`, matching the existing `ChronoframeCore*Tests` convention. App-layer tests go in `ui/Tests/ChronoframeAppTests/` named `NAS<Thing>Tests.swift`. CLI tests go in `ui/Tests/ChronoframeCLIKitTests/`.
- **D-NAS-05 No new XCUITests.** v1 adds no files under `ui/Xcode/UITests/`, so `project.pbxproj` is never edited. UI behavior is covered by App-layer unit tests plus manual screenshot evidence.
- **D-NAS-06 Feature flag.** The NAS workspace is behind `NASCapability.isEnabled` (C-01). Release builds return `false` until the owner records release Go. DEBUG builds enable it with `CHRONOFRAME_ENABLE_NAS=1` or `isEnabledOverride`.
- **D-NAS-07 Remote copy policy ships unflagged.** C-08 to C-11 tighten safety for every network destination and are not behind the flag. This intentionally changes current behavior: network copies always verify, refuse the placeholder rename fallback, and the CLI refuses network destinations. These are approved requirements (NAS-CPY-03, NAS-CON-06, ADR-NAS-03).
- **D-NAS-08 New invariants.** The orchestrator adds INV-27 (assessment read-only) and INV-28 (remote copy policy) to `AGENTS.md` at gate G2, with the exact text in `IMPLEMENTATION_PLAN.md`. Tests that cover them carry `// AGENTS-INVARIANT: 27` or `28`.

## Assessment engine

- **D-NAS-10 Separate engine.** Assessment uses the new `NASAssessmentScanner`, never `DeduplicateScanner`, because the latter writes `.organize_cache.db` into the root (NAS-DAT-01).
- **D-NAS-11 Hashing without touching the shared hasher.** `NASMeteredFileReader` reimplements the digest with `BLAKE2bHasher` and the same size prefix, and a parity test proves equality with `FileIdentityHasher`. `FileIdentityHasher.swift` is not edited (safety-critical shared code).
- **D-NAS-12 Resume model.** A new scan always re-enumerates (metadata only). Digests are reused from the immediately previous generation, whatever its outcome, when relative path, size, modification time (within 1 ms) and file ID all match. Directory cursors are never trusted (NAS-SCP-07).
- **D-NAS-13 Zero-byte files** are reported as "empty files", never read, never grouped, and excluded from H.
- **D-NAS-14 Dot-prefixed names** are skipped silently and not counted, as INV-15 already requires. AppleDouble `._` files and `.DS_Store` therefore never appear.
- **D-NAS-15 Synology containers** match `@eaDir`, `#recycle` and `#snapshot` as whole path components, case-insensitively. They are reported as exclusions and never traversed.
- **D-NAS-16 Nested mounts** are detected by a change in `st_dev` from the root and never traversed.
- **D-NAS-17 Exclusions are not gaps.** System containers, packages, links, special files and nested mounts are reported exclusions and do not make an assessment incomplete. Unreadable folders or files and unresolved candidates do.
- **D-NAS-18 Waiting for NAS.** A lost volume ends the scan with outcome `interruptedVolumeUnavailable`. There is no automatic retry loop; the user chooses Reconnect, which revalidates identity and starts a new generation that reuses digests (NAS-REC-04).
- **D-NAS-19 Concurrency.** Default two concurrent hashes, clamped to 1 to 8. No network-aware tuning in v1.
- **D-NAS-20 Retention.** Keep the latest two scan generations. Review choices and review state are never pruned.
- **D-NAS-21 Review choices** are keyed by content digest. A choice whose keeper path is no longer a member of that digest's current group is shown as stale and must be chosen again. Choices are never deletion approvals.
- **D-NAS-22 Root rules.** The selected root must be a real directory on a remote volume. A symlink root is refused. A local folder is refused with a pointer to Deduplicate.

## Identity and coordination

- **D-NAS-30 Identity tuple** is C-04: file system type, share name, root path relative to the mount, root and share-root file IDs, creation time and server host. Server host changes are ambiguous (user confirms) because DNS and IP aliases are common; everything else that changes is a mismatch.
- **D-NAS-31 A mismatch creates a new library.** Re-choosing a folder after a mismatch gets a new `libraryUUID`, so no review choices or trust carry over (NAS-CON-03).
- **D-NAS-32 Lease granularity.** The app-container lease is one per network share, keyed without the server host (C-10). Within one app installation, all Chronoframe mutations on a share are serialized. Over-serialization is accepted for v1.
- **D-NAS-33 Unknown means remote.** A volume that can't be classified is treated as remote for the copy policy, the lease and the CLI refusal. Classification walks to the nearest existing ancestor so a not-yet-created destination folder still classifies.
- **D-NAS-34 CLI refusal** happens at the very top of `CLI.run`, before revert dispatch, cache rebuild, engine creation or any lock (NAS-CON-06). A NAS source with a local destination stays allowed.

## Copy qualification (slice 1c)

- **D-NAS-40 No runtime profile registry.** "Qualified profile" is release evidence recorded in the evidence ledger, not app state. At runtime every remote primitive fails closed: unsupported no-replace rename aborts the run, and a failed flush fails the copy.
- **D-NAS-41 Flush.** Remote copies reopen the temporary file with `O_RDWR | O_CLOEXEC | O_NOFOLLOW` and try `F_FULLFSYNC`, falling back to `fsync` only on ENOTSUP, EINVAL or ENOTTY. The data is copied by `copyfile` by path, so the reopened descriptor is the temporary-file descriptor for ADR-NAS-03.
- **D-NAS-42 Verification is forced** for remote destinations; a run with verification off aborts before any job.
- **D-NAS-43 Metadata.** Remote copies skip `clonefile`, copy bytes with `COPYFILE_DATA`, then attempt `COPYFILE_STAT | COPYFILE_XATTR | COPYFILE_ACL` and only warn if that fails (NAS-CPY-09).
- **D-NAS-44 Journal mode.** Remote `.organize_cache.db` opens use rollback journaling (`DELETE`) with `synchronous=FULL`, verified by readback. A failed switch (for example, another connection holds the WAL) refuses the open. Sidecars are never deleted.
- **D-NAS-45 Capacity** keeps the existing per-file checks (NAS-SPC-03). No new capacity dashboard.

## Review UI (slice 1b)

- **D-NAS-50 Previews.** Only the per-group Load Preview button reads media for display. It renders the group's first member (sorted path) through the existing `ThumbnailRenderer` and caches by digest in memory. Nothing about previews is persisted except a request counter.
- **D-NAS-51 Localization.** New strings use the existing `Text(LocalizedStringKey(...), bundle: .module)` pattern with the C-13 copy as keys' English values. Do not hand-edit `.xcstrings` files.
- **D-NAS-52 One library at a time.** The workspace shows the first saved library. Managing several libraries is P1.

## Evidence

- **D-NAS-60 Hardware rows stay todo.** Rows that need the real Synology share, a signed build, VoiceOver, or the owner's network are `todo-hardware` until Nishith records the result. Agents never mark them pass.
- **D-NAS-61 Probe tool is local only.** `ChronoframeNASProbeTool` is a SwiftPM executable that CI builds but never runs against a share.

## Runtime decisions

(Append `D-NAS-1NN` entries here during implementation.)

- **D-NAS-101 (WP-01) statfs name clash.** Inside `NASVolumeClassifier` the contract's `statfs` property shadows the Darwin function. Options: rename the property (breaks C-02) or call the function from a private file-scope wrapper. Chose the private `callStatfs` wrapper; no public API change.

- **D-NAS-102 (WP-01) Mount-string parsing details.** C-02 rule 4 leaves edge order open. Chose: percent-decode the SMB share, then strip a trailing `/`; keep the raw string if decoding fails; drop the port at the first `:` after removing user-info (`@`) and `DOMAIN;`; IPv6 literal hosts are not handled (P1); the NFS branch applies only to `nfs` with a `:`; an empty NFS host is nil; one leading `/` is dropped from the NFS path. Any other value gives (nil, nil).

- **D-NAS-103 (WP-01) Unknown observation path.** `.unknown(observedPath:)` carries the original `url.path` (C-02 rule 1); the ancestor walk stops after trying `/`.

- **D-NAS-104 (WP-02) Mount-prefix match on a component boundary.** C-04 says strip the mount-point prefix. A plain string prefix would make `/Volumes/photo2/x` relative to `/Volumes/photo`. Chose: root equal to mount ⇒ ""; `hasPrefix(mount + "/")` ⇒ strip; trailing-slash mount tolerated; otherwise the full path without the leading `/` (the contract's own fallback), which can never equal a recorded relative path and so fails closed as a mismatch.

- **D-NAS-105 (WP-02) Root type check.** `observe` checks symlink first, then directory, returning nil for either; `liveLstat` derives both from `st_mode & S_IFMT`; birth time is `st_birthtimespec` seconds plus fractional nanoseconds, nil when ≤ 0.

- **D-NAS-106 (WP-02) Reason ordering.** `compare` collects reasons in C-04 rule order 1–9; ambiguous reasons (`missingShareName`, then `serverHostChanged`) are dropped whenever any mismatch reason exists.

- **D-NAS-107 (WP-03) Post-read mtime baseline.** C-05 step 5 says "mtime differs by ≥ 0.001" without a baseline. Chose post vs the pre-read descriptor mtime (detects change during the read; pre is already within 1 ms of expected).

- **D-NAS-108 (WP-03) Reader seams and counters.** `SystemCalls.init(open:fstat:read:close:lastError:)` in contract property order with escaping `@Sendable` closures. A nil `fstat` (pre or post) gives `.readFailed` with errorCode nil. `readCalls` counts every call including EINTR and the failing call.

- **D-NAS-109 (WP-04) Store anchor errors.** A symlinked store file throws `DestinationMetadataUnsafeError` unwrapped, copying the `OrganizerDatabase` anchor sequence (C-06). SQLite failures, directory creation and use-after-`close()` throw `storeFailed`. Other POSIX errors from the anchor propagate as-is, as in `OrganizerDatabase`; the App layer (WP-10) maps them to plain text.

- **D-NAS-110 (WP-04) Store details C-06 leaves open.** `markCandidates` reclassifies only `notCandidate`/`pending`/`emptyFile` rows and never reverts `hashed`/`unresolved` (the scanner calls it before filling reused digests). `pruneGenerations` clamps a negative count to 0. `latestGeneration` includes running generations (D-NAS-12 reuses whatever the outcome). An `NSLock` serializes public methods so multi-statement transactions never interleave. Summary JSON `{}` (a running scan) decodes to defaults. `init` creates the store's parent directory.

- **D-NAS-111 (WP-05) NFC collisions fail closed.** Two on-disk names that normalize to the same NFC relative path can't both be stored (items are keyed by NFC path). Options: merge silently, store the raw name, or report. Chose: keep the first in sorted order, report the other as `unreadableItem`, so the scan ends `completedWithGaps` (NAS-SCP-08: visible, never silently merged). NFD-only names are stored under their NFC path and hashed through an in-memory NFC→on-disk path map.

- **D-NAS-112 (WP-05) Scanner preflight and lifecycle.** The scanner does not enforce remote-only (C-07 has no classifier seam); the workspace store refuses local folders (D-NAS-22, WP-10). `stateURL` is also refused when its resolved (symlink-free) parent reaches the root. A refused run finishes the stream with the error before any event, activity or generation. Activity ends before the stream finishes on every path; a consumer that stops iterating cancels the run. A store failure mid-scan closes the generation as failed and rethrows. Progress throttling uses `ProcessInfo.systemUptime`; `hashingProgress.total` counts reused candidates.

- **D-NAS-113 (WP-06) Run-fatal job state.** C-08 item 8 doesn't name the interrupted job's status. Chose: the job keeps status `pending` with mutation state `.failed` (not counted as failed), so a resumed run retries it. Known edge: if a foreign file already sits at that job's requested path, recovery may raise a false "manual recovery" prompt; it never deletes, so this fails safe. `copyData` is a stored default closure, so `.system` gets `COPYFILE_DATA` implicitly and existing three-argument strategy inits compile unchanged. The metadata warning shows the requested destination path, not the `.tmp` path.

- **D-NAS-114 (WP-06) Run-fatal abort is also emitted as an issue.** `abortRunFatally` sets `abortReason` (C-08 item 8) and also emits one `.error` RunIssue with the same text, because `SwiftOrganizerEngine` shows only a generic failed/skipped count and ignores `abortReason`; without it the user would see "0 failed" and no reason.

- **D-NAS-115 (WP-06) `execute(queuedJobs:)` stays policy-less.** The public `execute(queuedJobs:…)` builds its context with the `.local` default. It has no production callers (only tests; production uses `executeQueuedJobs` from `SwiftOrganizerEngine`), and C-08 says every line outside items 1–10 stays byte-identical. Options: wire the policy in (≈8 lines, outside the contract) or leave and flag. Chose: leave, flagged in FINAL_REPORT for the owner. Any future production caller must resolve the policy first, or the method should be removed.

- **D-NAS-116 (WP-07) Journal switch refused by SQLITE_BUSY.** When another connection holds the WAL, `PRAGMA journal_mode=DELETE` fails immediately with SQLITE_BUSY and returns no mode string (busy_timeout does not apply). Chose: treat a failed pragma as an unconfirmed switch — query `PRAGMA journal_mode;` (fallback "unknown"), close, throw `journalModeUnavailable(<mode>)`. Fails closed; nothing on disk is touched.

- **D-NAS-117 (WP-07) Leftover `-shm` after converting an idle WAL database.** SQLite leaves `-shm` after leaving WAL and Chronoframe never deletes sidecars (D-NAS-44), so `testRollbackDeleteConvertsIdleWALDatabase` asserts mode `delete`, synchronous 2 and no `-wal`, not the absence of `-shm`. A fresh rollback database leaves none of `-wal`/`-shm`/`-journal` (asserted separately). The C-09 message lives in `OrganizerDatabaseError.errorDescription`; `UserFacingErrorMessage` already routes that type to `errorDescription`, so no WP-10 mapping is needed for it. The rollback branch returns early so the WAL block stays byte-identical.

- **D-NAS-118 (WP-08) A named profile's destination is always classified.** C-11 orders "`options.destinationPath`, else the profile's destination", but the engine ignores `--dest` when a profile is named (`RunConfiguration.resolving(profile:)` overwrites it), so `--profile nas --dest /tmp/x` would pass the refusal and then write to the NAS (INV-28 fail-open). Tie-break rule 1. Chose: for a non-revert run with a profile name, classify the profile's own destination (engine lookup: first profile with that name) and any non-empty `--dest` (rebuild-cache clears that one); refuse if either is non-local, naming the profile's path first. Profile not found → no refusal on that part (existing errors surface). A `loadProfiles()` error propagates (fail closed). Revert and no-profile paths follow C-11 as written.

- **D-NAS-119 (WP-08) Nothing to classify.** With no `--dest`, no profile and no revert receipt the resolver returns nil, so existing usage/`destinationMissing` errors surface before any write (reviewer traced every path; no default profile or env-derived destination exists).

- **D-NAS-120 (WP-09) P07 holds an EXCLUSIVE writer.** C-14 says `BEGIN IMMEDIATE`, but in rollback-journal mode that takes only RESERVED, which never blocks readers, so the C-14 acceptance (≥ 1500 ms at timeout 30000, SQLITE_BUSY at timeout 0) is unreachable. Chose `BEGIN EXCLUSIVE` held 2 s (C-14 erratum); the detail text says so.

- **D-NAS-121 (WP-09) Probe and parity details.** Results keep `{id, status, errorCode?, detail}`; metrics go in a `key=value` detail string. P02 `unsupported` = F_FULLFSYNC ENOTSUP/EINVAL/ENOTTY with fsync OK. P03/P04 `unsupported` on ENOTSUP/EINVAL/ENOSYS; P04 passes only on EEXIST with the existing digest unchanged and the source still present. P06 passes only when the OrganizerDatabase connection reads back `delete` and synchronous 2. Cleanup unlinks only names the probe registered (plus its own db sidecars) and then `rmdir`; leftovers add a CLEANUP error and exit 3. `NASProbe.init` has public seams (classifier, trashItem, writerHoldSeconds); P08 runs only with `--trash`. Parity exits 2 when `parity == false`; its exhaustive walk mirrors scanner inclusion rules and drops unresolved items; state-inside-root is checked symlink-resolved and case-insensitively before anything is created. Corpus: at least 16 files, duplicate percent 0–90, destination must be empty, manifest refused inside it.

- **D-NAS-122 (WP-10) Test seams stay internal.** `NASPaths.applicationSupportOverride` (nil in production) and `SwiftNASAssessmentEngine.init(storeURL:)` are internal, used via `@testable`. `NASStartupTests` lives in `NASLibraryRegistryTests.swift`.

- **D-NAS-123 (WP-10) Reconnect probe off the cooperative pool.** `validatedStartPath` runs the observe closure on `DispatchQueue.global` raced against a timer with a once-only continuation, so a blocked `stat` neither pins a Swift-concurrency thread nor delays the result past the timeout. Its closures are `@escaping @Sendable`.

- **D-NAS-124 (WP-10) Probe placement (C-12 erratum).** C-12 lists "picker start via NASReconnectProbe" under `reconnect()`, but `reconnect()` opens no picker. The probe chooses the picker's start path in `chooseLibrary()` (`allowNetworkStart: true`); `reconnect()` only revalidates the saved library. Known gap: `validate()` resolves the bookmark on the main actor and `observe` has no timeout, so a dead share can leave the store in `checkingConnection` — tracked as hardware row H5.

- **D-NAS-125 (WP-10) Re-choosing a folder.** Against the current library: `.same`/`.remounted` keep the UUID; `.ambiguous` goes to `needsIdentityConfirmation` (nothing saved until `confirmIdentity()`, which keeps the UUID and choices; assessment refused meanwhile, D-NAS-30); `.mismatch` gets a new UUID (D-NAS-31), the new record is upserted and the old one removed from the registry (one library at a time, D-NAS-52). The old `assessment.db` stays on disk.

- **D-NAS-126 (WP-10) Saved outcomes on load.** A saved `interruptedVolumeUnavailable` shows `incompleteAssessment` after a successful reconnect; only a live `.finished` with that outcome goes to `waitingForNAS`. A saved `running` outcome (crashed scan) shows as incomplete.

- **D-NAS-127 (WP-10) Plain error text.** Any `NSPOSIXErrorDomain` error the store shows (D-NAS-109) becomes "Chronoframe couldn't open its assessment data on this Mac. Nothing on the NAS was changed."; a folder that can't be observed (not a directory, or a link) shows "Chronoframe can't use this folder. Choose a regular folder on a network share, not a link. Nothing was changed." Everything else goes through `UserFacingErrorMessage`. Scanner `unresolvedCandidate` details (raw reason text) are rewritten into plain sentences when a snapshot loads.

- **D-NAS-128 (WP-10) Unclassified volumes are refused.** Any observation whose kind is not `.remote`, including `.unknown`, is refused with the C-13 `error.notNetwork` text; nothing is saved.

- **D-NAS-129 (WP-10) Review edits only on results.** `select`, `chooseKeeper` and `requestPreview` act only in `completeAssessment`/`incompleteAssessment`; entering `differentFolder` clears the snapshot, selection and preview requests (NAS-CON-03). `select`/`requestPreview` persistence is best effort; `requestPreview` counts once per digest; `chooseKeeper` ignores non-members and shows `failed` on a save error (results hidden — owner follow-up). Snapshot loading and observation run off the main actor with an epoch counter dropping stale results; `selectedDigest` is stored in `ReviewState` under "selectedDigest".

- **D-NAS-130 (WP-11) Copy C-13 does not fix.** Ready banner "Ready to assess. Chronoframe reads this library to find identical copies and changes nothing on the NAS."; phase labels "Looking through your folders…", "Comparing files that look alike…", "Grouping identical copies…"; "Folder summary"; preview failure "A preview couldn't be made for this file."; sidebar subtitle "Assess a library on your NAS". Not added to `.xcstrings` (D-NAS-51). `incompleteAssessment(.cancelled)` shows state.cancelled, every other outcome state.incomplete; `noLibrary` shows empty.body under empty.title.

- **D-NAS-131 (WP-11) UI wiring details.** `SidebarView` observes `nasWorkspaceStore` so the running spinner (C-13 isRunning switch) updates. `AppState.cancelRun` stops the NAS store for `.nasLibrary` (compiler-forced case). `viewDidAppear` loads the saved library only from `noLibrary`. Buttons per state: differentFolder → Choose Folder; waitingForNAS → Reconnect, Choose Folder; needsIdentityConfirmation → This Is the Same Library, Choose Folder; ready/results → Assess Library or Assess Again, Choose Folder; assessing → Stop; failed → Reconnect (if a library exists), Choose Folder. Accessibility labels start with the visible title (the start button's label follows Assess Library/Assess Again). The `.failed` banner renders `Text(verbatim:)`.

- **D-NAS-132 (WP-11) Preview path containment.** The store's resolved root is private, so `previewURL` builds mountPoint + rootRelativePath (bookmark path fallback) + the first sorted member, standardizes both, and returns nil unless the result is the root or under root + "/" (a `..` member from a tampered local DB never renders). It renders only after `store.requestPreview` recorded the digest.

- **D-NAS-133 (WP-11) No NASStartup under XCTest.** `RuntimePaths.applicationSupportDirectory()` ignores `$HOME`, so test-built `AppState`s would create `nas/leases` in the real home. `AppState` skips `NASStartup.configure()` when `XCTestCase` is loaded (same detection the file uses for the status item); `NASStartup` itself is tested directly. An empty `~/Library/Application Support/Chronoframe/nas/leases` created by earlier WP-11 test runs was left in place (the app creates it on first launch anyway).

- **D-NAS-134 (WP-12) Lease folder failure fails closed.** CONTRACTS.md C-12 and the `NASStartup` comment imply a fallback to the in-destination lock when `nas/leases` can't be created. In code `configure()` sets `leaseDirectory` regardless, and `acquire(lockFileURL:)` rethrows its own directory-creation failure, so a network-destination change does not start. Chose to keep the code (fail closed) and document it; the contract wording is an erratum.

- **D-NAS-135 (WP-12) Docs state the Deduplicate gap.** The existing Deduplicate workspace only warns on a network folder and can move files to the Trash there (`DeduplicateEngine.swift:101`, `DeduplicateExecutor.swift:582`). That is pre-existing behavior outside NAS v1 scope, so docs say "NAS Library offers no cleanup" and state the Deduplicate fact plainly. Whether Deduplicate should refuse network folders is an owner decision (FINAL_REPORT).

- **D-NAS-136 (G3) Probe tool exempt from the Xcode source-list test.** `BuildPipelineTests.testSwiftAppSourcesAreListedInXcodeProject` requires every `ui/Sources` file to be in `project.pbxproj` except SwiftPM-only tool targets, which it lists by name. WP-09 added `ChronoframeNASProbeTool` (SwiftPM-only by D-NAS-61, never in the app) but its owned paths didn't include this test. Options: add the probe to `project.pbxproj` (forbidden, D-NAS-05), log BLOCKED and stop G3, or add the target name to the existing exemption list beside `ChronoframeVideoCalibrationTool`. Chose the exemption (one token, same pattern, test intent unchanged: app sources still must be in the project), committed separately as WP-09b.

- **D-NAS-137 (post-G3) No fixedSize on wrapping workspace text.** A `.fixedSize(horizontal: false, vertical: true)` banner gave the NAS workspace a 1,692 pt minimum height; with `.windowResizability(.contentMinSize)` the split view overflowed the window and the whole window looked blank. Removed it; two tests bound the empty and results layouts' minimum heights to `DesignTokens.Window.mainMinHeight`.

- **D-NAS-138 (PR #266 review, item 1) Verification-off refusal moves into `prepare`.** `TransferExecutor` refused a network transfer with Verify Copies off only after `context.start()`, so the refusal left an ABORTED receipt. Options: gate in `prepare` after the rename probe (next to `copyDestinationQualifier.check`), or before the lease. Chose before the lease and before the probe: `NASCopyDestinationQualifier.checkVerification` only classifies, so a refused transfer writes nothing at all (no lock file, no `.organize_logs`, no probe file). Only `.transfer` is refused; a preview with verification off plans and writes nothing to be unsafe, so it still runs and the user meets the refusal when they start the transfer. The `TransferExecutor` check stays as a backstop for engines that skip `prepare`. The verification value is `preflight.configuration.verifyCopies` (profile-resolved), the same value the executor receives.

- **D-NAS-139 (PR #266 review, item 2) Pruning always keeps the latest finished generation.** D-NAS-20 keeps the latest two generations, but the scanner prunes after every scan, so two cancelled, interrupted or failed scans deleted the only complete one. Options: prune only after a complete scan, or keep the latest finished generation in addition to the latest N. Chose the latter, inside `pruneGenerations` so every caller is covered. "Finished" means outcome `complete` or `completedWithGaps` (the scan walked everything it could reach); a `running` row never counts. With no finished generation the behavior is unchanged. A newer finished generation supersedes the older one, which then ages out normally. The kept set is a subquery with no NULL row, so `NOT IN` can't turn into "delete nothing". Review choices and review state are still never pruned. Erratum to C-06's `pruneGenerations` comment.
