#!/usr/bin/env bash
#
# Guards against shipping App-layer behavior changes with no test change.
#
# Why this exists: negative/regression tests in this repo cluster in the pure
# ChronoframeCore executors, because the coverage gate and the AGENTS-INVARIANT
# script both bite there. The App layer — SwiftUI views, view-models,
# coordinators, and the @MainActor stores — is where most user-visible bugs
# slip through, and fixes there have repeatedly landed with no accompanying
# test (e.g. a 7-source-file scrub with a single trivial test edit).
#
# The check is a heuristic nudge, not a proof: if the diff touches App-layer
# source, it must also touch a test file. It cannot verify the test is
# *relevant* — code review still owns that — but it makes "fix with zero
# tests" a deliberate, visible choice instead of the default.
#
# Usage:
#     script/check_app_layer_changes_have_tests.sh [BASE_REF]
#
# BASE_REF defaults to origin/main (falling back to main). The diff examined
# is merge-base(BASE_REF, HEAD)..HEAD, i.e. everything this branch adds.
#
# Escape hatch: for a genuinely test-free change (pure copy, styling, asset,
# or comment edits), include the literal token [skip-app-test-check] in any
# commit message on the branch. Use it sparingly and say why.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# App-layer source globs: the view/store/coordinator code that the coverage
# gate does not meaningfully reach. Core executors are intentionally excluded
# — they are covered by the coverage gate and the invariants script.
APP_LAYER_REGEX='^ui/Sources/ChronoframeApp/|^ui/Sources/ChronoframeAppCore/Stores/'
TEST_REGEX='^ui/Tests/'
SKIP_TOKEN='[skip-app-test-check]'

# Resolve the base ref.
BASE_REF="${1:-}"
if [[ -z "$BASE_REF" ]]; then
    if git rev-parse --verify --quiet origin/main >/dev/null; then
        BASE_REF="origin/main"
    else
        BASE_REF="main"
    fi
fi

if ! git rev-parse --verify --quiet "$BASE_REF" >/dev/null; then
    echo "Base ref '$BASE_REF' not found; nothing to compare against." >&2
    echo "Pass an explicit base: $(basename "${BASH_SOURCE[0]}") <ref>" >&2
    exit 2
fi

MERGE_BASE="$(git merge-base "$BASE_REF" HEAD)"
DIFF_RANGE="${MERGE_BASE}..HEAD"

changed_files="$(git diff --name-only "$DIFF_RANGE")"

if [[ -z "$changed_files" ]]; then
    echo "✓ No commits on this branch beyond ${BASE_REF}; nothing to check."
    exit 0
fi

app_layer_changes="$(printf '%s\n' "$changed_files" | grep -E "$APP_LAYER_REGEX" || true)"
test_changes="$(printf '%s\n' "$changed_files" | grep -E "$TEST_REGEX" || true)"

if [[ -z "$app_layer_changes" ]]; then
    echo "✓ No App-layer source changes in ${DIFF_RANGE}; nothing to check."
    exit 0
fi

if [[ -n "$test_changes" ]]; then
    n_app="$(printf '%s\n' "$app_layer_changes" | wc -l | tr -d ' ')"
    n_test="$(printf '%s\n' "$test_changes" | wc -l | tr -d ' ')"
    echo "✓ ${n_app} App-layer source file(s) changed alongside ${n_test} test file(s)."
    exit 0
fi

# App-layer source changed with no test change. Honor the escape hatch.
commit_messages="$(git log --format='%B' "$DIFF_RANGE")"
if printf '%s' "$commit_messages" | grep -qF "$SKIP_TOKEN"; then
    echo "⚠ App-layer source changed with no test change, but ${SKIP_TOKEN} is present — skipping."
    exit 0
fi

echo "✗ App-layer source changed in ${DIFF_RANGE} with no accompanying test change:" >&2
printf '%s\n' "$app_layer_changes" | sed 's/^/    /' >&2
echo >&2
echo "  Add or update a test for this change. The App layer (views, view-models," >&2
echo "  coordinators, stores) is where most bugs slip past the coverage gate." >&2
echo "  If this change genuinely has no testable behavior (pure copy, styling," >&2
echo "  asset, or comment edits), add ${SKIP_TOKEN} to a commit message and say why." >&2
exit 1
