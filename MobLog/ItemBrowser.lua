-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local page, search, heading, explanation, empty, areaButton, rarityButton, rarityMenu
local Text, Panel, Button, left, right, selected
local rarity, area = "all", "all"
local closed = {observed=true,unlooted=true,sources=true,possible=true}
local prepareButton,searchStatus
local searchSequence=0
local itemBuckets
local function RarityLabel(entry)
    local color=type(entry.key)=="number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[entry.key]
    local hex=color and string.format("ff%02x%02x%02x",math.floor(color.r*255+0.5),math.floor(color.g*255+0.5),math.floor(color.b*255+0.5)) or entry.color
    return hex and ("|c"..hex..entry.label.."|r") or entry.label
end
function ML.SetItemRarityFilter(key)
    for _, entry in ipairs(ML.ItemRarityFilters) do
        if entry.key==key then
            rarity=key
            if ML.ItemSearchStatus() then ML.PauseItemSearchPreparation()
            else ML.PublishItemSearchIndex() end
            if rarityButton then rarityButton:SetText(RarityLabel(entry).."  v") end
            if rarityMenu then rarityMenu:Hide() end
            if left then left.scroll:SetVerticalScroll(0) end
            if page then ML.RefreshItems() end
            return
        end
    end
end
-- Compact group headers have their own pool, matching the Mob list. Items
-- retain normal row heights; offsets drive virtualization for mixed heights.
local function PreviewItem(item)
    if not IsModifiedClick("DRESSUP") then return false end
    GameTooltip:Hide()
    HandleModifiedItemClick(item.link or ("item:"..item.id))
    local preview=DressUpFrame
    if preview and preview:IsShown() then
        -- MobLog is a dialog; keep the native preview visible above it and
        -- restore its normal strata when closed.
        local ranks={BACKGROUND=1,LOW=2,MEDIUM=3,HIGH=4,DIALOG=5,FULLSCREEN=6,FULLSCREEN_DIALOG=7,TOOLTIP=8}
        local wanted=page:GetFrameStrata()
        if (ranks[preview:GetFrameStrata()] or 0)<(ranks[wanted] or 0) then
            if not preview.mobLogOriginalStrata then
                preview.mobLogOriginalStrata=preview:GetFrameStrata()
                if not preview.mobLogRestoreHook then
                    preview.mobLogRestoreHook=true
                    preview:HookScript("OnHide",function(self)
                        if self.mobLogOriginalStrata then
                            local original=self.mobLogOriginalStrata
                            self.mobLogOriginalStrata=nil
                            self:SetFrameStrata(original)
                        end
                    end)
                end
            end
            preview:SetFrameStrata(wanted)
        end
        preview:Raise()
    end
    return true
end
ML.PreviewItem=PreviewItem

