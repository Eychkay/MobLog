-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

local frame = CreateFrame("Frame")
local character, bankOpen, pending, index
local dirty = {}

local function Store()
    if not ML.db then return end
    ML.db.inventory = ML.db.inventory or {}
    local client = ML.IsForever and "forever" or "retail"
    local store = ML.db.inventory[client]
    if not store then
        store = { characters = {} }
        ML.db.inventory[client] = store
    end
    return store
end

local function ScanBag(bag, mustExist)
    local size = ML.Public(C_Container.GetContainerNumSlots(bag))
    if type(size) ~= "number" or (mustExist and size == 0) then return end
    local items = {}
    for slot = 1, size do
        local raw = C_Container.GetContainerItemInfo(bag, slot)
        local info = ML.Public(raw)
        if info then
            local id, count = ML.Public(info.itemID), ML.Public(info.stackCount)
            if type(id) ~= "number" or type(count) ~= "number" or count < 1 then return end
            items[#items + 1] = { id = id, count = count, link = ML.Public(info.hyperlink),
                icon = ML.Public(info.iconFileID), quality = ML.Public(info.quality) }
        elseif issecretvalue and issecretvalue(raw) then
            return
        end
    end
    return items
end

local function ScanBags()
    local bags = Enum and Enum.BagIndex
    local first = bags and bags.Backpack or 0
    local last = bags and bags.Bag_4 or NUM_BAG_SLOTS or 4
    local items = {}
    for bag = first, last do
        local found = ScanBag(bag, bag == first)
        if not found then return end
        for _, item in ipairs(found) do items[#items + 1] = item end
    end
    local reagent = bags and bags.ReagentBag
    if not ML.IsForever and reagent and reagent > last then
        local found = ScanBag(reagent)
        if not found then return end
        for _, item in ipairs(found) do items[#items + 1] = item end
    end
    return { stamp = time(), groups = { { items = items } } }
end

local function ScanEquipment()
    local items = {}
    for slot = INVSLOT_FIRST_EQUIPPED or 1, INVSLOT_LAST_EQUIPPED or 19 do
        local raw = GetInventoryItemID("player", slot)
        local id = ML.Public(raw)
        if id then
            items[#items + 1] = { id = id, count = 1, link = ML.Public(GetInventoryItemLink("player", slot)),
                icon = ML.Public(GetInventoryItemTexture("player", slot)) }
        elseif issecretvalue and issecretvalue(raw) then
            return
        end
    end
    return { stamp = time(), groups = { { items = items } } }
end

local function CanReadBank(bankType)
    if bankType == nil or not C_Bank or not C_Bank.CanViewBank or ML.Public(C_Bank.CanViewBank(bankType)) ~= true then return false end
    if C_Bank.FetchBankLockedReason then
        local reason = C_Bank.FetchBankLockedReason(bankType)
        if (issecretvalue and issecretvalue(reason)) or reason ~= nil then return false end
    end
    return true
end

local function ScanBank(bankType)
    if not CanReadBank(bankType) or not C_Bank.FetchPurchasedBankTabData then return end
    local tabs = ML.Public(C_Bank.FetchPurchasedBankTabData(bankType))
    local count = ML.Public(C_Bank.FetchNumPurchasedBankTabs(bankType))
    if type(tabs) ~= "table" or type(count) ~= "number" or count ~= #tabs then return end
    local groups = {}
    for page, tab in ipairs(tabs) do
        local bag = ML.Public(tab.ID)
        if type(bag) ~= "number" then return end
        -- On Forever a purchased bank bag slot can still have no bag equipped.
        local items = ScanBag(bag, not ML.IsForever or page == 1)
        if not items then return end
        local name = ML.Public(tab.name)
        groups[page] = { label = type(name) == "string" and name ~= "" and name or ("Tab " .. page), items = items }
    end
    return { stamp = time(), groups = groups }
end

local function ScanMoney(amount)
    amount = ML.Public(amount)
    if type(amount) == "number" and amount >= 0 then return { amount = amount, stamp = time() } end
end

local function ScanSharedMoney(bankType)
    if not CanReadBank(bankType) or not C_Bank.FetchDepositedMoney then return end
    if C_Bank.DoesBankTypeSupportMoneyTransfer and ML.Public(C_Bank.DoesBankTypeSupportMoneyTransfer(bankType)) ~= true then return end
    return ScanMoney(C_Bank.FetchDepositedMoney(bankType))
end

local function Flush()
    pending = false
    local store = Store()
    if not character or not store then return end
    if InCombatLockdown() then return end
    local saved = store.characters[character] or {}
    store.characters[character] = saved
    local itemsChanged = dirty.bags or dirty.equipment or dirty.bank
    local moneyChanged = dirty.money or dirty.sharedMoney
    if dirty.bags then saved.bags = ScanBags() or saved.bags end
    if dirty.equipment then saved.equipment = ScanEquipment() or saved.equipment end
    if dirty.money and GetMoney then saved.money = ScanMoney(GetMoney()) or saved.money end
    if dirty.bank and bankOpen and Enum and Enum.BankType then
        saved.bank = ScanBank(Enum.BankType.Character) or saved.bank
        store.shared = ScanBank(Enum.BankType.Account) or store.shared
    end
    if dirty.sharedMoney and bankOpen and Enum and Enum.BankType then
        store.sharedMoney = ScanSharedMoney(Enum.BankType.Account) or store.sharedMoney
    end
    wipe(dirty)
    if itemsChanged then
        index = nil
        if ML.RefreshInventoryView then ML.RefreshInventoryView() end
        if ML.RefreshInventoryCatalogCount then ML.RefreshInventoryCatalogCount() end
    elseif moneyChanged and ML.RefreshInventoryGold then
        ML.RefreshInventoryGold()
    end
end

local function Schedule()
    if pending then return end
    pending = true
    C_Timer.After(0.12, function() if pending then Flush() end end)
end

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_ENTERING_WORLD" then
        character = ML.UpdateCharacter()
        dirty.bags, dirty.equipment, dirty.money = true, true, true
    elseif event == "PLAYER_LOGOUT" then
        if next(dirty) then Flush() end
        return
    elseif event == "PLAYER_REGEN_ENABLED" then
        if not next(dirty) then return end
    elseif event == "PLAYER_EQUIPMENT_CHANGED" then
        dirty.equipment, dirty.bags = true, true
    elseif event == "BAG_UPDATE_DELAYED" then
        dirty.bags, dirty.bank = true, bankOpen
    elseif event == "PLAYER_MONEY" or event == "ACCOUNT_MONEY" then
        if event == "ACCOUNT_MONEY" and not bankOpen then return end
        dirty.money, dirty.sharedMoney = true, bankOpen
    elseif event == "BANKFRAME_CLOSED" then
        if (dirty.bank or dirty.sharedMoney) and bankOpen then Flush() end
        bankOpen = false
        return
    else
        if event == "BANKFRAME_OPENED" then
            bankOpen, dirty.money, dirty.sharedMoney = true, true, true
        end
        if not bankOpen then return end
        dirty.bank, dirty.bags = true, true
    end
    Schedule()
end)
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LOGOUT", "PLAYER_REGEN_ENABLED", "PLAYER_EQUIPMENT_CHANGED",
    "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED",
    "PLAYER_ACCOUNT_BANK_TAB_SLOTS_CHANGED", "BANK_TABS_CHANGED", "BANK_TAB_SETTINGS_UPDATED", "PLAYER_MONEY", "ACCOUNT_MONEY" }) do
    frame:RegisterEvent(event)
