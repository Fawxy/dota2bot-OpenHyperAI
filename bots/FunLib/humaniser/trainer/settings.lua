--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
____exports.DEFAULTS = {
    Enable = true,
    Bar = true,
    BarStyle = "time",
    OutcomeOnly = false,
    ScreenText = true,
    Denies = true,
    Chat = "off",
    EasyWindow = 0.3,
    Checkpoints = {300, 600},
    SelfTest = false,
    TextX = 560,
    TextY = 40,
    WatchInterval = 0.1,
    MaxWatched = 2
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
        local isList = d ~= nil and type(d) == "table" and d[1] ~= nil
        local ____k_1 = k
        local ____temp_0
        if d ~= nil and type(d) == "table" and type(v) == "table" and not isList then
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
        local ____merge_4 = merge
        local ____opt_2 = Config.Get().Trainer
        cached = ____merge_4(____exports.DEFAULTS, ____opt_2 and ____opt_2.LastHit)
    end
    return cached
end
function ____exports.IsEnabled()
    return Config.IsEnabled() and ____exports.Get().Enable == true
end
return ____exports
