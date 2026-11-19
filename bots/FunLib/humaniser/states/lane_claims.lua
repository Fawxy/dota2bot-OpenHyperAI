--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local offersOf, coreTakes, offerCache
local Etiquette = require(GetScriptDirectory().."/FunLib/humaniser/etiquette")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local PickTable = require(GetScriptDirectory().."/FunLib/humaniser/states/pick_table")
local SupportDeny = require(GetScriptDirectory().."/FunLib/humaniser/states/support_deny")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
function offersOf(core, within)
    local pid = core:GetPlayerID()
    local now = DotaTime()
    local c = offerCache[pid]
    if c ~= nil and c.t == now then
        return c.offers
    end
    local ____opt_0 = Tasks.Verbs()
    local offers = ____opt_0 and ____opt_0.laneTargets(core, {within = within}) or ({})
    offerCache[pid] = {t = now, offers = offers}
    return offers
end
function coreTakes(core, t, within)
    local creep = t.creep
    local busyOn = LanePick.Attempting(core:GetPlayerID())
    if busyOn == nil then
        return Etiquette.CanTake(core, creep)
    end
    local offers = offersOf(core, within)
    local other
    local mine
    for ____, o in ipairs(offers) do
        if o.creep == busyOn then
            other = o
        end
        if o.creep == t.creep then
            mine = o
        end
    end
    if other == nil then
        return Etiquette.CanTake(core, creep)
    end
    local next = LanePick.Choose(
        offers,
        other,
        ____exports.CoreMine(core),
        nil,
        nil,
        nil,
        PickTable.Order(LaneConfig.PositionOf(core))
    ) or other
    if next.creep == t.creep then
        return true
    end
    if mine == nil then
        return false
    end
    local ____next_due_4 = next.due
    local ____this_3
    ____this_3 = core
    local ____opt_2 = ____this_3.GetSecondsPerAttack
    local free = ____next_due_4 + (____opt_2 and ____opt_2(____this_3) or 1)
    return math.max(free + mine.walk, mine.eta) < t.dies
end
--- The allied support (pos 4-5) whose laning body is in an attempt on deny `t` (LanePick.Attempting, as coreTakes reads the
-- core's), within Etiquette's approach range of the creep (a body that left lane mid-attempt keeps its last phase), or
-- undefined. Only denies: a core's last hits are never yielded. With Ours.CoreDenyYield off, always undefined.
function ____exports.DenyYield(core, t)
    if t.kind ~= "deny" or not Ours.On("CoreDenyYield") then
        return nil
    end
    local own = LaneConfig.PositionOf(core)
    if own ~= nil and not PickTable.IsCore(own) then
        return nil
    end
    if PickTable.ClaimOf("deny", own or 1) ~= "unattempted" then
        return nil
    end
    local creep = t.creep
    do
        local i = 1
        while i <= 5 do
            do
                local __continue17
                repeat
                    local member = GetTeamMember(i)
                    if member == nil or member == nil or member == core then
                        __continue17 = true
                        break
                    end
                    if not member:IsAlive() or member:IsIllusion() then
                        __continue17 = true
                        break
                    end
                    local pos = LaneConfig.PositionOf(member)
                    if pos == nil or PickTable.IsCore(pos) then
                        __continue17 = true
                        break
                    end
                    if LanePick.Attempting(member:GetPlayerID()) ~= t.creep then
                        __continue17 = true
                        break
                    end
                    if GetUnitToUnitDistance(member, creep) > Etiquette.SETTINGS.ApproachRange then
                        __continue17 = true
                        break
                    end
                    return member:GetPlayerID()
                until true
                if not __continue17 then
                    break
                end
            end
            i = i + 1
        end
    end
    return nil
end
--- A core's `mine` for LanePick.Choose: every creep but a deny an allied support is attempting (DenyYield); undefined (all) with the switch off.
function ____exports.CoreMine(core)
    if not Ours.On("CoreDenyYield") then
        return nil
    end
    return function(t) return ____exports.DenyYield(core, t) == nil end
end
--- The claim `bot` (a support) has on `t`, or undefined when an allied core will take it.
function ____exports.SupportClaim(bot, t, within)
    if t.kind == "deny" then
        return "deny"
    end
    local creep = t.creep
    local busy = false
    do
        local i = 1
        while i <= 5 do
            do
                local __continue34
                repeat
                    local member = GetTeamMember(i)
                    if member == nil or member == nil or member == bot then
                        __continue34 = true
                        break
                    end
                    if not member:IsAlive() or member:IsIllusion() then
                        __continue34 = true
                        break
                    end
                    local pos = LaneConfig.PositionOf(member)
                    if not PickTable.IsCore(pos) then
                        __continue34 = true
                        break
                    end
                    if coreTakes(member, t, within) then
                        return nil
                    end
                    if LanePick.Attempting(member:GetPlayerID()) ~= nil and GetUnitToUnitDistance(member, creep) <= Etiquette.SETTINGS.ApproachRange then
                        busy = true
                    end
                    __continue34 = true
                until true
                if not __continue34 then
                    break
                end
            end
            i = i + 1
        end
    end
    return busy and "busy" or "free"
end
offerCache = {}
--- The creeps a laner whose body owns its lane hits may take, from its position's column of the pick table (`pos` is laning
-- ClaimPos): undefined when that is every creep. `unclaimed` is SupportClaim, off (no last hit) with Ours.SupportLastHit off;
-- `unattempted` is DenyYield, all with Ours.CoreDenyYield off.
function ____exports.Mine(bot, pos, within)
    local lastHit = PickTable.ClaimOf("lasthit", pos)
    local deny = PickTable.ClaimOf("deny", pos)
    if lastHit == "all" and (deny == "all" or deny == "unattempted" and not Ours.On("CoreDenyYield")) then
        return nil
    end
    local lastHits = SupportDeny.LastHits(bot)
    return function(t)
        local claim = t.kind == "deny" and deny or lastHit
        if claim == "none" then
            return false
        end
        if claim == "unattempted" then
            return ____exports.DenyYield(bot, t) == nil
        end
        if claim == "unclaimed" then
            return (t.kind == "deny" or lastHits) and ____exports.SupportClaim(bot, t, within) ~= nil
        end
        return true
    end
end
return ____exports
