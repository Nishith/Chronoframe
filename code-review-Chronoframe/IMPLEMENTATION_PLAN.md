# Chronoframe — Implementation Plans (Top 3)

*Generated: 2026-05-10 | Accompanies TOP_IMPROVEMENTS.md*

---

## Plan 1: Fix `cleanup_tmp_files()` to only delete Chronoframe's own temporaries

### A. Objective

**Problem:** `cleanup_tmp_files()` deletes every file ending in `.tmp` under the destination directory, including files created by other applications. This causes silent, irrecoverable data loss for any user whose destination is shared with a video editor, DAW, or any tool that writes `.tmp` scratch files.

**Measurable success criteria:**
- `cleanup_tmp_files()` only deletes files whose names match Chronoframe's own naming convention
- Non-Chronoframe `.tmp` files in the destination are never touched
- Existing behavior for Chronoframe's own orphaned temporaries is unchanged
- A new regression test fails before the fix and passes after

---

### B. Current State

**Python (`chronoframe/io.py:55-68`):**
```python
def cleanup_tmp_files(dst_dir):
    """Remove orphaned .tmp files left by interrupted copies. Returns count removed."""
    cleaned = 0
    for root, dirs, fnames in os.walk(dst_dir):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for fname in fnames:
            if fname.endswith('.tmp'):    # <- matches ANY .tmp file
                path = os.path.join(root, fname)
                try:
                    os.remove(path)
                    cleaned += 1
                except OSError:
                    pass
    return cleaned
```

**Swift (`ui/Sources/ChronoframeCore/TransferExecutor.swift:202-226`):**
```swift
public func cleanupTemporaryFiles(at destinationRoot: URL) -> Int {
    // ...
    for case let fileURL as URL in enumerator {
        guard fileURL.lastPathComponent.hasSuffix(Self.orphanedTemporarySuffix) else {
            continue
        }
        // <- matches ANY .tmp file, no Chronoframe-specific filter
        try FileManager.default.removeItem(at: fileURL)
        cleanedCount += 1
    }
    return cleanedCount
}
```

**Why it is insufficient:** The only filter is the `.tmp` extension. Chronoframe's own temporaries have a distinctive naming pattern (destination filename + `.tmp`), but that pattern is not used to filter here.

---

### C. Target State

`cleanup_tmp_files()` only removes files whose names match the Chronoframe destination filename pattern:

- Primary: `YYYY-MM-DD_NNN<ext>.tmp` (e.g., `2024-01-15_001.jpg.tmp`)
- Unknown date: `Unknown_NNN<ext>.tmp` (e.g., `Unknown_003.heic.tmp`)
- Collision: `YYYY-MM-DD_NNN_collision_N<ext>.tmp`
- Swift UUID pattern: `YYYY-MM-DD_NNN<ext>.<UUID>.tmp` (e.g., `2024-01-15_001.jpg.8F3A2C1D-....tmp`)

All other `.tmp` files in the destination are left strictly untouched.

**Properties that must hold after the change:**
- `cleanup_tmp_files("/path/to/dest")` with a DaVinci Resolve `.tmp` file present returns 0 (zero files removed)
- `cleanup_tmp_files("/path/to/dest")` with Chronoframe's own `.tmp` files returns the correct count
- Behavior on a fresh destination (no `.tmp` files of any kind) is unchanged

---

### D. Detailed Design

#### Python changes

**File:** `chronoframe/io.py`

Add the regex constant above `cleanup_tmp_files()`:

```python
import re  # already imported — verify at top of file

# Matches Chronoframe's own temporary files only.
# Pattern covers:
#   2024-01-15_001.jpg.tmp
#   Unknown_003.heic.tmp
#   2024-01-15_001_collision_2.jpg.tmp
#   2024-01-15_001.jpg.8F3A2C1D-8F3A-2C1D-8F3A-2C1D8F3A2C1D.tmp (Swift UUID variant)
_CHRONOFRAME_TMP_RE = re.compile(
    r'^(?:\d{4}-\d{2}-\d{2}|Unknown)_\d+(?:_collision_\d+)?'  # date_seq[_collision_N]
    r'\.[a-zA-Z0-9]+(?:\.[0-9a-fA-F-]{36})?\.tmp$'           # .ext[.UUID].tmp
)
```

Replace the body of `cleanup_tmp_files()`:

