#!/bin/bash
# Fails if an App Intent can attempt an in-app purchase.
#
# Free-trial T11. An intent runs from a Shortcut, an automation, or a Focus
# trigger, with nobody watching. A StoreKit purchase or restore needs a
# foreground app and a person to answer a sheet, so from a background intent it
# would either fail silently or hang the automation waiting on a window nobody
# can see. The correct move at the gate is to throw and say "open Chronoframe".
#
# This is a grep, not a type-system guarantee — it catches the reachable
# mistake, which is someone calling the purchase surface directly from an intent
# because the refusal is right there and a purchase looks like the fix.
#
# Usage: script/check_app_intents_never_purchase.sh

set -euo pipefail

INTENTS_DIR="ui/Sources/ChronoframeApp/AppIntents"

if [[ ! -d "$INTENTS_DIR" ]]; then
    echo "✗ $INTENTS_DIR does not exist. Update this guard if App Intents moved."
    exit 1
fi

# The interactive surfaces: EntitlementStore.purchase()/restore(),
# StoreKitClient.purchase(productID:)/restorePurchases(), and StoreKit's own
# Product.purchase() / AppStore.sync().
#
# Anchored on call syntax, so a symbol that merely contains the word — say
# `restoreQuarantined` — does not trip it. A commented-out call DOES trip it,
# which is deliberate: the failure mode this guards against is someone leaving
# the call one keystroke from live.
FORBIDDEN='\.purchase\(|\.restore\(|restorePurchases\(|AppStore\.sync\(|\bProduct\.purchase\b'

matches=$(grep -rnE "$FORBIDDEN" "$INTENTS_DIR" --include='*.swift' || true)

if [[ -n "$matches" ]]; then
    echo "✗ An App Intent attempts an in-app purchase or restore."
    echo ""
    echo "$matches"
    echo ""
    echo "Background intents must never attempt an interactive purchase — there is no"
    echo "foreground app to present the sheet and nobody to answer it. Throw an intent"
    echo "error telling the user to open Chronoframe instead; see"
    echo "OrganizeIntentPurchaseMessage."
    exit 1
fi

count=$(find "$INTENTS_DIR" -name '*.swift' | wc -l | tr -d ' ')
echo "✓ No App Intent attempts a purchase or restore ($count file(s) checked)."
