-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local maxLetters = 2000

function ML.GetNPCNote(id)
    local notes = ML.db and ML.db.npcNotes
    local note = notes and notes[id]
    return type(note) == "string" and note or nil
end

function ML.CanEditNPCNote(mob)
    local id = mob and mob.id
    return type(id) == "number" and id > 0 and id % 1 == 0 and not mob.provisional
end

function ML.NPCNotePreview(id)
    local note = ML.GetNPCNote(id)
    if not note then return end
    local line = note:match("^[^\n]*")
    local characters, truncated = {}, false
    for character in line:gmatch("[^\128-\191][\128-\191]*") do
        if #characters == 100 then truncated = true; break end
        characters[#characters + 1] = character
    end
    -- Render notes as plain text even if they contain WoW formatting codes.
    return "Note: " .. table.concat(characters):gsub("|", "||")
        .. ((truncated or #line < #note) and "…" or "")
end

local function SaveNote(id, note)
    note = note:gsub("\r\n", "\n"):gsub("\r", "\n"):match("^%s*(.-)%s*$")
    if note ~= "" then
        ML.db.npcNotes = ML.db.npcNotes or {}
        ML.db.npcNotes[id] = note
    elseif ML.db.npcNotes then
        ML.db.npcNotes[id] = nil
    end
end

local function BuildEditor(parent, ui)
    local overlay = CreateFrame("Frame", nil, parent)
    overlay:SetAllPoints(parent)
    overlay:SetFrameLevel(parent:GetFrameLevel() + 200)
    overlay:EnableMouse(true)
    local dim = overlay:CreateTexture(nil, "BACKGROUND")
    dim:SetAllPoints()
    dim:SetColorTexture(0, 0, 0, 0.65)

    local panel = ui.Panel(overlay)
    panel:SetSize(510, 335)
    panel:SetPoint("CENTER")
    panel:EnableMouse(true)
    local title = ui.Text(panel, 18, {0.92, 0.76, 0.45})
    title:SetPoint("TOPLEFT", 20, -17)
    title:SetText("Personal note")
    local creature = ui.Text(panel, 12)
    creature:SetPoint("TOPLEFT", 20, -46)
    creature:SetSize(466, 32)
    creature:SetJustifyV("TOP")

    local field = ui.Panel(panel)
    field:SetPoint("TOPLEFT", 18, -82)
    field:SetPoint("BOTTOMRIGHT", -18, 77)
    local scroll = CreateFrame("ScrollFrame", nil, field, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 9, -9)
    scroll:SetPoint("BOTTOMRIGHT", -28, 9)
    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetFontObject(ChatFontNormal)
    edit:SetTextInsets(4, 4, 4, 4)
    edit:SetWidth(437)
    edit:SetMaxLetters(maxLetters)
    scroll:SetScrollChild(edit)
    local measure = edit:CreateFontString(nil, "ARTWORK", "ChatFontNormal")
    measure:SetWidth(429)
    measure:Hide()

    local hint = ui.Text(panel, 11, {0.78, 0.70, 0.58})
    hint:SetPoint("BOTTOMLEFT", 20, 50)
    local cancel = ui.Button(panel, "Cancel", 94, function() overlay:Hide() end)
    cancel:SetPoint("BOTTOMRIGHT", -18, 15)
    local save = ui.Button(panel, "Save", 94, function()
        if not overlay.onSave then return end
        overlay.onSave(edit:GetText())
        overlay:Hide()
        ML.Refresh(true)
    end)
    save:SetPoint("RIGHT", cancel, "LEFT", -8, 0)

    local function ResizeText()
        measure:SetText(edit:GetText():gsub("|", "||") .. " ")
        edit:SetHeight(math.max(scroll:GetHeight(), measure:GetStringHeight() + 12))
        scroll:UpdateScrollChildRect()
        scroll:SetVerticalScroll(math.min(scroll:GetVerticalScroll(), scroll:GetVerticalScrollRange()))
    end
    edit:SetScript("OnTextChanged", ResizeText)
    edit:SetScript("OnCursorChanged", function(_, _, y, _, height)
        local offset, viewport = scroll:GetVerticalScroll(), scroll:GetHeight()
        local top = -y
        if top < offset then
            scroll:SetVerticalScroll(math.max(0, top))
        elseif top + height > offset + viewport then
            scroll:SetVerticalScroll(math.min(scroll:GetVerticalScrollRange(), top + height - viewport))
        end
    end)
    edit:SetScript("OnEscapePressed", function() overlay:Hide() end)
    overlay:SetScript("OnHide", function(self)
        edit:ClearFocus()
        self.onSave = nil
    end)
    function overlay:Open(heading, context, help, initialText, onSave)
        self.onSave = onSave
        title:SetText(heading)
        creature:SetText(context)
        hint:SetText(help)
        self:Show()
        edit:SetText(initialText)
        ResizeText()
        edit:SetCursorPosition(0)
        scroll:SetVerticalScroll(0)
        edit:SetFocus()
    end
    overlay:Hide()
    return overlay
end

function ML.OpenNPCNoteEditor(parent, ui, mob)
    if not ML.CanEditNPCNote(mob) then return end
    parent.noteEditor = parent.noteEditor or BuildEditor(parent, ui)
    parent.noteEditor:Open("Personal note", string.format("%s · NPC #%d", mob.name, mob.id),
        "Shared across your characters here. Clear the text and save to remove it.",
        ML.GetNPCNote(mob.id) or "", function(text) SaveNote(mob.id, text) end)
end
