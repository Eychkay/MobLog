-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

local view, refresh
local metadata = {}
local tooltipRequests = {}
local filters = {
    { label = "All item types" },
    { label = "Equipment", classes = { [2] = true, [4] = true } },
    { label = "Consumables", classes = { [0] = true } },
    { label = "Materials", classes = { [5] = true, [7] = true } },
}
local ink = { 0.24, 0.14, 0.07 }
local muted = { 0.34, 0.21, 0.10 }
local itemInk = { 1, 1, 1 }
local itemCountInk = { 0.94, 0.85, 0.67 }

local function OwnerName(owner)
    if owner == "shared" then return ML.InventoryBankName() end
    local character = ML.db.characters[owner]
    return character and (character.name .. (character.realm and (" - " .. character.realm) or "")) or "Unknown character"
end

local function InventoryText(ui, parent, size, x, y, width, height, color)
    local text = ui.Text(parent, size, color or ink)
    text:SetPoint("TOPLEFT", x, y)
    text:SetSize(width, height)
    text:SetShadowColor(0, 0, 0, 0)
    text:SetWordWrap(false)
    return text
end

local function Paper(parent, x, width)
    local leaf = CreateFrame("Frame", nil, parent)
    leaf:SetPoint("TOPLEFT", x, -237)
    leaf:SetSize(width, 338)
    local texture = leaf:CreateTexture(nil, "BACKGROUND")
    texture:SetAllPoints()
    if C_Texture and C_Texture.GetAtlasInfo("QuestBG-Parchment") then
        texture:SetAtlas("QuestBG-Parchment")
    else
        texture:SetTexture("Interface\\QuestFrame\\QuestBG")
    end
    texture:SetVertexColor(0.97, 0.93, 0.84)
    return leaf
end

