# MobLog 1.21 · Share finds in game

Share a gathering route, a creature location, or an item source directly with
another MobLog player. Choose the records you want to send. The recipient
reviews the new finds and decides which ones to keep.

## Send a package

1. Both players should use MobLog 1.21 on the same WoW edition and be logged in.
   Open **Share finds** in the main window or type `/ml share`.
2. In **Send finds**, use **Find or zone** to search your recorded loot sources,
   creatures and locations, and ore, herbs, and fishing spots. Click a category
   heading to expand or collapse it. Select a category, check individual
   entries, or click **Select shown** to choose all filtered entries.
3. In **Retail**, enter the player's character name, or use **Name-Realm** for
   a different realm. In **Forever**, type their **first and last name**
   separated by a space.
4. Optionally name the package and enable **Include gathered quantities**.
   Click **Offer to player**. For a focused selection, use **Share finds** on a
   selected item in the item catalog or **Alt + right-click** a personal
   gathering spot on the world map.

## Receive and review

1. The recipient opens **Transfers** and checks the sender and number of finds.
   Click **Accept** to begin or **Decline** to dismiss the offer.
2. Follow the incoming or outgoing progress in **Transfers**. **Packages with
   more than 1,000 finds may take a while.** Keep both characters logged in
   until delivery finishes. Either player can cancel the transfer.
3. Click **Review finds**. MobLog counts already known entries and shows the new
   entries with checkboxes. Hover over a row to inspect relevant item or NPC IDs
   and included quantities. Click **Import selected** to save your selection.
4. Open **Items → Item catalog → Imported sources** to see reported loot
   sources. Creature coordinates appear under **Details & Places → Imported
   creature locations**. Imported gathering spots appear on the world map and
   minimap when enabled. MobLog keeps the imported data separate from your own
   encounters, drop rates, and gathering statistics.

## Remove imported finds

Open **Imported finds** and choose a package in the dropdown. Check specific
entries or use **Select shown**, then click **Remove → Confirm removal**. Use
**Undo this import → Confirm removal** to remove the whole package.

## Install for your client

- **Retail** uses `MobLog-1.21.zip`. Extract `MobLog` and `MobLog_TrinityDB`
  into `_retail_/Interface/AddOns/`.
- **Forever** uses `MobLog-1.21-Forever.zip`. Extract `MobLog` and
  `MobLog_ForeverDB` into `_forever_/Interface/AddOns/`.

Fully restart WoW after updating. Existing records and preferences carry
forward in their respective clients.

MobLog is distributed under **GPL-2.0-or-later**. Third-party notices are included. [Source code on GitHub](https://github.com/Eychkay/MobLog)