```python
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

Note: the `fname.endswith('.tmp')` check is now implicit in the regex (regex requires `.tmp` at end); no need to keep both.

#### Swift changes

**File:** `ui/Sources/ChronoframeCore/TransferExecutor.swift`

Add a static regex pattern constant to `TransferExecutor`:

```swift
// Matches Chronoframe's own .tmp files only (see Python counterpart).
private static let chronoframeTmpPattern: NSRegularExpression? = try? NSRegularExpression(
    pattern: #"^(?:\d{4}-\d{2}-\d{2}|Unknown)_\d+(?:_collision_\d+)?\.[a-zA-Z0-9]+(?:\.[0-9a-fA-F-]{36})?\.tmp$"#
)
```

Update `cleanupTemporaryFiles(at:)`:

```swift
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

---

### E. Execution Plan

**Phase 1: Land the structural guard (failing test)**

File: `tests/test_chronoframe.py` — extend `TestCleanupTmpFiles`

```python
def test_cleanup_does_not_delete_non_chronoframe_tmp(self):
    """cleanup_tmp_files must NOT delete .tmp files from other applications."""
    dst = self.mkdtemp()
    # A non-Chronoframe .tmp file (e.g., from DaVinci Resolve)
    external_tmp = os.path.join(dst, "Timeline_Export.tmp")
    with open(external_tmp, 'w') as f:
        f.write("resolve scratch")
    # A Chronoframe .tmp file (orphaned from interrupted copy)
    chrono_tmp = os.path.join(dst, "2024-01-15_001.jpg.tmp")
    with open(chrono_tmp, 'w') as f:
        f.write("partial copy")
    
    count = cleanup_tmp_files(dst)
    
    self.assertEqual(count, 1)                           # only Chronoframe's own
    self.assertTrue(os.path.exists(external_tmp))        # external NOT deleted
    self.assertFalse(os.path.exists(chrono_tmp))         # Chronoframe's deleted

def test_cleanup_handles_unknown_date_tmp(self):
    dst = self.mkdtemp()
    unknown_tmp = os.path.join(dst, "Unknown_003.heic.tmp")
    with open(unknown_tmp, 'w') as f:
        f.write("partial")
    count = cleanup_tmp_files(dst)
    self.assertEqual(count, 1)
    self.assertFalse(os.path.exists(unknown_tmp))
```

Commit as: `test: cleanup_tmp_files must not delete non-Chronoframe .tmp files (failing)`

**Phase 2: Apply the fix**

Edit `chronoframe/io.py` as per the design above. Verify the new tests pass. Verify existing `TestCleanupTmpFiles` tests still pass.

**Phase 3: Apply Swift fix**

Edit `TransferExecutor.swift:cleanupTemporaryFiles()` as per the design above. Run SwiftPM tests.

**Phase 4: Review and ship**

- Verify `grep -n "endswith('.tmp')" chronoframe/io.py` returns no results (old check gone)
- Verify regex covers all known Chronoframe temp file variants by running the test suite

---

### F. Testing Strategy

| Test | Type | Location |
|------|------|----------|
| `test_cleanup_does_not_delete_non_chronoframe_tmp` | Unit | `tests/test_chronoframe.py` |
| `test_cleanup_handles_unknown_date_tmp` | Unit | `tests/test_chronoframe.py` |
| `test_cleanup_handles_collision_tmp` | Unit | `tests/test_chronoframe.py` |
| `test_cleanup_handles_uuid_suffix_tmp` | Unit | `tests/test_chronoframe.py` |
| Existing `TestCleanupTmpFiles.*` | Regression | `tests/test_chronoframe.py` |
| Swift equivalent in `ChronoframeAppCoreTests` | Unit | `ui/Tests/ChronoframeAppCoreTests/` |

---

### G. Operational Plan

- No metrics or alerts needed — this is a startup cleanup function
- No rollout required — single-user local tool
- The only "rollback" is reverting the commit; no state on disk is affected

---

### H. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Regex doesn't cover a legitimate Chronoframe temp pattern | Review all places `tmp_dst = dst + ".tmp"` is used (io.py:119, TransferExecutor.swift:563, 664) and verify regex covers all of them |
| Future naming change breaks the regex | Document `_CHRONOFRAME_TMP_RE` prominently; add a comment that it must be updated alongside any filename convention change |

---

### I. Resourcing and Sequencing

