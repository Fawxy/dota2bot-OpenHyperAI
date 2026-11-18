--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArraySome(self, callbackfn, thisArg)
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            return true
        end
    end
    return false
end
-- End of Lua Library inline imports
local ____exports = {}
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
--- Enemy creeps within this of a hero turn on whoever attacks within it (docs/reference/specifics/creep-aggro-numbers.md).
local CREEP_AGGRO_RADIUS = 500
function ____exports.Paid(bot, h)
    local forced = Drill.RigCreepAggro()
    if forced ~= nil then
        return forced
    end
    local at = h:GetLocation()
    return __TS__ArraySome(
        bot:GetNearbyLaneCreeps(1600, false) or ({}),
        function(____, c) return c:IsAlive() and GetUnitToLocationDistance(c, at) <= CREEP_AGGRO_RADIUS end
    )
end
return ____exports
