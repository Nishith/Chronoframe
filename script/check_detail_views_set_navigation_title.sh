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
# source so new destinations are covered automatically.
#
# The check looks for an applied `.navigationTitle(` modifier, not the bare
# identifier: `PhotosImportView` also declares a `static let navigationTitle`,
# so an identifier match would still pass if someone deleted the modifier and
# left the constant behind — exactly the regression this guard exists to catch.
# It remains a heuristic in two respects: it cannot prove the modifier is
# reached on every path (see `DeduplicateNavigationTitle`, which applies it
# conditionally), and its parser only recognizes a single-line
# `TypeName(appState:` call per case — a case written across multiple lines
# or via a factory function would silently parse to nothing for that case. The
# case-count check below turns that specific failure mode into a loud CI
# failure instead of a silent skip.
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
# Bash 3.2 (macOS default) lacks `mapfile`, so we read line-by-line — the same
# idiom `script/check_agents_invariants_have_tests.sh` uses.
detail_views=()
while IFS= read -r view; do
    [[ -n "$view" ]] || continue
    detail_views+=("$view")
done < <(
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

# Cross-check against the number of `case` labels in the same block. The
# parser above only recognizes a single-line `TypeName(appState:` call, so a
# case written differently (multi-line, a factory call, two views in one
# case) would otherwise parse to nothing for that case and vanish from
# `detail_views` without a trace, passing the rest of the script trivially.
case_count=$(
    awk '
        /private var detailView/ { in_block = 1; next }
        in_block && /^    \}$/   { in_block = 0 }
        in_block && /^[[:space:]]*case / { count++ }
        END { print count + 0 }
    ' "$ROOT_SPLIT_VIEW"
)

if [[ ${#detail_views[@]} -ne "$case_count" ]]; then
    echo "✗ Parsed ${#detail_views[@]} detail view(s) but detailView has $case_count case(s)." >&2
    echo "  This guard's parser only recognizes a single-line \`TypeName(appState:\` call" >&2
    echo "  per case; update it to match however the mismatched case is written." >&2
    exit 1
fi

violations=0
for view in "${detail_views[@]}"; do
    matches=()
    while IFS= read -r candidate; do
        [[ -n "$candidate" ]] || continue
        matches+=("$candidate")
    done < <(find ui/Sources/ChronoframeApp -type f -name "${view}.swift")

    if [[ ${#matches[@]} -eq 0 ]]; then
        file=""
    else
        file="${matches[0]}"
    fi

    if [[ -z "$file" ]]; then
        echo "✗ No source file found for detail view ${view}." >&2
        violations=$((violations + 1))
        continue
    fi

    # Strip line comments — both whole-line and trailing — so this very
    # explanation, quoted in a docstring, or a commented-out modifier
    # (`.onAppear { } // .navigationTitle("x")`), cannot satisfy the check on
    # a view that never applies the modifier live. The trailing-comment sed
    # only matches `//` preceded by whitespace, which a same-line `://` in a
    # string literal (a URL) will not be, so it does not truncate those. A
    # `.navigationTitle(` sitting inside a `/* … */` block whose lines don't
    # themselves start with `*` is a residual gap this heuristic accepts.
    code="$(sed -E 's|[[:space:]]//.*$||' "$file" | grep -vE '^[[:space:]]*(//|\*|/\*)' || true)"

    # Match with bash's own pattern operator, never by piping into `grep -q`.
    # `grep -q` exits at the first match, the upstream writer takes SIGPIPE, and
    # under `pipefail` that 141 becomes the pipeline's status — which `!` then
    # reads as "no match". It only bites on a file large enough that the writer
    # is still writing when grep exits, so it surfaces as an intermittent false
    # violation on the biggest view rather than as a reproducible failure.
    if [[ "$code" != *.navigationTitle\(* ]]; then
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
