# MobLog — Your Personal Bestiary

MobLog is a personal bestiary and inventory for **World of Warcraft Retail and Forever**. Record the creatures you encounter, browse them in a parchment album, follow your loot history, and save notes on creatures or on the world map. A bundled catalog shows possible drops and habitats alongside your own discoveries.

**New in 1.1.8 · Gathering locations.** Find your way back to the herbs and ore you have gathered. MobLog adds small markers to your world map and minimap. Hover over a marker to see the items and quantities recorded there, or open an item in the catalog to see its gathering locations.

## Discover and collect

Track hostile creatures alongside friendly and neutral NPCs. Separate **Killed** and **Seen only** sections help you see what you have encountered and what you have defeated.

Browse **Undiscovered** creatures alongside your recorded encounters. Catalog browsing never marks an NPC as seen or killed, and catalog entries may include older, unused or conditional variants.

Search by name, NPC ID or location, filter by classifications such as **Rare, Elite and Boss**, and narrow Mobs and Items through matching **world → region → area** dropdowns. Choose **Recent**, **Most kills**, **Most dropped** or **Alphabetical A–Z / Z–A** where applicable.

## Browse your bestiary album

Switch between **List** and **Album** on the Mobs tab. Filter album cards by **Hostile**, **Non-hostile**, **Undiscovered** or **Unknown attitude**. Known creature names are visible on undiscovered cards.

Open a card to see the creature on a parchment double-page spread, with its interactive 3D model, loot, character records and locations. Use **Previous** and **Next** to browse the filtered album. **More details** opens the same spread from the list, and **Back to list** restores your selection, filters and scroll position.

## Turn encounters into milestones

Grow your collection with **account-wide kill ranks** for each grouped bestiary entry:

*   **Bronze:** 50 recorded kills.
*   **Silver:** 250 recorded kills.
*   **Gold:** 1,000 recorded kills.
*   **Master:** 5,000 recorded kills.

Unlock colored frames, rank badges and decorative details, follow your progress toward the next rank, and celebrate new milestones with a rank-up notification. **Your existing kill records already count.**

Filter your collection by rank and check the summary to see how many entries have reached each tier. Each entry counts once at its highest current rank. Newly earned ranks also save the date, visible on the creature entry and in its list tooltip.

The **Discoveries** tab adds account-wide seals across 29 series, with **410 seals in Retail** and **259 in Forever**. Earn them by discovering distinct NPCs, encountering rares, elites and bosses, or recording kills overall and by creature type. The journal shows your next goals and offers dropdowns for category and completion.

Your existing records count toward seals. Newly earned seals can show the date, character and NPC involved. Click a linked seal to open that creature's entry, and toggle seal notifications from the Discoveries tab.

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

Each client uses its own bundled creature and loot catalog. The Retail catalog contains **31,375 item IDs linked to possible creature sources**. The Forever catalog uses separate creature, loot and location references. Catalog coverage is incomplete: a missing item or source does not mean a creature has no other drops. Availability can depend on difficulty, faction, character, game version or other conditions. Known loot contexts appear in tooltips; they are not exhaustive eligibility checks.

Open **Items → Item catalog** to search by name or ID, filter by rarity using **color-coded options**, and browse by area. Compare **Observed sources**, with your personal percentages, against **Possible sources** where you have not recorded the item yet. Click a creature to jump directly to its bestiary entry.

Item names and rarities are cached for your client language. Use **Prepare search** to retrieve missing information explicitly in small batches. Preparation pauses in combat. With background scanning enabled (the default), a manually started scan continues after leaving Items or starting a search; use Pause to stop it. Otherwise, leaving Items or starting a search stops preparation. Item ID searches work without names, and some information may remain unavailable.

Use **Ctrl-click** on supported item rows to open WoW's native item preview.

## Find what you already own

Search by **item name or ID** and use the character and item type dropdowns to narrow the list. Select an item to see the quantity in each character's bags, equipped gear or bank, together with the last scan time. Open **View drop sources** to see where the item can drop. In the Item catalog, **In inventory** takes you back to the recorded locations.

Click the **gold, silver and copper** display for the balance by character and shared bank. Enable **Show inventory counts on item tooltips** to check your recorded holdings while browsing items elsewhere in the game.

Log in on each character to record their bags, equipped items and carried money. Open their bank to record its contents. The shared bank is counted once when available. Retail and Forever keep separate inventory records.

## Find your gathering spots again

Mine ore or gather herbs to save the approximate location. Hover over a marker on either map for the last gather date, coordinates, number of gathers, and recorded quantities per item.

Nearby minimap icons turn into hollow rings when the matching WoW tracking mode is active, leaving room for the live tracking dot. The world map and minimap markers can be toggled separately in MobLog's options.

