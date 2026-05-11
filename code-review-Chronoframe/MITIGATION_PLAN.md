# Chronoframe — Mitigation Plan for Deep Code Review Findings

*Generated: 2026-05-10 | Companion to TOP_IMPROVEMENTS.md and IMPLEMENTATION_PLAN.md*

This plan sequences remediation of all 10 findings into executable PRs, grouped by phase. Each phase has a clear gate, structural guards land before fixes, and parallelism is called out explicitly. Total estimated effort: **~6 engineer-days** spread over **3 calendar weeks**.

---

## Executive Summary

| Phase | Window | Goal | Findings addressed | Effort |
|-------|--------|------|-------------------|--------|
| 0 | Day 0 | Baseline measurements | — | 1 hour |
| 1 | Week 1 | P1 data-loss safety fixes | 1, 2 | 6–10 hours |
| 2 | Week 1 (parallel) | CI structural guards | 4, 5 | 2 hours |
| 3 | Week 2 | Quick correctness wins | 3, 8, 10 | 3 hours |
| 4 | Week 2–3 | Reliability improvements | 6, 9 | 8 hours |
| 5 | Week 3+ | Architectural cleanup | 7 | 1–3 days |

**Sequencing principle:** Land structural guards (failing tests, CI checks) *before* code fixes wherever possible. This makes every fix land green and prevents regressions during the campaign.

---

## Phase 0 — Pre-Work (Day 0, ~1 hour)

Before any code changes, gather the baseline data needed to set thresholds correctly.

### 0.1 Measure current Python coverage

```bash
cd /Users/nishithnand/Code/Chronoframe
python -m pip install coverage pip-audit
coverage run -m unittest discover -s tests -t . -v
coverage report
```

**Record:** overall coverage percentage. This sets the `--fail-under` threshold for Phase 2.

### 0.2 Audit current dependencies

```bash
pip-audit -r requirements.txt
```

**Record:** any current CVEs. If found, escalate immediately — either bump the affected dep or document a suppression with rationale before adding `pip-audit` to CI.

### 0.3 Verify all cited line numbers are still current

```bash
# Confirm Finding 1
grep -n "endswith('.tmp')" chronoframe/io.py    # expect line 61

# Confirm Finding 2
grep -n "os.remove(dst)" chronoframe/core.py     # expect line 346

# Confirm Finding 3
grep -B1 "def get_cache_dict\|def get_pending_jobs" chronoframe/database.py  # confirm no `with self._lock:`

# Confirm Finding 10
grep -n "startedAt\|finishedAt" chronoframe/core.py  # expect lines 283-284
```

If any cited line has shifted (recent commits), update the implementation plans before proceeding.

### 0.4 Create tracking issue

Open a single tracking GitHub issue titled **"Deep Code Review — May 2026 Findings"** listing all 10 findings with checkboxes. Sub-PRs reference this issue. This gives one place to see overall progress.

---

## Phase 1 — P1 Data-Loss Safety Fixes (Week 1)

**Goal:** Eliminate the two P1 findings before any other work. Both are reachable in normal usage and cause irrecoverable data loss.

These two PRs can run in **parallel** — different files, no shared logic.

### PR 1.A — `fix: scope cleanup_tmp_files to Chronoframe's own .tmp files`

**Addresses:** Finding 1
**Branch:** `fix/cleanup-tmp-scope`
**Effort:** 3–4 hours

#### Step 1: Land the structural guard first (failing tests)

Commit message: `test: cleanup_tmp_files must not delete non-Chronoframe .tmp files`

Add to `tests/test_chronoframe.py` in the existing `TestCleanupTmpFiles` class:

