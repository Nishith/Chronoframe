# Chronoframe — Top 10 Highest-Impact Improvements

*Generated: 2026-05-10 | Review type: NEW-BUILD*

---

## Executive Summary

Chronoframe is a well-engineered, safety-first application with strong foundations: atomic I/O, content-based identity, parameterized SQL, a 235-method test suite with real I/O (no mock theater), and explicit failure budgets. The architecture is sound for its scope.

**Two P1 findings require prompt attention** — both involve file deletion safety:
1. `cleanup_tmp_files()` deletes *any* `.tmp` file in the destination directory, including files from other applications (DaVinci Resolve, Final Cut Pro, video editors), with no warning.
2. `revert_receipt()` will delete files at any path the receipt specifies, with no validation that the path is inside the destination directory.

The remaining eight findings are P2 quality and reliability improvements: an unlocked SQLite read, missing CI gates (coverage + dependency audit), log rotation, global mutable state, cross-platform filename sanitization, asymmetric copy verification, and a stale audit receipt timestamp.

---

## Top 10 Findings

---

### 1. `cleanup_tmp_files()` deletes any `.tmp` in the destination — including from other applications

- **Category:** Reliability / Data integrity
- **Priority:** P1
- **Effort:** S (1–8 hours)
- **Confidence:** high

**Problem:** Every Chronoframe run begins by calling `cleanup_tmp_files(dst)`, which walks the entire destination directory and deletes every file ending in `.tmp`. There is no check that the file was created by Chronoframe.

**Why it matters:** A user who organizes photos into a directory also used by DaVinci Resolve, Final Cut Pro, or any video/audio application that stores scratch `.tmp` files will silently lose those files on every Chronoframe run. The operation is immediate and irrecoverable (no trash, no backup).

**Evidence (verified):**
- `chronoframe/io.py:55-68`:
  ```python
  for root, dirs, fnames in os.walk(dst_dir):
      dirs[:] = [d for d in dirs if not d.startswith('.')]
      for fname in fnames:
          if fname.endswith('.tmp'):           # line 61 — no Chronoframe filter
              path = os.path.join(root, fname)
              os.remove(path)                  # line 65 — silent hard delete
  ```
- `ui/Sources/ChronoframeCore/TransferExecutor.swift:202-226` has the identical issue:
  ```swift
  guard fileURL.lastPathComponent.hasSuffix(Self.orphanedTemporarySuffix) else { continue }
  FileManager.default.removeItem(at: fileURL)  // any .tmp, no pattern filter
  ```
- `chronoframe/core.py:449-453` calls `cleanup_tmp_files(dst)` unconditionally at startup

**Root cause:** Chronoframe's own `.tmp` files (`2024-01-15_001.jpg.tmp`, `io.py:119`) have no unique prefix or identifier tag that distinguishes them from other applications' temporary files.

**Attack / Failure Scenario (P1 — reachable today without prior compromise):**
1. User has `/Volumes/NAS/Media/` as both their Chronoframe photo destination and a working directory for DaVinci Resolve (scratch files like `Timeline_Export.tmp`)
2. User launches Chronoframe, selects `/Volumes/NAS/Media/` as destination
3. Before any photos are transferred, `cleanup_tmp_files("/Volumes/NAS/Media/")` runs (core.py:450)
4. All `.tmp` files from DaVinci Resolve are silently deleted via `os.remove()`
5. Resolve project is unrecoverable; no undo available

**Risks if unchanged:** Permanent, unrecoverable data loss for any user whose destination directory is shared with another application that uses `.tmp` scratch files. This is a common pattern for media professionals.

**Recommended change:** Scope cleanup to Chronoframe's own naming pattern. Chronoframe's temp files always follow the final destination filename + `.tmp` suffix (e.g., `2024-01-15_001.jpg.tmp`). Add a regex guard:

