--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
____exports.SETTINGS = {ReachBuffer = 300, ApproachRange = 1000, ApproachLookahead = 0.5, ApproachEpsilon = 25}
local function isCore(unit)
    local pos = LaneConfig.PositionOf(unit)
    return pos ~= nil and pos <= 3
end
--- The switch is on and `bot` is a support (position 4 or 5).
function ____exports.Applies(bot)
    if not Ours.On("LeaveCoreCreep") then
        return false
    end
    local pos = LaneConfig.PositionOf(bot)
    return pos == 4 or pos == 5
end
--- Whether `core` can take `creep` itself: attacking it, in attack range + ReachBuffer, or walking to it.
function ____exports.CanTake(core, creep)
    if core:GetAttackTarget() == creep then
        return true
    end
    local dist = GetUnitToUnitDistance(core, creep)
    if dist <= core:GetAttackRange() + ____exports.SETTINGS.ReachBuffer then
        return true
    end
    if dist > ____exports.SETTINGS.ApproachRange then
        return false
    end
    local ahead = GetUnitToLocationDistance(
        creep,
        core:GetExtrapolatedLocation(____exports.SETTINGS.ApproachLookahead)
    )
    return ahead < dist - ____exports.SETTINGS.ApproachEpsilon
end
--- Some living allied core other than `bot` can take `creep`. Walks GetTeamMember (GetTeamPlayers is empty for a bot-only team).
function ____exports.CoreCanTake(bot, creep)
    do
        local i = 1
        while i <= 5 do
            do
                local __continue10
                repeat
                    local member = GetTeamMember(i)
                    if member == nil or member == nil or member == bot then
                        __continue10 = true
                        break
                    end
                    if not member:IsAlive() or member:IsIllusion() or not isCore(member) then
                        __continue10 = true
                        break
                    end
                    if ____exports.CanTake(member, creep) then
                        return true
                    end
                    __continue10 = true
                until true
                if not __continue10 then
                    break
                end
            end
            i = i + 1
        end
    end
    return false
end
--- May `bot` last-hit `creep`? Only meaningful where Applies(bot).
function ____exports.MayLastHit(bot, creep)
    return not ____exports.CoreCanTake(bot, creep)
end
return ____exports
