-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

function ML.ScanVisibleUnits()
    ML.Observe("target", true, false)
    if not ML.TargetOnlySeen() and not ML.InstanceLootOnly() then
        ML.QueuePassiveSighting("mouseover")
        ML.QueuePassiveSighting("focus")
        if C_NamePlate and C_NamePlate.GetNamePlates then
            local ok, plates = pcall(C_NamePlate.GetNamePlates)
            plates = ok and ML.Public(plates)
            if type(plates) == "table" then
                for _, plate in pairs(plates) do
                    plate = ML.Public(plate)
                    if plate and (not plate.IsForbidden or not plate:IsForbidden()) then
                        local unit = ML.Public(plate.unitToken) or ML.Public(plate.namePlateUnitToken)
                        if not unit and plate.GetUnit then
                            local success, token = pcall(plate.GetUnit, plate)
                            if success then unit = ML.Public(token) end
                        end
                        ML.QueuePassiveSighting(unit)
                    end
                end
            end
        end
    end
    if ML.Refresh then ML.QueueRefresh() end
end

function ML.MetadataBlocked()
    return InCombatLockdown() or (IsInInstance and ML.Public(IsInInstance()) ~= false)
end

function ML.UnknownName(name, id)
    return type(name) ~= "string" or name == "" or name == "Unknown mob #" .. id
        or name == "Unbekannter Mob #" .. id or name == UNKNOWNOBJECT or name == UNKNOWN
end

-- Only use public tooltip data outside combat; never infer faction or elite status.
function ML.ResolveMobName(guid)
    local id = ML.CreatureID(guid)
    local mob = id and ML.db.mobs[id]
    if not mob or not ML.UnknownName(mob.name, id) or ML.MetadataBlocked() then return false end
    if not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then return false end
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, "unit:" .. guid)
    data = ok and ML.Public(data)
    if type(data) ~= "table" then return false end
    local kind = ML.Public(data.type)
    if kind ~= 2 and kind ~= 3 then return false end -- Unit / Corpse
    local returnedGUID = ML.Public(data.guid)
    if returnedGUID and ML.CreatureID(returnedGUID) ~= id then return false end
    local lines = ML.Public(data.lines)
    if type(lines) ~= "table" then return false end
    for _, line in ipairs(lines) do
        line = ML.Public(line)
        if type(line) == "table" and ML.Public(line.type) == 2 then -- UnitName
            local name = ML.Public(line.leftText)
            if not ML.UnknownName(name, id) then mob.name = name; mob.nameSource = "tooltip"; return true end
        end
    end
    return false
end

function ML.RepairNames(force)
    if ML.MetadataBlocked() then return 0 end
    local repaired, tried = 0, {}
    for guid in pairs(ML.db.seen) do
        local id = ML.CreatureID(guid)
        if id and (tried[id] or 0) < 3 then
            -- Permit a few real GUIDs per NPC in case an older corpse is unavailable.
            if ML.ResolveMobName(guid) then repaired = repaired + 1; tried[id] = 3
            else tried[id] = (tried[id] or 0) + 1 end
        end
    end
    ML.QueueUnknownNames(force)
    return repaired
end

-- This synthetic link queries public NPC type data only. It is never used as
-- a sighting, corpse GUID or kill key, or to infer attitude/classification.
local function PlainTooltipText(value)
    value = ML.Public(value)
    if type(value) ~= "string" then return nil end
    return value:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):match("^%s*(.-)%s*$")
end

