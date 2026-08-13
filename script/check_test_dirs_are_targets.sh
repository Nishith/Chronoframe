#!/bin/bash
# Fail if a directory under ui/Tests is not declared as a testTarget in
# ui/Package.swift.
#
# Why this exists: writing a test file into a directory that no target claims
# compiles nothing and runs nothing, and `swift test` still passes. There is no
# error to notice — the suite is simply smaller than it looks. That happened
# once already: an entire test file sat in ui/Tests/ChronoframeCoreTests/, a
# directory no testTarget declares, and the only symptom was the coverage gate
# reporting 0% for a file with a full test suite next to it.
#
# This is the same failure mode script/check_uitest_membership.sh guards for
# ui/Xcode/UITests, one level up: there, a file missing from the target; here, a
# whole directory.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
package_manifest="${CHRONOFRAME_PACKAGE_MANIFEST:-$repo_root/ui/Package.swift}"
tests_root="${CHRONOFRAME_TESTS_ROOT:-$repo_root/ui/Tests}"

if [[ ! -f "$package_manifest" ]]; then
    echo "check_test_dirs_are_targets: no package manifest at $package_manifest" >&2
    exit 1
fi

if [[ ! -d "$tests_root" ]]; then
    echo "check_test_dirs_are_targets: no tests directory at $tests_root" >&2
    exit 1
fi

# The directory each testTarget compiles, as its last path component.
#
# Read per block rather than line by line: a target's declaration spans several
# lines and may carry comments containing brackets, so "the block ends at the
# first close paren" is wrong. A block runs until the next target of any kind.
#
# `path:` wins when present because that is what SwiftPM compiles; a target
# without one defaults to Tests/<name>, so the name is the fallback.
declared_dirs="$(
    awk '
        function lastComponent(spec,   parts, n) {
            n = split(spec, parts, "/")
            return parts[n]
        }
        function quoted(line, key,   spec) {
            if (!match(line, key ":[[:space:]]*\"[^\"]*\"")) return ""
            spec = substr(line, RSTART, RLENGTH)
            sub(key ":[[:space:]]*\"", "", spec)
            sub(/"$/, "", spec)
            return spec
        }
        function flush() {
            if (!in_target) return
            if (path != "") print lastComponent(path)
            else if (name != "") print name
            in_target = 0; name = ""; path = ""
        }
        /\.testTarget\(/ { flush(); in_target = 1; name = ""; path = ""; next }
        /\.executableTarget\(/ || /\.target\(/ { flush(); next }
        in_target && name == "" { candidate = quoted($0, "name"); if (candidate != "") name = candidate }
        in_target && path == "" { candidate = quoted($0, "path"); if (candidate != "") path = candidate }
        END { flush() }
    ' "$package_manifest" | sort -u
)"

if [[ -z "$declared_dirs" ]]; then
    echo "check_test_dirs_are_targets: parsed no testTarget paths from $package_manifest" >&2
    echo "The manifest format changed; this guard needs updating rather than removing." >&2
    exit 1
fi

undeclared=()
while IFS= read -r dir; do
    name="$(basename "$dir")"
    if ! grep -qxF "$name" <<<"$declared_dirs"; then
        undeclared+=("$name")
    fi
done < <(find "$tests_root" -mindepth 1 -maxdepth 1 -type d | sort)

if (( ${#undeclared[@]} > 0 )); then
    echo "Test directories that no testTarget declares:" >&2
    for name in "${undeclared[@]}"; do
        echo "  ui/Tests/$name" >&2
    done
    echo >&2
    echo "Nothing in these directories is compiled or run, and 'swift test' still passes." >&2
    echo "Either add a testTarget for the directory in ui/Package.swift, or move the" >&2
    echo "tests into a target that already exists." >&2
    exit 1
fi

echo "check_test_dirs_are_targets: OK (${declared_dirs//$'\n'/, })"
