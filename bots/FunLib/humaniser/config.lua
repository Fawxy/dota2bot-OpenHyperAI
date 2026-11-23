--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
____exports.DEFAULTS = {
    Enable = true,
    Debug = false,
    TickEvery = 3,
    Telemetry = {Enable = false},
    Tasks = {Enable = true}
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
            merged.Telemetry = ____exports.DEFAULTS.Telemetry
        end
        cached = merged
    end
    return cached
end
--- Game time as the humaniser's game-phase logic sees it: DotaTime() plus Customize.Overrides.ClockOffset (scenario
-- games fake "10:00 in" this way, since the real clock can't be set). Only for "which part of the game is it" reads;
-- anything synced to world timers (camp spawns, runes, waves) and relative timers must keep raw DotaTime().
function ____exports.Now()
    local ____opt_2 = Customize.Overrides
    if ____opt_2 ~= nil then
        ____opt_2 = ____opt_2.ClockOffset
    end
    local offset = ____opt_2
    return DotaTime() + (type(offset) == "number" and offset or 0)
end
function ____exports.IsEnabled()
    return ____exports.Get().Enable == true
end
return ____exports
