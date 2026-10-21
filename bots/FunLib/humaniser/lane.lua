--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LaneDebug = require(GetScriptDirectory().."/FunLib/humaniser/lane_debug")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
____exports.Config = LaneConfig
____exports.Hooks = LaneHooks
____exports.Camps = Camps
____exports.LaneState = LaneState
____exports.LanePlan = LanePlan
function ____exports.IsEnabled()
    return LaneConfig.IsEnabled()
end
function ____exports.SetHelpers(h)
    LaneConfig.SetHelpers(h)
end
function ____exports.Tick(bot)
    LaneDebug.Tick(bot)
    local snapshot = LaneState.ForBot(bot)
    if snapshot == nil then
        return
    end
    if HDebug.IsEnabled() then
        local state = LaneState.Describe(
            snapshot,
            LaneState.ScoreFor(bot, snapshot)
        )
        HDebug.Text(
            bot,
            "lane",
            (state .. " ") .. LanePlan.Describe(LanePlan.View(bot, snapshot))
        )
    end
end
return ____exports
