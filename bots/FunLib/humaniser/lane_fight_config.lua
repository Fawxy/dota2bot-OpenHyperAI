--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
____exports.DEFAULTS = {
    Enable = true,
    Memory = true,
    Trade = true,
    Kill = true,
    CallKills = true,
    Teams = "all",
    ShareMemory = false,
    UseCastCallback = false,
    PollInterval = 0.1,
    KillCheckEvery = 0.5,
    WindowReadEvery = 0.25,
    KeyThreatsWindow = 0.5,
    BlinkJump = 600,
    LevelSpikeMin = 10,
    LevelSpikeMax = 15,
    OutOfPosition = 400,
    FrontsMeetDistance = 1500,
    TradeDuration = 2.5,
    TradeHits = 3,
    CommitMax = 8,
    StartHP = 0.5,
    StartMaxRetreat = 0.7,
    StopHP = 0.3,
    FogGrace = 1,
    TradeFloor = 0.75,
    CommitFloor = 0.82,
    CommitFocusMargin = 0.01,
    CommitHoldHP = 0.5,
    TowerOverride = 1.3,
    FollowMargin = 0.8,
    InRangeWindow = 2.5,
    Overwhelming = 1.5,
    SoloSkill = 0.7,
    CallCooldown = 30,
    Curves = {
        RememberUlt = {0.6, 0.98},
        RememberKey = {0.35, 0.9},
        RememberOther = {0.1, 0.6},
        TimingError = {0.35, 0.05},
        ForgetWindow = {20, 90},
        ShareLoss = {0.3, 0.05},
        Notice = {0.3, 0.9},
        BurstError = {0.3, 0.05},
        AbortNotice = {0.8, 0.15},
        SyncDelay = {0.6, 0.1}
    }
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
            Config.Get().LaneFight
        )
    end
    return cached
end
function ____exports.ResetSettings()
    cached = nil
end
local function isEnabled()
    return Config.IsFeatureEnabled("LaneFight")
end
function ____exports.IsOn(flag)
    return isEnabled() and LaneConfig.IsActive() and ____exports.Settings()[flag] == true
end
--- Lane fights read the Lane feature's perception-filtered enemy list, so they need it active.
function ____exports.IsActive()
    if not isEnabled() or not LaneConfig.IsActive() then
        return false
    end
    local s = ____exports.Settings()
    return s.Memory == true or s.Trade == true or s.Kill == true
end
local function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end
function ____exports.Curve(name, skill)
    local c = ____exports.Settings().Curves[name]
    return c[1] + (c[2] - c[1]) * clamp01(skill)
end
function ____exports.AppliesTo(bot)
    local teams = ____exports.Settings().Teams
    if teams == "allies" then
        return Difficulty.IsAllyOfHuman(bot)
    end
    if teams == "enemies" then
        return not Difficulty.IsAllyOfHuman(bot)
    end
    return true
end
return ____exports
