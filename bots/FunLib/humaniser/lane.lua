--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LanePlanner = require(GetScriptDirectory().."/FunLib/humaniser/lane_planner")
local LaneTech = require(GetScriptDirectory().."/FunLib/humaniser/lane_tech")
local LaneDebug = require(GetScriptDirectory().."/FunLib/humaniser/lane_debug")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
____exports.Config = LaneConfig
____exports.Hooks = LaneHooks
____exports.Camps = Camps
____exports.LaneState = LaneState
____exports.LaneRoles = LaneRoles
____exports.LanePlan = LanePlan
____exports.LanePlanner = LanePlanner
____exports.LaneTech = LaneTech
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
--- Whether this bot's laning Think() is OHA's (decided once at mode-file load, like AllyLastHit.OwnsLaning).
function ____exports.OwnsLaning(bot)
    return LaneTech.OwnsLaning(bot)
end
--- Runs before last hits; true means this frame's action is issued.
function ____exports.PreThink(bot, allyCreeps, enemyCreeps, enemies)
    return LaneTech.PreThink(bot, allyCreeps, enemyCreeps, enemies)
end
--- Runs after last hit and deny; true means this frame's action is issued.
function ____exports.Think(bot, allyCreeps, enemyCreeps, enemies)
    return LaneTech.Think(bot, allyCreeps, enemyCreeps, enemies)
end
--- Lane position override for the final move; returns `loc` itself when nothing applies.
function ____exports.AdjustPosition(bot, loc)
    return LaneTech.AdjustPosition(bot, loc)
end
function ____exports.PickDeny(_bot, _allyCreeps)
    return nil
end
function ____exports.SupersedesHarass(_bot)
    return false
end
return ____exports
