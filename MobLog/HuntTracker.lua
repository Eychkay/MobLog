-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local tracker, scrollIndex, dirty, scheduled = nil, 1, false, false
local rows, targets = {}, {}
local perPage = 6

local function Text(parent, size)
    local label = parent:CreateFontString(nil, "OVERLAY")
    label:SetFont(STANDARD_TEXT_FONT, size, "")
    label:SetTextColor(0.92, 0.87, 0.76)
    label:SetShadowColor(0, 0, 0, 1); label:SetShadowOffset(1, -1)
    label:SetJustifyH("LEFT")
    return label
end

local function Enabled()
    return ML.db and ML.db.options.huntTracker ~= false
end

local function Render()
    if not tracker then return end
    if not Enabled() or #targets == 0 then tracker:Hide(); return end
    scrollIndex = math.max(1, math.min(scrollIndex, math.max(1, math.ceil(#targets / perPage))))
    local start = (scrollIndex - 1) * perPage + 1
    local visible = math.min(perPage, #targets - start + 1)
    local collapsed = ML.db.options.huntTrackerCollapsed == true
    tracker:SetHeight(collapsed and 34 or (62 + visible * 48))
    tracker.collapse:SetText(collapsed and "+" or "-")
    tracker.previous:SetShown(not collapsed and #targets > perPage)
    tracker.next:SetShown(not collapsed and #targets > perPage)
    tracker.footer:SetShown(not collapsed)
    tracker.footer:SetText(string.format("%d–%d of %d", start, start + visible - 1, #targets))
    tracker.previous:SetEnabled(scrollIndex > 1)
    tracker.next:SetEnabled(start + visible <= #targets)
    for i, row in ipairs(rows) do
        local mob = targets[start + i - 1]
        row:SetShown(not collapsed and i <= visible)
        if mob and i <= visible then
            row.mob = mob
            row.name:SetText(mob.name)
            local _, fraction, rank, nextRank = ML.CollectionProgress(mob)
            local tier = nextRank or rank or ML.KillRanks[1]
            row.progress:SetWidth(math.max(1, 230 * fraction)); row.progress:SetShown(fraction > 0)
            row.progress:SetVertexColor(unpack(tier.color))
            row.detail:SetText(nextRank and string.format("%d / %d kills · %s", mob.count, nextRank.kills, nextRank.label) or
                (mob.count .. " kills · Master"))
        end
    end
    tracker:Show()
end

local function Build()
    tracker = CreateFrame("Frame", "MobLogHuntTracker", UIParent, "BackdropTemplate")
    tracker:SetSize(260, 80); tracker:SetFrameStrata("MEDIUM"); tracker:SetClampedToScreen(true)
    tracker:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12,
        insets = {left = 3, right = 3, top = 3, bottom = 3}})
    tracker:SetBackdropColor(0.12, 0.10, 0.07, 0.95); tracker:SetBackdropBorderColor(0.64, 0.52, 0.34, 1)
    local position = ML.db.options.huntTrackerPosition
    if type(position) == "table" and type(position.x) == "number" and type(position.y) == "number" then
        tracker:SetPoint("CENTER", UIParent, "BOTTOMLEFT", position.x * UIParent:GetWidth(), position.y * UIParent:GetHeight())
    else tracker:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -50, -260) end
    tracker:SetMovable(true)
    local header = CreateFrame("Frame", nil, tracker)
    header:SetPoint("TOPLEFT", 8, -5); header:SetSize(192, 26); header:EnableMouse(true); header:RegisterForDrag("LeftButton")
    local title = Text(header, 12); title:SetPoint("LEFT", 3, 0); title:SetText("|cffeac273HUNT TARGETS|r")
    header:SetScript("OnDragStart", function()
        if not ML.db.options.huntTrackerLocked then tracker:StartMoving() end
    end)
    header:SetScript("OnDragStop", function()
        tracker:StopMovingOrSizing()
        local x, y = tracker:GetCenter()
        if x and y then ML.db.options.huntTrackerPosition = {x = x / UIParent:GetWidth(), y = y / UIParent:GetHeight()} end
    end)
    local function Button(label, x, callback)
        local button = CreateFrame("Button", nil, tracker, "UIPanelButtonTemplate")
        button:SetSize(22, 22); button:SetPoint("TOPRIGHT", x, -6); button:SetText(label); button:SetScript("OnClick", callback)
        return button
    end
    tracker.collapse = Button("-", -32, function()
        ML.db.options.huntTrackerCollapsed = not ML.db.options.huntTrackerCollapsed; Render()
    end)
    Button("x", -7, function() ML.db.options.huntTracker = false; tracker:Hide() end)
    for i = 1, perPage do
        local row = CreateFrame("Button", nil, tracker)
        row:SetSize(240, 45); row:SetPoint("TOPLEFT", 10, -34 - (i - 1) * 48)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.name = Text(row, 12); row.name:SetPoint("TOPLEFT", 4, -2); row.name:SetSize(230, 16); row.name:SetWordWrap(false)
        row.detail = Text(row, 10); row.detail:SetPoint("TOPLEFT", 4, -20); row.detail:SetSize(230, 13); row.detail:SetWordWrap(false)
        local background = row:CreateTexture(nil, "BACKGROUND"); background:SetColorTexture(0.035, 0.03, 0.02, 1)
        background:SetPoint("BOTTOMLEFT", 4, 3); background:SetSize(230, 3)
        row.progress = row:CreateTexture(nil, "ARTWORK"); row.progress:SetTexture("Interface\\Buttons\\WHITE8X8")
        row.progress:SetPoint("BOTTOMLEFT", 4, 3); row.progress:SetHeight(3)
        row:SetScript("OnClick", function(self, button)
            if button == "RightButton" then GameTooltip:Hide(); ML.ToggleHuntTarget(self.mob)
            else ML.ShowMob(self.mob.representativeID or self.mob.id) end
        end)
        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:AddLine(self.mob.name, 0.92, 0.76, 0.45)
            GameTooltip:AddLine(ML.CollectionProgress(self.mob), 0.85, 0.82, 0.74, true)
            GameTooltip:AddLine("Left-click: open bestiary · Right-click: unpin", 0.85, 0.82, 0.74, true)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        rows[i] = row
    end
    tracker.footer = Text(tracker, 10); tracker.footer:SetPoint("BOTTOMLEFT", 14, 10)
    tracker.previous = Button("<", -34, function() scrollIndex = scrollIndex - 1; Render() end)
    tracker.previous:ClearAllPoints(); tracker.previous:SetPoint("BOTTOMRIGHT", -34, 6)
    tracker.next = Button(">", -8, function() scrollIndex = scrollIndex + 1; Render() end)
    tracker.next:ClearAllPoints(); tracker.next:SetPoint("BOTTOMRIGHT", -8, 6)
    tracker:Hide()
end

function ML.UpdateHuntTracker(groups)
    dirty = false
    if not Enabled() or not next(ML.db.huntTargets or {}) then
        targets = {}; if tracker then tracker:Hide() end; return
    end
    targets = {}
    for _, mob in ipairs(groups or ML.BuildMobGroups(ML.db.huntTargets)) do
        if ML.IsHuntTarget(mob) then targets[#targets + 1] = mob end
    end
    table.sort(targets, function(a, b)
        local an, bn = string.lower(a.name), string.lower(b.name)
        if an == bn then return a.id < b.id end
        return an < bn
    end)
    if not tracker and #targets > 0 then Build() end
    Render()
end

function ML.QueueHuntTrackerRefresh()
    if not Enabled() or not next(ML.db.huntTargets or {}) then ML.UpdateHuntTracker(); return end
    dirty = true
    if scheduled then return end
    scheduled = true
    C_Timer.After(0.15, function()
        scheduled = false
        if dirty then ML.UpdateHuntTracker() end
    end)
end

function ML.ToggleHuntTracker()
    ML.db.options.huntTracker = not Enabled()
    ML.UpdateHuntTracker()
    if Enabled() and #targets == 0 then ML.Print("Pin a mob with + in the bestiary to show the hunt tracker.") end
end
