-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
ML.ItemRarityFilters = {
    { key = "all", label = "All rarities" },
    { key = 0, label = "Poor", color = "ff9d9d9d" },
    { key = 1, label = "Common", color = "ffffffff" },
    { key = 2, label = "Uncommon", color = "ff1eff00" },
    { key = 3, label = "Rare", color = "ff0070dd" },
    { key = 4, label = "Epic", color = "ffa335ee" },
    { key = 5, label = "Legendary", color = "ffff8000" },
    { key = 6, label = "Artifact", color = "ffe6cc80" },
    { key = 7, label = "Heirloom", color = "ff00ccff" },
    { key = 8, label = "WoW Token", color = "ff00ccff" },
    { key = "unknown", label = "Unknown rarity" },
}

-- Client metadata is saved per locale. Published search metadata is immutable
-- until preparation completes, is paused, or the Items page is reopened.
local infoCache,published,coverage
local pending,lastRequest={},{}
local loadingFrame,refreshScheduled,preparation
local preparationSequence=0
local catalogSnapshot
local itemRevision=0
local scanOutcome,publishAfterResponse
function ML.BackgroundItemScanEnabled()
    return ML.db and ML.db.options and ML.db.options.backgroundItemScan~=false
end

function ML.InvalidateItemSources()
    ML.itemSourceRevision=(ML.itemSourceRevision or 0)+1
end
function ML.InvalidateItemLocations()
    ML.itemLocationRevision=(ML.itemLocationRevision or 0)+1
end
function ML.InvalidateItemCatalog()
    itemRevision=itemRevision+1
    catalogSnapshot=nil
    ML.InvalidateItemSources()
end

local function ValidQuality(value)
    value=ML.Public(value)
    return type(value)=="number" and value>=0 and value<=8 and value==math.floor(value)
end
local function LinkQuality(link)
    local color=type(link)=="string" and link:match("|c(%x%x%x%x%x%x%x%x)")
    if not color then return nil end
    for _,entry in ipairs(ML.ItemRarityFilters) do
        if type(entry.key)=="number" and entry.key<=5 and entry.color==string.lower(color) then return entry.key end
    end
end
local function Complete(info)
    return type(info)=="table" and type(info.name)=="string" and info.name~="" and ValidQuality(info.quality)
end
local function EnsureCache()
    if infoCache then return end
    local locale=GetLocale()
    local saved=ML.db.itemSearchCache
    if type(saved)~="table" or saved.version~=1 or saved.locale~=locale or type(saved.items)~="table" then
        saved={version=1,locale=locale,items={}}
        ML.db.itemSearchCache=saved
    end
    infoCache=saved.items
end
local function IndexIDs()
    local ids=ML.CopyViewTable(ML.db.itemWishlist)
    for id in pairs(ML.TrinityData and ML.TrinityData.ready and ML.TrinityData.items or {}) do ids[id]=true end
    for _,mob in pairs(ML.db.mobs) do
        for id,drop in pairs(mob.items or {}) do
            ids[id]=true
            if not Complete(infoCache[id]) then
                local name=drop.name or (drop.link and drop.link:match("%[(.-)%]"))
                local quality=ValidQuality(drop.quality) and drop.quality or LinkQuality(drop.link)
                if type(name)=="string" and name~="" and ValidQuality(quality) then
                    infoCache[id]={name=name,link=drop.link,icon=drop.icon,quality=quality}
                end
            end
        end
    end
    return ids
end
function ML.PublishItemSearchIndex()
    EnsureCache()
    local ids=IndexIDs()
    published={}
    for id,info in pairs(infoCache) do if Complete(info) then published[id]=info end end
    for id,source in pairs(ML.TrinityData and ML.TrinityData.ready and ML.TrinityData.items or {}) do
        if not published[id] and source[1]~="" and ValidQuality(source[2]) then
            published[id]={name=source[1],quality=source[2],icon=source[3]>0 and source[3] or nil}
        end
    end
    local total,known=0,0
    for id in pairs(ids) do total=total+1; if published[id] then known=known+1 end end
    coverage={known=known,total=total}
end
local nextProgress=0
local function NotifyProgress(force)
    local now=GetTime()
    if not force and now<nextProgress then return end
    nextProgress=now+0.25
    if ML.RefreshItemSearchStatus then ML.RefreshItemSearchStatus() end
end
local function QueueRowRefresh()
    if refreshScheduled then return end
    refreshScheduled=true
    C_Timer.After(0.1,function()
        refreshScheduled=false
        if publishAfterResponse and not preparation then
            publishAfterResponse=nil
            ML.PublishItemSearchIndex()
            if ML.RefreshItems then ML.RefreshItems() end
        end
        if ML.RefreshItemRows then ML.RefreshItemRows() end
        if ML.RefreshMobLootRows then ML.RefreshMobLootRows() end
        NotifyProgress()
    end)
end
local function MarkResolved(id)
    if preparation and preparation.wanted[id] then
        preparation.wanted[id]=nil
        preparation.resolved=preparation.resolved+1
    end
