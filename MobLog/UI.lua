-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local window, search, detail, model, modelHint, list, content
local rows, selected = {}, nil
local renderEntries, renderingRows = {}, false
local catalogViewport
local catalogPage,catalogPageKey=1,nil
local catalogPageSize=200
local catalogArea, catalogAreaButton, catalogAreaMenu = "all", nil, nil
local sortButton
local mobLoot,locationBrowser,backButton,resetFiltersButton,currentAreaButton
local history,restoringView={},false
local gold = { 0.92, 0.76, 0.45 }
local stats = {}
local defaultDistance = 1.8
local activeTab = "info"
local lootRows, tabs, locationRows = {}, {}, {}
local detailScroll
local mobPage, itemPage, sessionPage, areaPage, pageTabs = nil, nil, nil, nil, {}
local currentPage = "mobs"
local rowHeight = 74
local typeFilter, filterButton, filterMenu, filterCount = "all", nil, nil, nil
local appearanceText, appearanceCounter, previousAppearance, nextAppearance
local groupRows, closedGroups = {}, {}
local attitudeButton, attitudeMenu, bulkHostile
local mobGroups, nameGroupButton = {}, nil
local collectionFilter, collectionButton, collectionMenu, collectionSummary = "all", nil, nil, nil
local collectionChoices = {
    {key = "all", label = "All ranks"}, {key = "hunts", label = "Hunt targets"},
    {key = "unranked", label = "Unranked"},
}
for _, rank in ipairs(ML.KillRanks) do
    collectionChoices[#collectionChoices + 1] = {key = rank.key, label = "|c" .. rank.hex .. rank.label .. "|r"}
end
function ML.SetCollectionFilter(key)
    local label
    for _, choice in ipairs(collectionChoices) do if choice.key == key then label = choice.label; break end end
    if not label then return end
    collectionFilter = key
    if collectionButton then collectionButton:SetText(label .. "  v") end
    if collectionMenu then collectionMenu:Hide() end
    if list then list:SetVerticalScroll(0) end
    if window then ML.Refresh() end
end
function ML.SetMobTypeFilter(key)
    for _, entry in ipairs(ML.MobTypeFilters) do
        if entry.key == key then
            typeFilter = key
            if filterButton then filterButton:SetText(entry.label .. "  v") end
            if filterMenu then filterMenu:Hide() end
            if list then list:SetVerticalScroll(0) end
            if window then ML.Refresh() end
            return
        end
    end
end
local function ApplyCamera()
    model:SetPortraitZoom(0)
    model:SetCamDistanceScale(model.distance or defaultDistance)
    model:SetPosition(0, model.panX or 0, model.panY or 0)
end
local function ModelRequestActive(request)
    return model.request==request and selected==request.id and model:IsVisible()
end
local function LoadModel(mob,reset)
    local request={id=mob.id,display=ML.SelectedDisplay(mob)}
    model.request=request
    if reset then
        model.distance=defaultDistance
        model.panX,model.panY,model.dragButton=0,0,nil
    end
    modelHint:SetText("Loading model …")
    if not model:IsVisible() then return end -- OnShow starts the selected request.
    local function Start()
        if not ModelRequestActive(request) then return end
        model:ClearModel()
        local ok=false
        if not mob.provisional then
            -- A known appearance can stream directly without waiting for the
            -- creature query/cache to finish first.
            if request.display then ok=pcall(model.SetDisplayInfo,model,request.display)
            else ok=pcall(model.SetCreature,model,request.id) end
        end
        if ok then model:SetFacing(0.5)
        else modelHint:SetText(mob.provisional and "Model unavailable until NPC identity is readable" or "Model currently unavailable") end
        return ok
    end
    if not Start() then return end
    -- Bounded retries for a missed load callback/client cache warmup. Every
    -- callback belongs to one selection; hidden or superseded requests stop.
    for _,delay in ipairs({1,3}) do
        C_Timer.After(delay,function()
            if ModelRequestActive(request) and not request.loaded then Start() end
        end)
    end
    C_Timer.After(7,function()
        if ModelRequestActive(request) and not request.loaded then modelHint:SetText("No model loaded · NPC #"..request.id) end
    end)
end
local function Text(parent, size, color)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    fs:SetFont(STANDARD_TEXT_FONT, size, "")
    fs:SetTextColor(unpack(color or { 0.92, 0.87, 0.76 }))
    fs:SetShadowColor(0, 0, 0, 1); fs:SetShadowOffset(1, -1)
    fs:SetJustifyH("LEFT")
    return fs
end
local function Panel(parent)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    -- Dialog artwork has alpha in its pixels even with backdrop alpha at 1.
    f.opaqueBackground = f:CreateTexture(nil, "BACKGROUND", nil, -8)
    f.opaqueBackground:SetColorTexture(0.035, 0.029, 0.022, 1)
    f.opaqueBackground:SetPoint("TOPLEFT", 4, -4); f.opaqueBackground:SetPoint("BOTTOMRIGHT", -4, 4)
    f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 32,
        edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    f:SetBackdropColor(0.8, 0.72, 0.6, 1)
    f:SetBackdropBorderColor(0.64, 0.52, 0.34, 1)
    return f
end
local function Button(parent, label, width, callback)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 28); b:SetText(label); b:SetScript("OnClick", callback)
    b.selectedMark = b:CreateTexture(nil, "OVERLAY")
    b.selectedMark:SetColorTexture(0.95, 0.77, 0.35, 1)
    b.selectedMark:SetPoint("BOTTOMLEFT", 8, 3); b.selectedMark:SetPoint("BOTTOMRIGHT", -8, 3)
    b.selectedMark:SetHeight(2); b.selectedMark:Hide()
    return b
end
local unlockToast, unlockQueue
function ML.ShowRankUnlock(mob, rank)
    unlockQueue = unlockQueue or {}
    -- Keep notifications bounded during mass looting.
    if #unlockQueue < 8 then unlockQueue[#unlockQueue + 1] = {name = mob.name, rank = rank} end
    if not unlockToast then
        unlockToast = Panel(UIParent)
        unlockToast:SetSize(360, 78); unlockToast:SetPoint("TOP", 0, -145)
        unlockToast:SetFrameStrata("DIALOG"); unlockToast:EnableMouse(false)
        unlockToast.title = Text(unlockToast, 15); unlockToast.title:SetPoint("TOPLEFT", 18, -14)
        unlockToast.name = Text(unlockToast, 13); unlockToast.name:SetPoint("TOPLEFT", 18, -39)
        unlockToast.name:SetSize(324, 20); unlockToast.name:SetWordWrap(false)
        unlockToast:SetScript("OnUpdate", function(self, elapsed)
            if not self.elapsed then
                local nextUnlock = table.remove(unlockQueue, 1)
                if not nextUnlock then self:Hide(); return end
                self.elapsed = 0
                local tier = nextUnlock.rank
                self:SetBackdropBorderColor(unpack(tier.color))
                self.title:SetText("|c" .. tier.hex .. tier.label .. " rank unlocked!|r")
                self.name:SetText(nextUnlock.name .. " · " .. tier.kills .. " recorded kills")
            end
            self.elapsed = self.elapsed + elapsed
            self:SetAlpha(math.max(0, math.min(1, self.elapsed / 0.25, (3.5 - self.elapsed) / 0.5)))
            if self.elapsed >= 3.5 then self.elapsed = nil; if #unlockQueue == 0 then self:Hide() end end
        end)
        unlockToast:Hide()
    end
    if not unlockToast:IsShown() then unlockToast:SetAlpha(0); unlockToast:Show() end
end
local function PlaceLabel(p)
    local label = p.zone
    if p.sub ~= "" then label = label .. " · " .. p.sub end
    return label
end
local function RenderLoot(mob)
    if not mobLoot then mobLoot=ML.BuildMobLoot(detail:GetParent(),detailScroll,{Text=Text,Panel=Panel,Button=Button}) end
    detail:Hide(); mobLoot:Show(mob)
end
function ML.RefreshMobLootRows()
    if mobLoot then mobLoot:Draw() end
