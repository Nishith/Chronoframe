#!/usr/bin/env bash
#
# Every sidebar destination's root detail view must publish a navigation title.
#
# Why this exists: on macOS the unified toolbar is what insets a
# `NavigationSplitView`'s detail column below the window titlebar. The sidebar
# deliberately runs full height behind that chrome (hence the hand-rolled
# `DesignTokens.Sidebar.titlebarClearance`), but the detail column relies on the
# toolbar for its top inset. A destination that publishes neither a navigation
# title nor a toolbar item leaves the toolbar with nothing to draw: the detail
# column then starts at the very top of the window and the window title —
# inherited from the sidebar, so it reads "Chronoframe" — paints straight over
# the view's own header text.
#
# That is exactly how `PhotosImportView` shipped: it was the only destination
# without a `.navigationTitle`, and its header collided with the window title.
# Nothing else catches it — the app builds, every test passes, and the damage
# is only visible on screen.
#
# Scope: the view types `RootSplitView.detailView` switches to, read out of the
# source so new destinations are covered automatically. The check is a
# heuristic — it confirms the file mentions `navigationTitle`, not that the
# modifier is applied unconditionally on every path.
#
# Usage:
#     script/check_detail_views_set_navigation_title.sh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_SPLIT_VIEW="ui/Sources/ChronoframeApp/Views/RootSplitView.swift"

if [[ ! -f "$ROOT_SPLIT_VIEW" ]]; then
    echo "✗ Cannot find $ROOT_SPLIT_VIEW; update this guard." >&2
    exit 1
fi

# Pull the detail view type names out of the `detailView` switch body. The
# property ends at the first closing brace back at four-space indentation.
mapfile -t detail_views < <(
    awk '
        /private var detailView/ { in_block = 1; next }
        in_block && /^    \}$/   { in_block = 0 }
        in_block && match($0, /[A-Za-z][A-Za-z0-9_]*View\(appState:/) {
            print substr($0, RSTART, RLENGTH - length("(appState:"))
        }
    ' "$ROOT_SPLIT_VIEW" | sort -u
)

if [[ ${#detail_views[@]} -eq 0 ]]; then
    echo "✗ Parsed no detail views out of $ROOT_SPLIT_VIEW; update this guard." >&2
    exit 1
fi

violations=0
for view in "${detail_views[@]}"; do
    file="$(find ui/Sources/ChronoframeApp -type f -name "${view}.swift" -print -quit)"
    if [[ -z "$file" ]]; then
        echo "✗ No source file found for detail view ${view}." >&2
        violations=$((violations + 1))
        continue
    fi

    # Strip whole-line comments so this very explanation, quoted in a docstring,
    # cannot satisfy the check on a view that never applies the modifier. The
    # stripped source goes through a variable rather than a pipe into `grep -q`,
    # which would exit early and SIGPIPE the upstream grep under `pipefail`.
    code="$(grep -vE '^[[:space:]]*(//|\*|/\*)' "$file" || true)"
    if ! printf '%s\n' "$code" | grep -q 'navigationTitle'; then
        if [[ $violations -eq 0 ]]; then
            echo "✗ Detail destination views missing a navigation title:" >&2
        fi
        echo "  $file" >&2
        violations=$((violations + 1))
    fi
done

if [[ $violations -gt 0 ]]; then
    echo >&2
    echo "  Add .navigationTitle(…) to the view's body. Without it the window has" >&2
    echo "  no toolbar on that destination, the detail column draws under the" >&2
    echo "  titlebar, and the window title overlaps the view's header." >&2
    exit 1
fi

echo "✓ All ${#detail_views[@]} detail destination view(s) publish a navigation title."
