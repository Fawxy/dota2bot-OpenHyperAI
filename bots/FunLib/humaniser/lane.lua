--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneDebug = require(GetScriptDirectory().."/FunLib/humaniser/lane_debug")
____exports.Config = LaneConfig
____exports.Hooks = LaneHooks
____exports.Camps = Camps
function ____exports.IsEnabled()
    return LaneConfig.IsEnabled()
end
function ____exports.SetHelpers(h)
    LaneConfig.SetHelpers(h)
end
function ____exports.Tick(bot)
    LaneDebug.Tick(bot)
    if not LaneConfig.IsActive() then
        return
    end
end
return ____exports