Select an item in **Items → Item catalog** and open **Gathering sources** to see its recorded locations. Click a source to set a waypoint on a supported map. Previously saved markers gain item quantities from new gathers.

## Plan your next find

Add items to your account-wide **Wishlist** with **+**, or remove them with **\***. Wishlisted items have their own section, and associated creatures show a wishlist indicator.

Wishlist entries stay until you remove them. A loot observation records what appeared in the loot window. The inventory shows what was present the last time MobLog checked your storage.

Use **Back**, **Reset filters** and **Current area** in the footer to move between creatures, items and areas. Back restores your recent views, including filters, selections and scroll positions.

## Leave yourself a note

Use **Add note** in the creature details to save a personal reminder for that NPC variant, even if you have only found it in the catalog. The first line appears in the creature details. Open **Notes** to edit the full text.

On the world map, **Shift + right-click** to add a note at your cursor. To link a creature, search by name or NPC ID and choose it from the dropdown. Your current target is available as a suggestion.

- **Left-click** a linked gold **!** marker to open its bestiary entry.
- **Right-click** a marker to edit the note or change its creature link.
- **Shift + right-click** a marker to remove it.

Linked map notes also appear under **Details & Places → Personal map marks** in the creature entry.

## Remember where—and with whom

Creature-list subtitles distinguish **Seen in** (your latest personal encounter area) from **Found in** (a known habitat). Mobs and Items can filter **All locations**, **Your encounters** or **Known habitats** before you choose a world, region and area.

Creature pages clearly separate **Your discoveries** from **Known locations**:

*   **Your discoveries** are saved at your character's position when a sighting or kill was recorded.
*   **Known locations** are available catalog spawn positions, shown separately and loaded only when needed. They never count as personal sightings, kills or discoveries.

Click supported locations to open the world map. Verified coordinates can also place a waypoint. Some dungeon locations open the map without marking an exact floor or spawn. Unavailable coordinates and ambiguous floors are not guessed. Catalog positions may be incomplete, conditional or associated with moving creatures; they do not guarantee that an NPC is currently present.

Your collection, wishlist and hunt targets are shared across characters using the same addon database. A character breakdown shows who recorded sightings and kills, with character names displayed in their **class colors**.

## Made for everyday exploring

*   English interface with a classic fantasy look.
*   Collapsible creature groups, quick search and combined filters.
*   On-demand list rendering, cached views and portrait loading for larger collections.
*   Optional background catalog preparation after login, enabled by default and paused in combat.
*   Minimap button for easy access.
*   Optional **target-only sightings** to help reduce CPU usage and micro-stutters in crowded cities; disabled by default.
*   Optional automatic target-only sightings in supported capital cities and major hubs; disabled by default.
*   Configurable NPC tooltip details and hunt tracker.
*   Catalog included; no external tracking addon or library required.

Open **Options → AddOns → MobLog** to configure the addon.

## Install for your client

- **World of Warcraft Retail:** Extract both `MobLog` and `MobLog_TrinityDB` from `MobLog-1.1.8.zip` into `_retail_/Interface/AddOns/`.
- **World of Warcraft Forever:** Extract both `MobLog` and `MobLog_ForeverDB` from `MobLog-1.1.8-Forever.zip` into `_forever_/Interface/AddOns/`.

Fully restart WoW after installing or updating. Your existing records and preferences are preserved within each client.

### Quick commands

*   **`/moblog`** or **`/ml`** — Open your bestiary.
*   **`/ml session`** — Open your session report.
*   **`/ml tracker`** — Toggle the hunt tracker.

## A note on tracking

Your personal collection grows only through recorded encounters. The separate catalog supplies additional creature, loot and location information; it does not create personal progress and is not a complete creature or loot database.

**In the open world**, death tracking is best effort within the game client’s API limits. It uses readable unit observations, with loot-based recording and manual confirmation as additional recording methods. Some kills may be missed, and recorded deaths do not prove a personal killing blow. **Inside dungeons and raids, tracking is loot-based only.**

Loot history reflects items exposed by the loot window, rather than confirmed receipt in your bags. Drop percentages are calculated from your recorded samples and are **not official drop rates**. In instances, creatures you do not loot are not included in those samples.

**Your discoveries** represent your character's position when an encounter was recorded. **Known locations** are separate catalog positions.

## Open source

MobLog is distributed under **GNU GPL version 2 or later (GPL-2.0-or-later)**, with third-party license and attribution notices retained in the package. **Source code:** [GitHub](https://github.com/Eychkay/MobLog)

_Available for World of Warcraft Retail and World of Warcraft Forever. English interface; available creature, item and location names follow your game client's language, with catalog fallbacks where needed._
