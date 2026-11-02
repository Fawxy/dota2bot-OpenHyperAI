--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
____exports.SETTINGS = {JobDesire = 0.92, MinHpFraction = 0.5, EnemyRadius = 600, HitWithin = 3}
--- The mode that hosts a running job.
____exports.HOST_MODE = BotMode.Farm
--- Hero damage just now, checked every frame of a running job (1x probe s4p7: the pos5 was hit at 61% on the walk, kept
-- going and died at the camp to two heroes). Not an enemy hero in reach: lane opponents walk within 600 of a laning pos5,
-- and that check ended 4 jobs 1-6 s after their start (probe s4p8). Not HP or mode: the camp's neutrals hit the bot by
-- design, and the mode is ours.
local function hit(bot)
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
--- mode_farm_generic GetDesire: the job's desire while it runs or as it starts, else 0 (OHA decides). A hero hit ends a
-- running job.
function ____exports.FarmDesire(bot)
    if not StackJob.Wants(bot, ____exports.MayStart, ____exports.HOST_MODE) then
        return 0
    end
    if StackJob.Running(bot) and hit(bot) then
        StackJob.End(bot, "hit")
        return 0
    end
    return ____exports.SETTINGS.JobDesire
end
--- mode_farm_generic Think: steps the job; false when none runs.
function ____exports.FarmThink(bot)
    return StackJob.Step(bot, ____exports.HOST_MODE)
end
--- OHA's farm-mode run (or any host abort) ends the job; its line reports `cancelled:<why>`.
function ____exports.Abort(bot, why)
    StackJob.End(bot, why)
end
--- mode_farm_generic's ShouldRun: neutrals hitting the hero during its job are not a reason to run; the job's exit is its
-- retreat. OHA's creep clause (level < 5, hit by a creep, HP < 0.7) cancelled 5 of 9 attempts after the hit (probe s4p4).
function ____exports.HoldsRun(bot)
    return StackJob.Running(bot)
end
--- ability_item_usage: spells and items wait while the job runs, as camp_jobs' HoldsCasts does for camp jobs. OHA's farm
-- branches cast on the camp: witch doctor's cask landed at :42-:47, before the hit, and once after it, and the stunned
-- neutrals walked back into the box (user replay and s4solo2); a TP scroll on the walk stalled the job (s4solo2 5:4x).
-- An enemy hero in reach lifts it so the bot can fight or save itself. Benched heroes (Overrides.Solo) never cast.
function ____exports.HoldsCasts(bot)
    if StackJob.Benched(bot) then
        return true
    end
    if not StackJob.Running(bot) then
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
    if not StackJob.Running(bot) then
        return false
    end
    StackJob.NoteIdleHeld(bot)
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
