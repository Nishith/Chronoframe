#!/bin/bash
# Fail if ui/Chronoframe.storekit drifts from the shipping product.
#
# Why this exists: this file is the only thing that makes local StoreKit
# testing possible, and it is data — no compiler reads it, no test imports it.
# A product ID that no longer matches `ChronoframeUnlock.productID` does not
# break anything visibly; it makes every local purchase test exercise a product
# the app never asks for, and then pass. That is worse than having no local
# testing at all, because it looks like coverage.
#
# Checks the three settled-policy facts that would be expensive to get wrong:
#
#   - the product ID matches the constant the app actually requests;
#   - the type is a non-consumable, because the unlock is a one-time purchase
#     and a mistyped subscription would expire under customers;
#   - Family Sharing is on, which is IRREVERSIBLE in App Store Connect and so
#     has to be right in the local model as well.
#
# Price is checked as a warning rather than a failure: it is settled at $14.99
# for launch but is expected to rise, and a stale local price misleads nobody
# about behaviour.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${CHRONOFRAME_STOREKIT_CONFIG:-$repo_root/ui/Chronoframe.storekit}"
entitlement="${CHRONOFRAME_ENTITLEMENT_SOURCE:-$repo_root/ui/Sources/ChronoframeCore/Entitlement.swift}"

for path in "$config" "$entitlement"; do
    if [[ ! -f "$path" ]]; then
        echo "check_storekit_config_matches_policy: missing $path" >&2
        exit 1
    fi
done

expected_product_id="$(
    grep -Eo 'static let productID = "[^"]+"' "$entitlement" \
        | head -1 \
        | sed -E 's/.*"([^"]+)"/\1/'
)"

if [[ -z "$expected_product_id" ]]; then
    echo "Could not read ChronoframeUnlock.productID from ${entitlement#"$repo_root/"}." >&2
    echo "This guard compares the StoreKit config against that constant; if the" >&2
    echo "constant moved, update the guard rather than dropping the check." >&2
    exit 1
fi

python3 - "$config" "$expected_product_id" <<'PY'
import json
import sys

config_path, expected_product_id = sys.argv[1], sys.argv[2]

try:
    with open(config_path) as handle:
        config = json.load(handle)
except json.JSONDecodeError as error:
    sys.exit(f"{config_path} is not valid JSON: {error}\n"
             "Xcode rewrites this file when edited in the StoreKit editor; if it "
             "was hand-edited, fix the syntax before committing.")

products = config.get("products", [])
if len(products) != 1:
    sys.exit(f"Expected exactly one product in {config_path}, found {len(products)}.\n"
             "Settled policy is a single non-consumable unlock.")

product = products[0]
problems = []

if product.get("productID") != expected_product_id:
    problems.append(
        f"productID is {product.get('productID')!r}, but the app requests "
        f"{expected_product_id!r} (ChronoframeUnlock.productID).\n"
        "    Local purchase tests would exercise a product the app never asks for."
    )

if product.get("type") != "NonConsumable":
    problems.append(
        f"type is {product.get('type')!r}, expected 'NonConsumable'.\n"
        "    The unlock is a one-time purchase; a subscription would expire."
    )

if product.get("familyShareable") is not True:
    problems.append(
        "familyShareable is not true.\n"
        "    Family Sharing is ON for this product and that switch is "
        "irreversible in App Store Connect."
    )

if problems:
    print(f"{config_path} does not match the shipping product:", file=sys.stderr)
    for problem in problems:
        print(f"  - {problem}", file=sys.stderr)
    sys.exit(1)

if product.get("displayPrice") != "14.99":
    print(
        f"note: displayPrice is {product.get('displayPrice')!r}, and launch "
        "policy says 14.99. Not a failure — the price is expected to rise.",
    )

print(f"check_storekit_config_matches_policy: OK ({expected_product_id})")
PY

# The config only reaches a debug run through the scheme. A reference pointing
# at a path that no longer exists disables local StoreKit testing silently:
# Xcode simply runs without a configuration, purchases fail as unavailable, and
# nothing says why.
scheme="${CHRONOFRAME_SCHEME:-$repo_root/ui/Chronoframe.xcodeproj/xcshareddata/xcschemes/Chronoframe.xcscheme}"

if [[ ! -f "$scheme" ]]; then
    echo "check_storekit_config_matches_policy: missing $scheme" >&2
    exit 1
fi

python3 - "$scheme" <<'SCHEME_CHECK'
import os
import sys
import xml.etree.ElementTree as ElementTree

scheme_path = sys.argv[1]
tree = ElementTree.parse(scheme_path)
references = tree.getroot().findall(".//StoreKitConfigurationFileReference")

if not references:
    sys.exit(
        f"{scheme_path} has no StoreKitConfigurationFileReference.\n"
        "Without it a debug run has no StoreKit configuration, so purchases "
        "fail as unavailable and the unlock cannot be tested locally at all."
    )

scheme_dir = os.path.dirname(scheme_path)
for reference in references:
    identifier = reference.get("identifier") or ""
    resolved = os.path.normpath(os.path.join(scheme_dir, identifier))
    if not os.path.isfile(resolved):
        sys.exit(
            f"{scheme_path} references a StoreKit configuration that does not exist:\n"
            f"  identifier:  {identifier}\n"
            f"  resolves to: {resolved}"
        )

print("check_storekit_config_matches_policy: scheme reference OK")
SCHEME_CHECK
