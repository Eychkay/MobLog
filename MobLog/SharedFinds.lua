-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local Share = {}
ML.Share = Share
Share.client = ML.IsForever and "FOREVER" or "RETAIL"
Share.maxBytes, Share.maxRows = 512 * 1024, 50000
local maxPayloadBytes = 8 * 1024 * 1024
local empty, mapNames, mapViews = {}, {}, {}
local imported

local function Plain(s)
    return type(s) == "string" and #s <= 128 and not s:find("[%c|]")
end

local function Escape(s)
    return (s:gsub("([^%w%-%._])", function(c) return string.format("%%%02X", c:byte()) end))
end

local function Decode(s)
    if not s or s:gsub("%%%x%x", ""):find("%%") then return end
    s = s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    if Plain(s) then return s end
end

local function Number(s, max)
    if type(s) ~= "string" or not s:match("^%d+$") or #s > 9 then return end
    local n = tonumber(s)
    if n <= max then return n end
end

local function ID(s)
    local n = Number(s, 99999999)
    if n and n > 0 then return n end
end

function Share.Zone(map)
    if not map then return "" end
    if not mapNames[map] then
        if C_Map and C_Map.GetMapInfo then
            local ok,info=pcall(C_Map.GetMapInfo,map)
            info=ok and ML.Public(info)
            mapNames[map] = info and ML.Public(info.name)
        end
    end
    return mapNames[map] or ("Map #" .. map)
end

local function ItemName(id, fallback, request)
    local localized = ML.LocalItemName(id, request)
    if localized then return localized end
    local item = ML.db.gatheredItems and ML.db.gatheredItems[id]
    local data = ML.TrinityData
    local info = data and data.ready and data.items[id]
    return item and item.name or fallback or (info and info[1] ~= "" and info[1]) or ("Item #" .. id)
end

local npcNames, npcRetry = {}, {}
local function CreatureName(r, request)
    local id = r.npc
    if request and not npcNames[id] and not ML.MetadataBlocked() and GetTime() >= (npcRetry[id] or 0) then
        npcNames[id] = ML.LookupNPCName(id)
        npcRetry[id] = GetTime() + 15
    end
    if npcNames[id] then return npcNames[id] end
    local mob = ML.GetMob(id)
    if mob and not ML.UnknownName(mob.name,id) and mob.name ~= ("NPC #" .. id) then return mob.name end
    return r.npcName or ("NPC #" .. id)
end

function Share.Label(r, request)
    local name
    if r.npc then name = CreatureName(r, request) end
    if r.type == "D" then return ItemName(r.item, r.itemName, request) .. "  ·  " .. name end
    if r.type == "G" then
        name = ML.GatherLocationName(r)
        if r.resource and r.locale and r.locale ~= GetLocale() then
            local resource = ML.LocalItemName(r.resource, request)
            if resource and resource ~= name then name = resource .. " (" .. name .. ")" end
        end
    end
    if not r.map then return name end
    return string.format("%s  ·  %s  %.1f / %.1f", name, Share.Zone(r.map), 100*r.x, 100*r.y)
end

