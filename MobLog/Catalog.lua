-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local areaNames, areaOptions, npcFilters = {}, nil, {}
local class = {[0]="normal",[1]="elite",[2]="rareelite",[4]="rare",[5]="trivial",[6]="minus"}
local knownRevision=0
local knownCatalog,knownCount={},0
local catalogWorker=false
local nextProgress=0
local catalogNames={}
function ML.BackgroundCatalogEnabled()
    return ML.db and ML.db.options and ML.db.options.backgroundCatalog~=false
end
local function NameKey(id)
    if not catalogNames[id] then catalogNames[id]=string.lower(ML.TrinityData.npcs[id][1]) end
    return catalogNames[id]
end
local typeNames={}
local function CreatureTypeName(id)
    if type(id)~="number" or id<=0 then return nil end
    if not typeNames[id] and C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo then
        local ok,info=pcall(C_CreatureInfo.GetCreatureTypeInfo,id)
        info=ok and ML.Public(info)
        if type(info)=="table" then typeNames[id]=ML.Public(info.name) end
    end
    return typeNames[id]
end
function ML.CatalogRecordAdded(id)
    if ML.TrinityData and ML.TrinityData.ready and ML.TrinityData.npcs[id] and not knownCatalog[id] then
        knownRevision=knownRevision+1
        knownCatalog[id]=true; knownCount=knownCount+1
    end
    -- Mark the view stale using the revision above. Refilter only when the UI
    -- requests it again; never shift a catalog-sized array in a sighting event.
