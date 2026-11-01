-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local page, search, heading, summary, empty, areaList, mobList, selected
local areas = {}
local regionFilter, areaFilter = "all", nil
local regionButton, areaButton, regionMenu, areaMenu, regionChoices, areaChoices
local regionCache = {}
local worldFilter = "all"
local worldButton, worldMenu, worldChoices
local worldCache = {}
local currentCatalog = {}

local function RegionWorld(regionKey, regionName)
    if worldCache[regionKey] then return unpack(worldCache[regionKey]) end
    local id = tonumber(regionKey:match("^map:(%d+)$"))
    if id and C_Map and C_Map.GetMapInfo and Enum and Enum.UIMapType then
        local visited = {}
        for _ = 1, 24 do
            if visited[id] then break end
            visited[id] = true
            local info = C_Map.GetMapInfo(id)
            if not info then break end
            local kind, name, parent = ML.Public(info.mapType), ML.Public(info.name), ML.Public(info.parentMapID)
            if kind == Enum.UIMapType.World and type(name) == "string" then
                worldCache[regionKey] = {"map:" .. id, name}
                return "map:" .. id, name
            end
            if type(parent) ~= "number" or parent <= 0 then break end
            id = parent
        end
        -- Some continents are direct children of the cosmic map, without a World level.
        return regionKey, regionName
    end
    return "other", "Other worlds"
end

local function HideMenus()
    if worldMenu then worldMenu:Hide() end
    if regionMenu then regionMenu:Hide() end
    if areaMenu then areaMenu:Hide() end
end

