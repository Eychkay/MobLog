# SPDX-License-Identifier: GPL-2.0-or-later
# Copyright (C) 2026 MobLog contributors
"""Build MobLog's read-only catalog from an official Retail Trinity Database dump.

Input SQL is parsed as data, never executed. Re-run with the pinned dump to reproduce.
Derived TrinityCore data: GPL-2.0-or-later; upstream license is shipped alongside it.
"""
import csv
import hashlib
import json
from pathlib import Path
import re
import subprocess
import math

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).parent / 'source'
OUT = ROOT / 'MobLog_TrinityDB'
TAG = 'TDB1210.26091'
ADDON_VERSION = '1.1.1'
ARCHIVE = 'TDB_full_1210.26091_2026_09_09.7z'
SHA256 = 'fc5513334d7534a19f533124a95910193c8150379e5ed8d0db3e547ac2c5a3f5'
WANTED = {'creature_template', 'creature_template_difficulty', 'creature_template_model',
          'creature', 'creature_loot_template', 'reference_loot_template',
          'item_sparse', 'item', 'area_table', 'ui_map', 'ui_map_assignment'}
TUPLE = re.compile(r"\((?:[^'()]|'(?:\\.|[^'\\])*')*\)")
csv.field_size_limit(32 * 1024 * 1024)


def rows(path):
    schemas = {}
    with path.open(encoding='utf-8') as stream:
        for line in stream:
            if line.startswith('CREATE TABLE '):
                table = line.split('`')[1]
                columns = []
                for field in stream:
                    if field.startswith(')'): break
                    if field.startswith('  `'): columns.append(field.split('`')[1])
                schemas[table] = columns
            elif line.startswith('INSERT INTO '):
                table = line.split('`')[1]
                if table not in WANTED: continue
                columns = schemas[table]
                for match in TUPLE.finditer(line.partition(' VALUES ')[2]):
                    values = next(csv.reader([match[0][1:-1]], quotechar="'", escapechar='\\'))
                    if len(values) != len(columns): raise ValueError((table, len(values), len(columns)))
                    yield table, dict(zip(columns, values))


def n(row, key):
    return int(row.get(key, '0') or '0')


def lua(value):
    if isinstance(value, str): return json.dumps(value, ensure_ascii=False).replace('\\/', '/')
    if value is None: return 'nil'
    if isinstance(value, (list, tuple)):
        if not value: return 'D.empty'
        return '{' + ','.join(lua(v) for v in value) + '}'
    return str(value)


