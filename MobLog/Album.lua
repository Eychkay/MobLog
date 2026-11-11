-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...

function ML.BuildMobAlbum(parent, ui, onSelect)
    local view={page=1,cards={},pageSize=4}
    view.frame=CreateFrame("Frame",nil,parent)
    view.frame:SetPoint("TOPLEFT",26,-260); view.frame:SetSize(846,308)
    for leaf=1,2 do
        local paper=view.frame:CreateTexture(nil,"BACKGROUND")
        paper:SetPoint("TOPLEFT",leaf==1 and 0 or 430,0); paper:SetSize(416,274)
        if C_Texture and C_Texture.GetAtlasInfo("QuestBG-Parchment") then paper:SetAtlas("QuestBG-Parchment")
        else paper:SetTexture("Interface\\QuestFrame\\QuestBG") end
        paper:SetVertexColor(0.97,0.93,0.84)
        local rule=view.frame:CreateTexture(nil,"BORDER")
        rule:SetColorTexture(0.33,0.20,0.09,0.25); rule:SetSize(374,1)
        rule:SetPoint("TOPLEFT",leaf==1 and 21 or 451,-136)
    end
    local spine=view.frame:CreateTexture(nil,"BORDER")
    spine:SetPoint("TOPLEFT",416,0); spine:SetSize(14,274); spine:SetColorTexture(0.12,0.075,0.036,1)
    for edge=1,2 do
        local shadow=view.frame:CreateTexture(nil,"BORDER")
        shadow:SetPoint("TOPLEFT",edge==1 and 404 or 430,0); shadow:SetSize(12,274)
        shadow:SetColorTexture(0.22,0.13,0.06,0.32)
    end
    view.heading=ui.Text(parent,19,{0.92,0.76,0.45})
    view.heading:SetPoint("TOPLEFT",420,-194); view.heading:SetSize(240,25)
    view.subheading=ui.Text(parent,11,{0.77,0.70,0.55})
    view.subheading:SetPoint("TOPLEFT",420,-226); view.subheading:SetSize(442,18); view.subheading:SetWordWrap(true)
    view.progress=CreateFrame("StatusBar",nil,parent)
    view.progress:SetPoint("TOPLEFT",420,-249); view.progress:SetSize(442,4)
    view.progress:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8")
    view.progress:SetStatusBarColor(0.75,0.56,0.24)
    view.previous=ui.Button(view.frame,"<",32,function() view.page=view.page-1; ML.Refresh(true) end)
    view.previous:SetPoint("BOTTOMLEFT",0,0); view.previous:SetHeight(24)
    view.next=ui.Button(view.frame,">",32,function() view.page=view.page+1; ML.Refresh(true) end)
    view.next:SetPoint("BOTTOMRIGHT",0,0); view.next:SetHeight(24)
    view.counter=ui.Text(view.frame,11); view.counter:SetPoint("BOTTOM",0,5)
    for direction,button in pairs({Prev=view.previous,Next=view.next}) do
        button:SetText(""); button:SetSize(28,28)
        button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-"..direction.."Page-Up")
        button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-"..direction.."Page-Down")
        button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-"..direction.."Page-Disabled")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight","ADD")
    end
    view.empty=ui.Text(view.frame,13,{0.28,0.19,0.10}); view.empty:SetPoint("TOPLEFT",34,-100); view.empty:SetWidth(344)

    function view:Hide()
        self.frame:Hide(); self.heading:Hide(); self.subheading:Hide(); self.progress:Hide()
        for _,card in ipairs(self.cards) do card:Hide(); card.mob=nil end
    end

    function view:Show(mobs,undiscoveredCount,key,getUndiscovered,selected)
        if self.key~=key then self.page=1; self.key=key end
        local total=#mobs+undiscoveredCount
        self.mobs,self.getUndiscovered,self.total=mobs,getUndiscovered,total
        local pages=math.max(1,math.ceil(total/self.pageSize))
        self.page=math.max(1,math.min(self.page,pages))
        self.frame:Show(); self.heading:Show(); self.subheading:Show()
        self.progress:Show(); self.progress:SetMinMaxValues(0,math.max(1,total)); self.progress:SetValue(#mobs)
        self.heading:SetText("Your bestiary")
        self.subheading:SetText(ML.CatalogUnavailableText() or (#mobs.." collected · "..undiscoveredCount.." undiscovered"))
        self.counter:SetText(string.format("%d  —  %d     /     %d",self.page*2-1,self.page*2,pages*2))
        self.previous:SetEnabled(self.page>1); self.next:SetEnabled(self.page<pages)
        self.empty:SetShown(total==0)
        self.empty:SetText(ML.CatalogUnavailableText() or "No creatures match your search and filters.")
        local ids
        ML.db.albumViewed=ML.db.albumViewed or {}
        ML.db.albumStarted=ML.db.albumStarted or time()
        for slot=1,self.pageSize do
            local index=(self.page-1)*self.pageSize+slot
            local mob=mobs[index]
            if index<=total and not mob then
                ids=ids or getUndiscovered()
                local id=ids[index-#mobs]
                mob=id and ML.GetMob(id)
            end
            local card=self.cards[slot]
            if mob then
                if not card then
                    card=CreateFrame("Frame",nil,self.frame,"BackdropTemplate"); card:EnableMouse(true)
                    card:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12,insets={left=3,right=3,top=3,bottom=3}})
                    card:SetSize(388,116)
                    card.portrait=ML.CreateMobPortrait(card,66)
                    card.portrait:SetPoint("TOPLEFT",39,-25)
                    card.portrait.maxFrameWidth,card.portrait.maxFrameHeight=112,92
                    card.question=ui.Text(card.portrait,36,{0.40,0.30,0.18}); card.question:SetPoint("CENTER",0,0); card.question:SetText("?")
                    card.name=ui.Text(card,15,{0.22,0.12,0.055}); card.name:SetPoint("TOPLEFT",140,-14)
                    card.name:SetSize(229,38); card.name:SetWordWrap(true)
                    card.status=ui.Text(card,11,{0.36,0.24,0.13}); card.status:SetPoint("TOPLEFT",140,-57)
                    card.status:SetSize(229,15); card.status:SetWordWrap(false)
                    card.rank=ui.Text(card,11,{0.30,0.18,0.07}); card.rank:SetPoint("TOPLEFT",140,-80)
                    card.rank:SetSize(229,18); card.rank:SetWordWrap(false)
                    for _,label in ipairs({card.name,card.status,card.rank,card.question}) do label:SetShadowColor(0,0,0,0) end
                    card.new=ui.Text(card,9,{0.55,0.07,0.035}); card.new:SetPoint("TOPRIGHT",-8,-5); card.new:SetText("NEW")
                    card:SetScript("OnMouseUp",function(button,mouse)
                        if mouse~="LeftButton" or not button.mob then return end
                        if not button.mob.catalogOnly then
                            for _,member in ipairs(button.mob.members or {button.mob}) do ML.db.albumViewed[member.id]=true end
                        end
                        self.inspectedIndex=button.index
                        onSelect(button.mob)
                    end)
                    card:SetScript("OnEnter",function(button)
                        local creature=button.mob
                        if not creature then return end
                        GameTooltip:SetOwner(button,"ANCHOR_RIGHT")
                        GameTooltip:AddLine(creature.name,0.92,0.76,0.45)
                        GameTooltip:AddLine(creature.catalogOnly and "Undiscovered" or ML.CollectionProgress(creature),0.85,0.82,0.74,true)
                        for _,line in ipairs(ML.CollectionAchievementLines(creature)) do GameTooltip:AddLine(line,0.85,0.82,0.74,true) end
                        ML.AddMobLocationTooltip(creature)
                        GameTooltip:AddLine("Click to open creature details.",1,1,1)
                        GameTooltip:Show()
                        button:SetBackdropColor(0.34,0.19,0.06,0.14)
                    end)
                    card:SetScript("OnLeave",function(button) GameTooltip:Hide(); button:SetBackdropColor(0.34,0.19,0.06,0.035) end)
                    self.cards[slot]=card
                end
                card.mob=mob
                card.index=index
                card:SetPoint("TOPLEFT",slot<=2 and 14 or 444,-10-((slot-1)%2)*136)
                card:SetBackdropColor(0.34,0.19,0.06,0.035)
                local rank=ML.KillRank(mob.count)
                local color=rank and rank.color or {0.48,0.34,0.18}
                if ML.GroupContains(mob,selected) then color={0.45,0.24,0.055} end
                card:SetBackdropBorderColor(unpack(color))
                card.question:SetShown(mob.catalogOnly==true)
                if mob.catalogOnly then
                    ML.LayoutMobPortrait(card.portrait)
                    card.portrait.mobID,card.portrait.displayID=nil,nil
                    card.portrait.icon:SetTexture(nil)
                    card.portrait.backing:SetColorTexture(0.47,0.36,0.22,0.18)
                    card.portrait.dragon:Hide(); card.portrait.star:Hide()
                    card.portrait.ring:SetVertexColor(0.48,0.37,0.22)
                    card.name:SetText(mob.name or ("NPC #"..mob.id))
                    card.status:SetText("Not yet discovered")
                    card.rank:SetText("Known clues available")
                else
                    card.portrait.backing:SetColorTexture(0.02,0.018,0.015,1)
                    ML.UpdateMobPortrait(card.portrait,mob)
                    card.name:SetText(mob.name)
                    card.status:SetText(ML.ClassificationLabel(mob).." · "..((mob.count or 0)>0 and (mob.count.." recorded kills") or "Seen only"))
                    card.rank:SetText(rank and (rank.label.." collection rank") or ((mob.first or 0)>0 and ("Discovered "..date("%Y-%m-%d",mob.first)) or "Recorded in your bestiary"))
                end
                card.new:SetShown(not mob.catalogOnly and (mob.first or 0)>=ML.db.albumStarted and not ML.db.albumViewed[mob.id])
                card:Show()
            elseif card then card:Hide(); card.mob=nil end
        end
    end
    function view:Neighbor(step)
        local index=(self.inspectedIndex or 1)+step
        if index<1 or index>(self.total or 0) then return end
        local mob=self.mobs and self.mobs[index]
        if not mob and self.getUndiscovered then
            local ids=self.getUndiscovered()
            mob=ids[index-#self.mobs] and ML.GetMob(ids[index-#self.mobs])
        end
        return mob,index
    end
    view:Hide()
    return view
end

function ML.BuildAlbumEntry(parent,ui,onBack,onNeighbor)
    local book={}
    book.frame=CreateFrame("Frame",nil,parent)
    book.frame:SetPoint("TOPLEFT",26,-164); book.frame:SetSize(846,404)
    book.frame:SetFrameLevel(parent:GetFrameLevel()+1)
    for leaf=1,2 do
        local paper=book.frame:CreateTexture(nil,"BACKGROUND")
        paper:SetPoint("TOPLEFT",leaf==1 and 0 or 392,0); paper:SetSize(leaf==1 and 378 or 454,404)
        if C_Texture and C_Texture.GetAtlasInfo("QuestBG-Parchment") then paper:SetAtlas("QuestBG-Parchment")
        else paper:SetTexture("Interface\\QuestFrame\\QuestBG") end
        paper:SetVertexColor(0.97,0.93,0.84)
    end
    local spine=book.frame:CreateTexture(nil,"BORDER")
    spine:SetPoint("TOPLEFT",378,0); spine:SetSize(14,404); spine:SetColorTexture(0.12,0.075,0.036,1)
    book.contentShade=book.frame:CreateTexture(nil,"BORDER")
    book.contentShade:SetPoint("TOPLEFT",400,-104); book.contentShade:SetSize(440,282)
    book.contentShade:SetColorTexture(0.065,0.05,0.037,0.97); book.contentShade:Hide()
    book.back=ui.Button(book.frame,"Back to album",130,onBack)
    book.back:SetPoint("TOPLEFT",16,-8); book.back:SetHeight(22)
    book.title=ui.Text(book.frame,16,{0.22,0.12,0.055})
    book.title:SetPoint("TOPLEFT",24,-34); book.title:SetSize(328,34); book.title:SetWordWrap(true); book.title:SetJustifyV("TOP")
    book.subtitle=ui.Text(book.frame,11,{0.36,0.24,0.13})
    book.subtitle:SetPoint("TOPLEFT",24,-68); book.subtitle:SetSize(328,16); book.subtitle:SetWordWrap(false)
    book.notes=ui.Text(book.frame,19,{0.28,0.16,0.07})
    book.notes:SetPoint("TOPLEFT",408,-17); book.notes:SetText("Field notes")
    book.rank=ui.Text(book.frame,11,{0.36,0.24,0.13})
    book.rank:SetPoint("TOPLEFT",408,-47); book.rank:SetSize(418,18); book.rank:SetWordWrap(false)
    for _,label in ipairs({book.title,book.subtitle,book.notes,book.rank}) do label:SetShadowColor(0,0,0,0) end
    book.previous=ui.Button(book.frame,"Previous",90,function() onNeighbor(-1) end)
    book.previous:SetPoint("BOTTOMLEFT",16,7); book.previous:SetHeight(22)
    book.next=ui.Button(book.frame,"Next",90,function() onNeighbor(1) end)
    book.next:SetPoint("BOTTOMLEFT",268,7); book.next:SetHeight(22)
    function book:SetMob(mob,group,album)
        self.title:SetText(mob.name)
        self.subtitle:SetText(ML.ClassificationLabel(mob).." · "..ML.ReactionLabel(mob))
        local entry=group or mob
        local rank=ML.KillRank(entry.count)
        self.rank:SetText(mob.catalogOnly and "Undiscovered · Known catalog information" or
            ((rank and rank.label.." collector" or "Collection record").." · "..entry.count.." recorded kills"))
        self.previous:SetEnabled(album and album.inspectedIndex~=nil and album.inspectedIndex>1)
        self.next:SetEnabled(album and album.inspectedIndex~=nil and album.inspectedIndex<(album.total or 0))
    end
    book.frame:Hide()
    return book
end
