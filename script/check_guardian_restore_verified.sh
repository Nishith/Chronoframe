#!/usr/bin/env bash
#
# Enforces the Library Guardian verified-restore safety invariant
# (AGENTS-INVARIANT 25): the restore executor may overwrite a library file only
# from a mirror copy that it re-verifies against the trusted digest at commit
# time — the immutable plan alone is never sufficient against a TOCTOU race.
#
# Restore is the one Guardian surface that writes the library, so this guard
# makes it a loud CI failure if a future edit removes any part of the commit-time
# verification seam from GuardianRestoreExecutor.swift:
#
#   * the mirror is opened O_NOFOLLOW (a symlink swapped in after planning cannot
#     redirect the copy source);
#   * the bytes hashed are the SAME descriptor used as the copy source
#     (hashIdentity(descriptor:) — not a fresh open that could see different bytes);
#   * that hash is checked to equal the trusted identity before anything is
#     installed;
#   * the replacement is installed with an atomic, no-overwrite rename
#     (RENAME_EXCL) so an existing file is never clobbered in place.
#
# Comment lines are stripped before scanning, so a docstring that merely *names*
# these tokens cannot satisfy the guard — the real code must contain them.
#
# Usage:
#     script/check_guardian_restore_verified.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXECUTOR="ui/Sources/ChronoframeCore/GuardianRestoreExecutor.swift"

if [[ ! -f "$EXECUTOR" ]]; then
    echo "✗ $EXECUTOR not found; the verified-restore executor must exist." >&2
    exit 1
fi

# Strip whole-line comments (// , /// , * , /* ) so documentation naming these
# tokens does not satisfy the guard — only real code counts.
code_only="$(grep -vE '^[[:space:]]*(//|\*|/\*)' "$EXECUTOR")"

# Each required token, with a human-readable reason for the failure message.
declare -a tokens=(
    "O_NOFOLLOW|opens the mirror O_NOFOLLOW so a symlink swap cannot redirect the copy source"
    "hashIdentity(descriptor:|hashes the same descriptor it copies from (commit-time re-verification)"
    "action.trustedIdentity|verifies the mirror bytes against the trusted digest before installing"
    "RENAME_EXCL|installs the replacement with an atomic, no-overwrite rename"
)

missing=0
for entry in "${tokens[@]}"; do
    token="${entry%%|*}"
    reason="${entry#*|}"
    if ! printf '%s\n' "$code_only" | grep -qF "$token"; then
        if [[ $missing -eq 0 ]]; then
            echo "✗ Guardian restore is missing its commit-time verification seam:" >&2
        fi
        echo "  missing '$token' — the executor must $reason." >&2
        missing=$((missing + 1))
    fi
done

if [[ $missing -gt 0 ]]; then
    echo >&2
    echo "  Verified restore overwrites the library only from a mirror copy that" >&2
    echo "  re-verifies against the trusted digest at commit time (AGENTS.md" >&2
    echo "  Safety Invariants, #25). Do not remove the O_NOFOLLOW open, the" >&2
    echo "  same-descriptor hash, the trusted-identity check, or the atomic" >&2
    echo "  no-overwrite install." >&2
    exit 1
fi

echo "✓ Guardian restore keeps its commit-time verification seam (O_NOFOLLOW + same-descriptor hash + trusted-identity check + atomic no-overwrite install)."