end
local function RenderCharacters(mob)
    local entries, unknown = ML.CharacterBreakdown(mob)
    local lines = { "|cffeac273RECORDED BY YOUR CHARACTERS|r",
        "Account-wide · " .. mob.count .. " recorded mobs", "" }
    for _, entry in ipairs(entries) do
        local stats = entry.stats
        lines[#lines + 1] = ML.CharacterName(entry.guid) .. "  |cffeac273×" .. stats.count .. "|r"
        lines[#lines + 1] = stats.loot .. " from loot · " .. stats.manual .. " manual"
        lines[#lines + 1] = (stats.observed or 0) .. " observed deaths"
        lines[#lines + 1] = "Last seen: " .. date("%Y-%m-%d %H:%M", stats.last)
        lines[#lines + 1] = ""
    end
    lines[#lines + 1] = "|cffeac273SIGHTINGS BY CHARACTER|r"
    local sightings = {}
    for guid, stats in pairs(mob.sightingCharacters or {}) do sightings[#sightings + 1] = {guid = guid, stats = stats} end
    table.sort(sightings, function(a, b) return a.guid < b.guid end)
    for _, entry in ipairs(sightings) do
        lines[#lines + 1] = ML.CharacterName(entry.guid) .. "  ×" .. entry.stats.count
    end
    if #sightings == 0 then lines[#lines + 1] = "No sightings recorded yet." end
    if unknown > 0 then
        lines[#lines + 1] = "|cff9099a5Unknown|r  ×" .. unknown
        lines[#lines + 1] = "Older records or missing character data."
    elseif #entries == 0 then
        lines[#lines + 1] = "No character data recorded yet."
    end
    detail:SetText(table.concat(lines, "\n"))
    detail:GetParent():SetHeight(math.max(140, detail:GetStringHeight() + 16))
end
local function ShowLocationSections(mob)
    if not locationBrowser then
        locationBrowser=ML.BuildLocationBrowser(detail:GetParent(),detailScroll,{Text=Text,Panel=Panel,Button=Button},function() window:Hide() end)
    end
    locationBrowser:Show(mob,detail:GetStringHeight()+10)
end
local function Details(mob, keepModel)
    if locationBrowser then locationBrowser:Hide() end
    if mobLoot then mobLoot:Hide() end
    detail:Show()
    if mob.members then mob = ML.GetMob(mob.representativeID) end
    local group = mobGroups[mob.id]
    local count = group and #group.members or 1
    if selected ~= mob.id then detailScroll:SetVerticalScroll(0) end
    selected = mob.id
    local collectionMob = group or mob
    local nameGrouping = ML.db.nameGroups and ML.db.nameGroups[mob.name]
    local sameName = 0
    for _, entry in pairs(ML.db.mobs) do if entry.name == mob.name then sameName = sameName + 1 end end
    nameGroupButton:SetEnabled(not mob.provisional and not mob.catalogOnly and (sameName > 1 or nameGrouping))
    nameGroupButton:SetText(nameGrouping and "Restore auto grouping" or "Group same name")
    attitudeButton:SetText("Attitude: " .. ML.ReactionLabel(mob)); attitudeButton:SetEnabled(not mob.provisional and not mob.catalogOnly)
    local choices, index = ML.ModelChoices(group or mob), 1
    for i, choice in ipairs(choices) do
        if choice.mob.id == mob.id and choice.display == ML.SelectedDisplay(mob) then index = i; break end
    end
    appearanceText:SetText(mob.provisional and "NPC identity pending" or ML.SelectedDisplay(mob) and ("Appearance #" .. ML.SelectedDisplay(mob) .. " · NPC #" .. mob.id) or
        ("Discovering appearance · NPC #" .. mob.id))
    appearanceCounter:SetText(index .. "/" .. #choices)
    previousAppearance:SetEnabled(#choices > 1); nextAppearance:SetEnabled(#choices > 1)
    for _, row in ipairs(lootRows) do row:Hide() end
    for _, row in ipairs(locationRows) do row:Hide() end
    for name, tab in pairs(tabs) do
        tab.selectedMark:SetShown(name == activeTab)
    end
    if not keepModel or not model.request or model.request.id~=mob.id or model.request.display~=ML.SelectedDisplay(mob) then
        LoadModel(mob,not keepModel)
    end
    if activeTab == "loot" then RenderLoot(mob); return end
    if activeTab == "characters" then RenderCharacters(mob); return end
    if mob.catalogOnly then
        local zones = {}
        for _, area in ipairs(ML.TrinityData.npcs[mob.id][5]) do zones[#zones+1] = ML.CatalogAreaName(area) end
        detail:SetText("|cffeac273" .. mob.name .. "|r\nNPC #" .. mob.id .. "\nStatus: Undiscovered\nType: " .. ML.ClassificationLabel(mob) ..
            (mob.tooltipType and (" · "..mob.tooltipType) or "").."\n\nNo encounters recorded." .. (#zones>0 and ("\nKnown areas: "..table.concat(zones, ", ")) or "") ..
            "\nCatalog entries may include older, unused or conditional variants.")
        ShowLocationSections(mob)
        return
    end
    local lines = { "|cffeac273" .. mob.name .. "|r", mob.provisional and "NPC ID pending" or "NPC #" .. mob.id,
        "Type: " .. ML.ClassificationLabel(mob) .. "  ·  Level: " .. (mob.level and (mob.level < 0 and "??" or tostring(mob.level)) or "Unknown"),
        "Attitude: " .. ML.ReactionLabel(mob) .. " · " .. (mob.sightings or 0) .. " sightings",
        "Status: " .. (mob.count > 0 and "Killed / recorded" or "Seen only"),
        "", "|cffeac273" .. mob.count .. " recorded mobs|r",
        mob.loot .. " from loot  ·  " .. mob.manual .. " manual",
        (mob.observed or 0) .. " observed deaths",
        "Last kill record: " .. (mob.lastKilled and date("%Y-%m-%d %H:%M", mob.lastKilled) or "Not recorded / legacy data"),
        "", "First seen: " .. date("%Y-%m-%d", mob.first),
        "Last seen: " .. date("%Y-%m-%d %H:%M", mob.last) }
    table.insert(lines, 2, "Collection: " .. ML.CollectionProgress(collectionMob))
    for index, achievement in ipairs(ML.CollectionAchievementLines(collectionMob)) do
        table.insert(lines, index + 2, achievement)
    end
    if ML.IsHuntTarget(collectionMob) then table.insert(lines, 2, "|cffffd166Hunt target · Pinned to the top of the list|r") end
    if count > 1 then
        table.insert(lines, 2, string.format("Group: %d NPC variants · %d kills · %d sightings", count, group.count, group.sightings))
        table.insert(lines, 3, "Details, loot, characters and places below: selected NPC variant.")
    end
    if mob.tooltipType then table.insert(lines, 3, "Creature details: " .. mob.tooltipType) end
    local metadataStatus = ML.NPCMetadataStatus(mob)
    if metadataStatus then table.insert(lines, 2, "|cffeac273" .. metadataStatus .. "|r") end
    detail:SetText(table.concat(lines, "\n"))
    ShowLocationSections(mob)
end
local function StyleRow(row)
    local chosen = ML.GroupContains(row.mob, selected)
    row:SetBackdropColor(chosen and 0.16 or 0.065, chosen and 0.12 or 0.055, chosen and 0.065 or 0.04, 1)
    row.accent:SetShown(chosen)
    row.selection:SetShown(chosen)
    local _, progress, rank, nextRank = ML.CollectionProgress(row.mob)
    row.rankBorder:SetShown(rank ~= nil)
    if rank then
        row.rankBorder:SetBackdropBorderColor(unpack(rank.color))
        row.rankBadge:SetText("|c" .. rank.hex .. "[" .. rank.badge .. "] " .. rank.label .. "|r")
    else row.rankBadge:SetText("") end
    row.progressFill:SetWidth(math.max(1, (row:GetWidth() - 16) * progress))
    row.progressFill:SetShown(progress > 0)
    row.progressFill:SetVertexColor(unpack((nextRank or rank or ML.KillRanks[1]).color))
    row.hunt:SetText(ML.IsHuntTarget(row.mob) and "*" or "+")
    row.runes:SetShown(rank ~= nil and rank.key == "master")
    for _, ornament in ipairs(row.rankOrnaments) do
        ornament:SetShown(rank ~= nil and (rank.key == "gold" or rank.key == "master"))
        if rank then ornament:SetVertexColor(unpack(rank.color)) end
    end
end
local function RenderVisibleRows()
    if renderingRows or not window or not window:IsShown() or currentPage ~= "mobs" or not list or not content then return end
    renderingRows = true
    local scroll = list:GetVerticalScroll() or 0
    local top = math.max(0, scroll - 156)
    local bottom = scroll + list:GetHeight() + 156
    -- Offsets are sorted. Scrolling finds the first visible entry without
    -- rebuilding groups, searching the collection, or scanning every mob.
    local low, high = 1, #renderEntries
    while low <= high do
        local middle = math.floor((low + high) / 2)
        if renderEntries[middle].offset + rowHeight < top then low = middle + 1
        else high = middle - 1 end
    end
    local inView, wanted = {}, {}
    for index = low, #renderEntries do
        local entry = renderEntries[index]
        if entry.offset > bottom then break end
        inView[#inView + 1] = entry
        wanted[entry.mob.id] = true
    end
    if catalogViewport then
        local section = catalogViewport
        local first = math.max(1, math.floor((top-section.offset)/78)+1)
        local last = math.min(#section.ids, math.floor((bottom-section.offset)/78)+1)
        for index=first,last do
            local mob=ML.GetMob(section.ids[index])
            if mob then
                mob.members={mob}; mob.representativeID=mob.id
                inView[#inView+1]={mob=mob,offset=section.offset+(index-1)*78,indent=0}
                wanted[mob.id]=true
            end
        end
    end
    local existing, used = {}, {}
    for _, row in ipairs(rows) do
        if row.mob then existing[row.mob.id] = row end
    end
    for _, entry in ipairs(inView) do
        local mob = entry.mob
        local row = existing[mob.id]
        if not row then
            for _, candidate in ipairs(rows) do
                if not used[candidate] and (not candidate.mob or not wanted[candidate.mob.id]) then
                    row = candidate
                    break
                end
            end
        end
        if not row then
            row = CreateFrame("Button", nil, content, "BackdropTemplate")
            row:SetSize(340, rowHeight)
            row:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8" })
            row.portrait = ML.CreateMobPortrait(row, 38); row.portrait:SetPoint("LEFT", 12, 0)
            row.title = Text(row, 13); row.title:SetPoint("TOPLEFT", 78, -10); row.title:SetSize(188, 18); row.title:SetWordWrap(false)
            row.zone = Text(row, 11, { 0.72, 0.65, 0.52 }); row.zone:SetPoint("TOPLEFT", 78, -32); row.zone:SetSize(188, 14); row.zone:SetWordWrap(false)
            row.typeLabel = Text(row, 10, gold); row.typeLabel:SetPoint("TOPLEFT", 78, -52); row.typeLabel:SetSize(188, 12); row.typeLabel:SetWordWrap(false)
            row.count = Text(row, 18, gold); row.count:SetPoint("RIGHT", -10, 4); row.count:SetSize(54, 24); row.count:SetJustifyH("RIGHT"); row.count:SetWordWrap(false)
            row.selection = row:CreateTexture(nil, "BORDER")
            row.selection:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
            row.selection:SetAllPoints(); row.selection:SetBlendMode("ADD"); row.selection:SetAlpha(0.12)
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row:GetHighlightTexture():SetAlpha(0.10)
            row.accent = row:CreateTexture(nil, "ARTWORK"); row.accent:SetColorTexture(unpack(gold))
            row.accent:SetPoint("TOPLEFT"); row.accent:SetPoint("BOTTOMLEFT"); row.accent:SetWidth(3)
            row.rankBorder = CreateFrame("Frame", nil, row, "BackdropTemplate")
            row.rankBorder:SetAllPoints(); row.rankBorder:EnableMouse(false)
            row.rankBorder:SetBackdrop({edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12})
            row.rankBadge = Text(row.rankBorder, 9); row.rankBadge:SetPoint("TOPRIGHT", -8, -6)
            row.runes = Text(row.rankBorder, 9, gold); row.runes:SetPoint("TOP", 0, -1); row.runes:SetText("< : >")
            row.rankOrnaments = {}
            for _, corner in ipairs({{"TOPLEFT", 5, -5}, {"TOPRIGHT", -5, -5}, {"BOTTOMLEFT", 5, 5}, {"BOTTOMRIGHT", -5, 5}}) do
                local ornament = row.rankBorder:CreateTexture(nil, "OVERLAY")
                ornament:SetTexture("Interface\\Buttons\\WHITE8X8"); ornament:SetSize(4, 4)
                ornament:SetPoint(corner[1], corner[2], corner[3]); ornament:SetRotation(math.pi / 4)
                row.rankOrnaments[#row.rankOrnaments + 1] = ornament
            end
            row.progressBackground = row:CreateTexture(nil, "ARTWORK")
            row.progressBackground:SetColorTexture(0.025, 0.02, 0.015, 1)
            row.progressBackground:SetPoint("BOTTOMLEFT", 8, 4); row.progressBackground:SetPoint("BOTTOMRIGHT", -8, 4); row.progressBackground:SetHeight(3)
            row.progressFill = row:CreateTexture(nil, "OVERLAY")
            row.progressFill:SetTexture("Interface\\Buttons\\WHITE8X8")
            row.progressFill:SetPoint("BOTTOMLEFT", 8, 4); row.progressFill:SetHeight(3)
            row.hunt = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
            row.hunt:SetSize(20, 20); row.hunt:SetPoint("BOTTOMRIGHT", -7, 9)
            row.hunt:SetScript("OnClick", function() ML.ToggleHuntTarget(row.mob) end)
            row.hunt:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(ML.IsHuntTarget(row.mob) and "Unpin hunt target" or "Pin hunt target")
                GameTooltip:AddLine(ML.CollectionProgress(row.mob), 0.85, 0.82, 0.74, true)
                GameTooltip:Show()
            end)
            row.hunt:SetScript("OnLeave", function() GameTooltip:Hide() end)
            row:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(self.mob.name, 0.92, 0.76, 0.45)
                GameTooltip:AddLine(ML.CollectionProgress(self.mob), 0.85, 0.82, 0.74, true)
                for _, achievement in ipairs(ML.CollectionAchievementLines(self.mob)) do
                    GameTooltip:AddLine(achievement, 0.85, 0.82, 0.74, true)
                end
                GameTooltip:AddLine("Ranks: Bronze 50 · Silver 250 · Gold 1,000 · Master 5,000", 0.85, 0.82, 0.74, true)
                GameTooltip:AddLine(self.mob.provisional and "NPC ID pending" or (ML.ClassificationLabel(self.mob) .. " · NPC #" .. self.mob.id))
                local metadataStatus = ML.NPCMetadataStatus(self.mob)
                if metadataStatus then GameTooltip:AddLine(metadataStatus, 0.92, 0.76, 0.45, true) end
                if #self.mob.members > 1 then
                    local ids = {}
                    for _, member in ipairs(self.mob.members) do ids[#ids + 1] = tostring(member.id) end
                    GameTooltip:AddLine("Grouped NPC IDs: " .. table.concat(ids, ", "), 0.85, 0.82, 0.74, true)
                    GameTooltip:AddLine("Use the model arrows to inspect each NPC's records and appearances.", 0.85, 0.82, 0.74, true)
                end
                if ML.MobHasWishlistDrops(self.mob) then GameTooltip:AddLine("Wishlist source: associated with an item on your wishlist.",1,0.82,0,true) end
                ML.AddMobLocationTooltip(self.mob)
                GameTooltip:Show()
            end)
            row:SetScript("OnLeave", function(self) StyleRow(self); GameTooltip:Hide() end)
            row:SetScript("OnClick", function(self)
                local id = ML.GroupContains(self.mob, selected) and selected or self.mob.representativeID
                if id~=selected then ML.PushView() end
                Details(ML.GetMob(id)); ML.Refresh()
            end)
            rows[#rows + 1] = row
        end
        used[row] = true
        if row.entry ~= entry or not row:IsShown() then
            if row.mob and row.mob.id ~= mob.id and GameTooltip.IsOwned and GameTooltip:IsOwned(row) then GameTooltip:Hide() end
            row.entry = entry
            row.mob = mob
            row.offset = entry.offset
            row:SetPoint("TOPLEFT", entry.indent, -entry.offset); row:SetWidth(340 - entry.indent)
            row.title:SetWidth(188 - entry.indent); row.zone:SetWidth(188 - entry.indent); row.typeLabel:SetWidth(188 - entry.indent)
            StyleRow(row)
            ML.UpdateMobPortrait(row.portrait, mob)
            row.title:SetText(mob.name); row.count:SetText(mob.catalogOnly and "New" or (mob.count > 0 and mob.count or "Seen"))
            row.hunt:SetShown(not mob.catalogOnly)
            local _, metadataShort = ML.NPCMetadataStatus(mob)
            row.typeLabel:SetText(metadataShort or (#mob.members > 1 and (#mob.members .. " NPC variants · " .. ML.ReactionLabel(mob)) or
                (ML.ClassificationLabel(mob) .. " · " .. ML.ReactionLabel(mob))))
            if ML.MobHasWishlistDrops(mob) then row.typeLabel:SetText("|cffffd100*|r "..row.typeLabel:GetText()) end
            row.fullLocation = ML.MobLocationSummary(mob)
            row.zone:SetText(row.fullLocation)
            row:Show()
        else StyleRow(row) end
    end
    for _, row in ipairs(rows) do
        if not used[row] then row:Hide(); row.entry = nil end
    end
    renderingRows = false
end
local statusDirty,statusScheduled={},false
function ML.RefreshNPCStatus(id)
    if not window or not window:IsShown() or currentPage~="mobs" then return end
    statusDirty[id]=true
    if statusScheduled then return end
    statusScheduled=true
    C_Timer.After(0.25,function()
        statusScheduled=false
        local dirty=statusDirty; statusDirty={}
        if not window:IsShown() or currentPage~="mobs" then return end
        for _,row in ipairs(rows) do
            local mob=row.mob
            if row:IsShown() and mob then
                local affected=false
                for _,member in ipairs(mob.members or {mob}) do if dirty[member.id] then affected=true; break end end
                if affected then
                    local _,short=ML.NPCMetadataStatus(mob)
                    row.typeLabel:SetText(short or (#mob.members>1 and (#mob.members.." NPC variants · "..ML.ReactionLabel(mob)) or
                        (ML.ClassificationLabel(mob).." · "..ML.ReactionLabel(mob))))
                    if ML.MobHasWishlistDrops(mob) then row.typeLabel:SetText("|cffffd100*|r "..row.typeLabel:GetText()) end
                end
            end
        end
        if selected and dirty[selected] and activeTab=="info" then
            local mob=ML.GetMob(selected)
            if mob then Details(mob,true) end
        end
    end)
end
function ML.Refresh(background)
    if background~=true and ML.InvalidateMobGroups then ML.InvalidateMobGroups() end
    if ML.QueueHuntTrackerRefresh then ML.QueueHuntTrackerRefresh() end
    if not window or not window:IsShown() or not ML.db then return end
    local query = string.lower(search:GetText() or "")
    local mobs, total, species, unknown = {}, 0, 0, 0
    for _, mob in pairs(ML.db.mobs) do
        if not mob.reaction or mob.reaction == "unknown" then unknown = unknown + 1 end
    end
    local groups
    groups, mobGroups = ML.BuildMobGroups()
    ML.tooltipGroups = mobGroups
    if ML.UpdateHuntTracker then ML.UpdateHuntTracker(groups) end
    ML.CheckCollectionUnlocks(groups)
    local ranks = {bronze = 0, silver = 0, gold = 0, master = 0}
    for _, mob in ipairs(groups) do
        total = total + mob.count; species = species + 1
        local rank = ML.KillRank(mob.count)
        if rank then ranks[rank.key] = ranks[rank.key] + 1 end
        if currentPage == "mobs" then
            local matches = query=="" or string.find(string.lower(mob.name), query, 1, true) or string.find(tostring(mob.id), query, 1, true)
            if not matches then
                for _, p in pairs(mob.places) do
                    if string.find(string.lower(PlaceLabel(p)), query, 1, true) then matches=true; break end
                end
            end
            if not matches then
                for _, p in pairs(mob.sightingPlaces or {}) do
                    if string.find(string.lower(PlaceLabel(p)), query, 1, true) then matches=true; break end
                end
            end
            local matchesType = typeFilter=="all"
            if not matches or not matchesType then for _, member in ipairs(mob.members) do
                if string.find(tostring(member.id), query, 1, true) then matches = true end
                if ML.MatchesMobType(member, typeFilter) or
                    (ML.PendingDungeonIdentity(member) and ML.MissingNPCField(member.classification)) then matchesType = true end
                if matches and matchesType then break end
            end end
            if matches and matchesType and ML.MatchesCollection(mob, collectionFilter) and ML.MatchesCatalogArea(mob,catalogArea) then mobs[#mobs + 1] = mob end
        end
    end
    local sortMode=ML.GetSortMode("mobs")
    if currentPage == "mobs" then table.sort(mobs,function(a,b) return ML.SortMobBefore(a,b,sortMode) end) end
    stats[1]:SetText(total); stats[2]:SetText(species); stats[3]:SetText(ML.session)
    local summary = {}
    for _, rank in ipairs(ML.KillRanks) do summary[#summary + 1] = "|c" .. rank.hex .. ranks[rank.key] .. " " .. rank.label .. "|r" end
    collectionSummary:SetText(table.concat(summary, " · "))
    bulkHostile:SetShown(unknown > 0); bulkHostile.unknownCount = unknown
    if currentPage == "items" then ML.RefreshItems(); return end
    if currentPage == "session" then ML.RefreshSessionReport(); return end
    if currentPage == "areas" then ML.RefreshAreas(groups); return end
    local undiscovered={}
    local undiscoveredCount=ML.UndiscoveredCount(query,typeFilter,catalogArea,collectionFilter)
    if closedGroups.undiscovered==false then undiscovered=ML.UndiscoveredIDs(query,typeFilter,catalogArea,collectionFilter) end
    local pageKey=query..":"..typeFilter..":"..ML.AreaFilterKey(catalogArea)..":"..collectionFilter..":"..sortMode
    if pageKey~=catalogPageKey then catalogPage=1; catalogPageKey=pageKey end
    local catalogPages=math.max(1,math.ceil(undiscoveredCount/catalogPageSize))
    catalogPage=math.min(catalogPage,catalogPages)
    filterCount:SetText(string.format("%d / %d", #mobs+undiscoveredCount, species+undiscoveredCount))
    -- Keep visible rows alive: hiding hovered rows fires OnLeave, which used to
    -- recursively rebuild this list and leave the selected row blank.
    local selectionVisible = false
    for _, mob in ipairs(mobs) do if ML.GroupContains(mob, selected) then selectionVisible = true; break end end
    local selectedEntry=selected and ML.GetMob(selected)
    if selectedEntry and selectedEntry.catalogOnly and ML.MatchesMobType(selectedEntry,typeFilter) and ML.MatchesCatalogArea(selectedEntry,catalogArea) and
        ML.MatchesCollection(selectedEntry,collectionFilter) and (query=="" or string.find(string.lower(selectedEntry.name),query,1,true) or string.find(tostring(selected),query,1,true)) then selectionVisible=true end
    if not selectionVisible then
        if selected and mobs[1] then Details(mobs[1])
        else
            if mobLoot then mobLoot:Hide() end
            if locationBrowser then locationBrowser:Hide() end
            detail:Show()
            selected = nil; model:ClearModel(); modelHint:SetText("")
            appearanceCounter:SetText("0/0")
            nameGroupButton:SetEnabled(false)
            appearanceText:SetText("No mob selected")
            previousAppearance:SetEnabled(false); nextAppearance:SetEnabled(false)
            attitudeButton:SetText("Set attitude"); attitudeButton:SetEnabled(false)
            detail:SetText(#mobs>0 and "Select a creature to inspect its model and details." or undiscoveredCount>0 and "Expand Undiscovered and select a creature to inspect its model and details." or ML.CatalogUnavailableText() or "No mobs match your search and filters.")
            detail:GetParent():SetHeight(140)
            for _, row in ipairs(lootRows) do row:Hide() end
            for _, row in ipairs(locationRows) do row:Hide() end
        end
    end
    closedGroups = ML.db.closedGroups or closedGroups
    local layout, listHeight = ML.DiscoveryLayout(mobs, closedGroups)
    catalogViewport=nil
    if undiscoveredCount>0 then
        layout[#layout+1]={header=true,key="undiscovered",label="Undiscovered",count=undiscoveredCount,indent=0,offset=listHeight}
        listHeight=listHeight+32
        if closedGroups.undiscovered==false then
            local ids={}
            for i=(catalogPage-1)*catalogPageSize+1,math.min(#undiscovered,catalogPage*catalogPageSize) do ids[#ids+1]=undiscovered[i] end
            catalogViewport={ids=ids,offset=listHeight}
            listHeight=listHeight+#ids*78
        end
    end
    if ML.CatalogUnavailableText() then
        layout[#layout+1]={header=true,key="catalogUnavailable",label=ML.CatalogUnavailableText(),count=0,indent=0,offset=listHeight}
        listHeight=listHeight+32
    end
    local visibleMobs, usedGroups = {}, {}
    local colors = {nonhostile = {0.65, 0.85, 0.45}, hostile = {0.95, 0.45, 0.35}}
    for _, entry in ipairs(layout) do
        if entry.header then
            local header = groupRows[entry.key]
            if not header then
                header = CreateFrame("Button", nil, content, "BackdropTemplate")
                header:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"}); header:SetBackdropColor(0.11, 0.09, 0.06, 1)
                header.label = Text(header, 12, colors[entry.key] or gold); header.label:SetPoint("LEFT", 8, 0)
                header.label:SetSize(310, 18); header.label:SetWordWrap(false)
                header:SetScript("OnEnter",function(self)
                    if self.groupKey=="catalogUnavailable" then
                        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine(ML.CatalogUnavailableText(),1,0.82,0,true); GameTooltip:Show()
                    end
                end)
                header:SetScript("OnLeave",function() GameTooltip:Hide() end)
                header:SetScript("OnClick", function(self)
                    if self.groupKey=="catalogUnavailable" then ML.Print(ML.CatalogUnavailableText()); return end
                    closedGroups[self.groupKey] = not closedGroups[self.groupKey]
                    ML.db.closedGroups = closedGroups; ML.Refresh()
                end)
                groupRows[entry.key] = header
            end
            header.groupKey = entry.key
            header:SetPoint("TOPLEFT", entry.indent, -entry.offset); header:SetSize(340 - entry.indent, 28)
            header.label:SetText((closedGroups[entry.key] and "+ " or "- ") .. entry.label .. " (" .. entry.count .. ")")
            if entry.key=="undiscovered" then
                if not header.previous then
                    header.previous=Button(header,"<",22,function() catalogPage=math.max(1,catalogPage-1); ML.Refresh() end)
                    header.previous:SetPoint("RIGHT",-27,0); header.previous:SetHeight(22)
                    header.next=Button(header,">",22,function() catalogPage=catalogPage+1; ML.Refresh() end)
                    header.next:SetPoint("RIGHT",-3,0); header.next:SetHeight(22)
                end
                header.label:SetWidth(284)
                header.label:SetText((closedGroups.undiscovered and "+ " or "- ").."Undiscovered · "..entry.count.." · "..catalogPage.."/"..catalogPages)
                header.previous:SetEnabled(catalogPage>1); header.next:SetEnabled(catalogPage<catalogPages)
            end
            if entry.key=="catalogUnavailable" then header.label:SetText(entry.label) end
            header:Show(); usedGroups[entry.key] = true
        else visibleMobs[#visibleMobs + 1] = entry end
    end
    for key, header in pairs(groupRows) do if not usedGroups[key] then header:Hide() end end
    renderEntries = visibleMobs
    content:SetHeight(math.max(1, listHeight))
    local maxScroll = math.max(0, listHeight - list:GetHeight())
    if list:GetVerticalScroll() > maxScroll then list:SetVerticalScroll(maxScroll) end
    RenderVisibleRows()
    window.empty:SetShown(#mobs == 0 and undiscoveredCount==0 and not ML.CatalogUnavailableText())
    window.empty:SetText(species == 0 and "Your bestiary starts here.\n\nSelect an NPC as your target\nto record a sighting." or "No matching entries.")
    if selected and ML.GetMob(selected) then
        Details(ML.GetMob(selected), true)
    end
end
function ML.SelectPage(name,skipHistory)
    if name~=currentPage and not skipHistory then ML.PushView() end
    if name=="mobs" or name=="items" then ML.EnsureCatalog() end
    if catalogAreaButton then catalogAreaButton:CloseMenu() end
    if filterMenu then filterMenu:Hide() end
    if collectionMenu then collectionMenu:Hide() end
    if attitudeMenu then attitudeMenu:Hide() end
    currentPage = name
    ML.UpdateNavigationButtons()
    mobPage:SetShown(name == "mobs"); itemPage:SetShown(name == "items"); sessionPage:SetShown(name == "session")
    areaPage:SetShown(name == "areas")
    for key, tab in pairs(pageTabs) do tab.selectedMark:SetShown(key == name) end
    ML.Refresh()
end
function ML.OpenMob(id)
    local mob = ML.GetMob(id)
    if not mob then return end
    ML.PushView()
    activeTab = "info"
    local _, byID = ML.BuildMobGroups()
    for _, key in ipairs(ML.DiscoveryPath(byID[id] or mob)) do closedGroups[key] = false end
    if ML.IsHuntTarget(byID[id] or mob) then closedGroups.hunts = false end
    ML.db.closedGroups = closedGroups
    ML.SetMobTypeFilter("all")
    ML.SetCollectionFilter("all")
    catalogArea="all"; if catalogAreaButton then catalogAreaButton:Reset() end
    if mob.catalogOnly then closedGroups.undiscovered=false end
    ML.SelectPage("mobs",true)
    search:SetText("")
    Details(mob)
    if mob.catalogOnly then
        for index,npc in ipairs(ML.UndiscoveredIDs("","all","all","all")) do
            if npc==id then catalogPage=math.floor((index-1)/catalogPageSize)+1; break end
        end
    end
    ML.Refresh()
    if mob.catalogOnly and catalogViewport then
        for index,npc in ipairs(catalogViewport.ids) do
            if npc==id then list:SetVerticalScroll(math.max(0,math.min(catalogViewport.offset+(index-1)*78,content:GetHeight()-list:GetHeight()))); RenderVisibleRows(); break end
        end
        return
    end
    for _, entry in ipairs(renderEntries) do
        if ML.GroupContains(entry.mob, id) then
            list:SetVerticalScroll(math.max(0, math.min(entry.offset, content:GetHeight() - list:GetHeight())))
            RenderVisibleRows()
            break
        end
    end
end
local function Build()
    window = Panel(UIParent)
    window:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Gold-Border", tile = true, tileSize = 32,
        edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 } })
    window:SetBackdropColor(0.85, 0.8, 0.7, 1); window:SetBackdropBorderColor(1, 1, 1, 1)
    window:SetSize(900, 650); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG")
    window:SetClampedToScreen(true); window:SetMovable(true); window:EnableMouse(true)
    window:RegisterForDrag("LeftButton"); window:SetScript("OnDragStart", window.StartMoving)
    window:SetScript("OnDragStop", window.StopMovingOrSizing)
    window:SetScale(math.min(1, UIParent:GetWidth() / 940, UIParent:GetHeight() / 690))
    window:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" then self:SetPropagateKeyboardInput(false); self:Hide()
        else self:SetPropagateKeyboardInput(true) end
    end)
    window:EnableKeyboard(true)
    local header = window:CreateTexture(nil, "BORDER")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(310, 64); header:SetPoint("TOP", 0, 16)
    local title = Text(window, 28, gold); title:SetPoint("TOPLEFT", 26, -17); title:SetText("MOBLOG")
    local subtitle = Text(window, 10, { 0.72, 0.65, 0.52 }); subtitle:SetPoint("TOPLEFT", 28, -50); subtitle:SetText("YOUR ACCOUNT-WIDE BESTIARY")
    local collectionCard = CreateFrame("Frame", nil, window)
    collectionCard:SetPoint("TOP", 0, -55); collectionCard:SetSize(462, 12); collectionCard:EnableMouse(true)
    collectionSummary = Text(collectionCard, 10); collectionSummary:SetAllPoints()
    collectionSummary:SetJustifyH("CENTER"); collectionSummary:SetJustifyV("MIDDLE"); collectionSummary:SetWordWrap(false)
    collectionCard:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine("Account-wide collection ranks", 0.92, 0.76, 0.45)
        GameTooltip:AddLine("Each grouped entry counts once at its highest rank. Existing kills count toward progress.", 0.85, 0.82, 0.74, true)
        for _, rank in ipairs(ML.KillRanks) do GameTooltip:AddLine(rank.label .. ": " .. rank.kills .. " recorded kills", unpack(rank.color)) end
        GameTooltip:Show()
    end)
    collectionCard:SetScript("OnLeave", function() GameTooltip:Hide() end)
    currentAreaButton=Button(window,"Current area",108,ML.UseCurrentArea)
    currentAreaButton:SetPoint("BOTTOMRIGHT",-28,12); currentAreaButton:SetHeight(24)
    resetFiltersButton=Button(window,"Reset filters",104,ML.ResetCurrentFilters)
    resetFiltersButton:SetPoint("BOTTOMRIGHT",currentAreaButton,"BOTTOMLEFT",-8,0); resetFiltersButton:SetHeight(24)
    backButton=Button(window,"< Back",58,ML.GoBack)
    backButton:SetPoint("BOTTOMRIGHT",resetFiltersButton,"BOTTOMLEFT",-8,0); backButton:SetHeight(24)
    local footerDivider=window:CreateTexture(nil,"BORDER")
    footerDivider:SetColorTexture(0.64,0.52,0.34,0.3); footerDivider:SetPoint("BOTTOMLEFT",26,42); footerDivider:SetSize(846,1)
    local close = CreateFrame("Button", nil, window, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -7, -7); close:SetScript("OnClick", function() window:Hide() end)
    for i, label in ipairs({ "KILL RECORDS", "NPC TYPES", "KILLS THIS SESSION" }) do
        local card = Panel(window); card:SetSize(274, 46); card:SetPoint("TOPLEFT", 26 + (i - 1) * 286, -70)
        stats[i] = Text(card, 23, gold); stats[i]:SetPoint("LEFT", 12, 0)
        local caption = Text(card, 10, { 0.75, 0.67, 0.51 }); caption:SetPoint("RIGHT", -12, 0); caption:SetText(label)
    end
    mobPage = CreateFrame("Frame", nil, window); mobPage:SetAllPoints()
    search = CreateFrame("EditBox", nil, mobPage, "InputBoxTemplate")
    search:SetSize(160, 28); search:SetPoint("TOPLEFT", 34, -191); search:SetAutoFocus(false)
    local searchSequence=0
    search:SetScript("OnTextChanged",function()
        searchSequence=searchSequence+1; local token=searchSequence
        C_Timer.After(0.2,function() if token==searchSequence and window:IsShown() then ML.Refresh() end end)
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEditFocusGained", function()
        if filterMenu then filterMenu:Hide() end
        if collectionMenu then collectionMenu:Hide() end
    end)
    local hint = Text(mobPage, 10); hint:SetPoint("TOPLEFT", 28, -170); hint:SetText("MOB, NPC ID OR LOCATION")
    sortButton=ML.BuildSortDropdown(mobPage,{Button=Button,Panel=Panel},"mobs","mobs",206,-191,164,function()
        list:SetVerticalScroll(0); ML.Refresh()
    end)
    filterButton = Button(mobPage, "All types  v", 130, function()
        if collectionMenu then collectionMenu:Hide() end
        filterMenu:SetShown(not filterMenu:IsShown())
    end)
    filterButton:SetPoint("TOPLEFT", 26, -226)
    filterCount = Text(mobPage, 10); filterCount:SetPoint("TOPLEFT", 302, -226); filterCount:SetSize(92, 28)
    filterCount:SetWordWrap(false); filterCount:SetJustifyH("RIGHT"); filterCount:SetJustifyV("MIDDLE")
    filterMenu = Panel(mobPage); filterMenu:SetSize(220, #ML.MobTypeFilters * 26 + 14)
    filterMenu:SetPoint("TOPLEFT", filterButton, "BOTTOMLEFT", 0, -2)
    filterMenu:SetFrameLevel(window:GetFrameLevel() + 50); filterMenu:Hide()
    for i, entry in ipairs(ML.MobTypeFilters) do
        local option = Button(filterMenu, entry.label, 202, function() ML.SetMobTypeFilter(entry.key) end)
        option:SetPoint("TOPLEFT", 9, -7 - (i - 1) * 26); option:SetHeight(25)
    end
    collectionButton = Button(mobPage, "All ranks  v", 130, function()
        filterMenu:Hide(); collectionMenu:SetShown(not collectionMenu:IsShown())
    end)
    collectionButton:SetPoint("TOPLEFT", 164, -226)
    collectionMenu = Panel(mobPage); collectionMenu:SetSize(280, #collectionChoices * 26 + 14)
    collectionMenu:SetPoint("TOPLEFT", collectionButton, "BOTTOMLEFT", 0, -2)
    collectionMenu:SetFrameLevel(window:GetFrameLevel() + 50); collectionMenu:Hide()
    for i, choice in ipairs(collectionChoices) do
        local key = choice.key
        local option = Button(collectionMenu, choice.label, 262, function() ML.SetCollectionFilter(key) end)
        option:SetPoint("TOPLEFT", 9, -7 - (i - 1) * 26); option:SetHeight(25)
    end
    window:SetScript("OnHide", function()
        if ML.ReleaseCatalogViewCache then ML.ReleaseCatalogViewCache() end
        if catalogAreaButton then catalogAreaButton:CloseMenu() end
        filterMenu:Hide(); collectionMenu:Hide(); if attitudeMenu then attitudeMenu:Hide() end
    end)
    -- Clip nested portrait frames and rows at the list boundary, while keeping
    -- the native scrollbar inside the wider clipping container.
    local listViewport = CreateFrame("Frame", nil, mobPage)
    catalogAreaButton=ML.BuildAreaNavigation(mobPage,{Button=Button,Panel=Panel,Text=Text},26,-126,846,function(key)
        catalogArea=key; list:SetVerticalScroll(0); ML.Refresh()
    end)
    listViewport:SetPoint("TOPLEFT", 26, -260); listViewport:SetSize(380, 300)
    listViewport:SetClipsChildren(true)
    list = CreateFrame("ScrollFrame", nil, listViewport, "UIPanelScrollFrameTemplate")
    list:SetPoint("TOPLEFT"); list:SetSize(344, 300)
    content = CreateFrame("Frame", nil, list); content:SetSize(340, 1); list:SetScrollChild(content)
    list:HookScript("OnVerticalScroll", RenderVisibleRows)
    list:HookScript("OnSizeChanged", RenderVisibleRows)
    window.empty = Text(mobPage, 14); window.empty:SetPoint("TOPLEFT", 40, -275); window.empty:SetWidth(310)
    local preview = Panel(mobPage); preview:SetPoint("TOPLEFT", 410, -180); preview:SetSize(462, 190)
    preview:SetBackdropColor(0.65, 0.58, 0.46, 1)
    modelHint = Text(preview, 12); modelHint:SetPoint("BOTTOM", 0, 9)
    model = CreateFrame("PlayerModel", nil, preview)
    model:SetPoint("TOPLEFT", 6, -35); model:SetPoint("BOTTOMRIGHT", -6, 31)
    model:SetKeepModelOnHide(true)
    model:SetScript("OnModelLoaded", function(self)
        local request=self.request
        local display=ML.Public(self:GetDisplayInfo())
        if not request or not ModelRequestActive(request) or type(display)~="number" or display<=0 then return end
        if request.display and request.display~=display then return end
        request.loaded=true; request.display=display
        -- Geometry/camera setup can finish after OnModelLoaded. Apply the camera
        -- on the next frame and once after layout settles, rather than claiming
        -- success while the model still has an uninitialized camera.
        local function Ready()
            if not ModelRequestActive(request) then return end
            self:RefreshCamera(); ApplyCamera(); modelHint:SetText("")
        end
        C_Timer.After(0,Ready); C_Timer.After(0.1,Ready)
        local mob=ML.db.mobs[request.id]
        if mob and ML.SavePortraitDisplay(mob,display) then ML.QueueRefresh() end
    end)
    model:SetScript("OnShow",function()
        local request=model.request
        if not request or selected~=request.id then return end
        local mob=ML.GetMob(request.id)
        if mob then LoadModel(mob,false) end
    end)
    local appearanceBar = CreateFrame("Frame", nil, preview)
    appearanceBar:SetPoint("TOPLEFT", 12, -8); appearanceBar:SetSize(438, 24)
    appearanceBar:SetFrameLevel(model:GetFrameLevel() + 1)
    appearanceText = Text(appearanceBar, 11, gold); appearanceText:SetPoint("LEFT"); appearanceText:SetWidth(300)
    appearanceCounter = Text(appearanceBar, 11, gold)
    appearanceCounter:SetPoint("RIGHT", -68, 0); appearanceCounter:SetSize(64, 20); appearanceCounter:SetJustifyH("RIGHT")
    local function ChangeAppearance(step)
        local mob = selected and ML.GetMob(selected)
        if not mob then return end
        local choices, index = ML.ModelChoices(mobGroups[selected] or mob), 1
        for i, choice in ipairs(choices) do
            if choice.mob.id == selected and choice.display == ML.SelectedDisplay(mob) then index = i; break end
        end
        if #choices < 2 then return end
        local choice = choices[(index - 1 + step) % #choices + 1]
        choice.mob.selectedDisplayID = choice.display
        if choice.mob.catalogOnly then
            ML.db.catalogAppearances=ML.db.catalogAppearances or {}
            ML.db.catalogAppearances[choice.mob.id]=choice.display
        end
        Details(choice.mob); ML.Refresh()
    end
    previousAppearance = Button(appearanceBar, "<", 28, function() ChangeAppearance(-1) end)
    previousAppearance:SetPoint("RIGHT", -33, 0); previousAppearance:SetHeight(22)
    nextAppearance = Button(appearanceBar, ">", 28, function() ChangeAppearance(1) end)
    nextAppearance:SetPoint("RIGHT", 0, 0); nextAppearance:SetHeight(22)
    local controls = Text(preview, 10, { 0.72, 0.65, 0.52 }); controls:SetPoint("BOTTOMLEFT", 12, 10)
    controls:SetText("Left: rotate · Right: pan · Wheel: zoom")
    local reset = Button(preview, "Reset", 54, function()
        model.distance = defaultDistance
        model.panX, model.panY, model.dragButton = 0, 0, nil
        ApplyCamera(); model:SetFacing(0.5)
    end)
    reset:SetPoint("BOTTOMRIGHT", -8, 5); reset:SetHeight(22)
    model:SetFacing(0.35)
    model:EnableMouse(true)
    model:EnableMouseWheel(true)
    model:SetScript("OnMouseWheel", function(self, delta)
        self.distance = math.max(0.1, math.min(30, (self.distance or defaultDistance) * 1.15 ^ (-delta)))
        ApplyCamera()
    end)
    local function UpdateModelDrag(self)
        if not self.dragButton then self:SetScript("OnUpdate",nil); return end
        if not IsMouseButtonDown(self.dragButton) then self.dragButton=nil; self:SetScript("OnUpdate",nil); return end
        local x, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        local dx, dy = (x - self.dragX) / scale, (y - self.dragY) / scale
        if self.dragButton == "LeftButton" then
            self:SetFacing(self:GetFacing() + dx / 100)
        else
            -- Model axes: depth, horizontal, vertical. Keep depth unchanged.
            -- Multiplying by camera distance dampened panning as the user
            -- zoomed in (down to 1/18 of the default speed at minimum distance).
            -- Keep drag input independent of that extra zoom multiplier.
            local sensitivity = defaultDistance / 100
            self.panX = (self.panX or 0) + dx * sensitivity
            self.panY = (self.panY or 0) + dy * sensitivity
            self:SetPosition(0, self.panX, self.panY)
        end
        self.dragX, self.dragY = x, y
    end
    model:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" or button == "RightButton" then
            self.dragButton = button
            self.dragX, self.dragY = GetCursorPosition()
            self:SetScript("OnUpdate",UpdateModelDrag)
        end
    end)
    model:SetScript("OnMouseUp", function(self, button)
        if self.dragButton == button then self.dragButton=nil; self:SetScript("OnUpdate",nil) end
    end)
    model:SetScript("OnHide", function(self) self.dragButton=nil; self:SetScript("OnUpdate",nil) end)

    local detailPanel = Panel(mobPage); detailPanel:SetPoint("TOPLEFT", 410, -414); detailPanel:SetSize(462, 154)
    local ds = CreateFrame("ScrollFrame", nil, mobPage, "UIPanelScrollFrameTemplate")
    ds:SetFrameLevel(detailPanel:GetFrameLevel() + 1)
    detailScroll = ds
    ds:SetPoint("TOPLEFT", 424, -420); ds:SetSize(422, 140)
    local dc = CreateFrame("Frame", nil, ds); dc:SetSize(420, 240); ds:SetScrollChild(dc)
    detail = Text(dc, 13); detail:SetPoint("TOPLEFT"); detail:SetWidth(412); detail:SetSpacing(4)
    detail:SetText("Select a mob from your collection.")
    local tabLabels = { info = "Details & Places", loot = "Loot", characters = "Characters" }
    for i, name in ipairs({ "info", "loot", "characters" }) do
        local tab = Button(mobPage, tabLabels[name], 147, function()
            activeTab = name; ds:SetVerticalScroll(0); ML.Refresh()
        end)
        tab:SetPoint("TOPLEFT", 410 + (i - 1) * 157, -382)
        tabs[name] = tab
    end
    local add = Button(mobPage, "Confirm dead target", 185, ML.ConfirmTarget); add:SetPoint("BOTTOMLEFT", 26, 49)
    bulkHostile = Button(mobPage, "Unknown -> Hostile", 165, function()
        ML.Print(string.format("Marked %d unknown NPC types as Hostile. Use the attitude menu to correct individual entries.", ML.MarkUnknownHostile()))
    end)
    bulkHostile:SetPoint("BOTTOMLEFT", 230, 49)
    bulkHostile:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("Mark unknown NPCs as Hostile", 0.92, 0.76, 0.45)
        GameTooltip:AddLine(string.format("Applies a manual override to %d NPC types. Known Friendly and Neutral entries are unchanged.", self.unknownCount or 0), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    bulkHostile:SetScript("OnLeave", function() GameTooltip:Hide() end)
    attitudeButton = Button(mobPage, "Set attitude", 180, function() attitudeMenu:SetShown(not attitudeMenu:IsShown()) end)
    attitudeButton:SetPoint("BOTTOMLEFT", 424, 49)
    nameGroupButton = Button(mobPage, "Group same name", 240, function()
        local mob = selected and ML.db.mobs[selected]
        if not mob then return end
        local enabled = ML.db.nameGroups and ML.db.nameGroups[mob.name]
        ML.SetNameGrouping(selected, not enabled)
        ML.Refresh()
    end)
    nameGroupButton:SetPoint("BOTTOMLEFT", 620, 49)
    nameGroupButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Personal grouping override", 0.92, 0.76, 0.45)
        GameTooltip:AddLine("Group every recorded NPC with this exact name, even without a shared Display ID. Saved account-wide; source records and loot rates stay separate. Restore auto grouping to undo.", 0.85, 0.82, 0.74, true)
        GameTooltip:Show()
    end)
    nameGroupButton:SetScript("OnLeave", function() GameTooltip:Hide() end)
    attitudeMenu = Panel(mobPage); attitudeMenu:SetSize(200, 144)
    attitudeMenu:SetPoint("BOTTOMLEFT", attitudeButton, "TOPLEFT", 0, 2)
    attitudeMenu:SetFrameLevel(window:GetFrameLevel() + 60); attitudeMenu:Hide()
    for i, choice in ipairs({ {key = "auto", label = "Auto (observed)"}, {key = "friendly", label = "Friendly"},
        {key = "neutral", label = "Neutral"}, {key = "hostile", label = "Hostile"}, {key = "unknown", label = "Unknown"} }) do
        local option = Button(attitudeMenu, choice.label, 182, function()
            if selected then ML.SetAttitude(selected, choice.key); ML.Refresh() end
            attitudeMenu:Hide()
        end)
        option:SetPoint("TOPLEFT", 9, -7 - (i - 1) * 26); option:SetHeight(25)
    end
    ML.BuildFooterNote(mobPage,Text,"Instances: loot-based records. Open world: observed deaths and loot.\nTracking is best effort. Hover for details.",
        "Instances: loot-based records. Open world: observed deaths and loot.\nRestricted WoW data can prevent recording. Participation does not prove a killing blow.")
    itemPage = ML.BuildItemBrowser(window, { Text = Text, Panel = Panel, Button = Button })
    sessionPage = ML.BuildSessionReport(window, { Text = Text, Panel = Panel, Button = Button })
    areaPage = ML.BuildAreas(window, { Text = Text, Panel = Panel, Button = Button })
    for i, name in ipairs({ "mobs", "items", "session", "areas" }) do
        local tab = Button(window, ({mobs = "Mobs", items = "Items", session = "Session", areas = "Areas"})[name], 90, function() ML.SelectPage(name) end)
        tab:SetPoint("TOP", (i - 2.5) * 100, -18)
        pageTabs[name] = tab
    end
    pageTabs.mobs.selectedMark:Show()
    ML.UpdateNavigationButtons()
end
function ML.OpenSessionReport()
    if not window then Build() end
    window:Show()
    ML.SelectPage("session")
end
function ML.ShowMob(id)
    ML.EnsureCatalog()
    if not window then Build() end
    window:Show()
    ML.OpenMob(id)
end
function ML.Toggle()
    ML.EnsureCatalog()
    if not window or not window:IsShown() then
        closedGroups = ML.DefaultClosedGroups()
        ML.db.closedGroups = closedGroups
    end
    if not window then Build(); ML.Refresh(); return end
    window:SetShown(not window:IsShown())
    if window:IsShown() then sortButton:UpdateLabel(); ML.Refresh() end
end

function ML.UpdateNavigationButtons()
    if not backButton then return end
    backButton:SetEnabled(#history>0)
    resetFiltersButton:SetEnabled(currentPage~="session"); currentAreaButton:SetEnabled(currentPage~="session")
end
function ML.PushView()
    if restoringView or not window or not window:IsShown() then return end
    local state={page=currentPage}
    if currentPage=="mobs" then
        state.view={selected=selected,query=search:GetText(),type=typeFilter,rank=collectionFilter,area=catalogArea,
            closed=ML.CopyViewTable(closedGroups),tab=activeTab,page=catalogPage,left=list:GetVerticalScroll(),right=detailScroll:GetVerticalScroll(),
            sort=ML.GetSortMode("mobs"),lootSort=ML.GetSortMode("mobLoot"),lootClosed=mobLoot and ML.CopyViewTable(mobLoot.closed),
            locationState=locationBrowser and {closed=ML.CopyViewTable(locationBrowser.closed),page=locationBrowser.page}}
    elseif currentPage=="items" then state.view=ML.GetItemsView()
    elseif currentPage=="areas" then state.view=ML.GetAreasView()
    else state.view=ML.GetSessionView() end
    if #history>=20 then table.remove(history,1) end
    history[#history+1]=state; ML.UpdateNavigationButtons()
end
function ML.GoBack()
    local state=table.remove(history)
    if not state then return end
    restoringView=true
    ML.SelectPage(state.page,true)
    if state.page=="mobs" then
        local view=state.view
        catalogArea=view.area or "all"; catalogAreaButton:SetSelection(catalogArea,false)
        ML.SetMobTypeFilter(view.type or "all"); ML.SetCollectionFilter(view.rank or "all")
        closedGroups=ML.CopyViewTable(view.closed); ML.db.closedGroups=closedGroups
        ML.db.sortModes=ML.db.sortModes or {}; ML.db.sortModes.mobs=view.sort; ML.db.sortModes.mobLoot=view.lootSort
        activeTab=view.tab or "info"
        if mobLoot and view.lootClosed then mobLoot.closed=ML.CopyViewTable(view.lootClosed) end
        if locationBrowser and view.locationState then locationBrowser.closed=ML.CopyViewTable(view.locationState.closed) end
        search:SetText(view.query or ""); selected=view.selected
        ML.Refresh(); catalogPage=view.page or 1; ML.Refresh()
        local mob=selected and ML.GetMob(selected)
        if mob then
            Details(mob)
            if locationBrowser and activeTab=="info" and view.locationState then
                locationBrowser.page=view.locationState.page or 1; locationBrowser:Show(mob,detail:GetStringHeight()+10)
            end
        end
        ML.SetViewScroll(list,view.left); ML.SetViewScroll(detailScroll,view.right)
    elseif state.page=="items" then ML.RestoreItemsView(state.view)
    elseif state.page=="areas" then ML.RestoreAreasView(state.view)
    else ML.RestoreSessionView(state.view) end
    ML.UpdateSortLabels(); restoringView=false; ML.UpdateNavigationButtons()
end
function ML.OpenItem(id)
    ML.PushView(); ML.SelectPage("items",true); ML.FocusItem(id)
end
function ML.ResetCurrentFilters()
    ML.PushView()
    if currentPage=="mobs" then
        catalogArea="all"; catalogAreaButton:Reset(); search:SetText("")
        ML.SetMobTypeFilter("all"); ML.SetCollectionFilter("all"); list:SetVerticalScroll(0); ML.Refresh()
    elseif currentPage=="items" then ML.ResetItemsFilters()
    elseif currentPage=="areas" then ML.ResetAreasFilters() end
end
function ML.UseCurrentArea()
    local filter=ML.CurrentAreaFilter()
    if not filter then ML.Print("Current area is unavailable."); return end
    ML.PushView()
    if currentPage=="mobs" then catalogAreaButton:SetSelection(filter,true)
    elseif currentPage=="items" then ML.UseItemsCurrentArea(filter)
    elseif currentPage=="areas" then ML.UseAreasCurrentArea(filter) end
end

function ML.IsMobLogVisible() return window and window:IsShown() end
function ML.RefreshCatalogStatus()
    local header=groupRows.catalogUnavailable
    if header and header:IsVisible() then header.label:SetText(ML.CatalogUnavailableText() or "Catalog ready") end
    if ML.RefreshItemCatalogStatus then ML.RefreshItemCatalogStatus() end
end