local function EscapePattern(value)
    return (value:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

-- UI vocabulary only, never NPC IDs or NPC records. Some client builds omit
-- the old format globals or creature-type APIs used by the main parser.
local tooltipVocabulary = {
    deDE = { level = "Stufe", elite = "Elite", rare = "Selten", rareelite = "Seltene Elite", worldboss = "Weltboss", boss = "Boss", types = { "Wildtier", "Humanoid" } },
    enUS = { level = "Level", elite = "Elite", rare = "Rare", rareelite = "Rare Elite", worldboss = "World Boss", boss = "Boss", types = { "Beast", "Humanoid" } },
}
tooltipVocabulary.enGB = tooltipVocabulary.enUS
local function TooltipVocabulary()
    return GetLocale and tooltipVocabulary[GetLocale()] or {}
end

local function IsGenericLevelLine(text)
    if not text then return false end
    if type(UNIT_LETHAL_LEVEL_TEMPLATE) == "string" and text == UNIT_LETHAL_LEVEL_TEMPLATE then return true, true end
    for _, key in ipairs({ "TOOLTIP_UNIT_LEVEL", "UNIT_LEVEL_TEMPLATE" }) do
        local template = _G[key]
        if type(template) == "string" then
            local first, last = template:find("%%[sd]")
            if first then
                local value = text:match("^" .. EscapePattern(template:sub(1, first - 1)) .. "(.-)" .. EscapePattern(template:sub(last + 1)) .. "$")
                if value and (value:match("^%d") or value:match("^%?%?")) then return true, value == "??" or value:match("^%d+$") ~= nil end
            end
        end
    end
    local prefix = TooltipVocabulary().level
    if prefix then
        local value = text:match("^" .. EscapePattern(prefix) .. "%s+(.+)$")
        if value and (value:match("^%d") or value:match("^%?%?")) then return true, value == "??" or value:match("^%d+$") ~= nil end
    end
    return false
end

-- Localized creature-type labels come from the client, not an NPC database.
local function ClientCreatureTypes()
    local names = {}
    for _, name in ipairs(TooltipVocabulary().types or {}) do names[name] = true end
    if not C_CreatureInfo or not C_CreatureInfo.GetCreatureTypeIDs or not C_CreatureInfo.GetCreatureTypeInfo then return names end
    local ok, ids = pcall(C_CreatureInfo.GetCreatureTypeIDs)
    ids = ok and ML.Public(ids)
    if type(ids) ~= "table" then return names end
    for _, id in pairs(ids) do
        id = ML.Public(id)
        if type(id) == "number" then
            local success, info = pcall(C_CreatureInfo.GetCreatureTypeInfo, id)
            info = success and ML.Public(info)
            local name = type(info) == "table" and PlainTooltipText(info.name)
            if type(name) == "string" and name ~= "" then names[name] = true end
        end
    end
    return names
end

function ML.LookupNPCMetadata(id)
    id = ML.Public(id)
    if type(id) ~= "number" or id <= 0 or id % 1 ~= 0 then return nil, "invalid NPC ID" end
    if InCombatLockdown() then return nil, "waiting for end of combat" end
    if IsInInstance and ML.Public(IsInInstance()) ~= false then return nil, "waiting until outside the instance" end
    if not C_TooltipInfo or not C_TooltipInfo.GetHyperlink then return nil, "tooltip API unavailable" end
    local link = string.format("unit:Creature-0-0-0-0-%d-0000000000", id)
    local ok, data = pcall(C_TooltipInfo.GetHyperlink, link)
    if not ok then return nil, "tooltip query rejected" end
    data = ML.Public(data)
    if type(data) ~= "table" then return nil, "no readable tooltip data" end
    local kind = ML.Public(data.type)
    if kind ~= 2 and kind ~= 3 then return nil, "no unit tooltip returned" end
    if issecretvalue and issecretvalue(data.guid) then return nil, "tooltip identity restricted" end
    local guid = ML.Public(data.guid)
    if guid and ML.CreatureID(guid) ~= id then return nil, "tooltip identity mismatched" end
    local lines = ML.Public(data.lines)
    if type(lines) ~= "table" then return nil, "no readable tooltip lines" end
    local details = {}
    local creatureTypes, bareLevel
    for index, line in ipairs(lines) do
        line = ML.Public(line)
        if type(line) == "table" then
            if not (issecretvalue and issecretvalue(line.type)) then
                local lineType = ML.Public(line.type)
                local text = ML.Public(line.leftText)
                if index > 1 and (lineType == 0 or lineType == nil) then
                    local plain = PlainTooltipText(text)
                    if IsGenericLevelLine(plain) then lineType = 47
                    elseif plain then
                        creatureTypes = creatureTypes or ClientCreatureTypes()
                        if creatureTypes[plain] then lineType = 48 end
                    end
                end
                -- ID-only tooltips can expose the heading as None, not UnitName.
                if lineType == 2 or (index == 1 and (lineType == 0 or lineType == nil)) then
                    local name = ML.Public(line.leftText)
                    if not ML.UnknownName(name, id) and name ~= RETRIEVING_DATA then details.name = name end
                elseif lineType == 47 or lineType == 48 then -- UnitLevel / UnitType
                    local value = ML.Public(line.leftText)
                    if type(value) == "string" and value ~= "" and value ~= RETRIEVING_DATA then
                        value = PlainTooltipText(value)
                        details[lineType == 47 and "tooltipLevel" or "tooltipType"] = value
                        if lineType == 47 then
                            local recognized, bare = IsGenericLevelLine(value)
                            if bare or (not recognized and (value:match("^[^%d%?]*%d+$") or value:match("^[^%d%?]*%?%?$"))) then bareLevel = true end
                            local number = value:match("(%d+)")
                            local _, count = value:gsub("%d+", "")
                            if count == 1 then details.level = tonumber(number)
                            elseif value:find("??", 1, true) then details.level = -1 end
                        end
                        -- Only explicit, localized classification labels qualify.
                        -- Bare level lines become Normal after explicit labels and live data are checked.
                        local vocabulary = TooltipVocabulary()
                        for _, entry in ipairs({
                            { "rareelite", _G.RARE_ELITE or vocabulary.rareelite }, { "worldboss", _G.WORLD_BOSS or vocabulary.worldboss },
                            { "rare", _G.RARE or vocabulary.rare }, { "elite", _G.ELITE or vocabulary.elite },
                        }) do
                            local label = entry[2]
                            if type(label) == "string" and label ~= "" then
                                local start, finish = value:find(label, 1, true)
                                if start and (start == 1 or value:sub(start - 1, start - 1):match("[%s%(]"))
                                    and (finish == #value or value:sub(finish + 1, finish + 1):match("[%s%)]")) then
                                    if not details.classification then details.classification = entry[1]
                                    elseif (details.classification == "rare" and entry[1] == "elite") then details.classification = "rareelite" end
                                end
                            end
                        end
                        local boss = _G.BOSS or vocabulary.boss
                        if type(boss) == "string" and (value == boss or value:find("(" .. boss .. ")", 1, true)) then details.boss = true end
                    end
                end
                -- Only a readable, matching unit can establish player-relative attitude.
                local token = ML.Public(line.unitToken)
                if type(token) == "string" and ML.CreatureID(ML.Public(UnitGUID(token))) == id then
                    local observed = ML.ReadMobDetails(token)
                    for key, value in pairs(observed) do details[key] = value end
                    local reaction = ML.Public(UnitReaction(token, "player"))
                    if type(reaction) == "number" and reaction >= 1 and reaction <= 8 then
                        details.reaction = reaction >= 5 and "friendly" or (reaction == 4 and "neutral" or "hostile")
                    end
                end
            end
        end
    end
    if bareLevel and not details.classification and not details.boss then details.classification = "normal" end
    if next(details) then return details, "resolved" end
    return nil, "no readable NPC metadata"
end

function ML.LookupNPCName(id)
    local details, status = ML.LookupNPCMetadata(id)
    return details and details.name, status
end

function ML.ApplyResolvedName(id, name, source)
    local mob = ML.db.mobs[id]
    if not mob or not ML.UnknownName(mob.name, id) or ML.UnknownName(name, id) then return false end
    mob.name, mob.nameSource = name, source
    return true
end

function ML.MissingNPCField(value)
    return value == nil or value == "" or value == "unknown" or value == "Unknown" or value == UNKNOWN
end

function ML.ApplyNPCMetadata(id, details)
    local mob = ML.db.mobs[id]
    if not mob or not details then return false end
    local changed = ML.ApplyResolvedName(id, details.name, "npc-id-tooltip")
    if mob.level == -1 and type(details.level) == "number" and details.level > 0 then
        mob.level = details.level
        if details.tooltipLevel then mob.tooltipLevel = details.tooltipLevel end
        changed = true
    end
    for _, field in ipairs({ "level", "classification", "boss", "tooltipLevel", "tooltipType" }) do
        if ML.MissingNPCField(mob[field]) and not ML.MissingNPCField(details[field]) then mob[field] = details[field]; changed = true end
    end
    if details.reaction and ML.MissingNPCField(mob.observedReaction) then
        mob.observedReaction = details.reaction
        if not mob.reactionOverride and ML.MissingNPCField(mob.reaction) then mob.reaction = details.reaction end
        changed = true
    end
    return changed
end

function ML.NeedsNPCMetadata(mob)
    return ML.UnknownName(mob.name, mob.id) or ML.MissingNPCField(mob.level) or mob.level == -1
        or ML.MissingNPCField(mob.classification) or ML.MissingNPCField(mob.boss)
        or (not mob.reactionOverride and ML.MissingNPCField(mob.reaction))
        or ML.MissingNPCField(mob.tooltipType)
end

function ML.PendingDungeonIdentity(mob)
    if not IsInInstance or ML.Public(IsInInstance()) ~= true then return false end
    if mob.members then
        for _, member in ipairs(mob.members) do if ML.PendingDungeonIdentity(member) then return true end end
        return false
    end
    return ML.UnknownName(mob.name, mob.id) or ML.MissingNPCField(mob.classification)
        or (not mob.reactionOverride and ML.MissingNPCField(mob.reaction))
end

function ML.RevealDungeonRecord(mob)
    if not ML.PendingDungeonIdentity(mob) or not ML.MissingNPCField(mob.reaction) then return end
    ML.db.closedGroups = ML.db.closedGroups or ML.DefaultClosedGroups()
    ML.db.closedGroups.unknown = false
end

local pending, attempted = {}, {}
local deferred = {}
local nextRequest = 0
local generation = 0

function ML.NPCMetadataStatus(mob)
    if mob.catalogOnly then return nil end
    if mob.members then
        local fallback
        for _, member in ipairs(mob.members) do
            local status, short = ML.NPCMetadataStatus(member)
            if short then return status, short end
            fallback = fallback or status
        end
        return fallback
    end
    if mob.provisional then
        if IsInInstance and ML.Public(IsInInstance()) == true then
            return "NPC identity pending — data restricted in this instance", "Data lookup pending"
        end
        return "Unresolved sighting — the NPC ID was restricted"
    end
    if not ML.NeedsNPCMetadata(mob) then return end
    if IsInInstance and ML.Public(IsInInstance()) ~= false then
        return "Data lookup pending — available after leaving the dungeon", "Data lookup pending"
    end
    if pending[mob.id] then return "Data lookup in progress", "Data lookup in progress" end
    if not mob.metadataLookupAt then
        if InCombatLockdown() then return "Data lookup pending — waiting for combat to end", "Data lookup pending" end
        return "Data lookup pending", "Data lookup pending"
    end
    return "Some data unavailable from WoW"
end

function ML.CancelMetadataRequests()
    generation = generation + 1
    pending, attempted, deferred, nextRequest = {}, {}, {}, 0
end

function ML.MetadataWorldChanged()
    ML.CancelMetadataRequests()
    if not C_Timer or not C_Timer.After then return end
    local token = generation
    C_Timer.After(1, function()
        if token == generation then
            ML.QueueUnknownNames(true)
            if ML.Refresh then ML.QueueRefresh() end
        end
    end)
    if ML.Refresh then ML.QueueRefresh() end
end

function ML.QueueNPCName(id, force)
    local mob = ML.db.mobs[id]
    if not mob or mob.provisional or not ML.NeedsNPCMetadata(mob) or pending[id] then return false end
    if not C_Timer or not C_Timer.After then return false end
    local now = GetTime()
    if not force and attempted[id] and now - attempted[id] < 60 then return false end
    if ML.MetadataBlocked() then deferred[id] = true; return false end
    deferred[id] = nil
    local attempts = 0
    local token = generation
    pending[id] = true
    local function Query()
        if token ~= generation then return end
        local current = ML.db.mobs[id]
        if not current or not ML.NeedsNPCMetadata(current) then pending[id] = nil; return end
        if ML.MetadataBlocked() then
            pending[id], attempted[id] = nil, nil -- Allow immediate resumption after combat.
            deferred[id] = true
            return
        end
        attempts = attempts + 1
        attempted[id] = GetTime()
        local details, status = ML.LookupNPCMetadata(id)
        local changed = details and ML.ApplyNPCMetadata(id, details)
        if attempts < 3 and ML.NeedsNPCMetadata(current) and status ~= "tooltip API unavailable" and status ~= "tooltip query rejected" then
            C_Timer.After(attempts, Query)
            if changed and ML.Refresh then ML.QueueRefresh() end
        else
            pending[id] = nil
            current.metadataLookupAt = time()
            if changed then
                if ML.Refresh then ML.QueueRefresh() end
            elseif ML.RefreshNPCStatus then ML.RefreshNPCStatus(id) end
        end
    end
    -- Spread initial requests for old collections containing many unknown IDs.
    nextRequest = math.max(now, nextRequest) + 0.1
    C_Timer.After(nextRequest - now, Query)
    return true
end

function ML.QueueUnknownNames(force)
    for id in pairs(ML.db.mobs) do ML.QueueNPCName(id, force) end
end

function ML.ResumeMetadataRequests()
    if ML.MetadataBlocked() then return end
    local work = deferred
    deferred = {}
    for id in pairs(work) do ML.QueueNPCName(id, true) end
end