- Phase 1–2 (Python): 1–2 hours, 1 engineer
- Phase 3 (Swift): 1–2 hours, 1 engineer (can run in parallel with Phase 2 if two engineers)
- Total: 2–4 hours

---

### J. Definition of Done

- [ ] `_CHRONOFRAME_TMP_RE` regex defined in `io.py` and covers all current temp file variants
- [ ] `cleanup_tmp_files()` uses the regex exclusively
- [ ] `TestCleanupTmpFiles` extended with non-Chronoframe `.tmp` file case (passing)
- [ ] `TransferExecutor.swift:cleanupTemporaryFiles()` has equivalent regex guard
- [ ] All existing Python and Swift tests pass
- [ ] CI green

---
---

## Plan 2: Validate receipt paths are within the destination before revert

### A. Objective

**Problem:** `revert_receipt()` deletes files at any path specified in the receipt's `dest` fields. A crafted receipt can cause `os.remove()` on files anywhere the user has write access.

**Measurable success criteria:**
- `revert_receipt()` refuses to delete any `dest` path that is not a descendant of the receipts' parent directory (the destination root)
- The refusal is logged and counted as a skip, not a fatal error
- Correct receipts (all paths inside the destination) behave identically to today
- A regression test for the escape scenario fails before the fix and passes after

---

### B. Current State

**`chronoframe/core.py:338-346`:**
```python
for item in transfers:
    dst = item.get("dest")
    expected_hash = item.get("hash")
    if dst and os.path.exists(dst):
        try:
            current_hash = fast_hash(dst)
            if current_hash == expected_hash:
                os.remove(dst)          # <- deletes at any path
```

No validation that `dst` is inside the destination directory.

---

### C. Target State

Before any deletion attempt, `revert_receipt()` computes the expected destination root from the receipt file's own location (`<receipt_path>/../../` resolves to `<dest>/`) and validates that every `dest` path in the receipt is a descendant of that root.

**Properties that must hold after the change:**
- Receipts with all `dest` paths inside the destination directory work identically to today
- Receipts with any `dest` path outside the destination directory: the offending entry is skipped, logged, and counted as a failure; the remaining valid entries are processed normally (no all-or-nothing abort)
- The destination root derivation is documented and testable

---

### D. Detailed Design

#### Python changes (`chronoframe/core.py`)

```python
def revert_receipt(receipt_path):
    if not os.path.exists(receipt_path):
        console.print(f"[red]Receipt not found:[/red] {receipt_path}")
        emit_json("error", message=f"Receipt not found: {receipt_path}")
        sys.exit(1)

    try:
        with open(receipt_path, 'r') as f:
            data = json.load(f)
    except Exception as e:
        console.print(f"[red]Invalid receipt:[/red] {e}")
        emit_json("error", message=f"Invalid receipt: {e}")
        sys.exit(1)

    transfers = data.get("transfers", [])
    if not transfers:
        console.print("[yellow]No transfers to revert.[/yellow]")
        emit_json("complete", status="revert_empty")
        sys.exit(0)

    # --- NEW: Derive destination root from receipt location ---
    # Receipts live at: <dest>/.organize_logs/audit_receipt_*.json
    # So: dest_root = dirname(dirname(abspath(receipt_path)))
    receipt_abs = os.path.abspath(receipt_path)
    logs_dir = os.path.dirname(receipt_abs)
    dest_root = os.path.dirname(logs_dir)
    dest_prefix = os.path.normpath(dest_root) + os.sep
    # --- END NEW ---

    from .io import fast_hash
    reverted_count = 0
    failed_count = 0

    emit_json("task_start", task="revert", total=len(transfers))

    with Progress(...) as progress:
        task_id = progress.add_task("[cyan]Reverting items...", total=len(transfers))
        for item in transfers:
            dst = item.get("dest")
            expected_hash = item.get("hash")

            # --- NEW: Path boundary validation ---
            if dst:
                dst_abs = os.path.normpath(os.path.abspath(dst))
                if not dst_abs.startswith(dest_prefix):
                    console.print(
                        f"[red]Refusing to revert path outside destination boundary:[/red] {dst}"
                    )
                    emit_json("error", message=f"Receipt path outside destination: {dst}")
                    failed_count += 1
                    progress.advance(task_id)
                    emit_json("task_progress", task="revert",
                              completed=reverted_count + failed_count, total=len(transfers))
                    continue
            # --- END NEW ---

            if dst and os.path.exists(dst):
                try:
                    current_hash = fast_hash(dst)
                    if current_hash == expected_hash:
                        os.remove(dst)
                        reverted_count += 1
                        d_dir = os.path.dirname(dst)
                        try:
                            if not os.listdir(d_dir):
                                os.rmdir(d_dir)
                        except OSError:
                            pass
                    else:
                        failed_count += 1
                except OSError:
                    failed_count += 1
            # (missing file is trivially reverted — no counter change)

            progress.advance(task_id)
            emit_json("task_progress", task="revert",
                      completed=reverted_count + failed_count, total=len(transfers))
    ...
```

