-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local button
local gatherLayer
local gatherTooltip, tooltipPoint, tooltipStamp, tooltipRevision
local gatherPins, mapSizes = {}, {}
local displayed = 0
local lastMap, lastX, lastY, lastAngle, lastRadius, lastWidth, lastHeight, lastSquare
local trackingSpells = { [2383] = "herb", [2580] = "ore" }
local tracking = {}
local ringTexture = "Interface\\AddOns\\MobLog\\Media\\GatherRing"
local ringColors = { herb = {0.48, 0.94, 0.41}, ore = {0.60, 0.77, 1} }
local ringRangeSquared = 100 * 100

local function ReadGatherTracking()
    wipe(tracking)
    if not C_Minimap.GetNumTrackingTypes or not C_Minimap.GetTrackingInfo then return end
    local names = {}
    if C_Spell and C_Spell.GetSpellName then
        for id, kind in pairs(trackingSpells) do
            local name = ML.Public(C_Spell.GetSpellName(id))
            if type(name) == "string" and name ~= "" then names[name] = kind end
        end
    end
    local count = ML.Public(C_Minimap.GetNumTrackingTypes())
    if type(count) ~= "number" then return end
    for index = 1, count do
        local info = ML.Public(C_Minimap.GetTrackingInfo(index))
        if type(info) == "table" and ML.Public(info.active) == true then
            local kind = trackingSpells[ML.Public(info.spellID)] or names[ML.Public(info.name)]
            if kind then tracking[kind] = true end
        end
    end
end

local function ClearGatherPins()
    for i = 1, displayed do gatherPins[i]:Hide() end
    displayed, lastMap = 0, nil
    if gatherTooltip then gatherTooltip:Hide() end
    tooltipPoint, tooltipStamp = nil, nil
end

local function UpdateGatherTooltip()
    local hovered
    if displayed > 0 and ML.Public(Minimap:IsMouseOver()) and
        (not Minimap.IsMouseMotionFocus or ML.Public(Minimap:IsMouseMotionFocus())) then
        for i = displayed, 1, -1 do
            local pin = gatherPins[i]
            if ML.Public(pin:IsMouseOver()) then
                hovered = pin.mark
                break
            end
        end
    end
    if not hovered then
        if gatherTooltip then gatherTooltip:Hide() end
        tooltipPoint, tooltipStamp = nil, nil
        return
    end
    -- The minimap updates the native tooltip independently for active nodes.
    if not gatherTooltip then
        gatherTooltip = CreateFrame("GameTooltip", "MobLogGatherMinimapTooltip", UIParent, "GameTooltipTemplate")
        gatherTooltip:SetClampedToScreen(true)
        gatherTooltip:EnableMouse(false)
    end
    if hovered ~= tooltipPoint or hovered.last ~= tooltipStamp or tooltipRevision ~= ML.itemSourceRevision or not gatherTooltip:IsShown() then
        tooltipPoint, tooltipStamp, tooltipRevision = hovered, hovered.last, ML.itemSourceRevision
        ML.ShowGatherLocationTooltip(gatherTooltip, gatherLayer, hovered, "ANCHOR_LEFT", lastMap)
    end
end

local function MapSize(mapID)
    local size = mapSizes[mapID]
    if size then return size end
    local width, height = C_Map.GetMapWorldSize(mapID)
    width, height = ML.Public(width), ML.Public(height)
    if type(width) ~= "number" or type(height) ~= "number" or width <= 0 or height <= 0 then return end
    size = { width = width, height = height }
    mapSizes[mapID] = size
    return size
end

