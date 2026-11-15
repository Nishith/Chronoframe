#!/usr/bin/env bash
#
# Verifies that every bullet under AGENTS.md's "## Safety Invariants" section
# has at least one test method tagged with a matching AGENTS-INVARIANT marker.
#
# How to tag a test:
#
#     // AGENTS-INVARIANT: 7
#     func testRevertDeletesOnlyWhenHashStillMatches() throws { ... }
#
# Where `7` is the explicit INV-07 ID under "## Safety Invariants" in
# AGENTS.md, independent of list position. IDs are permanent and must not be
# renumbered or reused. The check is structural: it never reads the test body.
# It enforces that prose claims and code coverage stay aligned, so a future
# change to a safety invariant cannot silently ship without a corresponding
# test update.
#
# The marker format is also intentionally human-grep-able from inside an IDE:
# `// AGENTS-INVARIANT:` jumps to the test surface for the invariant.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AGENTS_MD="$ROOT_DIR/AGENTS.md"
TESTS_DIR="$ROOT_DIR/ui/Tests"

if [[ ! -f "$AGENTS_MD" ]]; then
    echo "AGENTS.md not found at $AGENTS_MD" >&2
    exit 2
fi

# Extract bullets under "## Safety Invariants" up to the next "##" header.
# Bash 3.2 (macOS default) lacks `mapfile`, so we read line-by-line.
bullets=()
while IFS= read -r line; do
    bullets+=("$line")
done < <(
    awk '
        /^## Safety Invariants/ { capturing = 1; next }
        /^## / && capturing { exit }
        capturing && /^- / {
            sub(/^- /, "")
            print
        }
    ' "$AGENTS_MD"
)

if (( ${#bullets[@]} == 0 )); then
    echo "No bullets found under '## Safety Invariants' in AGENTS.md" >&2
    exit 2
fi

# Read permanent IDs before checking coverage. Reject unlabelled/malformed or
# duplicate rules so inserting/reordering bullets cannot silently reassign tags.
# Indexed arrays and a delimited string keep this compatible with Bash 3.2.
invariant_ids=()
invariant_texts=()
seen_ids=" "
id_pattern='^\*\*INV-([0-9]{2,}):\*\*[[:space:]]+(.+)$'
for bullet in "${bullets[@]}"; do
    if [[ ! "$bullet" =~ $id_pattern ]]; then
        printf 'Invalid safety invariant: expected **INV-NN:** followed by rule text: %s\n' "$bullet" >&2
        exit 2
    fi
    raw_id="${BASH_REMATCH[1]}"
    rule_text="${BASH_REMATCH[2]}"
    n=$((10#$raw_id))
    printf -v canonical_id '%02d' "$n"
    if (( n < 1 )) || [[ "$raw_id" != "$canonical_id" ]]; then
        printf 'Invalid safety invariant ID: INV-%s (use a positive canonical ID, e.g. INV-07)\n' "$raw_id" >&2
        exit 2
    fi
    if [[ "$seen_ids" == *" $n "* ]]; then
        printf 'Duplicate safety invariant ID: INV-%s\n' "$canonical_id" >&2
        exit 2
    fi
    seen_ids+="$n "
    invariant_ids+=("$n")
    invariant_texts+=("$rule_text")
done

# Grep ALL AGENTS-INVARIANT markers across the test tree once.
marker_lines="$(grep -RInE '// AGENTS-INVARIANT:[[:space:]]*[0-9]+' "$TESTS_DIR" || true)"

missing=0
echo "Checking ${#bullets[@]} safety invariants…"
for i in "${!invariant_ids[@]}"; do
    n="${invariant_ids[i]}"
    bullet="${invariant_texts[i]}"
    # First sentence only, for readable output.
    summary="$(printf '%s' "$bullet" | head -c 100)"
    refs=""
    if [[ -n "$marker_lines" ]]; then
        refs="$(printf '%s\n' "$marker_lines" \
            | grep -E "AGENTS-INVARIANT:[[:space:]]*${n}([^0-9]|$)" \
            | awk -F: '{print $1}' \
            | sort -u || true)"
    fi
    if [[ -z "$refs" ]]; then
        printf '✗ INV-%02d  %s\n' "$n" "$summary"
        printf '         (no test tagged // AGENTS-INVARIANT: %d)\n' "$n"
        missing=$((missing + 1))
    else
        count="$(printf '%s\n' "$refs" | wc -l | tr -d ' ')"
        printf '✓ INV-%02d  %s\n' "$n" "$summary"
        printf '         (%s test file(s))\n' "$count"
    fi
done

echo
if (( missing > 0 )); then
    echo "✗ ${missing} of ${#bullets[@]} invariants have no test coverage." >&2
    echo "  Tag at least one test method per missing invariant with:" >&2
    echo "      // AGENTS-INVARIANT: <explicit-invariant-id>" >&2
    echo "  See $(basename "${BASH_SOURCE[0]}") for details." >&2
    exit 1
fi
echo "✓ All ${#bullets[@]} safety invariants have at least one tagged test."
