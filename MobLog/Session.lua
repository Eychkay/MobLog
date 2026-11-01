-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local report, body, scroll, content, totals
local sequence=0
local function Stamp() sequence=sequence+1; return time(),sequence end

function ML.StartSessionReport()
    ML.sessionReport = {started = time(), kills = {}, discoveries = {}, items = {}, ranks = {}, killCount = 0, itemCount = 0,killTimes={},discoveryTimes={}}
end

function ML.SessionDiscovery(id)
    local session = ML.sessionReport
    if session then
        session.discoveries[id] = true
        local stamp,order=Stamp(); session.discoveryTimes[id]={last=stamp,lastOrder=order}
    end
end

function ML.SessionKill(id)
    local session = ML.sessionReport
    if not session then return end
    session.kills[id] = (session.kills[id] or 0) + 1
    session.killCount = session.killCount + 1
    local stamp,order=Stamp(); session.killTimes[id]={last=stamp,lastOrder=order}
end

function ML.SessionLoot(id, item, quantity)
    local session = ML.sessionReport
    if not session then return end
    local entry = session.items[id] or {quantity = 0}
    entry.quantity = entry.quantity + quantity
    entry.last,entry.lastOrder=Stamp()
    entry.link, entry.name = item.link or entry.link, item.name or entry.name
    session.items[id] = entry
    session.itemCount = session.itemCount + quantity
end

function ML.SessionRank(mob, rank)
    local session = ML.sessionReport
    if session then
        local stamp,order=Stamp()
        session.ranks[#session.ranks+1]={id=mob.representativeID or mob.id,name=mob.name,rank=rank,last=stamp,lastOrder=order,count=rank.kills}
    end
end

local function MobName(id)
    local mob = ML.db.mobs[id]
    return mob and mob.name or ("NPC #" .. id)
end

function ML.RefreshSessionReport()
    if not report or not report:IsShown() then return end
    local session = ML.sessionReport
    if not session then return end
    local discovered = 0
    for _ in pairs(session.discoveries) do discovered = discovered + 1 end
    local minutes = math.max(0, math.floor((time() - session.started) / 60))
    totals:SetText(string.format("%d recorded kills  ·  %d new NPC types  ·  %d observed items  ·  %d rank-ups\nStarted %s  ·  %dh %02dm elapsed", session.killCount, discovered,
        session.itemCount, #session.ranks, date("%H:%M", session.started), math.floor(minutes / 60), minutes % 60))
    local mobSort,itemSort=ML.GetSortMode("sessionMobs"),ML.GetSortMode("sessionItems")
    local lines = {"|cffeac273KILLS THIS SESSION|r"}
    local kills = {}
    for id,count in pairs(session.kills) do
        local stamp=session.killTimes[id] or {}
        kills[#kills+1]={id=id,name=MobName(id),count=count,last=stamp.last,lastOrder=stamp.lastOrder}
    end
    table.sort(kills,function(a,b) return ML.SortBefore(a,b,mobSort) end)
    for _, entry in ipairs(kills) do lines[#lines + 1] = MobName(entry.id) .. "  ×" .. entry.count end
    if #kills == 0 then lines[#lines + 1] = "No kill records yet." end
    lines[#lines + 1] = "\n|cffeac273NEW DISCOVERIES|r"
    local discoveries = {}
    for id in pairs(session.discoveries) do
        local stamp=session.discoveryTimes[id] or {}
        discoveries[#discoveries+1]={id=id,name=MobName(id),count=session.kills[id] or 0,last=stamp.last,lastOrder=stamp.lastOrder}
    end
    table.sort(discoveries,function(a,b) return ML.SortBefore(a,b,mobSort) end)
    for _,entry in ipairs(discoveries) do lines[#lines+1]=entry.name.."  \194\183  NPC #"..entry.id end
    if #discoveries == 0 then lines[#lines + 1] = "No new NPC types recorded yet." end
    lines[#lines + 1] = "\n|cffeac273OBSERVED LOOT|r"
    local items = {}
    for id,item in pairs(session.items) do items[#items+1]={id=id,item=item,name=item.name or ("Item #"..id),quantity=item.quantity,last=item.last,lastOrder=item.lastOrder} end
    table.sort(items,function(a,b) return ML.SortBefore(a,b,itemSort) end)
    for _, entry in ipairs(items) do
        local item = entry.item
        lines[#lines + 1] = (item.link or item.name or ("Item #" .. entry.id)) .. "  ×" .. item.quantity
    end
    if #items == 0 then lines[#lines + 1] = "No item drops observed yet." end
    lines[#lines + 1] = "\n|cffeac273RANKS UNLOCKED|r"
    local ranks={}
    for _,entry in ipairs(session.ranks) do ranks[#ranks+1]=entry end
    table.sort(ranks,function(a,b) return ML.SortBefore(a,b,mobSort) end)
    for _, entry in ipairs(ranks) do lines[#lines + 1] = "|c" .. entry.rank.hex .. entry.rank.label .. "|r  ·  " .. MobName(entry.id) end
    if #session.ranks == 0 then lines[#lines + 1] = "No new ranks unlocked yet." end
    body:SetText(table.concat(lines, "\n"))
    content:SetHeight(math.max(1, body:GetStringHeight() + 20))
end

function ML.BuildSessionReport(parent, ui)
    report = CreateFrame("Frame", nil, parent); report:SetAllPoints()
    local title = ui.Text(report, 18, {0.92, 0.76, 0.45})
    title:SetPoint("TOPLEFT", 28, -131); title:SetText("Your session")
    local function RefreshSort() scroll:SetVerticalScroll(0); ML.RefreshSessionReport() end
    local mobs=ML.BuildSortDropdown(report,ui,"sessionMobs","mobs",430,-128,202,RefreshSort)
    mobs.prefix="Mobs: "; mobs:UpdateLabel()
    local items=ML.BuildSortDropdown(report,ui,"sessionItems","items",648,-128,202,RefreshSort)
    items.prefix="Items: "; items:UpdateLabel()
    totals = ui.Text(report, 13); totals:SetPoint("TOPLEFT", 28, -163); totals:SetSize(830, 44)
    local panel = ui.Panel(report); panel:SetPoint("TOPLEFT", 26, -216); panel:SetSize(846, 352)
    scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 14, -14); scroll:SetSize(800, 322)
    content = CreateFrame("Frame", nil, scroll); content:SetSize(796, 1); scroll:SetScrollChild(content)
    body = ui.Text(content, 13); body:SetPoint("TOPLEFT"); body:SetWidth(784)
    ML.BuildFooterNote(report,ui.Text,"This session starts at login or UI reload.\nLoot totals are observed quantities. Hover for details.",
        "This report starts at login or UI reload. New discoveries count original NPC IDs.\nLoot totals are observed item quantities, not confirmed bag receipts. Instances remain loot-based only.")
    report:SetScript("OnShow", ML.RefreshSessionReport)
    report:Hide()
    return report
end

function ML.GetSessionView()
    return {scroll=scroll:GetVerticalScroll(),mobSort=ML.GetSortMode("sessionMobs"),itemSort=ML.GetSortMode("sessionItems")}
end
function ML.RestoreSessionView(state)
    ML.db.sortModes=ML.db.sortModes or {}; ML.db.sortModes.sessionMobs=state.mobSort; ML.db.sortModes.sessionItems=state.itemSort
    ML.RefreshSessionReport(); ML.SetViewScroll(scroll,state.scroll)
end
