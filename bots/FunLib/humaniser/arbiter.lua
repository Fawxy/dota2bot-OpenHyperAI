--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringStartsWith(self, searchString, position)
    if position == nil or position < 0 then
        position = 0
    end
    return string.sub(self, position + 1, #searchString + position) == searchString
end

local function __TS__StringEndsWith(self, searchString, endPosition)
    if endPosition == nil or endPosition > #self then
        endPosition = #self
    end
    return string.sub(self, endPosition - #searchString + 1, endPosition) == searchString
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local CoreTrade = require(GetScriptDirectory().."/FunLib/humaniser/states/core_trade")
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
local MidRunes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/mid_runes")
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
--- A hero of ours the arbiter reasons about, one no drill holds: with `Ours.ArbiterDrive`, from its first laning read to an
-- end event (Phase.LaningHeld); off, a bot in its laning phase as last read by its own callers (no cache clock moves).
function ____exports.Owned(bot)
    if Drill.Held(bot) then
        return false
    end
    if Ours.On("ArbiterDrive") then
        return Phase.LaningHeld(bot)
    end
    return Phase.LaningTransitionsSeen(bot) == true
end
local owned = ____exports.Owned
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
local function retreatCandidate(bot)
    return {
        name = "retreat",
        group = 1,
        host = "retreat",
        applies = RetreatState.Running(bot)
    }
end
--- A pull lever of the controller lifts the running pull job to group 4; any other job is group 6.
local function jobCandidate(bot, job, lever)
    local host = RuneJob.HostOf(bot) == BotMode.Rune and "rune" or "farm"
    local pulls = job == "pull" or job ~= nil and __TS__StringEndsWith(job, "_pull")
    return {name = "job", group = lever == "pull" and pulls and 4 or 6, host = host, applies = job ~= nil}
end
--- The job is the chooser's running job, else a live camp job of the older camp-job path (`jobName` is then its kind). The
-- controller's lever is no candidate of its own: the in-lane levers are carried out by the laning body, so they ride on
-- `lane` and are logged as the `lever` field.
function ____exports.Candidates(bot, jobName, lever)
    if lever == nil then
        lever = ____exports.LeverOf(bot)
    end
    if not owned(bot) then
        return {{name = ____exports.OHA, group = OHA_GROUP, applies = true}}
    end
    local out = {}
    out[#out + 1] = retreatCandidate(bot)
    out[#out + 1] = {
        name = "trade",
        group = 5,
        host = "attack",
        applies = CoreTrade.Running(bot)
    }
    out[#out + 1] = {
        name = "lane_fight",
        group = 5,
        host = "team_roam",
        applies = LaneFight.CurrentPhase(bot) ~= "idle"
    }
    out[#out + 1] = jobCandidate(
        bot,
        jobName or CampJobs.LiveKind(bot),
        lever
    )
    out[#out + 1] = {
        name = "mid_rune",
        group = 6,
        host = "rune",
        applies = MidRunes.Claiming(bot)
    }
    out[#out + 1] = {
        name = "lane",
        group = lastHitNow(bot) and 3 or ____exports.BASE_GROUP,
        host = "laning",
        applies = true
    }
    out[#out + 1] = {name = ____exports.OHA, group = OHA_GROUP, applies = true}
    return out
end
--- The candidate the gate enforces now, if any: the hero's modes other than its host and the modes the gate admits for it
-- get desire 0. Only the driven candidates are asked (the retreat episode and the chooser's running job); every other
-- candidate is still shadow only and interrupts nothing. Not limited to laning heroes: an episode or a job is its own
-- claim on the hero (a drill's cast runs jobs while held).
function ____exports.Hold(bot, chooserJob)
    return ____exports.Pick({
        retreatCandidate(bot),
        jobCandidate(bot, chooserJob, nil)
    })
end
____exports.SETTINGS = {LaneDesire = 0.55}
local drivePrev = {}
local driveAt = {}
local drivePick = {}
--- Whether the drive holds this hero now: the switch on and the hero owned.
function ____exports.Drives(bot)
    return Ours.On("ArbiterDrive") and owned(bot)
end
--- The pick the gate enforces for an owned hero under the drive, computed once per hero per frame (the gate asks from all 20
-- mode files) and remembered for the next frame's tie. `chooserJob` is the chooser's running job.
function ____exports.Drive(bot, chooserJob)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local cached = drivePick[pid]
    if cached ~= nil and driveAt[pid] == now then
        return cached
    end
    local cands = ____exports.Candidates(bot, chooserJob)
    local p = ____exports.Pick(cands, drivePrev[pid]) or cands[#cands]
    drivePick[pid] = p
    driveAt[pid] = now
    drivePrev[pid] = p.name
    return p
end
--- Fight modes borrowed from OHA: what says our fight read wants them now (the attack mode's trade, team roam's trade or commit).
local BORROWED = {
    attack = function(bot) return CoreTrade.Running(bot) end,
    team_roam = function(bot)
        local p = LaneFight.CurrentPhase(bot)
        return p == "trade" or p == "commit"
    end
}
--- OHA's modes that run their own desire beside the lane base (the inventory's admitted rows); each is a job-group activity.
local ADMITTED_AT_BASE = {ward = true, rune = true}
--- Human interface and our own retreat: run their own code whatever the pick (retreat's desire is ours, Retreat.Desire).
local ALWAYS = {retreat = true, assemble = true, assemble_with_humans = true}
--- The drive's rule for `mode` against pick `p`, before OHA's code runs: a number replaces the mode's desire, undefined runs
-- the mode's own code (then After). `farmHost` is the chooser's host desire (a job may start from the lane base).
-- - always: retreat (ours), assemble, assemble_with_humans; the retreat pick keeps only these.
-- - the pick's host runs (farm: the chooser's host desire, its own code for an older-path camp job).
-- - borrowed attack and team roam run below a group-5 pick, kept by After only while our fight read wants them.
-- - farm below a group-6 pick: a chooser job may start, OHA's farm desire is denied.
-- - admitted ward and rune beside the lane base.
-- - everything else 0: laning when not the host, roam, defend, push, roshan, outpost and the shops.
function ____exports.DriveDecide(_bot, mode, p, farmHost)
    if ALWAYS[mode] == true then
        return nil
    end
    if p.name == "retreat" then
        return 0
    end
    if mode == p.host then
        local ____temp_0
        if mode == "farm" then
            ____temp_0 = farmHost()
        else
            ____temp_0 = nil
        end
        return ____temp_0
    end
    if BORROWED[mode] ~= nil then
        local ____temp_1
        if p.group > 5 then
            ____temp_1 = nil
        else
            ____temp_1 = 0
        end
        return ____temp_1
    end
    if mode == "farm" then
        return p.group > 6 and (farmHost() or 0) or 0
    end
    if ADMITTED_AT_BASE[mode] == true and p.group >= ____exports.BASE_GROUP then
        return nil
    end
    return 0
end
--- After OHA's code for `mode` returned `desire` under the drive: the lane host's desire replaces laning's, and a borrowed
-- fight mode that is not the pick's host keeps its desire only while our fight read wants it (the read is asked after the
-- mode's own GetDesire, which opens a trade or a fight).
function ____exports.DriveAfter(bot, mode, p, desire)
    if mode == "laning" and p.name == "lane" then
        return ____exports.SETTINGS.LaneDesire
    end
    local borrowed = BORROWED[mode]
    if borrowed ~= nil and mode ~= p.host then
        local ____borrowed_result_2
        if borrowed(bot) then
            ____borrowed_result_2 = desire
        else
            ____borrowed_result_2 = 0
        end
        return ____borrowed_result_2
    end
    return desire
end
--- ability_item_usage's "go complete items" TP to the fountain is denied for a hero the drive holds (user 13/11/2026).
function ____exports.DeniesItemsTp(bot)
    return ____exports.Drives(bot)
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
    local job = jobName or CampJobs.LiveKind(bot)
    local picked = ____exports.Drives(bot) and ____exports.Drive(bot, jobName) or (____exports.Pick(cands, l and l.pick) or cands[#cands])
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
        {"job", job},
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
