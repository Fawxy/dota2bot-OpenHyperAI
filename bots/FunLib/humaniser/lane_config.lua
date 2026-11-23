--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local isArray, merge, cached, phaseAt
local GameRules = require(GetScriptDirectory().."/FunLib/humaniser/game_rules")
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
function isArray(t)
    return t[1] ~= nil
end
function merge(defaults, overrides)
    if overrides == nil or overrides == nil or type(overrides) ~= "table" then
        return defaults
    end
    local result = {}
    for k, v in pairs(defaults) do
        result[k] = v
    end
    for k, v in pairs(overrides) do
        local d = defaults[k]
        local ____k_1 = k
        local ____temp_0
        if d ~= nil and type(d) == "table" and type(v) == "table" and not isArray(d) then
            ____temp_0 = merge(d, v)
        else
            ____temp_0 = v
        end
        result[____k_1] = ____temp_0
    end
    return result
end
function ____exports.Settings()
    if cached == nil then
        cached = merge(
            ____exports.DEFAULTS,
            Config.Get().Lane
        )
    end
    return cached
end
____exports.DEFAULTS = {
    ForecastModel = {K = 0.4, TypeWeight = {melee = 1, ranged = 1.6, siege = 1}, PowerFloor = 550},
    Gates = {
        Block = 0.3,
        FullPull = 0.3,
        StackPull = 0.75,
        AggroPull = 0.5,
        Freeze = 0.7,
        Shove = 0.4,
        SoloCampJob = 0.6,
        MultiStackAncients = 0.7
    },
    Curves = {
        JitterSigma = {1.5, 0},
        AttemptRate = {0.15, 1},
        PathNoise = {150, 0},
        StackAttempt = {0.2, 1},
        CounterNotice = {0.2, 1},
        PlanMisread = {0.3, 0},
        CoverAbsentCore = {0.3, 1},
        Foresight = {0, 1},
        SureCommit = {0.5, 1}
    },
    Eq = {
        Safe = -0.7,
        Off = -0.7,
        Mid = -0.1,
        MidPreRune = 0.15,
        XpDenyWeight = 0.2
    },
    Planner = {FullPullBelow = -0.5, AggroCorrectBelow = -0.15, AggroStepEq = 0.15},
    Timing = {
        SnapshotRefresh = 0.5,
        WaveCycle = GameRules.WAVE_EVERY,
        BlockEnd = 30,
        StackMoveFrom = 45,
        StackExitUntil = 1,
        StackOutcomeAt = 2,
        StackOutcomeUntil = 5,
        StackEarlyBefore = 52,
        StackLateAfter = 57,
        StackAssumedFrom = 53,
        StackAssumedTo = 56,
        StackFromValve = true,
        StackWindowAt = 0.5,
        JobDesire = 0.7,
        JobCommitDesire = 0.96,
        SupplySlack = 1.5,
        SupplyWait = 1.5,
        PartnerHPWindow = 2,
        PartnerBailConfirm = 0.4,
        JobStartSlack = 3,
        JobStartLate = 2,
        JobMaxAfterAggro = 15,
        JobPreemptAfter = 1,
        JobHoldHeroHit = 1.5,
        JobStartHeroHit = 2,
        JobUpcoming = 10,
        MaxTravel = 12,
        LanerSeenMin = 10,
        LanerSeenGap = 1,
        EqSampleAt = 10,
        WatchSec = 8,
        WatchEvery = 0.25,
        PullPeriod = GameRules.NEUTRAL_EVERY,
        NeutralFirstSpawn = GameRules.NEUTRAL_FIRST,
        NoCampAfter = 1,
        AggroConfirm = 2,
        AggroLeadDefault = 0.4,
        AggroLeadMax = 1.5,
        StandApproachLead = 3,
        DoublePullHitGap = 1,
        DoublePullMaxGap = 6,
        DoublePullJoin = 3,
        PingHandsOff = 30,
        PlanSustain = 5,
        PlanMinDwell = 15,
        HumanPullWindow = 6,
        CounterUnseen = 4,
        CounterPullWindow = 3,
        CounterWaveLate = 5,
        CounterSignalTTL = 20,
        MidRuneShoveLookahead = 25,
        RuneContestAfter = 10,
        RuneContestDesire = 0.6,
        MarkedStackFor = 120,
        StackWatchFrom = 50,
        StackWatchTo = 58,
        StackOutsideUntil = 3,
        StackedCampSeen = 5,
        CounterForgetAfter = 120,
        PreRuneMin = 15,
        PreRuneMax = 20,
        PullTelegraphLead = 5,
        PullTelegraphCooldown = 60,
        StackTelegraphCooldown = 120,
        CounterTelegraphCooldown = 60,
        ExposureSeen = 3
    },
    Thresholds = {
        CoreAbsentDist = 1200,
        PartnerMinHP = 0.4,
        JobMinHP = 0.4,
        JobHoldMinHP = 0.5,
        JobStartHP = 0.65,
        JobMissingFresh = 20,
        TangoMinLost = 80,
        ClarityMinLost = 150,
        PartnerDangerEnemies = 2,
        PartnerDangerRadius = 1200,
        PartnerBailHP = 0.35,
        PartnerDiveLoss = 0.12,
        CoverRetreatScale = 1.25,
        JobFocusMargin = 0.02,
        SupportNearFront = 800,
        StableEnemyRadius = 1200,
        StableSeenWithin = 3,
        StableMinHP = 0.5,
        FullPullMin = 0.8,
        EnemyTowerRange = 844,
        HeroRadius = 24,
        ShoveMinHP = 0.5,
        FreezeDriftMargin = 0.2,
        MidTowerEq = 0.8,
        FreezeCoreEqMax = -0.3,
        MidMissingEq = -0.6,
        FreezeSuspectEq = 0.6,
        ThinWaveMargin = 2,
        WaveCreeps = 4,
        StackMaxCampCount = 1,
        ApproachEpsilon = 25,
        ExposureEnemies = 2
    },
    Radii = {
        LaneCreep = 1200,
        LaneAssign = 1200,
        AllyNearFront = 1600,
        Exposure = 1500,
        LaneFrontPing = 600,
        HumanPullRadius = 800,
        StepBackCreeps = 700,
        StepBackEps = 50,
        NeutralSearch = 700,
        JobEnemyHero = 1200,
        TangoTree = 300,
        JobStartEnemy = 800,
        StandOffset = 150,
        StandReach = 450,
        StandApproach = 150,
        ExitCheckStep = 300,
        PartnerDive = 700,
        CoverCamp = 1200,
        JobArrive = 100,
        LaneCreepScan = 1600,
        MeetWatch = 800,
        WaveSize = 1200,
        StackExit = 900,
        StackCoreCamp = 3000,
        StackSight = 1200,
        StackCountScan = 1600,
        EnemyNearCamp = 800,
        NeutralOutsideMargin = 200,
        PullCampLastSeen = 800,
        PullerNear = 300,
        StackedCampSafe = 1500,
        CounterNeutralScan = 1600,
        PullPathEdge = 150,
        BoxMargin = 300,
        Stronger = 1200,
        ApproachExtrapolate = 0.5
    },
    Infer = {
        ShoveHits = 4,
        FreezeDenies = 2,
        FreezeEqMax = -0.5,
        HoldSignals = 2,
        ShoveHitDamageMult = 1.3
    },
    Camps = {PullCampMaxTowerDist = 2500, PullCampMaxLaneDist = 2400, ReplayMatchRadius = 600, LaneSampleStep = 0.005},
    PullTiming = {
        FromWave = true,
        CreepSpeed = 325,
        NeutralSpeed = {small = 290, medium = 300, large = 300, ancient = 290},
        Lead = 1.5,
        WaveAhead = {safe = 3, off = -0.4},
        WaveSlots = {0, 30},
        PathMaxOffset = 500,
        LiveFrom = 2,
        LiveWindow = 5,
        LiveMaxOffset = 600,
        LiveMaxShift = 4,
        LiveEvery = 0.25,
        WatchAfterWave = 3,
        FullPast = 100,
        LanePaths = {}
    },
    Orders = {FreezeShove = 90, PullNoPull = 120, Stack = 60}
}
--- How far from an enemy tower a hero's centre can be attacked: the tower's attack range and radius plus the hero's radius
-- (the edges meet; 868 in 7.41), read from the game (world_facts), the Thresholds constants when a read fails.
function ____exports.TowerReach()
    local t = ____exports.Settings().Thresholds
    return WorldFacts.Reach(t.EnemyTowerRange) + WorldFacts.HeroRadius(t.HeroRadius)
