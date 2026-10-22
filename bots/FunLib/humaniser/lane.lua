--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local nearestVisibleEnemy
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LanePlanner = require(GetScriptDirectory().."/FunLib/humaniser/lane_planner")
local LaneMid = require(GetScriptDirectory().."/FunLib/humaniser/lane_mid")
local LaneTech = require(GetScriptDirectory().."/FunLib/humaniser/lane_tech")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local PullTiming = require(GetScriptDirectory().."/FunLib/humaniser/pull_timing")
local Stacking = require(GetScriptDirectory().."/FunLib/humaniser/stacking")
local Harass = require(GetScriptDirectory().."/FunLib/humaniser/harass")
local Counter = require(GetScriptDirectory().."/FunLib/humaniser/counterplay")
local LaneDebug = require(GetScriptDirectory().."/FunLib/humaniser/lane_debug")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local ____commands = require(GetScriptDirectory().."/FunLib/humaniser/commands")
local teamMembers = ____commands.teamMembers
function nearestVisibleEnemy(bot, s)
    local best
    local bestDist = LaneConfig.Settings().Radii.LaneCreep
    for ____, e in ipairs(LaneState.Enemies(bot, s.lane)) do
        do
            local __continue27
            repeat
                if not e.visible or e.unit == nil then
                    __continue27 = true
                    break
                end
                local d = GetUnitToLocationDistance(bot, e.location)
                if d < bestDist then
                    best = e.unit
                    bestDist = d
                end
                __continue27 = true
            until true
            if not __continue27 then
                break
            end
        end
    end
    return best
end
____exports.Config = LaneConfig
____exports.Hooks = LaneHooks
____exports.Camps = Camps
____exports.LaneState = LaneState
____exports.LaneRoles = LaneRoles
____exports.LanePlan = LanePlan
____exports.LanePlanner = LanePlanner
____exports.LaneMid = LaneMid
____exports.LaneTech = LaneTech
____exports.CampJobs = CampJobs
____exports.PullTiming = PullTiming
____exports.Stacking = Stacking
____exports.Harass = Harass
____exports.Counter = Counter
function ____exports.IsEnabled()
    return LaneConfig.IsEnabled()
end
function ____exports.SetHelpers(h)
    LaneConfig.SetHelpers(h)
end
function ____exports.Tick(bot)
    LaneDebug.Tick(bot)
    local snapshot = LaneState.ForBot(bot)
    if snapshot == nil then
        return
    end
    Counter.Tick(bot)
    CampJobs.CoverTick(bot)
    if HDebug.IsEnabled() then
        local state = LaneState.Describe(
            snapshot,
            LaneState.ScoreFor(bot, snapshot)
        )
        HDebug.Text(
            bot,
            "lane",
            (state .. " ") .. LanePlan.Describe(LanePlan.View(bot, snapshot))
        )
    end
end
--- Whether this bot's laning Think() is OHA's (decided once at mode-file load, like AllyLastHit.OwnsLaning).
function ____exports.OwnsLaning(bot)
    return LaneTech.OwnsLaning(bot)
end
local function mayTouchAny(bot, creeps)
    for ____, creep in ipairs(creeps) do
        if not LaneMid.MayTouchWave(bot, creep) then
            return false
        end
    end
    return true
end
--- False when any of these creeps is a human mid's wave this bot must leave alone (deny included).
function ____exports.MayDeny(bot, allyCreeps)
    return mayTouchAny(bot, allyCreeps)