local function ScrollList(parent, top, width, height, stride, createRow, bindRow)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 17, top)
    scroll:SetSize(width, height)
    scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(width, 1)
    scroll:SetScrollChild(content)
    local rows, entries = {}, {}
    local poolSize = math.ceil(height / stride) + 1
    local function Draw()
        local owner = GameTooltip:GetOwner()
        local owned = owner and owner:GetParent() == content
        local previous = owned and owner.entry
        local first = math.floor(scroll:GetVerticalScroll() / stride) + 1
        local last = math.min(#entries, first + poolSize - 1)
        for index = first, last do
            local slot = (index - 1) % poolSize + 1
            local row = rows[slot] or createRow(content, width)
            rows[slot] = row
            row.index, row.entry = index, entries[index]
            row:SetPoint("TOPLEFT", 0, -(index - 1) * stride)
            bindRow(row, row.entry)
            row:Show()
        end
        local hovered
        for _, row in pairs(rows) do
            if row.index < first or row.index > last then
                row.entry = nil
                row:Hide()
            elseif owned and scroll:IsMouseOver() and row:IsMouseOver() then
                hovered = row
            end
        end
        if owned and (not hovered or hovered ~= owner or hovered.entry ~= previous) then
            if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
            if hovered and hovered.ShowEntryTooltip then hovered:ShowEntryTooltip() end
        end
    end
    scroll:HookScript("OnVerticalScroll", Draw)
    function scroll:SetEntries(values)
        entries = values
        local size = #entries * stride
        content:SetHeight(math.max(1, size))
        self:SetVerticalScroll(math.min(self:GetVerticalScroll(), math.max(0, size - height)))
        Draw()
    end
    return scroll
end

local function ItemDetails(item)
    local info = metadata[item.id]
    if not info then
        local name, link, quality, _, _, _, _, _, _, icon, _, class = C_Item.GetItemInfo(item.id)
        if not name and C_Item.GetItemInfoInstant then
            local _, _, _, _, instantIcon, instantClass = C_Item.GetItemInfoInstant(item.id)
            icon, class = instantIcon, instantClass
        end
        info = { name = name, link = link, quality = quality, icon = icon, class = class }
        metadata[item.id] = info
    end
    local name = info.name or (item.link and item.link:match("%[(.-)%]")) or ("Item #" .. item.id)
    local rarity = info.quality or item.quality
    return name, item.link or info.link, item.icon or info.icon, info.class, rarity
end

local function ShowItemTooltip(button)
    local entry = button.entry
    if not entry then return end
    local tooltip = GameTooltip
    tooltip:SetOwner(button, "ANCHOR_RIGHT")
    local baseLink = "item:" .. entry.id
    local link = entry.link and entry.link:match("|H(item:[^|]+)|h")
    local ok
    if link and tonumber(link:match("^item:(%d+)")) == entry.id then
        ok = pcall(tooltip.SetHyperlink, tooltip, link)
    end
    if not ok or tooltip:NumLines() == 0 then
        tooltip:ClearLines()
        ok = pcall(tooltip.SetHyperlink, tooltip, baseLink)
    end
    local empty = not ok or tooltip:NumLines() == 0
    if empty then
        tooltip:SetText(entry.name)
        tooltip:AddLine("Item #" .. entry.id, 0.7, 0.7, 0.7)
        ML.AddInventoryItemTooltip(tooltip, entry.id)
    end
    tooltip:Show()
    if C_Item.RequestLoadItemDataByID and (empty or (C_Item.IsItemDataCachedByID and not C_Item.IsItemDataCachedByID(entry.id))) then
        local now = GetTime()
        if not tooltipRequests[entry.id] or now - tooltipRequests[entry.id] >= 5 then
            tooltipRequests[entry.id] = now
            pcall(C_Item.RequestLoadItemDataByID, entry.id)
        end
    end
end

local function ItemNameBefore(a, b)
    if strcmputf8i then
        local order = strcmputf8i(a.name, b.name)
        if order == 0 then return a.id < b.id end
        return order < 0
    end
    return ML.SortBefore(a, b, "az")
end

local function FormatMoney(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper, 13) end
    return string.format("%dg %02ds %02dc", math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100)
end

local function CoinDisplay(copper)
    local coins = "Interface\\MoneyFrame\\UI-"
    return string.format("%d |T%sGoldIcon:14:14|t  %02d |T%sSilverIcon:14:14|t  %02d |T%sCopperIcon:14:14|t",
        math.floor(copper / 10000), coins, math.floor(copper / 100) % 100, coins, copper % 100, coins)
end

local function DrawLocations(title, summary, locations)
    view.itemTitle:SetText(title)
    view.itemSummary:SetText(summary)
    if view.showGold then view.gold:SetBackdropBorderColor(0.96, 0.75, 0.31)
    else view.gold:SetBackdropBorderColor(0.62, 0.47, 0.26) end
    view.sources:SetShown(not view.showGold)
    view.locations:SetEntries(locations)
end

function ML.RefreshInventoryGold()
    if not view or not view.frame:IsVisible() then return end
    local balances, total = {}, 0
    local function AddBalance(owner, money)
        if not money then return end
        balances[#balances + 1] = { owner = owner, count = money.amount, stamp = money.stamp }
        total = total + money.amount
    end
    for guid, saved in pairs(ML.InventoryCharacters()) do AddBalance(guid, saved.money) end
    AddBalance("shared", ML.InventorySharedMoney())
    view.gold.amount:SetText(CoinDisplay(total))
    if not view.showGold then return end
    table.sort(balances, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return OwnerName(a.owner) < OwnerName(b.owner)
    end)
    local summary = #balances > 0 and ("Recorded total · " .. FormatMoney(total)) or "No gold recorded for this selection yet."
    DrawLocations("Gold overview", summary, balances)
end

function ML.RefreshInventoryView()
    if view and view.frame:IsVisible() then refresh() end
end

function ML.GetInventoryView()
    return { query = view.search:GetText(), owner = view.owner, filter = view.filter, allFactions = view.allFactions,
        selected = view.selected, itemOffset = view.items:GetVerticalScroll(),
        locationOffset = view.locations:GetVerticalScroll(), showGold = view.showGold }
end

function ML.RestoreInventoryView(state)
    view.owner, view.filter = state.owner, state.filter or 1
    view.allFactions = state.allFactions == true
    view.search:SetText(state.query or "")
    view.selected = state.selected
    view.showGold = state.showGold
    refresh()
    view.factions:GenerateMenu()
    view.owners:GenerateMenu()
    view.types:GenerateMenu()
    ML.SetViewScroll(view.items, state.itemOffset)
    ML.SetViewScroll(view.locations, state.locationOffset)
end

function ML.ResetInventoryFilters()
    ML.RestoreInventoryView({})
end

function ML.FocusInventoryItem(id)
    local allFactions = view.allFactions
    local entry = ML.InventoryIndex()[id]
    if entry and not allFactions then
        allFactions = true
        for _, location in ipairs(entry.locations) do
            if ML.InventoryOwnerFaction(location.owner) then
                allFactions = false
                break
            end
        end
    end
    ML.RestoreInventoryView({ query = tostring(id), selected = id, allFactions = allFactions })
end

function ML.BuildInventoryView(parent, ui)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints()
    view = { frame = page, filter = 1, allFactions = false }
    local function ResetList()
        view.items:SetVerticalScroll(0)
        view.locations:SetVerticalScroll(0)
        refresh()
    end
    view.search = ML.BuildItemSearchField(page, ui.Text)
    view.search:SetScript("OnTextChanged", function(_, userInput) if userInput then ResetList() end end)
    view.factions = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    view.factions:SetPoint("TOPLEFT", 206, -197)
    view.factions:SetWidth(129)
    view.owners = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    view.owners:SetPoint("TOPLEFT", 347, -197)
    view.owners:SetWidth(214)
    view.types = CreateFrame("DropdownButton", nil, page, "WowStyle1DropdownTemplate")
    view.types:SetPoint("TOPLEFT", 573, -197)
    view.types:SetWidth(130)
    view.gold = CreateFrame("Button", nil, page, "BackdropTemplate")
    view.gold:SetSize(157, 27)
    view.gold:SetPoint("TOPRIGHT", -26, -197)
    view.gold:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    view.gold:SetBackdropColor(0.16, 0.12, 0.07, 1)
    view.gold:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    view.gold:SetScript("OnClick", function()
        view.showGold = not view.showGold
        view.locations:SetVerticalScroll(0)
        refresh()
    end)
    view.gold.amount = ui.Text(view.gold, 12)
    view.gold.amount:SetPoint("LEFT", 5, 0)
    view.gold.amount:SetPoint("RIGHT", -5, 0)
    view.gold.amount:SetJustifyH("CENTER")
    view.gold.amount:SetWordWrap(false)
    view.gold:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(view.showGold and "Click to return to item details" or "Click to view the gold breakdown", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    view.gold:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local list, detail = Paper(page, 26, 405), Paper(page, 441, 433)
    local label = InventoryText(ui, list, 18, 18, -13, 300, 23)
    label:SetText("Recorded items")
    view.itemTitle = InventoryText(ui, detail, 19, 18, -13, 394, 24)
    view.itemSummary = InventoryText(ui, detail, 11, 18, -39, 394, 16, muted)
    view.empty = InventoryText(ui, list, 13, 18, -56, 365, 56)
    view.empty:SetWordWrap(true)
    view.coverage = ui.Text(page, 11)
    view.coverage:SetPoint("TOPLEFT", 29, -583)
    view.coverage:SetSize(840, 17)
    view.sources = ui.Button(detail, "View sources", 143, function() ML.OpenItem(view.selected) end)
    view.sources:SetPoint("BOTTOMRIGHT", -18, 10)
    view.sources:SetHeight(24)
    local tooltip = CreateFrame("CheckButton", nil, page, "UICheckButtonTemplate")
    tooltip:SetPoint("BOTTOMLEFT", 24, 11)
    tooltip:SetSize(24, 24)
    tooltip:SetScript("OnClick", function(self) ML.db.options.inventoryTooltip = not not self:GetChecked() end)
    local tooltipLabel = ui.Text(page, 11)
    tooltipLabel:SetPoint("LEFT", tooltip, "RIGHT", 4, 0)
    tooltipLabel:SetText("Show inventory counts on item tooltips")

    view.items = ScrollList(list, -44, 350, 278, 37, function(content, width)
        local row = CreateFrame("Button", nil, content)
        row:SetSize(width, 36)
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints()
        background:SetColorTexture(0.14, 0.10, 0.075, 1)
        local hover = row:CreateTexture(nil, "HIGHLIGHT")
        hover:SetAllPoints()
        hover:SetColorTexture(0.58, 0.42, 0.21, 0.23)
        row.shade = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        row.shade:SetAllPoints()
        row.shade:SetColorTexture(0.28, 0.20, 0.10, 1)
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(27, 27)
        row.icon:SetPoint("LEFT", 6, 0)
        row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        row.title = InventoryText(ui, row, 13, 42, -7, width - 110, 22, itemInk)
        row.quantity = InventoryText(ui, row, 13, width - 55, -7, 47, 22, itemCountInk)
        row.quantity:SetJustifyH("RIGHT")
        row:SetScript("OnClick", function(self)
            view.selected = self.entry.id
            view.showGold = false
            view.locations:SetVerticalScroll(0)
            refresh()
        end)
        row.ShowEntryTooltip = ShowItemTooltip
        row:SetScript("OnEnter", ShowItemTooltip)
        row:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
        return row
    end, function(row, entry)
        row.icon:SetTexture(entry.icon or 134400)
        row.title:SetText(entry.name)
        local color = entry.rarity and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.rarity]
        if color then row.title:SetTextColor(color.r, color.g, color.b)
        else row.title:SetTextColor(unpack(itemInk)) end
        row.quantity:SetText(entry.count)
        row.shade:SetShown(entry.id == view.selected and not view.showGold)
    end)
    view.locations = ScrollList(detail, -62, 379, 236, 45, function(content, width)
        local row = CreateFrame("Button", nil, content)
        row:SetSize(width, 42)
        local rule = row:CreateTexture(nil, "BORDER")
        rule:SetPoint("BOTTOMLEFT"); rule:SetPoint("BOTTOMRIGHT"); rule:SetHeight(1)
        rule:SetColorTexture(0.35, 0.20, 0.09, 0.28)
        row.nameBackground = row:CreateTexture(nil, "BACKGROUND")
        row.nameBackground:SetPoint("TOPLEFT", 0, -2)
        row.nameBackground:SetColorTexture(0.14, 0.10, 0.075, 1)
        row.nameBackground:SetHeight(16)
        row.title = InventoryText(ui, row, 13, 6, -2, width - 169, 16)
        row.subtitle = InventoryText(ui, row, 11, 0, -20, width, 16, muted)
        row.quantity = InventoryText(ui, row, 13, width - 151, -2, 151, 16)
        row.quantity:SetJustifyH("RIGHT")
        function row:ShowEntryTooltip()
            if not self.entry or not self.entry.copies then return end
            local copies, seen = self.entry.copies, {}
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(ML.InventoryLocationName(self.entry), 1, 0.82, 0)
            for _, copy in ipairs(copies) do
                if copy.link and not seen[copy.link] then
                    local level = C_Item.GetDetailedItemLevelInfo and C_Item.GetDetailedItemLevelInfo(copy.link)
                    GameTooltip:AddLine(copy.link .. (level and (" · Item level " .. level) or ""), 1, 1, 1, true)
                    seen[copy.link] = true
                end
            end
            GameTooltip:Show()
        end
        row:SetScript("OnEnter", row.ShowEntryTooltip)
        row:SetScript("OnLeave", function(self) if GameTooltip:IsOwned(self) then GameTooltip:Hide() end end)
        return row
    end, function(row, location)
        local character = location.owner ~= "shared"
        row.title:SetText(character and ML.CharacterName(location.owner) or ML.InventoryBankName())
        row.nameBackground:SetWidth(math.min(row.title:GetStringWidth(), row.title:GetWidth()) + 12)
        row.nameBackground:SetShown(character)
        local balance = not location.kind
        row.quantity:SetText(balance and FormatMoney(location.count) or location.count)
        local place = balance and (location.owner == "shared" and "Shared balance" or "Carried gold") or ML.InventoryLocationName(location)
        local _, faction = ML.InventoryOwnerFaction(location.owner)
        local prefix = faction and ("|cff822a24" .. faction .. "|r · ") or ""
        row.subtitle:SetText(prefix .. place .. " · " .. date("%Y-%m-%d %H:%M", location.stamp))
    end)

    local function SelectOwner(owner)
        view.owner = owner
        ResetList()
    end
    local function SelectFaction(allFactions)
        view.allFactions = allFactions
        ResetList()
        view.owners:GenerateMenu()
    end
    view.factions:SetupMenu(function(_, root)
        root:CreateRadio("Own faction", function() return not view.allFactions end, function() SelectFaction(false) end)
        root:CreateRadio("All factions", function() return view.allFactions end, function() SelectFaction(true) end)
    end)
    view.owners:SetupMenu(function(_, root)
        root:CreateRadio("All characters and storage", function() return not view.owner end, function() SelectOwner(nil) end)
        local characters, shared = ML.InventoryCharacters()
        local owners = {}
        for guid in pairs(characters) do
            if view.allFactions or ML.InventoryOwnerFaction(guid) then owners[#owners + 1] = guid end
        end
        table.sort(owners, function(a, b) return OwnerName(a) < OwnerName(b) end)
        for _, guid in ipairs(owners) do
            root:CreateRadio(ML.InventoryOwnerLabel(guid), function(key) return view.owner == key end, SelectOwner, guid)
        end
        if shared or ML.InventorySharedMoney() then
            root:CreateRadio(ML.InventoryBankName(), function(key) return view.owner == key end, SelectOwner, "shared")
        end
        if #owners > 12 then root:SetScrollMode(300) end
    end)
    view.types:SetupMenu(function(_, root)
        for i, filter in ipairs(filters) do
            root:CreateRadio(filter.label, function(key) return view.filter == key end, function(key)
                view.filter = key
                ResetList()
            end, i)
        end
    end)

    refresh = function()
        local characters, shared = ML.InventoryCharacters()
        local available, count, banks, unknown = { shared = true }, 0, 0, false
        for guid, saved in pairs(characters) do
            local own, faction = ML.InventoryOwnerFaction(guid)
            if view.allFactions or own then
                available[guid] = true
                if saved.bags or saved.equipment then count = count + 1 end
                if saved.bank then banks = banks + 1 end
            elseif faction == "Faction unknown" then
                unknown = true
            end
        end
        if view.owner and not available[view.owner] then
            view.owner = nil
            view.owners:GenerateMenu()
        end
        local query = view.search:GetText():match("^%s*(.-)%s*$"):lower()
        local numeric = query:match("^#?(%d+)$")
        local classes = filters[view.filter].classes
        local entries, selected = {}, nil
        for id, item in pairs(ML.InventoryIndex()) do
            if not numeric or id == tonumber(numeric) then
                local name, link, icon, class, rarity = ItemDetails(item)
                if (not classes or classes[class]) and (numeric or name:lower():find(query, 1, true)) then
                    local locations, count = {}, 0
                    for _, location in ipairs(item.locations) do
                        if available[location.owner] and (not view.owner or view.owner == location.owner) then
                            locations[#locations + 1] = location
                            count = count + location.count
                        end
                    end
                    if count > 0 then
                        local entry = { id = id, name = name, link = link, icon = icon, rarity = rarity, count = count, locations = locations }
                        entries[#entries + 1] = entry
                        if id == view.selected then selected = entry end
                    end
                end
            end
        end
        table.sort(entries, ItemNameBefore)
        if not selected then
            selected = entries[1]
            view.selected = selected and selected.id
            view.locations:SetVerticalScroll(0)
        end
        view.items:SetEntries(entries)
        view.empty:SetShown(#entries == 0)
        view.empty:SetText(view.allFactions and "No matching items in the recorded inventory." or
            "No matching items for your faction and shared storage. Choose All factions to check other characters.")
        local locations = selected and selected.locations or {}
        table.sort(locations, function(a, b)
            if a.owner ~= b.owner then return OwnerName(a.owner) < OwnerName(b.owner) end
            if a.kind ~= b.kind then return a.kind < b.kind end
            return (a.label or "") < (b.label or "")
        end)
        ML.RefreshInventoryGold()
        if not view.showGold then
            local title = selected and selected.name or "Select an item"
            local summary = selected and (selected.count .. " recorded · " .. #locations .. " locations") or ""
            local gathered = selected and ML.db.gatheredItems and ML.db.gatheredItems[selected.id]
            if gathered then summary = summary .. " · Gathering sources recorded" end
            DrawLocations(title, summary, locations)
            view.sources:SetEnabled(selected ~= nil)
        end
        if view.owner == "shared" then
            view.coverage:SetText(shared and (ML.InventoryBankName() .. " checked " .. date("%Y-%m-%d %H:%M", shared.stamp)) or "Shared bank not yet recorded.")
        elseif view.owner then
            local bank = characters[view.owner] and characters[view.owner].bank
            view.coverage:SetText(bank and ("Personal bank checked " .. date("%Y-%m-%d %H:%M", bank.stamp)) or "Personal bank not yet recorded. Open it on this character.")
        else
            local hint = unknown and "Log in on older characters to record their faction." or
                "Log in on each character and open their bank to add its contents."
            view.coverage:SetText(string.format("%d characters in view · %d personal banks checked · %s", count, banks, hint))
        end
    end
    page:SetScript("OnShow", function()
        tooltip:SetChecked(ML.db.options.inventoryTooltip ~= false)
        refresh()
        view.owners:GenerateMenu()
    end)
    page:SetScript("OnHide", function()
        view.search:ClearFocus()
        view.factions:CloseMenu()
        view.owners:CloseMenu()
        view.types:CloseMenu()
    end)
    page:RegisterEvent("ITEM_DATA_LOAD_RESULT")
    page:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local queued
    page:SetScript("OnEvent", function(_, _, id, success)
        id, success = ML.Public(id), ML.Public(success)
        if not success or not id or not metadata[id] then return end
        metadata[id] = nil
        if page:IsVisible() and not queued then
            queued = true
            C_Timer.After(0, function()
                queued = false
                ML.RefreshInventoryView()
            end)
        end
    end)
    page:Hide()
    return page
end
