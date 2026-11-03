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
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
function hit(bot)
    return bot:WasRecentlyDamagedByAnyHero(____exports.SETTINGS.HitWithin)
end
--- Why the hero may not leave now (the lane is under attack), else undefined: low HP, an enemy hero in reach, hit by a
-- hero just now, or fighting or retreating.
function ____exports.MayStart(bot)
    if bot:GetHealth() < bot:GetMaxHealth() * ____exports.SETTINGS.MinHpFraction then
        return "low-hp"
    end
    if #(bot:GetNearbyHeroes(____exports.SETTINGS.EnemyRadius, true, BotMode.None) or ({})) > 0 then
        return "enemy-near"
    end
    if hit(bot) then
        return "hit"
    end
    local mode = bot:GetActiveMode()
    if mode == BotMode.Attack or mode == BotMode.Retreat then
        return "busy"
    end
    return nil
end
____exports.SETTINGS = {JobDesire = 0.92, MinHpFraction = 0.5, EnemyRadius = 600, HitWithin = 3}
--- The mode that hosts a running job.
____exports.HOST = "farm"
____exports.HOST_MODE = BotMode.Farm
--- OHA's modes that may still take the hero during a job: mode name (the file's, without `mode_` and `_generic`) to what
-- removes the entry. Designed to end up empty. Names, not BOT_MODE numbers: BotMode has no assemble-with-humans entry, and
-- a name cannot be nil. Attack: only the 9 heroes OHA overrides have a wrapped attack mode.
____exports.EXCEPTIONS = {retreat = "our own retreat", assemble = "our own human interface", assemble_with_humans = "our own human interface", attack = "our own fights, or a Valve fix"}
local STACK = {
    name = "stack",
    Priority = function(bot) return StackJob.Applies(bot) and ____exports.SETTINGS.JobDesire or nil end,
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
    Priority = function(bot) return RuneJob.Priority(bot) end,
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
    Priority = function(bot) return PullJob.Priority(bot) end,
    Claims = function(bot) return PullJob.Claims(bot) end,
    Wants = function(bot, blocked, host) return PullJob.Wants(bot, blocked, host) end,
    Running = function(bot) return PullJob.Running(bot) end,
    Step = function(bot, host) return PullJob.Step(bot, host) end,
    End = function(bot, why) return PullJob.End(bot, why) end,
    NoteHit = function(bot) return PullJob.NoteHit(bot) end,
    NoteIdleHeld = function(bot) return PullJob.NoteIdleHeld(bot) end
}
local JOBS = {STACK, RUNE, PULL}
--- The jobs that apply to this hero, highest priority first (a tie keeps JOBS order).
local function ranked(bot)
    local out = {}
    for ____, j in ipairs(JOBS) do
        local p = j.Priority(bot)
        if p ~= nil then
            out[#out + 1] = {j, p}
        end
    end
    do
        local i = 1
        while i < #out do
            do
                local k = i
                while k > 0 and out[k + 1][2] > out[k][2] do
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
--- Any of our jobs runs for this hero.
function ____exports.Running(bot)
    return runningJob(bot) ~= nil
end
--- The host's desire, switch on. Retreat at 0.92 or above wins through Valve's arbitration without help; below that no desire
-- value separates danger from a healthy hero (slice file, "Retreat"), so the job ends when a hero hit it just now and HP is
-- under MinHpFraction. Neutrals alone never count. A benched hero stays with the host file's own bench. Jobs are asked in
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
        if hit(bot) then
            cur.NoteHit(bot)
            if bot:GetHealth() < bot:GetMaxHealth() * ____exports.SETTINGS.MinHpFraction then
                cur.End(bot, "retreat")
                return nil
            end
        end
        return ____exports.SETTINGS.JobDesire
    end
    local jobs = ranked(bot)
    do
        local i = 0
        while i < #jobs do
            local function blocked(b)
                local why = ____exports.MayStart(b)
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
    return nil
end
--- A number replaces OHA's desire for `mode`; undefined lets OHA's code run.
function ____exports.Decide(bot, mode)
    if not Ours.On("JobChooser") then
        return nil
    end
    if mode == ____exports.HOST then
        return hostDesire(bot)
    end
    if not ____exports.Running(bot) or ____exports.EXCEPTIONS[mode] ~= nil then
        return nil
    end
    return 0
end
--- Wraps a mode file's GetDesire. 0, never nil: nil falls through to Valve's built-in desire for that mode.
function ____exports.Gate(bot, mode, inner)
    return function()
        local v = ____exports.Decide(bot, mode)
        return v ~= nil and v or inner()
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
        local ____table_Step_result_1
        if (runningJob(bot) or STACK).Step(bot, ____exports.HOST_MODE) then
            ____table_Step_result_1 = nil
        else
            ____table_Step_result_1 = inner()
        end
        return ____table_Step_result_1
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
    local ____opt_2 = runningJob(bot)
    if ____opt_2 ~= nil then
        ____opt_2.End(bot, why)
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
-- An enemy hero in reach lifts it so the bot can fight or save itself. Benched heroes (Overrides.Solo) never cast, nor does
-- anyone in a lane-only game (Overrides.LaneOnly: spells on creeps would change the last-hit contest under test).
function ____exports.HoldsCasts(bot)
    if StackJob.Benched(bot) or Overrides.LaneOnly() then
        return true
    end
    if not ____exports.Running(bot) then
        return false
    end
    return #(bot:GetNearbyHeroes(____exports.SETTINGS.EnemyRadius, true, BotMode.None) or ({})) == 0
end
--- jmz_func CheckBotIdleState (called from team_roam's GetDesire whatever mode is active): a bot in farm mode that moved
-- under 100 in 3 s gets ClearActions and an attack-move to its lane front. A stack job stands still at its stand point by
-- design, and when the check fell inside the 2 s after the hit order it replaced the attack: all 4 slice 4 `no-aggro` misses
-- (attack-move from the order to the miss, s4 A_on_1 5:55 and 7:53, s4r3 C_on_3 7:54, s4x1 A_on_1 5:55). True while the job
-- runs, counted on the attempt.
function ____exports.HoldsIdle(bot)
    local cur = runningJob(bot)
    if cur == nil then
        return false
    end
    cur.NoteIdleHeld(bot)
    return true
end
--- Overrides.Solo (test harness): a benched hero holds farm mode and sits in its fountain.
function ____exports.Benched(bot)
    return StackJob.Benched(bot)
end
function ____exports.Bench(bot)
    return StackJob.Bench(bot)
end
return ____exports