end

function ML.InventoryBankName()
    return ML.IsForever and "Account bank" or "Warband bank"
end

function ML.InventoryLocationName(location)
    local label = ({ bags = "Bags", equipment = "Equipped", bank = "Personal bank", shared = ML.InventoryBankName() })[location.kind]
    return location.label and (label .. " · " .. location.label) or label
end

local function AddSnapshot(items, owner, kind, snapshot)
    if not snapshot then return end
    for _, group in ipairs(snapshot.groups) do
        local locations = {}
        for _, copy in ipairs(group.items) do
            local entry = items[copy.id]
            if not entry then
                entry = { id = copy.id, count = 0, locations = {} }
                items[copy.id] = entry
            end
            entry.link = entry.link or copy.link
            entry.icon = entry.icon or copy.icon
            entry.quality = entry.quality or copy.quality
            entry.count = entry.count + copy.count
            local location = locations[copy.id]
            if not location then
                location = { owner = owner, kind = kind, label = group.label, stamp = snapshot.stamp, count = 0, copies = {} }
                locations[copy.id] = location
                entry.locations[#entry.locations + 1] = location
            end
            location.count = location.count + copy.count
            location.copies[#location.copies + 1] = copy
        end
    end
end

function ML.InventoryCharacters()
    local store = Store()
    return store and store.characters or {}, store and store.shared
end

function ML.InventorySharedMoney()
    local store = Store()
    return store and store.sharedMoney
end

function ML.InventoryIndex()
    if index then return index end
    local characters, shared = ML.InventoryCharacters()
    local items = {}
    for guid, saved in pairs(characters) do
        AddSnapshot(items, guid, "bags", saved.bags)
        AddSnapshot(items, guid, "equipment", saved.equipment)
        AddSnapshot(items, guid, "bank", saved.bank)
    end
    AddSnapshot(items, "shared", "shared", shared)
    index = items
    return index
end

function ML.InventoryItemCount(id)
    local item = ML.InventoryIndex()[id]
    return item and item.count or 0
end

function ML.AddInventoryItemTooltip(tooltip, id)
    if not ML.db or not ML.db.options or ML.db.options.inventoryTooltip == false or type(id) ~= "number" then return end
    local entry = ML.InventoryIndex()[id]
    if not entry then return end

    local owners, keys = {}, {}
    for _, location in ipairs(entry.locations) do
        local owner = location.owner
        local holdings = owners[owner]
        if not holdings then
            holdings = { total = 0, storage = {} }
            owners[owner] = holdings
            keys[#keys + 1] = owner
        end
        local label = owner == "shared" and location.label or ML.InventoryLocationName(location)
        holdings.total = holdings.total + location.count
        holdings.storage[#holdings.storage + 1] = label .. " ×" .. location.count
    end
    table.sort(keys, function(a, b)
        if a == character or b == character then return a == character end
        if a == "shared" or b == "shared" then return b == "shared" end
        local left, right = owners[a].total, owners[b].total
        if left == right then return a < b end
        return left > right
    end)

    tooltip:AddLine(" ")
    tooltip:AddLine("MobLog inventory · " .. entry.count .. " recorded", 0.9, 0.77, 0.48)
    for _, owner in ipairs(keys) do
        local holdings = owners[owner]
        local name = owner == "shared" and ML.InventoryBankName() or ML.CharacterName(owner)
        tooltip:AddDoubleLine(name, tostring(holdings.total), 1, 1, 1, 1, 1, 1)
        tooltip:AddLine("  " .. table.concat(holdings.storage, " · "), 0.83, 0.81, 0.75, true)
    end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
        if tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip then return end
        data = ML.Public(data)
        if type(data) == "table" then ML.AddInventoryItemTooltip(tooltip, ML.Public(data.id)) end
    end)
else
    local function AddLegacyItemTooltip(tooltip)
        local _, link = tooltip:GetItem()
        link = ML.Public(link)
        ML.AddInventoryItemTooltip(tooltip, type(link) == "string" and tonumber(link:match("item:(%d+)")))
    end
    for _, tooltip in pairs({ GameTooltip, ItemRefTooltip }) do
        if tooltip.GetItem and tooltip:HasScript("OnTooltipSetItem") then
            tooltip:HookScript("OnTooltipSetItem", AddLegacyItemTooltip)
        end
    end
end