local function Draw(state)
    if not page:IsVisible() then return end
    local y=state.scroll:GetVerticalScroll() or 0
    -- Binary search avoids walking thousands of rows when scrolling near the end.
    local low,high=1,#state.entries
    while low<=high do
        local middle=math.floor((low+high)/2)
        local entry=state.entries[middle]
        if entry.offset+entry.height<=y then low=middle+1 else high=middle-1 end
    end
    local first=math.max(1,low-1)
    local used,usedHeaders=0,0
    for i=first,#state.entries do
        local entry=state.entries[i]
        if entry.offset>y+state.scroll:GetHeight()+state.stride then break end
        if entry.header then
            usedHeaders=usedHeaders+1
            local header=state.headers[usedHeaders]
            if not header then
                header=CreateFrame("Button",nil,state.content,"BackdropTemplate")
                header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
                header:SetBackdropColor(0.11,0.09,0.06,1)
                header.label=Text(header,12,{0.92,0.76,0.45})
                header.label:SetPoint("LEFT",8,0); header.label:SetHeight(18); header.label:SetWordWrap(false)
                header:SetScript("OnClick",function(self)
                    if self.entry.key=="catalogUnavailable" then ML.Print(ML.CatalogUnavailableText()); return end
                    if self.entry.key=="empty" then return end
                    closed[self.entry.key]=not closed[self.entry.key]
                    ML.RefreshItems()
                end)
                header:SetScript("OnEnter",function(self)
                    if self.entry.key=="catalogUnavailable" then
                        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:AddLine(ML.CatalogUnavailableText(),1,0.82,0,true); GameTooltip:Show()
                    end
                end)
                header:SetScript("OnLeave",function() GameTooltip:Hide() end)
                state.headers[usedHeaders]=header
            end
            header.entry=entry
            header:SetPoint("TOPLEFT",0,-entry.offset); header:SetSize(state.width,28)
            header.label:SetWidth(state.width-16)
            if entry.key=="empty" or entry.key=="catalogUnavailable" then header.label:SetText(entry.label)
            else header.label:SetText((closed[entry.key] and "+ " or "- ")..entry.label.." ("..entry.count..")") end
            header:Show()
        else
            used=used+1
            local row=state.rows[used]
            if not row then
                row=CreateFrame("Button",nil,state.content,"BackdropTemplate")
                row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
                row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetPoint("LEFT",8,0); row.icon:SetSize(30,30)
                row.title=Text(row,13); row.title:SetPoint("TOPLEFT",50,-8); row.title:SetHeight(18); row.title:SetWordWrap(false)
                row.subtitle=Text(row,10); row.subtitle:SetPoint("TOPLEFT",50,-32); row.subtitle:SetHeight(14); row.subtitle:SetWordWrap(false)
                row.wish=Button(row,"+",20,function() ML.ToggleItemWishlist(row.entry.item.id) end)
                row.wish:SetPoint("RIGHT",-5,0); row.wish:SetHeight(20)
                row.wish:SetScript("OnEnter",function(button)
                    GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); GameTooltip:AddLine(ML.IsWishlisted(row.entry.item.id) and "Remove from wishlist" or "Add to wishlist",1,0.82,0); GameTooltip:Show()
                end)
                row.wish:SetScript("OnLeave",function() GameTooltip:Hide() end)
                row:SetScript("OnClick",function(self)
                    if self.entry.item and PreviewItem(self.entry.item) then return end
                    state.click(self.entry)
                end)
                row:SetScript("OnEnter",function(self)
                    local item=self.entry.item
                    if item then
                        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                        GameTooltip:SetHyperlink(item.link or ("item:"..item.id))
                        GameTooltip:AddLine("Ctrl-click to preview",0.7,0.65,0.55)
                        GameTooltip:Show()
                    elseif self.entry.npc or self.entry.source then
                        local npc=self.entry.npc or self.entry.source.mob.id
                        local mob=ML.GetMob(npc)
                        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                        GameTooltip:AddLine(mob and mob.name or ("NPC #"..npc),1,0.82,0)
                        if selected then
                            local context=ML.CatalogDropNote(npc,selected)
                            if context then GameTooltip:AddLine("Known loot context: "..context,0.8,0.7,0.5,true)
                            else GameTooltip:AddLine("Availability may depend on difficulty or conditions.",0.8,0.7,0.5,true) end
                        end
                        GameTooltip:AddLine("Click: open bestiary entry",0.7,0.65,0.55)
                        GameTooltip:Show()
                    end
                end)
                row:SetScript("OnLeave",function() GameTooltip:Hide() end)
                state.rows[used]=row
            end
            row.entry=entry; row.catalogItem=nil; row.source=nil
            row:SetPoint("TOPLEFT",20,-entry.offset); row:SetSize(state.width-20,state.stride-4)
            row.wish:SetShown(entry.item~=nil)
            row.title:SetWidth(state.width-(entry.item and 110 or 84)); row.subtitle:SetWidth(state.width-(entry.item and 110 or 84))
            if entry.item then row.wish:SetText(ML.IsWishlisted(entry.item.id) and "*" or "+") end
            row.icon:Show()
            if row.portrait then row.portrait:Hide() end
            state.update(row,entry)
            row:Show()
        end
    end
    for i=used+1,#state.rows do state.rows[i]:Hide(); state.rows[i].catalogItem=nil; state.rows[i].source=nil end
    for i=usedHeaders+1,#state.headers do state.headers[i]:Hide() end
