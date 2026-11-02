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

-- D4: with GetTeamPlayers empty for the bot-only enemy team (and no id from GetTeamForPlayer), an enemy seen once is
-- still counted when it goes missing.
do
	local R = fresh()
	local savedPlayers, savedTeamFor = GetTeamPlayers, GetTeamForPlayer
	GetTeamPlayers = function(team) if team == 3 then return {} end return savedPlayers(team) end
	GetTeamForPlayer = function() return -1 end
	OBSERVER = 1
	MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000) }).lane = Lane.Bot
	local enemy = MakeUnit({ pid = 7, team = 3, loc = Vector(500, -5000), level = 3, hp = 40 })
	local first = bot(R.Read(2, 100))
	enemy.hiddenFrom = { [1] = true }
	LAST_SEEN[7] = { location = Vector(2000, -5000), time_since_seen = 6 }
	local later = bot(R.Read(2, 106))
	GetTeamPlayers, GetTeamForPlayer = savedPlayers, savedTeamFor
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

-- Census per creep (cc) and our nearest tower (tw/twh): the lane forecast restarts from these, so kinds, order and the
-- tower that counts must be right. Creeps outside the lane and enemy creeps are left out.
do
	local R = fresh()
	MakeCreep({ team = 2, x = x(0.45), y = -5000, hp = 300, name = "npc_dota_creep_goodguys_ranged_upgraded" })
	MakeCreep({ team = 2, x = x(0.5), y = -5000, hp = 412.6 })
	MakeCreep({ team = 2, x = x(0.2), y = -5000, hp = 900, name = "npc_dota_goodguys_siege" })
	MakeCreep({ team = 2, x = x(0.48), y = -5000, name = "npc_dota_creep_goodguys_flagbearer" })
	MakeCreep({ team = 2, x = x(0.5), y = 5000 })
	MakeCreep({ team = 3, x = x(0.55), y = -5000 })
	local dead1 = { IsAlive = function() return false end }
	TOWERS_W[2][dota.Tower.Bot1] = dead1
	TOWERS_W[2][dota.Tower.Bot2] = { IsAlive = function() return true end, GetHealth = function() return 2100 end,
		GetLocation = function() return Vector(x(0.2), -5000) end }
	local r = bot(R.Read(2, 100))
	local cc = R.FormatCreeps(r.creeps)
	check("cc: own bot-lane creeps by amount with kind and HP", cc == "s:200:900;r:450:300;f:480:550;m:500:413", cc)
	check("tower: T1 down, so T2 and its HP", r.towerTier == 2 and r.towerHp == 2100, r.towerTier)
	TOWERS_W[2][dota.Tower.Bot2] = dead1
	TOWERS_W[2][dota.Tower.Bot3] = dead1
	local gone = bot(R.Read(2, 101))
	check("tower: all three down reads tier 0 and no HP", gone.towerTier == 0 and gone.towerHp == nil, gone.towerTier)
end

-- Slice lane-read-ec. M5: an enemy never seen has no last-seen spot, so ee cannot list it; ns does, found through
-- GetTeamForPlayer although GetTeamPlayers is empty. ed measures each listed enemy to our nearest tower and to the allies in
-- the lane, from the last-seen spot when it is missing.
do
	local R = fresh()
	local savedPlayers = GetTeamPlayers
	GetTeamPlayers = function(team) if team == 3 then return {} end return savedPlayers(team) end
	OBSERVER = 1
	MakeUnit({ pid = 1, team = 2, loc = Vector(x(0.4), -5000) }).lane = Lane.Bot
	MakeUnit({ pid = 2, team = 2, loc = Vector(x(0.5), 5000) }).lane = Lane.Top
	local seen = MakeUnit({ pid = 7, team = 3, loc = Vector(x(0.6), -5000) })
	seen.hiddenFrom = { [1] = true }
	LAST_SEEN[7] = { location = Vector(x(0.6), -5000), time_since_seen = 4 }
	MakeUnit({ pid = 8, team = 3, loc = Vector(x(0.9), -5000) }).hiddenFrom = { [1] = true }
	local deadUnseen = MakeUnit({ pid = 9, team = 3, loc = Vector(x(0.9), 5000) })
	deadUnseen.hiddenFrom = { [1] = true }
	deadUnseen.alive = false
	local r = bot(R.Read(2, 100))
	GetTeamPlayers = savedPlayers
	check("ns: the alive enemy never seen, found with GetTeamPlayers empty", #r.neverSeen == 1 and r.neverSeen[1] == 8, #r.neverSeen)
	check("the never-seen dead enemy counts dead, not missing", r.dead == 1, r.dead)
	local e = r.enemies[1]
	check("ed: missing enemy measured from its last spot to our bot T1 (amount 0.3)", #r.enemies == 1 and near(e.towerDist, 0.3 * 14000), e and e.towerDist)
	check("ed: only the ally in this lane, from the same spot", #e.allyDist == 1 and e.allyDist[1][1] == 1 and near(e.allyDist[1][2], 0.2 * 14000))
	check("ed string in ee's order", R.FormatEnemyDistances(r.enemies) == "7:4200:1=2800", R.FormatEnemyDistances(r.enemies))
	TOWERS_W[2][dota.Tower.Bot1] = { IsAlive = function() return false end }
	TOWERS_W[2][dota.Tower.Bot2] = TOWERS_W[2][dota.Tower.Bot1]
	TOWERS_W[2][dota.Tower.Bot3] = TOWERS_W[2][dota.Tower.Bot1]
	check("ed: -1 with every tower on the lane down", bot(R.Read(2, 101)).enemies[1].towerDist == -1)
end

-- ec: the visible enemy creeps in the lane, wherever they are (not only near our front), in cc's format; fogged ones are out.
do
	local R = fresh()
	LANE_FRONT[2][Lane.Bot] = 0.3
	MakeCreep({ team = 3, x = x(0.7), y = -5000, hp = 300, name = "npc_dota_creep_badguys_ranged" })
	MakeCreep({ team = 3, x = x(0.55), y = -5000, hp = 550 })
	MakeCreep({ team = 3, x = x(0.6), y = -5000 }).unseen = true
	MakeCreep({ team = 3, x = x(0.55), y = 5000 })
	local r = bot(R.Read(2, 100))
	check("ec: visible enemy bot-lane creeps by amount, far from our front too", R.FormatCreeps(r.enemyCreeps) == "m:550:550;r:700:300", R.FormatCreeps(r.enemyCreeps))
	check("near-front counts are unchanged by ec", r.enemyNear.count == 0, r.enemyNear.count)
end

finish()
