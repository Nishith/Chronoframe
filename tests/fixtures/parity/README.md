# Swift Engine Compatibility Fixtures

These fixtures preserve the planning and execution behavior that the Swift
engine was ported to match. The retired generator scripts are no longer part of
the repo; update `expected.json` only through an intentional Swift compatibility
change.

Each scenario directory contains:

- `manifest.json`: a language-neutral description of the source and destination
  trees to synthesize
- `expected.json`: normalized golden output for the Swift compatibility tests

The generated `expected.json` files intentionally normalize absolute paths into
source-relative and destination-relative paths so they remain stable across
machines and temp directories.