```python
def test_cleanup_does_not_delete_non_chronoframe_tmp(self):
    """External .tmp files (DaVinci Resolve, video editors) must survive cleanup."""
    dst = self.mkdtemp()
    external = os.path.join(dst, "Timeline_Export.tmp")
    with open(external, 'w') as f:
        f.write("resolve scratch")

    chrono = os.path.join(dst, "2024-01-15_001.jpg.tmp")
    with open(chrono, 'w') as f:
        f.write("interrupted copy")

    count = cleanup_tmp_files(dst)

    self.assertEqual(count, 1)
    self.assertTrue(os.path.exists(external))
    self.assertFalse(os.path.exists(chrono))

def test_cleanup_handles_unknown_date_tmp(self):
    dst = self.mkdtemp()
    tmp = os.path.join(dst, "Unknown_003.heic.tmp")
    with open(tmp, 'w') as f:
        pass
    self.assertEqual(cleanup_tmp_files(dst), 1)
    self.assertFalse(os.path.exists(tmp))

def test_cleanup_handles_collision_tmp(self):
    dst = self.mkdtemp()
    tmp = os.path.join(dst, "2024-03-10_005_collision_2.jpg.tmp")
    with open(tmp, 'w') as f:
        pass
    self.assertEqual(cleanup_tmp_files(dst), 1)

def test_cleanup_handles_swift_uuid_suffix_tmp(self):
    dst = self.mkdtemp()
    # Swift TransferExecutor.swift:664 uses .UUID.tmp pattern
    tmp = os.path.join(dst, "2024-03-10_005.jpg.8F3A2C1D-8F3A-2C1D-8F3A-2C1D8F3A2C1D.tmp")
    with open(tmp, 'w') as f:
        pass
    self.assertEqual(cleanup_tmp_files(dst), 1)
```

Push the test commit. CI fails. This is the structural guard.

#### Step 2: Land the fix

Commit message: `fix: scope cleanup_tmp_files to Chronoframe's own .tmp files (Finding 1)`

Edit `chronoframe/io.py`:

```python
import re  # add if not already at top

_CHRONOFRAME_TMP_RE = re.compile(
    r'^(?:\d{4}-\d{2}-\d{2}|Unknown)_\d+(?:_collision_\d+)?'
    r'\.[a-zA-Z0-9]+(?:\.[0-9a-fA-F-]{36})?\.tmp$'
)

def cleanup_tmp_files(dst_dir):
    """Remove Chronoframe's own orphaned .tmp files from interrupted copies."""
    cleaned = 0
    for root, dirs, fnames in os.walk(dst_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for fname in fnames:
            if _CHRONOFRAME_TMP_RE.match(fname):
                try:
                    os.remove(os.path.join(root, fname))
                    cleaned += 1
                except OSError:
                    pass
    return cleaned
```

#### Step 3: Mirror in Swift

Same PR — edit `ui/Sources/ChronoframeCore/TransferExecutor.swift:202-226`:

```swift
private static let chronoframeTmpPattern: NSRegularExpression? = try? NSRegularExpression(
    pattern: #"^(?:\d{4}-\d{2}-\d{2}|Unknown)_\d+(?:_collision_\d+)?\.[a-zA-Z0-9]+(?:\.[0-9a-fA-F-]{36})?\.tmp$"#
)

public func cleanupTemporaryFiles(at destinationRoot: URL) -> Int {
    guard let enumerator = FileManager.default.enumerator(
        at: destinationRoot,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    ) else { return 0 }

    var cleanedCount = 0
    for case let fileURL as URL in enumerator {
        let filename = fileURL.lastPathComponent
        guard
            filename.hasSuffix(Self.orphanedTemporarySuffix),
            let pattern = Self.chronoframeTmpPattern
        else { continue }

        let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
        guard pattern.firstMatch(in: filename, range: range) != nil else { continue }

        do {
            try FileManager.default.removeItem(at: fileURL)
            cleanedCount += 1
        } catch {
            continue
        }
    }
    return cleanedCount
}
```

Add equivalent Swift tests in `ui/Tests/ChronoframeAppCoreTests/TransferExecutorTests.swift`.

#### Verification

- All Python tests pass: `python -m unittest discover -s tests -t . -v`
- All Swift tests pass: `swift test --package-path ui`
- `grep -n "endswith('.tmp')" chronoframe/io.py` returns no results