```python
# io.py — add above cleanup_tmp_files()
import re
_CHRONOFRAME_TMP_RE = re.compile(
    r'^(?:\d{4}-\d{2}-\d{2}|Unknown)_\d+.*\.tmp$'
)

def cleanup_tmp_files(dst_dir):
    cleaned = 0
    for root, dirs, fnames in os.walk(dst_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for fname in fnames:
            if fname.endswith('.tmp') and _CHRONOFRAME_TMP_RE.match(fname):
                try:
                    os.remove(os.path.join(root, fname))
                    cleaned += 1
                except OSError:
                    pass
    return cleaned
```

Apply equivalent regex guard in `TransferExecutor.swift:cleanupTemporaryFiles()`. Also cover the Swift UUID-suffix pattern (`YYYY-MM-DD_NNN<ext>.<UUID>.tmp` visible at TransferExecutor.swift:664).

**Structural Guard:** Extend `TestCleanupTmpFiles` with a case that creates `unrelated_project.tmp` in the destination, runs cleanup, and asserts the file still exists. This test must fail before the fix and pass after.

**Expected impact:** Eliminates silent collateral deletion; zero behavior change for normal Chronoframe temp files.

**Tradeoffs:** The regex must be kept in sync with Chronoframe's naming conventions. If a future naming change is made (e.g., adding a prefix), the cleanup pattern must be updated.

**Dependencies:** None. Ship independently.

**Suggested owner:** Backend

---

### 2. `revert_receipt()` deletes files at arbitrary paths specified in the receipt

- **Category:** Security / Data integrity
- **Priority:** P1
- **Effort:** S (1–8 hours)
- **Confidence:** high

**Problem:** `revert_receipt()` reads `dest` paths from a JSON receipt file and calls `os.remove(dst)` on any path that hash-matches. There is no validation that the path is within the destination directory. A crafted or accidentally modified receipt can cause deletion of files anywhere the user has write access.

**Why it matters:** A local attacker (or a corrupted/shared receipt) can cause arbitrary file deletion. The BLAKE2b hash check is a meaningful mitigation — an attacker must know the target file's hash to exploit this. But (1) local attackers can compute any file's hash trivially, and (2) users sometimes share receipts for debugging, not knowing they could be weaponized.

**Evidence (verified):**
- `chronoframe/core.py:338-346`:
  ```python
  for item in transfers:
      dst = item.get("dest")           # raw path from JSON receipt
      expected_hash = item.get("hash")
      if dst and os.path.exists(dst):
          current_hash = fast_hash(dst)
          if current_hash == expected_hash:
              os.remove(dst)           # deletes file at any path if hash matches
  ```

**Root cause:** No path prefix validation against the destination root before deletion. The receipt is trusted entirely.

**Attack / Failure Scenario (P1 — requires crafted receipt, local access):**
1. Attacker has local filesystem access (same user account or physical access)
2. Attacker creates a JSON file with `{"schemaVersion": 2, "transfers": [{"source": "", "dest": "/Users/victim/Documents/tax_return.pdf", "hash": "<blake2b of tax_return.pdf>"}]}`
3. Attacker places this file in a directory the victim controls
4. Victim runs `chronoframe --revert /path/to/crafted_receipt.json`
5. `os.remove("/Users/victim/Documents/tax_return.pdf")` is called — file permanently deleted

**Risks if unchanged:** Privilege escalation to arbitrary file deletion within the user's filesystem if a crafted receipt is passed. For a file organizer run by non-technical users on precious media, this is a significant trust violation.

**Recommended change:**
```python
# core.py — add to revert_receipt() after loading data
receipt_abs = os.path.abspath(receipt_path)
logs_dir = os.path.dirname(receipt_abs)
dest_root = os.path.dirname(logs_dir)
dest_prefix = os.path.normpath(dest_root) + os.sep

for item in transfers:
    dst = item.get("dest")
    if not dst:
        continue
    dst_abs = os.path.normpath(os.path.abspath(dst))
    if not dst_abs.startswith(dest_prefix):
        emit_json("error", message=f"Receipt path outside destination boundary: {dst}")
        console.print(f"[red]Refusing to revert path outside destination: {dst}[/red]")
        failed_count += 1
        progress.advance(task_id)
        continue
    # existing hash-check and os.remove logic follows
```

Also apply in `RevertExecutor.swift`.

