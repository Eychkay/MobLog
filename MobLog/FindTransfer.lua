-- SPDX-License-Identifier: GPL-2.0-or-later
-- Copyright (C) 2026 MobLog contributors
local _, ML = ...
local T = {}
ML.FindTransfer = T

local prefix = "MobLogFinds1"
local chunkSize, windowSize = 210, 8
local offerTimeout, idleTimeout = 60, 40
local tickInterval, retryInterval = 0.4, 7
local serial, registered, timer, receipt = 0, false
local nextSend = 0

local function Update()
    if ML.RefreshFindTransfers then ML.RefreshFindTransfers() end
end

local function ForeverAddress(name)
    if type(name)~="string" then return end
    -- Addon messages may include a realm suffix; Forever whispers use the two-part name.
    local character = name:match("^([^%-]+)%-") or name
    local address = character:match("^%s*(.-)%s*$"):gsub("%s+"," ")
    if address:match("^%S+ %S") then return address end
end

local function PlayerKey(name)
    if ML.IsForever then return string.lower(name) end
    local character, realm = name:match("^([^%-]+)%-(.+)$")
    if not character then
        character, realm = name, GetNormalizedRealmName and ML.Public(GetNormalizedRealmName())
    end
    return string.lower(character .. "-" .. (realm or ""):gsub("%s+",""))
end

local function Register()
    if registered then return true end
    if not (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix and C_ChatInfo.SendAddonMessage
        and Enum and Enum.SendAddonMessageResult and Enum.RegisterAddonMessagePrefixResult) then
        return false
    end
    local ok, result = pcall(C_ChatInfo.RegisterAddonMessagePrefix,prefix)
    result = ML.Public(result)
    local codes = Enum.RegisterAddonMessagePrefixResult
    registered = ok and result~=nil and (result==codes.Success or result==codes.DuplicatePrefix)
    return registered
end

local function Send(peer, packet)
    if not Register() then return nil, "Addon messaging is unavailable in this client." end
    if InCombatLockdown() then return nil, "Try sharing after combat." end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage,prefix,packet,"WHISPER",peer)
    result = ML.Public(result)
    local codes = Enum.SendAddonMessageResult
    if ok and result==codes.Success then return true end
    if result~=nil and (result==codes.AddonMessageThrottle or result==codes.ChannelThrottle) then
        return false, "WoW is limiting addon messages. Try again in a moment."
    end
    if codes.TargetOffline and result==codes.TargetOffline then
        return nil, "The player is offline or unreachable."
    end
    return nil, "WoW rejected the addon message (" .. (ok and tostring(result) or "API error") .. ")."
end

local function NewID()
    serial=serial+1
    return string.format("%x%x%x",time(),math.floor(GetTime()*1000)%268435456,serial)
end

local function Active(state)
    return state and (state.phase=="offer" or state.phase=="sending" or state.phase=="receiving")
end
T.Active = Active

local function End(state, phase, detail)
    state.phase, state.detail = phase, detail
    state.code, state.chunks, state.ackQueued = nil,nil,nil
    Update()
end

local function Schedule()
    if timer then return end
    if not (Active(T.outgoing) or Active(T.incoming) or (T.incoming and T.incoming.ackQueued)
        or (receipt and receipt.ackQueued)) then return end
    timer=true
    C_Timer.After(tickInterval,function()
        timer=nil
        local now=GetTime()
        local outgoing, incoming = T.outgoing, T.incoming
        if receipt and receipt.untilAt<=now then receipt=nil end
        for _, state in pairs({outgoing=outgoing,incoming=incoming}) do
            if Active(state) and state.untilAt<=now then
                local detail=state.phase=="offer" and "No reply to the offer." or "No transfer progress. Try sending again."
                End(state,"expired",detail)
            end
        end
        if now<nextSend or InCombatLockdown() then Schedule(); return end
        local ack = incoming and incoming.ackQueued and incoming or receipt and receipt.ackQueued and receipt
        if ack then
            local ok=Send(ack.peer,"A:"..ack.id..":"..ack.received)
            ack.ackQueued=ok==false or nil
            nextSend=now+(ok==false and 1.2 or tickInterval)
        elseif incoming and incoming.phase=="receiving" and incoming.received==0 and now>=incoming.readyRetryAt then
            Send(incoming.peer,"R:"..incoming.id)
            incoming.readyRetryAt=now+retryInterval
            nextSend=now+tickInterval
        elseif outgoing and outgoing.phase=="sending" then
            if now>=outgoing.retryAt then
                outgoing.nextChunk=outgoing.acked+1
                outgoing.retryAt=now+retryInterval
            end
            local index=outgoing.nextChunk
            if index<=outgoing.total and index<=outgoing.acked+windowSize then
                local offset=(index-1)*chunkSize
                local data=outgoing.code:sub(offset+1,offset+chunkSize)
                local ok,detail=Send(outgoing.peer,"D:"..outgoing.id..":"..index..":"..data)
                if ok then
                    outgoing.nextChunk=index+1
                    outgoing.sent=math.max(outgoing.sent,index)
                    outgoing.retryAt=now+retryInterval
                elseif ok==nil then End(outgoing,"failed",detail) end
                nextSend=now+(ok==false and 1.2 or tickInterval)
            end
        end
        Schedule()
    end)
end