#### Rollback

Revert the merge commit. No on-disk state is changed by the fix itself.

---

### PR 1.B — `fix: validate revert receipt paths against destination boundary`

**Addresses:** Finding 2
**Branch:** `fix/revert-path-boundary`
**Effort:** 3–4 hours
**Can run in parallel with PR 1.A** — different files.

#### Step 1: Failing test first

Commit message: `test: revert_receipt must refuse paths outside destination boundary`

Add to `tests/test_chronoframe.py` in `TestRevertReceipt`:

```python
def test_revert_refuses_path_outside_destination(self):
    """A crafted receipt with a dest path outside the destination must be refused."""
    dst = self.mkdtemp()
    logs_dir = os.path.join(dst, '.organize_logs')
    os.makedirs(logs_dir)

    # File OUTSIDE the destination tree
    outside_dir = self.mkdtemp()
    outside_file = os.path.join(outside_dir, "tax_return.pdf")
    with open(outside_file, 'w') as f:
        f.write("important")
    from chronoframe.io import fast_hash
    outside_hash = fast_hash(outside_file)

    receipt = {
        "schemaVersion": 2,
        "transfers": [
            {"source": "/dev/null", "dest": outside_file, "hash": outside_hash}
        ]
    }
    receipt_path = os.path.join(logs_dir, "audit_receipt_crafted.json")
    with open(receipt_path, 'w') as f:
        json.dump(receipt, f)

    import chronoframe.core as core
    with self.assertRaises(SystemExit):
        core.revert_receipt(receipt_path)

    self.assertTrue(os.path.exists(outside_file),
                    "File outside destination must not be deleted")

def test_revert_preserves_normal_behavior_inside_destination(self):
    """Valid receipts (dest paths inside destination) work unchanged."""
    dst = self.mkdtemp()
    logs_dir = os.path.join(dst, '.organize_logs')
    os.makedirs(logs_dir)
    inside_path = os.path.join(dst, '2024', '01', '15', '2024-01-15_001.jpg')
    os.makedirs(os.path.dirname(inside_path))
    with open(inside_path, 'wb') as f:
        f.write(b"content")
    from chronoframe.io import fast_hash
    inside_hash = fast_hash(inside_path)

    receipt = {
        "schemaVersion": 2,
        "transfers": [
            {"source": "/dev/null", "dest": inside_path, "hash": inside_hash}
        ]
    }
    receipt_path = os.path.join(logs_dir, "audit_receipt_valid.json")
    with open(receipt_path, 'w') as f:
        json.dump(receipt, f)

    import chronoframe.core as core
    with self.assertRaises(SystemExit):
        core.revert_receipt(receipt_path)

    self.assertFalse(os.path.exists(inside_path))
```

Push test commit. CI fails. Structural guard in place.

#### Step 2: Apply the fix

Edit `chronoframe/core.py:301-369` per IMPLEMENTATION_PLAN.md Plan 2 design. Key addition before the `for item in transfers:` loop:

```python
receipt_abs = os.path.abspath(receipt_path)
logs_dir = os.path.dirname(receipt_abs)
dest_root = os.path.dirname(logs_dir)
dest_prefix = os.path.normpath(dest_root) + os.sep
```

Inside the loop, before any `os.remove`:

```python
if dst:
    dst_abs = os.path.normpath(os.path.abspath(dst))
    if not dst_abs.startswith(dest_prefix):
        emit_json("error", message=f"Receipt path outside destination: {dst}")
        console.print(f"[red]Refusing path outside destination:[/red] {dst}")
        failed_count += 1
        progress.advance(task_id)
        continue
```

Also add `--dest` argument to `parse_args()` (line 79-95) so users with moved receipts can override:

```python
parser.add_argument("--dest", type=str, default=None,
                    help="Destination root for path boundary validation during --revert")
```

And in `main()` (around line 398), when `args.revert` is truthy, pass the override:

