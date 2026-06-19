#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COVERAGE_FLAG=""

if [[ "${1:-}" == "--coverage" ]]; then
    COVERAGE_FLAG="--enable-code-coverage"
elif [[ $# -gt 0 ]]; then
    echo "Usage: $(basename "$0") [--coverage]" >&2
    exit 2
fi

export HOME="$ROOT_DIR/.tmp/home"
export XDG_CACHE_HOME="$ROOT_DIR/.tmp/home/Library/Caches"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.tmp/modulecache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.tmp/modulecache"

cd "$ROOT_DIR"
mkdir -p "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH" .tmp

test_list=".tmp/swift-test-identifiers.txt"
suite_counts=".tmp/swift-test-suite-counts.txt"
swift test list ${COVERAGE_FLAG:+$COVERAGE_FLAG} --package-path ui --disable-sandbox \
    | grep -E '^[[:alnum:]_]+\.[[:alnum:]_]+/' > "$test_list"

if [[ ! -s "$test_list" ]]; then
    echo "SwiftPM did not discover any XCTest suites." >&2
    exit 1
fi

awk -F/ '{ counts[$1] += 1 } END { for (suite in counts) print suite, counts[suite] }' \
    "$test_list" | sort > "$suite_counts"

if [[ -n "$COVERAGE_FLAG" ]]; then
    coverage_profile_store=".tmp/swift-suite-profraw"
    rm -rf "$coverage_profile_store"
    mkdir -p "$coverage_profile_store"
    find ui/.build -type f -path '*/debug/codecov/*.profraw' -delete 2>/dev/null || true
fi

# GitHub's macos-14-arm64 image selects Swift 6.0.3. Its XCTest process can
# stop advancing after several seconds in Chronoframe's full suite even though
# every test reached so far has passed. Short, count-bounded shards avoid that
# runtime bug while preserving complete discovery, execution, and (when
# requested) aggregate profraw coverage without paying one startup per suite.
SKIP_BUILD_FLAG=""
SHARD_INDEX=0
MAX_TESTS_PER_SHARD=100

run_shard() {
    shard_filter="$1"
    shard_test_count="$2"
    SHARD_INDEX=$((SHARD_INDEX + 1))

    if [[ -n "$COVERAGE_FLAG" ]]; then
        find ui/.build -type f -path '*/debug/codecov/*.profraw' -delete 2>/dev/null || true
    fi

    echo "Running Swift test shard $SHARD_INDEX ($shard_test_count tests)"
    swift test ${COVERAGE_FLAG:+$COVERAGE_FLAG} --package-path ui --disable-sandbox \
        ${SKIP_BUILD_FLAG:+$SKIP_BUILD_FLAG} --filter "^(${shard_filter})/"
    SKIP_BUILD_FLAG="--skip-build"

    if [[ -n "$COVERAGE_FLAG" ]]; then
        profile_count=0
        while IFS= read -r profile; do
            cp "$profile" "$coverage_profile_store/shard-${SHARD_INDEX}-$(basename "$profile")"
            profile_count=$((profile_count + 1))
        done < <(find ui/.build -type f -path '*/debug/codecov/*.profraw' -print)

        if (( profile_count == 0 )); then
            echo "No coverage profile was produced for shard $SHARD_INDEX." >&2
            exit 1
        fi
    fi
}

current_filter=""
current_test_count=0
while read -r suite suite_test_count; do
    if (( current_test_count > 0 && current_test_count + suite_test_count > MAX_TESTS_PER_SHARD )); then
        run_shard "$current_filter" "$current_test_count"
        current_filter=""
        current_test_count=0
    fi

    escaped_suite="${suite//./\\.}"
    if [[ -z "$current_filter" ]]; then
        current_filter="$escaped_suite"
    else
        current_filter="$current_filter|$escaped_suite"
    fi
    current_test_count=$((current_test_count + suite_test_count))
done < "$suite_counts"

if (( current_test_count > 0 )); then
    run_shard "$current_filter" "$current_test_count"
fi

if [[ -n "$COVERAGE_FLAG" ]]; then
    codecov_dir="$(find ui/.build -type d -path '*/debug/codecov' -print -quit)"
    if [[ -z "$codecov_dir" ]]; then
        echo "SwiftPM coverage directory was not created." >&2
        exit 1
    fi
    find "$codecov_dir" -type f -name '*.profraw' -delete
    cp "$coverage_profile_store"/*.profraw "$codecov_dir/"
    find "$codecov_dir" -type f \( -name '*.profdata' -o -name '*.json' \) -delete
fi
