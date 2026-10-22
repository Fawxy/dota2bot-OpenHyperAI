--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local LaneFightConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_config")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local AbilityClasses = require(GetScriptDirectory().."/FunLib/humaniser/ability_classes")
local CooldownMemory = require(GetScriptDirectory().."/FunLib/humaniser/cooldown_memory")
local CastWatch = require(GetScriptDirectory().."/FunLib/humaniser/cast_watch")
local FightRead = require(GetScriptDirectory().."/FunLib/humaniser/fight_read")
local KillCheck = require(GetScriptDirectory().."/FunLib/humaniser/kill_check")
____exports.Config = LaneFightConfig
____exports.AbilityClasses = AbilityClasses
____exports.CooldownMemory = CooldownMemory
____exports.CastWatch = CastWatch
____exports.FightRead = FightRead
____exports.KillCheck = KillCheck
function ____exports.IsActive()
    return LaneFightConfig.IsActive()
end
function ____exports.Tick(bot)
    if not LaneFightConfig.IsActive() or not LaneFightConfig.AppliesTo(bot) or not LaneConfig.InLaningPhase() then
        return
    end
    if LaneFightConfig.IsOn("Memory") and LaneState.ForBot(bot) ~= nil then
        CastWatch.Tick(bot)
    end
end
--- The fight read for `bot`; callers act on it. Guarded in index.ts: an error reads as no window.
function ____exports.ReadFor(bot, now)
    return FightRead.ReadFor(bot, now)
end
--- The kill check on `target` with `partners`; guarded in index.ts: an error reads as no check.
function ____exports.CheckKill(bot, partners, target, now)
    return KillCheck.Check(bot, partners, target, now)
end
return ____exports
