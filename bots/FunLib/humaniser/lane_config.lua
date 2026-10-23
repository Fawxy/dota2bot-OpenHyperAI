--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
____exports.DEFAULTS = {
    Enable = true,
    OwnLaningThink = "allies",
    Plan = true,
    Block = true,
    FullPull = true,
    HalfPull = true,
    StackPull = true,
    AggroPull = true,
    Freeze = true,
    Shove = true,
    Stack = true,
    Harass = true,
    Mid = true,
    CounterPlay = true,
    Telegraph = true,
    CampBlock = false,
    Forecast = true,
    PreContest = false,
    TakePull = true,
    PullLaneGate = true,
    ClashPull = true,
    ForecastModel = {K = 0.4, TypeWeight = {melee = 1, ranged = 1.6, siege = 1}, PowerFloor = 550},
    Gates = {
        Block = 0.3,
        FullPull = 0.3,
        HalfPull = 0.6,
        StackPull = 0.75,
        AggroPull = 0.5,
        Freeze = 0.7,
        Shove = 0.4,
        SoloCampJob = 0.6,
        MultiStackAncients = 0.7,
        CampBlock = 0.6,
        HarassPosition = 0.6,
        RandomHarass = 0.5,
        PreContest = 0.7,
        TakePull = 0.5,
        ClashPull = 0.7
    },
    Curves = {
        JitterSigma = {1.5, 0.2},
        AttemptRate = {0.15, 0.85},
        PathNoise = {150, 20},
        StackAttempt = {0.2, 0.9},
        HarassCapitalise = {0.25, 0.85},
        CounterNotice = {0.2, 0.8},
        PlanMisread = {0.3, 0.05},
        CoverAbsentCore = {0.3, 0.9},
        DoubleDraw = {0.2, 0},
        Foresight = {0, 1}
    },
    Eq = {
        Safe = -0.7,
        Off = -0.7,
        Mid = -0.1,
        MidPreRune = 0.15,
        XpDenyWeight = 0.2
    },
    Planner = {
        FullPullBelow = -0.5,
        SmallDriftBelow = -0.2,
        AggroCorrectBelow = -0.15,
        LargeWaveMargin = 2,
        AggroStepEq = 0.15
    },
    Timing = {
        SnapshotRefresh = 0.5,
        WaveCycle = 30,
        AggroWindow = 3,
        AggroCooldown = 2.3,
        WalkBack = 1.5,
        BlockEnd = 30,
        BlockLostSec = 2,
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
        ContestDesire = 0.65,
        ContestMax = 10,
        ContestAttackGap = 2.5,
        JobStartSlack = 3,
        JobStartLate = 2,
        JobMaxAfterAggro = 15,
        JobPreemptAfter = 1,
        JobHoldHeroHit = 1.5,
        JobStartHeroHit = 2,
        JobUpcoming = 10,
        MaxTravel = 12,
        PreContestLead = 2,
        PreContestWait = 4,
        PreContestCooldown = 60,
        LanerSeenMin = 10,
        LanerSeenGap = 1,
        TakePullMax = 15,
        TakePullWait = 3,
        TakePullSwing = 1,
        ClashRateWindow = 1.5,
        ClashWaitMax = 15,
        ClashWaveMargin = 3,
        EqSampleAt = 10,
        WatchSec = 8,
        WatchEvery = 0.25,
        PullPeriod = 60,
        NeutralFirstSpawn = 60,
        HalfPullLater = 2,
        NoCampAfter = 1,
        AggroConfirm = 2,
        AggroLeadDefault = 0.4,
        AggroLeadMax = 1.5,
        StandApproachLead = 3,
        DoublePullHitGap = 1,
        DoublePullMaxGap = 6,
        DoublePullJoin = 3,
        ShoveMaxSec = 8,
        PingHandsOff = 30,
        PlanSustain = 5,
        PlanMinDwell = 15,
        CoreYieldStagger = 1.5,
        HumanPullWindow = 6,
        CounterUnseen = 4,
        CounterPullWindow = 3,
        CounterRespondFresh = 4,
        CounterWaveLate = 5,
        CounterSignalTTL = 20,
        PunishGap = 2,
        PunishFor = 6,
        PathSafeSeen = 5,
        MidRuneShoveLookahead = 25,
        RuneContestAfter = 10,
        DropRangedDenyFor = 20,
        RuneContestDesire = 0.6,
        MarkedStackFor = 120,
        StackWatchFrom = 50,
        StackWatchTo = 58,
        StackOutsideUntil = 3,
        CampBlockFrom = 50,
        CampBlockTo = 58,
        StackedCampSeen = 5,
        CounterForgetAfter = 120,
        PreRuneMin = 15,
        PreRuneMax = 20,
        RandomHarassMin = 4,
        RandomHarassMax = 8,
        LowSkillHarassExtra = 1.5,
        AggroDanceBack = 1,
        BlockNoiseEvery = 1,
        CampBlockCooldown = 180,
        PullTelegraphLead = 5,
        PullTelegraphCooldown = 60,
        StackTelegraphCooldown = 120,
        CounterTelegraphCooldown = 60,
        ShoveTelegraphCooldown = 60,
        ExposureSeen = 3
    },
    Thresholds = {
        CoreAbsentDist = 1200,
        CoreBusyHP = 0.6,
        CoreBusyDamageMult = 1.3,
        PartnerMinHP = 0.4,
        JobMinHP = 0.4,
        JobHoldMinHP = 0.5,
        JobStartHP = 0.65,
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
        HalfPullMin = 0.3,
        HalfPullMax = 0.6,
        HarassExtraRange = 100,
        AggroDanceCreeps = 3,
        AggroDanceRadius = 500,
        HarassTowerLevel = 6,
        HarassTowerTargetHP = 0.3,
        EnemyTowerRange = 850,
        TakePullLaneCreeps = 1,
        TakePullDangerEnemies = 2,
        ClashAllyMin = 2,
        ShoveMinHP = 0.5,
        ShoveDoneCreeps = 1,
        TowerSwapAllyHP = 0.6,
        TowerSwapBotHP = 0.6,
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
        AggroDrawExtra = 200,
        AggroWalkBack = 300,
        AggroWalkMax = 400,
        BlockAhead = 120,
        BlockSide = 50,
        BlockStart = 1500,
        BlockLost = 400,
        BlockContact = 700,
        TowerAggro = 900,
        PreContestStand = 400,
        TowerExitMargin = 100,
        Zone = 900,
        ZoneOffset = 150,
        HoldMinBack = 250,
        HarassStandBack = 50,
        LowHpCreep = 700,
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
        MeetBusy = 800,
        WaveSize = 1200,
        StackExit = 900,
        StackCoreCamp = 3000,
        StackSight = 1200,
        StackCountScan = 1600,
        EnemyNearCamp = 800,
        NeutralOutsideMargin = 200,
        PullCampLastSeen = 800,
        PullerNear = 300,
        PathSafe = 1500,
        StackedCampSafe = 1500,
        ContestReach = 1200,
        TakePullCreeps = 800,
        TakePullDanger = 1200,
        ClashPullReach = 2000,
        ClashStandOff = 400,
        ClashFight = 600,
        CounterNeutralScan = 1600,
        MidFront = 1200,
        MidHuman = 1500,
        LaneActive = 2500,
        PullPathEdge = 150,
        BoxMargin = 300,
        AggroDanceStep = 250,
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
    Camps = {
        HalfMeetOffset = 500,
        PullCampMaxTowerDist = 2500,
        PullCampMaxLaneDist = 2400,
        ReplayMatchRadius = 600,
        LaneSampleStep = 0.005
    },
    PullTiming = {
        FromWave = true,
        CreepSpeed = 325,
        NeutralSpeed = {small = 290, medium = 300, large = 300, ancient = 290},
        Lead = 1.5,
        WaveSlots = {0, 30},
        PathMaxOffset = 500,
        LiveFrom = 2,
        LiveWindow = 5,
        LiveMaxOffset = 600,
        LiveMaxShift = 4,
        WatchAfterWave = 3,
        LanePaths = {}
    },
    Orders = {FreezeShove = 90, PullNoPull = 120, Stack = 60},
    HarassIdle = {IdleWindow = 1.2, IdleExtraRange = 300, IdleMinHP = 0.5, TowerAvoidRange = 850}
}
local FLAG_OF = {
    block = "Block",
    full_pull = "FullPull",
    half_pull = "HalfPull",
    stack_pull = "StackPull",
    aggro_pull = "AggroPull",
    freeze = "Freeze",
    shove = "Shove",
    stack = "Stack"
}
local GATE_OF = {
    block = "Block",
    full_pull = "FullPull",
    half_pull = "HalfPull",
    stack_pull = "StackPull",
    aggro_pull = "AggroPull",
    freeze = "Freeze",
    shove = "Shove",
    stack = nil
}
local CONSUMER_FLAGS = {
    "Plan",
    "Block",
    "FullPull",
    "HalfPull",
    "StackPull",
    "AggroPull",
    "Freeze",
    "Shove",
    "Stack",
    "Harass",
    "Mid",
    "CounterPlay",
    "CampBlock"
}
local function isArray(t)
    return t[1] ~= nil
end
local function merge(defaults, overrides)
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
local cached
function ____exports.Settings()
    if cached == nil then
        cached = merge(
            ____exports.DEFAULTS,
            Config.Get().Lane
        )
    end
    return cached
end
function ____exports.ResetSettings()
    cached = nil
end
function ____exports.IsEnabled()
    return Config.IsFeatureEnabled("Lane")
end
function ____exports.IsOn(flag)
    return ____exports.IsEnabled() and ____exports.Settings()[flag] == true
end
function ____exports.IsActive()
    if not ____exports.IsEnabled() then
        return false
    end
    for ____, flag in ipairs(CONSUMER_FLAGS) do
        if ____exports.Settings()[flag] == true then
            return true
        end
    end
    return false
end
function ____exports.GateFor(tech)
    local gate = GATE_OF[tech]
    return gate == nil and 0 or (____exports.Settings().Gates[gate] or 0)
end
function ____exports.Knows(tech, skill)
    return ____exports.IsOn(FLAG_OF[tech]) and skill >= ____exports.GateFor(tech)
end
local function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end
function ____exports.Curve(name, skill)
    local c = ____exports.Settings().Curves[name]
    return c[1] + (c[2] - c[1]) * clamp01(skill)
end
function ____exports.Gauss()
    local u1 = RandomFloat(0.000001, 1)
    local u2 = RandomFloat(0.000001, 1)
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2)
end
function ____exports.Jitter(skill)
    return ____exports.Gauss() * ____exports.Curve("JitterSigma", skill)
end
function ____exports.Roll(chance)
    return RandomFloat(0, 1) < chance
end
function ____exports.SkillOf(bot)
    return Profile.Get(bot).skill
end
function ____exports.OwnLaningMode()
    local mode = ____exports.Settings().OwnLaningThink
    return (mode == "allies" or mode == "all") and mode or "off"
end
local helpers = {}
function ____exports.SetHelpers(h)
    helpers = h
end
function ____exports.Helpers()
    return helpers
end
function ____exports.PositionOf(unit)
    return helpers.GetPosition ~= nil and helpers.GetPosition(unit) or nil
end
function ____exports.InLaningPhase()
    local ____temp_2
    if helpers.IsInLaningPhase ~= nil then
        ____temp_2 = helpers.IsInLaningPhase()
    else
        ____temp_2 = DotaTime() < 600
    end
    return ____temp_2
end
return ____exports