end
--- Runs before last hits; true means this frame's action is issued.
function ____exports.PreThink(bot, allyCreeps, enemyCreeps, enemies)
    if not mayTouchAny(bot, enemyCreeps) then
        local touchable = {}
        for ____, c in ipairs(allyCreeps) do
            if LaneMid.MayTouchWave(bot, c) then
                touchable[#touchable + 1] = c
            end
        end
        return LaneTech.TowerDropThink(bot, touchable)
    end
    return LaneTech.PreThink(bot, allyCreeps, enemyCreeps, enemies)
end
--- Runs after last hit and deny; true means this frame's action is issued.
function ____exports.Think(bot, allyCreeps, enemyCreeps, enemies)
    if not mayTouchAny(bot, enemyCreeps) then
        return false
    end
    if LaneTech.Think(bot, allyCreeps, enemyCreeps, enemies) then
        return true
    end
    return Counter.Think(bot, enemies)
end
--- Lane position override for the final move; returns `loc` itself when nothing applies.
function ____exports.AdjustPosition(bot, loc)
    local adjusted = LaneTech.AdjustPosition(bot, loc)
    if adjusted == loc then
        adjusted = Counter.AdjustPosition(bot, loc)
    end
    if adjusted ~= loc or not LaneConfig.IsOn("Harass") or CampJobs.Covering(bot) then
        return adjusted
    end
    local s = LaneState.ForBot(bot)
    if s == nil or LanePlan.View(bot, s).handsOff then
        return loc
    end
    local enemy = nearestVisibleEnemy(bot, s)
    if enemy == nil then
        return loc
    end
    return Harass.StandPoint(bot, enemy, s.ally.units) or loc
end
function ____exports.PickDeny(bot, allyCreeps)
    return LaneMid.PickDeny(bot, allyCreeps)
end
--- With Lane.Harass on, every bot whose laning Think() 04 or 07 owns uses the shared harass tool instead of 04's.
function ____exports.SupersedesHarass(_bot)
    return LaneConfig.IsActive() and LaneConfig.IsOn("Harass")
end
--- 04's Harass step for a superseded bot; `etiquette` is true when 04 owns the bot (an ally of a human).
function ____exports.HarassThink(bot, allyCreeps, enemyCreeps, enemies, etiquette)
    if CampJobs.Covering(bot) then
        return false
    end
    return Harass.Think(
        bot,
        allyCreeps,
        enemyCreeps,
        enemies,
        etiquette
    )
end
--- mode_farm_generic GetDesire: a camp job's desire, 0 when no job runs (and before any engine call when off).
function ____exports.CampJobDesire(bot)
    return CampJobs.Desire(bot)
end
local JOB_FOCUS_MODES = {
    BotMode.Ward,
    BotMode.TeamRoam,
    BotMode.Roam,
    BotMode.Rune,
    BotMode.SideShop,
    BotMode.SecretShop
}
--- mode_farm_generic GetDesire's return for a running job (`desire` from CampJobDesire). With intent arbitration
-- the job's desire is a same-frame CAMP_JOB floor over a raw 0, so survival and order claims outrank it and the
-- survival cap treats it as lifted; a second claim keeps the active mode's stickiness from making the pull late.
-- Without intent, or for a unit intent leaves out, it is the desire itself.
function ____exports.CampJobRawDesire(bot, desire)
    local job = CampJobs.Current(bot)
    local kind = job and job.kind or "job"
    if not Intent.Claim(
        bot,
        {
            source = "lane:" .. kind,
            tier = "CAMP_JOB",
            mode = BotMode.Farm,
            floor = desire,
            ["until"] = GameTime()
        }
    ) then
        return desire
    end
    if job ~= nil and (job.phase == "travel" or job.phase == "wait" or job.phase == "aggro") then
        Intent.Claim(bot, {source = "lane:camp_job", tier = "CAMP_JOB", mode = BotMode.Farm, unsticks = true})
    else
        Intent.Release(bot, "lane:camp_job", BotMode.Farm)
    end
    local cap = desire - LaneConfig.Settings().Thresholds.JobFocusMargin
    for ____, mode in ipairs(JOB_FOCUS_MODES) do
        Intent.Claim(bot, {source = "lane:job_focus", tier = "CAMP_JOB", mode = mode, cap = cap})
    end
    if CampJobs.HoldsRetreat(bot) then
        Intent.Claim(bot, {source = "lane:job_hold", tier = "CAMP_JOB", mode = BotMode.Retreat, cap = cap})
    else
        Intent.Release(bot, "lane:job_hold", BotMode.Retreat)
    end
    return 0
end
--- mode_farm_generic's ShouldRun: neutrals hitting a bot leading a pull are not a reason to run.
function ____exports.CampJobHoldsRetreat(bot)
    return CampJobs.HoldsRetreat(bot)
end
--- ability_item_usage_generic: no spells or items on the camp a job is working.
function ____exports.CampJobHoldsCasts(bot)
    return CampJobs.HoldsCasts(bot)
end
--- mode_farm_generic Think: true when the camp job owns this frame.
function ____exports.CampJobThink(bot)
    return CampJobs.Think(bot)
end
--- mode_laning_generic's last-hit desire yields to a running camp job.
function ____exports.CampJobActive(bot)
    return CampJobs.Active(bot)
end
function ____exports.CampJobOnEnd(bot)
    CampJobs.OnEnd(bot)
end
--- mode_farm_generic: a run started, so the camp job it would no longer execute ends now.
function ____exports.CampJobAbort(bot, reason)
    CampJobs.Abort(bot, reason)
end
--- mode_rune_generic GetDesire floor: a mid bot contesting the rune after spotting the enemy mid's pre-rune shove.
function ____exports.RuneContestDesire(bot)
    return Counter.RuneContestDesire(bot)
end
--- mode_farm_generic: a camp an enemy was seen stacking, or undefined to keep the farm pick.
function ____exports.PreferStackedCamp(bot, camps)
    return Counter.PreferStackedCamp(bot, camps)
end
local function nearestBot(team, issuer)
    local best
    local bestDist = math.huge
    for ____, member in ipairs(teamMembers(team)) do
        do
            local __continue53
            repeat
                if not member:IsBot() or not member:IsAlive() then
                    __continue53 = true
                    break
                end
                local d = GetUnitToLocationDistance(
                    member,
                    issuer:GetLocation()
                )
                if d < bestDist then
                    best = member
                    bestDist = d
                end
                __continue53 = true
            until true
            if not __continue53 then
                break
            end
        end
    end
    return best
end
LaneDebug.Register(
    "hpulltest",
    function(team, issuer, args)
        local campIdx = tonumber(args[1])
        if campIdx == nil then
            HDebug.Log("lane", "hpulltest usage: !hpulltest <idx> [half]")
            return
        end
        local best = nearestBot(team, issuer)
        if best == nil then
            HDebug.Log("lane", "hpulltest no bot")
            return
        end
        local kind = args[2] == "half" and "half_pull" or "full_pull"
        local ok = CampJobs.Start(best, {kind = kind, campIdx = campIdx, forced = true})
        HDebug.Log(
            "lane",
            (((((("hpulltest pid=" .. tostring(best:GetPlayerID())) .. " camp=") .. tostring(campIdx)) .. " kind=") .. kind) .. " started=") .. tostring(ok)
        )
    end
)
LaneDebug.Register(
    "hstacktest",
    function(team, issuer, args)
        local campIdx = tonumber(args[1])
        if campIdx == nil then
            HDebug.Log("lane", "hstacktest usage: !hstacktest <idx>")
            return
        end
        local best = nearestBot(team, issuer)
        if best == nil then
            HDebug.Log("lane", "hstacktest no bot")
            return
        end
        local ok = CampJobs.Start(best, {kind = "stack", campIdx = campIdx, forced = true})
        HDebug.Log(
            "lane",
            (((("hstacktest pid=" .. tostring(best:GetPlayerID())) .. " camp=") .. tostring(campIdx)) .. " started=") .. tostring(ok)
        )
    end
)
return ____exports
