-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

-- Ranks are derived from account-wide group totals; original NPC records stay intact.
ML.KillRanks = {
    { key = "bronze", label = "Bronze", kills = 50, color = {0.80, 0.46, 0.24}, hex = "ffcc753d", badge = "I" },
    { key = "silver", label = "Silver", kills = 250, color = {0.76, 0.82, 0.90}, hex = "ffc2d1e6", badge = "II" },
    { key = "gold", label = "Gold", kills = 1000, color = {1, 0.77, 0.24}, hex = "ffffc43d", badge = "III" },
    { key = "master", label = "Master", kills = 5000, color = {0.83, 0.64, 0.31}, hex = "ffd4a34f", badge = "IV" },
}

function ML.KillRank(count)
    local rank, nextRank
    for _, entry in ipairs(ML.KillRanks) do
        if (count or 0) >= entry.kills then rank = entry
        else nextRank = entry; break end
    end
    return rank, nextRank
end

function ML.CollectionProgress(mob)
    local rank, nextRank = ML.KillRank(mob.count)
    local text = rank and ("|c" .. rank.hex .. rank.label .. "|r") or "Unranked"
    if nextRank then
        return text .. string.format(" · %d / %d kills to %s", mob.count, nextRank.kills, nextRank.label),
            math.min(1, mob.count / nextRank.kills), rank, nextRank
    end
    return text .. " · " .. mob.count .. " kills · Maximum rank", 1, rank
end

function ML.CollectionAchievementDate(mob, rank)
    local achievements = ML.db.collectionAchievements or {}
    local earliest
    for _, member in ipairs(mob.members or {mob}) do
        local earned = achievements[member.id]
        local stamp = type(earned) == "table" and earned[rank.key]
        if type(stamp) == "number" and stamp > 0 and (not earliest or stamp < earliest) then
            earliest = stamp
        end
    end
    return earliest
end

function ML.CollectionAchievementLines(mob)
    local lines = {}
    for _, rank in ipairs(ML.KillRanks) do
        if (mob.count or 0) < rank.kills then break end
        local stamp = ML.CollectionAchievementDate(mob, rank)
        lines[#lines + 1] = "|c" .. rank.hex .. rank.label .. "|r · " ..
            (stamp and ("Achieved: " .. date("%Y-%m-%d", stamp)) or "Achievement date not recorded")
    end
    return lines
end

local function RecordAchievement(group, rank, stamp)
    ML.db.collectionAchievements = ML.db.collectionAchievements or {}
    -- Keep real NPC IDs so switching variants or regrouping preserves earned dates.
    local first = ML.CollectionAchievementDate(group, rank) or stamp
    for _, member in ipairs(group.members) do
        local earned = ML.db.collectionAchievements[member.id] or {}
        ML.db.collectionAchievements[member.id] = earned
        earned[rank.key] = first
    end
end

function ML.IsHuntTarget(mob)
    local targets = ML.db.huntTargets or {}
    for _, member in ipairs(mob.members or {mob}) do
        if targets[member.id] then return true end
    end
    return false
end

function ML.ToggleHuntTarget(mob)
    ML.db.huntTargets = ML.db.huntTargets or {}
    local enabled = not ML.IsHuntTarget(mob)
    -- Store real IDs so regrouping or discovering another appearance preserves the pin.
    for _, member in ipairs(mob.members or {mob}) do
        ML.db.huntTargets[member.id] = enabled and true or nil
    end
    ML.db.closedGroups = ML.db.closedGroups or {}
    if enabled then ML.db.closedGroups.hunts = false end
    if ML.Refresh then ML.Refresh() end
end

function ML.MatchesCollection(mob, key)
    if key == "all" then return true end
    if key == "hunts" then return ML.IsHuntTarget(mob) end
    local rank = ML.KillRank(mob.count)
    return (rank and rank.key or "unranked") == key
end

-- Batch kills from one loot window. Only new recorded kills trigger a celebration;
-- historical records and changes to grouping never trigger retroactive notifications.
local pending, scheduled = {}, false
function ML.CheckCollectionUnlocks(groups)
    if not next(pending) then return end
    local increments = pending
    pending = {}
    for _, group in ipairs(groups) do
        local added = 0
        for _, member in ipairs(group.members) do added = added + (increments[member.id] or 0) end
        if added > 0 then
            local stamp = 0
            for _, member in ipairs(group.members) do
                if increments[member.id] then stamp = math.max(stamp, member.lastKilled or 0) end
            end
            if stamp == 0 then stamp = time() end
            for _, rank in ipairs(ML.KillRanks) do
                if group.count - added < rank.kills and group.count >= rank.kills then
                    RecordAchievement(group, rank, stamp)
                end
            end
            local before = ML.KillRank(group.count - added)
            local after = ML.KillRank(group.count)
            if after and before ~= after then
                if ML.SessionRank then ML.SessionRank(group, after) end
                if ML.ShowRankUnlock then ML.ShowRankUnlock(group, after) end
            end
        end
    end
end

function ML.CollectionKill(id)
    if ML.InvalidateMobGroups then ML.InvalidateMobGroups() end
    pending[id] = (pending[id] or 0) + 1
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.15, function()
        scheduled = false
        -- Group only the names affected by this batch; never copy the complete
        -- collection and its location history just to check a kill milestone.
        if next(pending) then ML.CheckCollectionUnlocks(ML.BuildMobGroups(pending)) end
    end)
end