#### Edge case: receipt moved to a different location

If the user moves a receipt file (e.g., to attach it to a support ticket and then run revert from a different path), the `dest_root` derivation will be wrong. To handle this, add an optional `--dest` argument to the revert CLI:

```python
# parse_args() addition:
parser.add_argument("--dest", type=str, default=None,
                    help="Destination root for path boundary validation during --revert")

# In revert_receipt(), accept dest_root_override:
def revert_receipt(receipt_path, dest_root_override=None):
    ...
    if dest_root_override:
        dest_root = os.path.abspath(dest_root_override)
    else:
        dest_root = os.path.dirname(os.path.dirname(os.path.abspath(receipt_path)))
    dest_prefix = os.path.normpath(dest_root) + os.sep
```

#### Swift changes (`ui/Sources/ChronoframeCore/RevertExecutor.swift`)

The Swift revert executor reads the receipt and deletes files. Apply the same `destPrefix` guard before any `FileManager.default.removeItem()` call. The destination root is known at call time (passed as `destinationRoot: URL`), so no derivation is needed:

```swift
let destPrefix = destinationRoot.standardized.path + "/"
for transfer in receipt.transfers {
    let destPath = transfer.dest
    let destAbs = URL(fileURLWithPath: destPath).standardized.path
    guard destAbs.hasPrefix(destPrefix) else {
        // log and skip
        observer.onIssue(RunIssue(...))
        skippedCount += 1
        continue
    }
    // existing hash-check and removeItem logic
}
```

---

### E. Execution Plan

**Phase 1: Structural guard (failing test)**

```python
# tests/test_chronoframe.py — add to TestRevertReceipt class
def test_revert_receipt_path_escape_refused(self):
    """Paths outside the destination directory must not be deleted."""
    dst = self.mkdtemp()
    logs_dir = os.path.join(dst, '.organize_logs')
    os.makedirs(logs_dir)

    # A file that exists OUTSIDE the destination
    outside_file = os.path.join(self.mkdtemp(), "innocent_file.txt")
    with open(outside_file, 'w') as f:
        f.write("important data")
    outside_hash = fast_hash(outside_file)

    # Craft a receipt that points to the outside file
    receipt = {
        "schemaVersion": 2,
        "transfers": [
            {"source": "/dev/null", "dest": outside_file, "hash": outside_hash}
        ]
    }
    receipt_path = os.path.join(logs_dir, "audit_receipt_crafted.json")
    with open(receipt_path, 'w') as f:
        json.dump(receipt, f)

    # Run revert — must NOT delete the outside file
    with self.assertRaises(SystemExit):  # sys.exit(0) at end of revert
        import chronoframe.core as core
        core.revert_receipt(receipt_path)

    self.assertTrue(os.path.exists(outside_file),
                    "File outside destination must not be deleted by revert")
```

Commit as: `test: revert_receipt must refuse paths outside destination boundary (failing)`

**Phase 2: Apply the fix**

Edit `core.py` as per the design. Run `test_revert_receipt_path_escape_refused` — it should now pass. Run the full test suite.

**Phase 3: Swift fix**

Edit `RevertExecutor.swift` with the `destPrefix` guard. Run SwiftPM tests.

**Phase 4: Docs and release**

Update `README.md` to document: "If you move a receipt file before reverting, use `chronoframe --revert <receipt> --dest <original-dest>` to specify the destination boundary."

---

### F. Testing Strategy

| Test | Type | What it validates |
|------|------|-------------------|
| `test_revert_receipt_path_escape_refused` | Unit | Path outside dest not deleted |
| `test_revert_receipt_symlink_escape_refused` | Unit | Symlink resolving outside dest not followed |
| `test_revert_receipt_normal_path_still_works` | Regression | Valid receipts work identically |
| `test_revert_receipt_moved_with_dest_override` | Unit | `--dest` override sets correct boundary |
| Swift equivalent | Unit | `RevertExecutor` respects destPrefix |

