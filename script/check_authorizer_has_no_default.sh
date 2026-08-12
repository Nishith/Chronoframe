#!/usr/bin/env bash
#
# The trial authorizer must never gain a default argument.
#
# T7's whole mechanism is that the compiler enumerates the composition roots.
# A default like `authorizer: any TrialAuthorizing = UnrestrictedTrialAuthorizer()`
# would restore the exact failure it exists to prevent: every forgotten or
# future constructor silently becomes unrestricted. That failure is invisible —
# a missing gate does not crash, does not log, and does not fail a test. It just
# gives the product away.
#
# So this guards the acceptance criterion directly: no default, anywhere.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# A parameter default and a property initializer look almost identical:
#   authorizer: any TrialAuthorizing = Unrestricted...()   <- parameter, banned
#   static let authorizer: any TrialAuthorizing = Entitle...()  <- property, fine
# Only the second binds a name with let/var, so that is the discriminator.
offenders="$(
    grep -rn 'authorizer:[[:space:]]*any[[:space:]]*TrialAuthorizing[[:space:]]*=' \
        ui/Sources --include='*.swift' \
        | grep -Ev '\b(let|var)[[:space:]]+authorizer\b' \
        || true
)"

if [[ -n "$offenders" ]]; then
    echo "The trial authorizer has been given a default argument:" >&2
    echo "$offenders" >&2
    echo >&2
    echo "Remove it. A default makes every forgotten or future constructor a silent" >&2
    echo "licensing bypass — the compiler is the only thing enumerating the" >&2
    echo "composition roots, and a default switches that off." >&2
    exit 1
fi

# The requirement is only meaningful if the parameter still exists.
engines=(
    "ui/Sources/ChronoframeAppCore/Services/SwiftOrganizerEngine.swift"
    "ui/Sources/ChronoframeAppCore/Services/DeduplicateEngine.swift"
)
for engine in "${engines[@]}"; do
    if ! grep -q 'authorizer: any TrialAuthorizing' "$engine"; then
        echo "$engine no longer takes an authorizer at all." >&2
        echo "If the gating design changed, update this guard deliberately." >&2
        exit 1
    fi
done

echo "✓ The trial authorizer is required (no default) on ${#engines[@]} production engine(s)."
