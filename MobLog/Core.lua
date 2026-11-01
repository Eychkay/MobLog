-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
MobLog = ML
local frame = CreateFrame("Frame")
local cache = {}
local nextCachePrune = 0

-- Secret values must be rejected before comparison, concatenation or indexing.
function ML.Public(value)
    if issecretvalue and issecretvalue(value) then return nil end
    return value
end

function ML.CreatureID(guid)
    guid = ML.Public(guid)
    if type(guid) ~= "string" then return end
    local kind, _, _, _, _, id = strsplit("-", guid)
    if kind == "Creature" or kind == "Vehicle" then return tonumber(id) end
end

function ML.Location()
    local map = C_Map.GetBestMapForUnit("player")
    local zone = GetRealZoneText()
    local sub = GetSubZoneText()
    local x, y
    if map then
        local pos = C_Map.GetPlayerMapPosition(map, "player")
        if pos then x, y = pos:GetXY() end
    end
    return { map = map, zone = zone, sub = sub, x = x, y = y }
end

function ML.InstanceLootOnly()
    return IsInInstance and ML.Public(IsInInstance()) == true
end

function ML.TargetOnlySeen()
    return ML.db and ML.db.options and (ML.db.options.targetOnlySeen == true or
        (ML.CityTargetOnlyActive and ML.CityTargetOnlyActive())) or false
end

local passiveUnits, passiveScheduled = {}, false
function ML.ClearPassiveSightings()
    passiveUnits = {}
end

function ML.RemovePassiveSighting(unit)
    unit = ML.Public(unit)
    if type(unit) == "string" then passiveUnits[unit] = nil end
end

local function ProcessPassiveSightings()
    if ML.TargetOnlySeen() or ML.InstanceLootOnly() then
        passiveUnits, passiveScheduled = {}, false
        return
    end
    local count, changed, retry = 0, false, {}
    for unit, request in pairs(passiveUnits) do
        passiveUnits[unit] = nil
        local rawGUID = UnitGUID(unit)
        local currentGUID = ML.Public(rawGUID)
        local restrictedGUID = issecretvalue and issecretvalue(rawGUID)
        -- A recycled nameplate or moved mouseover must not reuse an older request.
        if not restrictedGUID and (not request.guid or not currentGUID or request.guid == currentGUID) then
            request.attempts = request.attempts + 1
            local rawControlled = UnitPlayerControlled(unit)
            local restrictedControlled = issecretvalue and issecretvalue(rawControlled)
            local controlled = ML.Public(rawControlled)
            local npcID = ML.CreatureID(currentGUID)
            request.guid = request.guid or currentGUID
            -- Only retry genuinely missing data. Protected values and players do
            -- not become readable through repeated polling. Read metadata once,
            -- after a public NPC identity and non-player flag are both available.
            if npcID and controlled == false then
                local _, _, updated = ML.Observe(unit, true, true)
                changed = updated or changed
            elseif not restrictedControlled and controlled ~= true and request.attempts < 3 and
                (not currentGUID or (npcID and controlled == nil)) then
                retry[unit] = request
            end
        end
        count = count + 1
        if count >= 1 then break end
    end
    for unit, request in pairs(retry) do passiveUnits[unit] = passiveUnits[unit] or request end
    if changed and ML.Refresh then ML.QueueRefresh() end
    if next(passiveUnits) then C_Timer.After(0.03, ProcessPassiveSightings)
    else passiveScheduled = false end
end

function ML.QueuePassiveSighting(unit)
    if ML.TargetOnlySeen() or ML.InstanceLootOnly() then return end
    unit = ML.Public(unit)
    if type(unit) ~= "string" or (unit ~= "focus" and unit ~= "mouseover" and not unit:match("^nameplate%d+$")) then return end
    if not C_Timer or not C_Timer.After then ML.Observe(unit, false, true); return end
    local rawGUID = UnitGUID(unit)
    if issecretvalue and issecretvalue(rawGUID) then return end
    local guid = ML.Public(rawGUID)
    if guid and not ML.CreatureID(guid) then return end
    local request = passiveUnits[unit]
    if not request or (guid and request.guid ~= guid) then
        passiveUnits[unit] = {attempts = 0, guid = guid}
    end
    if not passiveScheduled then
        passiveScheduled = true
        C_Timer.After(0.15, ProcessPassiveSightings)
    end
end

function ML.RemoveUnidentifiedSightings()
    if not ML.db then return end
    for id, mob in pairs(ML.db.mobs) do
        -- Only the addon-created placeholders with no kills or items qualify.
        if mob.provisional == true and (mob.count or 0) == 0 and not next(mob.items or {}) then
            ML.db.mobs[id] = nil
        end
    end
end

