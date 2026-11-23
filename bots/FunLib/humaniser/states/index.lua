--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local LaneTable = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_table")
local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
function ____exports.IsEnabled()
    return Config.IsEnabled()
end
--- Whether this bot runs mode_laning_generic's Lua Think where OHA itself would leave Valve's laning: an ally of a human
-- in a drill game or with `Ours.Sustain` on (the lane-only hold and sustain's walk are rows of that Think). Decided once,
-- at the file's load. Off, and for a team with no human, the answer is OHA's own.
function ____exports.MayOwn(bot)
    return ____exports.IsEnabled() and LaneConfig.IsAllyOfHuman(bot) and (Ours.On("Sustain") or Drill.Active() ~= nil)
end
--- mode_rune_generic: OHA's own wisdom logic stands aside while the rune job holds the shrine for this bot.
function ____exports.WisdomOwned(bot)
    return RuneJob.ShrineHeld(bot)
end
local laneCtx = {}
--- mode_laning_generic's Think for a bot that owns it: the name of the lane table row that acted (states/lane_table).
function ____exports.LaneStep(bot, cb)
    local pid = bot:GetPlayerID()
    local c = laneCtx[pid]
    if c == nil or c.cb ~= cb then
        c = {cb = cb, ctx = {
            enabled = ____exports.IsEnabled,
            ohaLastHit = cb.ohaLastHit,
            ohaDeny = cb.ohaDeny,
            ohaLocal = cb.ohaLocal,
            ohaPosition = cb.ohaPosition
        }}
        laneCtx[pid] = c
    end
    return LaneTable.Walk(bot, c.ctx)
end
return ____exports
