# MobLog licensing and attribution

Copyright (C) 2026 MobLog contributors.

MobLog 1.1.2's original addon source, build scripts, documentation and original
packaged artwork are distributed under the GNU General Public License, version 2
or (at your option) any later version: **GPL-2.0-or-later**. See `LICENSE` for the
complete license. You may redistribute and modify this work under those terms.
It is provided WITHOUT ANY WARRANTY, including implied warranties of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

This release does not change the terms of independently copyrighted upstream
material or purport to grant rights to Blizzard game assets/trademarks. Referenced
game textures and creature models are supplied by the player's game client, not
redistributed as artwork in this package.

## Included catalog

- TrinityCore TDB1210.26091-derived catalog: GPL-2.0-or-later. Retain
  `MobLog_TrinityDB/TRINITY-NOTICE.md` and `COPYING-TrinityCore`.
- AllTheThings-derived selected drop relationships: original material under MIT.
  Copyright (c) 2026 AllTheThings WoW Addon. Retain the complete `LICENSE-ATT` text
  and `ATT-NOTICE.md`. The combined catalog is distributed under GPL-2.0-or-later
  with these MIT notices preserved.

Source snapshots, input hashes, modifications and coverage are recorded in the
two catalog manifests and notices. No upstream drop percentages are imported.

## Corresponding source

The matching addon source, importers, editable intermediate data and source
manifests are published at https://github.com/Eychkay/MobLog with the exact commit linked in the release manifest.
Pinned original inputs and checked rebuild instructions are listed in `SOURCE.md`.
An optional offline source archive can also be built from that source tree.

## Dungeon map entry points

MobLog/InstanceMaps.lua also derives a server-instance to UI-map index from
AllTheThings pinned Midnight UiMap and UiMapAssignment CSV snapshots. Original
material: MIT, Copyright (c) 2026 AllTheThings WoW Addon; retain LICENSE-ATT.
See MobLog/map-manifest.json and tools/att/import_maps.py for source hashes.
The index opens dungeon maps; it does not verify spawn floors or positions.
