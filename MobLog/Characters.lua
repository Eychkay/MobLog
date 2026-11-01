-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

function ML.UpdateCharacter()
    local guid = ML.Public(UnitGUID("player"))
    local name, realm = UnitFullName("player")
    local _, class = UnitClass("player")
    name, realm, class = ML.Public(name), ML.Public(realm), ML.Public(class)
    if type(guid) ~= "string" or type(name) ~= "string" then return end
    if type(realm) ~= "string" or realm == "" then realm = GetRealmName() end
    local character = ML.db.characters[guid] or {}
    character.name, character.realm, character.class = name, realm, class
    ML.db.characters[guid] = character
    return guid
end

function ML.CharacterName(guid)
    local character = ML.db.characters[guid]
    if not character then return "|cff9099a5Unknown|r" end
    local color
    if character.class then
        color = C_ClassColor and C_ClassColor.GetClassColor(character.class)
        color = color or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[character.class])
    end
    local hex = color and string.format("ff%02x%02x%02x", math.floor(color.r * 255 + 0.5), math.floor(color.g * 255 + 0.5), math.floor(color.b * 255 + 0.5)) or "ff9099a5"
    local label = character.name
    if character.realm and character.realm ~= "" then label = label .. "-" .. character.realm end
    return "|c" .. hex .. label .. "|r"
end

function ML.RecordCharacter(mob, source, now)
    local guid = ML.UpdateCharacter()
    if not guid then return end
    mob.characters = mob.characters or {}
    local stats = mob.characters[guid]
    if not stats then
        stats = { count = 0, loot = 0, manual = 0, first = now }
        mob.characters[guid] = stats
    end
    stats.count = stats.count + 1
    stats[source] = (stats[source] or 0) + 1
    stats.last = now
end

function ML.CharacterBreakdown(mob)
    local entries, known = {}, 0
    for guid, stats in pairs(mob.characters or {}) do
        entries[#entries + 1] = { guid = guid, stats = stats }
        known = known + stats.count
    end
    table.sort(entries, function(a, b)
        if a.stats.count == b.stats.count then return a.guid < b.guid end
        return a.stats.count > b.stats.count
    end)
    return entries, math.max(0, mob.count - known)
end