**Structural Guard:** Add `TestRevertReceiptPathEscape` — creates a receipt with `dest` pointing to a file outside the destination directory, asserts `revert_receipt()` does not delete it, and asserts `failed_count == 1`.

**Expected impact:** Eliminates arbitrary file deletion; correct receipts (all `dest` paths inside `<dest>/.organize_logs/../../`) are unaffected.

**Tradeoffs:** Users who have moved receipt files to a different location must pass a `--dest` flag override to explicitly declare the boundary. Add `--dest` support to `revert_receipt()` for this case.

**Dependencies:** None. Ship together with Finding 1.

**Suggested owner:** Backend / Security

---

### 3. `get_cache_dict()` and `get_pending_jobs()` read SQLite without the threading lock

- **Category:** Reliability / Data integrity
- **Priority:** P2
- **Effort:** XS (< 1 hour)
- **Confidence:** medium

**Problem:** All write methods in `CacheDB` use `with self._lock:`, but the two read methods do not. With `check_same_thread=False` and a single SQLite connection shared across threads, concurrent reads during a write commit can produce indeterminate cursor state.

**Why it matters:** The ThreadPoolExecutor for hashing (core.py:535) runs concurrently with `get_cache_dict()` calls (core.py:532) during source indexing. A `save_batch()` commit during an ongoing cursor iteration could leave `get_cache_dict()` returning partial data, causing files to be re-hashed unnecessarily or hash index entries to be silently dropped.

**Evidence (verified):**
- `chronoframe/database.py:47-49` — no lock:
  ```python
  def get_cache_dict(self, type_id):
      cur = self.conn.execute("SELECT path, hash, size, mtime FROM FileCache WHERE id = ?", (type_id,))
      return {row[0]: {"hash": row[1], "size": row[2], "mtime": row[3]} for row in cur}
  ```
- `chronoframe/database.py:72-74` — no lock:
  ```python
  def get_pending_jobs(self):
      cur = self.conn.execute("SELECT src_path, dst_path, hash FROM CopyJobs WHERE status = 'PENDING'")
      return cur.fetchall()
  ```
- All write methods at lines 54, 60, 68, 77, 85, 94, 103 use `with self._lock:`

**Root cause:** Asymmetric locking — writes locked, reads not.

**Risks if unchanged:** Low probability of actual failure (Python GIL and SQLite WAL mode both reduce risk), but it is a correctness bug. If triggered, it would cause silent cache misses (extra work, not data loss). Harder to detect because symptoms are performance degradation, not errors.

**Recommended change:**
```python
def get_cache_dict(self, type_id):
    with self._lock:
        cur = self.conn.execute("SELECT path, hash, size, mtime FROM FileCache WHERE id = ?", (type_id,))
        return {row[0]: {"hash": row[1], "size": row[2], "mtime": row[3]} for row in cur.fetchall()}

def get_pending_jobs(self):
    with self._lock:
        cur = self.conn.execute("SELECT src_path, dst_path, hash FROM CopyJobs WHERE status = 'PENDING'")
        return cur.fetchall()
```

Note: `cur.fetchall()` inside the lock materializes results before releasing, preventing cursor lifetime issues.

**Structural Guard:** Add `TestCacheDBConcurrentReadWrite` that spawns 10 threads hammering `save_batch()` + `get_cache_dict()` simultaneously and asserts no `sqlite3.OperationalError` or `sqlite3.ProgrammingError`.

**Expected impact:** Correct concurrent behavior; no performance change (lock is uncontested in practice).

**Tradeoffs:** None. This is a pure correctness fix.

**Dependencies:** None.

**Suggested owner:** Backend

---

### 4. No `pip-audit` in CI; Python transitive dependencies have no lockfile

- **Category:** Supply chain
- **Priority:** P2
- **Effort:** XS (< 1 hour)
- **Confidence:** high

**Problem:** `requirements.txt` pins 4 direct dependencies with exact versions. However: (1) transitive dependencies are resolved fresh on each `pip install`, meaning a new transitive dep with a CVE could appear undetected, and (2) no CVE scanning tool runs in CI.

