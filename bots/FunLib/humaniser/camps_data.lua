--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
____exports.DEFAULT_STACK_SEC = {small = 54.5, medium = 54, large = 53.5, ancient = 53}
____exports.CAMP_DATA = {
    {
        key = "radiant_safe_small",
        team = 2,
        type = "small",
        laneKind = "safe",
        pullAggroSec = {15, 45},
        source = "seed"
    },
    {
        key = "dire_safe_small",
        team = 3,
        type = "small",
        laneKind = "safe",
        pullAggroSec = {15, 45},
        source = "seed"
    },
    {
        key = "radiant_safe_large",
        team = 2,
        type = "large",
        laneKind = "safe",
        pullAggroSec = {18, 48},
        source = "seed"
    },
    {
        key = "dire_safe_large",
        team = 3,
        type = "large",
        laneKind = "safe",
        pullAggroSec = {18, 48},
        source = "seed"
    },
    {
        key = "radiant_off_large",
        team = 2,
        type = "large",
        laneKind = "off",
        enemySide = true,
        maxTowerDist = 2800,
        meetBack = 600,
        pullAggroSec = {18, 48},
        source = "seed",
        unverified = true
    },
    {
        key = "dire_off_large",
        team = 3,
        type = "large",
        laneKind = "off",
        enemySide = true,
        maxTowerDist = 2800,
        meetBack = 600,
        pullAggroSec = {18, 48},
        source = "seed",
        unverified = true
    }
}
return ____exports
