--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Rune = ____dota.Rune
local ____game_rules = require(GetScriptDirectory().."/FunLib/humaniser/game_rules")
local RUNE_RULES = ____game_rules.RUNE_RULES
____exports.RUNE_RULES = RUNE_RULES
--- The first spawn time at or after `now`, or math.huge once the rune has stopped spawning.
function ____exports.NextSpawn(kind, now)
    local rule = RUNE_RULES[kind]
    local t = rule.first
    if now > t then
        t = t + math.ceil((now - t) / rule.every) * rule.every
    end
    if rule.last ~= nil and t > rule.last then
        return math.huge
    end
    return t
end
function ____exports.PowerSpots()
    return {
        GetRuneSpawnLocation(Rune.Power1),
        GetRuneSpawnLocation(Rune.Power2)
    }
end
--- The side is named by the spot's world position (y > 0 is top), not by the RUNE_POWERUP index.
function ____exports.NearestPowerSpot(loc)
    local spots = ____exports.PowerSpots()
    local best = spots[1]
    local bestD = math.huge
    for ____, spot in ipairs(spots) do
        local d = (spot.x - loc.x) ^ 2 + (spot.y - loc.y) ^ 2
        if d < bestD then
            bestD = d
            best = spot
        end
    end
    return best, best.y > 0 and "top" or "bot"
end
return ____exports
