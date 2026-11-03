--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Etiquette = require(GetScriptDirectory().."/FunLib/humaniser/etiquette")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
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
-- attack interval after the creep it waits on is due, at the earliest.
local function coreTakes(core, t, within)
    local creep = t.creep
    local busyOn = LanePick.Attempting(core:GetPlayerID())
    if busyOn == nil then
        return Etiquette.CanTake(core, creep)
    end
    if busyOn == t.creep then
        return true
    end
    local other
    local mine
    for ____, o in ipairs(offersOf(core, within)) do
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
    if mine == nil then
        return false
    end
    local ____other_due_4 = other.due
    local ____this_3
    ____this_3 = core
    local ____opt_2 = ____this_3.GetSecondsPerAttack
    local free = ____other_due_4 + (____opt_2 and ____opt_2(____this_3) or 1)
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
                local __continue15
                repeat
                    local member = GetTeamMember(i)
                    if member == nil or member == nil or member == bot then
                        __continue15 = true
                        break
                    end
                    if not member:IsAlive() or member:IsIllusion() then
                        __continue15 = true
                        break
                    end
                    local pos = LaneConfig.PositionOf(member)
                    if pos == nil or pos > 3 then
                        __continue15 = true
                        break
                    end
                    if coreTakes(member, t, within) then
                        return nil
                    end
                    if LanePick.Attempting(member:GetPlayerID()) ~= nil and GetUnitToUnitDistance(member, creep) <= Etiquette.SETTINGS.ApproachRange then
                        busy = true
                    end
                    __continue15 = true
                until true
                if not __continue15 then
                    break
                end
            end
            i = i + 1
        end
    end
    return busy and "busy" or "free"
end
return ____exports
