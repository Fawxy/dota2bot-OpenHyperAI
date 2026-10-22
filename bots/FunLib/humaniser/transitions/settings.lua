--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
____exports.DEFAULTS = {
    Enable = true,
    MidRunes = true,
    Rotation = true,
    Caution = true,
    Teleports = true,
    LaneWard = true,
    Phase = true,
    LostLane = true,
    Refresh = 0.5,
    MidRuneFloor = 0.6,
    MidRuneFocus = 20,
    MidRuneLead = 15,
    MidRuneRadius = 3500,
    MidRuneCheckWindow = 15,
    MidRuneSpawnGrace = 1,
    MidRuneSkipDesire = 0.3,
    MidRuneSkipWindow = 10,
    BusyHP = 0.5,
    BusyMana = 0.3,
    HumanPingWindow = 30,
    LanePingRadius = 2000,
    BusyJobLead = 30,
    SpareEq = -0.2,
    SparePartnerHP = 0.6,
    SpareCreepAggro = 3,
    SpareSeenWithin = 5,
    Pos5PartnerHP = 0.75,
    Pos5EnemyRadius = 1200,
    SpareKillHP = 0.5,
    SpareKillMargin = 300,
    SpareLaneRadius = 3500,
    DecideFrom = 25,
    DecideTo = 20,
    ArriveLead = 4,
    RotateChance = {Low = 0.3, High = 0.9},
    ArriveSigma = {Low = 6, High = 1},
    MistakeChance = {Low = 0.15, High = 0},
    MidSupportRadius = 1500,
    MidContestDesire = 0.55,
    ContestRadius = 1800,
    ContestSeenWithin = 5,
    Pos5ContestEnemies = 2,
    ChatCooldown = 60,
    PathFactor = 1.2,
    LateSlack = 2,
    RotateLinger = 5,
    RotateFloor = 0.7,
    RotateHoldRadius = 300,
    RuneHoldEnemyRadius = 1200,
    RuneHoldGrace = 3,
    RuneHoldMax = 15,
    ContestFrom = 6,
    ContestMidRadius = 2500,
    MidContestFrom = 10,
    AloneMissing = 4,
    LaneMissing = 6,
    OffsetMin = 150,
    OffsetMax = 300,
    RetreatScaleMax = 1.3,
    AttackScaleMin = 0.7,
    SkillAmount = {Low = 0.5, High = 1},
    MissingCooldown = 30,
    AloneLevel = 0.5,
    AloneLevelPerEnemy = 0.25,
    SuppressLevel = 0.5,
    MissingMaxAge = 60,
    CautionStrongerRadius = 1200,
    MidMissingSignalWindow = 30,
    TpRadius = 1600,
    TpLinger = 2,
    TpSetupSkill = 0.7,
    TpSetupDistance = 600,
    TpTowerClear = 850,
    TpStrongerRadius = 1600,
    TpRefresh = 0.25,
    WardFrom = 150,
    WardTo = 270,
    WardChance = {Low = 0.4, High = 0.95},
    WardCoverRadius = 1600,
    WardAnchorRadius = 1500,
    WardScanPeriod = 5,
    WardFloor = 0.6,
    WardLive = 1,
    WardLifetime = 360,
    SupportLevel = 6,
    SupportFrom = 360,
    SupportTo = 480,
    LostWindow = 240,
    LostDeaths = 2,
    LostLevelGap = 2,
    SuggestCooldown = 60,
    JungleSeenWindow = 3,
    JungleCampRadius = 2500,
    LostPingRadius = 1500,
    AbsentHold = 10,
    LaningCap = 0.3
}
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
        if d ~= nil and type(d) == "table" and type(v) == "table" then
            ____temp_0 = merge(d, v)
        else
            ____temp_0 = v
        end
        result[____k_1] = ____temp_0
    end
    return result
end
local cached
function ____exports.Get()
    if cached == nil then
        cached = merge(
            ____exports.DEFAULTS,
            Config.Get().Transitions
        )
    end
    return cached
end
function ____exports.ResetSettings()
    cached = nil
end
function ____exports.IsActive()
    return Config.IsFeatureEnabled("Transitions")
end
function ____exports.IsOn(flag)
    return ____exports.IsActive() and ____exports.Get()[flag] == true
end
function ____exports.Lerp(pair, skill)
    local s = skill < 0 and 0 or (skill > 1 and 1 or skill)
    return pair.Low + (pair.High - pair.Low) * s
end
return ____exports
