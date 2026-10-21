--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ObjectAssign(target, ...)
    local sources = {...}
    for i = 1, #sources do
        local source = sources[i]
        for key in pairs(source) do
            target[key] = source[key]
        end
    end
    return target
end
-- End of Lua Library inline imports
local ____exports = {}
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
local Runes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/runes")
local Busy = require(GetScriptDirectory().."/FunLib/humaniser/transitions/busy")
____exports.Settings = Settings
____exports.Runes = Runes
____exports.Busy = Busy
local function NEVER()
    return false
end
local helpers = {}
local providers = {
    Busy = function(bot) return (Busy.IsBusy(
        bot,
        DotaTime()
    )) end,
    Spare = function(bot) return (Busy.LaneCanSpare(bot, false)) end,
    Alone = NEVER,
    Rotation = function() return nil end
}
function ____exports.SetHelpers(h)
    helpers = h
end
function ____exports.Helpers()
    return helpers
end
function ____exports.SetOverlayProviders(p)
    providers = __TS__ObjectAssign({}, providers, p)
end
function ____exports.IsActive()
    return Settings.IsActive()
end
function ____exports.InLaningPhase()
    local ____temp_0
    if helpers.IsInLaningPhase ~= nil then
        ____temp_0 = helpers.IsInLaningPhase()
    else
        ____temp_0 = DotaTime() < 600
    end
    return ____temp_0
end
function ____exports.Tick(_bot)
    if not Settings.IsActive() then
        return
    end
end
function ____exports.Overlay(bot)
    return (((((((("phase: " .. (____exports.InLaningPhase() and "laning" or "post")) .. " busy=") .. tostring(providers.Busy(bot))) .. " spare=") .. tostring(providers.Spare(bot))) .. " alone=") .. tostring(providers.Alone(bot))) .. " rot=") .. (providers.Rotation(bot) or "-")
end
return ____exports
