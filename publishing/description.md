# MobLog — Your Personal Bestiary

Every creature has a story. Keep a record of the ones you encounter.

MobLog builds an account-wide bestiary as you explore, bringing together NPC sightings, kill records, creature models, personal loot history, wishlists and discovery locations in one place. A bundled catalog helps you explore creatures and possible drops you have not recorded yet.

## Discover and collect

Track hostile creatures alongside friendly and neutral NPCs. Separate **Killed** and **Seen only** sections help you see what you have encountered and what you have defeated.

Browse **Undiscovered** creatures alongside your recorded encounters. Catalog browsing never marks an NPC as seen or killed, and catalog entries may include older, unused or conditional variants.

Search by name, NPC ID or location, filter by classifications such as **Rare, Elite and Boss**, and narrow Mobs and Items through matching **world → region → area** dropdowns. Choose **Recent**, **Most kills**, **Most dropped** or **Alphabetical A–Z / Z–A** where applicable.

## Turn encounters into milestones

Grow your collection with **account-wide kill ranks** for each grouped bestiary entry:

*   **Bronze:** 50 recorded kills.
*   **Silver:** 250 recorded kills.
*   **Gold:** 1,000 recorded kills.
*   **Master:** 5,000 recorded kills.

Unlock colored frames, rank badges and decorative details, follow your progress toward the next rank, and celebrate new milestones with a rank-up notification. **Your existing kill records already count.**

Filter your collection by rank and check the summary to see how many entries have reached each tier. Each entry counts once at its highest current rank.

## Keep your hunts in view

Pin creatures as **Hunt targets** to keep them together at the top of your list. Use **+** on an entry to pin it and **\*** to unpin it.

The compact **hunt tracker** keeps your pinned creatures and their progress toward the next rank visible while you play—even with the bestiary closed.

*   Drag the header to position it anywhere on your screen.
*   Collapse it when you need more space.
*   Left-click a creature to open its bestiary entry.
*   Right-click a creature to unpin it.
*   Browse additional targets using the page controls.
*   Lock its position or disable it in the addon settings.

The tracker hides automatically when no creatures are pinned. Your position and preferences are saved account-wide.

## Your collection, right in the tooltip

Hover over a recorded NPC to see your **kill records, sightings, collection progress and hunt target status** directly in its tooltip.

Grouped NPCs show their combined collection totals. Tooltip details use your existing records and appear only when WoW exposes a readable NPC identity. You can disable this feature in the addon settings.

## Look back on your session

Open the **Session** tab to review your adventures since login or UI reload:

*   Recorded kills, broken down by NPC.
*   Newly discovered NPC types.
*   Observed item drops and quantities.
*   Newly unlocked collection ranks.

The report is temporary; your account-wide bestiary remains saved.

## Explore your recorded areas

The **Areas** tab organizes your encounters by zone. Navigate through **worlds, regions and areas** using the breadcrumb dropdowns, or search for a recorded area by name.

See which creatures you have discovered, which you have killed locally and which you have only seen there. Review local kill counts alongside the account-wide ranks of creatures found in that area.

Click a creature to jump directly to its bestiary entry.

This overview reflects **your own discoveries**, rather than a complete creature checklist or a claimed zone-completion percentage. Area names and hierarchy follow the information available from WoW.

## Dungeon adventures, recorded through loot

**In dungeons and raids, MobLog records creatures only when you loot them.** Simply targeting a creature or defeating it without looting does not add an entry inside an instance.

WoW’s API restrictions can make creature details unavailable while you are inside. Newly recorded entries may therefore appear with incomplete information and a **Data lookup pending** notice.

**After you leave the instance and are out of combat, MobLog automatically queries the available missing details**—including names, creature types and classifications. There is normally no need to run a manual repair. Information that WoW does not provide may remain unknown.

## Take a closer look

Explore your collection with creature portraits and interactive **3D models**. Rotate, move and zoom each model, or switch between appearances you have discovered for the same NPC.

NPCs with the same name and a shared discovered appearance are grouped into one list entry. Use the model arrows to explore their variants. Collection ranks use the group’s combined recorded kills, while each original NPC keeps its own loot statistics.

## Build your own loot history

Each original NPC variant has separate **Observed drops** and **Not observed drops** sections. See recorded quantities and **personal drop percentages** for your observations, alongside additional possibilities from the catalog.

The bundled catalog contains **31,375 item IDs linked to possible creature sources**. Catalog coverage is incomplete: a missing item or source does not mean a creature has no other drops. Availability can depend on difficulty, faction, character, game version or other conditions. Known loot contexts appear in tooltips; they are not exhaustive eligibility checks.

