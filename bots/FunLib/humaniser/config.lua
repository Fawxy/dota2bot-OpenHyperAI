--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
____exports.DEFAULTS = {
    Enable = true,
    Debug = false,
    ValveWeight = 0.5,
    FretWeight = 0.5,
    SkillOverride = nil,
    FretBridge = {FretBotsLevelOverride = nil, BridgeModifier = nil},
    Profile = {
        PersonalMin = 0.85,
        PersonalMax = 1.15,
        NoticeLow = 0.55,
        NoticeHigh = 0.18,
        ReactLow = 0.5,
        ReactHigh = 0.17,
        PingLow = 2,
        PingHigh = 0.8,
        ChatLow = 2,
        ChatHigh = 1,
        JitterLow = 0.45,
        JitterHigh = 0.2,
        LapseLow = 0.15,
        LapseHigh = 0.02,
        LapseMinExtra = 0.3,
        LapseMaxExtra = 0.8,
        AimErrorLow = 250,
        AimErrorHigh = 40,
        MinReact = 0.17
    },
    Orders = {DesireFloor = 0.85, AckCooldown = 20},
    Perception = {Enable = true},
    AllyLastHit = {Enable = true},
    Pings = {Enable = true},
    Commands = {Enable = true}
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
        local merged = merge(____exports.DEFAULTS, Customize.Humaniser)
        if Customize.Enable == false then
            merged.Enable = false
        end
        cached = merged
    end
    return cached
end
function ____exports.IsEnabled()
    return ____exports.Get().Enable == true
end
--- True when the humaniser and the named sub-feature are both enabled.
function ____exports.IsFeatureEnabled(feature)
    local cfg = ____exports.Get()
    return cfg.Enable == true and cfg[feature] ~= nil and cfg[feature].Enable == true
end
return ____exports
