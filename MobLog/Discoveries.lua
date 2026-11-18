-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local collectionGoals={25,100,250,500,1000,2500,5000,7500,10000,15000,20000,30000,40000,50000}
local creatureGoals={1,3,5,10,20,25,50,75,100,150,250,500,750,1000,1500,2000,2500,3500,5000}
local encounterGoals=ML.IsForever and {1,3,5,10,25,50,100,150,250} or {1,5,10,25,50,100,250,500,1000}
local population=ML.DiscoveryPopulations[ML.IsForever and "forever" or "retail"]
local killGoals={25,100,500,1000,2500,5000,10000,25000,50000,100000,250000,500000,1000000,2500000}
local typeKillGoals={25,100,500,1000,2500,5000,10000,25000,50000,100000}
local series = {
    {key="all", name="The first pages", subject="creatures", goals=collectionGoals, category="collection", icon="INV_Misc_Book_09"},
    {key=1, name="On quiet paws", subject="beasts", en="Beast", de="Wildtier", icon="Ability_Hunter_Pet_Wolf"},
    {key=7, name="Familiar faces", subject="humanoids", en="Humanoid", de="Humanoid", icon="INV_Helmet_31"},
    {key=6, name="Beyond the veil", subject="undead", en="Undead", de="Untoter", icon="Spell_Shadow_RaiseDead"},
    {key=3, name="Between worlds", subject="demons", en="Demon", de="Dämon", icon="Spell_Shadow_SummonFelHunter"},
    {key=2, name="A dragon's gaze", subject="dragonkin", en="Dragonkin", de="Drachkin", icon="INV_Misc_Head_Dragon_01"},
    {key=4, name="Primal encounters", subject="elementals", en="Elemental", de="Elementar", icon="Spell_Fire_Elemental_Totem"},
    {key=5, name="In towering shadows", subject="giants", en="Giant", de="Riese", icon="INV_Misc_Foot_Centaur"},
    {key=9, name="Gears and sparks", subject="mechanicals", en="Mechanical", de="Mechanisch", icon="INV_Misc_Gear_01"},
    {key=15, name="Beyond comprehension", subject="aberrations", en="Aberration", de="Entartung", icon="Spell_Shadow_Twilight"},
    {key=8, name="The little things", subject="critters", en="Critter", de="Tier", icon="Ability_Hunter_Pet_Rabbit"},
    {key="rare", name="A rare sight", subject="rare creatures", goals=encounterGoals, category="encounters", icon="INV_Misc_Eye_01"},
    {key="elite", name="Among the mighty", subject="elite creatures", goals=creatureGoals, category="encounters", icon="INV_Shield_06"},
    {key="boss", name="Face to face with legends", subject="bosses", goals=encounterGoals, category="encounters", icon="INV_Misc_Head_Dragon_01"},
    {key="friendly", name="Among friends", subject="friendly creatures", goals=ML.IsForever and encounterGoals or creatureGoals, category="encounters", icon="Spell_Holy_PrayerOfHealing"},
    {key="neutral", name="A cautious introduction", subject="neutral creatures", goals=ML.IsForever and encounterGoals or creatureGoals, category="encounters", icon="Ability_Hunter_BeastCall"},
    {key="hostile", name="Dangerous company", subject="hostile creatures", goals=collectionGoals, category="encounters", icon="Ability_Warrior_Challenge"},
    {key="defeated", name="A varied hunt", subject="creatures", goals=collectionGoals, category="combat", verb="Record kills of", icon="Ability_Hunter_SniperShot"},
    {key="kills", name="Veteran of the hunt", goals=killGoals, category="combat", kills=true, icon="Ability_Warrior_SavageBlow"},
}
ML.DiscoveryBadges = {}
local definitions, activeKeys = {}, {}
local function AddBadge(family,goal,tier,legacy)
    local badge={
        key=tostring(family.key)..":"..goal, family=family.key, goal=goal,
        name=family.name, tier=tier, icon="Interface\\Icons\\"..family.icon,
        category=family.category or "types", legacy=legacy,
        description=family.kills and string.format("Record %d kills%s",goal,family.subject and (" of "..family.subject) or "")
            or string.format("%s %d different %s",family.verb or "Discover",goal,family.subject),
    }
    ML.DiscoveryBadges[#ML.DiscoveryBadges+1]=badge
    activeKeys[badge.key]=true
end
local function AddSeries(family)
    definitions[tostring(family.key)]=family
    -- Catalog populations bound distinct-NPC goals, never repeated kills.
    -- The 20 percent margin is a balancing choice, not proof of accessibility.
    local limit=math.floor((population[family.key] or population.all)*0.8)
    for tier,goal in ipairs(family.goals or creatureGoals) do
        if family.kills or goal<=limit then AddBadge(family,goal,tier) end
    end
end
for _, family in ipairs(series) do AddSeries(family) end
for _, family in ipairs(series) do
    if family.en then
        AddSeries({key="kills:"..family.key,name="Hunt: "..family.subject,subject=family.subject,
            goals=typeKillGoals,category="combat",kills=true,icon=family.icon})
    end
end

-- Resolve localized client labels; never infer an encounter from the catalog.
local typeCache = {}
function ML.DiscoveryCreatureType(label)
    if type(label) ~= "string" then return end
    if typeCache[label]~=nil then return typeCache[label] or nil end
    for _, family in ipairs(series) do
        if family.en then
            if label == family.en or label == family.de then typeCache[label]=family.key; return family.key end
            if C_CreatureInfo and C_CreatureInfo.GetCreatureTypeInfo then
                local ok, info = pcall(C_CreatureInfo.GetCreatureTypeInfo, family.key)
                info = ok and ML.Public(info)
                if type(info)=="table" and label==ML.Public(info.name) then typeCache[label]=family.key; return family.key end
            end
        end
    end
    typeCache[label]=false
end

local counts, indexed, historical
local function Personal(mob)
    return mob and not mob.provisional and ((mob.count or 0)>0 or (mob.sightings or 0)>0 or mob.lastSeen~=nil)
end
local function Metrics(mob)
    local result={all=1,kills=mob.count or 0}
    if result.kills>0 then result.defeated=1 end
    local kind=ML.DiscoveryCreatureType(mob.creatureType or mob.tooltipType)
    if kind then result[kind]=1; result["kills:"..kind]=result.kills end
    if mob.classification=="rare" or mob.classification=="rareelite" then result.rare=1 end
    if mob.classification=="elite" or mob.classification=="rareelite" then result.elite=1 end
    if mob.boss or mob.classification=="worldboss" then result.boss=1 end
    -- Manual attitude overrides must not manufacture encounter achievements.
    local reaction=mob.observedReaction or (not mob.reactionOverride and mob.reaction)
    if reaction=="friendly" or reaction=="neutral" or reaction=="hostile" then result[reaction]=1 end
    return result
end
local function Award(mob, inherited, liveKill)
    for _, badge in ipairs(ML.DiscoveryBadges) do
        if (counts[badge.family] or 0)>=badge.goal and not ML.db.discoveryAchievements[badge.key] then
            local isKill=badge.family=="kills" or badge.family=="defeated"
                or (type(badge.family)=="string" and badge.family:match("^kills:"))
            local historicalAward=inherited and not (liveKill and isKill)
            local earned = {historical=historicalAward or nil}
            if not historicalAward then
                earned.date=time(); earned.npc=mob.id
                earned.character=ML.UpdateCharacter and ML.UpdateCharacter() or nil
            end
            ML.db.discoveryAchievements[badge.key]=earned
            if not historicalAward and ML.db.options.discoveryNotifications~=false and ML.ShowDiscoveryUnlock then
                ML.ShowDiscoveryUnlock(badge)
            end
        end
    end
end

function ML.InitializeDiscoveries()
    counts, indexed, historical = {all=0}, {}, {}
    ML.db.discoveryAchievements=ML.db.discoveryAchievements or {}
    for id, mob in pairs(ML.db.mobs) do
        historical[id]=true
        if Personal(mob) then
            local metrics=Metrics(mob)
            indexed[id]=metrics
            for key,value in pairs(metrics) do counts[key]=(counts[key] or 0)+value end
        end
    end
    -- Preserve earned goals removed by the new client-specific balancing.
    for key,earned in pairs(ML.db.discoveryAchievements) do
        if type(key)=="string" and type(earned)=="table" and not activeKeys[key] then
            local familyKey,goal=key:match("^(.-):(%d+)$")
            local family=familyKey and definitions[familyKey]
            goal=tonumber(goal)
            if family and goal and goal>0 then AddBadge(family,goal,0,true) end
        end
    end
    Award(nil, true)
end

-- Update only one NPC's contribution, even when the window is closed.
function ML.DiscoveryChanged(mob, liveKill)
    if not counts or not mob or ML.db.mobs[mob.id]~=mob or not Personal(mob) then return end
    local previous, current=indexed[mob.id] or {}, Metrics(mob)
    local changed=false
    for key,value in pairs(previous) do
        if value~=(current[key] or 0) then changed=true end
        counts[key]=(counts[key] or 0)-value
    end
    for key,value in pairs(current) do
        if value~=(previous[key] or 0) then changed=true end
        counts[key]=(counts[key] or 0)+value
    end
    indexed[mob.id]=current
    if not changed then return end
    Award(mob, historical[mob.id]==true, liveKill==true)
    if ML.RefreshDiscoveries then ML.RefreshDiscoveries() end
end

function ML.DiscoveryProgress(badge)
    if not counts then ML.InitializeDiscoveries() end
    return counts[badge.family] or 0, ML.db.discoveryAchievements[badge.key]
end

local page, scroll, cards, heading, nextGoals, content, pageLabel, previousButton, nextButton, statusButton, categoryButton
local pageNumber, statusFilter, categoryFilter=1,"all","all"
local pageSize=50
local gold={1,0.82,0.38}
local ink={0.22,0.12,0.055}
local softInk={0.36,0.24,0.13}
local function AchievementPanel(frame)
    -- QuestBG is a texture sheet. Stretch only its opaque upper-left parchment
    -- interior, not the unused right/bottom portions of the full sheet.
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize=16,insets={left=5,right=5,top=5,bottom=5}})
    frame:SetBackdropColor(0.20,0.18,0.15,1)
    frame:SetBackdropBorderColor(0.64,0.49,0.25,1)
    frame.paper=frame:CreateTexture(nil,"BACKGROUND",nil,1)
    if C_Texture and C_Texture.GetAtlasInfo("QuestBG-Parchment") then
        frame.paper:SetAtlas("QuestBG-Parchment")
    else
        frame.paper:SetTexture("Interface\\QuestFrame\\QuestBG")
        frame.paper:SetTexCoord(0.05,0.45,0.05,0.45)
    end
    frame.paper:SetPoint("TOPLEFT",5,-5); frame.paper:SetPoint("BOTTOMRIGHT",-5,5)
    frame.paper:SetVertexColor(0.97,0.93,0.84)
