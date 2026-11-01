# Additional possible-drop data

This catalog includes a conservative derived subset of AllTheThings data.

Copyright (c) 2026 AllTheThings WoW Addon.
Original project: https://github.com/ATTWoWAddon/AllTheThings
Snapshot: `5ee014cf4cf4c9e4d4c8f3c0d2333e3ac695ad07`.
Original license: MIT. The full original copyright, permission and warranty text
is included in `LICENSE-ATT` and must remain with redistributed copies.

Changes made for MobLog on 2026-10-31: statically read selected Retail category
expressions without executing addon code; extract explicit NPC/encounter item
relationships in selected drop contexts; exclude unavailable/removed, dynamic,
purchase, quest-reward and container-content branches; preserve recognized
availability variants; merge eligible links into the packed catalog indexes.
NPCs absent from the existing NPC catalog are skipped rather than invented.

An encounter can identify several creatures sharing loot. These are possible
source relationships, not proof that every member individually yields every item.
World drops without an explicit NPC association are not assigned to arbitrary
creatures. This is not the complete ATT database or a complete Retail loot list.
No source drop percentages are imported. Personal observations remain separate.

Source hashes and import coverage: `att-manifest.json`.
This build retains 30,570 NPC-item relationships for 5,046 known NPCs, adding
24,320 source relationships and 15,140 distinct item IDs to the base catalog.
The combined catalog contains 31,375 item IDs. These are catalog relationships,
not personal drops or a guarantee of current obtainability.
Reproducible extraction and editable intermediate source:
`tools/att/import_att.py` and `tools/att/enrichment.json` in the MobLog source tree.
`python tools/att/import_att.py --fetch` obtains and verifies the pinned inputs.
Then `python tools/trinity/import_catalog.py` rebuilds the combined catalog.

The combined catalog retains its GPL-2.0-or-later distribution terms for the
Trinity-derived portions and preserves these MIT notices for ATT-derived data.
MobLog 1.1.0's main addon is also distributed under GPL-2.0-or-later; see the
bundled `LICENSE` and `NOTICE.md`. These grants do not override third-party rights
in underlying game content or remove the original MIT notices above.
