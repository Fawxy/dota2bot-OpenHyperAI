--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local rotationProbes = {}
local stackedProbes = {}
local override
local fightProbes = {}
function ____exports.SetRotationProbe(fn)
    rotationProbes[#rotationProbes + 1] = fn
end
function ____exports.IsRotationPlanned(bot)
    for ____, probe in ipairs(rotationProbes) do
        if probe(bot) then
            return true
        end
    end
    return false
end
function ____exports.SetStackedProbe(fn)
    stackedProbes[#stackedProbes + 1] = fn
end
function ____exports.IsStacked(campIdx)
    for ____, probe in ipairs(stackedProbes) do
        if probe(campIdx) then
            return true
        end
    end
    return false
end
function ____exports.SetTechniqueOverride(fn)
    override = fn
end
function ____exports.TechniqueOverride(bot)
    local ____temp_0
    if override ~= nil then
        ____temp_0 = override(bot)
    else
        ____temp_0 = nil
    end
    return ____temp_0
end
--- lane_fight registers this: camp jobs must not start while the bot is committed to a lane kill.
function ____exports.SetFightProbe(fn)
    fightProbes[#fightProbes + 1] = fn
end
function ____exports.IsFightCommitting(bot)
    for ____, probe in ipairs(fightProbes) do
        if probe(bot) then
            return true
        end
    end
    return false
end
function ____exports.ResetHooks()
    rotationProbes = {}
    stackedProbes = {}
    override = nil
    fightProbes = {}
end
return ____exports