function T.Offer(player, code, count)
    if Active(T.outgoing) then return nil, "An outgoing transfer is already active." end
    if type(player)~="string" then return nil, "Enter a character name." end
    player=player:match("^%s*(.-)%s*$")
    if player=="" or #player>96 or player:find("[%c|:]") then return nil, "Enter a valid character name." end
    if ML.IsForever then
        player=ForeverAddress(player)
        if not player then return nil, "Enter the player's first and last name." end
    elseif player:find("%s") then
        return nil, "Enter a character name or Name-Realm."
    end
    if #code<1 or #code>ML.Share.maxBytes or count<1 or count>ML.Share.maxRows then
        return nil, "This package is too large. Narrow the selection."
    end
    local state={peer=player, key=PlayerKey(player), id=NewID(), phase="offer", code=code,
        count=count, total=math.ceil(#code/chunkSize), untilAt=GetTime()+offerTimeout}
    local previous=T.outgoing
    T.outgoing=state
    local ok,detail=Send(player,string.format("O:%s:%s:%d:%d",state.id,ML.Share.client,count,#code))
    if not ok then T.outgoing=previous; return nil,detail end
    Schedule()
    Update()
    return true
end

function T.Accept()
    local state=T.incoming
    if not state or state.phase~="offer" then return end
    state.phase,state.detail,state.chunks,state.received="receiving",nil,{},0
    state.readyRetryAt=GetTime()+retryInterval
    local ok,detail=Send(state.peer,"R:"..state.id)
    if not ok then
        state.phase,state.detail,state.chunks="offer",detail,nil
        Update()
        return
    end
    state.untilAt=GetTime()+idleTimeout
    Schedule()
    Update()
end

function T.Cancel(direction)
    local state=T[direction]
    if not state then return end
    if Active(state) then
        local kind=direction=="outgoing" and "X" or "C"
        Send(state.peer,kind..":"..state.id)
    elseif direction=="incoming" and state.phase=="ready" then
        receipt={peer=state.peer,key=state.key,id=state.id,received=state.total,ackQueued=state.ackQueued,
            untilAt=GetTime()+idleTimeout}
    end
    T[direction]=nil
    Schedule()
    Update()
end

local function ReceiveData(state, body)
    local sequence, data = body:match("^(%d+):(.+)$")
    sequence=tonumber(sequence)
    if not sequence or sequence<1 or sequence>state.total then return end
    local length=math.min(chunkSize,state.bytes-(sequence-1)*chunkSize)
    if #data~=length then return end
    if sequence==state.received+1 then
        state.chunks[sequence]=data
        state.received=sequence
        state.untilAt=GetTime()+idleTimeout
        if sequence==state.total then
            state.code=table.concat(state.chunks)
            state.chunks,state.phase=nil,"ready"
            ML.Print("Finds received from "..state.peer..". Open Share finds to review them.")
        end
        Update()
    end
    if sequence~=state.received or state.received%windowSize==0 or state.received==state.total then
        state.ackQueued=true
    end
    Schedule()
end

local function Message(packet, sender)
    if type(packet)~="string" or type(sender)~="string" or #packet>254 then return end
    if ML.IsForever then
        sender=ForeverAddress(sender)
        if not sender then return end
    end
    local kind, id, body=packet:match("^(%u):(%x+):?(.*)$")
    if not id or #id>32 then return end
    local key=PlayerKey(sender)
    local incoming, outgoing=T.incoming,T.outgoing
    if kind=="D" and receipt and receipt.untilAt>GetTime() and receipt.id==id and receipt.key==key then
        receipt.ackQueued=true
        Schedule()
        return
    end
    if kind=="O" and not (Active(incoming) or (incoming and incoming.phase=="ready")) then
        local client, count, bytes=body:match("^(%u+):(%d+):(%d+)$")
        count,bytes=tonumber(count),tonumber(bytes)
        if client~=ML.Share.client or not count or count<1 or count>ML.Share.maxRows or not bytes or bytes<1 or bytes>ML.Share.maxBytes then return end
        T.incoming={peer=sender,key=key,id=id,phase="offer",count=count,bytes=bytes,
            total=math.ceil(bytes/chunkSize),untilAt=GetTime()+offerTimeout}
        ML.Print(sender.." offered "..count.." finds. Open Share finds to respond.")
        Schedule()
        Update()
        return
    end
    if outgoing and outgoing.id==id and outgoing.key==key then
        if kind=="R" and outgoing.phase=="offer" and body=="" then
            local now=GetTime()
            outgoing.phase,outgoing.acked,outgoing.sent,outgoing.nextChunk="sending",0,0,1
            outgoing.retryAt,outgoing.untilAt=now+retryInterval,now+idleTimeout
            Schedule()
            Update()
        elseif kind=="C" and Active(outgoing) then
            End(outgoing,"cancelled","The recipient cancelled or declined.")
        elseif kind=="A" and outgoing.phase=="sending" then
            local ack=body:match("^%d+$") and tonumber(body)
            if not ack or ack<=outgoing.acked or ack>outgoing.sent then return end
            outgoing.acked=ack
            outgoing.nextChunk=math.max(outgoing.nextChunk,ack+1)
            outgoing.untilAt=GetTime()+idleTimeout
            if ack==outgoing.total then
                End(outgoing,"sent","Delivered. The recipient can now review the finds.")
            else Update() end
        end
    end
    if not incoming or incoming.id~=id or incoming.key~=key then return end
    if kind=="X" and Active(incoming) then End(incoming,"cancelled","The sender cancelled the transfer.")
    elseif kind=="D" and (incoming.phase=="receiving" or incoming.phase=="ready") then
        ReceiveData(incoming,body)
    end
end

local events=CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent",function(_,event,tag,packet,channel,sender)
    if event=="PLAYER_LOGIN" then Register(); return end
    if ML.Public(tag)==prefix and ML.Public(channel)=="WHISPER" then
        Message(ML.Public(packet),ML.Public(sender))
    end
end)
