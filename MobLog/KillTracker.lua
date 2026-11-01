-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local candidates, plates = {}, {}
local bindings = {}
local recordedDeaths = 0
local ScheduleDeathScan
local scanScheduled = false
local function SupportedUnit(unit)
    return unit == "target" or unit == "mouseover" or unit == "focus"
        or unit:match("^nameplate%d+$") or unit:match("^boss%d+$")
end

-- Threat-table membership shows participation, not a personal killing blow.
local function Participated(unit)
    local player = ML.Public(UnitThreatSituation("player", unit))
    local pet = ML.Public(UnitThreatSituation("pet", unit))
    return (type(player) == "number" and player >= 0)
        or (type(pet) == "number" and pet >= 0)
end

local function NotDenied(unit, fn)
    local raw = fn(unit)
    if issecretvalue and issecretvalue(raw) then return false end
    return raw ~= true
end

function ML.TrackUnit(unit, deferRefresh, watchForCombat)
    if ML.InstanceLootOnly() then return end
    unit = ML.Public(unit)
    if type(unit) ~= "string" or not SupportedUnit(unit) then return end
    if ML.Public(UnitPlayerControlled(unit)) ~= false then return end
    local rawGUID = UnitGUID(unit)
    local guid = ML.Public(rawGUID)
    if not ML.CreatureID(guid) then
        -- A previously public identity remains bound only for this token's lifetime.
        if issecretvalue and issecretvalue(rawGUID) and bindings[unit] and not unit:match("^boss%d+$") then
            guid = bindings[unit].guid
        else
            bindings[unit] = nil; return
        end
    else
        if not bindings[unit] or bindings[unit].guid ~= guid then bindings[unit] = {guid = guid} end
    end
    if ML.db.seen[guid] then candidates[guid] = nil; ML.Observe(unit, deferRefresh, false); return end
    local candidate = candidates[guid]
    local attackable = ML.Public(UnitCanAttack("player", unit))
    if not candidate and attackable ~= true then return end
    -- Passive tracking caches metadata without adding Seen entries or portrait work.
    local _, observed = ML.Observe(unit, true, false)
    observed = observed or bindings[unit].data
    if observed then bindings[unit].data = observed end
    local dead = ML.Public(UnitIsDead(unit))
    local firstObservation = not candidate
    local now = GetTime()
    -- Death and combat flags can arrive before/after threat events. Positive
    -- readable participation still qualifies even if the NPC combat flag lags.
    if dead == true and candidate and not candidate.engaged and Participated(unit) then
        candidate.engaged, candidate.engagedAt = true, now
    end
    if dead ~= true then
        if attackable ~= true then return end
        candidate = candidate or {}
        candidate.lastSeen = now
        candidate.data = observed or candidate.data
        candidates[guid] = candidate
        if unit == "target" and (firstObservation or watchForCombat) then candidate.watchUntil = now + 5 end
        local inCombat = ML.Public(UnitAffectingCombat(unit))
        local allowed = NotDenied(unit, UnitIsTapDenied)
        if not allowed then
            candidate.engaged, candidate.engagedAt = nil, nil
        elseif Participated(unit) then
            candidate.engaged, candidate.engagedAt = true, now
        elseif inCombat == false and dead == false then
            candidate.engaged, candidate.engagedAt = nil, nil
        end
        if candidate.engaged or (candidate.watchUntil and now < candidate.watchUntil) then ScheduleDeathScan() end
    elseif dead == true and candidate and candidate.engaged and now - (candidate.engagedAt or candidate.lastSeen) <= 120 then
        -- Never infer death from a removed nameplate, zero health or a missing GUID.
        if not NotDenied(unit, UnitIsTapDenied) or not NotDenied(unit, UnitIsFeignDeath) then
            return
        end
        if ML.Record(guid, "observed", candidate.data, deferRefresh) then
            recordedDeaths = recordedDeaths + 1
        end
        candidates[guid] = nil
    end
end

function ML.ScanTrackedUnits(watchForCombat)
    local before = recordedDeaths
    ML.TrackUnit("target", true, watchForCombat); ML.TrackUnit("focus", true)
    for unit in pairs(plates) do ML.TrackUnit(unit, true) end
    for i = 1, 5 do ML.TrackUnit("boss" .. i, true) end
    if ML.Refresh and recordedDeaths ~= before then ML.QueueRefresh() end
end

-- Check engaged units between events as well. Loot is not involved: only a
-- readable, participated-in death can commit a kill. Disappearance never does.
ScheduleDeathScan = function()
    if scanScheduled or not C_Timer or not C_Timer.After then return end
    local engaged, now = false, GetTime()
    for guid, candidate in pairs(candidates) do
        local watching = candidate.watchUntil and now < candidate.watchUntil and bindings.target and bindings.target.guid == guid
        if not ML.db.seen[guid] and (watching or (candidate.engaged and now - (candidate.engagedAt or candidate.lastSeen) <= 120)) then engaged = true; break end
    end
    if not engaged then return end
    scanScheduled = true
    C_Timer.After(0.2, function()
        ML.ScanTrackedUnits()
        scanScheduled = false
        ScheduleDeathScan()
    end)
end

function ML.KillTrackerEvent(event, unit)
    unit = ML.Public(unit)
    if ML.InstanceLootOnly() then candidates, plates, bindings = {}, {}, {}; return end
    if event == "PLAYER_LEAVING_WORLD" then
        candidates, plates, bindings = {}, {}, {}; return
    end
    local token = event == "PLAYER_TARGET_CHANGED" and "target" or
        (event == "PLAYER_FOCUS_CHANGED" and "focus" or (event == "UPDATE_MOUSEOVER_UNIT" and "mouseover" or nil))
    if token then bindings[token] = nil end
    if event == "NAME_PLATE_UNIT_ADDED" then
        if type(unit) == "string" then bindings[unit] = nil end
    end
    if event == "PLAYER_TARGET_CHANGED" then ML.TrackUnit("target", false, true)
    elseif event == "UPDATE_MOUSEOVER_UNIT" then ML.TrackUnit("mouseover")
    elseif event == "PLAYER_FOCUS_CHANGED" then ML.TrackUnit("focus")
    elseif event == "PLAYER_LOGIN" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_REGEN_DISABLED"
        or ((event == "UNIT_THREAT_SITUATION_UPDATE" or event == "UNIT_THREAT_LIST_UPDATE") and (unit == "player" or unit == "pet")) then
        ML.ScanTrackedUnits(event == "PLAYER_REGEN_DISABLED")
    elseif type(unit) == "string" then
        if event == "NAME_PLATE_UNIT_ADDED" then plates[unit] = true end
        -- The token may still be readable at removal; otherwise this does nothing.
        ML.TrackUnit(unit)
        if event == "NAME_PLATE_UNIT_REMOVED" then plates[unit] = nil; bindings[unit] = nil end
    end
    local now = GetTime()
    for guid, candidate in pairs(candidates) do
        if now - candidate.lastSeen > 120 then candidates[guid] = nil end
    end
end