```python
if args.revert:
    revert_receipt(args.revert, dest_root_override=args.dest)
    return
```

#### Step 3: Swift mirror

Edit `ui/Sources/ChronoframeCore/RevertExecutor.swift`. The Swift API already receives `destinationRoot: URL`, so derivation is unnecessary — add the prefix check before `FileManager.default.removeItem`. Add corresponding Swift tests.

#### Step 4: Documentation

Add a section to `README.md`:

> ### Reverting a moved receipt
> If you have moved an audit receipt file (e.g., to attach to a support ticket), specify the original destination explicitly:
>
> ```
> chronoframe --revert /path/to/receipt.json --dest /Volumes/Photos
> ```

#### Verification

- New tests pass
- Existing `TestRevertReceipt` tests pass unchanged
- Manual smoke test: craft a receipt referencing `/etc/hosts` and confirm refusal

#### Rollback

Revert the merge commit. No on-disk state is affected.

---

### Phase 1 Gate

Both PRs merged. Open a new release: `v<next>.0` with release notes:

```
SECURITY FIXES
- cleanup_tmp_files no longer deletes .tmp files from other applications
  in the destination directory (CVE-pending if assigned)
- revert_receipt now refuses to delete files outside the destination
  directory; use --dest to override for moved receipts

Users running on shared destination directories (e.g., with DaVinci Resolve)
should update immediately.
```

---

## Phase 2 — CI Structural Guards (Week 1, in parallel with Phase 1)

**Goal:** Wire up `pip-audit` and Python coverage gating. These are zero-friction protections that catch regressions caught by Phase 3+ work.

### PR 2.A — `ci: add pip-audit and Python coverage gate`

**Addresses:** Findings 4 and 5
**Branch:** `ci/audit-and-coverage`
**Effort:** 2 hours
**Can run in parallel with Phase 1.**

#### Step 1: Add `.coveragerc` at repo root

```ini
[run]
source = chronoframe
branch = True
omit =
    chronoframe/__main__.py
    tests/*

[report]
exclude_lines =
    pragma: no cover
    if __name__ == .__main__.:
    raise NotImplementedError
    def __repr__
show_missing = True
skip_covered = False

[xml]
output = coverage.xml
```

#### Step 2: Edit `.github/workflows/ci.yml`

Replace the `python-tests` job's "Install" and "Run" steps:

```yaml
- name: Install Python dependencies
  run: |
    python -m pip install --upgrade pip
    python -m pip install -r requirements.txt
    python -m pip install coverage pip-audit

- name: Audit Python dependencies for CVEs
  run: pip-audit -r requirements.txt

- name: Run Python test suite with coverage
  run: |
    coverage run -m unittest discover -s tests -t . -v
    coverage report --fail-under=${{ env.COVERAGE_THRESHOLD }}
    coverage xml

- name: Upload coverage report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: python-coverage
    path: coverage.xml
    retention-days: 30
```

Add at top of file (under `env:` block or job env):

```yaml
env:
  COVERAGE_THRESHOLD: "80"   # adjust based on Phase 0 baseline
```

#### Step 3: Set the threshold correctly

Use Phase 0.1's measurement. If baseline is 87%, set threshold to 85 (give a 2-point cushion). Document the choice in PR description.

#### Step 4: Handle pre-existing CVEs

If Phase 0.2 found any CVEs:
- For unaffected ones (Chronoframe's usage doesn't expose the vuln): add `--ignore-vuln <ID>` flag with a comment explaining why
- For affected ones: bump the dep in a separate prior PR before this one lands

#### Verification

- CI green on the PR
- Coverage artifact uploaded and downloadable
- Force a coverage drop locally (delete a test) and confirm CI fails

#### Rollback

Revert the merge. CI returns to current state with no audit/coverage.

---

## Phase 3 — Quick Correctness Wins (Week 2)

**Goal:** Three XS-effort fixes that materially improve correctness. Bundle into a single PR for review efficiency since they touch different concerns.

### PR 3.A — `fix: SQLite read locks, path sanitization, audit timestamps`