end
--- The enemy tower's attack range alone (read from the game; 700 when the read fails).
function ____exports.TowerAttackRange()
    return WorldFacts.TowerAttackRange(700)
end
function ____exports.ResetSettings()
    cached = nil
end
local function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end
function ____exports.Curve(name, skill)
    local c = ____exports.Settings().Curves[name]
    return c[1] + (c[2] - c[1]) * clamp01(skill)
end
local rngSource
--- Set by tasks.ts (which imports this module, so the source is injected rather than required): returns the SDK Skill
-- once the tasks bundle is loaded, else undefined. Without one, draws fall back to RandomFloat (tasks off).
function ____exports.SetRng(source)
    rngSource = source
end
local function rng()
    local ____temp_2
    if rngSource ~= nil then
        ____temp_2 = rngSource()
    else
        ____temp_2 = nil
    end
    return ____temp_2
end
function ____exports.Gauss()
    local r = rng()
    if r ~= nil then
        return r.gauss()
    end
    local u1 = RandomFloat(0.000001, 1)
    local u2 = RandomFloat(0.000001, 1)
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end
function ____exports.Jitter(skill)
    return ____exports.Gauss() * ____exports.Curve("JitterSigma", skill)
end
--- One uniform [0, 1) draw from the engine's Skill rng, or undefined without the tasks bundle (no host fallback).
function ____exports.Draw()
    local r = rng()
    return r ~= nil and r.random() or nil
