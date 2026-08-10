#!/usr/bin/env bash
#
# Asserts that codeql.yml's `paths` and codeql-skip.yml's `paths-ignore` are
# identical lists.
#
# `Analyze (Swift)` is a required status check. codeql.yml runs the real
# analysis for PRs touching Swift; codeql-skip.yml reports the same check name
# for everything else. The two filters must be exact complements:
#
#   - A path in NEITHER list  -> no workflow runs, the required check never
#     reports, and the PR blocks on "Expected — waiting for status to be
#     reported" forever.
#   - A path in BOTH lists    -> the skip job can report `Analyze (Swift)`
#     success for a pull request that genuinely needed analysis. That is the
#     dangerous direction: a green check asserting CodeQL looked at code it
#     never saw.
#
# A comment asking humans to keep two lists in sync is not a guarantee, which
# is the entire reason this script exists.
#
# Usage:
#     script/check_codeql_path_filters.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ANALYZE_WORKFLOW=".github/workflows/codeql.yml"
SKIP_WORKFLOW=".github/workflows/codeql-skip.yml"

for file in "$ANALYZE_WORKFLOW" "$SKIP_WORKFLOW"; do
    if [[ ! -f "$file" ]]; then
        echo "✗ Missing $file" >&2
        echo "  The required-check pairing needs both workflows; see $file's header." >&2
        exit 1
    fi
done

extract() {
    python3 - "$1" "$2" <<'PY'
import sys, yaml

path, key = sys.argv[1], sys.argv[2]
with open(path) as handle:
    doc = yaml.safe_load(handle)

# PyYAML parses the unquoted `on:` key as the boolean True.
triggers = doc.get("on", doc.get(True))
if not isinstance(triggers, dict):
    sys.exit(f"{path}: could not read the workflow's trigger block")

pull_request = triggers.get("pull_request")
if not isinstance(pull_request, dict):
    sys.exit(f"{path}: no pull_request trigger")

values = pull_request.get(key)
if not values:
    sys.exit(f"{path}: pull_request has no '{key}' list")

print("\n".join(values))
PY
}

analyze_paths="$(extract "$ANALYZE_WORKFLOW" paths)"
skip_paths="$(extract "$SKIP_WORKFLOW" paths-ignore)"

if [[ "$analyze_paths" != "$skip_paths" ]]; then
    echo "✗ CodeQL path filters have drifted apart." >&2
    echo >&2
    echo "  $ANALYZE_WORKFLOW  ->  paths:" >&2
    sed 's/^/      /' <<<"$analyze_paths" >&2
    echo "  $SKIP_WORKFLOW  ->  paths-ignore:" >&2
    sed 's/^/      /' <<<"$skip_paths" >&2
    echo >&2
    echo "  Only in paths (these PRs would block forever):" >&2
    comm -23 <(sort <<<"$analyze_paths") <(sort <<<"$skip_paths") | sed 's/^/      /' >&2
    echo "  Only in paths-ignore (these PRs could be greened WITHOUT analysis):" >&2
    comm -13 <(sort <<<"$analyze_paths") <(sort <<<"$skip_paths") | sed 's/^/      /' >&2
    echo >&2
    echo "  Make the two lists identical, including order." >&2
    exit 1
fi

count="$(wc -l <<<"$analyze_paths" | tr -d ' ')"
echo "✓ CodeQL analyze/skip path filters match across $count path(s)."