**Addresses:** Findings 3, 8, 10
**Branch:** `fix/correctness-quick-wins`
**Effort:** 3 hours
**Depends on:** Phase 2 (so the coverage gate catches any test gaps)

#### Subtask 3.A.1 — Finding 3: SQLite read locks

Edit `chronoframe/database.py`:

```python
def get_cache_dict(self, type_id):
    with self._lock:
        cur = self.conn.execute(
            "SELECT path, hash, size, mtime FROM FileCache WHERE id = ?",
            (type_id,),
        )
        return {row[0]: {"hash": row[1], "size": row[2], "mtime": row[3]}
                for row in cur.fetchall()}

def get_pending_jobs(self):
    with self._lock:
        cur = self.conn.execute(
            "SELECT src_path, dst_path, hash FROM CopyJobs WHERE status = 'PENDING'"
        )
        return cur.fetchall()
```

Add test to `tests/test_chronoframe.py`:

```python
class TestCacheDBConcurrentReadWrite(TempDirMixin, unittest.TestCase):
    def test_concurrent_reads_and_writes_do_not_error(self):
        import threading
        db = CacheDB(os.path.join(self.mkdtemp(), 'cache.db'))
        errors = []

        def writer():
            for i in range(100):
                try:
                    db.save_batch(1, [(f'/p/{i}', f'h{i}', i, float(i))])
                except Exception as e:
                    errors.append(e)

        def reader():
            for _ in range(100):
                try:
                    db.get_cache_dict(1)
                    db.get_pending_jobs()
                except Exception as e:
                    errors.append(e)

        threads = [threading.Thread(target=writer) for _ in range(3)]
        threads += [threading.Thread(target=reader) for _ in range(5)]
        for t in threads: t.start()
        for t in threads: t.join()
        db.close()
        self.assertEqual(errors, [])
```

#### Subtask 3.A.2 — Finding 8: `_event_subpath` sanitization

Edit `chronoframe/core.py`:

```python
_UNSAFE_PATH_CHARS = re.compile(r'[:<>|\\?*"]')

def _event_subpath(src_path, src_root):
    """Immediate parent folder name relative to source root, sanitized for cross-platform paths."""
    try:
        rel = os.path.relpath(os.path.dirname(src_path), src_root)
    except ValueError:
        return ""
    if rel in ("", "."):
        return ""
    raw = os.path.basename(rel)
    return _UNSAFE_PATH_CHARS.sub('_', raw)
```

Add test (already has `TestEventSubpath` at line 2820 — extend it):

```python
def test_event_subpath_sanitizes_unsafe_chars(self):
    self.assertEqual(
        _event_subpath('/source/2024:Hawaii/img.jpg', '/source'),
        '2024_Hawaii'
    )
    self.assertEqual(
        _event_subpath('/source/Photos?Backup*/img.jpg', '/source'),
        'Photos_Backup_'
    )
```

#### Subtask 3.A.3 — Finding 10: Audit receipt timestamps

Edit `chronoframe/core.py`. Change `generate_audit_receipt()` signature to accept `started_at`:

```python
def generate_audit_receipt(
    jobs_executed,
    dest_path,
    *,
    started_at,            # NEW: datetime when run began
    status="COMPLETED",
    abort_reason=None,
    attempted_count=None,
    failed_count=0,
    verify=False,
):
    finished_at = datetime.now()
    run_id = str(uuid.uuid4())
    receipt_name = f"audit_receipt_{finished_at.strftime('%Y%m%d_%H%M%S')}_{run_id}.json"
    ...
    payload = {
        "schemaVersion": 2,
        "runID": run_id,
        "operation": "organize",
        "timestamp": finished_at.isoformat(),
        "startedAt": started_at.isoformat(),
        "finishedAt": finished_at.isoformat(),
        ...
```

Update all callers (`execute_jobs()` and any tests calling the function directly) to pass `started_at`. In `main()`, capture `run_started_at = datetime.now()` near the top and thread it through `execute_jobs()`.

