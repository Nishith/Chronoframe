import argparse
import copy
import os
import tempfile
import json
import re
import subprocess
from collections import Counter
from pathlib import Path

parser = argparse.ArgumentParser(description="Compile German catalogs and verify translation coverage and format arguments.")
parser.add_argument("--baseline-ref", help="Optional Git ref against which original keys, metadata and other locales must be preserved")
parser.add_argument("--stringsdata-directory", type=Path, help="Optional Xcode arm64 compiler extraction directory")
args = parser.parse_args()
os.chdir(Path(__file__).resolve().parents[1])
outputs = tempfile.TemporaryDirectory(prefix="chronoframe-german-")

pattern = re.compile(r'%(?:(\d+)\$)?[-+ #0]*(?:\d+|\*)?(?:\.(?:\d+|\*))?(hh|ll|h|l|L|z|j|t)?([@diuoxXfFeEgGaAcCsSpn%])')

def arguments(value):
    result, implicit = [], 1
    for position, length, kind in pattern.findall(value):
        if kind == '%':
            continue
        result.append((int(position) if position else implicit, (length or '') + kind))
        if not position:
            implicit += 1
    return Counter(result)

catalogs = {}
for kind, relative, table in [
    ('app', 'ChronoframeApp/Resources/Localizable.xcstrings', 'Localizable'),
    ('core', 'ChronoframeAppCore/Resources/LocalizableCore.xcstrings', 'LocalizableCore'),
]:
    path = Path('ui/Sources') / relative
    strings = json.loads(path.read_text())['strings']
    catalogs[kind] = strings
    if args.baseline_ref:
        previous = json.loads(subprocess.check_output(['git', 'show', f'{args.baseline_ref}:{path}']))['strings']
        assert previous.keys() <= strings.keys()
        for key, entry in previous.items():
            before, after = copy.deepcopy(entry), copy.deepcopy(strings[key])
            for item in [before, after]:
                item.get('localizations', {}).pop('de', None)
                if item.get('localizations') == {}:
                    item.pop('localizations')
            assert before == after, ('Changed original metadata or another language', key)
    output = Path(outputs.name) / kind
    output.mkdir()
    subprocess.run(['xcrun', 'xcstringstool', 'compile', str(path), '--output-directory', str(output)], check=True)
    compiled = json.loads(subprocess.check_output([
        'plutil', '-convert', 'json', '-o', '-',
        str(output / 'de.lproj' / f'{table}.strings'),
    ]))
    verified = 0
    for key, entry in strings.items():
        if entry.get('shouldTranslate') is False:
            continue
        german = entry['localizations']['de']['stringUnit']
        assert german['state'] == 'translated', key
        assert arguments(key) == arguments(german['value']), ('Placeholder mismatch', key)
        assert compiled[key] == german['value'], ('Compiled lookup mismatch', key)
        verified += 1
    print(f'{kind}: {verified} German strings, placeholders and compiled values verified')
    if args.baseline_ref:
        print(f'{kind}: original metadata and other locales preserved against {args.baseline_ref}')

if args.stringsdata_directory is None:
    print('Compiler coverage not checked; pass --stringsdata-directory after building with SWIFT_EMIT_LOC_STRINGS=YES')
    raise SystemExit(0)
counts = {kind: set() for kind in catalogs}
directory = args.stringsdata_directory
assert directory.is_dir(), f'Compiler extraction directory not found: {directory}'
files = list(directory.glob('*.stringsdata'))
assert files, f'No compiler .stringsdata files found: {directory}'
for path in files:
    data = json.loads(path.read_text())
    source = data.get('source', '')
    if '/UITesting/' in source:
        continue
    kind = 'core' if '/ChronoframeAppCore/' in source else 'app'
    for entries in data.get('tables', {}).values():
        for entry in entries:
            key = entry['key']
            if not key or entry.get('shouldTranslate') is False:
                continue
            counts[kind].add(key)
            assert 'de' in catalogs[kind].get(key, {}).get('localizations', {}), ('Missing compiler key', source, key)
print('Compiler extraction: zero missing German keys', {kind: len(keys) for kind, keys in counts.items()})
