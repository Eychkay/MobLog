# MobLog — Retail / Midnight and Forever

MobLog is an account-wide bestiary for personal NPC encounters, recorded kills,
observed loot, character contributions, collection ranks and locations. It also
includes an optional bundled creature/loot catalog for discoveries still ahead.

## Install and open

Copy **MobLog** and **MobLog_TrinityDB** from **MobLog-1.1.8.zip** into
World of Warcraft/_retail_/Interface/AddOns/. Restart WoW after updating.
For Forever, install **MobLog** and **MobLog_ForeverDB** from
**MobLog-1.1.8-Forever.zip** into `_forever_/Interface/AddOns/`.
Use the package matching your client. Each package contains two addon folders. No external addon or library is
needed. Personal records and preferences are preserved.

Open with /moblog, /ml or the minimap button. The Mobs, Items, Session and Areas
pages offer search, sorting, account-wide character breakdowns, class colors,
interactive model previews and navigation between creatures and observed items.

## My inventory

Open **Items → My inventory** to search the recorded holdings of your characters
by item name or ID. Filter by character or item type and select an item to see
quantities, storage locations, and when they were checked. The coin balance opens
the breakdown of recorded gold by character and shared bank. You can also enable
inventory counts on item tooltips.

Bags, equipped items, and carried money are recorded during play. Open each
character's bank to record its contents. Shared storage is included once when
the client makes it available. The **Item catalog** links to recorded holdings,
and inventory entries link to their drop sources.

## Bestiary album

Switch between List and Album in the Mobs page. Album cards show known names
for undiscovered creatures and support Hostile, Non-hostile, Undiscovered and
Unknown attitude filters alongside search, area, type and collection rank.
Open a card to inspect the creature on a parchment double-page spread, with
interactive 3D models, loot and character records. Previous and Next browse
the filtered album. The list offers a larger model preview, Details & Places
and More details to open the same double-page view. Back to list restores
your selection, filters and scroll position.

## Discovery seals

Discovery goals are selected automatically for the current client: 410 seals in
Retail and 259 in Forever, across 29 series (plus any previously earned retired
goals). Distinct-NPC goals use the matching catalog population with a 20 percent
balancing margin, rounded down to a supported milestone. This is not proof that
every listed NPC is currently available. Retail uses the Trinity TDB1210.26091
population; Forever uses the incomplete pinned ATT Camelot references.

| Distinct discoveries | Retail maximum | Forever maximum |
|---|---:|---:|
| All NPCs | 50,000 | 2,500 |
| Beasts | 5,000 | 250 |
| Humanoids | 5,000 | 2,500 |
| Undead | 5,000 | 150 |
| Demons | 3,500 | 75 |
| Dragonkin | 3,500 | 50 |
| Elementals | 5,000 | 100 |
| Giants | 750 | 20 |
| Mechanicals | 5,000 | 20 |
| Aberrations | 3,500 | 20 |
| Critters | 2,500 | 3 |

Rare and elite discovery goals use their recorded classification populations.
Boss and attitude populations are not complete in these sources: those series
use broader client-scaled goals rather than claiming a verified subtype count.
Repeatable combat series remain at up to 2,500,000 total recorded kills and
100,000 kills per creature type. Recorded kills do not guarantee personal killing
blows. Each original NPC ID counts once for distinct discoveries, independently
of visual grouping and kill ranks. Catalog-only entries, provisional placeholders
and manual attitude overrides do not grant discovery credit.

Use dropdown filters for collection, creature types, encounters or combat and
for earned or in-progress seals. Fifty reusable cards are displayed per page.
Previously earned goals retired by new limits remain visible as earlier goals;
unearned retired goals disappear. Saved awards and their dates are preserved.

Regenerate the population snapshot after updating either catalog with
`python tools/trinity/build_discovery_limits.py`. It writes the small shared
`DiscoveryLimits.lua` file, so the addon need not load a catalog to select goals.

Existing personal records are credited silently as "From previous records".
Creature seals require a readable creature type; missing types can be filled by
later encounters or readable metadata. Newly earned seals record the date,
character and completing NPC. Click those seals to open the encounter.
Discovery notifications can be disabled directly on the Discoveries page.

## Personal notes and map notes

Use **Add note** in the creature details from the list or album to save a private
note for that NPC ID. Save an empty note to remove it.

On the world map, **Shift + right-click** to write a note at the clicked location.
Search by name or NPC ID, then choose a creature in the dropdown. The dropdown
suggests your current target. The link is optional. The mark appears on its original map and, when
linked, in the NPC's Details & Places. Right-click a pin to edit it, Shift +
right-click to remove it, or left-click a linked pin to open the creature entry.

## Locations

Seen in identifies the latest named personal encounter area. Found in identifies
known habitats when no personal area exists; +N indicates additional known areas.
The creature-list tooltip separates Your encounters from Known habitats.
Mobs and Items support All locations, Your encounters and Known habitats in the
world/region/area navigation. Changing source resets the geographic selection.
Personal discoveries and known spawns stay separate. Supported locations open a
map; only verified, supported coordinates can place a waypoint. A dungeon-map
entry point does not establish the NPC's exact floor or live location.

## Gathering locations

Successful mining and herbalism gathers add small markers to the world map and
minimap. Nearby minimap markers become hollow rings when the matching WoW
tracking mode is active. Hover over a marker for its approximate coordinates,
gather count, and recorded item quantities. The two maps have separate visibility
settings under **Options → AddOns → MobLog**.

Select a gathered item in the **Item catalog** to see its **Gathering sources**.
The source rows show the recorded amount at each location and can set waypoints
on supported maps. Existing markers gain item quantities from new gathers.

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

Current release: [Changelog](publishing/changelog-1.1.8.md) · [Release notes](publishing/release-notes-1.1.8.md).
