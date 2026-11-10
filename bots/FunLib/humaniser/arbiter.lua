--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringStartsWith(self, searchString, position)
    if position == nil or position < 0 then
        position = 0
    end
    return string.sub(self, position + 1, #searchString + position) == searchString
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneControl = require(GetScriptDirectory().."/FunLib/humaniser/lane_control")
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
local LaneFight = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
--- Doctrine groups: 1 stay alive, 2 pair, 3 farm, 4 wave, 5 pressure, 6 jobs; lower wins. The lane is the base, below every
-- interrupt candidate, and `oha` below it; both log their rank as text in `grp`.
____exports.OHA = "oha"
____exports.BASE_GROUP = 7
local OHA_GROUP = 8
--- The lowest group number that applies wins; a tie inside it keeps the previous pick, else the first in list order.
function ____exports.Pick(candidates, previous)
    local best
    local prev
    for ____, c in ipairs(candidates) do
        do
            local __continue3
            repeat
                if not c.applies then
                    __continue3 = true
                    break
                end
                if c.name == previous then
                    prev = c
                end
                if best == nil or c.group < best.group then
                    best = c
                end
                __continue3 = true
            until true
            if not __continue3 then
                break
            end
        end
    end
    if best == nil then
        return nil
    end
    if prev ~= nil and prev.group <= best.group then
        return prev
    end
    return best
end
--- Whether `who` (a lever's taker: both, core, sup or a pid) names this hero.
local function leverNames(who, pid, pos)
    if who == "both" or who == tostring(pid) then
        return true
    end
    if pos == nil then
        return false
    end
    return who == (pos >= 4 and "sup" or "core")
end
--- The live lever of the lane controller that names this hero, if any.
function ____exports.LeverOf(bot)
    local d = LaneControl.Current(
        bot:GetTeam(),
        bot:GetAssignedLane()
    )
    if d == nil then
        return nil
    end
    local pid = bot:GetPlayerID()
    local pos = LaneConfig.PositionOf(bot)
    do
        local i = 0
        while i < #d.levers do
            if d.levers[i + 1] ~= "hold" and leverNames(d.who[i + 1], pid, pos) then
                return d.levers[i + 1]
            end
            i = i + 1
        end
    end
    return nil
end
--- A hero of ours the arbiter reasons about: a bot in its laning phase (as last read by its own callers) that no drill holds.
local function owned(bot)
    return Phase.LaningTransitionsSeen(bot) == true and not Drill.Held(bot)
end
--- The lane picker's body is in a last-hit attempt right now: its stored phase label, fresh within a second of its last scan.
local function lastHitNow(bot)
    local d = LanePick.Describe(
        bot:GetPlayerID(),
        DotaTime()
    )
    if d == nil or not __TS__StringStartsWith(d, "ph=lasthit ") then
        return false
    end
    local age = string.match(d, "sc=([%d%.]+)")
    return age ~= nil and tonumber(age) <= 1
end
--- Left out for want of a read that changes nothing: `trade` (core_trade keeps its episode in a private table; Desire opens and
-- closes it). The controller's lever is no candidate of its own: a pull lever lifts the running pull job to group 4, and the
-- in-lane levers are carried out by the laning body, so they ride on `lane` and are logged as the `lever` field.
function ____exports.Candidates(bot, jobName, lever)
    if lever == nil then
        lever = ____exports.LeverOf(bot)
    end
    if not owned(bot) then
        return {{name = ____exports.OHA, group = OHA_GROUP, applies = true}}
    end
    local out = {}
    out[#out + 1] = {
        name = "retreat",
        group = 1,
        host = "retreat",
        applies = RetreatState.Running(bot)
    }
    out[#out + 1] = {
        name = "lane_fight",
        group = 5,
        host = "team_roam",
        applies = LaneFight.CurrentPhase(bot) ~= "idle"
    }
    local jobHost = RuneJob.HostOf(bot) == BotMode.Rune and "rune" or "farm"
    out[#out + 1] = {name = "job", group = lever == "pull" and jobName == "pull" and 4 or 6, host = jobHost, applies = jobName ~= nil}
    out[#out + 1] = {
        name = "lane",
        group = lastHitNow(bot) and 3 or ____exports.BASE_GROUP,
        host = "laning",
        applies = true
    }
    out[#out + 1] = {name = ____exports.OHA, group = OHA_GROUP, applies = true}
    return out
end
local last = {}
local nextAt = {}
--- judgement: seconds between computes per hero; the gate calls Shadow from all 20 mode files every frame.
local PERIOD = 0.25
local function compute(bot, jobName)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local l = last[pid]
    local lever = ____exports.LeverOf(bot)
    local cands = ____exports.Candidates(bot, jobName, lever)
    local picked = ____exports.Pick(cands, l and l.pick) or cands[#cands]
    local act = HDebug.ModeName(bot:GetActiveMode())
    if l ~= nil and l.pick == picked.name and l.act == act then
        return
    end
    Telemetry.Event("arb", {
        {"pid", pid},
        {"pick", picked.name},
        {"grp", picked.group < ____exports.BASE_GROUP and picked.group or (picked.name == ____exports.OHA and "oha" or "base")},
        {"host", picked.host},
        {"act", act},
        {"agree", (picked.name == ____exports.OHA or picked.host == act) and 1 or 0},
        {"job", jobName},
        {"lever", lever},
        {"prev", l and l.pick},
        {"dwell", l ~= nil and now - l.since or nil}
    })
    last[pid] = {pick = picked.name, act = act, since = now}
end
--- Called from every mode's gate each frame; computes at most once per hero per PERIOD (also after an error) and logs on a
-- change of pick or active mode. Returns nothing, and an error inside it is swallowed so it cannot reach GetDesire.
function ____exports.Shadow(bot, jobName)
    if not Telemetry.IsEnabled() or not Ours.On("ArbiterShadow") then
        return
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local due = nextAt[pid]
    if due ~= nil and now < due and now >= due - PERIOD then
        return
    end
    nextAt[pid] = now + PERIOD
    pcall(function() return compute(
        bot,
        jobName()
    ) end)
end
return ____exports
