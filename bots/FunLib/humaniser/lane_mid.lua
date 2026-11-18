--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
function ____exports.IsPreRuneWindow(now, nextRune)
    local timing = LaneConfig.Settings().Timing
    local left = nextRune - now
    return left >= timing.PreRuneMin and left <= timing.PreRuneMax
end
function ____exports.IsPreRune(_team, lane)
    if lane ~= Lane.Mid or not LaneConfig.IsOn("Mid") then
        return false
    end
    local next = LaneConfig.Helpers().NextPowerRuneTime
    return next ~= nil and ____exports.IsPreRuneWindow(
        DotaTime(),
        next()
    )
end
function ____exports.MidPullAllowed(team)
    return #Camps.PullCampsFor(team, Lane.Mid) > 0
end
function ____exports.RegisterProbes()
    LaneHooks.SetRotationProbe(function(bot) return bot:GetAssignedLane() == Lane.Mid and ____exports.IsPreRune(
        bot:GetTeam(),
        Lane.Mid
    ) end)
end
LaneState.SetPreRune(____exports.IsPreRune)
____exports.RegisterProbes()
return ____exports
