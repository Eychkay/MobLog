-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local classifications = {
    normal = "Normal", trivial = "Trivial", minus = "Minor",
    rare = "Rare", elite = "Elite", rareelite = "Rare Elite", worldboss = "World Boss",
}

function ML.ReadMobDetails(unit)
    local reaction = ML.Public(UnitReaction(unit, "player"))
    return {
        classification = ML.Public(UnitClassification(unit)),
        boss = ML.Public(UnitIsBossMob(unit)),
        level = ML.Public(UnitLevel(unit)),
        reaction = type(reaction) == "number" and (reaction >= 5 and "friendly" or (reaction == 4 and "neutral" or "hostile")) or nil,
    }
end

function ML.ApplyMobDetails(mob, data)
    if not data then return end
    local changed = false
    for _, field in ipairs({ "classification", "boss", "level" }) do
        if data[field] ~= nil and data[field] ~= mob[field] then
            mob[field] = data[field]; changed = true
        end
    end
    if data.reaction then
        mob.observedReaction = data.reaction
        local effective = mob.reactionOverride or data.reaction
        if mob.reaction ~= effective then mob.reaction = effective; changed = true end
    end
    return changed
end

function ML.ClassificationLabel(mob)
    if mob.classification == "worldboss" then return "World Boss" end
    if mob.boss then return "Boss" end
    return classifications[mob.classification] or "Unknown"
end

ML.MobTypeFilters = {
    { key = "all", label = "All types" }, { key = "normal", label = "Normal" },
    { key = "rare", label = "Rare" }, { key = "elite", label = "Elite" },
    { key = "rareelite", label = "Rare Elite" }, { key = "boss", label = "Boss" },
    { key = "worldboss", label = "World Boss" }, { key = "minor", label = "Minor / Trivial" },
    { key = "unknown", label = "Unknown" },
}

function ML.MatchesMobType(mob, filter)
    local kind = mob.classification
    local label = ML.ClassificationLabel(mob)
    if filter == "all" then return true end
    if filter == "rare" then return kind == "rare" or kind == "rareelite" end
    if filter == "elite" then return kind == "elite" or kind == "rareelite" end
    if filter == "boss" then return label == "Boss" or label == "World Boss" end
    if filter == "minor" then return kind == "minus" or kind == "trivial" end
    if filter == "unknown" then return label == "Unknown" end
    return kind == filter and (filter ~= "normal" or label == "Normal")
end

function ML.CanPinLocation(place)
    return type(place.map) == "number" and place.map > 0
        and type(place.x) == "number" and place.x >= 0 and place.x <= 1
        and type(place.y) == "number" and place.y >= 0 and place.y <= 1
end

function ML.PinLocation(place)
    if not ML.CanPinLocation(place) then ML.Print("No saved coordinates for this location."); return false end
    if InCombatLockdown() then ML.Print("Please open the map after combat."); return false end
    if not C_Map.CanSetUserWaypointOnMap(place.map) then
        ML.Print("WoW does not support waypoints on this map."); return false
    end
    local point = UiMapPoint.CreateFromCoordinates(place.map, place.x, place.y)
    if not C_Map.SetUserWaypoint(point) then ML.Print("Could not set a waypoint here."); return false end
    if C_SuperTrack then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
    C_Map.OpenWorldMap(place.map)
    return true
end