local function ReadRow(line)
    local f = {}
    for value in (line .. ","):gmatch("([^,]*),") do
        f[#f+1] = value
        if #f > 9 then return end
    end
    local r = {type=f[1]}
    if r.type == "D" and #f == 5 then
        r.item, r.npc = ID(f[2]), ID(f[3])
        local a, b = Decode(f[4]), Decode(f[5])
        if not (r.item and r.npc and a and b) then return end
        r.itemName, r.npcName = a ~= "" and a or nil, b ~= "" and b or nil
        return r
    end
    if r.type == "M" and #f == 6 then
        local name = Decode(f[6])
        r.npc = ID(f[2])
        if not r.npc or not name then return end
        r.npcName = name ~= "" and name or nil
        if f[3] == "0" and f[4] == "0" and f[5] == "0" then return r end
    elseif r.type == "G" and #f == 9 then
        r.kind = f[2]
        if not ML.GatherIcons[r.kind] then return end
        local name = Decode(f[7])
        local resource = Number(f[6],99999999)
        if not name or not resource or not f[8]:match("^%l%l%u%u$") then return end
        r.name, r.resource, r.locale = name ~= "" and name or nil, resource > 0 and resource or nil, f[8]
        if f[9] ~= "" then
            r.loot = {}
            local count = 0
            for part in (f[9] .. "+"):gmatch("([^+]*)%+") do
                local id, qty = part:match("^(%d+)x(%d+)$")
                id, qty = ID(id), ID(qty)
                if not id or not qty or r.loot[id] or count >= 64 then return end
                r.loot[id], count = qty, count + 1
            end
        end
    else return end
    local x, y = Number(f[4],100000), Number(f[5],100000)
    r.map = ID(f[3])
    if not (r.map and x and y) or (x == 0 and y == 0) then return end
    r.x, r.y = x / 100000, y / 100000
    return r
end

local function HashPart(hash, payload)
    for i = 1, #payload do
        hash = (hash * 131 + payload:byte(i)) % 4294967291
    end
    return (hash * 131 + 10) % 4294967291
end

function Share.Parse(code, checkpoint)
    if type(code) ~= "string" or #code > Share.maxBytes then return nil, "This package exceeds the size limit." end
    code = code:match("^%s*(.-)%s*$")
    local version, client, payload = code:match("^MOBLOG:(%d+):(%u+):(.+)$")
    if version ~= "3" and version ~= "4" then
        return nil, "Invalid or unsupported MobLog package."
    end
    if client ~= Share.client then return nil, "This package is for a different WoW client." end
    if version == "4" then
        local api = C_EncodingUtil
        if not (api and api.DecodeBase64 and api.DecompressString and Enum and Enum.CompressionMethod) then
            return nil, "This client cannot read compressed MobLog packages."
        end
        local ok, compressed = pcall(api.DecodeBase64, payload)
        if ok and type(compressed) == "string" then
            ok, payload = pcall(api.DecompressString, compressed, Enum.CompressionMethod.Zlib)
        else
            ok = false
        end
        if not ok or type(payload) ~= "string" or #payload > maxPayloadBytes then
            return nil, "The received package is incomplete, damaged, or too large."
        end
    else
        local hash
        hash, payload = payload:match("^(%x%x%x%x%x%x%x%x):(.+)$")
        if not payload or string.format("%08x", HashPart(0, payload)) ~= hash then
            return nil, "The received package is incomplete or damaged."
        end
    end
    local encodedTitle, body = payload:match("^([^:]*):(.+)$")
    local title = Decode(encodedTitle)
    if not title then return nil, "Invalid import name." end
    local rows = {}
    for line in (body .. ";"):gmatch("([^;]*);") do
        if #rows >= Share.maxRows then return nil, "This package contains too many finds." end
        local r = ReadRow(line)
        if not r then return nil, "A record in the received package is invalid." end
        rows[#rows+1] = r
        if checkpoint then checkpoint() end
    end
    return rows, title
end

local function Safe(s) return Plain(s) and Escape(s) or "" end

function Share.Encode(rows, title, amounts, checkpoint)
    if #rows == 0 then return nil, "Select at least one find." end
    if #rows > Share.maxRows then return nil, "Select up to 50,000 finds per transfer." end
    local records = {}
    local titlePrefix = Safe(title) .. ":"
    local prefix = "MOBLOG:3:" .. Share.client .. ":"
    local bytes = #prefix + 9 + #titlePrefix
    for _, r in ipairs(rows) do
        local x, y = math.floor((r.x or 0)*100000+0.5), math.floor((r.y or 0)*100000+0.5)
        local record
        if r.type == "D" then
            record = table.concat({"D",r.item,r.npc,Safe(r.itemName),Safe(r.npcName)}, ",")
        elseif r.type == "M" then
            record = table.concat({"M",r.npc,r.map or 0,x,y,Safe(r.npcName)}, ",")
        else
            local loot = {}
            if amounts then
                for id, qty in pairs(r.loot or empty) do loot[#loot+1] = id .. "x" .. qty end
                table.sort(loot)
            end
            record = table.concat({"G",r.kind,r.map,x,y,r.resource or 0,Safe(r.name),r.locale or GetLocale(),table.concat(loot,"+")}, ",")
        end
        if not ReadRow(record) then
            return nil, "A selected find cannot be exported with these settings."
        end
        bytes = bytes + #record + (#records > 0 and 1 or 0)
        if bytes > maxPayloadBytes then return nil, "This export is too large. Narrow the selection." end
        records[#records+1] = record
        if checkpoint then checkpoint() end
    end
    local payload = titlePrefix .. table.concat(records, ";")
    local api = C_EncodingUtil
    if api and api.CompressString and api.EncodeBase64 and Enum and Enum.CompressionMethod then
        local ok, compressed = pcall(api.CompressString, payload, Enum.CompressionMethod.Zlib)
        if ok and type(compressed) == "string" then
            local encoded
            ok, encoded = pcall(api.EncodeBase64, compressed)
            if ok and type(encoded) == "string" then
                local code = "MOBLOG:4:" .. Share.client .. ":" .. encoded
                if #code <= Share.maxBytes then return code end
            end
        end
    end
    if bytes <= Share.maxBytes then
        return prefix .. string.format("%08x:", HashPart(0, payload)) .. payload
    end
    return nil, "This selection is too large for one transfer. Narrow the selection."
end

-- Coordinate buckets restrict proximity checks to neighbouring cells, including
-- points on opposite sides of a cell boundary.
local function Bucket(r)
    if r.type == "D" then return "D:" .. r.item .. ":" .. r.npc end
    return r.type .. ":" .. (r.npc or r.kind) .. ":" .. (r.map or 0)
end
local function Cell(x, y) return x .. ":" .. y end

local function SameResource(a,b)
    if a.kind == "fish" then return true end
    if a.name and b.name then
        if a.name == b.name then return true end
        if a.locale == b.locale then return false end
    end
    if a.resource and b.resource then return a.resource == b.resource end
    return not a.name and not b.name and not a.resource and not b.resource
end

local function Track(index,r)
    local key = Bucket(r)
    if not r.x then
        if index[key] then return false end
        index[key] = true
        return true
    end
    local cells = index[key] or {}
    local cx, cy = math.floor(r.x*200), math.floor(r.y*200)
    local rx, ry = ML.GatherMatchRadius(r.map)
    for ix=cx-1,cx+1 do
        for iy=cy-1,cy+1 do
            for _, other in ipairs(cells[Cell(ix,iy)] or empty) do
                local dx, dy = (r.x-other.x)/rx, (r.y-other.y)/ry
                if dx*dx + dy*dy < 1 and (r.type ~= "G" or SameResource(r,other)) then return false end
            end
        end
    end
    local cell = Cell(cx,cy)
    cells[cell] = cells[cell] or {}
    table.insert(cells[cell],r)
    index[key] = cells
    return true
end

local function PersonalGather(map,p,loot)
    return {type="G", map=map, kind=p.kind, x=p.x, y=p.y, name=p.name, resource=ML.GetGatherResourceID(map,p),
        locale=GetLocale(), loot=loot}
end

function Share.ExportPoint(map,p)
    local loot,key = {},ML.GatherPointKey(map,p)
    for id,item in pairs(ML.db.gatheredItems or empty) do
        local source = item.sources and item.sources[key]
        if source then loot[id]=source.quantity end
    end
    return PersonalGather(map,p,loot)
end

local function CreaturePlaces(mob,visit)
    local located=false
    for _,places in ipairs({mob.places or empty,mob.sightingPlaces or empty}) do
        for _,place in pairs(places) do
            local function Point(p)
                local r={type="M",npc=mob.id,npcName=mob.name,map=place.map,x=p.x,y=p.y}
                if ML.CanPinLocation(r) then visit(r); located=true end
            end
            if place.points and next(place.points) then
                for _,p in pairs(place.points) do Point(p) end
            else Point(place) end
        end
    end
    return located
end

function Share.Personal(itemFilter)
    local rows, index, loot = {}, {}, {}
    local function Add(r)
        if Track(index,r) then rows[#rows+1] = r end
    end
    for id, item in pairs(ML.db.gatheredItems or empty) do
        for key,s in pairs(item.sources or empty) do
            loot[key] = loot[key] or {}
            loot[key][id] = s.quantity
        end
    end
    for map, points in pairs(ML.db.gatherLocations or empty) do
        for _, p in ipairs(points) do
            local amounts = loot[ML.GatherPointKey(map,p)]
            if not itemFilter or (amounts and amounts[itemFilter]) then Add(PersonalGather(map,p,amounts)) end
        end
    end
    for npc,mob in pairs(ML.db.mobs) do
        if not itemFilter then
            local located=CreaturePlaces(mob,Add)
            if not located then rows[#rows+1] = {type="M",npc=npc,npcName=mob.name} end
        end
        for id,drop in pairs(mob.items or empty) do
            if (not itemFilter or itemFilter == id) and (drop.quantity or 0)>0 then
                Add({type="D",npc=npc,npcName=mob.name,item=id,itemName=drop.name})
            end
        end
    end
    return rows
end

function Share.Batches() return ML.db.sharedFinds or empty end

local function Imports()
    if imported then return imported end
    imported = {G={},M={},D={},gatherItems={}}
    for _,batch in ipairs(Share.Batches()) do
        for _,r in ipairs(batch.rows) do
            local group = imported[r.type]
            local key = r.type == "G" and r.map or (r.type == "D" and r.item or r.npc)
            group[key] = group[key] or {}
            table.insert(group[key],r)
            if r.type=="G" then
                local function AddItem(id)
                    local points=imported.gatherItems[id] or {}
                    imported.gatherItems[id]=points
                    points[#points+1]=r
                end
                for id in pairs(r.loot or empty) do AddItem(id) end
                if r.resource and not (r.loot and r.loot[r.resource]) then AddItem(r.resource) end
            end
        end
    end
    return imported
end

function Share.Groups(kind) return Imports()[kind] end

function Share.New(rows, checkpoint)
    local index, indexedMaps, indexedNPCs, indexedItems = {},{},{},{}
    local imports=Imports()
    for _,r in ipairs(rows) do
        if checkpoint then checkpoint() end
        local mob=r.npc and ML.db.mobs[r.npc]
        if r.type=="G" and not indexedMaps[r.map] then
            indexedMaps[r.map]=true
            for _,p in ipairs((ML.db.gatherLocations or empty)[r.map] or empty) do
                Track(index,PersonalGather(r.map,p))
            end
            for _,p in ipairs(imports.G[r.map] or empty) do Track(index,p) end
        elseif r.type=="M" and not indexedNPCs[r.npc] then
            indexedNPCs[r.npc]=true
            if mob then CreaturePlaces(mob,function(p) Track(index,p) end) end
            local locations=imports.M[r.npc]
            for _,p in ipairs(locations or empty) do Track(index,p) end
            if mob or locations then index["M:"..r.npc..":0"]=true end
        elseif r.type=="D" then
            if not indexedItems[r.item] then
                indexedItems[r.item]=true
                for _,p in ipairs(imports.D[r.item] or empty) do Track(index,p) end
            end
            local drop=mob and mob.items and mob.items[r.item]
            if drop and (drop.quantity or 0)>0 then Track(index,r) end
        end
    end
    local result = {}
    for _,r in ipairs(rows) do
        if checkpoint then checkpoint() end
        if Track(index,r) then result[#result+1] = r end
        if r.type=="M" then index["M:"..r.npc..":0"]=true end
    end
    return result, #rows-#result
end

local function Changed()
    imported, mapViews = nil, {}
    ML.InvalidateItemCatalog()
    ML.RefreshGatherPins()
    ML.RefreshMinimapGatherPins()
    if ML.IsMobLogVisible() then ML.Refresh() end
end

function Share.Save(rows,title,checkpoint)
    local new = Share.New(rows,checkpoint)
    if #new == 0 then return 0 end
    local batch = {title=title ~= "" and title or "Shared finds", date=time(), rows=new}
    for _,r in ipairs(new) do r.shared=true end
    ML.db.sharedFinds = ML.db.sharedFinds or {}
    table.insert(ML.db.sharedFinds,1,batch)
    Changed()
    return #new
end

function Share.Remove(selection)
    local batches = ML.db.sharedFinds or empty
    local removed = 0
    for i=#batches,1,-1 do
        local rows = batches[i].rows
        for j=#rows,1,-1 do
            if selection[rows[j]] then table.remove(rows,j); removed=removed+1 end
        end
        if #rows == 0 then table.remove(batches,i) end
    end
    if removed > 0 then Changed() end
    return removed
end

function Share.InvalidateMap(map) mapViews[map] = nil end

function Share.MapPoints(map,personal)
    if not map or ML.db.options.sharedGatherPins == false then return personal end
    local others = Imports().G[map]
    if not others then return personal end
    if not mapViews[map] then
        local points,index = {},{}
        for _,p in ipairs(personal) do
            points[#points+1]=p
            Track(index,PersonalGather(map,p))
        end
        for _,p in ipairs(others) do
            if Track(index,p) then points[#points+1] = p end
        end
        mapViews[map] = points
    end
    return mapViews[map]
end

function Share.GatherTooltip(tooltip,p)
    tooltip:AddLine("Imported gathering spot",0.55,0.80,1)
    tooltip:AddLine(string.format("%s · %.1f / %.1f",Share.Zone(p.map),p.x*100,p.y*100),1,1,1)
    for id,qty in pairs(p.loot or empty) do tooltip:AddDoubleLine(ItemName(id),tostring(qty),1,1,1,1,1,1) end
    tooltip:Show()
end