end
function ____exports.Roll(chance)
    local r = rng()
    return (r ~= nil and r.random() or RandomFloat(0, 1)) < chance
end
local helpers = {}
function ____exports.SetHelpers(h)
    helpers = h
    phaseAt = nil
end
function ____exports.Helpers()
    return helpers
end
function ____exports.PositionOf(unit)
    return helpers.GetPosition ~= nil and helpers.GetPosition(unit) or nil
end
local phaseBot
local phaseValue = false
--- OHA's answer, asked once per frame and bot: its helper scans every allied unit on each call (J.IsModeTurbo looks for the
-- courier) and reads the calling bot's net worth after the time floor, and our gates asked about a million times in ten
-- minutes (perf probe 16/11/2026: the largest single cost in our script).
function ____exports.InLaningPhase()
    local now = DotaTime()
    local ours = Config.Now()
    if ours ~= now then
        return ours < 600
    end
    if helpers.IsInLaningPhase == nil then
        return now < 600
    end
    local bot = GetBot ~= nil and GetBot() or nil
    if now == phaseAt and bot == phaseBot then
        return phaseValue
    end
    phaseValue = helpers.IsInLaningPhase()
    phaseAt = now
    phaseBot = bot
    return phaseValue
end
function ____exports.IsLaneCreepName(name)
    local function has(part)
        return (string.find(name, part, 1, true)) ~= nil
    end
    return has("creep_goodguys") or has("creep_badguys") or has("goodguys_siege") or has("badguys_siege")
end
--- True when the bot's team has at least one human player.
function ____exports.IsAllyOfHuman(bot)
    for ____, pid in ipairs(GetTeamPlayers(bot:GetTeam())) do
        if not IsPlayerBot(pid) then
            return true
        end
    end
    return false
end
return ____exports
