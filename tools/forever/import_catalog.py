#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 MobLog contributors
"""Build the separate Forever catalog from pinned creature and drop references."""
from pathlib import Path
import argparse
import collections
import hashlib
import json
import math
import re
import shutil
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools/att'))
import import_att as att

CACHE = Path(__file__).parent / 'source/att'
OUT = ROOT / 'MobLog_ForeverDB'
CATEGORIES = ('Instances', 'Zones', 'WorldDrops', 'ExpansionFeatures', 'Holidays')


def lua(value):
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if value is True:
        return 'true'
    if isinstance(value, dict):
        return '{' + ','.join('[' + lua(k) + ']=' + lua(v) for k, v in value.items()) + '}'
    if isinstance(value, (list, tuple)):
        return '{' + ','.join(lua(v) for v in value) + '}' if value else 'D.empty'
    return str(value)


def digest(path):
    with path.open('rb') as stream:
        return hashlib.file_digest(stream, 'sha256').hexdigest()


def build(fetch=False):
    att.CACHE = CACHE
    att.CATEGORIES = CATEGORIES
    if fetch:
        att.fetch('Camelot')
    loot = att.build('Camelot', Path(__file__).with_name('enrichment.json'))
    npcs = set()
    habitats = collections.defaultdict(set)
    points = collections.defaultdict(set)
    bosses = set()

    def coords(value):
        if not isinstance(value, att.Table):
            return []
        result = []
        for map_id, rows in value.fields.items():
            if type(map_id) is int and map_id > 0 and isinstance(rows, att.Table):
                for row in rows.values:
                    if isinstance(row, att.Table) and len(row.values) >= 2:
                        result.append((map_id, *row.values[:2]))
        if len(value.values) >= 3 and all(type(v) in (int, float) for v in value.values[:3]):
            result.append((value.values[2], *value.values[:2]))
        else:
            for row in value.values:
                if isinstance(row, att.Table) and len(row.values) >= 3:
                    result.append((row.values[2], *row.values[:2]))
        return [(m, x / 100, y / 100) for m, x, y in result
                if type(m) is int and m > 0 and type(x) in (int, float) and type(y) in (int, float)
                and math.isfinite(x) and math.isfinite(y) and 0 <= x <= 100 and 0 <= y <= 100]

    def visit(node, maps, aliases):
        if isinstance(node, att.Table):
            for child in node.values:
                visit(child, maps, aliases)
            return
        if not isinstance(node, att.Call):
            return
        kind = aliases.get(node.name, node.name).removeprefix('_.Create')
        info = next((a for a in reversed(node.args) if isinstance(a, att.Table)), att.Table({}, []))
        fields = info.fields
        if 'u' in fields or 'rwp' in fields or att.dynamic(info):
            return
        local_maps = set(maps)
        first = node.args[0] if node.args else None
        if kind == 'Map' and att.integer(first):
            local_maps = {first}
        if att.numbers(fields.get('maps')):
            local_maps = set(att.numbers(fields['maps']))
        locations = coords(fields.get('coords')) + coords(fields.get('coord'))
        explicit_maps = {m for m, _, _ in locations}
        owners = set()
        if kind == 'NPC' and att.integer(first):
            owners.add(first)
        if kind == 'Encounter':
            owners.update(att.numbers(fields.get('crs')))
            bosses.update(owners)
        for npc in owners:
            npcs.add(npc)
            habitats[npc].update(explicit_maps or local_maps)
            points[npc].update(locations)
        for field in ('qgs', 'crs'):
            for npc in att.numbers(fields.get(field)):
                npcs.add(npc)
                habitats[npc].update(local_maps)
        children = fields.get('g') or (info if info.values else None)
        if isinstance(children, att.Table):
            for child in children.values:
                visit(child, local_maps, aliases)

    for category in CATEGORIES:
        text = (CACHE / f'db/Camelot/Categories/{category}.lua').read_text(encoding='utf-8-sig')
        aliases = {}
        for match in re.finditer(r'local ([A-Za-z_,]+)=([^;\n]+)', text):
            names, values = match[1].split(','), match[2].split(',')
            if len(names) == len(values):
                aliases.update(zip(names, values))
        marker = re.search(r'categories\.\w+\s*=\s*', text)
        if not marker:
            raise ValueError('Missing category root: ' + category)
        visit(att.Parser(text[marker.end():]).expr(), set(), aliases)

    drops = collections.defaultdict(set)
    sources = collections.defaultdict(set)
    notes = {}
    for record in loot['pairs']:
        npc, item = record['npc'], record['item']
        npcs.add(npc)
        drops[npc].add(item)
        sources[item].add(npc)
        notes[f'{npc}:{item}'] = record['note']

    # Shared legacy names and creature types only. Never copy Retail loot,
    # display IDs, map IDs or spawn geometry into the Forever catalog.
    base = {}
    base_hashes = {}
    pattern = re.compile(r'^D\.npcs\[(\d+)\]=\{("(?:\\.|[^"\\])*"),(-?\d+),(-?\d+),', re.M)
    for path in sorted((ROOT / 'MobLog_TrinityDB').glob('npcs-*.lua')):
        base_hashes[path.relative_to(ROOT).as_posix()] = digest(path)
        for match in pattern.finditer(path.read_text(encoding='utf-8-sig')):
            npc = int(match[1])
            if npc in npcs:
                base[npc] = (json.loads(match[2]), int(match[3]), int(match[4]))
    OUT.mkdir(parents=True, exist_ok=True)
    files = []
    version = re.search(r'^## Version: (.+)$', (ROOT / 'MobLog/MobLog.toc').read_text(encoding='utf-8-sig'), re.M)[1]
    header = '-- SPDX-License-Identifier: GPL-2.0-or-later\n-- Forever catalog; retain bundled GPL/MIT notices.\nlocal ML=MobLog\nif not ML.IsForever then return end\n'

    def write(prefix, entries):
        output = None
        try:
            for index, (key, value) in enumerate(entries):
                if index % 1000 == 0:
                    if output:
                        output.close()
                    name = f'{prefix}-{index // 1000 + 1}.lua'
                    files.append(name)
                    output = (OUT / name).open('w', encoding='utf-8', newline='\n')
                    output.write(header)
                    if len(files) == 1:
                        output.write('ML.TrinityData={client="forever",release="Forever",npcCount=' + str(len(npcs)) + ',empty={},npcs={},items={},loot={},lootGroups={},areas={},maps={},spawns={},uiSpawns={},habitats={},habitatAreas={},npcOrder={},itemSources={},itemSourceGroups={},dropNotes={},npcDetails={},jobs={}}\n')
                    output.write('local D=ML.TrinityData\n')
                if index % 250 == 0:
                    output.write('D.jobs[#D.jobs+1]=function()\n')
                output.write('D.' + prefix + '[' + lua(key) + ']=' + lua(value) + '\n')
                if index % 250 == 249:
                    output.write('end\n')
            if output and (index + 1) % 250:
                output.write('end\n')
        finally:
            if output:
                output.close()

    records = {}
    for npc in sorted(npcs):
        name, classification, creature_type = base.get(npc, ('', -1, 0))
        records[npc] = [name, classification, creature_type, [],
                        ['ui:' + str(m) for m in sorted(habitats[npc])], [-npc] if drops[npc] else []]
    write('npcs', records.items())
    write('npcDetails', ((npc, {'boss': True}) for npc in sorted(bosses)))
    write('items', ((item, ['', -1, 0]) for item in sorted(sources)))
    write('loot', ((-npc, ','.join(map(str, sorted(items)))) for npc, items in sorted(drops.items()) if items))
    write('itemSources', ((item, ','.join(map(str, sorted(owners)))) for item, owners in sorted(sources.items())))
    write('dropNotes', sorted(notes.items()))
    all_maps = sorted({m for maps in habitats.values() for m in maps})
    write('habitatAreas', (('ui:' + str(m), 1) for m in all_maps))
    locations = []
    for npc in sorted(npcs):
        rows = set(points[npc])
        positioned_maps = {m for m, _, _ in rows}
        rows.update((m, -1, -1) for m in habitats[npc] - positioned_maps)
        if rows:
            locations.append((npc, ';'.join(f'{m},{x:.8g},{y:.8g}' for m, x, y in sorted(rows))))
    write('uiSpawns', locations)
    order = sorted(npcs, key=lambda npc: ((records[npc][0] or f'NPC #{npc}').lower(), npc))
    write('npcOrder', ((i // 1000 + 1, ','.join(map(str, order[i:i + 1000]))) for i in range(0, len(order), 1000)))
    (OUT / 'Ready.lua').write_text('-- SPDX-License-Identifier: GPL-2.0-or-later\nif MobLog.IsForever and MobLog.TrinityData and MobLog.TrinityData.client=="forever" then MobLog.TrinityData.queued=true end\n', encoding='utf-8')
    (OUT / 'MobLog_ForeverDB.toc').write_text('## Interface: 16001\n## Title: MobLog Catalog (Forever)\n## Notes: Read-only creature and possible loot catalog for Forever.\n## Version: ' + version + '\n## X-License: GPL-2.0-or-later\n## Dependencies: MobLog\n## LoadOnDemand: 1\n' + '\n'.join(files + ['Ready.lua']) + '\n', encoding='utf-8', newline='\n')
    for name, original in [('LICENSE', ROOT / 'LICENSE'), ('COPYING-TrinityCore', ROOT / 'MobLog_TrinityDB/COPYING-TrinityCore'), ('LICENSE-ATT', CACHE / 'LICENSE')]:
        shutil.copyfile(original, OUT / name)
    notice = '# MobLog Forever catalog\n\nGPL-2.0-or-later. Shared creature names/types derive from TrinityCore TDB1210.26091; retain COPYING-TrinityCore.\nForever NPC, loot and map references derive from the MIT-licensed ATT Camelot snapshot ' + att.COMMIT + '; retain LICENSE-ATT.\nThe original MIT copyright notice is reproduced in full in LICENSE-ATT.\n\nNo Retail loot, display IDs or spawn geometry is imported. Missing names/types remain unknown until the game provides them. Catalog coverage may be incomplete or conditional.\n\nSource: https://github.com/Eychkay/MobLog\nRebuild: python tools/forever/import_catalog.py --fetch\n'
    (OUT / 'NOTICE.md').write_text(notice, encoding='utf-8', newline='\n')
    manifest = {'client': 'forever', 'interface': 16001, 'commit': att.COMMIT, 'inputs': loot['inputs'],
                'extractor_sha256': digest(ROOT / 'tools/att/import_att.py'),
                'subset_sha256': digest(Path(__file__).with_name('enrichment.json')),
                'base_npc_inputs': base_hashes, 'generator_sha256': digest(Path(__file__)),
                'npcs': len(npcs), 'unnamed_npcs': len(npcs - base.keys()), 'items': len(sources),
                'pairs': len(loot['pairs']), 'maps': len(all_maps), 'spawn_npcs': len(locations),
                'exact_points': sum(len(v) for v in points.values()), 'npc_order': len(order), 'files': files}
    (OUT / 'forever-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    print(json.dumps({key: manifest[key] for key in ['npcs', 'unnamed_npcs', 'items', 'pairs', 'maps', 'exact_points']}), flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fetch', action='store_true')
    build(parser.parse_args().fetch)
