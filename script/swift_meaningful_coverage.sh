#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THRESHOLD="${1:-95}"

export HOME="$ROOT_DIR/.tmp/home"
export XDG_CACHE_HOME="$ROOT_DIR/.tmp/home/Library/Caches"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.tmp/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.tmp/modulecache"

cd "$ROOT_DIR"
mkdir -p "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH"

script/run_swift_test_suites.sh --coverage
rm -f ui/default.profraw

CODECOV_DIR="$(find ui/.build -type d -path '*/debug/codecov' -print -quit)"
TEST_BINARY="$(
    find ui/.build -type f \
        -path '*/debug/ChronoframeUIPackageTests.xctest/Contents/MacOS/ChronoframeUIPackageTests' \
        -print -quit
)"

if [[ -z "$CODECOV_DIR" || -z "$TEST_BINARY" ]]; then
    echo "SwiftPM coverage artifacts were not created." >&2
    exit 1
fi

PROFDATA_PATH="$CODECOV_DIR/default.profdata"
CODECOV_PATH="$CODECOV_DIR/ChronoframeUI.json"
xcrun llvm-profdata merge -sparse "$CODECOV_DIR"/*.profraw -o "$PROFDATA_PATH"
xcrun llvm-cov export "$TEST_BINARY" \
    -instr-profile="$PROFDATA_PATH" > "$CODECOV_PATH"

if [[ ! -f "$CODECOV_PATH" ]]; then
    echo "Coverage JSON not found at: $CODECOV_PATH" >&2
    exit 1
fi

# This gate intentionally excludes SwiftUI view bodies, app entry points,
# OS bridge wrappers, and other code where line coverage encourages shallow
# instantiation tests. It focuses on deterministic domain algorithms,
# planning, path building, hashing, indexing, and user-facing formatting.
#
# Edit MEANINGFUL_BASENAMES (not the regex) to add/remove files. Every
# basename listed here must resolve to a real .swift file under ui/Sources;
# the preflight loop below fails the build on phantom entries so the gate
# can't silently shrink when a file is renamed or removed.
MEANINGFUL_BASENAMES=(
    BLAKE2bHasher
    CopyPlanBuilder
    DryRunPlanner
    MediaDiscovery
    PlanningPathBuilder
    DeduplicationPlanner
    PerceptualHash
    UserFacingErrorMessage
    RunHistoryIndexer
    "RunConfiguration+Profiles"
    TransferExecutor
    RevertExecutor
    DeduplicateExecutor
    ReorganizeExecutor
    DedupeFeatureCache
    PreviewReviewModels
    LibraryHealthScanner
    ClusterAnnotator
    ClusterConfidenceScorer
    DuplicateClusterer
    FingerprintIndex
    PhotoQualityScorer
    SafetyWarningDetector
    FaceExpressionAnalyzer
    BookmarkPathResolver
    FileIdentityHasher
    FileSystemMonitor
    EngineDomainModels
    BundleValidator
    OrganizerDatabase
    MediaDateResolver
    DeduplicatePairDetector
    DeduplicateScanner
)

missing_basenames=()
for basename in "${MEANINGFUL_BASENAMES[@]}"; do
    if [[ -z "$(find ui/Sources -name "${basename}.swift" -print -quit)" ]]; then
        missing_basenames+=("$basename")
    fi
done
if (( ${#missing_basenames[@]} > 0 )); then
    echo "Phantom entries in MEANINGFUL_BASENAMES (no matching .swift under ui/Sources):" >&2
    for basename in "${missing_basenames[@]}"; do
        echo "  - ${basename}.swift" >&2
    done
    echo "Update the list in $(basename "$0") so the meaningful coverage gate stays load-bearing." >&2
    exit 2
fi

escape_regex_basename() {
    local input="$1"
    local escaped=""
    local i ch
    for (( i=0; i<${#input}; i++ )); do
        ch="${input:i:1}"
        case "$ch" in
            \\|.|\*|\+|\?|\(|\)|\[|\]|\{|\}|\||\^|\$|/)
                escaped+="\\${ch}"
                ;;
            *)
                escaped+="$ch"
                ;;
        esac
    done
    printf '%s' "$escaped"
}

regex_alternation=""
for basename in "${MEANINGFUL_BASENAMES[@]}"; do
    escaped="$(escape_regex_basename "$basename")"
    if [[ -z "$regex_alternation" ]]; then
        regex_alternation="$escaped"
    else
        regex_alternation+="|$escaped"
    fi
done
MEANINGFUL_REGEX="/(${regex_alternation})\\.swift\$"

summary_json="$(
    jq --arg regex "$MEANINGFUL_REGEX" '
        def add_lines:
            reduce .[] as $x ({count:0, covered:0};
                .count += $x.summary.lines.count
                | .covered += $x.summary.lines.covered
            )
            | .percent = (if .count == 0 then 0 else (.covered / .count * 100) end);

        .data[0].files as $files
        | {
            raw: ($files | map(.summary.lines) | reduce .[] as $x ({count:0, covered:0};
                .count += $x.count
                | .covered += $x.covered
            ) | .percent = (.covered / .count * 100)),
            meaningful: ($files | map(select(.filename | test($regex))) | add_lines),
            files: ($files
                | map(select(.filename | test($regex)))
                | map({
                    path: (.filename | sub("^.*/ui/Sources/"; "ui/Sources/")),
                    percent: .summary.lines.percent,
                    covered: .summary.lines.covered,
                    count: .summary.lines.count
                })
                | sort_by(.percent))
        }
    ' "$CODECOV_PATH"
)"

raw_percent="$(jq -r '.raw.percent' <<<"$summary_json")"
meaningful_percent="$(jq -r '.meaningful.percent' <<<"$summary_json")"
meaningful_covered="$(jq -r '.meaningful.covered' <<<"$summary_json")"
meaningful_count="$(jq -r '.meaningful.count' <<<"$summary_json")"

printf 'Raw Swift coverage: %.2f%%\n' "$raw_percent"
printf 'Meaningful Swift coverage: %.2f%% (%s/%s lines)\n' \
    "$meaningful_percent" "$meaningful_covered" "$meaningful_count"
echo
echo "Meaningful files:"
jq -r '.files[] | "  \(.path): \(.percent | tostring)% (\(.covered)/\(.count))"' <<<"$summary_json"

awk -v actual="$meaningful_percent" -v threshold="$THRESHOLD" '
    BEGIN {
        if (actual + 0.000001 < threshold) {
            printf("Meaningful Swift coverage %.2f%% is below the %.2f%% threshold.\n", actual, threshold) > "/dev/stderr"
            exit 1
        }
    }
'