Add test (already has `TestAuditReceipt` at line 779 — extend it):

```python
def test_audit_receipt_has_distinct_started_finished_timestamps(self):
    import time
    started = datetime.now()
    time.sleep(0.05)
    rpath = generate_audit_receipt(
        [], self.mkdtemp(), started_at=started, status="COMPLETED"
    )
    with open(rpath) as f:
        data = json.load(f)
    self.assertNotEqual(data['startedAt'], data['finishedAt'])
    self.assertLess(data['startedAt'], data['finishedAt'])
```

#### Verification

- All three subtasks have passing tests
- Coverage doesn't drop (Phase 2's gate catches it)
- Manual: run a small organize and inspect the receipt — `startedAt` and `finishedAt` should differ

#### Rollback

Revert merge. No state on disk affected.

---

## Phase 4 — Reliability Improvements (Week 2–3)

**Goal:** Two medium-effort improvements that prevent operational issues at scale.

### PR 4.A — `feat: rotate .organize_log.txt at 5 MB`

**Addresses:** Finding 6
**Branch:** `feat/log-rotation`
**Effort:** 3 hours
**Can run in parallel with PR 4.B.**

#### Implementation

Edit `chronoframe/core.py` `RunLogger.open()`:

```python
class RunLogger:
    MAX_LOG_BYTES = 5 * 1024 * 1024

    def open(self):
        try:
            if (os.path.exists(self.log_path)
                    and os.path.getsize(self.log_path) > self.MAX_LOG_BYTES):
                rotated = self.log_path + '.1'
                if os.path.exists(rotated):
                    try:
                        os.remove(rotated)
                    except OSError:
                        pass
                try:
                    os.rename(self.log_path, rotated)
                except OSError:
                    pass
            self._fh = open(self.log_path, 'a')
        except OSError:
            self._fh = None
```

Mirror in Swift `PersistentRunLogger.open()` at `TransferExecutor.swift:93-106`:

```swift
public func open() throws {
    try FileManager.default.createDirectory(
        at: logURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )

    // Rotate if oversized
    if let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
       let size = attrs[.size] as? UInt64,
       size > Self.maxLogBytes {
        let rotatedURL = logURL.appendingPathExtension("1")
        try? FileManager.default.removeItem(at: rotatedURL)
        try? FileManager.default.moveItem(at: logURL, to: rotatedURL)
    }

    if !FileManager.default.fileExists(atPath: logURL.path) {
        FileManager.default.createFile(atPath: logURL.path, contents: Data())
    }

    let newHandle = try FileHandle(forWritingTo: logURL)
    try newHandle.seekToEnd()
    lock.withLock { $0 = newHandle }
}

public static let maxLogBytes: UInt64 = 5 * 1024 * 1024
```

#### Tests

```python
def test_run_logger_rotates_at_size_cap(self):
    path = os.path.join(self.mkdtemp(), 'organize.log')
    # Pre-seed log past the cap
    with open(path, 'w') as f:
        f.write('x' * (6 * 1024 * 1024))
    logger = RunLogger(path)
    logger.open()
    logger.log('after-rotation')
    logger.close()

    self.assertTrue(os.path.exists(path + '.1'))
    self.assertLess(os.path.getsize(path), 1024 * 1024)
```

#### Rollback

Revert merge. Existing log file remains; rotation simply stops.

---

### PR 4.B — `fix: verify source still matches planned hash before copy`

**Addresses:** Finding 9
**Branch:** `fix/verify-source-pre-copy`
**Effort:** 5 hours
**Can run in parallel with PR 4.A.**

#### Implementation

Edit `chronoframe/core.py` `execute_jobs()`. Before `safe_copy_atomic()`:

