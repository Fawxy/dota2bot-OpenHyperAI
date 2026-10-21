dofile(HARNESS_DIR .. "/lane_world.lua")

local dota = require("bots/ts_libs/dota/index")
local SPOTS = { [dota.Rune.Power1] = Vector(-1600, -1200), [dota.Rune.Power2] = Vector(1200, 1600) }
function GetRuneSpawnLocation(r) return SPOTS[r] end

local R = LaneFresh({ Enable = true }, { transitions = { Enable = true } }).Transitions.Runes

check("power: before first spawn", R.NextSpawn("power", 300) == 360)
check("power: exactly on a spawn", R.NextSpawn("power", 360) == 360)
check("power: just after a spawn", R.NextSpawn("power", 361) == 480)
check("water: before the first", R.NextSpawn("water", 0) == 120)
check("water: second and last", R.NextSpawn("water", 121) == 240)
check("water: none left", R.NextSpawn("water", 250) == math.huge)
check("bounty: next after 181", R.NextSpawn("bounty", 181) == 360)
check("bounty: at game start", R.NextSpawn("bounty", 0) == 0)
check("wisdom: first at 420", R.NextSpawn("wisdom", 100) == 420 and R.NextSpawn("wisdom", 421) == 840)

local spots = R.PowerSpots()
check("power spots in index order", #spots == 2 and spots[1].y < 0 and spots[2].y > 0)

local loc, side = R.NearestPowerSpot(Vector(1000, 1500))
check("nearest by top spot is top", side == "top" and loc.y == 1600, tostring(side))
loc, side = R.NearestPowerSpot(Vector(-1500, -1000))
check("nearest by bot spot is bot, named by position not index", side == "bot" and loc.y == -1200, tostring(side))

finish()