end
local function Fill(state,entries)
    local height=0
    for _,entry in ipairs(entries) do
        entry.offset=height; entry.height=entry.header and 32 or state.stride
        height=height+entry.height
    end
    state.entries=entries
    state.content:SetHeight(math.max(1,height))
    if state.scroll:GetVerticalScroll()>math.max(0,height-state.scroll:GetHeight()) then state.scroll:SetVerticalScroll(math.max(0,height-state.scroll:GetHeight())) end
    Draw(state)
end
local function Category(entries,key,label,values,convert)
    if #values==0 then return end
    entries[#entries+1]={header=true,key=key,label=label,count=#values}
    if not closed[key] then for _,value in ipairs(values) do entries[#entries+1]=convert(value) end end
end
local function SortSources(values,possible)
    local result={}
    for _,value in ipairs(values) do
        local mob=possible and ML.GetMob(value) or value.mob
        local drop=not possible and value.drop
        result[#result+1]={id=mob.id,name=mob.name,count=mob.count,quantity=drop and drop.quantity or 0,
            last=drop and (drop.last or 0) or mob.last or 0,lastOrder=drop and drop.lastOrder or 0,
            source=not possible and value or nil,npc=possible and value or nil}
    end
    local mode=ML.GetSortMode("itemSources")
    table.sort(result,function(a,b) return ML.SortBefore(a,b,mode) end)
    return result
end

function ML.RefreshItems()
    if not page or not page:IsVisible() then return end
    local items=ML.ItemCatalog(search:GetText(),rarity,area)
    if not itemBuckets or itemBuckets.items~=items then
        itemBuckets={items=items,observed={},unlooted={},wishlist={},byID={}}
        for _,item in ipairs(items) do
            itemBuckets.byID[item.id]=item
            local bucket=ML.IsWishlisted(item.id) and itemBuckets.wishlist or
                (item.quantity>0 and itemBuckets.observed or itemBuckets.unlooted)
            bucket[#bucket+1]=item
        end
    end
    local observed,unlooted,wishlist=itemBuckets.observed,itemBuckets.unlooted,itemBuckets.wishlist
    local chosen=itemBuckets.byID[selected]
    if not chosen then chosen=wishlist[1] or observed[1] or unlooted[1]; selected=chosen and chosen.id; right.scroll:SetVerticalScroll(0) end
    local status=ML.CatalogUnavailableText()
    local layoutKey=tostring(closed.wishlist)..":"..tostring(closed.observed)..":"..tostring(closed.unlooted)..":"..tostring(status~=nil)
    if left.layoutItems==items and left.layoutKey==layoutKey then
        if left.statusEntry then left.statusEntry.label=status end
        Draw(left)
    else
        local entries={}
        Category(entries,"wishlist","Wishlist",wishlist,function(item) return {item=item} end)
        Category(entries,"observed","Observed drops",observed,function(item) return {item=item} end)
        Category(entries,"unlooted","Not observed drops",unlooted,function(item) return {item=item} end)
        left.statusEntry=nil
        if status then
            left.statusEntry={header=true,key="catalogUnavailable",label=status,count=0}
            entries[#entries+1]=left.statusEntry
        end
        Fill(left,entries)
        left.layoutItems,left.layoutKey=items,layoutKey
    end
    empty:SetShown(#items==0)
    empty:SetText("No items match your search and filters.")
    local _,known,total=ML.ItemSearchStatus()
    if #items==0 and known<total and (search:GetText()~="" or rarity~="all") then
        empty:SetText("No matches in the available search index.\nUse Prepare search for missing names and rarities, or search by item ID.")
    end
    if chosen then ML.LoadCatalogItem(chosen,search:GetText()=="" and rarity=="all") end
    heading:SetText(chosen and (chosen.link or chosen.name) or "Select an item")
    explanation:SetText("Observed sources show your personal drop rates.\nPossible sources have no recorded drop for this item yet.")
    local sourceKey=tostring(selected)..":"..tostring(closed.sources)..":"..tostring(closed.possible)..":"..
        ML.GetSortMode("itemSources")..":"..tostring(ML.itemSourceRevision or 0)
    if right.layoutItems==items and right.layoutKey==sourceKey then
        Draw(right)
    else
        local sources={}
        local observedSources=chosen and chosen.sources or {}
        if area~="all" then
            local filtered={}
            for _,source in ipairs(observedSources) do if ML.MatchesCatalogArea(source.mob,area) then filtered[#filtered+1]=source end end
            observedSources=filtered
        end
        Category(sources,"sources","Observed sources",closed.sources and observedSources or SortSources(observedSources,false),function(entry) return entry end)
        local possible=chosen and ML.PossibleItemSources(chosen.id) or {}
        if area~="all" then
            local filtered={}; for _,id in ipairs(possible) do if ML.MatchesCatalogArea(ML.GetMob(id),area) then filtered[#filtered+1]=id end end; possible=filtered
        end
        Category(sources,"possible","Possible sources · not observed",closed.possible and possible or SortSources(possible,true),function(entry) return entry end)
        if #sources==0 then sources[1]={header=true,key="empty",label="No known sources",count=0} end
        Fill(right,sources)
        right.layoutItems,right.layoutKey=items,sourceKey
    end
    ML.RefreshItemSearchStatus()
end

function ML.RefreshItemRows()
    if not page or not page:IsVisible() then return end
    Draw(left)
    -- Refresh the selected heading only; keep list membership/selection/scroll.
    local item=itemBuckets and itemBuckets.byID[selected]
    if item then ML.LoadCatalogItem(item,false); heading:SetText(item.link or item.name) end
end

function ML.RefreshItemSearchStatus()
    if not prepareButton or not searchStatus then return end
    local job,known,total,outcome=ML.ItemSearchStatus()
    local loading=ML.catalogLoadScheduled or (ML.TrinityData and ML.TrinityData.queued and not ML.TrinityData.ready)
    prepareButton:SetEnabled(not loading)
    if loading then
        prepareButton:SetText("Loading..."); searchStatus:SetText((ML.CatalogUnavailableText() or "").."\nYour recorded items remain searchable."); return
    end
    prepareButton:SetText(job and "Pause" or (known==total and "Update index" or outcome and outcome.completed and "Retry missing" or "Prepare search"))
    if job then
        searchStatus:SetText(string.format("%s: %d / %d indexed · Pass %d / 3\n%s",job.inCombat and "Paused in combat" or job.retryAt and "Retrying" or "Preparing",known+job.resolved,total,job.pass or 1,
            ML.BackgroundItemScanEnabled() and "Continues in the background; pauses in combat." or "Starting a search or leaving this tab pauses preparation."))
    elseif known==total then
        searchStatus:SetText(string.format("Search index complete: %d / %d items.\nSaved for this language.",known,total))
    elseif outcome and outcome.completed then
        searchStatus:SetText(string.format("Scan finished: %d / %d items indexed.\n%d unresolved (name or rarity). Retry missing to check again.",known,total,total-known))
    else
        searchStatus:SetText(string.format("%s: %d / %d items indexed.\n%d need name or rarity lookup; item IDs work immediately.",outcome and "Scan paused" or "Search index",known,total,total-known))
    end
end
function ML.BuildItemBrowser(parent,ui)
    Text,Panel,Button=ui.Text,ui.Panel,ui.Button
    page=CreateFrame("Frame",nil,parent); page:SetAllPoints()
    local label=Text(page,10); label:SetPoint("TOPLEFT",28,-170); label:SetText("ITEM NAME OR ID")
    search=CreateFrame("EditBox",nil,page,"InputBoxTemplate"); search:SetSize(160,28); search:SetPoint("TOPLEFT",34,-191); search:SetAutoFocus(false)
    search:SetScript("OnTextChanged",function()
        if not left then return end
        searchSequence=searchSequence+1
        local token=searchSequence
        if search:GetText()~="" and ML.ItemSearchStatus() and not ML.BackgroundItemScanEnabled() then ML.PauseItemSearchPreparation() end
        C_Timer.After(0.15,function()
            if token~=searchSequence or not page:IsVisible() or (ML.ItemSearchStatus() and not ML.BackgroundItemScanEnabled()) then return end
            left.scroll:SetVerticalScroll(0); ML.RefreshItems()
        end)
    end)
    search:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    ML.BuildSortDropdown(page,ui,"items","items",206,-191,164,function()
        left.scroll:SetVerticalScroll(0); ML.RefreshItems()
    end)
    rarityButton=Button(page,"All rarities  v",220,function() rarityMenu:SetShown(not rarityMenu:IsShown()) end)
    rarityButton:SetPoint("TOPLEFT",26,-226)
    prepareButton=Button(page,"Prepare search",116,function()
        if ML.ItemSearchStatus() then ML.PauseItemSearchPreparation(); return end
        search:SetText(""); ML.SetItemRarityFilter("all")
        ML.PrepareItemSearch(function() return page:IsVisible() end)
        ML.RefreshItems()
    end)
    prepareButton:SetPoint("TOPLEFT",254,-226)
    prepareButton:SetScript("OnEnter",function(self)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
        GameTooltip:AddLine("Prepare item search",1,0.82,0)
        GameTooltip:AddLine("Resolve missing names and rarities once and save them for this language. Preparation pauses in combat. With background item scanning enabled, it continues after leaving this tab or starting a search; otherwise it stops. Use Pause to stop it manually. Some IDs may remain unavailable. Searching itself never starts a catalog lookup.",1,1,1,true)
        GameTooltip:Show()
    end)
    prepareButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
    rarityMenu=Panel(page); rarityMenu:SetSize(344,#ML.ItemRarityFilters*26+14); rarityMenu:SetPoint("TOPLEFT",rarityButton,"BOTTOMLEFT",0,-2)
    rarityMenu:SetFrameLevel(page:GetFrameLevel()+70); rarityMenu:Hide()
    for i,entry in ipairs(ML.ItemRarityFilters) do
        local key=entry.key
        local option=Button(rarityMenu,RarityLabel(entry),326,function() ML.SetItemRarityFilter(key) end)
        option:SetPoint("TOPLEFT",9,-7-(i-1)*26); option:SetHeight(25)
    end
    areaButton=ML.BuildAreaNavigation(page,ui,26,-126,846,function(key) area=key; left.scroll:SetVerticalScroll(0); ML.RefreshItems() end)
    local function List(parentFrame,x,y,width,height,update,click)
        local clip=CreateFrame("Frame",nil,parentFrame); clip:SetPoint("TOPLEFT",x,y); clip:SetSize(width+26,height); clip:SetClipsChildren(true)
        local scroll=CreateFrame("ScrollFrame",nil,clip,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT"); scroll:SetSize(width,height)
        local content=CreateFrame("Frame",nil,scroll); content:SetSize(width-4,1); scroll:SetScrollChild(content)
        local state={scroll=scroll,content=content,width=width-4,stride=62,rows={},headers={},entries={},update=update,click=click}
        scroll:HookScript("OnVerticalScroll",function() Draw(state) end)
        return state
    end
    left=List(page,26,-260,344,276,function(row,entry)
        local item=entry.item; ML.LoadCatalogItem(item,search:GetText()=="" and rarity=="all"); row.catalogItem=item
        row.icon:SetTexture(item.icon or 134400); row.title:SetText(item.link or item.name)
        row.subtitle:SetText(item.quantity>0 and string.format("%d items · %d observed sources",item.quantity,#item.sources) or "Not observed · no drops recorded")
        row:SetBackdropColor(item.id==selected and 0.16 or 0.065,item.id==selected and 0.12 or 0.055,0.04,1)
    end,function(entry) if selected~=entry.item.id then ML.PushView() end; selected=entry.item.id; right.scroll:SetVerticalScroll(0); ML.RefreshItems() end)
    local panel=Panel(page); panel:SetPoint("TOPLEFT",410,-180); panel:SetSize(462,388)
    heading=Text(panel,17,{0.92,0.76,0.45}); heading:SetPoint("TOPLEFT",14,-15); heading:SetSize(430,24); heading:SetWordWrap(false)
    explanation=Text(panel,11); explanation:SetPoint("TOPLEFT",14,-51); explanation:SetSize(430,36)
    ML.BuildSortDropdown(panel,ui,"itemSources","mixed",282,-92,164,function()
        right.scroll:SetVerticalScroll(0); ML.RefreshItems()
    end)
    right=List(panel,12,-126,422,247,function(row,entry)
        local source=entry.source
        local mob=source and source.mob or ML.GetMob(entry.npc)
        row.source=source
        row.icon:SetTexture(134400)
        if not row.portrait then row.portrait=ML.CreateMobPortrait(row,30); row.portrait:SetPoint("LEFT",8,0) end
        row.portrait:Show(); row.icon:Hide(); ML.UpdateMobPortrait(row.portrait,mob)
        row.title:SetText(mob.name)
        if source then row.subtitle:SetText(string.format("%.1f %% · %d / %d mobs · %d items",ML.DropRate(mob,source.drop),source.drop.corpses,mob.count,source.drop.quantity))
        else row.subtitle:SetText("Not observed · availability may depend on difficulty or conditions") end
        row:SetBackdropColor(0.075,0.06,0.04,1)
    end,function(entry)
        local id=entry.source and entry.source.mob.id or entry.npc
        ML.OpenMob(id)
    end)
    empty=Text(page,13); empty:SetPoint("TOPLEFT",36,-266); empty:SetWidth(310)
    ML.BuildFooterNote(page,Text,"Personal drop samples; bag receipt is not verified.\nPossible sources may be incomplete or conditional. Hover for details.",
        "Not observed drops are items without a drop recorded by MobLog; bag receipt is not verified.\nPossible sources may be incomplete or conditional. Percentages use your observations only.")
    searchStatus=Text(page,10); searchStatus:SetPoint("TOPLEFT",28,-540); searchStatus:SetSize(344,32)
    page:SetScript("OnShow",function() ML.PublishItemSearchIndex(); ML.RefreshItemSearchStatus() end)
    page:SetScript("OnHide",function()
        searchSequence=searchSequence+1
        rarityMenu:Hide(); areaButton:CloseMenu()
        if not ML.BackgroundItemScanEnabled() then ML.PauseItemSearchPreparation() end
    end)
    search:SetScript("OnEditFocusGained",function()
        rarityMenu:Hide(); areaButton:CloseMenu()
        if not ML.ItemSearchStatus() then ML.PublishItemSearchIndex() end
    end)
    page:Hide()
    return page
end

function ML.GetItemsView()
    return {query=search:GetText(),rarity=rarity,area=area,selected=selected,closed=ML.CopyViewTable(closed),
        left=left.scroll:GetVerticalScroll(),right=right.scroll:GetVerticalScroll(),sort=ML.GetSortMode("items"),sourceSort=ML.GetSortMode("itemSources")}
end
function ML.RestoreItemsView(state)
    area=state.area or "all"; areaButton:SetSelection(area,false)
    rarity=state.rarity or "all"
    for _,entry in ipairs(ML.ItemRarityFilters) do if entry.key==rarity then rarityButton:SetText(RarityLabel(entry).."  v") end end
    closed=ML.CopyViewTable(state.closed); selected=state.selected
    ML.db.sortModes=ML.db.sortModes or {}; ML.db.sortModes.items=state.sort; ML.db.sortModes.itemSources=state.sourceSort; ML.UpdateSortLabels()
    searchSequence=searchSequence+1; search:SetText(state.query or ""); searchSequence=searchSequence+1
    ML.RefreshItems(); ML.SetViewScroll(left.scroll,state.left); ML.SetViewScroll(right.scroll,state.right)
end
function ML.ResetItemsFilters()
    area="all"; areaButton:Reset(); search:SetText(""); searchSequence=searchSequence+1; ML.SetItemRarityFilter("all")
    left.scroll:SetVerticalScroll(0); right.scroll:SetVerticalScroll(0); ML.RefreshItems()
end
function ML.UseItemsCurrentArea(filter) areaButton:SetSelection(filter,true) end
function ML.FocusItem(id)
    ML.ResetItemsFilters(); selected=id
    closed[ML.IsWishlisted(id) and "wishlist" or "unlooted"]=false; closed.observed=false
    ML.RefreshItems()
    for _,entry in ipairs(left.entries) do if entry.item and entry.item.id==id then ML.SetViewScroll(left.scroll,entry.offset); break end end
    right.scroll:SetVerticalScroll(0)
end

function ML.RefreshItemCatalogStatus()
    if not page or not page:IsVisible() then return end
    for _,header in ipairs(left.headers) do
        if header.entry and header.entry.key=="catalogUnavailable" and header:IsVisible() then header.label:SetText(ML.CatalogUnavailableText() or "Catalog ready") end
    end
    ML.RefreshItemSearchStatus()
end