**Why it matters:** Supply-chain attacks increasingly target transitive dependencies. Even a small dependency tree (4 packages) can grow transitive deps that carry vulnerabilities. Without `pip-audit` in CI, a dependency-introduced CVE would be invisible until a user runs it manually.

**Evidence (verified):**
- `requirements.txt` — 4 pinned direct deps, no lockfile
- `.github/workflows/ci.yml:25-41` — `pip install -r requirements.txt` with no audit step

**Root cause:** `pip-audit` was never added to the CI pipeline; no lockfile tooling (pip-compile, poetry, uv) was introduced.

**Recommended change:**
```yaml
# .github/workflows/ci.yml — in python-tests job
- name: Audit Python dependencies
  run: pip-audit -r requirements.txt
```

Install `pip-audit` via `pip install pip-audit` in the same step as other deps, or add it to a dev-requirements file.

**Structural Guard:** CI `pip-audit` step fails the build on any known CVE in direct or transitive deps.

**Expected impact:** CVEs in the dependency tree become visible within 24 hours (CI runs on every PR).

**Tradeoffs:** `pip-audit` may have false positives for CVEs that don't affect Chronoframe's usage pattern. The `--ignore-vuln` flag can suppress specific accepted risks.

**Dependencies:** None.

**Suggested owner:** Backend / DevOps

---

### 5. No minimum Python coverage threshold enforced in CI

- **Category:** Testing / DX
- **Priority:** P2
- **Effort:** XS (< 1 hour)
- **Confidence:** high

**Problem:** CI runs the 235-method Python test suite but does not measure or gate on coverage percentage. New code paths can be added without tests and CI will still pass.

**Why it matters:** For a file organizer that operates on irreplaceable data, untested code paths are a direct data-loss risk. The existing test suite is excellent; adding a coverage gate locks in that quality level.

**Evidence (verified):**
- `.github/workflows/ci.yml:39-41`:
  ```yaml
  - name: Run Python test suite
    run: python -m unittest discover -s tests -t . -v
  ```
  No `coverage run`, no `coverage report --fail-under`.
- A `.coverage` file (53 KB) exists locally, proving coverage was measured but not wired to CI.

**Root cause:** Coverage reporting was set up locally but never integrated into CI.

**Recommended change:**
```yaml
- name: Run Python test suite with coverage
  run: |
    pip install coverage
    coverage run -m unittest discover -s tests -t . -v
    coverage report --fail-under=80
    coverage xml -o coverage.xml
- uses: actions/upload-artifact@v4
  with:
    name: python-coverage
    path: coverage.xml
```

Start with `--fail-under=80` after first measuring the actual baseline.

**Structural Guard:** The `coverage report --fail-under=N` line is itself the guard — CI fails if coverage drops below threshold.

**Expected impact:** Coverage regressions caught on every PR.

**Tradeoffs:** Choosing a threshold too high may create friction for legitimate refactors. Start at the measured baseline (likely ~85–90%) and adjust.

**Dependencies:** None.

**Suggested owner:** Backend

---

### 6. `.organize_log.txt` grows without bound — no rotation or size cap

- **Category:** Reliability / Operational
- **Priority:** P2
- **Effort:** S (1–8 hours)
- **Confidence:** high

**Problem:** `RunLogger` appends indefinitely to `<dest>/.organize_log.txt`. For users who run Chronoframe health scans or dry runs repeatedly (a common workflow), this file can grow to GB scale over months. On SD card or NAS destinations with limited capacity, this log growth could eventually cause the very `ENOSPC` condition that Chronoframe guards against during copies.

**Evidence (verified):**
- `chronoframe/core.py:54`:
  ```python
  self._fh = open(self.log_path, 'a')  # append mode, no size check
  ```
- `ui/Sources/ChronoframeCore/TransferExecutor.swift:103-105`:
  ```swift
  let newHandle = try FileHandle(forWritingTo: logURL)
  try newHandle.seekToEnd()  // append mode, no size check
  ```
- No rotation logic in either implementation.

**Root cause:** Log rotation was not implemented at initial design.

