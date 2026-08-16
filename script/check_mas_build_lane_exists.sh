#!/bin/bash
# Fail if no CI job builds with SWIFT_ACTIVE_COMPILATION_CONDITIONS=MAS_BUILD.
#
# Why this exists: the Mac App Store lane is the only thing that type-checks
# `#if MAS_BUILD` code. Deleting the job would be noticed; deleting just the
# flag would not — the lane keeps building, keeps passing, and quietly checks
# the same configuration every other lane already covers. The failure mode is a
# green board over a store binary nothing has compiled.
#
# `RuntimePaths.repositoryRootURL()` is the standing example: it exists only in
# the `#else`, so a reference to it from shared code builds everywhere except
# the binary customers actually get.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="${CHRONOFRAME_CI_WORKFLOW:-$repo_root/.github/workflows/ci.yml}"

if [[ ! -f "$workflow" ]]; then
    echo "check_mas_build_lane_exists: no workflow at $workflow" >&2
    exit 1
fi

# Matched loosely on purpose: quoting and line breaks around the flag are the
# workflow author's business, but the setting has to be there somewhere.
if ! grep -q 'SWIFT_ACTIVE_COMPILATION_CONDITIONS=MAS_BUILD' "$workflow"; then
    echo "No CI job passes SWIFT_ACTIVE_COMPILATION_CONDITIONS=MAS_BUILD." >&2
    echo >&2
    echo "Without it, every '#if MAS_BUILD' branch is compiled by zero lanes, and" >&2
    echo "a break in the shipping Mac App Store build passes CI unnoticed." >&2
    echo "Restore the flag in the Mac App Store build job in ${workflow#"$repo_root/"}." >&2
    exit 1
fi

echo "check_mas_build_lane_exists: OK"
