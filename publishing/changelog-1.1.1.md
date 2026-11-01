# MobLog 1.1.1 — Background Preparation & Clearer Locations

Changes since **1.1.0**. Released **1 November 2026**.

## Background preparation

- Added **Prepare catalog in the background**, enabled by default. Preparation
  starts five seconds after login or UI reload and can continue with MobLog closed.
- Added **Continue item scanning in the background**, enabled by default. A scan
  started with Prepare search continues after closing the window or typing a search.
  Full item scans still start only when requested.
- Both tasks pause in combat and use slower timer steps while hidden. Settings
  can restore window-only catalog preparation or stop background item scanning.
- Fixed the indexing counter when reopening Items during an active scan.
- Kept the existing single bundled catalog; no additional data-addon folders.

## Item indexing

- Distinguished **scan finished**, **scan paused** and **search index complete**.
  A completed pass no longer implies that every item has readable metadata.
- Show the remaining count when names or rarities cannot be resolved, with
  **Retry missing** after the scan finishes.
- Added explicit item-data requests, both item-data completion callbacks,
  timeout cache rechecks and up to three bounded passes for unresolved IDs.
- Count each newly indexed item once and handle successful late responses.
- Keep unresolved IDs in the total instead of excluding them to claim 100%.
  Item ID searches remain available without names. Some IDs may stay unresolved.
- Preserve request limits, combat pauses and cached language-specific metadata.

## Personal encounter areas and known habitats

- Show **Seen in:** for the latest named personal encounter area.
- When no personal area exists, show **Found in:** with a known habitat and
  **+N** for additional areas; show **Location unknown** when neither is available.
- Separate **Your encounters** and **Known habitats** in creature-list tooltips.
- Added **All locations**, **Your encounters** and **Known habitats** to the
  Mobs and Items area navigation. Dropdown choices and filtering use the same
  location source; changing source clears incompatible geographic selections.
- Include known dungeon habitats even when NPC area IDs are missing. Added compact
  offline memberships for **24,502 NPCs**, with **451 area keys** for navigation.
  Filters do not scan raw coordinate strings or create personal discoveries.

## Dungeon maps and model previews

- Resolve dungeon names from internal map IDs when area information is absent.
- Open supported dungeon maps without requiring an exact spawn coordinate or
  waypoint support. Added **333 instance-map entry points**; uncertain floors
  and positions are not presented as verified spawn pins.
- Stream known model appearances directly by display ID, reapply the camera after
  loading/layout, and retry incomplete loads a limited number of times.
- Reload the selected preview on show and ignore stale selection callbacks.
- Removed extra zoom-dependent damping from right-drag model panning.

## Performance

- Avoid shifting large Undiscovered arrays when discovering a new creature.
- Share empty catalog arrays, removing roughly **435,000 duplicate Lua tables**.
- Limit background rank checks, hunt tracking and NPC tooltip grouping to relevant
  same-name candidates instead of rebuilding all location histories.
- Spread passive sighting observations over smaller timer steps.
- Enumerate catalog areas from a compact index instead of scanning every NPC.

## Upgrade and tracking

Install **both MobLog and MobLog_TrinityDB** from the addon ZIP. Personal records
and settings are retained. No external tracking addon is required. Fully restarting
WoW is recommended after updating; existing installations can reload the UI.

Dungeon/raid recording remains loot-based. Open-world death recognition is unchanged.
The original creature, item, loot and spawn data is retained; new habitat/map indexes
are derived from the bundled sources. Catalog possibilities do not count as personal
kills, sightings or observed drops, and percentages remain personal samples.

The initial loading of Lua data files is synchronous and can still briefly pause
the client.

GPL-2.0-or-later, with upstream MIT/GPL notices retained.
Source: https://github.com/Eychkay/MobLog/tree/v1.1.1
