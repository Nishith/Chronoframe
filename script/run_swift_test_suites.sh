#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COVERAGE_ARGS=()

if [[ "${1:-}" == "--coverage" ]]; then
    COVERAGE_ARGS=(--enable-code-coverage)
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

test_list=".tmp/swift-test-suites.txt"
swift test list "${COVERAGE_ARGS[@]}" --package-path ui --disable-sandbox \
    | grep -E '^[[:alnum:]_]+\.[[:alnum:]_]+/' \
    | cut -d/ -f1 \
    | sort -u > "$test_list"

if [[ ! -s "$test_list" ]]; then
    echo "SwiftPM did not discover any XCTest suites." >&2
    exit 1
fi

if (( ${#COVERAGE_ARGS[@]} > 0 )); then
    coverage_profile_store=".tmp/swift-suite-profraw"
    rm -rf "$coverage_profile_store"
    mkdir -p "$coverage_profile_store"
    find ui/.build -type f -path '*/debug/codecov/*.profraw' -delete 2>/dev/null || true
fi

# GitHub's macos-14-arm64 image selects Swift 6.0.3. Its XCTest process can
# stop advancing after several seconds in Chronoframe's full suite even though
# every test reached so far has passed. A fresh process per XCTestCase avoids
# that runtime bug while preserving complete discovery, execution, and (when
# requested) aggregate profraw coverage.
SKIP_BUILD_ARGS=()
while IFS= read -r suite; do
    if (( ${#COVERAGE_ARGS[@]} > 0 )); then
        find ui/.build -type f -path '*/debug/codecov/*.profraw' -delete 2>/dev/null || true
    fi

    escaped_suite="${suite//./\\.}"
    swift test "${COVERAGE_ARGS[@]}" --package-path ui --disable-sandbox \
        "${SKIP_BUILD_ARGS[@]}" --filter "^${escaped_suite}/"
    SKIP_BUILD_ARGS=(--skip-build)

    if (( ${#COVERAGE_ARGS[@]} > 0 )); then
        profiles=()
        while IFS= read -r profile; do
            profiles+=("$profile")
        done < <(find ui/.build -type f -path '*/debug/codecov/*.profraw' -print)

        if (( ${#profiles[@]} == 0 )); then
            echo "No coverage profile was produced for $suite." >&2
            exit 1
        fi

        safe_suite="${suite//./_}"
        for profile in "${profiles[@]}"; do
            cp "$profile" "$coverage_profile_store/${safe_suite}-$(basename "$profile")"
        done
    fi
done < "$test_list"

if (( ${#COVERAGE_ARGS[@]} > 0 )); then
    codecov_dir="$(find ui/.build -type d -path '*/debug/codecov' -print -quit)"
    if [[ -z "$codecov_dir" ]]; then
        echo "SwiftPM coverage directory was not created." >&2
        exit 1
    fi
    find "$codecov_dir" -type f -name '*.profraw' -delete
    cp "$coverage_profile_store"/*.profraw "$codecov_dir/"
    find "$codecov_dir" -type f \( -name '*.profdata' -o -name '*.json' \) -delete
fi