**Recommended change:**

Python (`RunLogger.open()` in core.py):
```python
def open(self):
    try:
        log_path = self.log_path
        max_bytes = 5 * 1024 * 1024  # 5 MB
        if os.path.exists(log_path) and os.path.getsize(log_path) > max_bytes:
            rotated = log_path + '.1'
            if os.path.exists(rotated):
                os.remove(rotated)
            os.rename(log_path, rotated)
        self._fh = open(log_path, 'a')
    except OSError:
        self._fh = None
```

Apply equivalent size-check-and-rotate logic before opening in Swift.

**Structural Guard:** Add `TestRunLoggerRotation` — write 6 MB of log entries and assert the active log file stays under 5 MB and a `.1` rotation file is created.

**Expected impact:** Log storage capped at ~10 MB (current + 1 rotated). No behavior change for normal operation.

**Tradeoffs:** Historical log entries older than the rotation boundary are lost. For a tool that also writes structured audit receipts, the plain-text log is secondary; this tradeoff is acceptable.

**Dependencies:** None.

**Suggested owner:** Backend

---

### 7. Global mutable `_json_active` and `console` — CLI is non-reentrant

- **Category:** Maintainability / Testing
- **Priority:** P2
- **Effort:** M (1–5 engineer-days)
- **Confidence:** high

**Problem:** `core.py` uses module-level global variables for output mode (`_json_active`) and the Rich console object (`console`). These are mutated in `main()` via `global`. This makes the CLI non-reentrant: calling `main()` twice in the same process (e.g., from test code) causes the second invocation to inherit output mode from the first.

**Evidence (verified):**
- `chronoframe/core.py:36`: `_json_active = False`
- `chronoframe/core.py:392-395`:
  ```python
  if args.json:
      global _json_active, console
      _json_active = True
      console = Console(quiet=True)
  ```
- The test suite explicitly resets `core._json_active = False` and `core.console = Console()` in setUp/tearDown to work around this.

**Root cause:** Global state was used as a shortcut to thread output mode through deeply nested function calls without parameter plumbing.

**Risks if unchanged:** Test isolation relies on explicit global resets. Adding new tests that forget the reset will produce confusing cross-test contamination. Any future embedding of Chronoframe as a library will be unsafe.

**Recommended change:** Introduce an `OutputContext` dataclass or pass `json_mode: bool, console: Console` as parameters:
```python
@dataclass
class OutputContext:
    json_mode: bool
    console: Console

def main(args=None, ctx: OutputContext | None = None):
    if args is None:
        args = parse_args()
    if ctx is None:
        ctx = OutputContext(
            json_mode=args.json,
            console=Console(quiet=True) if args.json else Console()
        )
    # replace all `_json_active` → `ctx.json_mode`, `console` → `ctx.console`
```

**Structural Guard:** `grep -rn "global _json_active\|global console" chronoframe/` fails in CI if any such lines exist.

**Expected impact:** CLI becomes reentrant; test isolation is guaranteed without manual global resets; future embedding is safe.

**Tradeoffs:** Large but mechanical refactor — every function that currently reads `_json_active` or `console` needs a parameter added. No behavior change.

**Dependencies:** Finding 5 (coverage gate) should land first so the refactor doesn't regress coverage.

**Suggested owner:** Backend

---

### 8. `_event_subpath()` injects raw APFS folder names into cross-platform destination paths

- **Category:** Reliability / Correctness
- **Priority:** P2
- **Effort:** XS (< 1 hour)
- **Confidence:** high

**Problem:** The `YYYY/Mon/Event` folder structure uses the source file's parent directory name as the event folder (`_event_subpath()`). On macOS APFS, folder names can contain characters that are invalid on FAT32/NTFS/ext4: `:`, `?`, `*`, `<`, `>`, `|`, `\`, `"`. When the destination is a NAS mounted as SMB or an external drive formatted FAT32, these characters silently cause copy failures or corrupt filenames.

