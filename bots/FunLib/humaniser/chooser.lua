--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local runningJob, hit, JOBS
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
local CoreCamp = require(GetScriptDirectory().."/FunLib/humaniser/core_camp")
local PullFarm = require(GetScriptDirectory().."/FunLib/humaniser/pull_farm")
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local Arbiter = require(GetScriptDirectory().."/FunLib/humaniser/arbiter")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
local ChoiceShadow = require(GetScriptDirectory().."/FunLib/humaniser/choice_shadow")
function runningJob(bot)
    for ____, j in ipairs(JOBS) do
        if j.Running(bot) then
            return j
        end
    end
    return nil
end
--- The name of the job running for this hero, or undefined (slice retreat reads it as the hero's purpose).
function ____exports.RunningJobName(bot)
    local ____opt_1 = runningJob(bot)
    return ____opt_1 and ____opt_1.name
end
--- Under the drive, the arbiter's word on what OHA's code for `mode` returned (Arbiter.DriveAfter); else that value.
function ____exports.After(bot, mode, desire)
    if not Arbiter.Drives(bot) then
        return desire
    end
    local jobs = Ours.On("JobChooser")
    local ____Arbiter_DriveAfter_26 = Arbiter.DriveAfter
    local ____bot_24 = bot
    local ____mode_25 = mode
    local ____Arbiter_Drive_23 = Arbiter.Drive
    local ____bot_22 = bot
    local ____jobs_21
    if jobs then
        ____jobs_21 = ____exports.RunningJobName(bot)
    else
        ____jobs_21 = nil
    end
    return ____Arbiter_DriveAfter_26(
        ____bot_24,
        ____mode_25,
        ____Arbiter_Drive_23(____bot_22, ____jobs_21),
        desire
    )
end
function hit(bot)
    return bot:WasRecentlyDamagedByAnyHero(____exports.SETTINGS.HitWithin)
end
--- Why the hero may not leave now, else undefined. `Ours.TripRead`: a `deadly` Safe.At answer here (`enemy-near`), the walk to `ask.at` when
-- given (`kill`, `tower`, `unknown`), the HP floor only for `ask.neutrals`, or fighting or retreating. Off: low HP, the answer here, hit by a
-- hero just now, or fighting or retreating.
function ____exports.MayStart(bot, ask)
    local read = Ours.On("TripRead")
    if (not read or (ask and ask.neutrals) == true) and bot:GetHealth() < bot:GetMaxHealth() * ____exports.SETTINGS.MinHpFraction then
        return "low-hp"
    end
    if SafeGather.At(
        bot,
        bot:GetLocation(),
        {who = "job_start"}
    ).level == "deadly" then
        return "enemy-near"
    end
    if read and (ask and ask.at) ~= nil then
        local why = SafeGather.TripGate(bot, ask.at, ask.who or "job_trip").why
        if why ~= nil then
            return why
        end
    end
    if not read and hit(bot) then
        return "hit"
    end
    local mode = bot:GetActiveMode()
    if mode == BotMode.Attack or mode == BotMode.Retreat then
        return "busy"
    end
    return nil
end
____exports.SETTINGS = {
    JobDesire = 0.92,
    BenchDesire = 1.2,
    MinHpFraction = 0.5,
    EnemyRadius = 600,
    HitWithin = 3
}
--- The mode that hosts a running job.
____exports.HOST = "farm"
____exports.HOST_MODE = BotMode.Farm
--- OHA's modes that may still take the hero during a job: mode name (the file's, without `mode_` and `_generic`) to what
-- removes the entry. Designed to end up empty. Names, not BOT_MODE numbers: BotMode has no assemble-with-humans entry, and
-- a name cannot be nil. Attack: only the 9 heroes OHA overrides have a wrapped attack mode.
____exports.EXCEPTIONS = {retreat = "our own retreat after laning", assemble = "our own human interface", assemble_with_humans = "our own human interface", attack = "our own fights, or a Valve fix"}
local STACK = {
    name = "stack",
    Applies = function(bot) return StackJob.Applies(bot) end,
    Claims = function(bot) return StackJob.Pending(bot) end,
    Wants = function(bot, blocked, host) return StackJob.Wants(bot, blocked, host) end,
    Running = function(bot) return StackJob.Running(bot) end,
    Step = function(bot, host) return StackJob.Step(bot, host) end,
    End = function(bot, why) return StackJob.End(bot, why) end,
    NoteHit = function(bot) return StackJob.NoteHit(bot) end,
    NoteIdleHeld = function(bot) return StackJob.NoteIdleHeld(bot) end
}
local RUNE = {
    name = "rune",
    Applies = function(bot) return RuneJob.Applies(bot) end,
    Claims = function(bot) return RuneJob.Claims(bot) end,
    Wants = function(bot, blocked, host) return RuneJob.Wants(bot, blocked, host) end,
    Running = function(bot) return RuneJob.Running(bot) end,
    Step = function(bot, host) return RuneJob.Step(bot, host) end,
    End = function(bot, why) return RuneJob.End(bot, why) end,
    NoteHit = function(bot) return RuneJob.NoteHit(bot) end,
    NoteIdleHeld = function(bot) return RuneJob.NoteIdleHeld(bot) end
}
local PULL = {
    name = "pull",
    Applies = function(bot) return PullJob.Applies(bot) end,
    Lifted = function(bot) return PullJob.Lifted(bot) end,
    Claims = function(bot) return PullJob.Claims(bot) end,
    Wants = function(bot, blocked, host) return PullJob.Wants(bot, blocked, host) end,
    Running = function(bot) return PullJob.Running(bot) end,
    Step = function(bot, host) return PullJob.Step(bot, host) end,
    End = function(bot, why) return PullJob.End(bot, why) end,
    NoteHit = function(bot) return PullJob.NoteHit(bot) end,
    NoteIdleHeld = function(bot) return PullJob.NoteIdleHeld(bot) end
}
local CAMP = {
    name = "camp",
    guards = true,
    Applies = function(bot) return CoreCamp.Owns(bot) end,
    Claims = function(bot) return CoreCamp.Claims(bot) end,
    Wants = function(bot, blocked, host) return CoreCamp.Wants(bot, blocked, host) end,
    Running = function(bot) return CoreCamp.Running(bot) end,
    Step = function(bot, host) return CoreCamp.Step(bot, host) end,
    End = function(bot, why) return CoreCamp.End(bot, why) end,
    NoteHit = function(bot) return CoreCamp.NoteHit(bot) end,
    NoteIdleHeld = function(bot) return CoreCamp.NoteIdleHeld(bot) end
}
local PULLFARM = {
    name = "pullfarm",
    guards = true,
    Applies = function(bot) return PullFarm.Applies(bot) end,
    Claims = function(bot) return PullFarm.Claims(bot) end,
    Wants = function(bot, blocked, host) return PullFarm.Wants(bot, blocked, host) end,
    Running = function(bot) return PullFarm.Running(bot) end,
    Step = function(bot, host) return PullFarm.Step(bot, host) end,
    End = function(bot, why) return PullFarm.End(bot, why) end,
    NoteHit = function(bot) return PullFarm.NoteHit(bot) end,
    NoteIdleHeld = function(bot) return PullFarm.NoteIdleHeld(bot) end
}
JOBS = {
    STACK,
    RUNE,
    PULL,
    PULLFARM,
    CAMP
}
--- The jobs that apply to this hero, best place in the trip table first (a tie keeps JOBS order).
local function ranked(bot)
    local out = {}
    local only = Drill.ForcedJob(bot)
    local pos = LaneConfig.PositionOf(bot)
    for ____, j in ipairs(JOBS) do
        do
            local __continue44
            repeat
                if only ~= nil and j.name ~= only then
                    __continue44 = true
                    break
                end
                if not j.Applies(bot) then
                    __continue44 = true
                    break
                end
                local p = TripTable.RankOf(
                    j.name,
                    pos,
                    j.Lifted ~= nil and j.Lifted(bot)
                )
                if p ~= nil then
                    out[#out + 1] = {j, p}
                end
                __continue44 = true
            until true
            if not __continue44 then
                break
            end
        end
    end
    do
        local i = 1
        while i < #out do
            do
                local k = i
                while k > 0 and out[k + 1][2] < out[k][2] do
                    local ____temp_0 = {out[k], out[k + 1]}
                    out[k + 1] = ____temp_0[1]
                    out[k] = ____temp_0[2]
                    k = k - 1
                end
            end
            i = i + 1
        end
    end
    return __TS__ArrayMap(
        out,
        function(____, e) return e[1] end
    )
end
--- Any of our jobs runs for this hero.
function ____exports.Running(bot)
    return runningJob(bot) ~= nil
end
--- The host's desire, switch on. Retreat at 0.92 or above wins through Valve's arbitration without help; below that no desire
-- value separates danger from a healthy hero (slice file, "Retreat"), so the job ends itself: with `Ours.TripRead` on a deadly safe-read answer
-- where the hero stands (held; no reaction hold, one deadly frame ends it), unless the job has its own guard (`Job.guards`); off, when a
-- hero hit it just now and HP is under MinHpFraction. Neutrals alone never count. A benched hero stays with the host file's own bench. Jobs are asked in
-- rank order; a start waits while a higher-ranked job claims the hero (`why=<job>` in the waiting job's skip line).
local function hostDesire(bot)
    if StackJob.Benched(bot) then
        return nil
    end
    local cur = runningJob(bot)
    if cur ~= nil then
        for ____, j in ipairs(ranked(bot)) do
            if j ~= cur then
                j.Wants(
                    bot,
                    function() return cur.name end,
                    ____exports.HOST_MODE
                )
            end
        end
        if not cur.Wants(bot, ____exports.MayStart, ____exports.HOST_MODE) then
            return nil
        end
        local struck = hit(bot)
        if struck then
            cur.NoteHit(bot)
        end
        local leave
        if not Ours.On("TripRead") then
            leave = struck and bot:GetHealth() < bot:GetMaxHealth() * ____exports.SETTINGS.MinHpFraction
        else
            leave = cur.guards ~= true and SafeGather.At(
                bot,
                bot:GetLocation(),
                {held = true, who = "job_run"}
            ).level == "deadly"
        end
        if leave then
            cur.End(bot, "retreat")
            return nil
        end
        return ____exports.SETTINGS.JobDesire
    end
    local jobs = ranked(bot)
    do
        local i = 0
        while i < #jobs do
            local function blocked(b, ask)
                local why = ____exports.MayStart(b, ask)
                if why ~= nil then
                    return why
                end
                do
                    local k = 0
                    while k < i do
                        if jobs[k + 1].Claims(b) then
                            return jobs[k + 1].name
                        end
                        k = k + 1
                    end
                end
                return nil
            end
            if jobs[i + 1].Wants(bot, blocked, ____exports.HOST_MODE) then
                return ____exports.SETTINGS.JobDesire
            end
            i = i + 1
        end
    end
    if Drill.IdleStatue(bot) then
        return ____exports.SETTINGS.BenchDesire
    end
    return nil
end
--- While our retreat's episode runs, only the retreat mode (the hold's host) and the human's order modes, listed here, may hold the hero: OHA's modes post
-- up to 2.88, and roam's tango branch (1.00) took it five times in 8 s at 10-15% HP with the enemy in reach (rtwatch1).
local EPISODE_MODES = {assemble = true, assemble_with_humans = true}
--- OHA's modes that keep their own desire beside the host's while the arbiter's hold of that name runs.
local ADMITTED = {retreat = EPISODE_MODES, job = ____exports.EXCEPTIONS}
--- Which branch of Decide gave its last number (choice_shadow's reason); telemetry only, read by Gate.
local decideWhy
local HOLD_WHY = {retreat = "hold:retreat", job = "hold:job"}
--- A number replaces OHA's desire for `mode`; undefined lets OHA's code run. Under the arbiter's hold the host mode runs
-- and every mode the hold does not admit gets 0. A job hosted in the rune mode (the mid's 6:00 trip) leaves the chooser's
-- host at 0: gating the rune mode handed the mid to the attack mode 9 of 10 trips (rspchk1), and OHA's farm desire must
-- not take it either.
function ____exports.Decide(bot, mode)
    decideWhy = nil
    if Drill.InLaneDenies(bot, mode) then
        decideWhy = "drill"
        return 0
    end
    local rig = Drill.RigDesire(bot, mode)
    if rig ~= nil then
        decideWhy = "rig"
        return rig
    end
    local jobs = Ours.On("JobChooser")
    if Arbiter.Drives(bot) then
        local ____Arbiter_Drive_5 = Arbiter.Drive
        local ____bot_4 = bot
        local ____jobs_3
        if jobs then
            ____jobs_3 = ____exports.RunningJobName(bot)
        else
            ____jobs_3 = nil
        end
        local p = ____Arbiter_Drive_5(____bot_4, ____jobs_3)
        decideWhy = "drive"
        return Arbiter.DriveDecide(
            bot,
            mode,
            p,
            function()
                local ____jobs_6
                if jobs then
                    ____jobs_6 = hostDesire(bot)
                else
                    ____jobs_6 = nil
                end
                return ____jobs_6
            end
        )
    end
    local ____Arbiter_Hold_9 = Arbiter.Hold
    local ____bot_8 = bot
    local ____jobs_7
    if jobs then
        ____jobs_7 = ____exports.RunningJobName(bot)
    else
        ____jobs_7 = nil
    end
    local hold = ____Arbiter_Hold_9(____bot_8, ____jobs_7)
    decideWhy = (hold == nil or mode == hold.host) and "host" or HOLD_WHY[hold.name]
    if hold == nil then
        local ____temp_10
        if jobs and mode == ____exports.HOST then
            ____temp_10 = hostDesire(bot)
        else
            ____temp_10 = nil
        end
        return ____temp_10
    end
    if mode == hold.host then
        local ____temp_11
        if mode == ____exports.HOST then
            ____temp_11 = hostDesire(bot)
        else
            ____temp_11 = nil
        end
        return ____temp_11
    end
    local ____temp_12
    if ADMITTED[hold.name][mode] ~= nil then
        ____temp_12 = nil
    else
        ____temp_12 = 0
    end
    return ____temp_12
end
--- Wraps a mode file's GetDesire. 0, never nil: nil falls through to Valve's built-in desire for that mode.
function ____exports.Gate(bot, mode, inner)
    return function()
        Arbiter.Shadow(
            bot,
            function()
                local ____opt_13 = runningJob(bot)
                return ____opt_13 and ____opt_13.name
            end
        )
        local shadow = ChoiceShadow.On()
        if shadow then
            ChoiceShadow.Frame(
                bot,
                function()
                    local ____opt_15 = runningJob(bot)
                    return ____opt_15 and ____opt_15.name
                end
            )
        end
        local v = ____exports.Decide(bot, mode)
        if v ~= nil then
            if shadow then
                local why = decideWhy
                local probe = why == "drive" and ChoiceShadow.PROBED[mode] == true and Ours.On("ChoiceProbe")
                local ____ChoiceShadow_Note_20 = ChoiceShadow.Note
                local ____bot_18 = bot
                local ____mode_19 = mode
                local ____probe_17
                if probe then
                    ____probe_17 = ChoiceShadow.Probe(inner)
                else
                    ____probe_17 = nil
                end
                ____ChoiceShadow_Note_20(
                    ____bot_18,
                    ____mode_19,
                    ____probe_17,
                    v,
                    why,
                    probe
                )
            end
            return v
        end
        local d = inner()
        local out = ____exports.After(bot, mode, d)
        if shadow then
            ChoiceShadow.Note(
                bot,
                mode,
                d,
                out,
                nil,
                false
            )
        end
        return out
    end
end
--- Wraps the host file's Think, switch on: the job steps without entering OHA's code, so its defend-ping and run aborts cannot
-- fire. No step while the bot cannot act, as OHA's Think does first: StackJob's StallAfter depends on that skip.
function ____exports.HostThink(bot, mode, inner, cannotAct)
    return function()
        if mode ~= ____exports.HOST or not Ours.On("JobChooser") or StackJob.Benched(bot) then
            return inner()
        end
        if cannotAct(bot) then
            return nil
        end
        local ____table_Step_result_27
        if (runningJob(bot) or STACK).Step(bot, ____exports.HOST_MODE) then
            ____table_Step_result_27 = nil
        else
            ____table_Step_result_27 = inner()
        end
        return ____table_Step_result_27
    end
end
--- mode_farm_generic GetDesire hook, switch off: the job's desire while it runs or as it starts, else 0 (OHA decides). A hero
-- hit ends a running job. Switch on, the wrapper has already acted. Goes when the switch is retired.
function ____exports.FarmDesire(bot)
    if Ours.On("JobChooser") or not StackJob.Wants(bot, ____exports.MayStart, ____exports.HOST_MODE) then
        return 0
    end
    if StackJob.Running(bot) and hit(bot) then
        StackJob.NoteHit(bot)
        StackJob.End(bot, "hit")
        return 0
    end
    return ____exports.SETTINGS.JobDesire
end
--- mode_farm_generic Think hook, switch off: steps the job; false when none runs. Switch on, the wrapper has already acted.
function ____exports.FarmThink(bot)
    return not Ours.On("JobChooser") and StackJob.Step(bot, ____exports.HOST_MODE)
end
--- OHA's farm-mode run (or any host abort) ends the job; its line reports `cancelled:<why>`.
function ____exports.Abort(bot, why)
    local ____opt_32 = runningJob(bot)
    if ____opt_32 ~= nil then
        ____opt_32.End(bot, why)
    end
end
--- mode_farm_generic's ShouldRun: neutrals hitting the hero during its job are not a reason to run; the job's exit is its
-- retreat. OHA's creep clause (level < 5, hit by a creep, HP < 0.7) cancelled 5 of 9 attempts after the hit (probe s4p4).
function ____exports.HoldsRun(bot)
    return ____exports.Running(bot)
end
--- ability_item_usage: spells and items wait while the job runs, as camp_jobs' HoldsCasts does for camp jobs. OHA's farm
-- branches cast on the camp: witch doctor's cask landed at :42-:47, before the hit, and once after it, and the stunned
-- neutrals walked back into the box (user replay and s4solo2); a TP scroll on the walk stalled the job (s4solo2 5:4x).
-- An enemy hero in reach lifts it so the bot can fight or save itself. A drill's benched heroes and statues never cast, nor
-- does a lane-only hero (spells on creeps would change the last-hit contest under test); a chaser of an entry with
-- `chaserCasts` does, in a chase rep. `items`: the caller is OHA's item use, which a cast of an entry with `castItems` keeps.
function ____exports.HoldsCasts(bot, items)
    local rig = Drill.RigHoldsCasts(bot, items == true)
    if rig ~= nil then
        return rig
    end
    if StackJob.Benched(bot) and not Drill.Casts(bot) or Overrides.LaneOnly(bot) and not (items == true and Drill.CastItems(bot)) then
        return true
    end
    if not ____exports.Running(bot) then
        return Drill.IdleStatue(bot)
    end
    return #(bot:GetNearbyHeroes(____exports.SETTINGS.EnemyRadius, true, BotMode.None) or ({})) == 0
end
--- jmz_func CheckBotIdleState (called from team_roam's GetDesire whatever mode is active): a bot in farm mode that moved
-- under 100 in 3 s gets ClearActions and an attack-move to its lane front. A stack job stands still at its stand point by
-- design, and when the check fell inside the 2 s after the hit order it replaced the attack: all 4 slice 4 `no-aggro` misses
-- (attack-move from the order to the miss, s4 A_on_1 5:55 and 7:53, s4r3 C_on_3 7:54, s4x1 A_on_1 5:55). True while the job
-- runs, counted on the attempt, and always for a drill's benched hero or statue (its attack-move would end the statue).
function ____exports.HoldsIdle(bot)
    if StackJob.Benched(bot) then
        return true
    end
    local cur = runningJob(bot)
    if cur == nil then
        return Drill.IdleStatue(bot)
    end
    cur.NoteIdleHeld(bot)
    return true
end
--- A drill's benched hero or statue (humaniser/drill.ts) holds farm mode and takes its step there.
function ____exports.Benched(bot)
    return StackJob.Benched(bot)
end
function ____exports.Bench(bot)
    return StackJob.Bench(bot)
end
return ____exports
