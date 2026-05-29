#!/usr/bin/env bash
#
# Guards against re-introducing animations that ignore the Reduce Motion
# accessibility setting.
#
# Why this exists: Chronoframe routes every animation through the reduce-motion
# helpers in `App/Motion.swift` (`.motion(_:value:)`, `Motion.withMotion`, and
# `Motion.resolved`). A raw `withAnimation(...)` or `.animation(...)` bypasses
# that gate and will animate even when a user has asked the system to minimise
# motion — a regression that is easy to add and invisible in review.
#
# The check greps the SwiftUI view layer for raw animation calls and fails if it
# finds any outside the small allowlist of legitimate, already-gated forms:
#
#   * App/Motion.swift                  — the helpers themselves.
#   * TimelineView(.animation(...))     — periodic timelines that pass
#                                          `paused: reduceMotion`.
#   * .animation(Motion.resolved(...))  — transition animations resolved
#                                          through the reduce-motion gate.
#
# Usage:
#     script/check_no_raw_animations.sh
#
# Exits non-zero (and prints the offending lines) on a violation.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCOPE="$ROOT/ui/Sources/ChronoframeApp"

# Find raw animation calls, then strip the allowlisted forms.
violations="$(
    grep -rEn 'withAnimation\(|\.animation\(' "$SCOPE" \
        --include='*.swift' \
        | grep -v '/App/Motion.swift:' \
        | grep -v 'TimelineView(\.animation(' \
        | grep -v '\.animation(Motion\.resolved(' \
        || true
)"

if [[ -n "$violations" ]]; then
    echo "✗ Raw animation call(s) found that bypass the Reduce Motion gate."
    echo "  Use .motion(_:value:), Motion.withMotion(...), or Motion.resolved(...) instead."
    echo "  (Allowed: App/Motion.swift, TimelineView(.animation(... paused: reduceMotion)),"
    echo "   and .animation(Motion.resolved(...)) on transitions.)"
    echo
    echo "$violations"
    exit 1
fi

echo "✓ No raw (reduce-motion-bypassing) animation calls in the view layer."