**Evidence (verified):**
- `chronoframe/core.py:376-384`:
  ```python
  def _event_subpath(src_path, src_root):
      rel = os.path.relpath(os.path.dirname(src_path), src_root)
      if rel in ("", "."):
          return ""
      return os.path.basename(rel)  # raw APFS basename, no sanitization
  ```
- Used directly in path construction at `core.py:661, 677`:
  ```python
  parts = [dst, yyyy, mon] + ([evt] if evt else []) + [filename]
  dst_path = os.path.join(*parts)
  ```

**Root cause:** No sanitization step between APFS basename and destination path construction.

**Recommended change:**
```python
import re
_UNSAFE_PATH_CHARS = re.compile(r'[:<>|\\?*"]')

def _event_subpath(src_path, src_root):
    rel = os.path.relpath(os.path.dirname(src_path), src_root)
    if rel in ("", "."):
        return ""
    raw = os.path.basename(rel)
    return _UNSAFE_PATH_CHARS.sub('_', raw)
```

**Structural Guard:** Add `TestEventSubpathSanitization` covering inputs with `:`, `?`, `*`, `|` and asserting they are replaced with `_`.

**Expected impact:** Destination paths are valid on FAT32/NTFS/SMB. Source folder names are preserved with only unsafe characters replaced.

**Tradeoffs:** Slight deviation from the exact source folder name. Acceptable for cross-platform safety.

**Dependencies:** None.

**Suggested owner:** Backend

---

### 9. `verify_copy()` does not check that the source still matches the planned hash

- **Category:** Reliability / Data integrity
- **Priority:** P2
- **Effort:** S (1–8 hours)
- **Confidence:** high

**Problem:** `execute_jobs()` copies each file and optionally verifies the destination hash matches the hash computed during planning. However, it does not verify that the source file still has the same hash as when it was planned. If a source file is modified between planning and execution (e.g., a photo editor autosaves a new version), the verification fails, the destination copy is deleted, and the error message says "Verification failed" — not "source file changed." The user receives no actionable information.

**Evidence (verified):**
- `chronoframe/core.py:816-826`:
  ```python
  result = safe_copy_atomic(src_p, dst_p)
  if verify:
      if not verify_copy(src_p, result, h):  # h = hash from planning
          # deletes result, marks FAILED, no source check
  ```
- `chronoframe/io.py:29-35` — `verify_copy()` hashes only the destination:
  ```python
  def verify_copy(src_path, dst_path, expected_hash):
      actual = fast_hash(dst_path)
      return actual == expected_hash
  ```

**Root cause:** Verification is asymmetric: destination-to-plan, not source-to-destination-to-plan.

**Recommended change:** In `execute_jobs()`, before copying, verify the source still matches the planned hash:
```python
for src_p, dst_p, h in pending_jobs:
    try:
        current_src_hash = fast_hash(src_p)
        if current_src_hash != h:
            emit_json("warning", message=f"Source modified since planning, skipping: {src_p}")
            status_updates.append((src_p, 'SKIPPED'))
            continue
        result = safe_copy_atomic(src_p, dst_p)
        ...
```

This converts a confusing "verification failed" into a clear "source modified" skip — not a failure count.

**Structural Guard:** Add `TestExecuteJobsSourceModifiedBetweenPlanAndCopy` — plans a copy, modifies the source, runs execute, asserts the job is SKIPPED (not FAILED) and the destination is not corrupted.

**Expected impact:** Cleaner failure UX; no more "verification failed" on legitimate source-modified-after-planning scenarios.

**Tradeoffs:** Extra hash computation per file before copy. For large libraries, this adds ~10–20% to the copy phase time. Can be gated on `verify=True` to keep it opt-in.

**Dependencies:** None.

**Suggested owner:** Backend

---

### 10. Audit receipt `startedAt` and `finishedAt` are always identical

- **Category:** Reliability / Observability
- **Priority:** P2
- **Effort:** XS (< 1 hour)
- **Confidence:** high

**Problem:** `generate_audit_receipt()` captures `now = datetime.now().isoformat()` at receipt-write time and uses it for both `startedAt` and `finishedAt`. For a run that processes 100,000 photos over 4 hours, the receipt shows a 0-second duration. This makes receipts useless for debugging performance issues or estimating future run times.

