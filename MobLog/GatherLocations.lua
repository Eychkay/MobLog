-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

ML.GatherIcons = {
    ore = "Interface\\Icons\\INV_Ore_Copper_01",
    herb = "Interface\\Icons\\INV_Misc_Herb_19",
    fish = "Interface\\Icons\\INV_Misc_Fish_01",
}
local locationNames = { ore = "Ore deposit", herb = "Herb", fish = "Fishing spot" }

local spellKinds = {
    [2575] = "ore", [2576] = "ore", [2578] = "ore", [3564] = "ore", [10248] = "ore",
    [195122] = "ore", [423341] = "ore", [471013] = "ore",
    [2366] = "herb", [2368] = "herb", [3570] = "herb", [11993] = "herb",
    [471022] = "herb",
}
local spellNames = {}
local gather, lastCast, fishingLoot
local empty = {}
local iconsByPoint
-- Metal & Stone includes incidental stone drops as well as ore.
local stoneByproducts = {
    [2835] = true, [2836] = true, [2838] = true, [7912] = true,
    [12365] = true, [171840] = true, [171841] = true,
}

local function KindForSpell(id)
    if not id then return end
    local kind = spellKinds[id]
    if kind then return kind end
    if C_Spell and C_Spell.GetSpellName then
        local name = ML.Public(C_Spell.GetSpellName(id))
        return name and spellNames[name]
    end
end

function ML.GatherLocations(mapID)
    local maps = ML.db and ML.db.gatherLocations
    return maps and maps[mapID] or empty
end

function ML.GatherLocationName(point)
    return point.name or locationNames[point.kind]
end

local function GatherPointKey(mapID, point)
    return string.format("%d:%.7f:%.7f:%s", mapID, point.x, point.y, point.kind)
end

local function GatherResourceIcon(id, item)
    local getInfo = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not getInfo or stoneByproducts[id] then return nil, item.icon end
    local _, _, _, _, icon, classID, subclassID = getInfo(id)
    classID, subclassID = ML.Public(classID), ML.Public(subclassID)
    icon = item.icon or ML.Public(icon)
    if classID == 7 then -- Trade Goods
        if subclassID == 7 then return "ore", icon end -- Metal & Stone
        if subclassID == 9 then return "herb", icon end
    end
    return nil, icon
end

local function IndexGatherIcon(key, id, source, icon)
    local current = iconsByPoint[key]
    if not current or source.quantity > current.source.quantity
        or (source.quantity == current.source.quantity and id <= current.id) then
        iconsByPoint[key] = { id = id, source = source, icon = icon }
    end
end

function ML.GetGatherLocationIcon(mapID, point)
    if not iconsByPoint then
        iconsByPoint = {}
        for id, item in pairs(ML.db.gatheredItems or empty) do
            local kind, icon = GatherResourceIcon(id, item)
            if icon then
                for key, source in pairs(item.sources) do
                    if source.kind == kind or source.kind == "fish" then IndexGatherIcon(key, id, source, icon) end
                end
            end
        end
    end
    local entry = iconsByPoint[GatherPointKey(mapID, point)]
    return entry and entry.icon
end

local function RefreshGatherLocationPins(mapID)
    if ML.RefreshGatherPins then ML.RefreshGatherPins(mapID) end
    if ML.RefreshMinimapGatherPins then ML.RefreshMinimapGatherPins() end
end

local function SaveGatherLoot(cast)
    local db = ML.db
    local point = cast.point
    if not point or not cast.items or not next(cast.items) then return end
    local key = GatherPointKey(point.map, point)
    db.gatheredItems = db.gatheredItems or {}
    cast.saved = cast.saved or {}
    local changed
    for id, loot in pairs(cast.items) do
        local delta = loot.quantity - (cast.saved[id] or 0)
        if delta > 0 then
            local item = db.gatheredItems[id] or { quantity = 0, sources = {} }
            db.gatheredItems[id] = item
            item.name, item.link, item.icon, item.quality = loot.name or item.name, loot.link or item.link,
                loot.icon or item.icon, loot.quality or item.quality
            item.quantity, item.last = item.quantity + delta, cast.stamp
            local source = item.sources[key] or { map = point.map, x = point.x, y = point.y,
                zone = point.zone, kind = point.kind, quantity = 0 }
            item.sources[key] = source
            source.name, source.last = point.name or source.name, cast.stamp
            source.quantity = source.quantity + delta
            if iconsByPoint then
                local kind, icon = GatherResourceIcon(id, item)
                if icon and (kind == source.kind or source.kind == "fish") then IndexGatherIcon(key, id, source, icon) end
            end
            cast.saved[id], changed = loot.quantity, true
        end
    end
    if changed then
        ML.InvalidateItemCatalog()
        RefreshGatherLocationPins(point.map)
        if ML.QueueRefresh then ML.QueueRefresh() end
    end
    return changed
