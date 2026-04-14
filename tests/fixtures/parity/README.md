# Planning Parity Fixtures

These fixtures freeze Python dry-run planning behavior so the future Swift
planner can be compared against the same corpus.

Each scenario directory contains:

- `manifest.json`: a language-neutral description of the source and destination
  trees to synthesize
- `expected.json`: normalized golden output from the Python reference engine

Regenerate the checked-in golden outputs with:

```bash
python3 tests/fixtures/parity/generate_planning_golden.py --write
```

The generated `expected.json` files intentionally normalize absolute paths into
source-relative and destination-relative paths so they remain stable across
machines and temp directories.
