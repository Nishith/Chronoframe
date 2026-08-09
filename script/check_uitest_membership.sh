#!/usr/bin/env bash
#
# Fails when a UI-test source file exists on disk but is not compiled by the
# ChronoframeUITests target.
#
# Why this needs a guard at all: `ui/Xcode/UITests/` is the one source directory
# in this repository with no automatic membership. It is not a SwiftPM target,
# so `swift test` never sees it, and Xcode compiles only what
# `project.pbxproj` references. A UI test dropped into that directory without
# being registered is silently never built and never run — and every CI lane
# stays green, because nothing is compiling it to notice. That is the worst
# shape a coverage gap can take: the test exists, it appears in the diff, a
# reviewer reads it, and it never executes.
#
# Everything else in the project is self-maintaining and deliberately out of
# scope here: `ui/Sources/` is covered by the Xcode file-system-synchronized
# root groups, and `ui/Tests/` is discovered by SwiftPM.
#
# The check resolves the target's real build phase rather than grepping the
# whole project file, so a stray reference from some other target cannot
# satisfy it.
#
# Usage:
#     script/check_uitest_membership.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PROJECT_FILE="ui/Chronoframe.xcodeproj/project.pbxproj"
UITEST_DIR="ui/Xcode/UITests"
TARGET_NAME="ChronoframeUITests"

if [[ ! -f "$PROJECT_FILE" ]]; then
    echo "✗ Xcode project not found at $PROJECT_FILE" >&2
    exit 1
fi

if [[ ! -d "$UITEST_DIR" ]]; then
    echo "✓ $UITEST_DIR does not exist; nothing to check."
    exit 0
fi

# 1. Find the Sources build phase belonging to the ChronoframeUITests native
#    target. Scoping to the target matters: the project has three Sources
#    phases, and a file listed in the wrong one is not built by this target.
phase_id="$(
    awk -v target="$TARGET_NAME" '
        $0 ~ "^[[:space:]]*[A-Za-z0-9]+ \\/\\* " target " \\*\\/ = \\{$" { in_block = 1 }
        in_block && /isa = PBXNativeTarget;/ { is_native = 1 }
        in_block && is_native && match($0, /[A-Za-z0-9]+ \/\* Sources \*\//) {
            id = substr($0, RSTART, RLENGTH)
            sub(/ .*/, "", id)
            print id
            exit
        }
        in_block && /^[[:space:]]*\};$/ { in_block = 0; is_native = 0 }
    ' "$PROJECT_FILE"
)"

if [[ -z "$phase_id" ]]; then
    echo "✗ Could not locate the Sources build phase for the $TARGET_NAME target." >&2
    echo "  The project layout changed; update $(basename "$0") to match." >&2
    exit 2
fi

# 2. Read that phase's build-file IDs.
build_file_ids="$(
    awk -v phase="$phase_id" '
        $0 ~ "^[[:space:]]*" phase " \\/\\* Sources \\*\\/ = \\{$" { in_phase = 1 }
        in_phase && /files = \(/ { in_files = 1; next }
        in_phase && in_files && /^[[:space:]]*\);$/ { exit }
        in_phase && in_files { print $1 }
    ' "$PROJECT_FILE"
)"

# 3. Resolve each build file to the path of the file reference it points at.
#
#    Deliberately NOT the `/* Name */` display comment: that is cosmetic, it
#    holds only a basename, and two files in different subdirectories share it.
#    Matching on the comment would let `Nested/Foo.swift` satisfy itself against
#    a registered root `Foo.swift` and report a clean pass for a file that is
#    never compiled — precisely the failure this guard exists to prevent.
#
#    Paths are relative to the group (`sourceTree = "<group>"` under the
#    `UITests` group), which makes them relative to $UITEST_DIR.
registered_paths=()
unresolved=()
while IFS= read -r build_id; do
    [[ -z "$build_id" ]] && continue

    build_line="$(grep -E "^[[:space:]]*${build_id} .*isa = PBXBuildFile" "$PROJECT_FILE" || true)"
    ref_id="$(sed -nE 's/.*fileRef = ([A-Za-z0-9]+).*/\1/p' <<<"$build_line")"
    if [[ -z "$ref_id" ]]; then
        unresolved+=("$build_id (no fileRef)")
        continue
    fi

    ref_line="$(grep -E "^[[:space:]]*${ref_id} .*isa = PBXFileReference" "$PROJECT_FILE" || true)"
    ref_path="$(sed -nE 's/.*[[:space:];]path = "?([^";]*)"?;.*/\1/p' <<<"$ref_line")"
    if [[ -z "$ref_path" ]]; then
        unresolved+=("$build_id -> $ref_id (no path)")
        continue
    fi

    registered_paths+=("$ref_path")
done <<<"$build_file_ids"

path_is_registered() {
    local needle="$1" candidate
    for candidate in ${registered_paths+"${registered_paths[@]}"}; do
        [[ "$candidate" == "$needle" ]] && return 0
    done
    return 1
}

# 4. Every .swift on disk must be one of those paths.
missing=()
while IFS= read -r file; do
    relative="${file#"$UITEST_DIR/"}"
    if ! path_is_registered "$relative"; then
        missing+=("$file")
    fi
done < <(find "$UITEST_DIR" -name '*.swift' -type f | sort)

# 5. And every registered path must still exist on disk, so a deleted file
#    leaves a loud dangling reference rather than a confusing build error.
dangling=()
for referenced in ${registered_paths+"${registered_paths[@]}"}; do
    if [[ ! -f "$UITEST_DIR/$referenced" ]]; then
        dangling+=("$referenced")
    fi
done

status=0

# A build file we cannot resolve would otherwise be silently dropped from the
# registered set, which turns into a false "missing" report or, worse, a false
# pass. Fail loudly instead so the script gets fixed rather than trusted.
if [[ ${#unresolved[@]} -gt 0 ]]; then
    echo "✗ Could not resolve $TARGET_NAME build file(s) to a file reference path:" >&2
    for entry in "${unresolved[@]}"; do
        echo "      $entry" >&2
    done
    echo >&2
    echo "  The project layout changed; update $(basename "$0") to match." >&2
    exit 2
fi

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "✗ UI-test file(s) on disk but not compiled by the $TARGET_NAME target:" >&2
    for file in "${missing[@]}"; do
        echo "      $file" >&2
    done
    echo >&2
    echo "  These files are never built and never run, and no other CI lane will" >&2
    echo "  catch that — $UITEST_DIR is outside SwiftPM, so only the Xcode" >&2
    echo "  project decides what compiles." >&2
    echo >&2
    echo "  Add each file to the $TARGET_NAME target in Xcode (or add the" >&2
    echo "  matching PBXFileReference, PBXBuildFile, group child, and Sources" >&2
    echo "  build-phase entries in $PROJECT_FILE), then re-run this check." >&2
    status=1
fi

if [[ ${#dangling[@]} -gt 0 ]]; then
    [[ $status -ne 0 ]] && echo >&2
    echo "✗ $TARGET_NAME references file(s) that no longer exist in $UITEST_DIR:" >&2
    for referenced in "${dangling[@]}"; do
        echo "      $referenced" >&2
    done
    echo >&2
    echo "  Remove the stale references from $PROJECT_FILE." >&2
    status=1
fi

if [[ $status -ne 0 ]]; then
    exit $status
fi

swift_count="$(find "$UITEST_DIR" -name '*.swift' -type f | wc -l | tr -d ' ')"
echo "✓ All $swift_count UI-test source file(s) in $UITEST_DIR are compiled by the $TARGET_NAME target."