end
local function StartCatalogWorker()
    local data=ML.TrinityData
    if catalogWorker or not data or data.ready or not data.queued then return end
    if not data.jobTotal then
        local owned={}
        data.ownedIncluded={}
        for _,mob in pairs(ML.db.mobs) do owned[#owned+1]=mob; data.ownedIncluded[mob.id]=true end
        for first=1,#owned,100 do
            local offset=first
            data.jobs[#data.jobs+1]=function()
                for i=offset,math.min(offset+99,#owned) do ML.ApplyCatalogMetadata(owned[i]) end
            end
        end
        data.jobTotal=#data.jobs; data.jobIndex=1
    end
    catalogWorker=true
    local function Step()
        local visible=ML.IsMobLogVisible and ML.IsMobLogVisible()
        if not visible and not ML.BackgroundCatalogEnabled() then catalogWorker=false; return end
        data.paused=InCombatLockdown()
        if data.paused then
            if ML.RefreshCatalogStatus then ML.RefreshCatalogStatus() end
            C_Timer.After(0.5,Step); return
        end
        -- One bounded data batch per timer turn, not several on every frame.
        local job=data.jobs[data.jobIndex]
        if job then
            data.jobs[data.jobIndex]=nil; data.jobIndex=data.jobIndex+1
            job()
        end
        if data.jobIndex>data.jobTotal then
            data.ready=true; data.jobs=nil; data.queued=nil; catalogWorker=false
            areaOptions,npcFilters=nil,{}
            knownCatalog,knownCount={},0
            for id,mob in pairs(ML.db.mobs) do
                if data.npcs[id] then
                    knownCatalog[id]=true; knownCount=knownCount+1
                    if not data.ownedIncluded[id] then ML.ApplyCatalogMetadata(mob) end
                end
            end
            data.ownedIncluded=nil
            if ML.InvalidateItemSearchIndex then ML.InvalidateItemSearchIndex() end
            ML.QueueRefresh(); return
        end
        if GetTime()>=nextProgress then
            nextProgress=GetTime()+0.2
            if ML.RefreshCatalogStatus then ML.RefreshCatalogStatus() end
        end
        C_Timer.After(visible and 0.02 or 0.05,Step)
    end
    C_Timer.After(0,Step)
end
function ML.EnsureCatalog()
    if ML.TrinityData and ML.TrinityData.ready then return true end
    if ML.TrinityData and ML.TrinityData.queued then StartCatalogWorker(); return false end
    if ML.catalogLoadAttempted or ML.catalogLoadScheduled then return false end
    ML.catalogLoadScheduled=true
    local function LoadFiles()
        if not (ML.IsMobLogVisible and ML.IsMobLogVisible()) and not ML.BackgroundCatalogEnabled() then ML.catalogLoadScheduled=false; return end
        if InCombatLockdown() then
            if ML.RefreshCatalogStatus then ML.RefreshCatalogStatus() end
            C_Timer.After(0.5,LoadFiles); return
        end
        ML.catalogLoadScheduled=false; ML.catalogLoadAttempted=true
        local loader=C_AddOns and C_AddOns.LoadAddOn
        if loader then
            local ok,loaded,reason=pcall(loader,"MobLog_TrinityDB")
            ML.catalogLoadReason=ok and reason or loaded
        end
        local data=ML.TrinityData
        if data and data.queued then StartCatalogWorker(); return end
        -- Compatibility with older, already materialized catalog modules.
        if data and data.ready then
            for id,mob in pairs(ML.db.mobs) do
                ML.ApplyCatalogMetadata(mob)
                if data.npcs[id] then knownCatalog[id]=true; knownCount=knownCount+1 end
            end
            if ML.InvalidateItemSearchIndex then ML.InvalidateItemSearchIndex() end
        else ML.TrinityData=nil end
        ML.QueueRefresh()
    end
    C_Timer.After(0.05,LoadFiles)
    return false
end
local startupScheduled=false
function ML.ScheduleBackgroundCatalog()
    if startupScheduled or not ML.BackgroundCatalogEnabled() then return end
    startupScheduled=true
    C_Timer.After(5,function()
        startupScheduled=false
        if ML.BackgroundCatalogEnabled() then ML.EnsureCatalog() end
    end)
end
function ML.CatalogUnavailableText()
    local data=ML.TrinityData
    if data and data.ready then return nil end
    if ML.catalogLoadScheduled then return InCombatLockdown() and "Catalog loading paused in combat." or "Loading catalog files..." end
    if data and data.queued then
        if data.paused then return "Catalog preparation paused in combat." end
        return string.format("Preparing catalog: %d %%",math.floor(((data.jobIndex or 1)-1)/math.max(1,data.jobTotal or 1)*100))
    end
    return "Catalog unavailable. Install/enable MobLog Catalog in AddOns, then restart WoW."
end
function ML.ApplyCatalogMetadata(mob)
    local info=ML.TrinityData and ML.TrinityData.npcs[mob.id]
    if not info then return end
    if ML.UnknownName(mob.name,mob.id) and info[1]~="" then mob.name=info[1]; mob.nameSource="catalog" end
    if not mob.classification or mob.classification=="unknown" then mob.classification=class[info[2]] end
    if not mob.displayID then mob.catalogDisplayID=info[4][1] end
    if not mob.tooltipType then mob.tooltipType=CreatureTypeName(info[3]) end
end
function ML.CatalogAreaName(id)
    id=tonumber(id) or id
    if not areaNames[id] then
        local world=type(id)=="string" and tonumber(id:match("^world:(%d+)$"))
        local name
        if world and GetRealZoneText then
            local ok,value=pcall(GetRealZoneText,world)
            name=ok and ML.Public(value)
        elseif type(id)=="number" and C_Map and C_Map.GetAreaInfo then
            local ok,value=pcall(C_Map.GetAreaInfo,id)
            name=ok and ML.Public(value)
        end
        if type(name)~="string" or name=="" then name=nil end
        local entry = ML.TrinityData and ML.TrinityData.areas[id]
        areaNames[id] = name or (entry and entry[1] ~= "" and entry[1]) or ((world and "Map #" or "Area #") .. (world or id))
    end
    return areaNames[id]
end
function ML.CatalogAreas()
    if not ML.TrinityData or not ML.TrinityData.ready then return {{key="all",label="All areas"}} end
    if areaOptions then return areaOptions end
    local found = {}
    if ML.TrinityData.habitatAreas then
        for key in pairs(ML.TrinityData.habitatAreas) do found[tonumber(key) or key]=true end
    else
        for _,info in pairs(ML.TrinityData.npcs) do for _,id in ipairs(info[5]) do found[id]=true end end
    end
    areaOptions = {{key="all",label="All areas"}}
    for id in pairs(found) do areaOptions[#areaOptions+1] = {key=id,label=ML.CatalogAreaName(id)} end
    table.sort(areaOptions, function(a,b)
        if a.key==b.key then return false end
        if a.key=="all" then return true end
        if b.key=="all" then return false end
        if a.label==b.label then return tostring(a.key)<tostring(b.key) end
        return string.lower(a.label)<string.lower(b.label)
    end)
    return areaOptions
end
function ML.GetMob(id)
    if ML.db.mobs[id] then return ML.db.mobs[id] end
    local info = ML.TrinityData and ML.TrinityData.ready and ML.TrinityData.npcs[id]
    if not info then return nil end
    local displays = {}
    for _, display in ipairs(info[4]) do displays[display] = true end
    return {id=id,name=info[1]~="" and info[1] or ("NPC #"..id),classification=class[info[2]],count=0,sightings=0,loot=0,manual=0,first=0,last=0,
        places={},sightingPlaces={},displayID=info[4][1],displayIDs=displays,catalogOnly=true,
        selectedDisplayID=ML.db.catalogAppearances and ML.db.catalogAppearances[id],tooltipType=CreatureTypeName(info[3])}
end
function ML.MatchesCatalogArea(mob, filter)
    if not mob then return false end
    if ML.AreaFilterIsAll(filter) then return true end
    local members = mob.members or {mob}
    for _, member in ipairs(members) do
        if ML.CatalogHabitatMatches(member.id,filter) then return true end
        for _, places in ipairs({member.places or {},member.sightingPlaces or {}}) do
            for _, place in pairs(places) do if ML.RecordedPlaceMatchesArea(place,filter) then return true end end
        end
    end
    return false
end
function ML.UndiscoveredIDs(query, kind, area, rank)
    if ML.LocationSource(area)=="encounters" then return {} end
    if not ML.TrinityData or not ML.TrinityData.ready or (rank~="all" and rank~="unranked") then return {} end
    query = string.lower(query or "")
    local descending=ML.GetSortMode("mobs")=="za"
    local key = query .. "\031" .. kind .. "\031" .. ML.AreaFilterKey(area).."\031"..(descending and "za" or "az")
    local candidates = npcFilters[key]
    if not candidates then
        candidates = {}
        local function Match(id)
            local info=ML.TrinityData.npcs[id]
            local matches=query=="" or string.find(NameKey(id),query,1,true) or string.find(tostring(id),query,1,true)
            if not matches or (kind~="all" and not ML.MatchesMobType({classification=class[info[2]]},kind)) then return end
            local matchesArea=ML.AreaFilterIsAll(area) or ML.CatalogHabitatMatches(id,area)
            if matchesArea then candidates[#candidates+1]=id end
        end
        if ML.TrinityData.npcOrder then
            for _,chunk in ipairs(ML.TrinityData.npcOrder) do for id in chunk:gmatch("%d+") do Match(tonumber(id)) end end
        else
            for id in pairs(ML.TrinityData.npcs) do Match(id) end
            table.sort(candidates,function(a,b) local an,bn=NameKey(a),NameKey(b); if an==bn then return a<b end; return an<bn end)
        end
        -- Reverse name ordering while keeping equal-name NPC IDs ascending.
        if descending then
            local reversed={}
            local last=#candidates
            while last>=1 do
                local first=last
                while first>1 and NameKey(candidates[first-1])==NameKey(candidates[last]) do first=first-1 end
                for i=first,last do reversed[#reversed+1]=candidates[i] end
                last=first-1
            end
            candidates=reversed
        end
        -- Search edits should not retain a full catalog-sized cache for every keystroke.
        npcFilters = {[key]=candidates,descending=descending}
    end
    if npcFilters.result and npcFilters.revision==knownRevision then return npcFilters.result end
    local ids = {}
    for _, id in ipairs(candidates) do if not ML.db.mobs[id] then ids[#ids+1]=id end end
    npcFilters.result, npcFilters.revision=ids,knownRevision
    return ids
end
-- Iterate a shared packed loot group without constructing a large item array.
local function LootItems(lootID)
    local data=ML.TrinityData
    local value=data and data.loot[lootID]
    if type(value)=="number" and data.lootGroups then value=data.lootGroups[value] end
    if type(value)=="string" then
        local nextID=value:gmatch("%d+")
        return function() local id=nextID(); if id then return tonumber(id) end end
    end
    local index=0
    return function() index=index+1; return value and value[index] end
end
local lootOwners, itemLootIDs = nil, nil
function ML.PossibleItemSources(itemID,includeObserved)
    if not ML.TrinityData or not ML.TrinityData.ready then return {} end
    local data = ML.TrinityData
    local result={}
    if data.itemSources then
        local packed=data.itemSources[itemID]
        if type(packed)=="number" and data.itemSourceGroups then packed=data.itemSourceGroups[packed] end
        for value in (packed or ""):gmatch("%d+") do
            local npc=tonumber(value)
            local observed=ML.db.mobs[npc]
            local drop=observed and observed.items and observed.items[itemID]
            if includeObserved or not drop or (drop.quantity or 0)==0 then result[#result+1]=npc end
        end
    else
    if not lootOwners then
        lootOwners, itemLootIDs = {}, {}
        for npc, info in pairs(data.npcs) do
            for _, lootID in ipairs(info[6]) do
                lootOwners[lootID]=lootOwners[lootID] or {}; lootOwners[lootID][#lootOwners[lootID]+1]=npc
            end
        end
        for lootID in pairs(data.loot) do
            for id in LootItems(lootID) do
                itemLootIDs[id]=itemLootIDs[id] or {}; itemLootIDs[id][#itemLootIDs[id]+1]=lootID
            end
        end
    end
    local found = {}
    for _, lootID in ipairs(itemLootIDs[itemID] or {}) do
        for _, npc in ipairs(lootOwners[lootID] or {}) do
            if not found[npc] then
                found[npc]=true
                local observed=ML.db.mobs[npc]
                local drop=observed and observed.items and observed.items[itemID]
                if includeObserved or not drop or (drop.quantity or 0)==0 then result[#result+1]=npc end
            end
        end
    end
    end
    table.sort(result,function(a,b)
        local an,bn=data.npcs[a][1],data.npcs[b][1]
        if an==bn then return a<b end
        return an<bn
    end)
    return result
end
function ML.CatalogMobDrops(id)
    local info=ML.TrinityData and ML.TrinityData.ready and ML.TrinityData.npcs[id]
    local found,result={},{}
    for _, lootID in ipairs(info and info[6] or {}) do
        for itemID in LootItems(lootID) do
            if not found[itemID] then found[itemID]=true; result[#result+1]=itemID end
        end
    end
    table.sort(result)
    return result
end
function ML.CatalogDropNote(npc,item)
    local data=ML.TrinityData
    local note=data and data.ready and data.dropNotes and data.dropNotes[npc..":"..item]
    if type(note)~="string" then return nil end
    if #note>700 then return note:sub(1,700).."... Additional variants may exist." end
    return note
end
local areaItems={}
function ML.ReleaseCatalogViewCache()
    npcFilters,catalogNames,areaItems={},{},{}
end
function ML.ItemMatchesCatalogArea(itemID,area)
    if ML.LocationSource(area)=="encounters" then return false end
    if not ML.TrinityData or not ML.TrinityData.ready then return false end
    if ML.AreaFilterIsAll(area) then return true end
    local key=ML.AreaFilterKey(area)
    if not areaItems[key] then
        local items,templates={},{}
        for npc,info in pairs(ML.TrinityData.npcs) do
            local matches=ML.CatalogHabitatMatches(npc,area)
            if matches then for _,lootID in ipairs(info[6]) do templates[lootID]=true end end
        end
        for lootID in pairs(templates) do for id in LootItems(lootID) do items[id]=true end end
        areaItems[key]=items
    end
    return areaItems[key][itemID]==true
end

function ML.UndiscoveredCount(query,kind,area,rank)
    if ML.LocationSource(area)=="encounters" then return 0 end
    local data=ML.TrinityData
    if not data or not data.ready or (rank~="all" and rank~="unranked") then return 0 end
    if (not query or query=="") and kind=="all" and ML.AreaFilterIsAll(area) and data.npcCount then
        return math.max(0,data.npcCount-knownCount)
    end
    return #ML.UndiscoveredIDs(query,kind,area,rank)
end
