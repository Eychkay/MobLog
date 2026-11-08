-- SPDX-License-Identifier: GPL-2.0-or-later
-- Forever catalog; retain bundled GPL/MIT notices.
local ML=MobLog
if not ML.IsForever then return end
local D=ML.TrinityData
D.jobs[#D.jobs+1]=function()
D.npcDetails[5719]={["boss"]=true}
D.npcDetails[5720]={["boss"]=true}
D.npcDetails[5721]={["boss"]=true}
D.npcDetails[5722]={["boss"]=true}
D.npcDetails[8440]={["boss"]=true}
D.npcDetails[8443]={["boss"]=true}
D.npcDetails[10812]={["boss"]=true}
D.npcDetails[10813]={["boss"]=true}
end