**Evidence (verified):**
- `chronoframe/core.py:277-284`:
  ```python
  now = datetime.now().isoformat()     # line 277 — captured at receipt-write time
  payload = {
      ...
      "startedAt": now,                # line 283
      "finishedAt": now,               # line 284 — identical to startedAt
  ```

**Root cause:** `generate_audit_receipt()` doesn't receive a `started_at` parameter; `now` serves double duty.

**Recommended change:**
```python
# core.py — top of main()
run_started_at = datetime.now()

# Pass to generate_audit_receipt():
def generate_audit_receipt(jobs_executed, dest_path, *, started_at, status=...):
    finished_at = datetime.now()
    payload = {
        "startedAt": started_at.isoformat(),
        "finishedAt": finished_at.isoformat(),
        ...
    }
```

**Structural Guard:** Add `TestAuditReceiptTimestamps` — runs `execute_jobs()` with a small sleep, then asserts `startedAt < finishedAt` in the generated receipt.

**Expected impact:** Receipts gain meaningful duration data. No behavior change for file operations.

**Tradeoffs:** Minor API change to `generate_audit_receipt()`. Any callers (Python tests, Swift `RevertExecutor`) that use the timestamp fields will benefit.

**Dependencies:** None.

**Suggested owner:** Backend

---

## Scoring Table

Priority subtotal = SEV × LIK × BLAST × LEV (all 1–5, higher = worse)
Tie-break = EFF_INV × REV × CONF (higher = do it sooner)

| Rank | Finding | SEV | LIK | BLAST | LEV | **Priority** | EFF_INV | REV | CONF | **Tie-break** |
|------|---------|:---:|:---:|:-----:|:---:|:------------:|:-------:|:---:|:----:|:-------------:|
| 1 | cleanup_tmp_files deletes any .tmp | 4 | 3 | 4 | 4 | **192** | 2 | 1 | 3 | 6 |
| 2 | revert_receipt arbitrary path deletion | 4 | 2 | 4 | 4 | **128** | 2 | 1 | 3 | 6 |
| 3 | SQLite unlocked reads | 3 | 2 | 3 | 2 | **36** | 1 | 3 | 2 | 6 |
| 4 | No CI coverage threshold | 2 | 4 | 2 | 3 | **48** | 1 | 4 | 3 | 12 |
| 5 | No pip-audit / lockfile | 3 | 2 | 2 | 2 | **24** | 1 | 4 | 3 | 12 |
| 6 | Log file unbounded growth | 2 | 3 | 2 | 2 | **24** | 2 | 3 | 3 | 18 |
| 7 | Global mutable _json_active | 2 | 2 | 2 | 2 | **16** | 3 | 2 | 3 | 18 |
| 8 | _event_subpath raw folder names | 2 | 3 | 2 | 2 | **24** | 1 | 3 | 3 | 9 |
| 9 | verify_copy source not re-hashed | 2 | 2 | 2 | 2 | **16** | 2 | 3 | 3 | 18 |
| 10 | Audit receipt timestamps identical | 1 | 5 | 1 | 1 | **5** | 1 | 4 | 3 | 12 |

**Scoring axis definitions:**
- SEV: How bad is the worst-case impact? (1=annoyance, 5=permanent data loss)
- LIK: How likely is this to trigger for a real user? (1=theoretical, 5=common workflow)
- BLAST: How many users/files are affected when it triggers? (1=single file, 5=entire library)
- LEV: How much does fixing this reduce future risk? (1=local patch, 5=structural improvement)
- EFF_INV: Inverse of effort (5=XS, 1=XL) — prefer cheap fixes
- REV: How reversible is the impact? (1=irrecoverable, 5=trivially undone)
- CONF: Review confidence (1=low inference, 3=code read + grep verified)

---

## Recommended Execution Order

### Week 1 — Safety-critical (ship together)
1. **Finding 1** (`cleanup_tmp_files` scope fix) — P1, Effort S
2. **Finding 2** (receipt path boundary) — P1, Effort S

