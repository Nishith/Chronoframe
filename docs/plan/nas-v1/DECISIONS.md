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