end
local filterMenus={}
local function CloseFilterMenus()
    for _,menu in ipairs(filterMenus) do menu:Hide() end
end
local categories={{key="all",label="All categories"},{key="collection",label="Collection"},{key="types",label="Creature types"},{key="encounters",label="Encounters"},{key="combat",label="Combat"}}
local statuses={{key="all",label="All seals"},{key="pending",label="In progress"},{key="earned",label="Earned"}}
local function ChoiceLabel(choices,key)
    for _,choice in ipairs(choices) do if choice.key==key then return choice.label end end
end
function ML.SetDiscoveryFilters(status,category)
    CloseFilterMenus()
    statusFilter=ChoiceLabel(statuses,status) and status or "all"
    categoryFilter=ChoiceLabel(categories,category) and category or "all"
    pageNumber=1
    if scroll then scroll:SetVerticalScroll(0) end
    ML.RefreshDiscoveries()
end
function ML.TurnDiscoveryPage(delta)
    pageNumber=math.max(1,pageNumber+delta)
    if scroll then scroll:SetVerticalScroll(0) end
    ML.RefreshDiscoveries()
end
function ML.RefreshDiscoveries()
    if not page or not page:IsShown() then return end
    local earnedCount, upcoming, visible, nextByFamily=0, {}, {}, {}
    for _,badge in ipairs(ML.DiscoveryBadges) do
        local count,earned=ML.DiscoveryProgress(badge)
        if earned then earnedCount=earnedCount+1
        elseif not nextByFamily[badge.family] then
            upcoming[#upcoming+1]={badge=badge,count=count}; nextByFamily[badge.family]=true
        end
        if (categoryFilter=="all" or categoryFilter==badge.category)
            and (statusFilter=="all" or (statusFilter=="earned")==not not earned) then
            visible[#visible+1]=badge
        end
    end
    local pages=math.max(1,math.ceil(#visible/pageSize))
    pageNumber=math.min(pageNumber,pages)
    pageLabel:SetText(string.format("%d / %d · %d seals",pageNumber,pages,#visible))
    previousButton:SetEnabled(pageNumber>1); nextButton:SetEnabled(pageNumber<pages)
    statusButton:SetText(ChoiceLabel(statuses,statusFilter).."  v")
    categoryButton:SetText(ChoiceLabel(categories,categoryFilter).."  v")
    local shown=math.min(pageSize,math.max(0,#visible-(pageNumber-1)*pageSize))
    content:SetHeight(math.max(1,math.ceil(shown/2)*136))
    for i,card in ipairs(cards) do
        local badge=visible[(pageNumber-1)*pageSize+i]
        card:SetShown(badge~=nil)
        card.highlight:Hide()
        card.earned=nil
        if badge then
            local count,earned=ML.DiscoveryProgress(badge)
            card.title:SetText(badge.name.." · "..(badge.legacy and "Earlier goal" or badge.tier))
            card.description:SetText(badge.description)
            card.icon:SetTexture(badge.icon)
            card.progress:SetValue(math.min(count,badge.goal)/badge.goal)
            card.count:SetText(string.format("%d / %d",math.min(count,badge.goal),badge.goal))
            card.icon:SetDesaturated(not earned)
            card.icon:SetAlpha(earned and 1 or 0.65)
            card:SetBackdropColor(unpack(earned and {0.15,0.12,0.075,1} or {0.075,0.07,0.06,1}))
            card.paper:SetVertexColor(unpack(earned and {0.97,0.93,0.84} or {0.85,0.80,0.71}))
            card:SetBackdropBorderColor(unpack(earned and {0.60,0.39,0.16} or {0.48,0.34,0.18}))
            card.progress:SetStatusBarColor(unpack(earned and {0.18,0.40,0.14} or {0.62,0.43,0.13}))
            card.complete:SetShown(earned~=nil)
            card.earned=earned
            if earned then
                local text=earned.historical and "From previous records" or ("Earned "..date("%Y-%m-%d",earned.date))
                local mob=earned.npc and ML.db.mobs[earned.npc]
                if mob then text=text.." · "..mob.name end
                card.status:SetText(text)
            else card.status:SetText("In progress") end
        end
    end
    table.sort(upcoming,function(a,b)
        local af,bf=a.count/a.badge.goal,b.count/b.badge.goal
        if af~=bf then return af>bf end
        return a.badge.key<b.badge.key
    end)
    local lines={}
    for i=1,math.min(3,#upcoming) do
        local entry=upcoming[i]
        lines[#lines+1]=entry.badge.name.." ("..entry.count.."/"..entry.badge.goal..")"
    end
    heading:SetText(string.format("Your discoveries · %d / %d seals earned",earnedCount,#ML.DiscoveryBadges))
    nextGoals:SetText(#lines>0 and ("Next goals: "..table.concat(lines," · ")) or "Every seal earned. Your journal keeps growing!")
end

function ML.BuildDiscoveries(parent,ui)
    page=CreateFrame("Frame",nil,parent); page:SetAllPoints()
    local banner=ui.Panel(page); banner:SetPoint("TOPLEFT",26,-124); banner:SetSize(846,70)
    AchievementPanel(banner)
    local emblem=banner:CreateTexture(nil,"ARTWORK"); emblem:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
    emblem:SetSize(38,38); emblem:SetPoint("TOPLEFT",12,-14)
    local emblemBorder=banner:CreateTexture(nil,"OVERLAY"); emblemBorder:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    emblemBorder:SetSize(66,66); emblemBorder:SetPoint("CENTER",emblem,"CENTER")
    heading=ui.Text(banner,18,ink); heading:SetPoint("TOPLEFT",62,-9); heading:SetSize(760,24)
    heading:SetFont(DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT,18,"")
    nextGoals=ui.Text(banner,11,softInk); nextGoals:SetPoint("TOPLEFT",62,-34); nextGoals:SetSize(760,30)
    heading:SetShadowColor(0,0,0,0); nextGoals:SetShadowColor(0,0,0,0)
    local notifications=CreateFrame("CheckButton",nil,page,"UICheckButtonTemplate")
    notifications:SetPoint("TOPLEFT",26,-197); notifications:SetSize(24,24)
    local caption=ui.Text(page,12); caption:SetPoint("LEFT",notifications,"RIGHT",4,0); caption:SetText("Show discovery notifications")
    notifications:SetScript("OnClick",function(self) ML.db.options.discoveryNotifications=self:GetChecked()==true end)
    local function Dropdown(label,width,x,choices,select)
        local menu
        local button=ui.Button(page,label,width,function()
            local show=not menu:IsShown()
            CloseFilterMenus(); menu:SetShown(show)
        end)
        button:SetPoint("TOPLEFT",x,-195)
        button:GetFontString():SetTextColor(unpack(gold))
        menu=ui.Panel(page); menu:SetSize(width,#choices*26+14)
        menu:SetPoint("TOPLEFT",button,"BOTTOMLEFT",0,-2)
        menu:SetFrameLevel(page:GetFrameLevel()+90)
        for i,choice in ipairs(choices) do
            local key=choice.key
            local option=ui.Button(menu,choice.label,width-18,function() select(key) end)
            option:SetPoint("TOPLEFT",9,-7-(i-1)*26); option:SetHeight(25)
        end
        filterMenus[#filterMenus+1]=menu; menu:Hide()
        return button
    end
    statusButton=Dropdown("All seals",132,348,statuses,function(key) ML.SetDiscoveryFilters(key,categoryFilter) end)
    categoryButton=Dropdown("All categories",178,490,categories,function(key) ML.SetDiscoveryFilters(statusFilter,key) end)
    previousButton=ui.Button(page,"<",30,function() ML.TurnDiscoveryPage(-1) end); previousButton:SetPoint("TOPLEFT",678,-195)
    nextButton=ui.Button(page,">",30,function() ML.TurnDiscoveryPage(1) end); nextButton:SetPoint("TOPLEFT",714,-195)
    for direction,button in pairs({Prev=previousButton,Next=nextButton}) do
        button:SetText(""); button:SetSize(30,30)
        button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-"..direction.."Page-Up")
        button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-"..direction.."Page-Down")
        button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-"..direction.."Page-Disabled")
        button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight","ADD")
    end
    pageLabel=ui.Text(page,11,{0.80,0.72,0.54}); pageLabel:SetPoint("TOPLEFT",752,-195); pageLabel:SetSize(116,28)
    local panel=ui.Panel(page); panel:SetPoint("TOPLEFT",26,-228); panel:SetSize(846,340)
    scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT",10,-10); scroll:SetSize(808,318)
    content=CreateFrame("Frame",nil,scroll); content:SetSize(804,math.ceil(pageSize/2)*136)
    scroll:SetScrollChild(content); cards={}
    for i=1,pageSize do
        local card=ui.Panel(content); card:SetSize(396,128)
        AchievementPanel(card)
        card:SetPoint("TOPLEFT",((i-1)%2)*402,-math.floor((i-1)/2)*136)
        card.iconFrame=CreateFrame("Frame",nil,card); card.iconFrame:SetSize(64,64); card.iconFrame:SetPoint("TOPLEFT",8,-7)
        local rim=card.iconFrame:CreateTexture(nil,"BACKGROUND")
        rim:SetSize(48,48); rim:SetPoint("CENTER"); rim:SetColorTexture(0.57,0.46,0.28,1)
        local inset=card.iconFrame:CreateTexture(nil,"BORDER")
        inset:SetSize(46,46); inset:SetPoint("CENTER"); inset:SetColorTexture(0.09,0.07,0.04,1)
        card.icon=card.iconFrame:CreateTexture(nil,"ARTWORK"); card.icon:SetSize(42,42); card.icon:SetPoint("CENTER")
        card.icon:SetTexCoord(0.07,0.93,0.07,0.93)
        card.title=ui.Text(card,14,ink); card.title:SetPoint("TOPLEFT",78,-13); card.title:SetSize(284,21)
        card.title:SetFont(DAMAGE_TEXT_FONT or STANDARD_TEXT_FONT,14,""); card.title:SetWordWrap(false)
        card.description=ui.Text(card,12,softInk); card.description:SetPoint("TOPLEFT",78,-38); card.description:SetSize(296,30)
        card.complete=card:CreateTexture(nil,"OVERLAY"); card.complete:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
        card.complete:SetPoint("TOPRIGHT",-10,-11); card.complete:SetSize(18,18)
        card.progress=CreateFrame("StatusBar",nil,card); card.progress:SetPoint("TOPLEFT",16,-78); card.progress:SetSize(364,14)
        card.progress:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar"); card.progress:SetMinMaxValues(0,1)
        local bg=card.progress:CreateTexture(nil,"BACKGROUND"); bg:SetAllPoints(); bg:SetColorTexture(0.035,0.03,0.02,1)
        local barBorder=CreateFrame("Frame",nil,card.progress,"BackdropTemplate")
        barBorder:SetPoint("TOPLEFT",-3,3); barBorder:SetPoint("BOTTOMRIGHT",3,-3)
        barBorder:SetBackdrop({edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=10})
        barBorder:SetBackdropBorderColor(0.64,0.50,0.25,1)
        card.count=ui.Text(barBorder,11,{1,0.95,0.80}); card.count:SetPoint("CENTER"); card.count:SetSize(360,16)
        card.count:SetJustifyH("CENTER")
        card.status=ui.Text(card,11,softInk); card.status:SetPoint("TOPLEFT",16,-99); card.status:SetSize(364,19)
        card.status:SetWordWrap(false)
        for _,label in ipairs({card.title,card.description,card.status}) do label:SetShadowColor(0,0,0,0) end
        card.highlight=card:CreateTexture(nil,"OVERLAY"); card.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        card.highlight:SetBlendMode("BLEND"); card.highlight:SetAlpha(0.10)
        card.highlight:SetPoint("TOPLEFT",5,-5); card.highlight:SetPoint("BOTTOMRIGHT",-5,5)
        card.highlight:Hide()
        card:EnableMouse(true)
        card:SetScript("OnMouseUp",function(self,button)
            if button=="LeftButton" and self.earned and self.earned.npc then ML.ShowMob(self.earned.npc) end
        end)
        card:SetScript("OnEnter",function(self)
            self.highlight:Show()
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(self.title:GetText(),1,0.82,0.38)
            GameTooltip:AddLine(self.description:GetText(),0.90,0.86,0.74,true)
            if not self.earned or not self.earned.character then GameTooltip:Show(); return end
            local name=ML.CharacterName and ML.CharacterName(self.earned.character) or self.earned.character
            GameTooltip:AddLine("Earned by "..name)
            GameTooltip:AddLine("Click to open the completing encounter.",1,0.85,0.6); GameTooltip:Show()
        end)
        card:SetScript("OnLeave",function(self) self.highlight:Hide(); GameTooltip:Hide() end)
        cards[i]=card
    end
    ML.BuildFooterNote(page,ui.Text,"Personal records only. Discovery seals count different NPC IDs.\nCombat seals count recorded kills; readable details are required.",
        "Distinct-NPC goals use this client's catalog counts with a 20 percent balancing margin, not a complete availability checklist.\nBoss and attitude populations are incomplete; those series use broader client-scaled goals. Catalog entries alone never count.")
    page:SetScript("OnShow",function()
        notifications:SetChecked(ML.db.options.discoveryNotifications~=false); ML.RefreshDiscoveries()
    end)
    page:SetScript("OnHide",CloseFilterMenus)
    page:Hide(); return page
end
function ML.GetDiscoveriesView()
    return {scroll=scroll:GetVerticalScroll(),page=pageNumber,status=statusFilter,category=categoryFilter}
end
function ML.RestoreDiscoveriesView(view)
    ML.SetDiscoveryFilters(view.status,view.category); pageNumber=view.page or 1
    ML.RefreshDiscoveries(); ML.SetViewScroll(scroll,view.scroll)
end
