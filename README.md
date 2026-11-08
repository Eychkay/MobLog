# MobLog — Retail / Midnight and Forever

MobLog is an account-wide bestiary for personal NPC encounters, recorded kills,
observed loot, character contributions, collection ranks and locations. It also
includes an optional bundled creature/loot catalog for discoveries still ahead.

## Install and open

Copy **MobLog** and **MobLog_TrinityDB** from **MobLog-1.1.2.zip** into
World of Warcraft/_retail_/Interface/AddOns/. Restart WoW after updating.
These are the only two addon folders required. No external addon or library is
needed. Personal records and preferences are preserved.

Open with /moblog, /ml or the minimap button. The Mobs, Items, Session and Areas
pages offer search, sorting, account-wide character breakdowns, class colors,
interactive model previews and navigation between creatures and observed items.

## Locations

Seen in identifies the latest named personal encounter area. Found in identifies
known habitats when no personal area exists; +N indicates additional known areas.
The creature-list tooltip separates Your encounters from Known habitats.
Mobs and Items support All locations, Your encounters and Known habitats in the
world/region/area navigation. Changing source resets the geographic selection.
Personal discoveries and known spawns stay separate. Supported locations open a
map; only verified, supported coordinates can place a waypoint. A dungeon-map
entry point does not establish the NPC's exact floor or live location.

## Background work and search

Prepare catalog in the background is enabled by default and starts five seconds
after login or UI reload. The existing single catalog prepares in timer batches,
slower when hidden, and pauses in combat. Disable the setting to prepare only
with the bestiary open. Initial Lua file parsing is synchronous and can still
briefly pause the client; this is not parallel-thread loading.

Prepare search manually indexes missing item names and rarities. Continue item
scanning in the background is enabled by default, so a started job can continue
with the window closed or while searching. Pause stops it. Combat pauses it;
there is at most one item per timer turn and eight pending requests. Existing
search membership uses a published metadata snapshot rather than a per-response
whole-list rebuild. Saved metadata is language-specific.

Up to three bounded passes handle unresolved item data. Scan finished is distinct
from Search index complete: failed or unavailable responses can leave names or
rarities unresolved. Retry missing checks them again. The total is not reduced
to manufacture 100 percent; numeric ID searches still work without readable names.

## Tracking and collection

- Open world: readable selected targets, nameplates, mouseover and focus can
  record Seen entries. Target-only sightings and automatic capital-city mode
  are optional and disabled by default. Death recognition is best effort under
  client restrictions; loot and manual confirmation provide additional methods.
- Dungeons/raids: NPCs are recorded through readable loot sources only. Targeting
  does not create Seen placeholders. Missing available details are queried after
  leaving. Catalog facts do not create kills, sightings or loot observations.
- Loot percentages are observed drop occurrences divided by recorded kills,
  including personal sample limitations. A stack counts as one occurrence;
  opening a loot window does not prove bag receipt or a personal killing blow.
- Grouped collection ranks are Bronze 50, Silver 250, Gold 1,000 and Master 5,000
  recorded kills. Existing records count. Original NPC loot statistics remain
  separate. Pin hunt targets, maintain item wishlists, and review session progress.
- Newly earned collection ranks save their achievement date account-wide. Dates
  appear in creature details and list tooltips; older undated ranks are identified.
- Areas summarizes personal records, not a guaranteed complete zone checklist.

## Data, licenses and source

The catalog has 227,633 NPC templates, 31,375 NPC-linked item IDs and 258,748 known
spawn records for 28,931 NPCs. Coverage remains incomplete and includes historical
or conditional variants. Compact indexes provide habitat memberships for 24,502
NPCs and 451 area keys; another index provides 333 dungeon-map entry points.
These are derived from the same pinned data, not newly observed progress.

GPL-2.0-or-later with upstream GPL/MIT notices retained. See LICENSE, NOTICE.md,
SOURCE.md and bundled provider notices/manifests. The matching source is available
at https://github.com/Eychkay/MobLog with a tag for each release. Pinned source
inputs and rebuild instructions are documented in SOURCE.md.
ATT does not need to be installed.

## Releases

Download the installable ZIP from [GitHub Releases](https://github.com/Eychkay/MobLog/releases).
Install both included addon directories. Do not install GitHub's automatic
"Source code" ZIP directly into your AddOns folder.

Forever release: [Changelog](publishing/changelog-1.1.3.md).
Forever overview: [Release notes](publishing/release-notes-1.1.3.md).

## Forever

The Forever release targets Forever 1.60.1
(interface 16001). Install `MobLog` and `MobLog_ForeverDB` in the Forever AddOns
folder and restart the game. Retail continues to use `MobLog_TrinityDB`.
Each client selects its own catalog; records remain in that client's saved data.

The Forever catalog uses separate creature, loot and map references. Coverage is
incomplete: some names and creature details require a personal encounter before
the game can supply them. Instances remain loot-based only.