**Rationale:** Both are data-loss risks reachable by any user. The structural guards (failing tests for each) should be committed first, then the fixes make them green.

### Week 1–2 — CI gates (ship together, low effort)
3. **Finding 5** (pip-audit in CI) — P2, Effort XS
4. **Finding 4** (coverage threshold) — P2, Effort XS
5. **Finding 10** (receipt timestamps) — P2, Effort XS
6. **Finding 8** (_event_subpath sanitization) — P2, Effort XS

### Week 2–3 — Correctness and reliability
7. **Finding 3** (SQLite read locks) — P2, Effort XS
8. **Finding 6** (log rotation) — P2, Effort S
9. **Finding 9** (source hash pre-check) — P2, Effort S

### Month 2 — Architectural cleanup
10. **Finding 7** (global state refactor) — P2, Effort M

**Parallelism:** All items in the same week can be done in parallel by different PRs.

---

## Quick Wins (ship this week)

1. Add `with self._lock:` to `get_cache_dict()` and `get_pending_jobs()` — 2-line change, zero risk
2. Add `pip-audit -r requirements.txt` to CI python-tests job — 1-line change
3. Add `coverage run ... --fail-under=80` to CI python-tests job — 3-line change
4. Fix `_event_subpath()` to sanitize cross-platform-unsafe characters — 5-line change
5. Fix `generate_audit_receipt()` to accept `started_at` parameter — 10-line change

---

## What Works — Do Not Change

1. **Atomic copy pattern** (`io.py:119-124`): write → `fsync()` → `os.rename()`. The `fsync` before rename is essential on HFS+/APFS for crash safety and is correct. Do not remove it for "performance".

2. **Parameterized SQL throughout** (`database.py`): Every single query uses `?` parameter binding. Zero string interpolation in SQL. This is exactly right — don't introduce f-strings in SQL "for readability".

3. **Tenacity retry with explicit predicate** (`io.py:71-90`): The `_is_retryable_error()` predicate explicitly excludes `ENOSPC`, `ENOENT`, `EACCES`, `EPERM`, `EINVAL`. This is the correct design — non-retryable errors fail fast, preventing queue stalls on broken paths. Don't replace with a blanket OSError retry.

4. **Dual failure thresholds** (`core.py:26-28, 831-844`): `MAX_CONSECUTIVE_FAILURES=5` and `MAX_TOTAL_FAILURES=20` are well-calibrated. Too aggressive and a single bad source file aborts everything; too lenient and a failing destination fills the error log. The current values are correct.

5. **Content-based identity with size prefix** (`io.py:12-26`): `f"{size}_{h.hexdigest()}"` prevents hash collisions between files of different sizes that share hash values (impossible for BLAKE2b but the pattern is defense-in-depth). Keep the prefix.

6. **`yaml.safe_load()` everywhere** (`core.py:113, 413`): Prevents arbitrary Python object deserialization from profile YAML. Do not switch to `yaml.load()`.

7. **Real-I/O test suite** (`tests/test_chronoframe.py`): 235 methods hit real tempdir, real SQLite, and real file operations. The parity fixture tests (`test_parity_fixtures.py`) cross-validate Python and Swift logic. This is high-value testing — don't introduce mocks at the file I/O boundary.

---

## Changes to Avoid Right Now

1. **Migrating the Python backend to async/await**: The ThreadPoolExecutor model is simpler to test and reason about for I/O-bound work. Async would complicate cancellation and retry logic with minimal benefit.

2. **Replacing SQLite with a higher-level ORM**: The current queries are simple, correct, and parameterized. An ORM adds abstraction without solving any current problem.

3. **Adding a database migration system**: With only 4 tables and a local file, migrations would be over-engineering. Schema version checks are sufficient.

4. **Refactoring Swift app layer view code**: The UI views are not in scope for correctness findings — improvements here are pure UX and should be driven by user feedback, not this review.

5. **Moving to a lockfile-only dependency strategy** (removing `requirements.txt`): The existing pinned `requirements.txt` is sufficient for a 4-package Python project. Adopting poetry or uv is a separate initiative; for now, adding `pip-audit` is the correct incremental step.
