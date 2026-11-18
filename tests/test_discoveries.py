"""Discovery seals use personal NPC identities, with truthful historical dates."""
import pathlib
import runpy
import unittest
from lupa.lua51 import LuaRuntime

ROOT = pathlib.Path(__file__).resolve().parents[1]


class DiscoveryTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute('''
            ML={db={mobs={},options={}}}; alerts={}; now=100
            function time() return now end
            function ML.Public(v) return v end
            function ML.UpdateCharacter() return "Explorer-Realm" end
            function ML.ShowDiscoveryUnlock(b) alerts[#alerts+1]=b.key end
            function personal(id, kind)
                local mob={id=id,name="Creature "..id,count=0,sightings=1,creatureType=kind}
                ML.db.mobs[id]=mob; ML.DiscoveryChanged(mob); return mob
            end
        ''')
        self.lua.execute((ROOT / "MobLog/DiscoveryLimits.lua").read_text(encoding="utf-8"), "MobLog", self.lua.globals().ML)
        self.lua.execute((ROOT / "MobLog/Discoveries.lua").read_text(encoding="utf-8"), "MobLog", self.lua.globals().ML)

    def test_historical_backfill_is_silent_and_undated(self):
        self.lua.execute('''
            for id=1,25 do ML.db.mobs[id]={id=id,count=1,tooltipType="Beast"} end
            ML.InitializeDiscoveries()
            local earned=ML.db.discoveryAchievements
            assert(earned["all:25"].historical and earned["1:10"].historical)
            assert(not earned["all:25"].date and not earned["all:25"].npc)
            assert(#alerts==0)
            ML.InitializeDiscoveries(); assert(#alerts==0)
        ''')

    def test_new_discoveries_unlock_once_and_keep_context_after_reload(self):
        self.lua.execute('''
            ML.InitializeDiscoveries()
            local mob=personal(1,"Dragonkin")
            local earned=ML.db.discoveryAchievements["2:1"]
            assert(#alerts==1 and earned.date==100 and earned.npc==1)
            assert(earned.character=="Explorer-Realm" and not earned.historical)
            mob.count=1; ML.DiscoveryChanged(mob, true); assert(#alerts==1)
            now=200; ML.InitializeDiscoveries()
            assert(ML.db.discoveryAchievements["2:1"].date==100 and #alerts==1)
        ''')

    def test_catalog_placeholders_and_repeated_sightings_do_not_inflate_progress(self):
        self.lua.execute('''
            ML.InitializeDiscoveries()
            ML.db.mobs[999]={id=999,count=0,creatureType="Beast"}
            ML.DiscoveryChanged(ML.db.mobs[999])
            ML.DiscoveryChanged({id=1000,count=20,creatureType="Beast"})
            local provisional=personal(998); provisional.provisional=true
            ML.InitializeDiscoveries()
            for id=1,24 do
                local mob=personal(id); ML.DiscoveryChanged(mob)
            end
            assert(not ML.db.discoveryAchievements["all:25"])
            personal(25)
            assert(ML.db.discoveryAchievements["all:25"].npc==25)
        ''')

    def test_late_types_of_old_records_are_historical_and_disabled_alerts_still_save(self):
        self.lua.execute('''
            ML.db.mobs[1]={id=1,count=1}
            ML.InitializeDiscoveries()
            ML.db.mobs[1].tooltipType="Undead"; ML.DiscoveryChanged(ML.db.mobs[1])
            assert(ML.db.discoveryAchievements["6:1"].historical and #alerts==0)
            ML.db.options.discoveryNotifications=false
            personal(2,"Demon")
            assert(ML.db.discoveryAchievements["3:1"].date==100 and #alerts==0)
        ''')

    def test_localized_type_resolution_and_corrections(self):
        self.lua.execute('''
            C_CreatureInfo={GetCreatureTypeInfo=function(id)
                if id==4 then return {name="Localized elemental"} end
            end}
            assert(ML.DiscoveryCreatureType("Localized elemental")==4)
            ML.InitializeDiscoveries()
            local mob=personal(1,"Beast")
            mob.creatureType="Humanoid"; ML.DiscoveryChanged(mob)
            local beasts,humanoids
            for _,badge in ipairs(ML.DiscoveryBadges) do
                if badge.key=="1:1" then beasts=ML.DiscoveryProgress(badge) end
                if badge.key=="7:1" then humanoids=ML.DiscoveryProgress(badge) end
            end
            assert(beasts==0 and humanoids==1)
            assert(ML.db.discoveryAchievements["1:1"])
        ''')

    def test_page_progress_notifications_and_encounter_navigation(self):
        self.lua.execute('''
            objects={}
            local methods={}
            local mt={__index=function(_,key)
                if methods[key] then return methods[key] end
                if key:match("^[A-Z]") then return function() end end
            end}
            function widget()
                local obj=setmetatable({scripts={}},mt)
                objects[#objects+1]=obj; return obj
            end
            function CreateFrame() return widget() end
            function methods:SetScript(key,fn) self.scripts[key]=fn end
            function methods:CreateTexture() return widget() end
            function methods:SetTexture(value) self.texture=value end
            function methods:SetTexCoord(...) self.texCoords={...} end
            function methods:SetText(text) self.text=text end
            function methods:GetText() return self.text end
            function methods:GetFontString()
                self.fontString=self.fontString or widget(); return self.fontString
            end
            function methods:SetValue(value) self.value=value end
            function methods:SetDesaturated(value) self.desaturated=value end
            function methods:SetChecked(value) self.checked=value end
            function methods:GetChecked() return self.checked end
            function methods:IsShown() return self.shown end
            function methods:SetShown(value) self.shown=value end
            function methods:Hide() self.shown=false end
            function methods:Show()
                self.shown=true
                if self.scripts.OnShow then self.scripts.OnShow(self) end
            end
            function methods:GetFrameLevel() return 1 end
            function methods:GetVerticalScroll() return self.scroll or 0 end
            function methods:SetVerticalScroll(value) self.scroll=value end
            function ML.BuildFooterNote() end
            function ML.SetViewScroll(frame,value) frame:SetVerticalScroll(value) end
            function ML.ShowMob(id) opened=id end
            function date() return "2026-11-18" end
            ML.InitializeDiscoveries(); personal(1,"Beast")
            local ui={Text=widget,Panel=widget,Button=function(parent,label,_,fn) local obj=widget(); obj.parent=parent; obj.text=label; obj:SetScript("OnClick",fn); return obj end}
            local page=ML.BuildDiscoveries(widget(),ui); page:Show()
            ML.SetDiscoveryFilters("all","types")
            local seal,check
            for _,obj in ipairs(objects) do
                if obj.earned and obj.earned.npc==1 then seal=obj end
                if obj.scripts.OnClick and rawget(obj,"checked")~=nil then check=obj end
            end
            assert(seal and seal.progress.value==1 and not seal.icon.desaturated)
            assert(seal.paper.texture=="Interface\\\\QuestFrame\\\\QuestBG")
            assert(seal.paper.texCoords[1]==0.05 and seal.paper.texCoords[2]==0.45)
            assert(seal.paper.texCoords[3]==0.05 and seal.paper.texCoords[4]==0.45)
            assert(seal.status.text:find("Creature 1",1,true))
            personal(2,"Beast")
            assert(seal.count.text=="1 / 1", "Completed seals must not display progress above their goal")
            seal.scripts.OnMouseUp(seal,"LeftButton"); assert(opened==1)
            check:SetChecked(false); check.scripts.OnClick(check)
            assert(ML.db.options.discoveryNotifications==false)
            ML.RestoreDiscoveriesView({scroll=137})
            assert(ML.GetDiscoveriesView().scroll==137)
            local count=0
            for _,obj in ipairs(objects) do if rawget(obj,"progress") then count=count+1 end end
            assert(count==50, "The page must reuse fifty cards")
            ML.SetDiscoveryFilters("all","types"); ML.TurnDiscoveryPage(1)
            assert(ML.GetDiscoveriesView().page==2 and ML.GetDiscoveriesView().scroll==0)
            count=0
            for _,obj in ipairs(objects) do if rawget(obj,"progress") and obj.shown then count=count+1 end end
            assert(count==50, "The second page must show fifty creature-type seals")
            local typeCount=0
            for _,badge in ipairs(ML.DiscoveryBadges) do if badge.category=="types" then typeCount=typeCount+1 end end
            ML.TurnDiscoveryPage(999); assert(ML.GetDiscoveriesView().page==math.ceil(typeCount/50))
            count=0
            for _,obj in ipairs(objects) do if rawget(obj,"progress") and obj.shown then count=count+1 end end
            assert(count==((typeCount-1)%50+1), "The final page contains the remaining creature-type seals")
            ML.RestoreDiscoveriesView({page=2,status="all",category="types",scroll=89})
            assert(ML.GetDiscoveriesView().page==2 and ML.GetDiscoveriesView().scroll==89)
            ML.SetDiscoveryFilters("earned","combat")
            count=0
            for _,obj in ipairs(objects) do if rawget(obj,"progress") and obj.shown then count=count+1 end end
            assert(count==0 and ML.GetDiscoveriesView().page==1)
            assert(not seal.earned, "Recycled cards must forget the old completing encounter")
            local status,category,pending,types,combat
            for _,obj in ipairs(objects) do
                if obj.text=="Earned  v" then status=obj end
                if obj.text=="Combat  v" then category=obj end
                if obj.text=="In progress" and obj.scripts.OnClick then pending=obj end
                if obj.text=="Creature types" and obj.scripts.OnClick then types=obj end
                if obj.text=="Combat" and obj.scripts.OnClick then combat=obj end
            end
            assert(status and category and pending and types and combat)
            status.scripts.OnClick(status)
            assert(pending.parent:IsShown() and ML.GetDiscoveriesView().status=="earned")
            category.scripts.OnClick(category)
            assert(not pending.parent:IsShown() and combat.parent:IsShown())
            types.scripts.OnClick(types)
            assert(ML.GetDiscoveriesView().category=="types" and not types.parent:IsShown())
            status.scripts.OnClick(status); pending.scripts.OnClick(pending)
            assert(ML.GetDiscoveriesView().status=="pending" and not pending.parent:IsShown())
            assert(ML.GetDiscoveriesView().page==1 and ML.GetDiscoveriesView().scroll==0)
            category.scripts.OnClick(category); page.scripts.OnHide(page)
            assert(not types.parent:IsShown())

        ''')

    def test_all_runtime_lua_files_compile_with_client_lua51_limits(self):
        compile_lua = self.lua.eval('function(source) local fn,err=loadstring(source); assert(fn,err) end')
        for path in (ROOT / "MobLog").rglob("*.lua"):
            with self.subTest(file=path.name):
                compile_lua(path.read_text(encoding="utf-8-sig"))

    def test_long_series_have_unique_keys_and_keep_existing_awards(self):
        self.lua.execute('''
            local keys={}
            for _,badge in ipairs(ML.DiscoveryBadges) do
                assert(not keys[badge.key]); keys[badge.key]=true
                assert(badge.description and badge.category and badge.tier>0)
            end
            assert(#ML.DiscoveryBadges>300)
            assert(keys["all:50000"] and keys["kills:2500000"] and keys["defeated:50000"])
            for _,id in ipairs({1,2,3,4,5,6,7,8,9,15}) do assert(keys["kills:"..id..":100000"]) end
            assert(keys["5:750"] and not keys["5:1000"] and not keys["5:5000"])
            assert(keys["6:5000"] and keys["2:3500"] and not keys["2:5000"])
            assert(ML.DiscoveryCreatureType("Aberration")==15)
            for _,id in ipairs({1,7,6,3,2,4}) do
                for _,goal in ipairs({1,10,50,100}) do assert(keys[id..":"..goal]) end
            end
            ML.db.discoveryAchievements={["all:500"]={date=42,npc=9}}
            ML.InitializeDiscoveries()
            assert(ML.db.discoveryAchievements["all:500"].date==42)
        ''')

    def test_fifty_thousandth_personal_npc_unlocks_final_collection_seal(self):
        self.lua.execute('''
            for id=1,49999 do ML.db.mobs[id]={id=id,count=0,sightings=1} end
            ML.InitializeDiscoveries()
            assert(ML.db.discoveryAchievements["all:40000"].historical)
            assert(not ML.db.discoveryAchievements["all:50000"] and #alerts==0)
            local mob=personal(50000)
            assert(ML.db.discoveryAchievements["all:50000"].npc==50000 and #alerts==1)
            ML.DiscoveryChanged(mob); assert(#alerts==1)
        ''')

    def test_kills_of_existing_npcs_earn_dated_awards_and_never_double_count(self):
        self.lua.execute('''
            local mob={id=1,count=24,creatureType="Beast"}; ML.db.mobs[1]=mob
            ML.InitializeDiscoveries()
            mob.count=25; ML.DiscoveryChanged(mob,true)
            assert(ML.db.discoveryAchievements["kills:25"].date==100)
            assert(ML.db.discoveryAchievements["kills:1:25"].date==100)
            assert(#alerts==2)
            ML.DiscoveryChanged(mob,true); assert(#alerts==2)
            local total
            for _,badge in ipairs(ML.DiscoveryBadges) do
                if badge.key=="kills:25" then total=ML.DiscoveryProgress(badge) end
            end
            assert(total==25)
            mob.creatureType="Humanoid"; ML.DiscoveryChanged(mob)
            assert(ML.db.discoveryAchievements["kills:7:25"].historical)
            assert(#alerts==2)
        ''')

    def test_classifications_and_attitude_use_personal_observations(self):
        self.lua.execute('''
            ML.InitializeDiscoveries()
            local mob=personal(1)
            mob.classification="rareelite"; mob.boss=true
            mob.observedReaction="neutral"; mob.reaction="friendly"; mob.reactionOverride="friendly"
            ML.DiscoveryChanged(mob)
            for _,key in ipairs({"rare:1","elite:1","boss:1","neutral:1"}) do
                assert(ML.db.discoveryAchievements[key].npc==1)
            end
            assert(not ML.db.discoveryAchievements["friendly:1"])
            mob.observedReaction="hostile"; ML.DiscoveryChanged(mob)
            for _,badge in ipairs(ML.DiscoveryBadges) do
                if badge.key=="neutral:1" then assert(ML.DiscoveryProgress(badge)==0) end
            end
            assert(ML.db.discoveryAchievements["neutral:1"])
        ''')

    def test_client_detection_uses_separate_database_limits(self):
        expected = {
            120100: {"all": 50000, 6: 5000, 5: 750, 2: 3500, 8: 2500},
            16001: {"all": 2500, 6: 150, 5: 20, 2: 50, 8: 3},
        }
        for interface, maxima in expected.items():
            with self.subTest(interface=interface):
                lua = LuaRuntime()
                lua.execute(f'ML={{}}; function GetBuildInfo() return nil,nil,nil,{interface} end')
                for name in ("Client.lua", "DiscoveryLimits.lua", "Discoveries.lua"):
                    lua.execute((ROOT / "MobLog" / name).read_text(encoding="utf-8"), "MobLog", lua.globals().ML)
                goals = {}
                for _, badge in lua.globals().ML.DiscoveryBadges.items():
                    goals[badge.family] = max(goals.get(badge.family, 0), badge.goal)
                    if badge.family != "kills" and not str(badge.family).startswith("kills:"):
                        client = "forever" if interface == 16001 else "retail"
                        population = lua.globals().ML.DiscoveryPopulations[client]
                        bound = population[badge.family] or population["all"]
                        self.assertLessEqual(badge.goal, int(bound * 0.8))
                for family, maximum in maxima.items():
                    self.assertEqual(goals[family], maximum)
                self.assertEqual(goals["kills"], 2500000)
                self.assertEqual(goals["kills:6"], 100000)

    def test_saved_retired_goals_remain_visible_without_new_unlocks(self):
        self.lua.globals().ML.IsForever = True
        self.lua.execute((ROOT / "MobLog/Discoveries.lua").read_text(encoding="utf-8"), "MobLog", self.lua.globals().ML)
        self.lua.execute('''
            ML.db.discoveryAchievements={["5:100"]={date=42,npc=9}}
            ML.InitializeDiscoveries()
            local count=0
            for _,badge in ipairs(ML.DiscoveryBadges) do
                if badge.key=="5:100" then assert(badge.legacy); count=count+1 end
                assert(badge.key~="5:5000", "Unachieved goals above the new cap must disappear")
            end
            assert(count==1 and #alerts==0)
            local size=#ML.DiscoveryBadges; ML.InitializeDiscoveries()
            assert(#ML.DiscoveryBadges==size and ML.db.discoveryAchievements["5:100"].date==42)
        ''')

    def test_database_population_snapshot_matches_catalogs(self):
        populations = runpy.run_path(str(ROOT / "tools/trinity/build_discovery_limits.py"))["populations"]()
        for client, counts in populations.items():
            for family, count in counts.items():
                self.assertEqual(self.lua.globals().ML.DiscoveryPopulations[client][family], count)


if __name__ == "__main__":
    unittest.main()
