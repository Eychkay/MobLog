-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local category

function ML.RegisterOptions()
    if category or not Settings or not Settings.RegisterVerticalLayoutCategory then return end

    category = Settings.RegisterVerticalLayoutCategory("MobLog")
    local label = "Mark as seen only when targeted"
    local tooltip = "When enabled, NPCs are marked as Seen only when you select them as your target. " ..
        "Enabling this can reduce micro-stutters in crowded cities and lower CPU usage, improving performance.\n\n" ..
        "When disabled, readable nearby NPCs with visible nameplates, mouseover NPCs and focus targets can also be marked as Seen.\n\n" ..
        "Disabled by default. In dungeons and raids, NPCs are still recorded only from loot sources."

    local setting = Settings.RegisterProxySetting(category, "MobLog_TargetOnlySeen", Settings.VarType.Boolean, label, false,
        function() return ML.db.options.targetOnlySeen == true end,
        function(value)
            ML.db.options.targetOnlySeen = value
            if value then ML.ClearPassiveSightings()
            else ML.ScanVisibleUnits() end
            if ML.Refresh then ML.Refresh() end
        end)
    Settings.CreateCheckbox(category, setting, tooltip)
    local citySetting = Settings.RegisterProxySetting(category, "MobLog_AutoTargetOnlyCities", Settings.VarType.Boolean,
        "Automatically use target-only sightings in capital cities", false,
        function() return ML.db.options.autoTargetOnlyCities == true end,
        function(value)
            ML.db.options.autoTargetOnlyCities = value
            ML.UpdateCitySightings(true)
        end)
    Settings.CreateCheckbox(category, citySetting,
        "Temporarily restrict Seen records to selected targets in supported capital cities and major expansion hubs. " ..
        "This can reduce passive NPC processing in crowded cities. Your normal sighting preference is restored when you leave. " ..
        "Ordinary inns do not activate this option. Disabled by default and saved account-wide. Kill tracking is unchanged.")
    local tooltipSetting = Settings.RegisterProxySetting(category, "MobLog_NPCTooltip", Settings.VarType.Boolean,
        "Show MobLog details in NPC tooltips", true,
        function() return ML.db.options.npcTooltip ~= false end,
        function(value) ML.db.options.npcTooltip = value end)
    Settings.CreateCheckbox(category, tooltipSetting,
        "Show recorded kills, sightings, collection rank progress and hunt target status for known NPCs. " ..
        "Uses existing records only. Hidden NPC identities cannot be matched, so restricted tooltips may not show MobLog details.")
    local trackerSetting = Settings.RegisterProxySetting(category, "MobLog_HuntTracker", Settings.VarType.Boolean,
        "Show hunt tracker", true,
        function() return ML.db.options.huntTracker ~= false end,
        function(value) ML.db.options.huntTracker = value; ML.UpdateHuntTracker() end)
    Settings.CreateCheckbox(category, trackerSetting,
        "Show a small tracker for pinned hunt targets. Hides automatically when no mobs are pinned. " ..
        "Drag the title to move it, click a mob to open its entry, or right-click to unpin. Position is saved account-wide.")
    local lockSetting = Settings.RegisterProxySetting(category, "MobLog_HuntTrackerLocked", Settings.VarType.Boolean,
        "Lock hunt tracker position", false,
        function() return ML.db.options.huntTrackerLocked == true end,
        function(value) ML.db.options.huntTrackerLocked = value end)
    Settings.CreateCheckbox(category, lockSetting, "Prevent dragging the hunt tracker. Collapse and close controls remain available.")
    local catalogSetting=Settings.RegisterProxySetting(category,"MobLog_BackgroundCatalog",Settings.VarType.Boolean,
        "Prepare catalog in the background",true,
        function() return ML.BackgroundCatalogEnabled() end,
        function(value)
            ML.db.options.backgroundCatalog=value
            if value then ML.ScheduleBackgroundCatalog() end
        end)
    Settings.CreateCheckbox(category,catalogSetting,
        "Prepare the catalog automatically after login or UI reload, even while MobLog is closed. "..
        "Uses smaller timer steps and pauses in combat. Disable to prepare only while the window is open. "..
        "Initial addon-file loading is synchronous and may briefly pause the game. Enabled by default.")
    local scanSetting=Settings.RegisterProxySetting(category,"MobLog_BackgroundItemScan",Settings.VarType.Boolean,
        "Continue item scanning in the background",true,
        function() return ML.BackgroundItemScanEnabled() end,
        function(value)
            ML.db.options.backgroundItemScan=value
            if not value then ML.PauseItemSearchPreparation() end
            if ML.RefreshItemSearchStatus then ML.RefreshItemSearchStatus() end
        end)
    Settings.CreateCheckbox(category,scanSetting,
        "After you click Prepare search, continue indexing missing item names and rarities while the window is closed or a search is active. "..
        "Uses at most one new item per timer turn and pauses in combat. The scan does not start automatically. "..
        "Use Pause to stop it. Indexed metadata is saved for this language. Enabled by default.")
    Settings.RegisterAddOnCategory(category)
end
