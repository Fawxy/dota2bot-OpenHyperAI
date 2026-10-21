--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local rotationProbes = {}
local stackedProbes = {}
local busyProbes = {}
local override
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
--- Registered by modules that commit the bot to a kill setup or similar (task 11); read by the transitions IsBusy.
function ____exports.SetBusyProbe(fn)
    busyProbes[#busyProbes + 1] = fn
end
function ____exports.IsBusyByProbe(bot)
    for ____, probe in ipairs(busyProbes) do
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
function ____exports.ResetHooks()
    rotationProbes = {}
    stackedProbes = {}
    busyProbes = {}
    override = nil
end
return ____exports
