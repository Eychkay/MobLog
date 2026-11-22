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
    local width = 420
    panel:SetSize(width, 263)
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

    local search=EditBox(panel,60)
    search:SetPoint("TOPLEFT",24,-150)
    search:SetPoint("TOPRIGHT",-24,-150)
    local placeholder=Ink(search,"GameFontNormalSmall")
    placeholder:SetPoint("LEFT",3,0)
    placeholder:SetTextColor(0.78,0.70,0.56)
    placeholder:SetText("Search by name or NPC ID")
    local dropdown
    local function Select(id)
        panel.npcID=id
        dropdown:OverrideText(id>0 and (CreatureName(id).." (#"..id..")") or "No creature linked")
        search:ClearFocus()
    end
    local function FindMatches()
        local query=search:GetText():lower():match("^%s*(.-)%s*$")
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
                if #matches==5 then break end
                matches[#matches+1]=entry
            end
        end
        return matches
    end
    local function CreatureChoices()
        local choices={{key=0,label="No creature linked"}}
        for _,entry in ipairs(FindMatches()) do
            local prefix=entry.target and "Current target · " or ""
            choices[#choices+1]={key=entry.id,label=prefix..CreatureName(entry.id).." (#"..entry.id..")"}
        end
        return choices
    end
    dropdown=ML.CreateDropdown(panel,width-38,CreatureChoices,function() return panel.npcID or 0 end,Select)
    dropdown:SetPoint("TOPLEFT",19,-183)
    search:SetScript("OnTextChanged",function(self) placeholder:SetShown(self:GetText()=="" and not self:HasFocus()) end)
    search:SetScript("OnEditFocusGained",function() placeholder:Hide() end)
    search:SetScript("OnEditFocusLost",function() placeholder:SetShown(search:GetText()=="") end)
    search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    search:SetScript("OnEnterPressed",function()
        local first=FindMatches()[1]
        if first then Select(first.id) end
    end)
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
        search:ClearFocus()
        dropdown:CloseMenu()
        self.place,self.previous,self.previousID,self.targetID=nil,nil,nil,nil
    end)
    function panel:Open(place, id)
        self.place = place
        self.previous, self.previousID = id ~= nil and place or nil, id
        self.targetID = TargetID()
        heading:SetText(id ~= nil and "Edit map note" or "New map note")
        location:SetText(string.format("%s · %.1f / %.1f",place.zone,place.x*100,place.y*100))
        search:SetText("")
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

local function HideGatherTooltip(pin)
    if GameTooltip:IsOwned(pin) then GameTooltip:Hide() end
end

local gatherProfessionIcons = {
    ore = "Interface\\Icons\\Trade_Mining",
    herb = "Interface\\Icons\\Trade_Herbalism",
    fish = ML.GatherIcons.fish,
}

local function BuildGatherMarker(canvas)
    local pin = CreateFrame("Frame", nil, canvas)
    pin:SetSize(13, 13)
    pin:SetFrameStrata("FULLSCREEN_DIALOG")
    pin:SetFrameLevel(1)
    pin:SetIgnoreParentAlpha(true)
    local border = pin:CreateTexture(nil, "BACKGROUND")
    border:SetAllPoints()
    border:SetColorTexture(0.15, 0.10, 0.06, 1)
    pin.icon = pin:CreateTexture(nil, "ARTWORK")
    pin.icon:SetPoint("TOPLEFT", 1, -1)
    pin.icon:SetPoint("BOTTOMRIGHT", -1, 1)
    pin.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    if pin.SetMouseClickEnabled then
        pin:SetScript("OnEnter", function(self)
            local point = self.mark
            if not point then return end
            ML.ShowGatherLocationTooltip(GameTooltip, self, point, "ANCHOR_RIGHT", self.mapID)
        end)
        pin:SetScript("OnLeave", HideGatherTooltip)
        pin:SetMouseClickEnabled(false)
    end
    pin:SetScript("OnHide", HideGatherTooltip)
    return pin
end

local function Attach()
    local map = WorldMapFrame
    if provider or not (map and map.AddCanvasClickHandler and map.AddDataProvider
        and map.GetCanvas and MapCanvasDataProviderMixin) then return end
    local canvas = map:GetCanvas()
    local pins, count = {}, 0
    local gatheringPins, gatheringCount = {}, 0
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    local function PositionPin(pin, width, height, scale)
        pin:SetScale(1 / scale)
        pin:ClearAllPoints()
        pin:SetPoint("CENTER", canvas, "TOPLEFT", pin.mark.x * width * scale, -pin.mark.y * height * scale)
    end
    function provider:PositionNotes()
        local width,height=canvas:GetSize()
        if width<=0 or height<=0 then return end
        local scale=map:GetCanvasScale() or 1
        if scale<=0 then scale=1 end
        for i=1,count do PositionPin(pins[i],width,height,scale) end
        for i=1,gatheringCount do PositionPin(gatheringPins[i],width,height,scale) end
    end
    function provider:SetGatherPins(mapID)
        local previous = gatheringCount
        gatheringCount = 0
        if ML.db and ML.db.options.gatherPins ~= false then
            for _, mark in ipairs(ML.GatherLocations(mapID)) do
                gatheringCount = gatheringCount + 1
                local pin = gatheringPins[gatheringCount] or BuildGatherMarker(canvas)
                gatheringPins[gatheringCount] = pin
                if pin.mark ~= mark then HideGatherTooltip(pin) end
                pin.mark, pin.mapID = mark, mapID
                pin.icon:SetTexture(ML.GetGatherLocationIcon(mapID, mark) or gatherProfessionIcons[mark.kind])
                pin:Show()
            end
        end
        for i = gatheringCount + 1, previous do
            gatheringPins[i]:Hide()
            gatheringPins[i].mark = nil
        end
    end
    function provider:RemoveAllData()
        for i=1,count do
            pins[i]:Hide()
            pins[i].npcID,pins[i].mark=nil,nil
        end
        count=0
        self:SetGatherPins(nil)
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
        self:SetGatherPins(mapID)
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
function ML.RefreshGatherPins(mapID)
    local map = WorldMapFrame
    if not provider or not map:IsVisible() then return end
    local current = map:GetMapID()
    if mapID and mapID ~= current then return end
    provider:SetGatherPins(current)
    provider:PositionNotes()
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ADDON_LOADED")
events:SetScript("OnEvent",function(self,event,name)
    if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then Attach() end
    if provider then self:UnregisterAllEvents() end
end)
