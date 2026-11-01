-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local labels={recent="Recent",kills="Most kills",dropped="Most dropped",az="Alphabetical A-Z",za="Alphabetical Z-A"}
local menus,buttons={},{}

function ML.GetSortMode(scope)
    local mode=ML.db.sortModes and ML.db.sortModes[scope]
    return labels[mode] and mode or "recent"
end

function ML.SortBefore(a,b,mode)
    if mode=="recent" then
        local at,bt=a.last or 0,b.last or 0
        if at~=bt then return at>bt end
        local ao,bo=a.lastOrder or 0,b.lastOrder or 0
        if ao~=bo then return ao>bo end
    elseif mode=="kills" then
        local ac,bc=a.count or a.kills or 0,b.count or b.kills or 0
        if ac~=bc then return ac>bc end
    elseif mode=="dropped" then
        local aq,bq=a.quantity or 0,b.quantity or 0
        if aq~=bq then return aq>bq end
    end
    local an,bn=a.sortName or string.lower(a.name or ""),b.sortName or string.lower(b.name or "")
    if an~=bn then if mode=="za" then return an>bn end; return an<bn end
    if type(a.id)=="number" and type(b.id)=="number" then return a.id<b.id end
    return tostring(a.id or "")<tostring(b.id or "")
end

function ML.SortMobBefore(a,b,mode)
    if mode=="recent" then return ML.RecentBefore(a,b) end
    return ML.SortBefore(a,b,mode)
end

function ML.BuildSortDropdown(parent,ui,scope,kind,x,y,width,changed)
    local keys=kind=="items" and {"recent","dropped","az","za"} or
        (kind=="mixed" and {"recent","kills","dropped","az","za"} or {"recent","kills","az","za"})
    local menu,button
    button=ui.Button(parent,"",width,function()
        local show=not menu:IsShown()
        for _,other in ipairs(menus) do other:Hide() end
        menu:SetShown(show)
    end)
    button:SetPoint("TOPLEFT",x,y)
    menu=ui.Panel(parent); menu:SetSize(math.max(190,width),#keys*26+14)
    menu:SetPoint("TOPRIGHT",button,"BOTTOMRIGHT",0,-2); menu:SetFrameLevel(parent:GetFrameLevel()+90)
    menus[#menus+1]=menu
    for i,key in ipairs(keys) do
        local mode=key
        local option=ui.Button(menu,labels[mode],menu:GetWidth()-18,function()
            ML.db.sortModes=ML.db.sortModes or {}; ML.db.sortModes[scope]=mode
            button:UpdateLabel(); menu:Hide(); changed(mode)
        end)
        option:SetPoint("TOPLEFT",9,-7-(i-1)*26); option:SetHeight(25)
    end
    function button:UpdateLabel() self:SetText((self.prefix or "")..labels[ML.GetSortMode(scope)].."  v") end
    function button:CloseMenu() menu:Hide() end
    button:HookScript("OnHide",function() menu:Hide() end)
    buttons[#buttons+1]=button
    button:UpdateLabel(); menu:Hide()
    return button
end

function ML.UpdateSortLabels()
    for _,button in ipairs(buttons) do button:UpdateLabel() end
end