local function DrawGatherPins()
    local mapID = ML.Public(C_Map.GetBestMapForUnit("player"))
    local points = ML.GatherLocations(mapID)
    if #points == 0 then ClearGatherPins(); return end
    local size = MapSize(mapID)
    local position = ML.Public(C_Map.GetPlayerMapPosition(mapID, "player"))
    local radius = ML.Public(C_Minimap.GetViewRadius())
    if not size or not position or type(radius) ~= "number" or radius <= 0 then ClearGatherPins(); return end
    local x, y = position:GetXY()
    x, y = ML.Public(x), ML.Public(y)
    if type(x) ~= "number" or type(y) ~= "number" or (x == 0 and y == 0) then ClearGatherPins(); return end

    local getCVarBool = C_CVar and C_CVar.GetCVarBool or GetCVarBool
    local rotating = getCVarBool and ML.Public(getCVarBool("rotateMinimap"))
    local ignoresRotation = C_Minimap.IsRotateMinimapIgnored and ML.Public(C_Minimap.IsRotateMinimapIgnored())
    local angle = 0
    if rotating and not ignoresRotation then
        angle = GetPlayerFacing and ML.Public(GetPlayerFacing())
        if type(angle) ~= "number" then ClearGatherPins(); return end
    end
    local halfWidth, halfHeight = Minimap:GetWidth() / 2, Minimap:GetHeight() / 2
    local square = GetMinimapShape and GetMinimapShape() == "SQUARE"
    if mapID == lastMap and x == lastX and y == lastY and angle == lastAngle and radius == lastRadius
        and halfWidth == lastWidth and halfHeight == lastHeight and square == lastSquare then return end
    lastMap, lastX, lastY, lastAngle, lastRadius = mapID, x, y, angle, radius
    lastWidth, lastHeight, lastSquare = halfWidth, halfHeight, square

    local cos, sin = math.cos(angle), math.sin(angle)
    local previous = displayed
    displayed = 0
    for _, point in ipairs(points) do
        -- Zone map y increases southward. Minimap anchors increase northward.
        local east = (point.x - x) * size.width
        local north = (y - point.y) * size.height
        local dx = (east * cos + north * sin) / radius
        local dy = (north * cos - east * sin) / radius
        local inside
        if square then inside = math.abs(dx) <= 0.92 and math.abs(dy) <= 0.92
        else inside = dx * dx + dy * dy <= 0.92 * 0.92 end
        if inside then
            displayed = displayed + 1
            local pin = gatherPins[displayed]
            if not pin then
                pin = gatherLayer:CreateTexture(nil, "OVERLAY")
                gatherPins[displayed] = pin
            end
            pin.mark = point
            local ring = tracking[point.kind] and east * east + north * north <= ringRangeSquared
            if ring then
                pin:SetTexture(ringTexture)
                pin:SetVertexColor(unpack(ringColors[point.kind]))
                pin:SetSize(14, 14)
            else
                pin:SetTexture(ML.GatherIcons[point.kind])
                pin:SetVertexColor(1, 1, 1)
                pin:SetSize(10, 10)
            end
            pin:SetPoint("CENTER", gatherLayer, "CENTER", dx * halfWidth, dy * halfHeight)
            pin:Show()
        end
    end
    for i = displayed + 1, previous do gatherPins[i]:Hide() end
end

function ML.RefreshMinimapGatherPins()
    if not gatherLayer then return end
    lastMap = nil
    local enabled = ML.db.options.minimapGatherPins ~= false and ML.db.gatherLocations and next(ML.db.gatherLocations) ~= nil
    gatherLayer:SetShown(enabled == true)
    if enabled and gatherLayer:IsVisible() then DrawGatherPins() end
end

local function BuildGatherLayer()
    if not (C_Minimap and C_Minimap.GetViewRadius and C_Map and C_Map.GetBestMapForUnit
        and C_Map.GetPlayerMapPosition and C_Map.GetMapWorldSize) then return end
    gatherLayer = CreateFrame("Frame", nil, Minimap)
    gatherLayer:SetAllPoints()
    gatherLayer:SetFrameLevel(Minimap:GetFrameLevel() + 1)
    local elapsed = 0
    gatherLayer:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + dt
        if elapsed >= 0.12 then
            elapsed = 0
            DrawGatherPins()
            UpdateGatherTooltip()
        end
    end)
    gatherLayer:SetScript("OnHide", ClearGatherPins)
    gatherLayer:RegisterEvent("MINIMAP_UPDATE_TRACKING")
    gatherLayer:SetScript("OnEvent", function()
        ReadGatherTracking()
        ML.RefreshMinimapGatherPins()
    end)
    ReadGatherTracking()
    ML.RefreshMinimapGatherPins()
end

local function Position()
    local angle = math.rad(ML.db.minimap.angle)
    local x, y = math.cos(angle), math.sin(angle)
    -- Circular minimaps by default; keep the button outside square minimaps too.
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    if shape == "SQUARE" then
        local edge = math.max(math.abs(x), math.abs(y))
        x, y = x / edge, y / edge
    end
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", x * (Minimap:GetWidth() / 2 + 8), y * (Minimap:GetHeight() / 2 + 8))
end

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:SetScript("OnEvent", function()
    ML.db.minimap = ML.db.minimap or { angle = 220 }
    button = CreateFrame("Button", "MobLogMinimapButton", Minimap)
    button:SetSize(32, 32); button:SetFrameStrata("MEDIUM"); button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
    button:RegisterForClicks("LeftButtonUp"); button:RegisterForDrag("LeftButton")
    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetTexture("Interface\\AddOns\\MobLog\\Media\\Minimap")
    icon:SetSize(24, 24); icon:SetPoint("CENTER", 0, 1)
    local mask = button:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(54, 54); border:SetPoint("TOPLEFT")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    button:SetScript("OnMouseDown", function(self) self.wasDragged = nil end)
    button:SetScript("OnClick", function(self)
        if not self.wasDragged then ML.Toggle() end
        self.wasDragged = nil
    end)
    button:SetScript("OnDragStart", function(self)
        self.wasDragged = true; GameTooltip:Hide()
        self:SetScript("OnUpdate", function()
            local x, y = GetCursorPosition()
            local cx, cy = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            ML.db.minimap.angle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
            Position()
        end)
    end)
    button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("MobLog", 0.92, 0.76, 0.45)
        GameTooltip:AddLine("Click: open bestiary", 0.85, 0.90, 0.92)
        GameTooltip:AddLine("Drag: move minimap button", 0.55, 0.68, 0.70)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    Minimap:HookScript("OnSizeChanged", Position)
    Position()
    BuildGatherLayer()
end)
