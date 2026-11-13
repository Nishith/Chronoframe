#!/usr/bin/env python3
"""Add English-only keys to an Xcode String Catalog without touching existing entries.

usage: add_xcstrings_keys.py <catalog.xcstrings> <keys.txt>
keys.txt: one string per line, exactly as it appears in Text("…") / String(localized:) in code.
Existing keys are left untouched. New keys get extractionState "manual" and an English
stringUnit equal to the key, so other languages fall back to English until translated.
Exit 0 and prints the number of keys added. Never deletes anything.
"""
import json, sys
if len(sys.argv) != 3:
    sys.exit(__doc__)
catalog_path, keys_path = sys.argv[1], sys.argv[2]
with open(catalog_path, encoding="utf-8") as f:
    catalog = json.load(f)
strings = catalog.setdefault("strings", {})
added = 0
with open(keys_path, encoding="utf-8") as f:
    for raw in f:
        key = raw.rstrip("\n")
        if not key or key in strings:
            continue
        strings[key] = {
            "extractionState": "manual",
            "localizations": {"en": {"stringUnit": {"state": "translated", "value": key}}},
        }
        added += 1
catalog["strings"] = dict(sorted(strings.items()))
with open(catalog_path, "w", encoding="utf-8") as f:
    json.dump(catalog, f, ensure_ascii=False, indent=2)
    f.write("\n")
print(f"added {added} key(s) to {catalog_path}")
