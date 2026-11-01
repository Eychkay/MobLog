-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local button

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
end)
