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
local hit
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
local ChoiceShadow = require(GetScriptDirectory().."/FunLib/humaniser/choice_shadow")
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local DesireLog = require(GetScriptDirectory().."/FunLib/humaniser/desire_log")
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
local JOBS = {STACK, RUNE}
--- The jobs that apply to this hero, best place in the trip table first (a tie keeps JOBS order).
local function ranked(bot)
    local out = {}
    local pos = LaneConfig.PositionOf(bot)
    for ____, j in ipairs(JOBS) do
        do
            local __continue19
            repeat
                if not Drill.AllowsJob(bot, j.name) then
                    __continue19 = true
                    break
                end
                if not j.Applies(bot) then
                    __continue19 = true
                    break
                end
                local p = TripTable.RankOf(j.name, pos)
                if p ~= nil then
                    out[#out + 1] = {j, p}
                end
                __continue19 = true
            until true
            if not __continue19 then
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
local function runningJob(bot)
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
--- Any of our jobs, or the decider's pull, runs for this hero.
function ____exports.Running(bot)
    return runningJob(bot) ~= nil or PullJob.Running(bot)
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
--- OHA's modes that keep their own desire beside the host's while the hold of that name runs.
local ADMITTED = {retreat = EPISODE_MODES, job = ____exports.EXCEPTIONS}
--- Our retreat's episode, else the chooser's running job (hosted in the rune mode for the mid's rune trip, else farm). Not
-- limited to laning heroes: an episode or a job is its own claim on the hero (a drill's cast runs jobs while held).
local function holdOf(bot, job)
    if RetreatState.Running(bot) then
        return {name = "retreat", host = "retreat"}
    end
    if job ~= nil then
        return {
            name = "job",
            host = RuneJob.HostOf(bot) == BotMode.Rune and "rune" or "farm"
        }
    end
    return nil
end
--- Which branch of Decide gave its last number (choice_shadow's reason); telemetry only, read by Gate.
local decideWhy
local HOLD_WHY = {retreat = "hold:retreat", job = "hold:job"}
--- A number replaces OHA's desire for `mode`; undefined lets OHA's code run. Under a hold the host mode runs
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
    local ____holdOf_5 = holdOf
    local ____bot_4 = bot
    local ____jobs_3
    if jobs then
        ____jobs_3 = ____exports.RunningJobName(bot)
    else
        ____jobs_3 = nil
    end
    local hold = ____holdOf_5(____bot_4, ____jobs_3)
    decideWhy = (hold == nil or mode == hold.host) and "host" or HOLD_WHY[hold.name]
    if hold == nil then
        local ____temp_6
        if jobs and mode == ____exports.HOST then
            ____temp_6 = hostDesire(bot)
        else
            ____temp_6 = nil
        end
        return ____temp_6
    end
    if mode == hold.host then
        local ____temp_7
        if mode == ____exports.HOST then
            ____temp_7 = hostDesire(bot)
        else
            ____temp_7 = nil
        end
        return ____temp_7
    end
    local ____temp_8
    if ADMITTED[hold.name][mode] ~= nil then
        ____temp_8 = nil
    else
        ____temp_8 = 0
    end
    return ____temp_8
end
--- Wraps a mode file's GetDesire. 0, never nil: nil falls through to Valve's built-in desire for that mode. What it returns is
-- noted for the decider's retreat read (Decider.NoteDesire), then capped under a soft hold (Decider.Cap). The shadow line
-- and DesireLog note the value before the cap: under a soft hold, not what Valve saw.
function ____exports.Gate(bot, mode, inner)
    return function()
        local shadow = ChoiceShadow.On()
        if shadow then
            ChoiceShadow.Frame(bot)
        end
        local v = ____exports.Decide(bot, mode)
        if v ~= nil then
            if shadow then
                ChoiceShadow.Note(
                    bot,
                    mode,
                    nil,
                    v,
                    decideWhy
                )
            end
            Decider.NoteDesire(bot, mode, v)
            return Decider.Cap(bot, mode, v)
        end
        local d = inner()
        DesireLog.Note(bot, mode, d)
        if shadow then
            ChoiceShadow.Note(
                bot,
                mode,
                d,
                d,
                nil
            )
        end
        Decider.NoteDesire(bot, mode, d)
        return Decider.Cap(bot, mode, d)
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
        local ____table_Step_result_9
        if (runningJob(bot) or STACK).Step(bot, ____exports.HOST_MODE) then
            ____table_Step_result_9 = nil
        else
            ____table_Step_result_9 = inner()
        end
        return ____table_Step_result_9
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
    local ____opt_14 = runningJob(bot)
    if ____opt_14 ~= nil then
        ____opt_14.End(bot, why)
    end
end
--- mode_farm_generic's ShouldRun: neutrals hitting the hero during its job are not a reason to run; the job's exit is its
-- retreat. OHA's creep clause (level < 5, hit by a creep, HP < 0.7) cancelled 5 of 9 attempts after the hit (probe s4p4).
function ____exports.HoldsRun(bot)
    return ____exports.Running(bot)
end
--- mode_retreat_generic's creep-damage branch: while the decider's pull runs, the neutrals hitting the hero are the pull's
-- own doing and not a reason for stock's retreat (the pull's verb bails from them itself). Lane creeps and heroes still count.
function ____exports.PullsNeutrals(bot)
    return PullJob.Running(bot)
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
        if not PullJob.Running(bot) then
            return Drill.IdleStatue(bot)
        end
        PullJob.NoteIdleHeld(bot)
        return true
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