---

### G. Operational Plan

- No metrics or alerts needed
- No staged rollout — single-user local tool
- The only "rollback" is reverting the commit; no stored state is affected

---

### H. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| `dest_root` derivation breaks if receipt is not in `.organize_logs/` | `dest_root_override` / `--dest` flag handles moved receipts |
| Symlink in `dst` could resolve outside `dest_prefix` | Use `os.path.realpath()` instead of `os.path.abspath()` for stricter resolution |
| Windows paths with different separator | `os.path.normpath()` + `os.sep` handles cross-platform correctly |

---

### I. Resourcing and Sequencing

- Phase 1–2 (Python): 2–3 hours, 1 engineer
- Phase 3 (Swift): 2–3 hours, 1 engineer (can run in parallel)
- Total: 4–6 hours

---

### J. Definition of Done

- [ ] `revert_receipt()` derives `dest_prefix` from receipt location (or `--dest` override)
- [ ] Every `dest` path validated against `dest_prefix` before deletion attempt
- [ ] Paths outside boundary: skipped, logged, counted as `failed_count`, no deletion
- [ ] `TestRevertReceiptPathEscape` test passing
- [ ] `RevertExecutor.swift` has equivalent guard
- [ ] Existing revert tests pass
- [ ] README updated with moved-receipt guidance
- [ ] CI green

---
---

## Plan 3: Add `pip-audit` + Python coverage gate to CI

### A. Objective

**Problem:** CI never runs a CVE scanner on Python dependencies, and coverage is measured only locally — no threshold blocks regressions. Both are zero-friction structural guards that protect against silent quality degradation.

**Measurable success criteria:**
- `pip-audit` runs on every PR and build; fails CI if any known CVE is detected in direct or transitive deps
- `coverage report --fail-under=N` runs on every PR and build; fails CI if coverage drops below N%
- Coverage report uploaded as CI artifact for visibility

---

### B. Current State

**`.github/workflows/ci.yml:25-41`:**
```yaml
- name: Run Python test suite
  run: python -m unittest discover -s tests -t . -v
```

No `pip-audit`. No `coverage`. Dependabot is configured (good) but catches version updates, not CVEs in existing pinned versions.

---

### C. Target State

The `python-tests` CI job:
1. Installs `pip-audit` and `coverage` alongside other deps
2. Runs `pip-audit` on `requirements.txt` — fails build on any known CVE
3. Runs tests under `coverage run`
4. Runs `coverage report --fail-under=80` — fails build if coverage drops
5. Uploads `coverage.xml` as a build artifact

---

### D. Detailed Design

**Step 1: Measure current coverage before setting the threshold**

Before editing CI, run locally:
```bash
pip install coverage
coverage run -m unittest discover -s tests -t . -v
coverage report
```
Record the overall percentage. Set `--fail-under` to `floor(actual) - 2` as the initial gate (e.g., if actual is 87%, set `--fail-under=85` to allow headroom).

**Step 2: Edit `.github/workflows/ci.yml`**

```yaml
python-tests:
  name: Python tests
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@v6
    - uses: actions/setup-python@v6
      with:
        python-version: "3.13"
        cache: "pip"
        cache-dependency-path: requirements.txt
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
        coverage report --fail-under=80
        coverage xml -o coverage.xml
    - name: Upload coverage report
      uses: actions/upload-artifact@v4
      with:
        name: python-coverage
        path: coverage.xml
        retention-days: 30
```

**Step 3: Add `.coveragerc` for consistent configuration**

```ini
# .coveragerc
[run]
source = chronoframe
omit =
    chronoframe/__main__.py
    tests/*

[report]
exclude_lines =
    pragma: no cover
    if __name__ == .__main__.:
    def __repr__
```

**Step 4: Handle `pip-audit` false positives**

If `pip-audit` flags a CVE that doesn't affect Chronoframe's usage (e.g., a web-specific vulnerability in `pyyaml` that only applies to YAML deserialization of untrusted input, which Chronoframe never does), add an explicit suppression:

```bash
pip-audit -r requirements.txt --ignore-vuln GHSA-xxxx-yyyy-zzzz
```

Document the reason for each suppression in a comment.

---

