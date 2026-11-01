-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local registered

function ML.AddNPCTooltip(tooltip, data)
    if tooltip ~= GameTooltip or not ML.db or ML.db.options.npcTooltip == false then return end
    local guid = data and ML.Public(data.guid)
    if not guid and tooltip.GetUnit then
        local _, unit = tooltip:GetUnit()
        unit = ML.Public(unit)
        if type(unit) == "string" then guid = ML.Public(UnitGUID(unit)) end
    end
    local id = ML.CreatureID(guid)
    if not id or not ML.db.mobs[id] or tooltip.mobLogNPC == id then return end
    -- Reuse a valid UI group, or build only this NPC's same-name candidates.
    -- A tooltip never rebuilds all location histories or requests a model.
    if not ML.tooltipGroups then ML.tooltipGroups={} end
    if not ML.tooltipGroups[id] then
        local group=ML.GroupForMob(id)
        if group then for _,member in ipairs(group.members) do ML.tooltipGroups[member.id]=group end end
    end
    local mob = ML.tooltipGroups[id] or ML.db.mobs[id]
    tooltip.mobLogNPC = id
    tooltip:AddLine(" ")
    tooltip:AddLine("MobLog", 0.35, 0.84, 0.74)
    tooltip:AddLine(string.format("%d recorded kills · %d sightings", mob.count or 0, mob.sightings or 0), 0.85, 0.82, 0.74)
    tooltip:AddLine(ML.CollectionProgress(mob), 0.85, 0.82, 0.74, true)
    if ML.IsHuntTarget(mob) then tooltip:AddLine("Hunt target", 1, 0.82, 0.4) end
    if mob.members and #mob.members > 1 then tooltip:AddLine("Totals for this grouped bestiary entry", 0.65, 0.62, 0.55) end
end

function ML.RegisterNPCTooltip()
    if registered or not TooltipDataProcessor or not TooltipDataProcessor.AddTooltipPostCall or not Enum or not Enum.TooltipDataType then return end
    registered = true
    GameTooltip:HookScript("OnTooltipCleared", function(self) self.mobLogNPC = nil end)
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, ML.AddNPCTooltip)
end
