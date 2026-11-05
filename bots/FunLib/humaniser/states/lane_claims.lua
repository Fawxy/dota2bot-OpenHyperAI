--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Etiquette = require(GetScriptDirectory().."/FunLib/humaniser/etiquette")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
--- The allied support (pos 4-5) whose laning body is in an attempt on deny `t` (LanePick.Attempting, as coreTakes reads the
-- core's), within Etiquette's approach range of the creep (a body that left lane mid-attempt keeps its last phase), or
-- undefined. Only denies: a core's last hits are never yielded. With Ours.CoreDenyYield off, always undefined.
function ____exports.DenyYield(core, t)
    if t.kind ~= "deny" or not Ours.On("CoreDenyYield") then
        return nil
    end
    local creep = t.creep
    do
        local i = 1
        while i <= 5 do
            do
                local __continue15
                repeat
                    local member = GetTeamMember(i)
                    if member == nil or member == nil or member == core then
                        __continue15 = true
                        break
                    end
                    if not member:IsAlive() or member:IsIllusion() then
                        __continue15 = true
                        break
                    end
                    local pos = LaneConfig.PositionOf(member)
                    if pos == nil or pos < 4 then
                        __continue15 = true
                        break
                    end
                    if LanePick.Attempting(member:GetPlayerID()) ~= t.creep then
                        __continue15 = true
                        break
                    end
                    if GetUnitToUnitDistance(member, creep) > Etiquette.SETTINGS.ApproachRange then
                        __continue15 = true
                        break
                    end
                    return member:GetPlayerID()
                until true
                if not __continue15 then
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
--- The core's own laneTargets, once per frame (the support's scan asks for each creep it is offered).
local offerCache = {}
local function offersOf(core, within)
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
--- Whether `core` will take `t` itself, from the core's facts. `judgement`: the core's next swing is taken as landable one
-- attack interval after the creep it goes for next is due, at the earliest.
local function coreTakes(core, t, within)
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
        ____exports.CoreMine(core)
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
                local __continue26
                repeat
                    local member = GetTeamMember(i)
                    if member == nil or member == nil or member == bot then
                        __continue26 = true
                        break
                    end
                    if not member:IsAlive() or member:IsIllusion() then
                        __continue26 = true
                        break
                    end
                    local pos = LaneConfig.PositionOf(member)
                    if pos == nil or pos > 3 then
                        __continue26 = true
                        break
                    end
                    if coreTakes(member, t, within) then
                        return nil
                    end
                    if LanePick.Attempting(member:GetPlayerID()) ~= nil and GetUnitToUnitDistance(member, creep) <= Etiquette.SETTINGS.ApproachRange then
                        busy = true
                    end
                    __continue26 = true
                until true
                if not __continue26 then
                    break
                end
            end
            i = i + 1
        end
    end
    return busy and "busy" or "free"
end
return ____exports