function ML.Observe(unit, deferRefresh, markSeen)
    if markSeen == nil then markSeen = unit == "target" end
    if ML.InstanceLootOnly() then markSeen = false end
    local rawGUID = UnitGUID(unit)
    local guid = ML.Public(rawGUID)
    local id = ML.CreatureID(guid)
    if not id then
        return
    end
    local name = ML.Public(UnitName(unit))
    local observedName = not ML.UnknownName(name, id)
    local known = ML.db and ML.db.mobs[id]
    if ML.UnknownName(name, id) then name = known and known.name or ("Unknown mob #" .. id) end
    local details = ML.ReadMobDetails(unit)
    if markSeen and unit == "target" and ML.RequestUnitPortrait then ML.RequestUnitPortrait(unit, guid, id) end
    cache[guid] = { id = id, name = name, seen = GetTime(), details = details }
    local changed = markSeen and ML.RecordSighting(guid, cache[guid], unit) or false
    local mob = ML.db and ML.db.mobs[id]
    if mob then
        changed = mob.name ~= name or changed
        mob.name = name
        if observedName then mob.nameSource = "observed" end
        changed = ML.ApplyMobDetails(mob, details) or changed
        if changed then ML.RevealDungeonRecord(mob) end
        ML.QueueNPCName(id)
    end
    if changed and not deferRefresh and ML.Refresh then ML.QueueRefresh() end
    return guid, cache[guid], changed
end

function ML.Record(guid, source, observed, deferRefresh)
    if ML.InstanceLootOnly() and source ~= "loot" then return false end
    local id = ML.CreatureID(guid)
    if not id or ML.db.seen[guid] then return false end
    local now = time()
    ML.db.seen[guid] = now
    local mob = ML.db.mobs[id]
    if not mob then
        mob = { id = id, name = observed and observed.name or ("Unknown mob #" .. id),
            count = 0, loot = 0, manual = 0, first = now, places = {} }
        ML.db.mobs[id] = mob
        if ML.CatalogRecordAdded then ML.CatalogRecordAdded(id) end
        if ML.SessionDiscovery then ML.SessionDiscovery(id) end
    end
    if observed and not ML.UnknownName(observed.name, id) then mob.name = observed.name end
    if ML.UnknownName(mob.name, id) then
        for _, data in pairs(cache) do
            if data.id == id and not ML.UnknownName(data.name, id) then
                mob.name = data.name; ML.ApplyMobDetails(mob, data.details); break
            end
        end
    end
    ML.ApplyMobDetails(mob, observed and observed.details)
    if ML.ApplyCatalogMetadata then ML.ApplyCatalogMetadata(mob) end
    if ML.ApplyDiscoveredAppearances then ML.ApplyDiscoveredAppearances(mob) end
    mob.count = mob.count + 1
    mob[source] = (mob[source] or 0) + 1
    mob.last = now
    ML.StampActivity(mob, "lastKilled", now)
    ML.RecordCharacter(mob, source, now)
    local loc = ML.Location()
    ML.RecordLocation(mob, loc, now)
    ML.session = ML.session + 1
    if ML.InvalidateItemSources then ML.InvalidateItemSources() end
    if ML.SessionKill then ML.SessionKill(id) end
    if ML.CollectionKill then ML.CollectionKill(id) end
    -- Record and publish immediately; metadata recovery is independent.
    ML.RevealDungeonRecord(mob)
    if not deferRefresh and ML.Refresh then ML.QueueRefresh() end
    ML.QueueNPCName(id)
    return true
end

function ML.ConfirmTarget()
    if ML.InstanceLootOnly() then ML.Print("Inside instances, NPCs are recorded from loot sources only."); return end
    if InCombatLockdown() then ML.Print("Please confirm after combat."); return end
    local dead = ML.Public(UnitIsDead("target"))
    if not dead then ML.Print("Select a dead NPC first."); return end
    local guid, data = ML.Observe("target")
    if not guid then ML.Print("No readable NPC data for this target."); return end
    if ML.Record(guid, "manual", data) then
        ML.Print(data.name .. " recorded.")
    else ML.Print("This mob has already been recorded.") end
end

function ML.Print(message) print("|cff58d6bdMobLog|r  " .. message) end

local function ReadLoot()
    -- Each corpse may contribute multiple slots; GUID dedup also covers AoE loot,
    -- repeated LOOT_READY/LOOT_OPENED and manual confirmation of the same corpse.
    -- Capture all volatile slot data once, before metadata reads or UI refreshes.
    local capture = ML.CaptureLoot()
    ML.Observe("target", true, false)
    for _, slot in ipairs(capture.slots) do
        local sources = slot.sources
        for i = 1, #sources, 2 do
            local guid = ML.Public(sources[i])
            if ML.CreatureID(guid) then ML.Record(guid, "loot", cache[guid], true) end
        end
    end
    ML.ReadItemLoot(capture, true)
    if ML.Refresh then ML.QueueRefresh() end
end

