--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
function ____exports.Applies(bot)
    if not Ours.On("CoreLastHit") then
        return false
    end
    if bot:GetTeam() == Team.Dire and not Ours.On("CoreLastHitDire") then
        return false
    end
    local pos = LaneConfig.PositionOf(bot)
    return pos ~= nil and pos >= 1 and pos <= 3
end
return ____exports
