dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

-- Bot lane runs along y = -5000; absolute amount a sits at x = -7000 + 14000 a. T1s at amounts 0.3 (Radiant) and 0.7 (Dire).
local function x(a) return -7000 + 14000 * a end

local function fresh()
	LaneFresh({ Enable = true })
	CURRENT_TEAM = 2
	local R = require("bots/FunLib/humaniser/lane_read")
	R.Reset()
	return R
end

local function bot(reads) for _, r in ipairs(reads) do if r.lane == Lane.Bot then return r end end end

-- Fronts are team-relative in LANE_FRONT; both at absolute 0.6 means the wave meets past mid, towards Dire's T1. The stub
-- shares one lane path between the teams, so here Dire's conversion lands exactly; in game it does not (debt lane-amount-frame).
do
	local R = fresh()
	LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.6, 0.4
	local rad = bot(R.Read(2, 100))
	CURRENT_TEAM = 3
	local dire = bot(R.Read(3, 100))
	check("radiant reads the meet halfway to Dire's tower", near(rad.eq, 0.5), rad.eq)
	check("dire's script reads the same meet as halfway back to its own tower", near(dire.eq, -0.5), dire.eq)
	check("dire's team-relative front is converted to the Radiant-based amount", near(rad.ourFront, dire.enemyFront) and near(rad.ourFront, 0.6), dire.enemyFront)
end

-- Advantage reads creeps near our front and only visible enemies; the census counts every own creep in the lane.
do
	local R = fresh()
	LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.5, 0.5
	for _, a in ipairs({ 0.49, 0.5, 0.51 }) do MakeCreep({ team = 2, x = x(a), y = -5000 }) end
	MakeCreep({ team = 2, x = x(0.15), y = -5000 })
	MakeCreep({ team = 3, x = x(0.52), y = -5000 })
	MakeCreep({ team = 3, x = x(0.53), y = -5000 })
	local fogged = MakeCreep({ team = 3, x = x(0.54), y = -5000 })
	fogged.unseen = true
	local r = bot(R.Read(2, 100))
	check("near front: three of ours", r.near.count == 3, r.near.count)
	check("near front: the fogged enemy creep is left out", r.enemyNear.count == 2, r.enemyNear.count)
	check("three against two leans our way", r.adv > 1 and r.adv < 2, r.adv)
	check("census holds the straggler far behind the front", r.census.count == 4, r.census.count)
	check("radiant's lead creep is the one nearest Dire", near(r.census.lead, 0.51), r.census.lead)
	-- The stub fogs a creep for every viewer; in game a team always sees its own creeps.
	fogged.unseen = false
	CURRENT_TEAM = 3
	local d = bot(R.Read(3, 100))
	check("dire's census counts the creep it cannot have fogged", d.census.count == 3, d.census.count)
	check("dire's lead creep is the one nearest Radiant", near(d.census.lead, 0.52), d.census.lead)
	check("dire's own creeps at Radiant's front include the one Radiant could not see", d.censusAtEnemy.count == 3
		and d.censusAtEnemy.power > r.enemyNear.power, d.censusAtEnemy.count)
end

-- D4: with GetTeamPlayers empty for the bot-only enemy team, an enemy seen once is still counted when it goes missing.
do
	local R = fresh()
	local savedPlayers = GetTeamPlayers
	GetTeamPlayers = function(team) if team == 3 then return {} end return savedPlayers(team) end
	OBSERVER = 1
	MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000) }).lane = Lane.Bot
	local enemy = MakeUnit({ pid = 7, team = 3, loc = Vector(500, -5000), level = 3, hp = 40 })
	local first = bot(R.Read(2, 100))
	enemy.hiddenFrom = { [1] = true }
	LAST_SEEN[7] = { location = Vector(2000, -5000), time_since_seen = 6 }
	local later = bot(R.Read(2, 106))
	GetTeamPlayers = savedPlayers
	check("seen enemy is read with HP and level", #first.enemies == 1 and first.enemies[1].visible and near(first.enemies[1].hp, 0.4)
		and first.enemies[1].lvl == 3)
	local miss = later.enemies[1]
	check("the enemy that left vision is still listed", #later.enemies == 1 and miss ~= nil and not miss.visible)
	check("missing enemy carries time since seen and distance from its last spot", miss ~= nil and miss.seen == 6 and near(miss.dist, 2000))
	enemy.alive = false
	local dead = bot(R.Read(2, 110))
	check("a dead enemy is counted dead, not missing", dead.dead == 1 and #dead.enemies == 0, dead.dead)
end

-- Aggro: enemy lane creeps attacking our hero now, then seconds since the last.
do
	local R = fresh()
	local hero = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000) })
	hero.lane = Lane.Bot
	local c = MakeCreep({ team = 3, x = 100, y = -5000, target = hero })
	local hit = bot(R.Read(2, 200)).aggro[1]
	c.target = nil
	local after = bot(R.Read(2, 203.5)).aggro[1]
	check("one creep on our hero", hit.pid == 1 and hit.now == 1 and hit.since == 0)
	check("aggro drops and the clock runs", after.now == 0 and near(after.since, 3.5), after.since)
end

-- The ee and ag strings are parsed by hlog @lane_read_check (its store test uses the same shapes).
do
	local R = fresh()
	local ee = R.FormatEnemies({
		{ pid = 7, visible = false, seen = 12.6, dist = 1500.9 },
		{ pid = 8, visible = true, seen = 0, dist = 300.2, hp = 0.504, lvl = 3 },
	})
	check("ee: missing as pid:secs:dist, visible as pid:v:dist:hp%:lvl", ee == "7:12:1500;8:v:300:50:3", ee)
	local ag = R.FormatAggro({ { pid = 1, now = 2, since = 0 }, { pid = 2, now = 0, since = 3.56 }, { pid = 3, now = 0 } })
	check("ag: pid:now:since, -1 when never", ag == "1:2:0.0;2:0:3.5;3:0:-1", ag)
end

finish()
