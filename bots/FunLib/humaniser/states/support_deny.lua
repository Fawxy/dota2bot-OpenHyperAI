--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
function ____exports.Applies(bot)
    if not Ours.On("SupportDeny") then
        return false
    end
    if bot:GetTeam() == Team.Dire and not Ours.On("SupportDenyDire") then
        return false
    end
    local pos = LaneConfig.PositionOf(bot)
    return pos == 4 or pos == 5
end
--- With Applies: the body also takes the support's claimed last hits (Ours.SupportLastHit); false leaves them to OHA.
function ____exports.LastHits(_bot)
    return Ours.On("SupportLastHit")
end
return ____exports