local function FollowArea(area)
    local keys = {}
    for key in pairs(area.regions) do keys[#keys + 1] = key end
    table.sort(keys)
    local region = area.regions[regionFilter] and regionFilter or keys[1]
    if region then regionFilter = region; worldFilter = RegionWorld(region, area.regions[region]) end
end

local function MapRegion(mapID)
    if type(mapID) ~= "number" or mapID <= 0 or not C_Map or not C_Map.GetMapInfo then return "other", "Other areas" end
    local cached = regionCache[mapID]
    if cached and (not cached[3] or GetTime() < cached[3]) then return cached[1], cached[2] end
    local id, visited = mapID, {}
    for _ = 1, 24 do
        if visited[id] then break end
        visited[id] = true
        local info = C_Map.GetMapInfo(id)
        if not info then break end
        local kind, parent, name = ML.Public(info.mapType), ML.Public(info.parentMapID), ML.Public(info.name)
        if Enum and Enum.UIMapType and kind == Enum.UIMapType.Continent and type(name) == "string" then
            local key = "map:" .. id
            regionCache[mapID] = {key, name}
            return key, name
        end
        if type(parent) ~= "number" or parent <= 0 then break end
        id = parent
    end
    regionCache[mapID] = {"other", "Other areas", GetTime() + 30}
    return "other", "Other areas"
end

-- Shared ancestry logic for the creature/item navigation.
ML.MapRegion, ML.RegionWorld = MapRegion, RegionWorld

-- Aggregate recorded zone totals, not coordinate points: a corpse must not be
-- counted again for every saved waypoint. A visual NPC group counts once per zone.
function ML.AreaCatalog(groups, query)
    groups = groups or ML.BuildMobGroups()
    local byZone, result = {}, {}
    query = string.lower(query or "")
    for _, group in ipairs(groups) do
        local localEntries = {}
        local function AddPlaces(places, field)
            for _, place in pairs(places or {}) do
                local zone = type(place.zone) == "string" and place.zone ~= "" and place.zone or "Unknown location"
                local entry = localEntries[zone] or {mob = group, kills = 0, sightings = 0, regions = {},last=0,lastOrder=0,id=group.id,name=group.name}
                localEntries[zone] = entry
                entry[field] = entry[field] + (place.count or 0)
                if (place.last or 0)>entry.last or ((place.last or 0)==entry.last and (place.lastOrder or 0)>entry.lastOrder) then
                    entry.last,entry.lastOrder=place.last or 0,place.lastOrder or 0
                end
                local regionKey, regionName = MapRegion(place.map)
                entry.regions[regionKey] = regionName
            end
        end
        AddPlaces(group.places, "kills")
        AddPlaces(group.sightingPlaces, "sightings")
        if not next(localEntries) then
            localEntries["Unknown location"] = {mob = group, kills = group.count or 0, sightings = group.sightings or 0, regions = {other = "Other areas"},last=group.last or 0,id=group.id,name=group.name}
        end
        for zone, entry in pairs(localEntries) do
            local area = byZone[zone]
            if not area then
                area = {id=zone,name = zone, entries = {}, regions = {},last=0,lastOrder=0, kills = 0, killed = 0, seenOnly = 0, ranks = {bronze = 0, silver = 0, gold = 0, master = 0}}
                byZone[zone] = area
            end
            area.entries[#area.entries + 1] = entry
            for key, name in pairs(entry.regions) do area.regions[key] = name end
            area.kills = area.kills + entry.kills
            if entry.last>area.last or (entry.last==area.last and (entry.lastOrder or 0)>area.lastOrder) then
                area.last,area.lastOrder=entry.last,entry.lastOrder or 0
            end
            if entry.kills > 0 then area.killed = area.killed + 1 else area.seenOnly = area.seenOnly + 1 end
            local rank = ML.KillRank(group.count)
            if rank then area.ranks[rank.key] = area.ranks[rank.key] + 1 end
        end
    end
    for zone, area in pairs(byZone) do
        if string.find(string.lower(zone), query, 1, true) then
            local mode=ML.GetSortMode("areaMobs")
            table.sort(area.entries,function(a,b) return ML.SortBefore(a,b,mode) end)
            result[#result + 1] = area
        end
    end
    table.sort(result,function(a,b) return ML.SortBefore(a,b,ML.GetSortMode("areas")) end)
    return result
end

-- Both columns recycle a small viewport pool, even for large area collections.
local function RenderList(state)
    if not page:IsVisible() then return end
    local offset = state.scroll:GetVerticalScroll() or 0
    local first = math.max(1, math.floor(offset / state.stride))
    local last = math.min(#state.entries, math.ceil((offset + state.scroll:GetHeight()) / state.stride) + 1)
    local used = 0
    for index = first, last do
        used = used + 1
        local row = state.rows[used]
        if not row then
            row = CreateFrame("Button", nil, state.content, "BackdropTemplate")
            row:SetSize(state.width, state.stride - 4)
            row:SetBackdrop({bgFile = "Interface\\Buttons\\WHITE8X8"})
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.title = state.Text(row, 13); row.title:SetPoint("TOPLEFT", 10, -9); row.title:SetSize(state.width - 20, 18); row.title:SetWordWrap(false)
            row.subtitle = state.Text(row, 10); row.subtitle:SetPoint("TOPLEFT", 10, -31); row.subtitle:SetSize(state.width - 20, 16); row.subtitle:SetWordWrap(false)
            row:SetScript("OnClick", function(self) state.click(self.entry) end)
            state.rows[used] = row
        end
        row.entry = state.entries[index]
        row:SetPoint("TOPLEFT", 0, -(index - 1) * state.stride)
        if row.portrait then row.portrait:Hide() end
        state.update(row, row.entry)
        row:Show()
    end
    for index = used + 1, #state.rows do state.rows[index]:Hide() end
end

local function FillList(state, entries)
    state.entries = entries
    local height = math.max(1, #entries * state.stride)
    state.content:SetHeight(height)
    local maximum = math.max(0, height - state.scroll:GetHeight())
    if state.scroll:GetVerticalScroll() > maximum then state.scroll:SetVerticalScroll(maximum) end
    RenderList(state)
end

function ML.RefreshAreas(groups)
    if not page or not page:IsVisible() then return end
    local catalog = ML.AreaCatalog(groups)
    currentCatalog = catalog
    local worlds, worldOptions = {all = "All worlds"}, {}
    for _, area in ipairs(catalog) do
        for key, name in pairs(area.regions) do local worldKey, worldName = RegionWorld(key, name); worlds[worldKey] = worldName end
    end
    if not worlds[worldFilter] then worldFilter = "all" end
    for key, name in pairs(worlds) do if key ~= "all" then worldOptions[#worldOptions + 1] = {key = key, label = name} end end
    table.sort(worldOptions, function(a, b) return string.lower(a.label) < string.lower(b.label) end)
    table.insert(worldOptions, 1, {key = "all", label = "All worlds"})
    local regions = {all = "All regions"}
    for _, area in ipairs(catalog) do
        for key, name in pairs(area.regions) do
            local worldKey = RegionWorld(key, name)
            if worldFilter == "all" or worldKey == worldFilter then regions[key] = name end
        end
    end
    if not regions[regionFilter] then regionFilter = "all" end
    local regionOptions = {}
    for key, name in pairs(regions) do if key ~= "all" then regionOptions[#regionOptions + 1] = {key = key, label = name} end end
    table.sort(regionOptions, function(a, b) return string.lower(a.label) < string.lower(b.label) end)
    table.insert(regionOptions, 1, {key = "all", label = "All regions"})
    local areaOptions, available = {{key = "all", label = "All areas"}}, {}
    for _, area in ipairs(catalog) do
        local matchesWorld = worldFilter == "all"
        for key, name in pairs(area.regions) do if RegionWorld(key, name) == worldFilter then matchesWorld = true end end
        if matchesWorld and (regionFilter == "all" or area.regions[regionFilter]) then
            available[#available + 1] = area
            areaOptions[#areaOptions + 1] = {key = area.name, label = area.name}
        end
    end
    local found = areaFilter == nil
    for _, area in ipairs(available) do if area.name == areaFilter then found = true end end
    if not found then areaFilter = nil end
    worldButton.label:SetText(worlds[worldFilter] .. "  v")
    regionButton.label:SetText(regions[regionFilter] .. "  v")
    areaButton.label:SetText((areaFilter or selected or "All areas") .. "  v")
    FillList(worldChoices, worldOptions); FillList(regionChoices, regionOptions); FillList(areaChoices, areaOptions)
    local query = string.lower(search:GetText() or "")
    areas = {}
    for _, area in ipairs(available) do
        if (not areaFilter or area.name == areaFilter) and string.find(string.lower(area.name), query, 1, true) then areas[#areas + 1] = area end
    end
    local chosen
    for _, area in ipairs(areas) do if area.name == selected then chosen = area; break end end
    if not chosen then
        local current = GetRealZoneText()
        for _, area in ipairs(areas) do if area.name == current then chosen = area; break end end
        chosen = chosen or areas[1]
        selected = chosen and chosen.name
        mobList.scroll:SetVerticalScroll(0)
    end
    FillList(areaList, areas)
    FillList(mobList, chosen and chosen.entries or {})
    empty:SetShown(#areas == 0)
    heading:SetText(chosen and chosen.name or "Select an area")
    areaButton.label:SetText((chosen and chosen.name or areaFilter or "All areas") .. "  v")
    if chosen then
        local ranks = {}
        for _, rank in ipairs(ML.KillRanks) do ranks[#ranks + 1] = "|c" .. rank.hex .. chosen.ranks[rank.key] .. " " .. rank.label .. "|r" end
        summary:SetText(string.format("%d discovered entries · %d killed here · %d seen only here\n%d local kill records\n", #chosen.entries, chosen.killed, chosen.seenOnly, chosen.kills) ..
            table.concat(ranks, " · ") .. "\nRanks use account-wide kills. Click an entry to open its bestiary page.")
    else summary:SetText("No areas match your search. Record an encounter to add its location.") end
end

function ML.BuildAreas(parent, ui)
    page = CreateFrame("Frame", nil, parent); page:SetAllPoints()
    local label = ui.Text(page, 10); label:SetPoint("TOPLEFT", 28, -173); label:SetText("SEARCH YOUR RECORDED AREAS")
    search = CreateFrame("EditBox", nil, page, "InputBoxTemplate")
    search:SetPoint("TOPLEFT", 34, -191); search:SetSize(160, 28); search:SetAutoFocus(false)
    search:SetScript("OnTextChanged", function()
        if not areaList then return end
        areaList.scroll:SetVerticalScroll(0); ML.RefreshAreas()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    ML.BuildSortDropdown(page,ui,"areas","mobs",206,-191,164,function()
        areaList.scroll:SetVerticalScroll(0); ML.RefreshAreas()
    end)
    search:SetScript("OnEditFocusGained", HideMenus)
    local function List(parentFrame, x, y, width, height, update, click)
        local viewport = CreateFrame("Frame", nil, parentFrame)
        viewport:SetPoint("TOPLEFT", x, y); viewport:SetSize(width + 26, height); viewport:SetClipsChildren(true)
        local scrollFrame = CreateFrame("ScrollFrame", nil, viewport, "UIPanelScrollFrameTemplate")
        scrollFrame:SetPoint("TOPLEFT"); scrollFrame:SetSize(width, height)
        local contentFrame = CreateFrame("Frame", nil, scrollFrame); contentFrame:SetSize(width - 4, 1); scrollFrame:SetScrollChild(contentFrame)
        local state = {scroll = scrollFrame, content = contentFrame, width = width - 4, stride = 58, rows = {}, entries = {}, Text = ui.Text, update = update, click = click}
        scrollFrame:HookScript("OnVerticalScroll", function() RenderList(state) end)
        return state
    end
    areaList = List(page, 26, -230, 344, 330, function(row, area)
        row.title:SetText(area.name)
        row.subtitle:SetText(string.format("%d entries · %d local kills", #area.entries, area.kills))
        row:SetBackdropColor(area.name == selected and 0.16 or 0.065, area.name == selected and 0.12 or 0.055, 0.04, 1)
    end, function(area)
        if selected~=area.name then ML.PushView() end
        selected = area.name; FollowArea(area); mobList.scroll:SetVerticalScroll(0); ML.RefreshAreas()
    end)
    local panel = ui.Panel(page); panel:SetPoint("TOPLEFT", 410, -176); panel:SetSize(462, 392)
    heading = ui.Text(panel, 17, {0.92, 0.76, 0.45}); heading:SetPoint("TOPLEFT", 14, -14); heading:SetSize(430, 24); heading:SetWordWrap(false)
    summary = ui.Text(panel, 11); summary:SetPoint("TOPLEFT", 14, -47); summary:SetSize(430, 78)
    ML.BuildSortDropdown(panel,ui,"areaMobs","mobs",282,-129,164,function()
        mobList.scroll:SetVerticalScroll(0); ML.RefreshAreas()
    end)
    mobList = List(panel, 12, -166, 422, 211, function(row, entry)
        if not row.portrait then row.portrait=ML.CreateMobPortrait(row,36); row.portrait:SetPoint("LEFT",10,0) end
        row.portrait:Show(); ML.UpdateMobPortrait(row.portrait,entry.mob)
        row.title:SetPoint("TOPLEFT",70,-9); row.title:SetWidth(336)
        row.subtitle:SetPoint("TOPLEFT",70,-31); row.subtitle:SetWidth(336)
        row.title:SetText(entry.mob.name)
        local rank = ML.KillRank(entry.mob.count)
        local rankText = rank and ("|c" .. rank.hex .. rank.label .. "|r") or "Unranked"
        row.subtitle:SetText(string.format("%d local kills · %d sightings · %s", entry.kills, entry.sightings, rankText))
        row:SetBackdropColor(0.075, 0.06, 0.04, 1)
    end, function(entry) ML.OpenMob(entry.mob.representativeID or entry.mob.id) end)
    empty = ui.Text(page, 13); empty:SetPoint("TOPLEFT", 36, -246); empty:SetWidth(310); empty:SetText("No recorded areas match your search and filters.")
    local navigation = ui.Panel(page); navigation:SetPoint("TOPLEFT", 26, -126); navigation:SetSize(846, 36)
    -- A single opaque strip under all segments prevents dark gaps between buttons.
    local strip = navigation:CreateTexture(nil, "ARTWORK")
    strip:SetColorTexture(0.16, 0.15, 0.14, 1)
    strip:SetPoint("TOPLEFT", 4, -4); strip:SetPoint("BOTTOMRIGHT", -4, 4)
    local function Crumb(x, width, callback)
        local button = CreateFrame("Button", nil, navigation)
        button:SetPoint("LEFT", x, 0); button:SetSize(width, 28)
        button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        button.label = ui.Text(button, 13, {1, 0.82, 0})
        button.label:SetPoint("LEFT", 15, 0); button.label:SetSize(width - 37, 20); button.label:SetWordWrap(false)
        for _, edge in ipairs({{y=6, angle=math.pi/4}, {y=-6, angle=-math.pi/4}}) do
            local texture = button:CreateTexture(nil, "OVERLAY")
            texture:SetColorTexture(0.65, 0.60, 0.52, 1); texture:SetSize(2, 18)
            texture:SetPoint("RIGHT", -6, edge.y); texture:SetRotation(edge.angle)
        end
        button:SetScript("OnClick", callback)
        button:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(self.label:GetText(), 1, 0.82, 0); GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        return button
    end
    worldButton = Crumb(4, 220, function()
        local show = not worldMenu:IsShown(); HideMenus(); worldMenu:SetShown(show)
    end)
    regionButton = Crumb(224, 260, function()
        local show = not regionMenu:IsShown(); HideMenus(); regionMenu:SetShown(show)
    end)
    areaButton = Crumb(484, 358, function()
        local show = not areaMenu:IsShown(); HideMenus(); areaMenu:SetShown(show)
    end)
    local function Menu(button, click)
        local menu = ui.Panel(page); menu:SetSize(344, 250)
        if button == areaButton then menu:SetPoint("TOPRIGHT", button, "BOTTOMRIGHT", 0, -5)
        else menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -5) end
        menu:SetFrameLevel(page:GetFrameLevel() + 70)
        local state = List(menu, 10, -10, 296, 230, function(row, entry)
            row.title:SetPoint("TOPLEFT", 10, -5)
            row.title:SetText(entry.label); row.subtitle:SetText(""); row:SetBackdropColor(0.075, 0.06, 0.04, 1)
        end, function(entry) menu:Hide(); click(entry.key) end)
        state.stride = 30
        menu:Hide()
        return menu, state
    end
    worldMenu, worldChoices = Menu(worldButton, function(key)
        worldFilter, regionFilter, areaFilter, selected = key, "all", nil, nil
        regionChoices.scroll:SetVerticalScroll(0); areaChoices.scroll:SetVerticalScroll(0)
        areaList.scroll:SetVerticalScroll(0); ML.RefreshAreas()
    end)
    regionMenu, regionChoices = Menu(regionButton, function(key)
        regionFilter, areaFilter, selected = key, nil, nil
        areaChoices.scroll:SetVerticalScroll(0); areaList.scroll:SetVerticalScroll(0); ML.RefreshAreas()
    end)
    areaMenu, areaChoices = Menu(areaButton, function(key)
        areaFilter = key ~= "all" and key or nil; selected = nil
        if areaFilter then
            for _, area in ipairs(currentCatalog) do if area.name == areaFilter then FollowArea(area); break end end
        end
        areaList.scroll:SetVerticalScroll(0); mobList.scroll:SetVerticalScroll(0); ML.RefreshAreas()
    end)
    page:SetScript("OnHide", HideMenus)
    ML.BuildFooterNote(page,ui.Text,"Your discoveries and recorded player locations.\nLocal kill counts; account-wide collection ranks. Hover for details.",
        "Your discoveries only: no complete zone checklist or completion percentage. Locations reflect your position when recorded.\nLocal counts use saved zone records; ranks use account-wide group totals. Instances remain loot-based only.")
    page:Hide()
    return page
end

function ML.GetAreasView()
    return {world=worldFilter,region=regionFilter,area=areaFilter,selected=selected,query=search:GetText(),
        left=areaList.scroll:GetVerticalScroll(),right=mobList.scroll:GetVerticalScroll(),sort=ML.GetSortMode("areas"),mobSort=ML.GetSortMode("areaMobs")}
end
function ML.RestoreAreasView(state)
    worldFilter,regionFilter,areaFilter,selected=state.world or "all",state.region or "all",state.area,state.selected
    ML.db.sortModes=ML.db.sortModes or {}; ML.db.sortModes.areas=state.sort; ML.db.sortModes.areaMobs=state.mobSort
    search:SetText(state.query or ""); ML.RefreshAreas(); ML.SetViewScroll(areaList.scroll,state.left); ML.SetViewScroll(mobList.scroll,state.right)
end
function ML.ResetAreasFilters()
    worldFilter,regionFilter,areaFilter="all","all",nil
    search:SetText(""); ML.RefreshAreas(); areaList.scroll:SetVerticalScroll(0); mobList.scroll:SetVerticalScroll(0)
end
function ML.UseAreasCurrentArea(filter)
    worldFilter,regionFilter,areaFilter,selected=filter.world,filter.region,filter.area,filter.area
    search:SetText(""); ML.RefreshAreas(); areaList.scroll:SetVerticalScroll(0); mobList.scroll:SetVerticalScroll(0)
end
