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
local LaneFightConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_config")
function ____exports.Paid(bot, h)
    local forced = Drill.RigCreepAggro()
    if forced ~= nil then
        return forced
    end
    local radius = LaneFightConfig.Settings().CreepAggroRadius
    local at = h:GetLocation()
    return __TS__ArraySome(
        bot:GetNearbyLaneCreeps(1600, false) or ({}),
        function(____, c) return c:IsAlive() and GetUnitToLocationDistance(c, at) <= radius end
    )
end
return ____exports
