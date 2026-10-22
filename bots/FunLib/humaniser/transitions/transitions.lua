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
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local Busy = require(GetScriptDirectory().."/FunLib/humaniser/transitions/busy")
local MidRunes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/mid_runes")
local Rotation = require(GetScriptDirectory().."/FunLib/humaniser/transitions/rotation")
local Caution = require(GetScriptDirectory().."/FunLib/humaniser/transitions/caution")
local Teleports = require(GetScriptDirectory().."/FunLib/humaniser/transitions/teleports")
____exports.Settings = Settings
____exports.Runes = Runes
____exports.Busy = Busy
____exports.MidRunes = MidRunes
____exports.Rotation = Rotation
____exports.Caution = Caution
____exports.Teleports = Teleports
local helpers = {}
local providers = {
    Busy = function(bot) return LaneState.ForBot(bot) ~= nil and (Busy.IsBusy(
        bot,
        DotaTime()
    )) end,
    Spare = function(bot) return LaneState.ForBot(bot) ~= nil and (Busy.LaneCanSpare(bot, false)) end,
    Alone = function(bot)
        local s = LaneState.ForBot(bot)
        return s ~= nil and Caution.IsAlone(bot, s)
    end,
    Rotation = function(bot) return Rotation.Target(bot) end
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
function ____exports.Tick(bot)
    if not Settings.IsActive() then
        return
    end
    MidRunes.Tick(bot)
    Rotation.Tick(bot)
    Teleports.Tick(bot)
    Caution.Tick(bot)
end
--- Rune-mode hooks (3b). True for our pos 2 while the MidRunes sub-feature is on.
function ____exports.MidRunesOn(bot)
    return MidRunes.IsOn(bot)
end
function ____exports.MidRuneFocus(bot)
    return MidRunes.Focus(bot)
end
function ____exports.MidRuneYield(bot)
    MidRunes.Yield(bot)
end
function ____exports.MidRuneSkip(bot, raw, desire, target, status, gate)
    MidRunes.NoteSkip(
        bot,
        raw,
        desire,
        target,
        status,
        gate
    )
end
--- Rune-mode hooks (Task 4): the power rune a rotating support heads for, or undefined.
function ____exports.RuneTarget(bot)
    return Rotation.RuneTarget(bot)
end
--- Our mid's power-rune desire while a rotating support is with it or at the spot; 0 otherwise.
function ____exports.MidRuneDesire(bot)
    return Rotation.MidRuneDesire(bot)
end
--- The rune mode refused this frame: the rotation floor must not apply.
function ____exports.RotationYield(bot)
    Rotation.Yield(bot)
end
function ____exports.Overlay(bot)
    return (((((((("phase: " .. (____exports.InLaningPhase() and "laning" or "post")) .. " busy=") .. tostring(providers.Busy(bot))) .. " spare=") .. tostring(providers.Spare(bot))) .. " alone=") .. tostring(providers.Alone(bot))) .. " rot=") .. (providers.Rotation(bot) or "-")
end
return ____exports
