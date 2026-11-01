-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local queue, attempted, unitRequests, discovered = {}, {}, {}, {}
local requestedPortraits = {}
local worker, active, sequence = nil, nil, 0
local StartNext

function ML.SavePortraitDisplay(mob, displayID)
    displayID = ML.Public(displayID)
    if type(displayID) ~= "number" or displayID <= 0 then return end
    mob.displayIDs = mob.displayIDs or {}
    if mob.displayID then mob.displayIDs[mob.displayID] = true end
    local changed = not mob.displayIDs[displayID]
    mob.displayIDs[displayID] = true
    mob.displayID = mob.displayID or displayID
    return changed
end

function ML.AppearanceChoices(mob)
    local choices, ids = {}, {}
    for id in pairs(mob.displayIDs or {}) do ids[id] = true end
    if mob.displayID then ids[mob.displayID] = true end
    if not next(ids) and mob.catalogDisplayID then ids[mob.catalogDisplayID] = true end
    for id in pairs(ids) do choices[#choices + 1] = id end
    table.sort(choices)
    return choices
end

function ML.SelectedDisplay(mob)
    return mob.selectedDisplayID or mob.displayID or mob.catalogDisplayID
end

function ML.ModelChoices(mob)
    local entries = {}
    for _, member in ipairs(mob.members or { mob }) do
        local displays = ML.AppearanceChoices(member)
        if #displays == 0 then
            entries[#entries + 1] = { mob = member }
        else
            for _, display in ipairs(displays) do entries[#entries + 1] = { mob = member, display = display } end
        end
    end
    return entries
end

function ML.CycleAppearance(mob, direction)
    local choices = ML.AppearanceChoices(mob)
    if #choices < 2 then return false end
    local index = 1
    for i, id in ipairs(choices) do if id == ML.SelectedDisplay(mob) then index = i; break end end
    mob.selectedDisplayID = choices[(index - 1 + direction) % #choices + 1]
    return true
end

function ML.ApplyDiscoveredAppearances(mob)
    for id in pairs(discovered[mob.id] or {}) do ML.SavePortraitDisplay(mob, id) end
end

local function Finish(token, displayID)
    if not active or token ~= sequence then return end
    local request = active
    if not request.unit then requestedPortraits[request.id] = nil end
    if request.unit and ML.Public(UnitGUID(request.unit)) ~= request.guid then displayID = nil end
    displayID = ML.Public(displayID)
    local changed
    if type(displayID) == "number" and displayID > 0 then
        discovered[request.id] = discovered[request.id] or {}
        discovered[request.id][displayID] = true
        local mob = ML.db.mobs[request.id]
        changed = mob and ML.SavePortraitDisplay(mob, displayID)
    end
    active = nil
    if worker then
        worker:SetScript("OnModelLoaded",nil)
        worker:ClearModel()
        worker:Hide()
    end
    if changed then C_Timer.After(0, function() if ML.Refresh then ML.QueueRefresh() end end) end
    C_Timer.After(0, StartNext)
end

StartNext = function()
    if active or #queue == 0 then return end
    local request, skipped = nil, 0
    repeat
        request = table.remove(queue, 1)
        if request and not request.unit then request.portrait = requestedPortraits[request.id] or request.portrait end
        if request and request.unit and ML.Public(UnitGUID(request.unit)) ~= request.guid then
            request = nil
        elseif request and request.portrait and
            (request.portrait.mobID ~= request.id or not request.portrait:IsVisible()) then
            -- A recycled/hidden row no longer needs this queued model. Permit a
            -- fresh request when the NPC becomes visible again.
            attempted[request.id] = nil
            requestedPortraits[request.id] = nil
            request = nil
        end
        if not request then
            skipped = skipped + 1
            if skipped >= 20 and #queue > 0 then C_Timer.After(0, StartNext); return end
        end
    until request or #queue == 0
    if not request then return end
    if not worker then
        -- Keep the loader shown off-screen so model streaming can complete.
        worker = CreateFrame("PlayerModel", nil, UIParent)
        worker:SetSize(32, 32); worker:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", -1000, -1000)
        worker:EnableMouse(false)
    end
    worker:ClearModel()
    worker:Show()
    active = request; sequence = sequence + 1
    local token = sequence
    worker:SetScript("OnModelLoaded", function(self) Finish(token, self:GetDisplayInfo()) end)
    local ok, result
    if request.unit then ok, result = pcall(worker.SetUnit, worker, request.unit)
    else ok = pcall(worker.SetCreature, worker, request.id) end
    if not ok or result == false then Finish(token); return end
    C_Timer.After(3, function() Finish(token) end)
end

local function Request(mob, portrait)
    if ML.catalogLoadScheduled or (ML.TrinityData and ML.TrinityData.queued) then return end
    if mob.provisional or mob.catalogOnly then return end
    requestedPortraits[mob.id] = portrait
    if attempted[mob.id] then return end
    attempted[mob.id] = true
    queue[#queue + 1] = { id = mob.id, portrait = portrait }
    -- Let the row finish becoming visible before checking its request.
    C_Timer.After(0, StartNext)
end

function ML.RequestUnitPortrait(unit, guid, id, force)
    local now = GetTime()
    if unitRequests[guid] and (not force or now - unitRequests[guid] < 0.2) then return end
    unitRequests[guid] = now
    for key, stamp in pairs(unitRequests) do if now - stamp > 600 then unitRequests[key] = nil end end
    table.insert(queue, 1, { unit = unit, guid = guid, id = id })
    StartNext()
end

function ML.PortraitAtlas(mob)
    if mob.boss or mob.classification == "worldboss" then
        return "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold-Winged", true
    elseif mob.classification == "rareelite" then
        return "ui-hud-unitframe-target-portraiton-boss-rare-silver", false
    elseif mob.classification == "elite" then
        return "UI-HUD-UnitFrame-Target-PortraitOn-Boss-Gold", false
    end
end

function ML.CreateMobPortrait(parent, size)
    local portrait = CreateFrame("Frame", nil, parent)
    portrait:SetSize(size, size)
    portrait.icon = portrait:CreateTexture(nil, "ARTWORK"); portrait.icon:SetAllPoints()
    portrait.mask = portrait:CreateMaskTexture()
    portrait.mask:SetAtlas("CircleMask"); portrait.mask:SetAllPoints(portrait.icon)
    portrait.icon:AddMaskTexture(portrait.mask)
    -- The minimap border has an off-centre ring and must not frame portraits.
    -- Concentric masked disks keep both the image and rim on the same centre.
    portrait.ring = portrait:CreateTexture(nil, "BACKGROUND")
    portrait.ring:SetColorTexture(1, 1, 1, 1)
    portrait.ring:SetSize(size + 4, size + 4); portrait.ring:SetPoint("CENTER", portrait, "CENTER")
    portrait.ringMask = portrait:CreateMaskTexture()
    portrait.ringMask:SetAtlas("CircleMask"); portrait.ringMask:SetAllPoints(portrait.ring)
    portrait.ring:AddMaskTexture(portrait.ringMask)
    portrait.backing = portrait:CreateTexture(nil, "BORDER")
    portrait.backing:SetColorTexture(0.02, 0.018, 0.015, 1); portrait.backing:SetAllPoints(portrait.icon)
    portrait.backing:AddMaskTexture(portrait.mask)
    portrait.dragon = portrait:CreateTexture(nil, "OVERLAY", nil, 1)
    portrait.star = portrait:CreateTexture(nil, "OVERLAY", nil, 2)
    portrait.star:SetAtlas("UnitFrame-Target-PortraitOn-Boss-Rare-Star")
    portrait.star:SetSize(12, 12); portrait.star:SetPoint("BOTTOMLEFT", -3, -3)
    return portrait
end

function ML.UpdateMobPortrait(portrait, mob)
    local displayID = ML.SelectedDisplay(mob)
    if portrait.mobID ~= mob.id or portrait.displayID ~= displayID then
        portrait.mobID, portrait.displayID = mob.id, displayID
        portrait.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
        if displayID and SetPortraitTextureFromCreatureDisplayID then
            pcall(SetPortraitTextureFromCreatureDisplayID, portrait.icon, displayID)
        end
    end
    if not displayID then Request(mob, portrait) end
    local rare = mob.classification == "rare" or mob.classification == "rareelite"
    portrait.star:SetShown(rare)
    portrait.ring:SetVertexColor(rare and 0.72 or 0.82, rare and 0.75 or 0.66, rare and 0.8 or 0.37)
    local atlas, winged = ML.PortraitAtlas(mob)
    local info = atlas and C_Texture and C_Texture.GetAtlasInfo(atlas)
    portrait.dragon:SetShown(info ~= nil and info ~= false)
    if info then
        local scale = portrait:GetWidth() / 58
        portrait.dragon:SetAtlas(atlas)
        portrait.dragon:SetSize(info.width * scale, info.height * scale)
        portrait.dragon:ClearAllPoints()
        portrait.dragon:SetPoint("TOPRIGHT", portrait, "TOPRIGHT", (winged and 34 or 15) * scale, 11 * scale)
    end
end
