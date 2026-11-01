-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local cachedGroups,cachedByID,cachedDB,cachedMobs
function ML.InvalidateMobGroups()
    cachedGroups,cachedByID=nil,nil
    ML.tooltipGroups=nil
end

function ML.SetNameGrouping(id, enabled)
    local mob = ML.db.mobs[id]
    if not mob or type(mob.name) ~= "string" or mob.name == "" then return false end
    ML.db.nameGroups = ML.db.nameGroups or {}
    ML.db.nameGroups[mob.name] = enabled and true or nil
    ML.InvalidateMobGroups()
    local _, byID = ML.BuildMobGroups()
    ML.db.closedGroups = ML.db.closedGroups or {}
    for _, key in ipairs(ML.DiscoveryPath(byID[id])) do ML.db.closedGroups[key] = false end
    return true
end

-- Derived groups only: source records and item denominators are never merged.
function ML.BuildMobGroups(affected)
    if not affected and cachedGroups and cachedDB==ML.db and cachedMobs==ML.db.mobs then return cachedGroups,cachedByID end
    local wanted
    if affected then
        wanted={}
        for id in pairs(affected) do
            local mob=ML.db.mobs[id]
            if mob then wanted[mob.name]=true end
        end
        if not next(wanted) then return {},{} end
    end
    local ordered, parent, keys, names = {}, {}, {}, {}
    for _, mob in pairs(ML.db.mobs) do
        if not wanted or wanted[mob.name] then ordered[#ordered + 1] = mob end
    end
    table.sort(ordered, function(a, b) return a.id < b.id end)
    local function Root(id)
        if parent[id] ~= id then parent[id] = Root(parent[id]) end
        return parent[id]
    end
    for _, mob in ipairs(ordered) do
        parent[mob.id] = mob.id
        if not mob.provisional and ML.db.nameGroups and ML.db.nameGroups[mob.name] then
            if names[mob.name] then
                local a, b = Root(mob.id), Root(names[mob.name])
                parent[math.max(a, b)] = math.min(a, b)
            else names[mob.name] = mob.id end
        end
        local displays = {}
        for id in pairs(mob.displayIDs or {}) do displays[id] = true end
        if mob.displayID then displays[mob.displayID] = true end
        for display in pairs(displays) do
            if type(display) == "number" and display > 0 then
                local key = mob.name .. "\031" .. display
                if keys[key] then
                    local a, b = Root(mob.id), Root(keys[key])
                    parent[math.max(a, b)] = math.min(a, b)
                else keys[key] = mob.id end
            end
        end
    end
    local groups, byRoot, byID = {}, {}, {}
    for _, mob in ipairs(ordered) do
        local root = Root(mob.id)
        local group = byRoot[root]
        if not group then
            group = { members = {}, memberIDs = {}, count = 0, sightings = 0, places = {}, sightingPlaces = {} }
            byRoot[root] = group; groups[#groups + 1] = group
        end
        group.members[#group.members + 1] = mob
        group.memberIDs[mob.id] = true; byID[mob.id] = group
    end
    for _, group in ipairs(groups) do
        local representative = group.members[1]
        for _, mob in ipairs(group.members) do
            if ML.RecentBefore(mob, representative) then representative = mob end
        end
        for key, value in pairs(representative) do
            if group[key] == nil then group[key] = value end
        end
        group.id = group.members[1].id
        group.representativeID = representative.id
        group.first, group.last = nil, 0
        group.lastKilled, group.lastKilledOrder = nil, nil
        group.lastSeen, group.lastSeenOrder = nil, nil
        for _, mob in ipairs(group.members) do
            group.count = group.count + mob.count
            group.sightings = group.sightings + (mob.sightings or 0)
            if mob.first and (not group.first or mob.first < group.first) then group.first = mob.first end
            group.last = math.max(group.last, mob.last or 0)
            for _, kind in ipairs({ "lastSeen", "lastKilled" }) do
                local stamp = mob[kind] or (kind == "lastKilled" and mob.count > 0 and mob.last) or 0
                local order = mob[kind .. "Order"] or 0
                if stamp > (group[kind] or 0) or (stamp == (group[kind] or 0) and order > (group[kind .. "Order"] or 0)) then
                    group[kind], group[kind .. "Order"] = stamp, order
                end
            end
            if not affected then
                for key, place in pairs(mob.places or {}) do group.places[mob.id .. ":" .. key] = place end
                for key, place in pairs(mob.sightingPlaces or {}) do group.sightingPlaces[mob.id .. ":" .. key] = place end
            end
        end
    end
    if not affected then cachedGroups,cachedByID,cachedDB,cachedMobs=groups,byID,ML.db,ML.db.mobs end
    return groups, byID
end

function ML.GroupForMob(id)
    if cachedByID and cachedDB==ML.db and cachedMobs==ML.db.mobs then return cachedByID[id] end
    local _,byID=ML.BuildMobGroups({[id]=true})
    return byID[id]
end

function ML.GroupContains(group, id)
    return group and (group.id == id or group.memberIDs and group.memberIDs[id])
end

-- Saved ordering resolves multiple encounters within the same timestamp second.
function ML.StampActivity(mob, kind, now)
    ML.db.activityOrder = (ML.db.activityOrder or 0) + 1
    mob[kind] = now
    mob[kind .. "Order"] = ML.db.activityOrder
end

function ML.RecentBefore(a, b)
    local ak = a.count > 0 and "lastKilled" or "lastSeen"
    local bk = b.count > 0 and "lastKilled" or "lastSeen"
    local at, bt = a[ak] or a.last or 0, b[bk] or b.last or 0
    if at ~= bt then return at > bt end
    local ao, bo = a[ak .. "Order"] or 0, b[bk .. "Order"] or 0
    if ao ~= bo then return ao > bo end
    return a.id < b.id
end

function ML.ReactionLabel(mob)
    return ({ friendly = "Friendly", neutral = "Neutral", hostile = "Hostile" })[mob.reaction] or "Unknown"
end

function ML.SetAttitude(id, reaction)
    local mob = ML.db.mobs[id]
    if not mob then return false end
    if not mob.reactionOverride and not mob.observedReaction then mob.observedReaction = mob.reaction end
    if reaction == "auto" then
        mob.reactionOverride = nil; mob.reaction = mob.observedReaction
    elseif reaction == "friendly" or reaction == "neutral" or reaction == "hostile" or reaction == "unknown" then
        mob.reactionOverride, mob.reaction = reaction, reaction
    else return false end
    ML.InvalidateMobGroups()
    ML.db.closedGroups = ML.db.closedGroups or {}
    for _, key in ipairs(ML.DiscoveryPath(mob)) do ML.db.closedGroups[key] = false end
    return true
end

function ML.MarkUnknownHostile()
    local changed = 0
    for id, mob in pairs(ML.db.mobs) do
        if not mob.reaction or mob.reaction == "unknown" then
            ML.SetAttitude(id, "hostile"); changed = changed + 1
        end
    end
    if ML.Refresh then ML.Refresh() end
    return changed
end

function ML.MatchesDiscovery(mob, reaction, status)
    return (reaction == "all" or (mob.reaction or "unknown") == reaction)
        and (status == "all" or (status == "seen" and mob.count == 0) or (status == "killed" and mob.count > 0))
end

function ML.RecordSighting(guid, data, unit)
    if ML.InstanceLootOnly and ML.InstanceLootOnly() then return false end
    if ML.Public(UnitPlayerControlled(unit)) ~= false then return false end
    local now, id = time(), data.id
    local mob = ML.db.mobs[id]
    local changed = not mob
    if not mob then
        mob = { id = id, name = data.name, count = 0, loot = 0, manual = 0,
            first = now, last = now, places = {} }
        ML.db.mobs[id] = mob
        if ML.CatalogRecordAdded then ML.CatalogRecordAdded(id) end
        if ML.SessionDiscovery then ML.SessionDiscovery(id) end
    end
    local reaction = ML.Public(UnitReaction(unit, "player"))
    if type(reaction) == "number" then
        local label = reaction >= 5 and "friendly" or (reaction == 4 and "neutral" or "hostile")
        mob.observedReaction = label
        local effective = mob.reactionOverride or label
        if mob.reaction ~= effective then mob.reaction = effective; changed = true end
    end
    local seenChanged = mob.lastSeen ~= now
    -- Repeated unit events in one second must not continuously reshuffle rows.
    if seenChanged then ML.StampActivity(mob, "lastSeen", now) end
    mob.last = now
    if mob.count == 0 and seenChanged then changed = true end
    local character = ML.UpdateCharacter() or "unknown"
    local seen = ML.db.sightingSeen[guid]
    if not seen then seen = {}; ML.db.sightingSeen[guid] = seen end
    if seen[character] then return changed end
    seen[character] = now
    mob.sightings = (mob.sightings or 0) + 1
    mob.sightingPlaces = mob.sightingPlaces or {}
    ML.RecordLocation({ places = mob.sightingPlaces }, ML.Location(), now)
    mob.sightingCharacters = mob.sightingCharacters or {}
    local stats = mob.sightingCharacters[character] or { count = 0, first = now }
    stats.count, stats.last = stats.count + 1, now
    mob.sightingCharacters[character] = stats
    return true
end

function ML.DiscoveryPath(mob)
    local reaction = mob.reaction or "unknown"
    if reaction == "hostile" then return { reaction, "hostile:" .. (mob.count > 0 and "killed" or "seen") } end
    if reaction == "friendly" or reaction == "neutral" then return { "nonhostile" } end
    return { reaction }
end

function ML.DefaultClosedGroups()
    local closed = { hostile = true, ["hostile:killed"] = true, ["hostile:seen"] = true, nonhostile = true, unknown = true, undiscovered = true }
    if ML.db and ML.PendingDungeonIdentity then
        for _, mob in pairs(ML.db.mobs) do
            if ML.PendingDungeonIdentity(mob) and ML.MissingNPCField(mob.reaction) then closed.unknown = false; break end
        end
    end
    return closed
end

function ML.DiscoveryLayout(mobs, closed)
    local buckets = { hunts = {}, nonhostile = {}, hostile = {}, unknown = {} }
    for _, mob in ipairs(mobs) do
        local key = ML.IsHuntTarget and ML.IsHuntTarget(mob) and "hunts" or
            ((mob.reaction == "friendly" or mob.reaction == "neutral") and "nonhostile" or (buckets[mob.reaction] and mob.reaction or "unknown"))
        buckets[key][#buckets[key] + 1] = mob
    end
    local layout, offset = {}, 0
    local function Header(key, label, count, indent)
        layout[#layout + 1] = { header = true, key = key, label = label, count = count, indent = indent, offset = offset }
        offset = offset + 32
    end
    local function Entries(entries, indent)
        for _, mob in ipairs(entries) do
            layout[#layout + 1] = { mob = mob, offset = offset, indent = indent }
            offset = offset + 78
        end
    end
    for _, key in ipairs({ "hunts", "hostile", "nonhostile", "unknown" }) do
        local entries = buckets[key]
        if #entries > 0 then
            local label = key == "hunts" and "Hunt targets" or (key == "nonhostile" and "Non-hostile" or (key == "unknown" and "Unknown attitude" or "Hostile"))
            Header(key, label, #entries, 0)
            if not closed[key] then
                if key == "hostile" then
                    local seen, killed = {}, {}
                    for _, mob in ipairs(entries) do
                        local target = mob.count > 0 and killed or seen
                        target[#target + 1] = mob
                    end
                    for _, group in ipairs({ {key = "killed", label = "Killed", entries = killed}, {key = "seen", label = "Seen only", entries = seen} }) do
                        Header("hostile:" .. group.key, group.label, #group.entries, 10)
                        if not closed["hostile:" .. group.key] then Entries(group.entries, 10) end
                    end
                else Entries(entries, 0) end
            end
        end
    end
    return layout, offset
end
