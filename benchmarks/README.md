# Chronoframe Benchmarks

This directory holds the phase-0 baseline harness for the Python reference engine.

The initial budgets for the native refactor are:

- No more than 5% throughput regression versus the Python reference on the same machine for source hashing, destination indexing, fast-destination preview, and filename-based classification.
- App-side log buffering must remain bounded in memory.
- Large-run verification must continue to use the existing artifact and queue layout unchanged.

Run the synthetic benchmark harness with:

```bash
python3 benchmarks/run_benchmarks.py --source-count 400 --dest-count 600 --workers 8
```

The harness prints a JSON summary with timing and throughput figures for:

- Source hashing
- Destination indexing
- Cached `--fast-dest` indexing
- Date classification
- CLI dry-run preview planning

Use the same input sizes and machine when comparing changes across phases.
