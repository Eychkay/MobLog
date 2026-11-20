-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local editor, provider

local function CreatureName(id)
    local mob = id > 0 and ML.GetMob(id)
    return mob and mob.name or ("NPC #" .. id)
end

local function TargetID()
    if ML.Public(UnitPlayerControlled("target")) == false then
        return ML.CreatureID(UnitGUID("target"))
    end
end

local function RenderChanges()
    if provider then provider:RefreshAllData() end
    if ML.Refresh then ML.Refresh(true) end
end

local function BuildEditor(map)
    local panel = CreateFrame("Frame", nil, map, "BackdropTemplate")
    local width, baseHeight = 420, 232
    panel:SetSize(width, baseHeight)
    panel:SetPoint("CENTER")
    panel:SetFrameStrata("FULLSCREEN_DIALOG")
    panel:SetToplevel(true)
    panel:SetClampedToScreen(true)
    panel:EnableMouse(true)
    panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}})
    panel:SetBackdropColor(0.87,0.75,0.53,1)
    panel:SetBackdropBorderColor(0.63,0.42,0.20,1)
    local paper = panel:CreateTexture(nil,"BACKGROUND",nil,1)
    paper:SetPoint("TOPLEFT",5,-5)
    paper:SetPoint("BOTTOMRIGHT",-5,5)
    if C_Texture and C_Texture.GetAtlasInfo("QuestBG-Parchment") then
        paper:SetAtlas("QuestBG-Parchment")
    else
        paper:SetTexture("Interface\\QuestFrame\\QuestBG")
        paper:SetTexCoord(0.05,0.45,0.05,0.45)
    end
    paper:SetVertexColor(0.97,0.93,0.84)

    local function Ink(frame, font)
        local label = frame:CreateFontString(nil,"OVERLAY",font)
        label:SetTextColor(0.26,0.15,0.065)
        label:SetShadowColor(0,0,0,0)
        label:SetJustifyH("LEFT")
        return label
    end
    local function Label(text,x,y,font)
        local label = Ink(panel,font or "GameFontNormalSmall")
        label:SetPoint("TOPLEFT",x,y)
        label:SetText(text)
        return label
    end
    local function EditBox(parent,max)
        local box = CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
        box:SetHeight(26)
        box:SetMaxLetters(max)
        box:SetAutoFocus(false)
        return box
    end
    local function Button(text,width,action)
        local button = CreateFrame("Button",nil,panel,"UIPanelButtonTemplate")
        button:SetSize(width,24)
        button:SetText(text)
        button:SetScript("OnClick",action)
        return button
    end
    local icon=panel:CreateTexture(nil,"ARTWORK")
    icon:SetSize(34,34)
    icon:SetPoint("TOPLEFT",18,-17)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Note_01")
    local heading=Label("Map note",64,-15,"GameFontNormalLarge")
    local location=Label("",64,-40)
    local rule=panel:CreateTexture(nil,"ARTWORK")
    rule:SetColorTexture(0.45,0.28,0.11,0.4)
    rule:SetPoint("TOPLEFT",18,-62)
    rule:SetPoint("TOPRIGHT",-18,-62)
    rule:SetHeight(1)
    Label("Note",19,-74)
    local note=EditBox(panel,180)
    note:SetPoint("TOPLEFT",24,-93)
    note:SetPoint("TOPRIGHT",-24,-93)
    note:SetScript("OnEscapePressed",function() panel:Hide() end)
    Label("Linked creature (optional)",19,-130)

    local function ChoiceRow(parent)
        local row=CreateFrame("Button",nil,parent)
        row:SetHeight(24)
        local highlight=row:CreateTexture(nil,"HIGHLIGHT")
        highlight:SetAllPoints()
        highlight:SetColorTexture(0.54,0.34,0.12,0.23)
        row.label=Ink(row,"GameFontNormal")
        row.label:SetPoint("LEFT",10,0)
        row.label:SetPoint("RIGHT",-24,0)
        row.label:SetWordWrap(false)
        return row
    end
    local dropdown=ChoiceRow(panel)
    dropdown:SetPoint("TOPLEFT",19,-150)
    dropdown:SetPoint("TOPRIGHT",-19,-150)
    dropdown:SetHeight(29)
    local field=dropdown:CreateTexture(nil,"BACKGROUND")
    field:SetAllPoints()
    field:SetColorTexture(0.48,0.30,0.14,0.25)
    local arrow=Ink(dropdown,"GameFontNormal")
    arrow:SetPoint("RIGHT",-8,0)
    arrow:SetText("▼")

    local menu=CreateFrame("Frame",nil,panel,"BackdropTemplate")
    menu:SetPoint("TOPLEFT",dropdown,"BOTTOMLEFT",0,-2)
    menu:SetPoint("TOPRIGHT",dropdown,"BOTTOMRIGHT",0,-2)
    menu:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,
        insets={left=3,right=3,top=3,bottom=3}})
    menu:SetBackdropColor(0.90,0.79,0.59,1)
    menu:SetBackdropBorderColor(0.63,0.42,0.20,1)
    local search=EditBox(menu,60)
    search:SetPoint("TOPLEFT",11,-8)
    search:SetPoint("TOPRIGHT",-11,-8)
    local placeholder=Ink(search,"GameFontNormalSmall")
    placeholder:SetPoint("LEFT",3,0)
    placeholder:SetTextColor(0.78,0.70,0.56)
    placeholder:SetText("Search by name or NPC ID")
    local empty=Ink(menu,"GameFontNormalSmall")
    empty:SetPoint("TOPLEFT",12,-64)
    empty:SetText("No matching creatures")
    local function CloseMenu()
        search:ClearFocus()
        menu:Hide()
        panel:SetHeight(baseHeight)
        arrow:SetText("▼")
    end
    local function Select(id)
        panel.npcID=id
        dropdown.label:SetText(id>0 and (CreatureName(id).." (#"..id..")") or "No creature linked")
        CloseMenu()
    end
    local none=ChoiceRow(menu)
    none:SetPoint("TOPLEFT",5,-37)
    none:SetPoint("TOPRIGHT",-5,-37)
    none.label:SetText("No creature linked")
    none:SetScript("OnClick",function() Select(0) end)
    local results={}
    for i=1,5 do
        local row=ChoiceRow(menu)
        row:SetPoint("TOPLEFT",5,-61-(i-1)*24)
        row:SetPoint("TOPRIGHT",-5,-61-(i-1)*24)
        row:SetScript("OnClick",function(self) Select(self.npcID) end)
        results[i]=row
    end
    local function RefreshResults()
        local query=search:GetText():lower():match("^%s*(.-)%s*$")
        placeholder:SetShown(query=="" and not search:HasFocus())
        local number=tonumber(query:match("^#?(%d+)$"))
        local matches={}
        if number then
            local mob=ML.GetMob(number)
            if number==panel.targetID or (mob and not mob.provisional) then matches[1]={id=number} end
        else
            if query=="" and panel.targetID then matches[1]={id=panel.targetID,target=true} end
            local found={}
            for id,mob in pairs(ML.db.mobs) do
                if not mob.provisional and (query~="" or id~=panel.targetID) then
                    local name=mob.name:lower()
                    local at=name:find(query,1,true)
                    if at then found[#found+1]={id=id,name=name,prefix=at==1} end
                end
            end
            table.sort(found,function(a,b)
                if a.prefix~=b.prefix then return a.prefix end
                if a.name~=b.name then return a.name<b.name end
                return a.id<b.id
            end)
            for _,entry in ipairs(found) do
                if #matches==#results then break end
                matches[#matches+1]=entry
            end
        end
        for i,row in ipairs(results) do
            local entry=matches[i]
            row.npcID=entry and entry.id
            if entry then
                local prefix=entry.target and "Current target · " or ""
                row.label:SetText(prefix..CreatureName(entry.id).." (#"..entry.id..")")
                row.label:SetTextColor(unpack(entry.id==panel.npcID and {0.49,0.26,0.062} or {0.26,0.15,0.065}))
            end
            row:SetShown(entry~=nil)
        end
        empty:SetShown(#matches==0)
        local height=66+math.max(1,#matches)*24
        menu:SetHeight(height)
        if menu:IsShown() then panel:SetHeight(baseHeight+height+2) end
    end
    dropdown:SetScript("OnClick",function()
        if menu:IsShown() then CloseMenu(); return end
        menu:Show()
        arrow:SetText("▲")
        search:SetText("")
        search:SetFocus()
        RefreshResults()
    end)
    search:SetScript("OnTextChanged",RefreshResults)
    search:SetScript("OnEditFocusGained",function() placeholder:Hide() end)
    search:SetScript("OnEditFocusLost",function() placeholder:SetShown(search:GetText()=="") end)
    search:SetScript("OnEscapePressed",CloseMenu)
    search:SetScript("OnEnterPressed",function() if results[1].npcID then Select(results[1].npcID) end end)
    local cancel,save
    cancel = Button("Cancel",82,function() panel:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT",-16,14)
    save = Button("Save",82,function()
        local place = panel.place
        if not place then return end
        if not ML.SaveNPCMapMark(panel.npcID,place,note:GetText()) then
            ML.Print("Could not save the map note at this position.")
            return
        end
        if panel.previous then ML.RemoveNPCMapMark(panel.previousID,panel.previous) end
        panel:Hide()
        RenderChanges()
        ML.Print("Map note saved.")
    end)
    save:SetPoint("RIGHT",cancel,"LEFT",-8,0)
    panel:SetScript("OnHide",function(self)
        note:ClearFocus()
        CloseMenu()
        self.place,self.previous,self.previousID,self.targetID=nil,nil,nil,nil
    end)
    function panel:Open(place, id)
        self.place = place
        self.previous, self.previousID = id ~= nil and place or nil, id
        self.targetID = TargetID()
        heading:SetText(id ~= nil and "Edit map note" or "New map note")
        location:SetText(string.format("%s · %.1f / %.1f",place.zone,place.x*100,place.y*100))
        Select(id or 0)
        note:SetText(place.label or "")
        self:Show()
        note:SetFocus()
    end
    panel:Hide()
    return panel
end

local function OpenEditor(map, place, id)
    editor = editor or BuildEditor(map)
    editor:Open(place,id)
end

local pinMethods = {}
function pinMethods:OnMouseEnter()
    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
    local label = self.mark.label
    GameTooltip:SetText(label ~= "" and (label:gsub("|","||")) or "Map note")
    if self.npcID > 0 then
        GameTooltip:AddLine(CreatureName(self.npcID),0.92,0.76,0.45)
        GameTooltip:AddLine("Left-click to open the bestiary.",1,1,1)
    end
    GameTooltip:AddLine("Right-click to edit · Shift + right-click to remove.",1,1,1)
    GameTooltip:Show()
end
function pinMethods:OnMouseLeave()
    GameTooltip:Hide()
end
function pinMethods:OnClick(button)
    if button == "RightButton" then
        if IsShiftKeyDown() then
            ML.RemoveNPCMapMark(self.npcID,self.mark)
            GameTooltip:Hide()
            RenderChanges()
        else
            OpenEditor(self.map,self.mark,self.npcID)
        end
    elseif button == "LeftButton" and self.npcID > 0 then
        local id = self.npcID
        self.map:Hide()
        ML.ShowMob(id)
    end
end
local function BuildMarker(map, canvas)
    local pin = CreateFrame("Button",nil,canvas)
    pin.map = map
    pin:SetSize(24,24)
    -- The map's art can render above children on the inherited canvas strata.
    pin:SetFrameStrata("FULLSCREEN_DIALOG")
    pin:SetFrameLevel(2)
    pin:SetIgnoreParentAlpha(true)
    local border=pin:CreateTexture(nil,"BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(1,0.76,0.22,1)
    local face=pin:CreateTexture(nil,"BORDER")
    face:SetPoint("TOPLEFT",2,-2)
    face:SetPoint("BOTTOMRIGHT",-2,2)
    face:SetColorTexture(0.16,0.085,0.027,1)
    local symbol=pin:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    symbol:SetPoint("CENTER",0,0)
    symbol:SetText("!")
    symbol:SetTextColor(1,0.84,0.40)
    pin:RegisterForClicks("LeftButtonUp","RightButtonUp")
    pin:SetScript("OnClick",pinMethods.OnClick)
    pin:SetScript("OnEnter",pinMethods.OnMouseEnter)
    pin:SetScript("OnLeave",pinMethods.OnMouseLeave)
    return pin
end

local function Attach()
    local map = WorldMapFrame
    if provider or not (map and map.AddCanvasClickHandler and map.AddDataProvider
        and map.GetCanvas and MapCanvasDataProviderMixin) then return end
    local canvas = map:GetCanvas()
    local pins, count = {}, 0
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    function provider:PositionNotes()
        local width,height=canvas:GetSize()
        if width<=0 or height<=0 then return end
        local scale=map:GetCanvasScale() or 1
        if scale<=0 then scale=1 end
        for i=1,count do
            local pin=pins[i]
            pin:SetScale(1/scale)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER",canvas,"TOPLEFT",pin.mark.x*width*scale,-pin.mark.y*height*scale)
        end
    end
    function provider:RemoveAllData()
        for i=1,count do
            pins[i]:Hide()
            pins[i].npcID,pins[i].mark=nil,nil
        end
        count=0
    end
    function provider:RefreshAllData()
        self:RemoveAllData()
        local mapID=map:GetMapID()
        for id,marks in pairs(ML.db and ML.db.npcMapMarks or {}) do
            for _,mark in ipairs(marks) do
                if mark.map==mapID and ML.CanPinLocation(mark) then
                    count=count+1
                    local pin=pins[count] or BuildMarker(map,canvas)
                    pins[count]=pin
                    pin.npcID,pin.mark=id,mark
                    pin:Show()
                end
            end
        end
        self:PositionNotes()
    end
    provider.OnCanvasScaleChanged=provider.PositionNotes
    canvas:HookScript("OnSizeChanged",function() provider:PositionNotes() end)
    map:AddDataProvider(provider)
    map:AddCanvasClickHandler(function(canvas, button)
        if button ~= "RightButton" or not IsShiftKeyDown() then return end
        local x,y = canvas:GetNormalizedCursorPosition()
        local mapID = ML.Public(canvas:GetMapID())
        local info = mapID and ML.Public(C_Map.GetMapInfo(mapID))
        local place = {map=mapID, x=ML.Public(x), y=ML.Public(y),
            zone=info and ML.Public(info.name) or "", sub=""}
        if not ML.CanPinLocation(place) then return end
        OpenEditor(canvas,place)
        return true,true
    end,100)
    provider:RefreshAllData()
end

ML.RefreshWorldMapNotes = RenderChanges
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent",function(self,event,name)
    if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then Attach() end
    if provider then self:UnregisterAllEvents() end
end)