### E. Execution Plan

**Phase 1: Measure baseline coverage**

Locally:
```bash
cd /Users/nishithnand/Code/Chronoframe
pip install coverage pip-audit
coverage run -m unittest discover -s tests -t . -v
coverage report
pip-audit -r requirements.txt
```

Record results. If `pip-audit` finds any CVEs, evaluate and either update the dep or add a documented suppression.

**Phase 2: Add `.coveragerc`**

Create `.coveragerc` at project root with the configuration above.

**Phase 3: Edit `ci.yml`**

Apply the diff to `.github/workflows/ci.yml`. Set `--fail-under` based on Phase 1 measurement.

**Phase 4: Open PR and verify CI passes**

If coverage is below the threshold due to untested code paths, either:
- Add missing tests (preferred), or
- Adjust the threshold with a comment explaining the gap

---

### F. Testing Strategy

This plan adds testing infrastructure rather than tests. The "test" is that CI now fails when:
- A CVE is introduced in dependencies
- Coverage drops below the threshold

Verify by:
- Temporarily introducing a `pass` where a test would be and confirming CI catches the regression
- Running `pip-audit` with a known-CVE package to verify it fires

---

### G. Operational Plan

- No metrics or alerts needed — CI is the signal
- Coverage report artifact gives per-file breakdown for post-merge review
- If a dep update introduces a new CVE, `pip-audit` will block the PR immediately (Dependabot PRs run CI)

---

### H. Risks and Mitigations

| Risk | Mitigation |
|------|-----------|
| Current coverage below 80% | Measure first; start threshold at actual - 5%, ratchet up |
| `pip-audit` false positive blocks legitimate dep update | `--ignore-vuln` with documented reason |
| Coverage fluctuates on different OS/Python versions | Run on `ubuntu-latest` only (consistent with current CI) |

---

### I. Resourcing and Sequencing

- Phase 1 (measure): 30 minutes
- Phase 2–3 (edit files): 30 minutes
- Phase 4 (PR review): 1 hour (CI run + review)
- Total: ~2 hours, 1 engineer

Can run in parallel with Plans 1 and 2.

---

### J. Definition of Done

- [ ] `pip-audit -r requirements.txt` runs on every PR build and fails on CVE
- [ ] `coverage report --fail-under=N` runs on every PR build and fails on regression
- [ ] `coverage.xml` uploaded as CI artifact on every build
- [ ] `.coveragerc` added to project root
- [ ] CI green on main branch
- [ ] Any `pip-audit` suppressions documented with rationale

---

## Next Actions (concrete, executable)

1. **Open PR: "fix: scope cleanup_tmp_files to Chronoframe's own .tmp files"**
   - Edit `chronoframe/io.py`: add `_CHRONOFRAME_TMP_RE`, update `cleanup_tmp_files()`
   - Edit `ui/Sources/ChronoframeCore/TransferExecutor.swift`: add regex guard
   - Extend `tests/test_chronoframe.py`: 4 new test cases in `TestCleanupTmpFiles`
   - Estimated review time: 30 minutes

2. **Open PR: "fix: validate revert receipt paths against destination boundary"**
   - Edit `chronoframe/core.py`: add `dest_prefix` derivation and check loop
   - Edit `ui/Sources/ChronoframeCore/RevertExecutor.swift`: add `destPrefix` guard
   - Extend `tests/test_chronoframe.py`: 4 new test cases in `TestRevertReceipt`
   - Estimated review time: 45 minutes

3. **Open PR: "ci: add pip-audit and Python coverage gate"**
   - Edit `.github/workflows/ci.yml`: add audit and coverage steps
   - Add `.coveragerc`
   - Estimated review time: 20 minutes

4. **Open PR: "fix: quick wins batch — SQLite read locks, _event_subpath sanitization, receipt timestamps"**
   - `database.py`: add `with self._lock:` to `get_cache_dict()` and `get_pending_jobs()`
   - `core.py`: add `_UNSAFE_PATH_CHARS.sub('_', raw)` in `_event_subpath()`
   - `core.py`: add `started_at` parameter to `generate_audit_receipt()`
   - Estimated review time: 30 minutes

5. **File backlog ticket: "refactor: remove global _json_active / console state from core.py"**
   - Discipline: Backend
   - Effort: M (1–5 engineer-days)
   - Dependency: land coverage gate first so refactor doesn't silently break tests
