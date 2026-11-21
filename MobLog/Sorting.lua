-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local labels={recent="Recent",kills="Most kills",dropped="Most dropped",az="Alphabetical A-Z",za="Alphabetical Z-A"}
local buttons={}

function ML.CreateDropdown(parent, width, choices, current, select, label)
    local button = CreateFrame("DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
    button:SetWidth(width)
    button:SetupMenu(function(_, root)
        local entries = type(choices) == "function" and choices() or choices
        for _, entry in ipairs(entries) do
            root:CreateRadio(label and label(entry) or entry.label, function(key) return current() == key end, select, entry.key)
        end
        if #entries > 12 then root:SetScrollMode(285) end
    end)
    return button
end

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
    local choices={}
    for i,key in ipairs(keys) do choices[i]={key=key,label=labels[key]} end
    local button
    button=ML.CreateDropdown(parent,width,choices,function() return ML.GetSortMode(scope) end,function(mode)
        ML.db.sortModes=ML.db.sortModes or {}; ML.db.sortModes[scope]=mode
        button:UpdateLabel()
        changed(mode)
    end)
    button:SetPoint("TOPLEFT",x,y)
    function button:UpdateLabel() self:OverrideText((self.prefix or "")..labels[ML.GetSortMode(scope)]) end
    buttons[#buttons+1]=button
    button:UpdateLabel()
    return button
end

function ML.UpdateSortLabels()
    for _,button in ipairs(buttons) do button:UpdateLabel() end
end
