-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

function ML.ValidLocationName(name)
    return type(name)=="string" and name~="" and name~="Unknown location" and name~="Unknown"
end

function ML.CatalogHabitatMatches(id,filter)
    if ML.LocationSource(filter)=="encounters" then return false end
    local data=ML.TrinityData
    local info=data and data.ready and data.npcs[id]
    if not info then return false end
    local packed=data.habitats and data.habitats[id]
    if ML.AreaCoordinatesAreAll(filter) then return info[5][1]~=nil or packed~=nil end
    for _,area in ipairs(info[5]) do if ML.CatalogZoneMatchesArea(area,filter) then return true end end
    if packed then
        for key in packed:gmatch("[^,]+") do
            if ML.CatalogZoneMatchesArea(tonumber(key) or key,filter) then return true end
        end
    end
    return false
end

function ML.KnownHabitatNames(mob)
    local data=ML.TrinityData
    local names,seen={},{}
    if not data or not data.ready then return names end
    local function Add(key)
        local name=ML.CatalogAreaName(key)
        if ML.ValidLocationName(name) and not seen[name] then seen[name]=true; names[#names+1]=name end
    end
    for _,member in ipairs(mob.members or {mob}) do
        local info=data.npcs[member.id]
        if info then for _,key in ipairs(info[5]) do Add(key) end end
        local packed=data.habitats and data.habitats[member.id]
        if packed then for key in packed:gmatch("[^,]+") do Add(tonumber(key) or key) end end
    end
    table.sort(names,function(a,b) return string.lower(a)<string.lower(b) end)
    return names
end

local function PersonalAreas(mob)
    local byName,entries={},{}
    -- Full list groups already contain merged personal histories. Nothing is
    -- added to saved records by displaying a catalog habitat.
    for _,places in ipairs({mob.places or {},mob.sightingPlaces or {}}) do
        for _,place in pairs(places) do
            if ML.ValidLocationName(place.zone) then
                local entry=byName[place.zone]
                if not entry then entry={name=place.zone,last=place.last or 0}; byName[place.zone]=entry; entries[#entries+1]=entry
                elseif (place.last or 0)>entry.last then entry.last=place.last end
            end
        end
    end
    table.sort(entries,function(a,b) if a.last==b.last then return a.name<b.name end; return a.last>b.last end)
    return entries
end

function ML.MobLocationSummary(mob)
    local personal=PersonalAreas(mob)
    if personal[1] then return "Seen in: "..personal[1].name end
    local known=ML.KnownHabitatNames(mob)
    if known[1] then return "Found in: "..known[1]..(#known>1 and (" +"..(#known-1)) or "") end
    return "Location unknown"
end

function ML.AddMobLocationTooltip(mob)
    local personal,known=PersonalAreas(mob),ML.KnownHabitatNames(mob)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Your encounters",0.92,0.76,0.45)
    for i=1,math.min(8,#personal) do GameTooltip:AddLine(personal[i].name,0.85,0.82,0.74,true) end
    if #personal==0 then GameTooltip:AddLine("No personal encounter areas recorded.",0.65,0.62,0.56,true) end
    if #personal>8 then GameTooltip:AddLine("+"..(#personal-8).." more areas",0.85,0.82,0.74) end
    GameTooltip:AddLine("Known habitats",0.55,0.76,0.94)
    for i=1,math.min(8,#known) do GameTooltip:AddLine(known[i],0.75,0.83,0.91,true) end
    if #known==0 then GameTooltip:AddLine(ML.CatalogUnavailableText() or "No known habitat areas available.",0.65,0.62,0.56,true) end
    if #known>8 then GameTooltip:AddLine("+"..(#known-8).." more areas",0.75,0.83,0.91) end
end