frame:SetScript("OnEvent", function(_, event, name)
    if event == "ADDON_LOADED" then
        if name ~= "MobLog" then return end
        MobLogDB = MobLogDB or { version = 1, mobs = {}, seen = {} }
        ML.db = MobLogDB
        ML.db.options = ML.db.options or {}
        if ML.db.options.targetOnlySeen == nil then ML.db.options.targetOnlySeen = false end
        ML.RemoveUnidentifiedSightings()
        ML.db.lootSeen = ML.db.lootSeen or {}
        ML.db.characters = ML.db.characters or {}
        ML.db.sightingSeen = ML.db.sightingSeen or {}
        ML.db.version = 4
        ML.MigrateLocations()
        ML.session = 0
        if ML.StartSessionReport then ML.StartSessionReport() end
        for id, mob in pairs(ML.db.mobs) do
            if mob.name == "Unbekannter Mob #" .. id then mob.name = "Unknown mob #" .. id end
        end
        ML.QueueUnknownNames()
        -- Bound dedup history; a corpse cannot normally survive seven days.
        for guid, stamp in pairs(ML.db.seen) do
            if time() - stamp > 604800 then ML.db.seen[guid] = nil end
        end
        for guid, entry in pairs(ML.db.lootSeen) do
            if time() - entry.time > 604800 then ML.db.lootSeen[guid] = nil end
        end
        for guid, entries in pairs(ML.db.sightingSeen) do
            for character, stamp in pairs(entries) do
                if time() - stamp > 604800 then entries[character] = nil end
            end
            if not next(entries) then ML.db.sightingSeen[guid] = nil end
        end
        ML.Print("Ready. Type /moblog to open your bestiary.")
    elseif ML.db then
        if event == "PLAYER_LOGIN" then
            ML.UpdateCharacter()
            ML.RegisterOptions()
            ML.ScheduleBackgroundCatalog()
            if ML.RegisterNPCTooltip then ML.RegisterNPCTooltip() end
            if ML.QueueHuntTrackerRefresh then ML.QueueHuntTrackerRefresh() end
            ML.ScanVisibleUnits()
        elseif event == "PLAYER_ENTERING_WORLD" then ML.ScanVisibleUnits(); ML.MetadataWorldChanged()
        elseif event == "PLAYER_LEAVING_WORLD" then ML.CancelMetadataRequests(); ML.ClearPassiveSightings()
        elseif event == "PLAYER_REGEN_ENABLED" then
            ML.ScanVisibleUnits()
            ML.ResumeMetadataRequests()
        elseif event == "PLAYER_TARGET_CHANGED" then
            ML.Observe("target", false, true)
        elseif event == "UPDATE_MOUSEOVER_UNIT" then ML.QueuePassiveSighting("mouseover")
        elseif event == "PLAYER_FOCUS_CHANGED" then ML.QueuePassiveSighting("focus")
        elseif event == "NAME_PLATE_UNIT_ADDED" then ML.QueuePassiveSighting(name)
        elseif event == "NAME_PLATE_UNIT_REMOVED" then ML.RemovePassiveSighting(name)
        elseif event == "CVAR_UPDATE" then
            local cvar = ML.Public(name)
            if type(cvar) == "string" and cvar:lower():find("nameplate", 1, true) then ML.ScanVisibleUnits() end
        elseif event == "UNIT_MODEL_CHANGED" or event == "UNIT_PORTRAIT_UPDATE" or event == "UNIT_NAME_UPDATE" then
            local unit = ML.Public(name)
            if unit == "target" then
                local guid, data = ML.Observe(unit, false, false)
                if data and event == "UNIT_MODEL_CHANGED" and ML.RequestUnitPortrait then ML.RequestUnitPortrait(unit, guid, data.id, true) end
            elseif type(unit) == "string" and event == "UNIT_NAME_UPDATE" then
                ML.QueuePassiveSighting(unit)
            end
        elseif event == "LOOT_READY" or event == "LOOT_OPENED" or event == "LOOT_SLOT_CHANGED" then ReadLoot() end
        ML.KillTrackerEvent(event, name)
        -- Keep the transient name cache bounded during long play sessions.
        local now = GetTime()
        if now >= nextCachePrune then
            nextCachePrune = now + 10
            for guid, data in pairs(cache) do
                if now - data.seen > 600 then cache[guid] = nil end
            end
        end
    end
end)
for _, event in ipairs({ "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEAVING_WORLD", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "UNIT_MODEL_CHANGED", "UNIT_PORTRAIT_UPDATE", "UNIT_NAME_UPDATE", "PLAYER_FOCUS_CHANGED", "PLAYER_REGEN_ENABLED", "PLAYER_REGEN_DISABLED", "UNIT_HEALTH", "UNIT_FLAGS", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE", "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "CVAR_UPDATE", "LOOT_READY", "LOOT_OPENED", "LOOT_SLOT_CHANGED" }) do
    frame:RegisterEvent(event)
end
SLASH_MOBLOG1 = "/moblog"
SLASH_MOBLOG2 = "/ml"
SlashCmdList.MOBLOG = function(text)
    if text == "tracker" then ML.ToggleHuntTracker()
    elseif text == "session" then ML.OpenSessionReport()
    elseif text == "add" then ML.ConfirmTarget()
    elseif text == "repair" then
        ML.RepairNames(true)
        if ML.MetadataBlocked() then ML.Print("Metadata recovery deferred until outside the instance and out of combat.")
        else ML.Print("Missing NPC details queued for recovery.") end
        if ML.Refresh then ML.QueueRefresh() end
    elseif text == "unknown hostile" then ML.Print(string.format("Marked %d unknown NPC types as Hostile.", ML.MarkUnknownHostile()))
    else ML.Toggle() end
end
