-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local active = false
local cityNames

-- Capital/hub map IDs only; NPC records do not need a bundled database.
-- Parent traversal also covers map floors within these cities.
local capitals = {
    [84] = true,   -- Stormwind
    [85] = true,   -- Orgrimmar
    [87] = true,   -- Ironforge
    [88] = true,   -- Thunder Bluff
    [89] = true,   -- Darnassus
    [90] = true,   -- Undercity
    [103] = true,  -- The Exodar
    [110] = true,  -- Silvermoon (original)
    [111] = true,  -- Shattrath
    [125] = true,  -- Dalaran (Northrend)
    [627] = true,  -- Dalaran (Broken Isles)
    [1161] = true, -- Boralus
    [1165] = true, -- Dazar'alor
    [1670] = true, -- Oribos
    [2112] = true, -- Valdrakken
    [2339] = true, -- Dornogal
    [2393] = true, -- Silvermoon (Midnight)
}

function ML.CityTargetOnlyActive()
    return active and ML.db and ML.db.options.autoTargetOnlyCities == true or false
end

local function InCapital()
    if ML.InstanceLootOnly() or not C_Map or not C_Map.GetBestMapForUnit then return false end
    local id = ML.Public(C_Map.GetBestMapForUnit("player"))
    local visited = {}
    for _ = 1, 16 do
        if type(id) ~= "number" or id <= 0 or visited[id] then break end
        if capitals[id] then return true end
        visited[id] = true
        local info = C_Map.GetMapInfo and C_Map.GetMapInfo(id)
        id = info and ML.Public(info.parentMapID)
    end
    -- Some interiors report a broader map. Match the actual zone name against
    -- localized city names supplied by the client, never a generic resting flag.
    if not cityNames and C_Map.GetMapInfo then
        cityNames = {}
        for mapID in pairs(capitals) do
            local info = C_Map.GetMapInfo(mapID)
            local name = info and ML.Public(info.name)
            if type(name) == "string" and name ~= "" then cityNames[name] = true end
        end
    end
    local zone = ML.Public(GetRealZoneText())
    return type(zone) == "string" and cityNames and cityNames[zone] == true or false
end

function ML.UpdateCitySightings(force)
    if not ML.db then return end
    local previous = active
    active = ML.db.options.autoTargetOnlyCities == true and InCapital() or false
    if previous ~= active or force then
        if ML.TargetOnlySeen() then ML.ClearPassiveSightings()
        elseif ML.ScanVisibleUnits then ML.ScanVisibleUnits() end
    end
end

local events = CreateFrame("Frame")
for _, event in ipairs({"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED_INDOORS", "PLAYER_MAP_CHANGED"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent", function() ML.UpdateCitySightings() end)