end
local function ReadItemInfo(id)
    if not C_Item or not C_Item.GetItemInfo then return nil end
    local ok,name,link,quality,level,minLevel,itemType,subType,stack,equip,icon=pcall(C_Item.GetItemInfo,id)
    name,link,quality,icon=ML.Public(name),ML.Public(link),ML.Public(quality),ML.Public(icon)
    if ok and type(name)=="string" and name~="" and ValidQuality(quality) then
        local wasKnown=Complete(infoCache[id])
        -- Replace rather than mutate the published snapshot's metadata table.
        infoCache[id]={name=name,link=link,icon=icon,quality=quality}
        pending[id]=nil
        MarkResolved(id)
        if not wasKnown and not preparation and scanOutcome then publishAfterResponse=true end
        return infoCache[id]
    end
end
local function RequestItemInfo(id)
    EnsureCache()
    if Complete(infoCache[id]) then MarkResolved(id); return infoCache[id] end
    if not C_Item or not C_Item.GetItemInfo then return nil end
    local now=GetTime()
    if lastRequest[id] and now-lastRequest[id]<8 then return nil end
    if not loadingFrame then
        loadingFrame=CreateFrame("Frame")
        loadingFrame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        loadingFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
        loadingFrame:SetScript("OnEvent",function(_,_,itemID,success)
            itemID,success=ML.Public(itemID),ML.Public(success)
            if type(itemID)~="number" or not lastRequest[itemID] or GetTime()-lastRequest[itemID]>60 then return end
            if Complete(infoCache[itemID]) then return end
            -- One failed callback must not discard a later successful data-load
            -- event. Keep waiting until readable data arrives or the timeout.
            if success then ReadItemInfo(itemID) end
            QueueRowRefresh()
        end)
    end
    lastRequest[id],pending[id]=now,now
    local info=ReadItemInfo(id)
    if not info and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID,id) end
    return info
end
local function ItemQuality(item)
    local info=published[item.id]
    if info then return info.quality end
    if ValidQuality(item.quality) then return item.quality end
    return LinkQuality(item.link)
end

function ML.CatalogItemInfo(id)
    if not published then ML.PublishItemSearchIndex() end
    local info=published[id]
    local source=ML.TrinityData and ML.TrinityData.ready and ML.TrinityData.items[id]
    return {id=id,name=info and info.name or (source and source[1]~="" and source[1]) or ("Item #"..id),
        link=info and info.link,icon=info and info.icon or (source and source[3]>0 and source[3] or nil),
        quality=info and info.quality or (source and source[2]>=0 and source[2] or nil),quantity=0,sources={},catalogOnly=true}
end

