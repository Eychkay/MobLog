-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

local function PointKey(location)
    return math.floor(location.x * 100 + 0.5) .. ":" .. math.floor(location.y * 100 + 0.5)
end

local function EnsurePoints(place)
    if place.points then return end
    place.points = {}
    if ML.CanPinLocation(place) then
        -- The old zone count cannot be assigned to its one surviving coordinate.
        place.points[PointKey(place)] = { x = place.x, y = place.y,
            first = place.last, last = place.last, count = 0, historical = true }
    end
end

function ML.MigrateLocations()
    for _, mob in pairs(ML.db.mobs) do
        for _, place in pairs(mob.places) do EnsurePoints(place) end
    end
end

function ML.RecordLocation(mob, loc, now)
    local key = tostring(loc.map or 0) .. ":" .. loc.zone .. ":" .. loc.sub
    local place = mob.places[key]
    if not place then
        place = { map = loc.map, zone = loc.zone, sub = loc.sub, count = 0, points = {} }
        mob.places[key] = place
        if ML.InvalidateItemLocations then ML.InvalidateItemLocations() end
    end
    EnsurePoints(place)
    place.count, place.last = place.count + 1, now
    place.lastOrder=ML.db.activityOrder or 0
    if ML.CanPinLocation(loc) then
        place.x, place.y = loc.x, loc.y
        local pointKey = PointKey(loc)
        local point = place.points[pointKey]
        if not point then
            point = { x = loc.x, y = loc.y, count = 0, first = now }
            place.points[pointKey] = point
        end
        point.count, point.last = point.count + 1, now
    end
end

function ML.LocationPoints(mob)
    local points = {}
    for _, place in pairs(mob.places) do
        EnsurePoints(place)
        local hasPoint = false
        for key, point in pairs(place.points) do
            hasPoint = true
            points[#points + 1] = { map = place.map, zone = place.zone, sub = place.sub,
                x = point.x, y = point.y, count = point.count, last = point.last,
                historical = point.historical, key = tostring(place.map) .. ":" .. key }
        end
        if not hasPoint then
            points[#points + 1] = { map = place.map, zone = place.zone, sub = place.sub,
                count = place.count, last = place.last, key = tostring(place.map) .. ":unknown" }
        end
    end
    table.sort(points, function(a, b)
        if (a.last or 0) == (b.last or 0) then return a.key < b.key end
        return (a.last or 0) > (b.last or 0)
    end)
    return points
end
