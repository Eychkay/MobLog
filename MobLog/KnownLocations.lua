-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local counts,sourceData={},nil
local cachedNPC,cachedPage,cachedPoints
local PAGE_SIZE=20

local function Packed(id)
    local catalog=ML.TrinityData and ML.TrinityData.ready and ML.TrinityData
    local data=catalog and (catalog.uiSpawns or catalog.spawns)
    if sourceData~=data then counts={}; cachedNPC,cachedPage,cachedPoints=nil,nil,nil; sourceData=data end
    return data and data[id]
end

function ML.KnownLocationCount(id)
    local packed=Packed(id)
    if not packed or packed=="" then return 0 end
    if not counts[id] then local _,n=packed:gsub(";",""); counts[id]=n+1 end
    return counts[id]
end

function ML.KnownLocationPage(id,page)
    local count=ML.KnownLocationCount(id)
    local pages=math.max(1,math.ceil(count/PAGE_SIZE))
    page=math.max(1,math.min(page or 1,pages))
    if cachedNPC==id and cachedPage==page then return cachedPoints,page,pages end
    local points={}
    local first,last=(page-1)*PAGE_SIZE+1,page*PAGE_SIZE
    local index=0
    for record in (Packed(id) or ""):gmatch("[^;]+") do
        index=index+1
        if index>last then break end
        if index>=first then
            if ML.TrinityData.uiSpawns then
                local map,x,y=record:match("^([^,]+),([^,]+),([^,]+)$")
                points[#points+1]={map=tonumber(map),x=tonumber(x),y=tonumber(y),uiCoordinates=true,known=true}
            else
                local map,x,y,z,area,flags=record:match("^([^,]+),([^,]+),([^,]+),([^,]+),([^,]+),([^,]+)$")
                points[#points+1]={worldMap=tonumber(map),worldX=tonumber(x),worldY=tonumber(y),worldZ=tonumber(z),areaID=tonumber(area),flags=tonumber(flags),known=true}
            end
        end
    end
    cachedNPC,cachedPage,cachedPoints=id,page,points
    return points,page,pages
end

local function Finite(value)
    value=ML.Public(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge and value or nil
end

local function VectorXY(vector)
    if not ML.Public(vector) then return nil end
    local ok,x,y=pcall(function() return vector:GetXY() end)
    if ok then return Finite(x),Finite(y) end
end

local function AmbiguousFloor(map,info)
    local types=Enum and Enum.UIMapType
    local kind=ML.Public(info.mapType)
    local dungeon=types and (kind==types.Dungeon or kind==types.Micro)
    if not C_Map.GetMapGroupID or not C_Map.GetMapGroupMembersInfo then return dungeon end
    local ok,group=pcall(C_Map.GetMapGroupID,map)
    group=ok and Finite(group)
    if group and group>0 then
        local success,members=pcall(C_Map.GetMapGroupMembersInfo,group)
        if success and type(members)=="table" then return #members>1 end
        return true
    end
    return false
end

local function CanWaypoint(place)
    if not ML.CanPinLocation(place) or not C_Map or not C_Map.CanSetUserWaypointOnMap then return false end
    local ok,allowed=pcall(C_Map.CanSetUserWaypointOnMap,place.map)
    return ok and ML.Public(allowed)==true
end

local worldNames={}
local function WorldName(id)
    if not Finite(id) or id<0 then return nil end
    if worldNames[id] then return worldNames[id] end
    -- These are server map IDs, not C_Map UI-map IDs. In particular, instance
    -- spawns often have areaID=0 while their server map still names the dungeon.
    if GetRealZoneText then
        local ok,name=pcall(GetRealZoneText,id)
        name=ok and ML.Public(name)
        if type(name)=="string" and name~="" then worldNames[id]=name; return name end
    end
end

local function LocationMap(place)
    if type(place.map)=="number" and place.map>0 then return place.map end
    if place.known then
        -- A dungeon entry map is independent of a verified spawn coordinate.
        -- Never use a server map ID directly as a UI-map ID or invent a pin.
        return (ML.InstanceMaps and ML.InstanceMaps[place.worldMap]) or place.viewMap
    end
end

local function OpenLocation(place)
    if InCombatLockdown() then ML.Print("Please open the map after combat."); return false end
    if CanWaypoint(place) then return ML.PinLocation(place) end
    local map=LocationMap(place)
    if not map or not C_Map or not C_Map.OpenWorldMap then
        ML.Print(place.reason or "Map unavailable for this location."); return false
    end
    local ok,info=pcall(C_Map.GetMapInfo,map)
    if not ok or type(ML.Public(info))~="table" then
        ML.Print("This location's map is unavailable in your client."); return false
    end
    ok=pcall(C_Map.OpenWorldMap,map)
    if not ok then ML.Print("Could not open this location's map.") end
    return ok
end

function ML.ResolveKnownLocation(place)
    if place.resolved or (place.retryAfter and GetTime()<place.retryAfter) then return place end
    place.retryAfter=GetTime()+30
    if place.uiCoordinates then
        local ok,info=pcall(C_Map.GetMapInfo,place.map)
        if ok and type(ML.Public(info))=="table" then
            place.zone=ML.Public(info.name) or ("Map #"..place.map)
            place.sub=""; place.viewMap=place.map
            place.resolved=true; place.reason=nil
        else
            place.zone="Map #"..tostring(place.map)
            place.reason="This location's map is unavailable in your client."
        end
        return place
    end
    place.map,place.x,place.y,place.viewMap=nil,nil,nil,nil
    local area=(place.areaID and place.areaID>0) and ML.CatalogAreaName(place.areaID)
    local world=WorldName(place.worldMap)
    place.zone=world or area or ("Map #"..tostring(place.worldMap or "?"))
    place.sub=(world and area and area~=world) and area or ""
    place.reason="Map coordinates unavailable for this spawn point."
    if not C_Map or not C_Map.GetMapPosFromWorldPos or not C_Map.GetWorldPosFromMapPos or not CreateVector2D then return place end
    if not Finite(place.worldMap) or not Finite(place.worldX) or not Finite(place.worldY) then return place end
    local ok,map,position=pcall(C_Map.GetMapPosFromWorldPos,place.worldMap,CreateVector2D(place.worldX,place.worldY))
    map=ok and Finite(map)
    if not map or map<=0 then return place end
    local x,y=VectorXY(position)
    if not x or not y or x<0 or x>1 or y<0 or y>1 then return place end
    -- Require a round trip on the original server map. UI-map IDs and world-map
    -- IDs are different namespaces; never guess a transform or exchange axes.
    local backOK,backWorld,back=pcall(C_Map.GetWorldPosFromMapPos,map,position)
    local wx,wy=VectorXY(back)
    if not backOK or Finite(backWorld)~=place.worldMap or not wx or not wy or (wx-place.worldX)^2+(wy-place.worldY)^2>1 then return place end
    local infoOK,info=pcall(C_Map.GetMapInfo,map)
    info=infoOK and ML.Public(info)
    if type(info)~="table" then return place end
    place.viewMap=map
    if AmbiguousFloor(map,info) then
        place.reason="The floor cannot be verified for this spawn point. No waypoint is placed."
        return place
    end
    local name=ML.Public(info.name)
    if type(name)=="string" and name~="" then
        local types=Enum and Enum.UIMapType
        local kind=ML.Public(info.mapType)
        local dungeon=types and (kind==types.Dungeon or kind==types.Micro)
        if world and dungeon then
            place.sub=area and area~=world and area or (name~=world and name or "")
        else
            place.zone=name
            place.sub=area and area~=name and area or ""
        end
    end
    place.map,place.x,place.y=map,x,y
    place.reason=nil; place.resolved=true
    return place
end

function ML.BuildLocationBrowser(parent,scroll,ui,onPin)
    local view={active=false,rows={},headers={},closed={personal=false,known=true},page=1,entries={}}
    function view:Hide()
        self.active=false
        for _,row in ipairs(self.rows) do row:Hide() end
        for _,header in ipairs(self.headers) do header:Hide() end
    end
    function view:Draw()
        if not self.active or not parent:IsVisible() then return end
        local y=scroll:GetVerticalScroll()
        local used,usedHeaders=0,0
        local low,high=1,#self.entries
        while low<=high do
            local middle=math.floor((low+high)/2)
            local entry=self.entries[middle]
            if entry.offset+entry.height<y-50 then low=middle+1 else high=middle-1 end
        end
        for i=low,#self.entries do
            local entry=self.entries[i]
            if entry.offset>y+scroll:GetHeight()+50 then break end
            if entry.header then
                usedHeaders=usedHeaders+1
                local header=self.headers[usedHeaders]
                if not header then
                    header=CreateFrame("Button",nil,parent,"BackdropTemplate"); header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
                    header.label=ui.Text(header,12); header.label:SetPoint("LEFT",8,0); header.label:SetHeight(18); header.label:SetWordWrap(false)
                    header:SetScript("OnClick",function(button) self.closed[button.entry.key]=not self.closed[button.entry.key]; self:Show(self.mob,self.top) end)
                    header.previous=ui.Button(header,"<",22,function() self.page=math.max(1,self.page-1); self:Show(self.mob,self.top) end)
                    header.previous:SetPoint("RIGHT",-27,0); header.previous:SetHeight(22)
                    header.next=ui.Button(header,">",22,function() self.page=self.page+1; self:Show(self.mob,self.top) end)
                    header.next:SetPoint("RIGHT",-3,0); header.next:SetHeight(22)
                    self.headers[usedHeaders]=header
                end
                header.entry=entry; header:SetPoint("TOPLEFT",0,-entry.offset); header:SetSize(412,28)
                local known=entry.key=="known"
                local paging=known and not self.closed.known and self.pages>1
                header.previous:SetShown(paging); header.next:SetShown(paging)
                header.previous:SetEnabled(self.page>1); header.next:SetEnabled(self.page<self.pages)
                header.label:SetWidth(paging and 350 or 396)
                header.label:SetText((self.closed[entry.key] and "+ " or "- ")..entry.label.." ("..entry.count..")"..(paging and (" · "..self.page.."/"..self.pages) or ""))
                if known then header:SetBackdropColor(0.045,0.075,0.10,1); header.label:SetTextColor(0.55,0.76,0.94)
                else header:SetBackdropColor(0.11,0.09,0.06,1); header.label:SetTextColor(0.92,0.76,0.45) end
                header:Show()
            else
                used=used+1
                local row=self.rows[used]
                if not row then
                    row=CreateFrame("Button",nil,parent,"BackdropTemplate"); row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
                    row.title=ui.Text(row,12); row.title:SetPoint("TOPLEFT",8,-5); row.title:SetSize(354,16); row.title:SetWordWrap(false)
                    row.coords=ui.Text(row,10); row.coords:SetPoint("TOPLEFT",8,-25); row.coords:SetSize(354,14); row.coords:SetWordWrap(false)
                    row.pin=row:CreateTexture(nil,"ARTWORK"); row.pin:SetPoint("RIGHT",-5,0); row.pin:SetSize(20,20); row.pin:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
                    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
                    row:SetScript("OnClick",function(button)
                        local place=button.place
                        if not place then return end
                        if place.known then
                            place.resolved,place.retryAfter=nil,nil
                            ML.ResolveKnownLocation(place); self:Draw()
                        end
                        if OpenLocation(place) then onPin() end
                    end)
                    row:SetScript("OnEnter",function(button)
                        local place=button.place
                        if not place then return end
                        GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
                        if place.known then
                            GameTooltip:AddLine("Known spawn point",0.55,0.76,0.94)
                            GameTooltip:AddLine("Catalog position, separate from your discoveries. This is not a live NPC location.",0.85,0.82,0.74,true)
                            if (place.flags or 0)%2==1 then GameTooltip:AddLine("Availability may depend on difficulty or phase.",0.85,0.82,0.74,true) end
                            if (place.flags or 0)>=2 then GameTooltip:AddLine("This NPC may move away from its spawn point.",0.85,0.82,0.74,true) end
                        else
                            GameTooltip:AddLine("Your discovery",0.92,0.76,0.45)
                            GameTooltip:AddLine("Your recorded player position at the encounter, not the NPC's exact position.",0.85,0.82,0.74,true)
                        end
                        if place.reason then GameTooltip:AddLine(place.reason,0.85,0.82,0.74,true) end
                        local action=CanWaypoint(place) and "Click to open the map and place a waypoint." or
                            (LocationMap(place) and "Click to open the map. No exact spawn position is marked." or "Map unavailable for this location.")
                        GameTooltip:AddLine(action,1,1,1,true)
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave",function() GameTooltip:Hide() end)
                    self.rows[used]=row
                end
                row:SetPoint("TOPLEFT",12,-entry.offset); row:SetSize(400,entry.height-4)
                local place=entry.place
                if place and place.known then ML.ResolveKnownLocation(place) end
                row.place=place; row.pin:SetShown(place~=nil)
                if place then
                    local label=place.zone..(place.sub~="" and (" · "..place.sub) or "")
                    local pin=ML.CanPinLocation(place)
                    local waypoint=CanWaypoint(place)
                    row.title:SetText(label..(place.known and "" or (" · "..place.kind.." · "..((place.count or 0)>0 and ("×"..place.count) or "Historic point"))))
                    local map=LocationMap(place)
                    row.coords:SetText((place.known and "Known spawn point · " or "Your discovery · ")..(pin and (string.format("%.1f / %.1f",place.x*100,place.y*100)..(waypoint and " · Click to pin" or " · Click to open map")) or
                        (map and "Click to open map · Exact position unavailable" or "Map coordinates unavailable")))
                    row.pin:SetAlpha((waypoint or map) and 1 or 0.3)
                    if place.known then row:SetBackdropColor(0.035,0.055,0.075,1); row.title:SetTextColor(0.55,0.76,0.94)
                    else row:SetBackdropColor(0.075,0.06,0.04,1); row.title:SetTextColor(0.92,0.76,0.45) end
                else row.title:SetText(entry.message); row.title:SetTextColor(0.72,0.65,0.52); row.coords:SetText(""); row:SetBackdropColor(0.045,0.04,0.03,1) end
                row:Show()
            end
        end
        for i=used+1,#self.rows do self.rows[i]:Hide() end
        for i=usedHeaders+1,#self.headers do self.headers[i]:Hide() end
    end
    function view:Show(mob,top)
        if not self.mob or self.mob.id~=mob.id then self.page=1 end
        self.active,self.mob,self.top=true,mob,top
        local personal={}
        for _,place in ipairs(ML.LocationPoints({places=mob.places or {}})) do place.kind="Kill"; personal[#personal+1]=place end
        for _,place in ipairs(ML.LocationPoints({places=mob.sightingPlaces or {}})) do place.kind="Seen"; personal[#personal+1]=place end
        table.sort(personal,function(a,b) if (a.last or 0)==(b.last or 0) then return a.key..a.kind<b.key..b.kind end; return (a.last or 0)>(b.last or 0) end)
        local count=ML.KnownLocationCount(mob.id)
        self.pages=math.max(1,math.ceil(count/PAGE_SIZE)); self.page=math.max(1,math.min(self.page,self.pages))
        local known={}
        if not self.closed.known then known,self.page,self.pages=ML.KnownLocationPage(mob.id,self.page) end
        self.entries={}
        local offset=top
        local function Section(key,label,total,points,message)
            self.entries[#self.entries+1]={header=true,key=key,label=label,count=total,offset=offset,height=32}; offset=offset+32
            if self.closed[key] then return end
            if #points==0 then self.entries[#self.entries+1]={message=message,offset=offset,height=28}; offset=offset+28 end
            for _,place in ipairs(points) do self.entries[#self.entries+1]={place=place,offset=offset,height=50}; offset=offset+50 end
        end
        Section("personal","Your discoveries",#personal,personal,"No personal encounter locations recorded.")
        Section("known","Known locations",count,known,ML.CatalogUnavailableText() or "No spawn locations are known for this NPC.")
        parent:SetHeight(math.max(140,offset)); ML.SetViewScroll(scroll,scroll:GetVerticalScroll()); self:Draw()
    end
    scroll:HookScript("OnVerticalScroll",function() view:Draw() end)
    return view
end
