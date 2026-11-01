-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local mapNames, zoneRegions = nil, {}

function ML.AreaFilterKey(filter)
    if type(filter)~="table" then return tostring(filter or "all") end
    return table.concat({filter.world,filter.region,filter.area,filter.source or "all"},"\031")
end

function ML.LocationSource(filter)
    return type(filter)=="table" and (filter.source or "all") or "all"
end

function ML.AreaCoordinatesAreAll(filter)
    return not filter or filter=="all" or (type(filter)=="table" and filter.world=="all" and filter.region=="all" and filter.area=="all")
end

function ML.AreaFilterIsAll(filter)
    return ML.AreaCoordinatesAreAll(filter) and ML.LocationSource(filter)=="all"
end

local function MapNames()
    if mapNames then return mapNames end
    mapNames={}
    if C_Map and C_Map.GetMapChildrenInfo then
        -- Read the static map hierarchy once, on opening a navigation menu.
        local ok,maps=pcall(C_Map.GetMapChildrenInfo,946,nil,true)
        if ok and type(maps)=="table" then
            for _,info in ipairs(maps) do
                local name,id=ML.Public(info.name),ML.Public(info.mapID)
                if type(name)=="string" and type(id)=="number" then
                    mapNames[name]=mapNames[name] or {}
                    mapNames[name][#mapNames[name]+1]=id
                end
            end
        end
    end
    return mapNames
end

function ML.CatalogAreaRegions(id)
    if zoneRegions[id] then return zoneRegions[id] end
    local regions={}
    local world=type(id)=="string" and tonumber(id:match("^world:(%d+)$"))
    local instanceMap=world and ML.InstanceMaps and ML.InstanceMaps[world]
    if instanceMap then
        local key,name=ML.MapRegion(instanceMap)
        if key~="other" then regions[key]=name end
    end
    for _,map in ipairs(MapNames()[ML.CatalogAreaName(id)] or {}) do
        local key,name=ML.MapRegion(map)
        regions[key]=name
    end
    if not next(regions) then regions.other="Other areas" end
    zoneRegions[id]=regions
    return regions
end

local function MatchesRegion(key,name,filter)
    return (filter.region=="all" or filter.region==key) and
        (filter.world=="all" or ML.RegionWorld(key,name)==filter.world)
end

function ML.CatalogZoneMatchesArea(id,filter)
    if ML.LocationSource(filter)=="encounters" then return false end
    if ML.AreaCoordinatesAreAll(filter) then return true end
    if type(filter)~="table" then return id==filter end
    if filter.area~="all" and ML.CatalogAreaName(id)~=filter.area then return false end
    for key,name in pairs(ML.CatalogAreaRegions(id)) do if MatchesRegion(key,name,filter) then return true end end
    return false
end

function ML.RecordedPlaceMatchesArea(place,filter)
    if ML.LocationSource(filter)=="habitats" or not ML.ValidLocationName(place.zone) then return false end
    if ML.AreaCoordinatesAreAll(filter) then return true end
    if type(filter)~="table" then return place.zone==ML.CatalogAreaName(filter) or place.sub==ML.CatalogAreaName(filter) end
    if filter.area~="all" and filter.area~=place.zone and filter.area~=place.sub then return false end
    local key,name=ML.MapRegion(place.map)
    return MatchesRegion(key,name,filter)
end

local function AvailableAreas(source)
    local byName,areas={},{}
    local function Add(name,regions)
        if not ML.ValidLocationName(name) then return end
        local area=byName[name]
        if not area then area={name=name,regions={}}; byName[name]=area; areas[#areas+1]=area end
        for key,label in pairs(regions) do area.regions[key]=label end
    end
    for _,choice in ipairs(source~="encounters" and ML.CatalogAreas() or {}) do
        if choice.key~="all" then Add(choice.label,ML.CatalogAreaRegions(choice.key)) end
    end
    for _,mob in pairs(source~="habitats" and ML.db.mobs or {}) do
        for _,places in ipairs({mob.places or {},mob.sightingPlaces or {}}) do
            for _,place in pairs(places) do
                local key,name=ML.MapRegion(place.map)
                Add(place.zone,{[key]=name})
            end
        end
    end
    table.sort(areas,function(a,b) return string.lower(a.name)<string.lower(b.name) end)
    return areas
end

-- Same dimensions, strip, chevrons and cascading selection as the Areas tab.
function ML.BuildAreaNavigation(parent,ui,x,y,width,changed)
    local nav=ui.Panel(parent); nav:SetPoint("TOPLEFT",x,y); nav:SetSize(width,36)
    local strip=nav:CreateTexture(nil,"ARTWORK"); strip:SetColorTexture(0.16,0.15,0.14,1)
    strip:SetPoint("TOPLEFT",4,-4); strip:SetPoint("BOTTOMRIGHT",-4,4)
    local filter={world="all",region="all",area="all",source="all"}
    local buttons,menus,labels={},{},{}
    local kinds={"source","world","region","area"}
    local defaults={source="All locations",world="All worlds",region="All regions",area="All areas"}
    local sources={all="All locations",encounters="Your encounters",habitats="Known habitats"}
    function nav:CloseMenu() for _,menu in ipairs(menus) do menu:Hide() end end
    local function UpdateLabels()
        for _,kind in ipairs(kinds) do buttons[kind].label:SetText((labels[kind] or defaults[kind]).."  v") end
    end
    function nav:SetSelection(value,notify)
        filter=type(value)=="table" and ML.CopyViewTable(value) or {world="all",region="all",area="all"}
        filter.source=sources[filter.source] and filter.source or "all"
        labels={}
        labels.source=sources[filter.source]
        for _,kind in ipairs({"world","region"}) do
            local key=filter[kind]
            if key~="all" then
                local map=tonumber(key:match("^map:(%d+)$"))
                local info=map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
                labels[kind]=info and ML.Public(info.name) or (kind=="world" and "Other worlds" or "Other areas")
            end
        end
        if filter.area~="all" then labels.area=filter.area end
        self.area=ML.AreaFilterIsAll(filter) and "all" or ML.CopyViewTable(filter)
        self:CloseMenu(); UpdateLabels()
        if notify then changed(self.area) end
    end
    function nav:Reset() self:SetSelection("all",false) end
    local function Options(kind)
        if kind=="source" then return {
            {key="all",label=sources.all},{key="encounters",label=sources.encounters},{key="habitats",label=sources.habitats},
        } end
        local found={}
        for _,area in ipairs(AvailableAreas(filter.source)) do
            for key,name in pairs(area.regions) do
                local world,worldName=ML.RegionWorld(key,name)
                if kind=="world" then found[world]=worldName
                elseif filter.world=="all" or filter.world==world then
                    if kind=="region" then found[key]=name
                    elseif filter.region=="all" or filter.region==key then found[area.name]=area.name end
                end
            end
        end
        local values={}
        for key,label in pairs(found) do values[#values+1]={key=key,label=label} end
        table.sort(values,function(a,b) if a.label==b.label then return a.key<b.key end; return string.lower(a.label)<string.lower(b.label) end)
        table.insert(values,1,{key="all",label=defaults[kind]})
        return values
    end
    local sizes={152,178,210,width-548}
    local offset=4
    for index,kind in ipairs(kinds) do
        local field=kind
        local button=CreateFrame("Button",nil,nav); buttons[field]=button
        button:SetPoint("LEFT",offset,0); button:SetSize(sizes[index],28); offset=offset+sizes[index]
        button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
        button.label=ui.Text(button,13,{1,0.82,0}); button.label:SetPoint("LEFT",15,0); button.label:SetSize(sizes[index]-37,20); button.label:SetWordWrap(false)
        for _,edge in ipairs({{6,math.pi/4},{-6,-math.pi/4}}) do
            local texture=button:CreateTexture(nil,"OVERLAY"); texture:SetColorTexture(0.65,0.60,0.52,1); texture:SetSize(2,18)
            texture:SetPoint("RIGHT",-6,edge[1]); texture:SetRotation(edge[2])
        end
        local menu=ui.Panel(parent); menu:SetSize(344,250); menus[#menus+1]=menu
        if field=="area" then menu:SetPoint("TOPRIGHT",button,"BOTTOMRIGHT",0,-5) else menu:SetPoint("TOPLEFT",button,"BOTTOMLEFT",0,-5) end
        menu:SetFrameLevel(parent:GetFrameLevel()+80)
        local scroll=CreateFrame("ScrollFrame",nil,menu,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",10,-10); scroll:SetSize(296,230)
        local content=CreateFrame("Frame",nil,scroll); content:SetSize(292,1); scroll:SetScrollChild(content)
        local rows,values={},{}
        local function Render()
            local first=math.max(1,math.floor(scroll:GetVerticalScroll()/28)+1)
            local used=0
            for i=first,math.min(#values,first+9) do
                used=used+1
                local row=rows[used]
                if not row then
                    row=CreateFrame("Button",nil,content); row:SetSize(292,28)
                    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
                    row.label=ui.Text(row,12); row.label:SetPoint("LEFT",8,0); row.label:SetSize(276,20); row.label:SetWordWrap(false)
                    row:SetScript("OnClick",function(self)
                        filter[field]=self.entry.key; labels[field]=self.entry.label
                        if field=="source" then
                            filter.world,filter.region,filter.area="all","all","all"
                            labels.world,labels.region,labels.area=nil,nil,nil
                        elseif field=="world" then filter.region,filter.area="all","all"; labels.region,labels.area=nil,nil
                        elseif field=="region" then filter.area="all"; labels.area=nil end
                        nav:CloseMenu(); UpdateLabels()
                        nav.area={world=filter.world,region=filter.region,area=filter.area,source=filter.source}
                        changed(nav.area)
                    end)
                    rows[used]=row
                end
                row.entry=values[i]; row:SetPoint("TOPLEFT",0,-(i-1)*28); row.label:SetText(values[i].label); row:Show()
            end
            for i=used+1,#rows do rows[i]:Hide() end
        end
        scroll:HookScript("OnVerticalScroll",Render)
        button:SetScript("OnClick",function()
            local show=not menu:IsShown(); nav:CloseMenu()
            if show then values=Options(field); content:SetHeight(math.max(1,#values*28)); scroll:SetVerticalScroll(0); menu:Show(); Render() end
        end)
        button:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:AddLine(self.label:GetText(),1,0.82,0); GameTooltip:Show() end)
        button:SetScript("OnLeave",function() GameTooltip:Hide() end)
        menu:Hide()
    end
    nav.area="all"; UpdateLabels(); nav:HookScript("OnHide",function(self) self:CloseMenu() end)
    return nav
end