```python
for src_p, dst_p, h in pending_jobs:
    attempted_count = count + 1

    # NEW: verify source still matches the planned hash
    try:
        current_src_hash = fast_hash(src_p)
    except OSError as e:
        emit_json("warning", message=f"Source unreadable, skipping: {src_p}: {e}")
        if run_log:
            run_log.warn(f"Source unreadable, skipping: {src_p}: {e}")
        status_updates.append((src_p, 'SKIPPED'))
        progress.advance(task_id)
        count += 1
        continue

    if current_src_hash != h:
        emit_json("warning",
                  message=f"Source modified since planning, skipping: {src_p}")
        if run_log:
            run_log.warn(f"Source modified since planning, skipping: {src_p}")
        status_updates.append((src_p, 'SKIPPED'))
        progress.advance(task_id)
        count += 1
        continue
    # END NEW

    try:
        result = safe_copy_atomic(src_p, dst_p)
        # ... existing verify and bookkeeping logic
```

Update `CopyJobs` schema to support a `SKIPPED` status (already a string column, so no migration needed — just document the new value).

#### Tests

```python
def test_execute_jobs_skips_if_source_modified_since_planning(self):
    dst = self.mkdtemp()
    src_dir = self.mkdtemp()
    src = os.path.join(src_dir, 'photo.jpg')
    with open(src, 'wb') as f:
        f.write(b"original")
    planned_hash = fast_hash(src)

    # Simulate source modification AFTER planning
    with open(src, 'wb') as f:
        f.write(b"modified after plan")

    cache_db = CacheDB(os.path.join(dst, 'cache.db'))
    cache_db.enqueue_jobs([(src, os.path.join(dst, 'copy.jpg'), planned_hash, 'PENDING')])

    execute_jobs(cache_db.get_pending_jobs(), cache_db, dst, verify=True)

    # Destination should not exist (skipped, not failed)
    self.assertFalse(os.path.exists(os.path.join(dst, 'copy.jpg')))
    cache_db.close()
```

#### Performance note

Pre-copy hashing adds I/O — for a 4 TB photo library, expect ~10–20% increase in copy phase time. If unacceptable, gate behind `--verify-source` flag (default on for safety).

#### Rollback

Revert merge. No state change.

---

## Phase 5 — Architectural Cleanup (Week 3+)

**Goal:** Address the global-state finding. This is intentionally last because (a) it's a mechanical refactor with low correctness risk and (b) the coverage gate from Phase 2 protects against regressions.

### PR 5.A — `refactor: thread output context through core.py instead of globals`

**Addresses:** Finding 7
**Branch:** `refactor/output-context`
**Effort:** 1–3 days
**Depends on:** Phase 2 (coverage gate must be in place)

#### Approach

Replace module globals `_json_active` and `console` with an `OutputContext` dataclass passed through function signatures:

```python
# core.py — near top
from dataclasses import dataclass

@dataclass
class OutputContext:
    json_mode: bool
    console: Console

    def emit_json(self, msg_type: str, **kwargs):
        if self.json_mode:
            print(json.dumps({"type": msg_type, **kwargs}), flush=True)
```

Update every function currently using `console`, `_json_active`, or `emit_json` to accept `ctx: OutputContext` as the first parameter.

**Affected functions** (`grep -n "emit_json\|^console\|_json_active" chronoframe/core.py`):
- `generate_dry_run_report`
- `generate_audit_receipt`
- `revert_receipt`
- `build_dest_index`
- `execute_jobs`
- `load_profile`
- `main` (constructs the ctx)

This is mechanical but touches ~40 call sites. Do it as a single PR — splitting introduces backward-compat scaffolding that would have to be torn down.

#### Tests

Existing tests will need updating to construct an `OutputContext` instead of mutating globals. The test suite already has setUp/tearDown that reset `core._json_active = False` and `core.console = Console()` — those resets disappear after this refactor (good).

#### Structural Guard

Add a CI step:

```yaml
- name: Reject re-introduction of mutable module globals
  run: |
    if grep -rn 'global _json_active\|global console' chronoframe/; then
      echo "Module globals are forbidden; use OutputContext instead."
      exit 1
    fi
```

#### Rollback

Revert merge. The refactor is large but contained to one PR.