-- Derive this index from per-mob records so old data needs no duplicate store.
function ML.ItemCatalog(query, rarity, area)
    if not published then ML.PublishItemSearchIndex() end
    query = string.lower(query or "")
    local mode=ML.GetSortMode("items")
    local areaKey=ML.AreaFilterKey(area)
    local locations=not ML.AreaFilterIsAll(area) and (ML.itemLocationRevision or 0) or 0
    local data=ML.TrinityData and ML.TrinityData.ready and ML.TrinityData
    local cached=catalogSnapshot
    if cached and cached.query==query and cached.rarity==rarity and cached.area==areaKey and
        cached.mode==mode and cached.index==published and cached.revision==itemRevision and
        cached.locations==locations and cached.data==data then return cached.items end
    local byID, items = {}, {}
    for id,info in pairs(ML.TrinityData and ML.TrinityData.ready and ML.TrinityData.items or {}) do
        local cached=published[id]
        byID[id]={id=id,name=cached and cached.name or (info[1]~="" and info[1] or nil),
            link=cached and cached.link,icon=cached and cached.icon or (info[3]>0 and info[3] or nil),
            quality=cached and cached.quality or (info[2]>=0 and info[2] or nil),quantity=0,sources={},catalogOnly=true}
    end
    for id in pairs(ML.db.itemWishlist or {}) do if not byID[id] then byID[id]=ML.CatalogItemInfo(id) end end
    for _, mob in pairs(ML.db.mobs) do
        for id, drop in pairs(mob.items or {}) do
            if (drop.quantity or 0) > 0 then
                local item = byID[id]
                if not item then
                    item = { id = id, quantity = 0, sources = {} }
                    byID[id] = item
                end
                local cached=published[id]
                item.name = cached and cached.name or drop.name or item.name
                item.link = cached and cached.link or drop.link or item.link
                item.icon = cached and cached.icon or drop.icon or item.icon
                if type(drop.quality) == "number" then item.quality = drop.quality end
                item.quantity = item.quantity + drop.quantity
                if (drop.last or 0)>(item.last or 0) or ((drop.last or 0)==(item.last or 0) and (drop.lastOrder or 0)>(item.lastOrder or 0)) then
                    item.last,item.lastOrder=drop.last,drop.lastOrder
                end
                item.catalogOnly=false
                item.sources[#item.sources + 1] = { mob = mob, drop = drop, rate = ML.DropRate(mob, drop) }
            end
        end
    end
    for _, item in pairs(byID) do
        item.name = item.name or (item.link and item.link:match("%[(.-)%]")) or ("Item #" .. item.id)
        item.sortName=string.lower(item.name)
        item.quality = ItemQuality(item)
        local matchesRarity = rarity == nil or rarity == "all" or item.quality == rarity or
            (rarity == "unknown" and item.quality == nil)
        local matchesArea=ML.AreaFilterIsAll(area)
        if not matchesArea then
            for _, source in ipairs(item.sources) do if ML.MatchesCatalogArea(source.mob,area) then matchesArea=true; break end end
            if not matchesArea then
                matchesArea=ML.ItemMatchesCatalogArea(item.id,area)
            end
        end
        if matchesArea and matchesRarity and (query=="" or string.find(item.sortName, query, 1, true) or string.find(tostring(item.id), query, 1, true)) then
            -- The selected source pane applies its own sort when expanded.
            items[#items + 1] = item
        end
    end
    table.sort(items,function(a,b) return ML.SortBefore(a,b,mode) end)
    catalogSnapshot={query=query,rarity=rarity,area=areaKey,mode=mode,index=published,
        revision=itemRevision,locations=locations,data=data,items=items}
    return items
end

-- Visible rows may resolve their display while browsing. Filtered results never
-- trigger requests, and metadata responses repaint rows without rebuilding results.
function ML.LoadCatalogItem(item,allowRequest)
    EnsureCache()
    local info=infoCache[item.id]
    if not Complete(info) and allowRequest~=false then info=RequestItemInfo(item.id) end
    if Complete(info) then item.name,item.link,item.icon,item.quality=info.name,info.link,info.icon,info.quality end
end
function ML.ItemSearchStatus()
    if not published then ML.PublishItemSearchIndex() end
    if preparation then return preparation,preparation.known,preparation.known+preparation.total end
    return preparation,coverage.known,coverage.total,scanOutcome
end
function ML.PauseItemSearchPreparation(completed)
    if not preparation then return end
    scanOutcome={completed=completed==true}
    publishAfterResponse=nil
    preparation=nil; preparationSequence=preparationSequence+1
    ML.PublishItemSearchIndex()
    NotifyProgress(true)
    if ML.RefreshItems then ML.RefreshItems() end
end
function ML.PrepareItemSearch(visible)
    if preparation then return end
    if not C_Item or not C_Item.GetItemInfo then ML.Print("Item lookup is unavailable in this client."); return end
    EnsureCache()
    ML.PublishItemSearchIndex()
    local ids,wanted={},{}
    for id in pairs(IndexIDs()) do
        if not published[id] then ids[#ids+1]=id; wanted[id]=true end
    end
    if #ids==0 then NotifyProgress(); return end
    table.sort(ids)
    scanOutcome=nil; publishAfterResponse=nil
    preparation={ids=ids,wanted=wanted,cursor=1,waiting={},resolved=0,total=#ids,known=coverage.known,pass=1}
    preparationSequence=preparationSequence+1
    local token=preparationSequence
    local function Step()
        if token~=preparationSequence or not preparation then return end
        local shown=visible()
        if not shown and not ML.BackgroundItemScanEnabled() then ML.PauseItemSearchPreparation(); return end
        local state=preparation
        state.inCombat=InCombatLockdown()
        if state.inCombat then NotifyProgress(); C_Timer.After(0.5,Step); return end
        if state.retryAt and GetTime()<state.retryAt then NotifyProgress(); C_Timer.After(0.25,Step); return end
        state.retryAt=nil
        local waiting=0
        local polled=false
        for id in pairs(state.waiting) do
            if Complete(infoCache[id]) then MarkResolved(id); state.waiting[id]=nil
            elseif not pending[id] or GetTime()-pending[id]>=8 then
                if not polled then
                    polled=true
                    ReadItemInfo(id) -- Recover readable cache data after a missed callback.
                    pending[id]=nil; state.waiting[id]=nil
                end
            end
            if state.waiting[id] then waiting=waiting+1 end
        end
        -- Never issue a multi-item burst in a single frame.
        for _=1,math.min(polled and 0 or 1,8-waiting) do
            local id=state.ids[state.cursor]
            if not id then break end
            state.cursor=state.cursor+1
            RequestItemInfo(id)
            if pending[id] then state.waiting[id]=true end
        end
        if state.cursor>#state.ids and not next(state.waiting) then
            local retry={}
            for _,id in ipairs(state.ids) do
                if Complete(infoCache[id]) then MarkResolved(id)
                elseif state.wanted[id] then retry[#retry+1]=id end
            end
            if #retry>0 and state.pass<3 then
                state.ids=retry; state.cursor=1; state.pass=state.pass+1
                state.retryAt=GetTime()+8
            else ML.PauseItemSearchPreparation(true); return end
        end
        NotifyProgress()
        C_Timer.After(shown and 0.05 or 0.1,Step)
    end
    NotifyProgress(true)
    C_Timer.After(0.05,Step)
end

function ML.InvalidateItemSearchIndex() published,coverage=nil,nil end
