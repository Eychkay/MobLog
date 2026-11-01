-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

function ML.BuildMobLoot(parent,scroll,ui)
    local view={active=false,rows={},headers={},closed={observed=true,possible=true},entries={}}
    local summary=ui.Text(parent,10); summary:SetPoint("TOPLEFT"); summary:SetSize(412,22)
    summary:SetText("Personal rates only. Possible drops may be incomplete or conditional.")
    local caption=ui.Text(parent,10); caption:SetPoint("TOPLEFT",0,-28); caption:SetText("DROPS FOR THIS NPC")
    local sort=ML.BuildSortDropdown(parent,ui,"mobLoot","items",248,-24,164,function() view:Show(view.mob) end)
    sort:SetHeight(22)

    function view:Hide()
        self.active=false; summary:Hide(); caption:Hide(); sort:Hide()
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
            if entry.offset+entry.height<y-46 then low=middle+1 else high=middle-1 end
        end
        for index=low,#self.entries do
            local entry=self.entries[index]
            if entry.offset>y+scroll:GetHeight()+46 then break end
            if entry.offset+entry.height>=y-46 then
                if entry.header then
                    usedHeaders=usedHeaders+1
                    local header=self.headers[usedHeaders]
                    if not header then
                        header=CreateFrame("Button",nil,parent,"BackdropTemplate")
                        header:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); header:SetBackdropColor(0.11,0.09,0.06,1)
                        header.label=ui.Text(header,12,{0.92,0.76,0.45}); header.label:SetPoint("LEFT",8,0); header.label:SetSize(396,18); header.label:SetWordWrap(false)
                        header:SetScript("OnClick",function(button)
                            self.closed[button.entry.key]=not self.closed[button.entry.key]; self:Show(self.mob)
                        end)
                        self.headers[usedHeaders]=header
                    end
                    header.entry=entry; header:SetPoint("TOPLEFT",0,-entry.offset); header:SetSize(412,28)
                    header.label:SetText((self.closed[entry.key] and "+ " or "- ")..entry.label.." ("..entry.count..")")
                    header:Show()
                else
                    used=used+1
                    local row=self.rows[used]
                    if not row then
                        row=CreateFrame("Button",nil,parent,"BackdropTemplate"); row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
                        row:SetBackdropColor(0.075,0.06,0.04,1); row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight","ADD")
                        row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetPoint("LEFT",5,0); row.icon:SetSize(30,30)
                        row.name=ui.Text(row,12); row.name:SetPoint("TOPLEFT",43,-5); row.name:SetSize(260,16); row.name:SetWordWrap(false)
                        row.source=ui.Text(row,10); row.source:SetPoint("TOPLEFT",43,-24); row.source:SetSize(260,12); row.source:SetWordWrap(false)
                        row.count=ui.Text(row,13); row.count:SetPoint("RIGHT",-34,0)
                        row.wish=ui.Button(row,"+",20,function() ML.ToggleItemWishlist(row.entry.item.id) end)
                        row.wish:SetPoint("RIGHT",-5,0); row.wish:SetHeight(20)
                        row.wish:SetScript("OnEnter",function(button)
                            GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); GameTooltip:AddLine(ML.IsWishlisted(row.entry.item.id) and "Remove from wishlist" or "Add to wishlist",1,0.82,0); GameTooltip:Show()
                        end)
                        row.wish:SetScript("OnLeave",function() GameTooltip:Hide() end)
                        row:SetScript("OnClick",function(button)
                            if not button.entry.item then return end
                            if ML.PreviewItem(button.entry.item) then return end
                            ML.OpenItem(button.entry.item.id)
                        end)
                        row:SetScript("OnEnter",function(button)
                            local item=button.entry.item
                            if not item then return end
                            GameTooltip:SetOwner(button,"ANCHOR_RIGHT"); GameTooltip:SetHyperlink(item.link or ("item:"..item.id))
                            if button.entry.observed then GameTooltip:AddLine(string.format("Personal drop rate: %.1f %%",ML.DropRate(self.mob,item)),0.35,0.84,0.74)
                            else GameTooltip:AddLine("Not observed for this NPC. Availability may be conditional.",0.8,0.7,0.5,true) end
                            local context=ML.CatalogDropNote(self.mob.id,item.id)
                            if context then GameTooltip:AddLine("Known loot context: "..context,0.8,0.7,0.5,true) end
                            GameTooltip:AddLine("Click: item sources · Ctrl-click: preview",0.7,0.65,0.55); GameTooltip:Show()
                        end)
                        row:SetScript("OnLeave",function() GameTooltip:Hide() end)
                        self.rows[used]=row
                    end
                    row.entry=entry; row:SetPoint("TOPLEFT",12,-entry.offset); row:SetSize(400,entry.height-4)
                    local item=entry.item
                    row.icon:SetShown(item~=nil); row.wish:SetShown(item~=nil)
                    if item then
                        local originalLink=entry.observed and item.link
                        ML.LoadCatalogItem(item,true)
                        if originalLink then item.link=originalLink end
                        row.name:SetText(item.link or item.name); row.icon:SetTexture(item.icon or 134400)
                        row.source:SetText(entry.observed and string.format("%.1f %% · %d / %d mobs",ML.DropRate(self.mob,item),item.corpses or 0,self.mob.count) or "Not observed for this NPC")
                        row.count:SetText(entry.observed and ("×"..item.quantity) or "")
                        row.wish:SetText(ML.IsWishlisted(item.id) and "*" or "+")
                    else row.name:SetText(entry.message); row.source:SetText(""); row.count:SetText("") end
                    row:Show()
                end
            end
        end
        for i=used+1,#self.rows do self.rows[i]:Hide() end
        for i=usedHeaders+1,#self.headers do self.headers[i]:Hide() end
    end

    function view:Show(mob)
        self.mob,self.active=mob,true
        summary:Show(); caption:Show(); sort:Show(); sort:UpdateLabel()
        local observed,possible,seen={},{},{}
        for id,item in pairs(mob.items or {}) do
            if (item.quantity or 0)>0 then
                local copy=ML.CopyViewTable(item); copy.id=id; copy.name=copy.name or ("Item #"..id)
                observed[#observed+1]=copy; seen[id]=true
            end
        end
        for _,id in ipairs(ML.CatalogMobDrops(mob.id)) do if not seen[id] then possible[#possible+1]=ML.CatalogItemInfo(id) end end
        local mode=ML.GetSortMode("mobLoot")
        for _,items in ipairs({observed,possible}) do
            table.sort(items,function(a,b) return ML.SortBefore(a,b,mode) end)
        end
        self.entries={}
        local offset=52
        local function Section(key,label,items,empty)
            self.entries[#self.entries+1]={header=true,key=key,label=label,count=#items,offset=offset,height=32}; offset=offset+32
            if self.closed[key] then return end
            if #items==0 then self.entries[#self.entries+1]={message=empty,offset=offset,height=26}; offset=offset+26 end
            for _,item in ipairs(items) do
                self.entries[#self.entries+1]={item=item,observed=key=="observed",offset=offset,height=46}; offset=offset+46
            end
        end
        Section("observed","Observed drops",observed,"No item drops recorded for this NPC yet.")
        Section("possible","Not observed drops",possible,ML.CatalogUnavailableText() or "No additional catalog drops known for this NPC.")
        parent:SetHeight(math.max(140,offset))
        ML.SetViewScroll(scroll,scroll:GetVerticalScroll()); self:Draw()
    end
    scroll:HookScript("OnVerticalScroll",function() view:Draw() end)
    view:Hide()
    return view
end
