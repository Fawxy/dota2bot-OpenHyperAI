--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Tower = ____dota.Tower
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local T1 = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
local held = {}
function ____exports.ResetCache()
    held = {}
end
local function towerDown(team, lane)
    local id = T1[lane]
    if id == nil then
        return false
    end
    local t = GetTower(team, id)
    return t == nil or t == nil or not t:IsAlive()
end
--- judgement: seconds between checks of a hero's hold.
local HELD_CHECK = 1
--- Why a hero's laning is over: the clock, or a tier-1 of its lane lost (ours or theirs); undefined while it is not.
local function heldEndWhy(bot)
    if not LaneConfig.InLaningPhase() then
        return "clock"
    end
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    if towerDown(team, lane) or towerDown(team == 2 and 3 or 2, lane) then
        return "tower"
    end
    return nil
end
--- The hero is held from its first read in its laning to an end event (heldEndWhy), and never again after it. The start
-- and the end log `ev=arb` with `ph`.
function ____exports.LaningHeld(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local h = held[pid]
    if h == nil then
        h = {on = false, checkAt = -math.huge}
        held[pid] = h
    end
    if h.ended ~= nil then
        return false
    end
    if now < h.checkAt then
        return h.on
    end
    h.checkAt = now + HELD_CHECK
    if not h.on then
        if heldEndWhy(bot) ~= nil then
            return false
        end
        h.on = true
        Telemetry.Event("arb", {{"pid", pid}, {"ph", "own"}})
        return true
    end
    local why = heldEndWhy(bot)
    if why == nil then
        return true
    end
    h.on = false
    h.ended = why
    Telemetry.Event("arb", {{"pid", pid}, {"ph", "end"}, {"why", why}})
    return false
end
return ____exports