end

local function AddObservedItem(observed, slot, quantity)
    if not slot.id or type(quantity) ~= "number" or quantity <= 0 then return end
    local loot = observed[slot.id] or { quantity = 0, name = slot.name, link = slot.link, icon = slot.icon, quality = slot.quality }
    loot.quantity = loot.quantity + quantity
    observed[slot.id] = loot
end

local function MergeGatherLoot(cast, observed)
    cast.items = cast.items or {}
    for id, loot in pairs(observed) do
        if not cast.items[id] or loot.quantity > cast.items[id].quantity then cast.items[id] = loot end
    end
    SaveGatherLoot(cast)
end

local function ReadResourceLoot(capture)
    local cast = gather
    if not cast or cast.closed then return end
    local now = GetTime()
    if now - (cast.completed or cast.started) > (cast.completed and 2 or 10) then return end
    local source, observed = nil, {}
    for _, slot in ipairs(capture.slots) do
        for i = 1, #slot.sources, 2 do
            local guid, quantity = ML.Public(slot.sources[i]), ML.Public(slot.sources[i + 1])
            if type(guid) ~= "string" or not guid:match("^GameObject%-") or (source and guid ~= source) then return end
            source = guid
            AddObservedItem(observed, slot, quantity)
        end
    end
    if not source or not next(observed) or (cast.source and source ~= cast.source) then return end
    cast.source, cast.sampleAt = source, now
    MergeGatherLoot(cast, observed)
end

