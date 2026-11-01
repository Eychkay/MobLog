# MobLog read-only catalog

The catalog now also includes selected possible-drop relationships derived from
AllTheThings. See `ATT-NOTICE.md`, `LICENSE-ATT` and `att-manifest.json` for that
separate provenance, MIT copyright/license and import coverage. Negative internal
loot-template IDs identify this offline enrichment; they are not source database
template IDs. Historical Trinity-only counts below describe the base snapshot,
not the enriched combined item total in the generated manifest.

This separate load-on-demand addon contains data derived from the TrinityCore
Retail database release **TDB1210.26091**, published 2026-09-09.

Upstream project and contributors: https://github.com/TrinityCore/TrinityCore

Source release: https://github.com/TrinityCore/TrinityCore/releases/tag/TDB1210.26091

Source archive: `TDB_full_1210.26091_2026_09_09.7z`

SHA-256: `fc5513334d7534a19f533124a95910193c8150379e5ed8d0db3e547ac2c5a3f5`

Derived data files were generated for MobLog on 2026-10-31. Changes consist of
selecting NPC identity/classification/model fields, recorded spawn-area IDs and
item-loot relationships, resolving nested loot references, combining difficulty
variants, and converting the resulting records into Lua source tables.

These derived data files are provided under **GNU GPL version 2 or later**,
without warranty. See `COPYING-TrinityCore`. Preserve this notice and the license
when redistributing this catalog. The generated Lua files are editable source;
the reproducible importer is `tools/trinity/import_catalog.py` in the MobLog project.

## Coverage and interpretation

- 227,633 NPC templates; this is not a verified list of currently obtainable kills.
- 16,235 distinct item IDs connected to NPC loot templates.
- 8,188 NPCs have a non-empty recorded zone/area assignment in this dump.
- 8,709 NPCs have a non-empty loot-template assignment in this dump.
- The dump's client hotfix tables do not supply a complete item-name, area-name
  or UI-map catalog. MobLog obtains available item names/icons/quality and area
  names from the user's WoW client. Missing fields remain unknown.
- Currency and tracking-quest loot entries are excluded. Reference loot entries
  are expanded into possible item associations; configured drop percentages are
  deliberately omitted.
- Possible drops are the union across recorded difficulties and conditions.
  They do not guarantee eligibility for the player's faction, quest state,
  difficulty, game build, or loot mode.
- Database availability does not identify protected live units and does not prove
  kills or item receipt. Catalog entries never become personal encounter records
  merely because they are browsed.

The source release may contain incomplete, obsolete, developer or conditional
templates. Missing source relationships are not reconstructed or invented.

## Spawn-position extract

The derived catalog additionally includes 258,748 unique stored spawn positions
for 28,931 NPC templates. Source: the world database's `creature` records.
Selected fields are server map ID, world position X/Y/Z, zone-or-area hint, and
flags indicating possible phase/difficulty conditions and movement. Positions
are rounded to 0.001 world units; duplicate positions for the same NPC/map/area
are combined, preserving the union of condition/movement flags. Non-finite
positions and references to NPC templates absent from this catalog are omitted.

`spawns-*.lua` contains packed editable text strings, one per NPC. Each semicolon
separates a point; each point is `worldMap,x,y,z,areaID,flags`. Flags: bit 1 means
conditional availability, bit 2 means possible movement. These records are
subject to the same GPL-2.0-or-later terms and upstream source attribution as
the other derived data. The importer reproduces this representation.

These are static source spawn positions, not a complete list of Retail spawns,
not live positions, and not evidence of an encounter. UI-map conversion is
performed by the user's client on demand. Missing conversion, map transforms
that do not round-trip, and unverified multi-floor mappings do not produce pins.

## Runtime representation and indexes

The generated Lua source now registers deferred declaration functions (250 records
per job) to allow the main addon to prepare tables incrementally. Additional packed
`npcOrder` and `itemSources` indexes precompute alphabetical order and possible NPC
sources from the same source fields; no additional upstream dataset is included.
These generated source files retain the same attribution and GPL-2.0-or-later terms.

Repeated loot and item-source sets additionally use deduplicated packed groups:
`loot` indexes `lootGroups`, and `itemSources` indexes `itemSourceGroups`. These
are representation changes only; the resolved possible drop relationships are
unchanged. Generated declarations remain editable, licensed source.
