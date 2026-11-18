dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane


local BOT_Y = LANE_Y[Lane.Bot]
local function lane(skill)
	local H = LaneFresh({ Enable = true }, { skill = skill })
	T = 100
	CURRENT_TEAM = 2
	local enemy = MakeUnit({ pid = 6, team = 3, loc = Vector(-2500, BOT_Y) })
	enemy.dmg = 40
	return H, enemy
end

local function attempt(enemy, hp)
	local creep = MakeCreep({ team = 2, x = -2700, y = BOT_Y, hp = hp or 30 })
	enemy.target = creep
	return creep
end

-- attempt detection
do
	local H, enemy = lane(0.9)
	local Harass = H.Lane.Harass
	local creep = attempt(enemy, 30)
	check("(a) enemy targeting a creep it kills is an attempt", Harass.IsLastHitAttempt(enemy, { creep }) == creep)
	creep.hp = 60
	check("(a) a creep the hit cannot kill is no attempt", Harass.IsLastHitAttempt(enemy, { creep }) == nil)

	enemy.target = nil
	local low = MakeCreep({ team = 2, x = -2800, y = BOT_Y, hp = 35 })
	enemy.extrap = Vector(-2600, BOT_Y)
	check("(b) moving toward a killable creep is an attempt", Harass.IsLastHitAttempt(enemy, { low }) == low)
	enemy.extrap = Vector(-2400, BOT_Y)
	check("(b) moving away is no attempt", Harass.IsLastHitAttempt(enemy, { low }) == nil)
end

finish()
