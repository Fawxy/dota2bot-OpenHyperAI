--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local rotationProbes = {}
local stackedProbes = {}
local busyProbes = {}
local override
local cautionProbe
local positionProbe
local tradeProbe
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
--- Registered by the transitions caution (task 12): a cautious core never picks SHOVE.
function ____exports.SetCautionProbe(fn)
    cautionProbe = fn
end
function ____exports.IsCautious(bot)
    return cautionProbe ~= nil and cautionProbe(bot)
end
function ____exports.SetPositionProbe(fn)
    positionProbe = fn
end
--- The final lane move point; `loc` itself when no probe applies.
function ____exports.PositionOverride(bot, loc)
    return positionProbe ~= nil and positionProbe(bot, loc) or loc
end
function ____exports.SetTradeProbe(fn)
    tradeProbe = fn
end
function ____exports.TradesSuppressed(bot)
    return tradeProbe ~= nil and tradeProbe(bot)
end
function ____exports.ResetHooks()
    rotationProbes = {}
    stackedProbes = {}
    busyProbes = {}
    override = nil
    cautionProbe = nil
    positionProbe = nil
    tradeProbe = nil
end
return ____exports
