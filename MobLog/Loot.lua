-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

function ML.DropRate(mob, item)
    if not mob.count or mob.count <= 0 then return 0 end
    return (item.corpses or 0) / mob.count * 100
end

function ML.CaptureLoot(count)
    count = count or ML.Public(GetNumLootItems())
    local capture = { slots = {} }
    if type(count) ~= "number" then return capture end
    for slot = 1, count do
        local sources = { GetLootSourceInfo(slot) }
        local link = ML.Public(GetLootSlotLink(slot))
        local icon, name, _, _, quality = GetLootSlotInfo(slot)
        local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
        capture.slots[#capture.slots + 1] = { id = id, link = link,
            icon = ML.Public(icon), name = ML.Public(name), quality = ML.Public(quality), sources = sources }
    end
    return capture
end

-- Consume a frozen snapshot; don't re-read sources after rendering the UI.
function ML.ReadItemLoot(capture, deferRefresh)
    if type(capture) == "number" then capture = ML.CaptureLoot(capture) end
    local snapshot = {}
    for _, slot in ipairs(capture.slots) do
        local link, itemID = slot.link, slot.id
        if itemID then
            local icon, name = slot.icon, slot.name
            local sources = slot.sources
            for i = 1, #sources, 2 do
                local guid, quantity = ML.Public(sources[i]), ML.Public(sources[i + 1])
                if ML.CreatureID(guid) and type(quantity) == "number" and quantity > 0 then
                    snapshot[guid] = snapshot[guid] or {}
                    local item = snapshot[guid][itemID]
                    if not item then
                        item = { quantity = 0, link = link, name = name, icon = icon, quality = slot.quality }
                        snapshot[guid][itemID] = item
                    end
                    item.quantity = item.quantity + quantity
                end
            end
        end
    end
    local changed = false
    for guid, items in pairs(snapshot) do
        local mob = ML.db.mobs[ML.CreatureID(guid)]
        if mob then
            mob.items = mob.items or {}
            local seen = ML.db.lootSeen[guid]
            if not seen then
                seen = { time = time(), items = {} }
                ML.db.lootSeen[guid] = seen
            end
            for id, item in pairs(items) do
                local before = seen.items[id] or 0
                local delta = item.quantity - before
                if mob.items[id] and type(item.quality) == "number" then
                    mob.items[id].quality = item.quality
                end
                if delta > 0 then
                    local entry = mob.items[id]
                    if not entry then
                        entry = { id = id, quantity = 0, corpses = 0 }
                        mob.items[id] = entry
                    end
                    entry.quantity = entry.quantity + delta
                    if ML.SessionLoot then ML.SessionLoot(id, item, delta) end
                    if before == 0 then entry.corpses = entry.corpses + 1 end
                    entry.link, entry.name, entry.icon = item.link, item.name, item.icon
                    if type(item.quality) == "number" then entry.quality = item.quality end
                    entry.last = time()
                    ML.db.itemActivityOrder=(ML.db.itemActivityOrder or 0)+1
                    entry.lastOrder=ML.db.itemActivityOrder
                    seen.items[id] = item.quantity
                    changed = true
                end
            end
        end
    end
    if changed and ML.InvalidateItemCatalog then ML.InvalidateItemCatalog() end
    if changed and not deferRefresh and ML.Refresh then ML.QueueRefresh() end
end