def build():
    archive = SOURCE / ARCHIVE
    if hashlib.file_digest(archive.open('rb'), 'sha256').hexdigest() != SHA256:
        raise ValueError('Unexpected source archive checksum')
    if not (SOURCE / 'TDB_full_world_1210.26091_2026_09_09.sql').exists():
        subprocess.run(['tar','-xf',str(archive),'-C',str(SOURCE)],check=True)
    npcs, loot_ids, models, npc_zones, item_data, area_data, maps = {}, {}, {}, {}, {}, {}, {}
    loot, references, assignments = {}, {}, []
    spawns = {}
    for path in sorted(SOURCE.glob('TDB_full_*.sql')):
        hotfix = 'hotfixes' in path.name
        print('Reading', path.name, flush=True)
        for table, r in rows(path):
            if table == 'creature_template':
                ident = n(r, 'entry')
                # name, classification, creature type; no guessed faction or level.
                npcs[ident] = [r['name'], n(r, 'Classification'), n(r, 'type')]
            elif table == 'creature' and hotfix:
                ident = n(r, 'ID')
                if r['Name'] and ident not in npcs: npcs[ident] = [r['Name'], n(r, 'Classification'), n(r, 'Type')]
                for field in ('DisplayID1', 'DisplayID2', 'DisplayID3', 'DisplayID4'):
                    if n(r, field): models.setdefault(ident, set()).add(n(r, field))
            elif table == 'creature':
                zone = n(r, 'zoneId') or n(r, 'areaId')
                if zone: npc_zones.setdefault(n(r, 'id'), set()).add(zone)
                position = tuple(round(float(r[key]), 3) for key in ('position_x', 'position_y', 'position_z'))
                if all(math.isfinite(value) for value in position) and n(r, 'map') >= 0:
                    conditional = any(n(r, key) for key in ('phaseUseFlags', 'PhaseId', 'PhaseGroup')) or n(r, 'terrainSwapMap') >= 0 or r.get('spawnDifficulties', '0') not in ('', '0')
                    flags = int(bool(conditional)) | (2 if n(r, 'MovementType') or float(r.get('wander_distance', '0')) > 0 else 0)
                    key = (n(r, 'map'), *position, zone)
                    points = spawns.setdefault(n(r, 'id'), {})
                    points[key] = points.get(key, 0) | flags
            elif table == 'creature_template_model':
                if n(r, 'CreatureDisplayID'): models.setdefault(n(r, 'CreatureID'), set()).add(n(r, 'CreatureDisplayID'))
            elif table == 'creature_template_difficulty':
                if n(r, 'LootID'): loot_ids.setdefault(n(r, 'Entry'), set()).add(n(r, 'LootID'))
            elif table in ('creature_loot_template', 'reference_loot_template'):
                # Currency and tracking quests are not item drops. References are
                # resolved below; union covers difficulties/conditions, not player eligibility.
                kind = n(r, 'ItemType')
                if kind in (0, 1):
                    target = loot if table == 'creature_loot_template' else references
                    target.setdefault(n(r, 'Entry'), set()).add((kind, n(r, 'Item')))
            elif table == 'item_sparse':
                item = item_data.setdefault(n(r, 'ID'), ['', -1, 0])
                item[0], item[1] = r['Display'], n(r, 'OverallQualityID')
            elif table == 'item':
                item_data.setdefault(n(r, 'ID'), ['', -1, 0])[2] = n(r, 'IconFileDataID')
            elif table == 'area_table':
                area_data[n(r, 'ID')] = [r['AreaName'], 0, n(r, 'ParentAreaID')]
            elif table == 'ui_map':
                maps[n(r, 'ID')] = [r['Name'], n(r, 'ParentUiMapID'), n(r, 'Type')]
            elif table == 'ui_map_assignment' and n(r, 'AreaID'):
                assignments.append((n(r, 'AreaID'), n(r, 'UiMapID')))
    for area, map_id in assignments:
        if area in area_data and map_id in maps:
            old = area_data[area][1]
            if not old or (maps[map_id][2] == 3 and maps.get(old, ['', 0, 0])[2] != 3): area_data[area][1] = map_id
    memo = {}
    def expand(ref, seen):
        if ref in memo: return memo[ref]
        if ref in seen: raise ValueError('Cyclic loot reference: ' + str(ref))
        found = set()
        for kind, item in references.get(ref, ()):
            if kind == 0: found.add(item)
            else: found.update(expand(item, seen | {ref}))
        memo[ref] = found
        return found
    resolved = {}
    for ident, entries in loot.items():
        found = set()
        for kind, item in entries:
            if kind == 0: found.add(item)
            else: found.update(expand(item, set()))
        if found: resolved[ident] = sorted(found)
    base_used_items = {item for ident in loot_ids for loot_id in loot_ids[ident] for item in resolved.get(loot_id, ())}
    # Enrich offline: runtime keeps the same packed indexes and incremental loader.
    # Negative synthetic template IDs cannot collide with positive Trinity IDs.
    att_path = ROOT / 'tools/att/enrichment.json'
    if not att_path.exists():
        raise ValueError('ATT subset missing: run python tools/att/import_att.py --fetch')
    att = json.loads(att_path.read_text(encoding='utf-8'))
    att_npcs, att_items, att_notes, att_pairs, skipped_npcs = {}, set(), {}, 0, set()
    added_pairs = 0
    for record in att['pairs']:
        npc, item = record['npc'], record['item']
        if npc not in npcs:
            skipped_npcs.add(npc)
            continue  # Do not add anonymous NPC placeholders to the bestiary.
        previous = any(item in resolved.get(template, ()) for template in loot_ids.get(npc, ()))
        if not previous: added_pairs += 1
        att_npcs.setdefault(npc, set()).add(item)
        att_items.add(item); att_pairs += 1
        att_notes[f'{npc}:{item}'] = record['note']
    for npc, items in att_npcs.items():
        resolved[-npc] = sorted(items)
        loot_ids.setdefault(npc, set()).add(-npc)
    used_items = base_used_items | att_items
    OUT.mkdir(parents=True, exist_ok=True)
    header = ('-- SPDX-License-Identifier: GPL-2.0-or-later\n-- Modified 2026-11-01 for MobLog 1.1.1; see bundled source and change notices.\n-- MobLog derived catalog: TrinityCore '+TAG+'; AllTheThings '+att['commit']+'.\n'
              '-- GPL-2.0-or-later catalog; retain ATT MIT attribution. See TRINITY-NOTICE.md, ATT-NOTICE.md and both licenses.\nlocal ML=MobLog\n')
    filenames = []
    def write_chunks(prefix, entries):
        out = None
        try:
            for index, (ident, value) in enumerate(entries):
                if index % 5000 == 0:
                    if out: out.close()
                    filename = prefix + '-' + str(index // 5000 + 1) + '.lua'
                    filenames.append(filename)
                    out = (OUT / filename).open('w', encoding='utf-8', newline='\n')
                    out.write(header)
                    if len(filenames) == 1: out.write('ML.TrinityData={release='+lua(TAG)+',npcCount='+str(len(npcs))+',empty={},npcs={},items={},loot={},lootGroups={},areas={},maps={},spawns={},habitats={},habitatAreas={},npcOrder={},itemSources={},itemSourceGroups={},dropNotes={},jobs={}}\n')
                    out.write('local D=ML.TrinityData\n')
                if index % 250 == 0:
                    out.write('D.jobs[#D.jobs+1]=function()\n')
                out.write('D.'+prefix+'['+lua(ident)+']='+lua(value)+'\n')
                if index % 250 == 249 or index == len(entries)-1:
                    out.write('end\n')
        finally:
            if out: out.close()
    write_chunks('npcs', [(ident, info+[sorted(models.get(ident, ())), sorted(npc_zones.get(ident, ())), sorted(loot_ids.get(ident, ()))]) for ident, info in sorted(npcs.items())])
    write_chunks('items', [(ident, item_data.get(ident, ['', -1, 0])) for ident in sorted(used_items)])
    def packed_groups(records):
        groups, indexes, lookup = {}, [], {}
        for ident, values in sorted(records.items()):
            signature = tuple(sorted(values))
            if signature not in lookup:
                group = len(lookup)+1
                lookup[signature] = group
                groups[group] = ','.join(map(str,signature))
            indexes.append((ident,lookup[signature]))
        return indexes, sorted(groups.items())
    loot_index, loot_groups = packed_groups(resolved)
    write_chunks('loot', loot_index)
    write_chunks('lootGroups', loot_groups)
    write_chunks('areas', sorted(area_data.items()))
    write_chunks('maps', sorted(maps.items()))
    # One packed string per NPC avoids creating a table for every spawn at login
    # and avoids Lua 5.1 constant limits for very common creatures. Decode only a
    # selected NPC's visible page. Format: worldMap,x,y,z,areaID,flags;...
    spawn_npcs = {npc: points for npc, points in spawns.items() if npc in npcs}
    write_chunks('spawns', [(npc, ';'.join(','.join(str(value) for value in (*key, flags)) for key, flags in sorted(points.items()))) for npc, points in sorted(spawn_npcs.items())])
    # Offline memberships keep runtime filters away from packed coordinates.
    instance_maps={int(value) for value in re.findall(r'\[(\d+)\]=\d+', (ROOT/'MobLog/InstanceMaps.lua').read_text(encoding='utf-8'))}
    habitats={}
    habitat_areas={str(zone) for zones in npc_zones.values() for zone in zones}
    for npc,points in spawn_npcs.items():
        worlds={key[0] for key in points if not npc_zones.get(npc) or key[0] in instance_maps}
        if worlds:
            keys=['world:'+str(world) for world in sorted(worlds)]
            habitats[npc]=','.join(keys); habitat_areas.update(keys)
    write_chunks('habitats', sorted(habitats.items()))
    write_chunks('habitatAreas', [(key,1) for key in sorted(habitat_areas)])
    item_sources = {}
    for npc, templates in loot_ids.items():
        if npc not in npcs: continue
        for template in templates:
            for item in resolved.get(template, ()):
                item_sources.setdefault(item, set()).add(npc)
    source_index, source_groups = packed_groups(item_sources)
    write_chunks('itemSources', source_index)
    write_chunks('itemSourceGroups', source_groups)
    write_chunks('dropNotes', sorted(att_notes.items()))
    order=sorted(npcs,key=lambda npc:(npcs[npc][0].translate(str.maketrans('ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')),npc))
    write_chunks('npcOrder', [(i//1000+1, ','.join(map(str,order[i:i+1000]))) for i in range(0,len(order),1000)])
    (OUT / 'Ready.lua').write_text('-- SPDX-License-Identifier: GPL-2.0-or-later\n-- Modified 2026-11-01 for MobLog 1.1.1; see bundled source and change notices.\nMobLog.TrinityData.queued=true\n',encoding='utf-8')
    filenames.append('Ready.lua')
    (OUT / 'MobLog_TrinityDB.toc').write_text('## Interface: 120000, 120001, 120005, 120007, 120100\n## Title: MobLog Catalog\n## Notes: Read-only creature and possible loot catalog.\n## Version: '+ADDON_VERSION+'\n## X-License: GPL-2.0-or-later\n## X-Data-Version: '+TAG+' + ATT 5ee014cf\n## Dependencies: MobLog\n## LoadOnDemand: 1\n'+'\n'.join(filenames)+'\n', encoding='utf-8')
    (OUT / 'COPYING-TrinityCore').write_bytes((SOURCE / 'COPYING').read_bytes())
    (OUT / 'LICENSE-ATT').write_bytes((ROOT / 'tools/att-review/LICENSE').read_bytes())
    att_manifest = {key: att[key] for key in ('commit', 'url', 'inputs', 'policy')}
    att_manifest.update(subset_sha256=hashlib.sha256(att_path.read_bytes()).hexdigest(),
                        extractor_sha256=hashlib.sha256((ROOT / 'tools/att/import_att.py').read_bytes()).hexdigest())
    att_manifest.update(npc_item_pairs=att_pairs, additional_npc_item_pairs=added_pairs,
                        npcs=len(att_npcs), items=len(att_items), additional_items=len(att_items-base_used_items),
                        skipped_unknown_npcs=sorted(skipped_npcs), base_trinity_items=len(base_used_items))
    (OUT / 'att-manifest.json').write_text(json.dumps(att_manifest, indent=2)+'\n', encoding='utf-8')
    manifest = dict(habitat_npcs=len(habitats), habitat_areas=len(habitat_areas), release=TAG, archive=ARCHIVE, sha256=SHA256, npcs=len(npcs), items=len(used_items), loot_templates=len(resolved), loot_groups=len(loot_groups), item_source_groups=len(source_groups), areas=len(area_data), maps=len(maps), spawn_npcs=len(spawn_npcs), spawn_points=sum(map(len, spawn_npcs.values())),
                    url='https://github.com/TrinityCore/TrinityCore/releases/tag/'+TAG)
    (OUT / 'trinity-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(manifest, flush=True)


if __name__ == '__main__': build()