function ML.ShowGatherLocationTooltip(tooltip, owner, point, anchor, mapID)
    tooltip:SetOwner(owner, anchor)
    tooltip:SetText(ML.GatherLocationName(point))
    local fishing = point.kind == "fish"
    tooltip:AddLine((fishing and "Last fished " or "Last gathered ") .. date("%Y-%m-%d", point.last), 1, 1, 1)
    tooltip:AddLine(string.format("%.1f / %.1f · Approximate location", point.x * 100, point.y * 100), 0.82, 0.76, 0.66)
    if point.count then
        local countLabel = fishing and (point.count == 1 and "catch" or "catches")
            or (point.count == 1 and "gather" or "gathers")
        tooltip:AddLine(string.format("%d successful %s", point.count, countLabel), 0.82, 0.76, 0.66)
    end
    local key = GatherPointKey(mapID or point.map, point)
    local gathered = {}
    for id, item in pairs(ML.db.gatheredItems or {}) do
        local source = item.sources[key]
        if source then gathered[#gathered + 1] = { id = id, item = item, quantity = source.quantity } end
    end
    if #gathered > 0 then
        table.sort(gathered, function(a, b)
            if a.quantity ~= b.quantity then return a.quantity > b.quantity end
            return a.id < b.id
        end)
        tooltip:AddLine("Items recorded here", 1, 0.82, 0.4)
        for _, entry in ipairs(gathered) do
            local name = entry.item.link or entry.item.name or ("Item #" .. entry.id)
            tooltip:AddDoubleLine(name, tostring(entry.quantity), 1, 1, 1, 1, 1, 1)
        end
    else
        tooltip:AddLine("Item quantities not recorded here yet.", 0.82, 0.76, 0.66)
    end
    tooltip:Show()
end

local function Record(kind, name)
    if not ML.db or ML.InstanceLootOnly() or not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return end
    local mapID = ML.Public(C_Map.GetBestMapForUnit("player"))
    if type(mapID) ~= "number" then return end
    local position = ML.Public(C_Map.GetPlayerMapPosition(mapID, "player"))
    if not position then return end
    local x, y = position:GetXY()
    local place = { map = mapID, x = ML.Public(x), y = ML.Public(y) }
    if not ML.CanPinLocation(place) or (place.x == 0 and place.y == 0) then return end
    ML.db.gatherLocations = ML.db.gatherLocations or {}
    local locations = ML.db.gatherLocations[place.map] or {}
    ML.db.gatherLocations[place.map] = locations

    local width, height
    if C_Map.GetMapWorldSize then
        width, height = C_Map.GetMapWorldSize(place.map)
        width, height = ML.Public(width), ML.Public(height)
    end
    local xRadius, yRadius = 0.0015, 0.0015
    if type(width) == "number" and width > 0 and type(height) == "number" and height > 0 then
        xRadius, yRadius = math.min(14 / width, 0.004), math.min(14 / height, 0.004)
    end

    local nearest, distance = nil, 1
    for _, point in ipairs(locations) do
        if point.kind == kind and (not name or not point.name or point.name == name) then
            local dx, dy = (point.x - place.x) / xRadius, (point.y - place.y) / yRadius
            local squared = dx * dx + dy * dy
            if squared < distance then nearest, distance = point, squared end
        end
    end
    if not nearest then
        nearest = { kind = kind, x = place.x, y = place.y, count = 0 }
        locations[#locations + 1] = nearest
    end
    nearest.name = name or nearest.name
    nearest.count, nearest.last = nearest.count + 1, time()
    return { map = place.map, x = nearest.x, y = nearest.y, kind = kind, name = nearest.name,
        zone = ML.Public(GetRealZoneText()) or "" }
end

function ML.ReadGatherLoot(capture)
    if not IsFishingLoot or ML.Public(IsFishingLoot()) ~= true then
        ReadResourceLoot(capture)
        return
    end

    -- The fishing loot window identifies the catch even if bobber source GUIDs are unavailable.
    local observed = {}
    for _, slot in ipairs(capture.slots) do
        AddObservedItem(observed, slot, slot.quantity)
    end
    if not next(observed) then return end
    if not fishingLoot then
        local point = Record("fish")
        if not point then return end
        fishingLoot = { point = point, stamp = time() }
    end
    MergeGatherLoot(fishingLoot, observed)
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("UNIT_SPELLCAST_SENT")
events:RegisterEvent("LOOT_CLOSED")
events:RegisterEvent("PLAYER_LEAVING_WORLD")
events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_FAILED", "player")
events:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
events:SetScript("OnEvent", function(_, event, unit, first, second, third)
    if event == "PLAYER_LOGIN" then
        if C_Spell and C_Spell.GetSpellName then
            for id, kind in pairs(spellKinds) do
                local name = ML.Public(C_Spell.GetSpellName(id))
                if name and name ~= "" then spellNames[name] = kind end
            end
        end
        return
    end
    if event == "LOOT_CLOSED" then
        fishingLoot = nil
        if gather and gather.source then gather.closed = true end
        return
    end
    if event == "PLAYER_LEAVING_WORLD" then
        fishingLoot = nil
        return
    end
    if ML.Public(unit) ~= "player" then return end
    local cast, id
    if event == "UNIT_SPELLCAST_SENT" then
        cast, id = ML.Public(second), ML.Public(third)
        local kind = KindForSpell(id)
        local name = kind and ML.Public(first)
        gather = nil
        if kind and type(cast) == "string" then
            gather = { guid = cast, kind = kind, name = type(name) == "string" and name ~= "" and name or nil, started = GetTime() }
        end
        return
    end
    cast, id = ML.Public(first), ML.Public(second)
    if event ~= "UNIT_SPELLCAST_SUCCEEDED" then
        if gather and cast and cast == gather.guid then gather = nil end
        return
    end
    local kind = KindForSpell(id)
    if not kind or (cast and cast == lastCast) then return end
    lastCast = cast
    local now = GetTime()
    if not gather or not cast or cast ~= gather.guid or kind ~= gather.kind or now - gather.started > 10 then
        gather = { guid = cast, kind = kind, started = now }
    elseif gather.sampleAt and now - gather.sampleAt > 2 then
        gather.source, gather.items, gather.closed = nil, nil, nil
    end
    gather.completed, gather.stamp = now, time()
    gather.point = Record(kind, gather.name)
    if gather.point and not SaveGatherLoot(gather) then
        RefreshGatherLocationPins(gather.point.map)
    end
end)
