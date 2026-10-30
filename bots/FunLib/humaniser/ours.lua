--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArraySort(self, compareFn)
    if compareFn ~= nil then
        table.sort(
            self,
            function(a, b) return compareFn(nil, a, b) < 0 end
        )
    else
        table.sort(self)
    end
    return self
end

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local Customize
function ____exports.On(feature)
    if Customize.Enable == false then
        return false
    end
    local ____opt_0 = Customize.Ours
    if ____opt_0 ~= nil then
        ____opt_0 = ____opt_0[feature]
    end
    local value = ____opt_0
    if value == nil or value == nil then
        return ____exports.DEFAULTS[feature]
    end
    return value == true
end
Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
____exports.DEFAULTS = {LeaveCoreCreep = true, StackExecute = true, DoubleStack = true, CoreLastHit = false}
--- Every switch's value as `Name:1|0` in name order (telemetry: which arm a game ran when no --set shows it).
function ____exports.Describe()
    local names = {}
    for name in pairs(____exports.DEFAULTS) do
        names[#names + 1] = name
    end
    __TS__ArraySort(names)
    return table.concat(
        __TS__ArrayMap(
            names,
            function(____, n) return (n .. ":") .. tostring(____exports.On(n) and 1 or 0) end
        ),
        ","
    )
end
return ____exports
