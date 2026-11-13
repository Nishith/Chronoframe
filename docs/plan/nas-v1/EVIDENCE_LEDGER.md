# NAS evidence ledger

Release record required by `docs/NAS_REQUIREMENTS.md` section 17.2. Every row below needs the owner's hardware, a signed build, VoiceOver, or the owner's network, so every row is `todo-hardware` (D-NAS-60). Agents never mark a row pass; Nishith records the result. Redact private paths and server names in any public copy.

The probe tool is local only and is built but never run against a share in CI (D-NAS-61). Run it only against an empty, disposable folder you created on the share; it writes inside `.chronoframe-nas-probe-<uuid>/` and removes it. `make-corpus` needs an empty folder. `assess-parity` only reads the corpus and keeps its state on this Mac.

## Commands

Run from the repo root after `docs/plan/nas-v1/bin/nas_swift.sh build`:

```bash
ui/.build/debug/ChronoframeNASProbeTool probe --test-dir "/Volumes/<share>/<empty-test-folder>" > probe.json
ui/.build/debug/ChronoframeNASProbeTool make-corpus --dest "/Volumes/<share>/<empty-corpus-folder>" --manifest "$HOME/nas-corpus-manifest.json" --files 10000 --duplicate-percent 20 --seed 42
ui/.build/debug/ChronoframeNASProbeTool assess-parity --root "/Volumes/<share>/<corpus-folder>" --state-dir "$HOME/nas-parity-state" > parity.json
```

## Ledger

Columns follow section 17.2. `Status` is `todo-hardware` until the owner records the result.

| ID | Requirement / test ID | Capability / profile | Commit / build / signing | Date / operator | Exact procedure / command | Corpus manifest / digests | Mac / NAS / network settings | Expected / actual behavior | Duration / memory / local footprint / I/O | Before / after hashes and counts | Receipts / journals / screenshots | Recovery rerun result | Limitation or failure disposition | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| H1 | Slice 0, ADR-NAS-01/02/03, T06, T11 | Named signed Synology SMB profile | | | `probe --test-dir` on the share (P01 to P07), including whether RENAME_EXCL is supported; save `probe.json` | n/a | | Expected: P03, P04, P05 pass; P04 leaves the existing bytes' digest unchanged; actual: | | | `probe.json` | | | todo-hardware |
| H2 | T21 P0, NAS-NFR-09, V1 reference corpus | Exact assessment, reference corpus | | | `make-corpus` (10,000 files, 20% duplicates, seed 42), then `assess-parity` three matched cold runs; save `parity.json` per run | `$HOME/nas-corpus-manifest.json` (record its SHA-256) | | Expected: `parity: true`, ledger within the NAS-NFR-09 budget in all three runs; actual: | | | `parity.json` x3 | | | todo-hardware |
| H3 | T04, T05, T09, T15 | Signed sandboxed build | | | Choose share, assess, quit, relaunch, confirm review restored, remount under another path | | | Expected: saved review restored; remount recognized as the same library; actual: | | | Screenshots | | | todo-hardware |
| H4 | T04 | Read-only share assessment | | | Assess a share with no write access to the account; compare server-side change history before and after | | | Expected: no server-side changes; actual: | | | Share change log | | | todo-hardware |
| H5 | T16, NAS-REC-09 | Disconnect, sleep, wake | | | Disconnect the share, then sleep and wake the Mac, during a scan and during a copy | | | Expected: scan ends "waiting for your NAS" without data loss; copy stops cleanly and resumes; actual: | | | Screenshots, receipts, journals | | | todo-hardware |
| H6 | T11, T18 | Verified copy to and from the share | | | Representative batch of at least 100 files / 10 GiB each way, plus a forced quota-full fault | | | Expected: every copy verified, no overwrite, quota fault stops cleanly with originals untouched; actual: | | | Receipts, before/after hashes | | | todo-hardware |
| H7 | T20 | Accessibility | | | VoiceOver, keyboard, increased text and reduced motion pass over the NAS workspace | | | Expected: every control reachable and labeled; actual: | | | Notes, screenshots | | | todo-hardware |
| H8 | NAS-NFR-01 to NFR-04 | Latency, memory, cancel | | | Measure on the reference corpus (use `wallSeconds` and `ruMaxrss` from `parity.json`) | | | Expected: within the NAS-NFR-01 to NFR-04 targets; actual: | | | `parity.json` | | | todo-hardware |
