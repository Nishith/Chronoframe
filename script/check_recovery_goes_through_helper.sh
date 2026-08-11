#!/usr/bin/env bash
#
# Every destination recovery must run trial reconciliation with it.
#
# `DestinationRecovery.recoverAndReconcile` pairs
# `MutationRecoveryCoordinator.recover(destinationRoot:)` with settling any
# trial reservation the recovered run left open. Calling `.recover` directly
# skips the second half, and the failure is silent and one-directional:
# filesystem recovery completes, the reservation stays open and therefore FULLY
# CHARGED, and the customer is refused work they are entitled to. Nothing
# errors. Nothing in CI would otherwise notice.
#
# There were ten such call sites before they were centralized, across the app,
# the stores, both engines and the CLI, so "just remember" is not a strategy.
#
# Tests are exempt: `MutationRecoveryCoordinatorTests` exercises the coordinator
# directly and legitimately, and reconciliation is tested on its own.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

HELPER_FILE="ui/Sources/ChronoframeAppCore/Support/DestinationRecovery.swift"

if [[ ! -f "$HELPER_FILE" ]]; then
    echo "Missing $HELPER_FILE — the single recovery entry point." >&2
    echo "If it moved, update this guard so the check stays load-bearing." >&2
    exit 2
fi

# The helper itself must still make the underlying call, or it has stopped
# recovering anything and every routed call site silently became a no-op.
if ! grep -q 'coordinator\.recover(destinationRoot:' "$HELPER_FILE"; then
    echo "$HELPER_FILE no longer calls coordinator.recover(destinationRoot:)." >&2
    echo "Routing every call site through a helper that does not recover is worse than not having one." >&2
    exit 1
fi

offenders="$(
    grep -rn '\.recover(destinationRoot:' ui/Sources \
        --include='*.swift' \
        | grep -v "^${HELPER_FILE}:" \
        || true
)"

if [[ -n "$offenders" ]]; then
    echo "Direct MutationRecoveryCoordinator.recover(destinationRoot:) calls outside the helper:" >&2
    echo "$offenders" >&2
    echo >&2
    echo "Call DestinationRecovery.recoverAndReconcile(destinationRoot:) instead." >&2
    echo "It runs filesystem recovery and then settles the trial reservation the run left open;" >&2
    echo "calling .recover directly leaves that reservation charged forever." >&2
    exit 1
fi

routed="$(grep -rn 'DestinationRecovery\.recoverAndReconcile(' ui/Sources --include='*.swift' | grep -vc "^${HELPER_FILE}:" || true)"
echo "✓ All ${routed} destination recovery call site(s) go through DestinationRecovery.recoverAndReconcile."