Open **Items** to search by name or ID, filter by rarity using **color-coded options**, and browse by area. Compare **Observed sources**, with your personal percentages, against **Possible sources** where you have not recorded the item yet. Click a creature to jump directly to its bestiary entry.

Item names and rarities are cached for your client language. Use **Prepare search** to retrieve missing information explicitly in small batches. Preparation pauses in combat. With background scanning enabled (the default), a manually started scan continues after leaving Items or starting a search; use Pause to stop it. Otherwise, leaving Items or starting a search stops preparation. Item ID searches work without names, and some information may remain unavailable.

Use **Ctrl-click** on supported item rows to open WoW's native item preview.

## Plan your next find

Add items to your account-wide **Wishlist** with **+**, or remove them with **\***. Wishlisted items have their own section, and associated creatures show a wishlist indicator.

Your wishlist stays under your control: observing a drop does not remove an item automatically, because MobLog does not verify whether you received or still own it.

Use **Back**, **Reset filters** and **Current area** in the footer to move between creatures, items and areas. Back restores your recent views, including filters, selections and scroll positions.

## Remember where—and with whom

Creature pages clearly separate **Your discoveries** from **Known locations**:

* **Your discoveries** are saved at your character's position when a sighting or kill was recorded.
* **Known locations** are available catalog spawn positions, shown separately and loaded only when needed. They never count as personal sightings, kills or discoveries.

Click supported, verified locations to open the world map and place a waypoint. Unavailable coordinates and ambiguous floors are not guessed. Catalog positions may be incomplete, conditional or associated with moving creatures; they do not guarantee that an NPC is currently present.

Your collection, wishlist and hunt targets are shared across characters using the same addon database. A character breakdown shows who recorded sightings and kills, with character names displayed in their **class colors**.

## Made for everyday exploring

*   English interface with a classic fantasy look.
*   Collapsible creature groups, quick search and combined filters.
*   On-demand list rendering, cached views and portrait loading for larger collections.
*   Optional background catalog preparation after login, enabled by default and paused in combat.
*   Manually started item indexing can continue with the window closed; unresolved items are reported explicitly.
*   Minimap button for easy access.
*   Optional **target-only sightings** to help reduce CPU usage and micro-stutters in crowded cities; disabled by default.
*   Optional automatic target-only sightings in supported capital cities and major hubs; disabled by default.
*   Configurable NPC tooltip details and hunt tracker.
*   Catalog included; no external tracking addon or library required.

Open **Options → AddOns → MobLog** to configure the addon.

Install **both MobLog and MobLog_TrinityDB** from the release ZIP and restart WoW after updating. No additional data modules or external tracking addons are required.

### Quick commands

*   **`/moblog`** or **`/ml`** — Open your bestiary.
*   **`/ml session`** — Open your session report.
*   **`/ml tracker`** — Toggle the hunt tracker.

## A note on tracking

Your personal collection grows only through recorded encounters. The separate catalog supplies additional creature, loot and location information; it does not create personal progress and is not a complete creature or loot database.

**In the open world**, death tracking is best effort under Midnight’s API restrictions. It uses readable unit observations, with loot-based recording and manual confirmation as additional recording methods. Some kills may be missed, and recorded deaths do not prove a personal killing blow. **Inside dungeons and raids, tracking is loot-based only.**

Loot history reflects items exposed by the loot window, rather than confirmed receipt in your bags. Drop percentages are calculated from your recorded samples and are **not official drop rates**. In instances, creatures you do not loot are not included in those samples.

**Your discoveries** represent your character's position when an encounter was recorded. **Known locations** are separate catalog positions.

## Open source

MobLog is distributed under **GNU GPL version 2 or later (GPL-2.0-or-later)**, with third-party license and attribution notices retained in the package.

_Designed for World of Warcraft Retail / Midnight. English interface; available creature, item and location names follow your game client's language, with catalog fallbacks where needed._


## Personal areas and known habitats

Creature-list subtitles distinguish **Seen in** (your latest personal area) from
**Found in** (known catalog habitats when you have no personal area). Hover an
entry to compare Your encounters and Known habitats. The Mobs and Items area
navigation lets you select **All locations**, **Your encounters** or **Known
habitats** before choosing a world, region and area. Catalog habitats never create
personal progress. Supported dungeon locations can open their map even without
an exact spawn pin; unverified floors and coordinates remain unmarked.
