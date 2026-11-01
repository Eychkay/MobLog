-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local wishlistSources,wishlistData

function ML.BuildFooterNote(parent,Text,summary,details)
    local frame=CreateFrame("Frame",nil,parent)
    frame:SetPoint("BOTTOMLEFT",26,10); frame:SetSize(540,28); frame:EnableMouse(true)
    local label=Text(frame,10,{0.72,0.65,0.52}); label:SetAllPoints(); label:SetJustifyV("MIDDLE"); label:SetText(summary)
    frame:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine("Tracking details",0.92,0.76,0.45)
        GameTooltip:AddLine(details,0.85,0.82,0.74,true); GameTooltip:Show()
    end)
    frame:SetScript("OnLeave",function() GameTooltip:Hide() end)
    return frame
end

function ML.CopyViewTable(source)
    local copy={}
    for key,value in pairs(source or {}) do copy[key]=value end
    return copy
end

function ML.IsWishlisted(id)
    return ML.db.itemWishlist and ML.db.itemWishlist[id]==true
end

function ML.ToggleItemWishlist(id)
    ML.db.itemWishlist=ML.db.itemWishlist or {}
    ML.db.itemWishlist[id]=not ML.IsWishlisted(id) or nil
    wishlistSources=nil
    if ML.InvalidateItemCatalog then ML.InvalidateItemCatalog() end
    if ML.Refresh then ML.Refresh() elseif ML.RefreshItems then ML.RefreshItems() end
    if ML.RefreshMobLootRows then ML.RefreshMobLootRows() end
end

function ML.CurrentAreaFilter()
    local map=C_Map and C_Map.GetBestMapForUnit and ML.Public(C_Map.GetBestMapForUnit("player"))
    local zone=ML.Public(GetRealZoneText())
    if type(zone)~="string" or zone=="" then return nil end
    local region,regionName=ML.MapRegion(map)
    local world=ML.RegionWorld(region,regionName)
    return {world=world,region=region,area=zone}
end

function ML.SetViewScroll(scroll,value)
    local child=scroll:GetScrollChild()
    scroll:SetVerticalScroll(math.max(0,math.min(value or 0,math.max(0,child:GetHeight()-scroll:GetHeight()))))
end

function ML.MobHasWishlistDrops(mob)
    if not next(ML.db.itemWishlist or {}) then return false end
    local ready=ML.TrinityData and ML.TrinityData.ready
    if ready and (not wishlistSources or wishlistData~=ML.TrinityData) then
        wishlistSources,wishlistData={},ML.TrinityData
        for id in pairs(ML.db.itemWishlist) do
            for _,npc in ipairs(ML.PossibleItemSources(id,true)) do wishlistSources[npc]=true end
        end
    end
    for _,member in ipairs(mob.members or {mob}) do
        if ready and wishlistSources[member.id] then return true end
        for id,drop in pairs(member.items or {}) do if ML.IsWishlisted(id) and (drop.quantity or 0)>0 then return true end end
    end
    return false
end

-- Background observations/metadata may arrive in bursts. Keep recording immediate,
-- but perform one visible UI rebuild per burst, not one per response.
local refreshQueued=false
function ML.QueueRefresh()
    if ML.InvalidateMobGroups then ML.InvalidateMobGroups() else ML.tooltipGroups=nil end
    if refreshQueued then return end
    refreshQueued=true
    C_Timer.After(1,function()
        refreshQueued=false
        if ML.IsMobLogVisible and ML.IsMobLogVisible() then
            if ML.Refresh then ML.Refresh(true) end
        elseif ML.QueueHuntTrackerRefresh then ML.QueueHuntTrackerRefresh() end
    end)
end
