-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local S, T = ML.Share, ML.FindTransfer
local frame, mode, records, selection, visible, groups, folded
local batch, packageName, skipped, confirm, previewed
local previewRows, reviewedTransfer
local importJob
local kinds = {"D","M","G"}
local names = {D="Items and loot sources", M="Creatures and locations", G="Gathering spots"}
local tabs = {{"export","Send finds"},{"transfers","Transfers"},{"manage","Imported finds"}}
local rowHeight, viewHeight = 26, 232
local Rebuild, SetMode

local function Text(parent,font,x,y)
    local label=parent:CreateFontString(nil,"OVERLAY",font)
    label:SetPoint("TOPLEFT",x,y)
    label:SetJustifyH("LEFT")
    return label
end

local function Button(parent,name,width,x,y,callback)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetPoint("TOPLEFT",x,y)
    b:SetSize(width,24)
    b:SetText(name)
    b:SetScript("OnClick",callback)
    return b
end

local function Edit(parent,width,x,y,max)
    local e=CreateFrame("EditBox",nil,parent,"InputBoxTemplate")
    e:SetSize(width,26)
    e:SetPoint("TOPLEFT",x,y)
    e:SetMaxLetters(max)
    e:SetAutoFocus(false)
    e:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    return e
end

local function Selected()
    local rows={}
    for _,r in ipairs(records) do if selection[r] then rows[#rows+1]=r end end
    return rows
end

local function Summary()
    local n = 0
    for _ in pairs(selection) do n=n+1 end
    local verb = mode=="export" and "Offer to player" or mode=="import" and "Import selected" or "Remove"
    frame.action:SetText(confirm and ("Confirm removal ("..n..")") or (verb.." ("..n..")"))
    frame.action:SetEnabled(n>0 and not importJob)
    local message
    if mode=="import" and previewed then
        message=string.format("%d new  ·  %d already known  ·  %d selected",#records,skipped,n)
    elseif mode=="export" and n>1000 then
        message=string.format("%d selected · Large transfers may take a while.",n)
    elseif mode=="manage" and confirm then message="Confirm to remove the selected imported finds."
    else message=string.format("%d finds  ·  %d selected",#records,n) end
    frame.status:SetText(message)
end

local function ChangedSelection()
    confirm=nil
end

local function UpdateLabel(entry, request)
    entry.label = S.Label(entry.r, request)
    entry.search = string.lower(entry.label) .. entry.searchSuffix
end

local function Draw()
    local first=math.floor(frame.scroll:GetVerticalScroll()/rowHeight)+1
    for i,b in ipairs(frame.rows) do
        local index=first+i-1
        local v=visible[index]
        b:SetShown(v~=nil)
        if v then
            local indent = v.header and 0 or 28
            b:SetPoint("TOPLEFT",indent,-(index-1)*rowHeight)
            b:SetWidth(frame.content:GetWidth()-indent)
            if b.value~=v and GameTooltip:IsOwned(b) then GameTooltip:Hide() end
            b.value=v
            if v.header then
                local group=groups[v.header]
                local all=true
                for _,entry in ipairs(group) do if not selection[entry.r] then all=false; break end end
                b.check:SetChecked(all)
                b.label:SetText((folded[v.header] and "+  " or "−  ")..names[v.header].." ("..#group..")")
                b.label:SetTextColor(1,0.82,0.40)
            else
                b.check:SetChecked(selection[v.r]==true)
                UpdateLabel(v, true)
                b.label:SetText(v.label)
                b.label:SetTextColor(0.91,0.88,0.82)
            end
        end
    end
end

Rebuild=function()
    local query=string.lower(frame.search:GetText() or "")
    groups={D={},M={},G={}}
    for _,v in ipairs(frame.entries) do
        if query=="" or v.search:find(query,1,true) then
            table.insert(groups[v.r.type],v)
        end
    end
    visible={}
    for _,kind in ipairs(kinds) do
        local group=groups[kind]
        if #group>0 then
            visible[#visible+1]={header=kind}
            if not folded[kind] then
                for _,v in ipairs(group) do visible[#visible+1]=v end
            end
        end
    end
    frame.content:SetHeight(math.max(1,#visible*rowHeight))
    local maxScroll=math.max(0,#visible*rowHeight-viewHeight)
    if frame.scroll:GetVerticalScroll()>maxScroll then frame.scroll:SetVerticalScroll(maxScroll) end
    Draw()
    Summary()
end

local function Load(rows,all,checkpoint)
    local entries, byItem, selected = {}, {}, {}
    for _,r in ipairs(rows) do
        if all then selected[r]=true end
        local entry={r=r,searchSuffix=string.lower(table.concat({"",r.item or "",r.npc or "",r.kind or "",
            r.resource or "",r.itemName or "",r.npcName or "",r.name or ""}," "))}
        UpdateLabel(entry, false)
        local id=r.item or r.resource
        if id then
            byItem[id]=byItem[id] or {}
            table.insert(byItem[id],entry)
        end
        entries[#entries+1]=entry
        if checkpoint then checkpoint() end
    end
    table.sort(entries,function(a,b) return a.search<b.search end)
    records,selection,folded,confirm=rows,selected,{},nil
    frame.entries,frame.byItem=entries,byItem
    frame.scroll:SetVerticalScroll(0)
    Rebuild()
end

local refreshQueued
function ML.SharingItemResolved(id)
    if not frame or not frame:IsVisible() or not frame.byItem or not frame.byItem[id] then return end
    for _,entry in ipairs(frame.byItem[id]) do UpdateLabel(entry,false) end
    if refreshQueued then return end
    refreshQueued=true
    C_Timer.After(0.1,function()
        refreshQueued=nil
        if not frame:IsVisible() then return end
        if frame.search:GetText()~="" then Rebuild() else Draw() end
    end)
end

local function BatchLabel(b)
    return b and (date("%Y-%m-%d %H:%M",b.date).." · "..b.title.." ("..#b.rows..")") or "All imports"
end

local function Manage()
    local rows={}
    for _,b in ipairs(S.Batches()) do
        if not batch or b==batch then
            for _,r in ipairs(b.rows) do rows[#rows+1]=r end
        end
    end
    frame.batch:OverrideText(BatchLabel(batch))
    frame.undo:SetShown(batch~=nil)
    Load(rows,false)
end

local function ShowPreview(rows,title,checkpoint)
    local new
    new,skipped=S.New(rows,checkpoint)
    packageName,previewed,previewRows=title,true,rows
    Load(new,true,checkpoint)
    frame.hint:SetText("Preview · "..(title~="" and title or "Shared finds"))
end

local function FinishJob()
    importJob=nil
    frame.target:SetEnabled(true)
end

local function StartJob(message, work)
    if importJob then return end
    local steps = 0
    local function Checkpoint()
        steps=steps+1
        if steps >= 200 then steps=0; coroutine.yield() end
    end
    local job=coroutine.create(function() work(Checkpoint) end)
    importJob=job
    frame.target:SetEnabled(false)
    frame.action:SetEnabled(false)
    frame.status:SetText(message)
    local function Step()
        if importJob~=job then return end
        if InCombatLockdown() then
            frame.status:SetText("Processing will resume after combat.")
            C_Timer.After(0.25,Step)
            return
        end
        frame.status:SetText(message)
        local ok, err=coroutine.resume(job)
        if ok and coroutine.status(job)~="dead" then
            C_Timer.After(0,Step)
            return
        end
        FinishJob()
        frame.action:SetEnabled(next(selection)~=nil)
        if not ok then
            frame.status:SetText("MobLog could not process these finds.")
            geterrorhandler()(err)
        end
    end
    C_Timer.After(0,Step)
end

local function Apply()
    local rows=Selected()
    if #rows==0 then return end
    if mode=="export" then
        if T.Active(T.outgoing) then SetMode("transfers"); return end
        local player=frame.target:GetText()
        if not player:find("%S") then frame.target:SetFocus(); frame.status:SetText("Enter a character name."); return end
        local title, amounts=frame.titleBox:GetText(),frame.amount:GetChecked()
        StartJob("Preparing the selected finds…",function(checkpoint)
            local code,err=S.Encode(rows,title,amounts,checkpoint)
            if not code then frame.status:SetText(err); return end
            local ok
            ok,err=T.Offer(player,code,#rows)
            if ok then SetMode("transfers") else frame.status:SetText(err) end
        end)
    elseif mode=="import" then
        StartJob("Checking and importing selected finds…",function(checkpoint)
            local n=S.Save(rows,packageName,checkpoint)
            ShowPreview(previewRows,packageName,checkpoint)
            if #records==0 and T.incoming==reviewedTransfer then T.Cancel("incoming") end
            frame.status:SetText(string.format("%d imported. Manage or undo them under Imported finds.",n))
        end)
    elseif confirm then
        local n=S.Remove(selection)
        if batch and #batch.rows==0 then batch=nil end
        Manage()
        frame.status:SetText(n.." imported finds removed.")
    else
        confirm=true
        Summary()
    end
end

function ML.RefreshFindTransfers()
    if not frame or mode~="transfers" or not frame:IsVisible() then return end
    local panel=frame.transfers
    local incoming, outgoing=T.incoming,T.outgoing
    local inText,outText="No incoming offers.","No outgoing transfer."
    if incoming then
        inText=string.format("%s · %d finds",incoming.peer,incoming.count)
        local progress=incoming.detail
        if incoming.phase=="receiving" then progress=string.format("Receiving… %d%%",math.floor(100*incoming.received/incoming.total))
        elseif incoming.phase=="ready" then
            progress="Received. Review the finds to choose what to import."
        elseif incoming.phase=="offer" and not progress then progress="Waiting for you to accept or decline." end
        inText=inText.."\n"..(progress or "")
    end
    if outgoing then
        outText=string.format("%s · %d finds",outgoing.peer,outgoing.count)
        local progress=outgoing.detail
        if outgoing.phase=="offer" then progress="Waiting for the recipient to accept."
        elseif outgoing.phase=="sending" then progress=string.format("Sending… %d%%",math.floor(100*outgoing.acked/outgoing.total)) end
        outText=outText.."\n"..(progress or "")
    end
    panel.incoming:SetText(inText)
    panel.outgoing:SetText(outText)
    panel.accept:SetShown(incoming and incoming.phase=="offer" or false)
    panel.review:SetShown(incoming and incoming.phase=="ready" or false)
    panel.cancelIncoming:SetShown(incoming~=nil)
    panel.cancelIncoming:SetText(incoming and (incoming.phase=="offer" and "Decline" or T.Active(incoming) and "Cancel" or "Dismiss") or "")
    panel.cancelOutgoing:SetShown(outgoing~=nil)
    panel.cancelOutgoing:SetText(T.Active(outgoing) and "Cancel" or "Dismiss")
end

local function ReviewTransfer()
    local received=T.incoming
    if not received or received.phase~="ready" then return end
    SetMode("import")
    reviewedTransfer=received
    StartJob("Checking the received finds…",function(checkpoint)
        local rows,title=S.Parse(received.code,checkpoint)
        if not rows then frame.status:SetText(title); return end
        if #rows~=received.count then frame.status:SetText("The received package does not match its offer."); return end
        ShowPreview(rows,title,checkpoint)
    end)
end

SetMode=function(key,context)
    FinishJob()
    mode,batch,skipped,previewed=key,nil,0,false
    previewRows,reviewedTransfer=nil,nil
    if mode=="manage" and context then
        for _,b in ipairs(S.Batches()) do
            for _,r in ipairs(b.rows) do if r==context.point then batch=b end end
        end
    end
    frame.resetting=true
    frame.search:SetText("")
    frame.titleBox:SetText("")
    frame.target:SetText("")
    frame.search:ClearFocus()
    frame.titleBox:ClearFocus()
    frame.target:ClearFocus()
    frame.resetting=nil
    for k,b in pairs(frame.tabs) do b:SetEnabled(k~=mode) end
    local recipient = ML.IsForever and "first and last name" or "character name"
    frame.hint:SetText(mode=="export" and ("Choose personal finds and enter the recipient's "..recipient..".") or mode=="import" and
        "Review the received finds and select what to import." or "Right-click a find to open it. Select finds to remove them.")
    local listing=mode~="transfers"
    frame.hint:SetShown(listing)
    frame.searchLabel:SetShown(listing)
    frame.search:SetShown(listing)
    frame.selectShown:SetShown(listing)
    frame.clearShown:SetShown(listing)
    frame.scroll:SetShown(listing)
    frame.status:SetShown(listing)
    frame.action:SetShown(listing)
    frame.transfers:SetShown(not listing)
    frame.batch:SetShown(mode=="manage")
    frame.undo:Hide()
    frame.titleBox:SetShown(mode=="export")
    frame.target:SetShown(mode=="export")
    frame.targetLabel:SetShown(mode=="export")
    frame.titleLabel:SetShown(mode=="export")
    frame.amount:SetShown(mode=="export")
    frame.amountLabel:SetShown(mode=="export")
    if mode=="export" then
        local rows
        if context and context.point then rows={S.ExportPoint(context.map,context.point)}
        else rows=S.Personal(context and context.item) end
        Load(rows,context~=nil)
    elseif mode=="import" then
        Load({},false)
    elseif mode=="manage" then
        Manage()
        if context and context.point then selection[context.point]=true; Draw(); Summary() end
    else
        Load({},false)
        ML.RefreshFindTransfers()
    end
end

local function Build()
    frame=CreateFrame("Frame","MobLogSharingWindow",UIParent,"BackdropTemplate")
    frame:SetSize(610,528)
    frame:SetPoint("CENTER")
    frame:SetClampedToScreen(true)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetToplevel(true)
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",frame.StartMoving)
    frame:SetScript("OnDragStop",frame.StopMovingOrSizing)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\DialogFrame\\UI-DialogBox-Border",edgeSize=24,insets={left=5,right=5,top=5,bottom=5}})
    frame:SetBackdropColor(0.09,0.07,0.05,1)
    Text(frame,"GameFontNormalLarge",22,-18):SetText("Share finds")
    local close=CreateFrame("Button",nil,frame,"UIPanelCloseButton")
    close:SetPoint("TOPRIGHT",-3,-3)
    table.insert(UISpecialFrames,"MobLogSharingWindow")
    frame.tabs={}
    for i,tab in ipairs(tabs) do
        local key=tab[1]
        frame.tabs[key]=Button(frame,tab[2],157,19+(i-1)*166,-46,function() SetMode(key) end)
    end
    frame.hint=Text(frame,"GameFontHighlight",23,-84)
    frame.targetLabel=Text(frame,"GameFontNormalSmall",23,-115)
    frame.targetLabel:SetText(ML.IsForever and "Full name" or "Player")
    frame.target=Edit(frame,205,119,-106,96)
    frame.titleLabel=Text(frame,"GameFontNormalSmall",23,-145)
    frame.titleLabel:SetText("Package name")
    frame.titleBox=Edit(frame,182,119,-137,96)
    frame.amount=CreateFrame("CheckButton",nil,frame,"UICheckButtonTemplate")
    frame.amount:SetSize(24,24); frame.amount:SetPoint("TOPLEFT",318,-137)
    frame.amountLabel=Text(frame,"GameFontHighlightSmall",345,-145)
    frame.amountLabel:SetText("Include gathered quantities")
    frame.batch=ML.CreateDropdown(frame,559,function()
        local choices={{key=0,label="All imports"}}
        for i,b in ipairs(S.Batches()) do choices[#choices+1]={key=i,label=BatchLabel(b)} end
        return choices
    end,function()
        for i,b in ipairs(S.Batches()) do if b==batch then return i end end
        return 0
    end,function(i) batch=S.Batches()[i]; Manage() end)
    frame.batch:SetPoint("TOPLEFT",19,-106)
    frame.undo=Button(frame,"Undo this import",153,20,-139,function()
        selection={}
        for _,r in ipairs(batch.rows) do selection[r]=true end
        confirm=true
        Draw(); Summary()
    end)
    frame.searchLabel=Text(frame,"GameFontNormalSmall",23,-181)
    frame.searchLabel:SetText("Find or zone")
    frame.search=Edit(frame,224,105,-171,100)
    frame.search:SetScript("OnTextChanged",function() if not frame.resetting and mode then confirm=nil; Rebuild() end end)
    local function SelectShown(value)
        ChangedSelection()
        for _,group in pairs(groups) do
            for _,v in ipairs(group) do selection[v.r]=value end
        end
        Draw(); Summary()
    end
    frame.selectShown=Button(frame,"Select shown",114,345,-173,function() SelectShown(true) end)
    frame.clearShown=Button(frame,"Clear shown",114,463,-173,function() SelectShown(nil) end)
    frame.scroll=CreateFrame("ScrollFrame",nil,frame,"UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT",22,-209); frame.scroll:SetSize(538,viewHeight)
    frame.content=CreateFrame("Frame",nil,frame.scroll); frame.content:SetSize(536,1)
    frame.scroll:SetScrollChild(frame.content)
    frame.rows={}
    visible={}
    for i=1,math.ceil(viewHeight/rowHeight)+1 do
        local b=CreateFrame("Button",nil,frame.content)
        b:SetSize(536,rowHeight)
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
        b.check=CreateFrame("CheckButton",nil,b,"UICheckButtonTemplate")
        b.check:SetPoint("LEFT"); b.check:SetSize(24,24)
        b.label=Text(b,"GameFontHighlightSmall",29,-7)
        b.label:SetPoint("TOPRIGHT",-7,-7); b.label:SetHeight(16); b.label:SetWordWrap(false)
        b:SetScript("OnEnter",function(self)
            local entry=self.value
            if not entry or not entry.r then return end
            local found=entry.r
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetText(entry.label)
            if found.npc then GameTooltip:AddLine("NPC ID: "..found.npc,1,1,1) end
            if found.item then GameTooltip:AddLine("Item ID: "..found.item,1,1,1) end
            if found.kind then
                for id, quantity in pairs(found.loot or {}) do
                    local itemName=ML.LocalItemName(id) or ("Item #"..id)
                    GameTooltip:AddDoubleLine(itemName,"×"..quantity,1,1,1,1,1,1)
                end
            end
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave",function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        b:SetScript("OnHide",function(self)
            if GameTooltip:IsOwned(self) then GameTooltip:Hide() end
        end)
        local function Toggle()
            local v=b.value
            ChangedSelection()
            if v.header then
                local all=true
                for _,e in ipairs(groups[v.header]) do if not selection[e.r] then all=false; break end end
                for _,e in ipairs(groups[v.header]) do selection[e.r]=not all or nil end
            else selection[v.r]=not selection[v.r] or nil end
            Draw(); Summary()
        end
        b.check:SetScript("OnClick",Toggle)
        b:RegisterForClicks("LeftButtonUp","RightButtonUp")
        b:SetScript("OnClick",function(_,button)
            local v=b.value
            if button=="RightButton" then
                if mode~="manage" or not v.r then return end
                local r=v.r
                if r.map then
                    if ML.OpenLocation(r) then frame:Hide() end
                elseif r.item then
                    frame:Hide()
                    if not ML.IsMobLogVisible() then ML.Toggle() end
                    ML.OpenItem(r.item)
                elseif ML.GetMob(r.npc) then
                    frame:Hide(); ML.ShowMob(r.npc)
                else ML.Print("No bestiary entry is available for NPC #"..r.npc..".") end
            elseif v.header then folded[v.header]=not folded[v.header]; Rebuild() else Toggle() end
        end)
        frame.rows[i]=b
    end
    frame.scroll:HookScript("OnVerticalScroll",Draw)
    frame.status=Text(frame,"GameFontHighlightSmall",23,-457)
    frame.action=Button(frame,"",170,410,-485,Apply)
    local panel=CreateFrame("Frame",nil,frame)
    panel:SetPoint("TOPLEFT",22,-103)
    panel:SetSize(566,372)
    frame.transfers=panel
    Text(panel,"GameFontNormal",0,0):SetText("Incoming")
    panel.incoming=Text(panel,"GameFontHighlight",0,-24)
    panel.accept=Button(panel,"Accept",110,0,-65,T.Accept)
    panel.review=Button(panel,"Review finds",110,0,-65,ReviewTransfer)
    panel.cancelIncoming=Button(panel,"",105,120,-65,function() T.Cancel("incoming") end)
    Text(panel,"GameFontNormal",0,-122):SetText("Outgoing")
    panel.outgoing=Text(panel,"GameFontHighlight",0,-146)
    panel.cancelOutgoing=Button(panel,"",105,0,-187,function() T.Cancel("outgoing") end)
    Text(panel,"GameFontHighlightSmall",0,-239):SetText("Transfers with more than 1,000 finds may take a while.")
    frame:SetScript("OnHide",function()
        FinishJob()
        frame.search:ClearFocus()
        frame.titleBox:ClearFocus()
        frame.target:ClearFocus()
    end)
end

function ML.OpenSharing(tab,context)
    if not ML.db then return end
    if not frame then Build() end
    frame:Show()
    frame:Raise()
    local incoming=T.incoming
    if not tab and incoming and (T.Active(incoming) or incoming.phase=="ready") then tab="transfers" end
    SetMode(tab or "export",context)
end
