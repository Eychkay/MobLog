# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 MobLog contributors
"""Build small server-instance -> UI-map entry points from pinned ATT CSV data.

Run with --fetch to download the two public inputs. Never executes upstream code.
The entry point opens a dungeon map; it does not identify a spawn's floor.
"""
import argparse
import csv
import hashlib
import io
import json
from pathlib import Path
from urllib.parse import quote
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[2]
COMMIT = '5ee014cf4cf4c9e4d4c8f3c0d2333e3ac695ad07'
PREFIX = '.contrib/.db/standard/.config/.wago/12 - Midnight/'
INPUTS = {
    PREFIX+'UiMap.12.1.5.70575.csv': 'c2303aef0e4b372db7841b1ee51ca92b5a8bab9e',
    PREFIX+'UiMapAssignment.12.1.5.70575.csv': 'dfe9f039fa7f930b18493c9605eecace7fb36828',
}


def build(fetch=False):
    tables, hashes = [], {}
    for relative, expected in INPUTS.items():
        path = ROOT/'tools/att-review'/relative
        if not path.exists() and fetch:
            data = urlopen('https://raw.githubusercontent.com/ATTWoWAddon/AllTheThings/'
                           +COMMIT+'/'+quote(relative), timeout=40).read()
        else:
            data = path.read_bytes()
        actual = hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()
        if actual != expected:
            raise ValueError('Unexpected map input: '+relative)
        if not path.exists():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        hashes[relative] = hashlib.sha256(data).hexdigest()
        tables.append(list(csv.DictReader(io.StringIO(data.decode('utf-8-sig')))))
    maps = {int(row['ID']): row for row in tables[0]}
    candidates = {}
    for row in tables[1]:
        server, ui = int(row['MapID']), int(row['UiMapID'])
        info = maps.get(ui)
        if server <= 1 or not info or info['Type'] != '4' or info['System'] != '0':
            continue
        group = candidates.setdefault(server, {})
        group[ui] = min(group.get(ui, int(row['OrderIndex'])), int(row['OrderIndex']))
    result = {}
    for server, group in candidates.items():
        roots = [ui for ui in group if int(maps[ui]['ParentUiMapID']) not in group]
        result[server] = min(roots or group, key=lambda ui: (group[ui], ui))
    lines = ['-- SPDX-License-Identifier: GPL-2.0-or-later',
             '-- Copyright (C) 2026 MobLog contributors',
             '-- Derived from MIT-licensed AllTheThings map CSVs; retain LICENSE-ATT.',
             '-- Source commit: '+COMMIT+'; regenerate: tools/att/import_maps.py',
             '-- Dungeon map entry points only, not verified spawn floors or pins.',
             'local _, ML = ...', 'ML.InstanceMaps = {']
    lines += ['    ['+str(server)+']='+str(ui)+',' for server, ui in sorted(result.items())]
    lines.append('}')
    output = ROOT/'MobLog/InstanceMaps.lua'
    output.write_text('\n'.join(lines)+'\n', encoding='utf-8', newline='\n')
    manifest = {'commit': COMMIT, 'inputs': hashes, 'instance_maps': len(result),
                'generator_sha256': hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                'output_sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
                'policy': 'Main-system dungeon map entry points; parent before child; no spawn-floor inference.'}
    (ROOT/'MobLog/map-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print('Generated instance map entry points:', len(result), '; Black Temple:', result.get(564))


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--fetch', action='store_true')
    build(parser.parse_args().fetch)
