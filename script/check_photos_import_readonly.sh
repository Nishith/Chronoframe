#!/usr/bin/env bash
#
# Enforces the Apple Photos read-only safety invariant (AGENTS-INVARIANT 22):
# the Photos import path must never call a mutating PhotoKit API.
#
# Chronoframe imports COPIES of Photos originals and never modifies, moves,
# favorites, or deletes anything in the user's library. The export seam
# (`PhotosResourceExporting`) is read-only by construction — it has no mutating
# method — but a future edit could import PhotoKit and reach a change request
# directly. This guard makes that a loud CI failure.
#
# Scope: every Swift file under ui/Sources that imports Photos. This is
# self-maintaining — any new Photos-touching file (catalog, export, thumbnail,
# view) is scanned automatically.
#
# Comment lines are stripped before scanning so docstrings that *name* the
# forbidden APIs (to explain that they are never called) do not trip the guard.
#
# Usage:
#     script/check_photos_import_readonly.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# Mutating PhotoKit entry points. Reads (fetchAssets, assetResources,
# PHAssetResourceManager, requestAuthorization, PHCachingImageManager) are all
# allowed and intentionally absent from this list.
FORBIDDEN_REGEX='performChanges|performChangesAndWait|PHAssetChangeRequest|PHAssetCreationRequest|PHAssetCollectionChangeRequest|PHCollectionListChangeRequest|creationRequestForAsset|deleteAssets'

mapfile -t photos_files < <(grep -rl --include='*.swift' 'import Photos' ui/Sources || true)

if [[ ${#photos_files[@]} -eq 0 ]]; then
    echo "✓ No Swift files under ui/Sources import Photos; nothing to check."
    exit 0
fi

violations=0
for file in "${photos_files[@]}"; do
    # Strip whole-line comments (// , /// , * , /* ) before scanning so that
    # documentation naming the forbidden APIs is not flagged.
    if grep -vE '^[[:space:]]*(//|\*|/\*)' "$file" \
        | grep -nE "$FORBIDDEN_REGEX" >/dev/null; then
        if [[ $violations -eq 0 ]]; then
            echo "✗ Mutating PhotoKit API found in the read-only Photos import path:" >&2
        fi
        echo "  $file:" >&2
        grep -vE '^[[:space:]]*(//|\*|/\*)' "$file" \
            | grep -nE "$FORBIDDEN_REGEX" \
            | sed 's/^/      /' >&2
        violations=$((violations + 1))
    fi
done

if [[ $violations -gt 0 ]]; then
    echo >&2
    echo "  Photos import is strictly read-only (AGENTS.md Safety Invariants)." >&2
    echo "  Copy originals out with PHAssetResourceManager; never mutate the library." >&2
    exit 1
fi

echo "✓ Photos import path is read-only across ${#photos_files[@]} file(s) importing Photos."