---

## Cross-Cutting Concerns

### Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Regex in Finding 1 misses a new naming pattern | Low | Medium | Centralize the pattern as a constant referenced by both `cleanup_tmp_files` and `safe_copy_atomic`'s temp creation; add a `# IF YOU CHANGE THIS, UPDATE BOTH SIDES` comment |
| Coverage gate blocks legitimate refactors | Medium | Low | Start with `--fail-under` 2 points below baseline; raise after stability proven |
| `pip-audit` false positives | Medium | Low | `--ignore-vuln` with documented rationale; review on each Dependabot update |
| Phase 5 refactor breaks subtle global-state assumption | Low | Medium | Coverage gate from Phase 2 catches regressions; mechanical scope keeps it auditable |
| Pre-copy hash check (Finding 9) impacts performance unacceptably | Medium | Medium | Bench on a 1k-file fixture; gate behind `--verify-source` if degradation > 15% |

### Communication Plan

- **Tracking issue:** "Deep Code Review — May 2026 Findings" with 10 checkboxes
- **Release notes after Phase 1:** Emphasize the security fixes; recommend immediate update
- **Release notes after Phase 2/3:** Bundle as a quality release; mention CI improvements
- **No public CVE filing** unless a security researcher requests it — these are user-environment risks, not remote attack surface

### Verification After Full Campaign

After all phases land:

```bash
# 1. All structural guards in place
grep -n "endswith('.tmp')" chronoframe/io.py                # no results
grep -n "with self._lock:" chronoframe/database.py | wc -l  # >= 7 (was 5)
grep -n "global _json_active\|global console" chronoframe/  # no results

# 2. CI gates active
grep -n "pip-audit\|--fail-under" .github/workflows/ci.yml  # both present

# 3. Tests verify the fixes
python -m unittest tests.test_chronoframe.TestCleanupTmpFiles -v
python -m unittest tests.test_chronoframe.TestRevertReceipt -v

# 4. Full suite green
coverage run -m unittest discover -s tests -t . -v
coverage report --fail-under=80
swift test --package-path ui
```

### Definition of Done (Campaign-Level)

- [ ] All 10 findings have merged PRs referenced from the tracking issue
- [ ] Each P1 finding has a regression test that fails before the fix
- [ ] Each P2 finding has either a regression test or a CI structural guard
- [ ] CI runs `pip-audit` and `coverage report --fail-under=N` on every PR
- [ ] No module globals remain in `chronoframe/core.py`
- [ ] At least two end-to-end manual smoke tests have been run (organize + revert)
- [ ] Release notes published describing the security fixes (Phase 1)

---

## Quick-Reference PR Sequence

```
Week 1:
  ├─ PR 1.A: cleanup_tmp_files scope        ─┐
  ├─ PR 1.B: revert path boundary           ─┼─ (parallel)
  └─ PR 2.A: pip-audit + coverage gate      ─┘

Week 2:
  └─ PR 3.A: SQLite locks + path sanitize + receipt timestamps
                 (depends on PR 2.A for coverage protection)

Week 2–3:
  ├─ PR 4.A: log rotation                   ─┐
  └─ PR 4.B: source pre-copy hash verify    ─┘ (parallel)

Week 3+:
  └─ PR 5.A: OutputContext refactor (depends on PR 2.A)
```

**Total: 7 PRs, ~6 engineer-days, 3 calendar weeks.**

All cited files: [chronoframe/io.py](chronoframe/io.py), [chronoframe/core.py](chronoframe/core.py), [chronoframe/database.py](chronoframe/database.py), [ui/Sources/ChronoframeCore/TransferExecutor.swift](ui/Sources/ChronoframeCore/TransferExecutor.swift), [ui/Sources/ChronoframeCore/RevertExecutor.swift](ui/Sources/ChronoframeCore/RevertExecutor.swift), [.github/workflows/ci.yml](.github/workflows/ci.yml), [tests/test_chronoframe.py](tests/test_chronoframe.py).
