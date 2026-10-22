dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, UnitType, Tower = dota.Lane, dota.UnitType, dota.Tower

-- Radiant bot lane at front amount 0.5 sits at x = 0, y = -5000; T1s at amounts 0.3 / 0.7.
local function world(laneCfg)
	local H = LaneFresh(laneCfg or { Enable = true })
	T = 100
	CURRENT_TEAM = 2
	OBSERVER = 1
	local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000) })
	bot.lane, bot.pos = Lane.Bot, 1
	return H, bot, H.Lane.LaneState
end

local function creep(team, x, y, name, target)
	return MakeCreep({ team = team, x = x, y = y, name = name, target = target })
end

local function allFronts(rad, dire)
	LANE_FRONT[2][Lane.Bot] = rad[1]
	LANE_FRONT[3][Lane.Bot] = rad[2]
	if dire then LANE_FRONT[3][Lane.Bot], LANE_FRONT[2][Lane.Bot] = dire[1], dire[2] end
end

do
	local _, _, S = world()
	check("eq at own T1", near(S.EqPos(0.3, 0.3, 0.7), -1))
	check("eq at their T1", near(S.EqPos(0.7, 0.3, 0.7), 1))
	check("eq at midpoint", near(S.EqPos(0.5, 0.3, 0.7), 0))
	check("eq clamps behind own tower", near(S.EqPos(0.1, 0.3, 0.7), -1))
	check("eq clamps past their tower", near(S.EqPos(0.95, 0.3, 0.7), 1))
	check("desired eq by kind", near(S.DesiredEq("safe", false), -0.7) and near(S.DesiredEq("off", true), -0.7)
		and near(S.DesiredEq("mid", false), -0.1) and near(S.DesiredEq("mid", true), 0.15))
	check("lane kind per team", S.LaneKindOf(2, Lane.Bot) == "safe" and S.LaneKindOf(2, Lane.Top) == "off"
		and S.LaneKindOf(3, Lane.Top) == "safe" and S.LaneKindOf(3, Lane.Mid) == "mid")
end

do
	local _, bot, S = world()
	allFronts({ 0.5, 0.5 })
	local base = S.ForBot(bot)
	check("T1 alive: our tower 0.3, eq 0", near(base.ourTowerAmount, 0.3) and near(base.eqPos, 0), base.eqPos)

	local t1 = TOWERS_W[2][Tower.Bot1]
	t1.alive = false
	local t2 = setmetatable({}, getmetatable(t1))
	for k, v in pairs(t1) do t2[k] = v end
	t2.alive, t2.loc = true, GetLocationAlongLane(Lane.Bot, 0.2)
	TOWERS_W[2][Tower.Bot2] = t2
	T = 101
	local s = S.ForBot(bot)
	check("T1 dead falls back to T2", near(s.ourTowerAmount, 0.2), s.ourTowerAmount)
	check("eq uses T2", near(s.eqPos, 0.2), s.eqPos)
end

do
	local _, _, S = world()
	allFronts({ 0.6, 0.45 })
	local rad = S.Get(2, Lane.Bot)
	allFronts({ 0.45, 0.6 })
	CURRENT_TEAM = 3
	T = 101
	local dire = S.Get(3, Lane.Bot)
	check("dire T1 in own frame", near(dire.ourTowerAmount, 0.3) and near(dire.theirTowerAmount, 0.7), dire.ourTowerAmount)
	check("same team-relative fronts, same eq", near(rad.eqPos, dire.eqPos) and near(rad.eqPos, 0.375), dire.eqPos)
end

do
	local _, bot, S = world()
	allFronts({ 0.7, 0.3 })
	local s = S.ForBot(bot)
	local plain = S.ScoreFor(bot, s)
	check("wave at enemy tower scores very negative", near(s.eqPos, 1) and plain.laneScore < -1.5, plain.laneScore)
	check("no enemy no exposure", plain.exposure == 0)

	local enemy = MakeUnit({ pid = 6, team = 3, loc = Vector(2800, -5000) })
	T = 101
	local s2 = S.ForBot(bot)
	local withEnemy = S.ScoreFor(bot, s2)
	check("enemy laner halves exposure to 0.5", near(withEnemy.exposure, 0.5), withEnemy.exposure)
	check("enemy laner costs 0.1", near(plain.laneScore - withEnemy.laneScore, 0.1), plain.laneScore - withEnemy.laneScore)
end

for _, firstObserver in ipairs({ 1, 2 }) do
	local _, a, S = world()
	local b = MakeUnit({ pid = 2, team = 2, loc = Vector(0, -5000) })
	b.lane, b.pos = Lane.Bot, 2
	local enemy = MakeUnit({ pid = 6, team = 3, loc = Vector(100, -5000) })
	enemy.hiddenFrom = { [2] = true }
	allFronts({ 0.5, 0.5 })
	OBSERVER = firstObserver
	local s = S.ForBot(firstObserver == 1 and a or b)
	OBSERVER = 1
	local va = S.ScoreFor(a, s)
	OBSERVER = 2
	local vb = S.ScoreFor(b, s)
	check("A sees the laner, B does not (first=" .. firstObserver .. ")", near(va.exposure, 0.5) and vb.exposure == 0, va.exposure .. "/" .. vb.exposure)
	check("scores differ by 0.1 on the same snapshot (first=" .. firstObserver .. ")", near(vb.laneScore - va.laneScore, 0.1), vb.laneScore - va.laneScore)
end

do
	local _, bot, S = world()
	local deadCore = MakeUnit({ pid = 3, team = 2, alive = false, loc = Vector(-6000, -6000) })
	deadCore.lane, deadCore.pos = Lane.Bot, 1
	local farOther = MakeUnit({ pid = 4, team = 2, loc = Vector(-1000, 0) })
	farOther.lane, farOther.pos = Lane.Top, 3
	local nearOther = MakeUnit({ pid = 5, team = 2, loc = Vector(0, -4500) })
	nearOther.lane, nearOther.pos = Lane.Mid, 4
	local s = S.ForBot(bot)
	local byPid = {}
	for _, h in ipairs(s.allies) do byPid[h.pid] = h end
	check("dead assigned core kept", byPid[3] ~= nil and byPid[3].alive == false and byPid[3].hp == 0 and byPid[3].distToFront == math.huge and byPid[3].assigned)
	check("dead core keeps its position", byPid[3] and byPid[3].position == 1)
	check("far unassigned ally absent", byPid[4] == nil)
	check("near unassigned ally present, not assigned", byPid[5] ~= nil and byPid[5].assigned == false and byPid[5].alive)
	check("own bot assigned and alive", byPid[1] ~= nil and byPid[1].assigned and byPid[1].isBot and near(byPid[1].hp, 1))
end

do
	local _, bot, S = world()
	local enemy = MakeUnit({ pid = 6, team = 3, loc = Vector(100, -5000) })
	local creeps = {}
	for i = 1, 4 do creeps[i] = creep(3, 50 * i, -5000) end
	local function refreshAt(t, target)
		T = t
		enemy.target = target
		S.ForBot(bot)
	end
	refreshAt(61, creeps[1])
	refreshAt(62, creeps[2])
	refreshAt(63, creeps[3])
	refreshAt(64, creeps[3])
	check("no completed cycle yet", #S.ForBot(bot).enemyDeniesPerCycle == 0)
	refreshAt(91, nil)
	local s = S.ForBot(bot)
	check("three distinct creeps denied once each", #s.enemyDeniesPerCycle == 1 and s.enemyDeniesPerCycle[1] == 3, s.enemyDeniesPerCycle[1])
	refreshAt(95, nil)
	refreshAt(121, nil)
	local s2 = S.ForBot(bot)
	check("quiet cycle appends zero", #s2.enemyDeniesPerCycle == 2 and s2.enemyDeniesPerCycle[1] == 3 and s2.enemyDeniesPerCycle[2] == 0)
end

do
	local _, bot, S = world()
	for i = 1, 3 do creep(2, 20 * i, -5000) end
	for i = 1, 2 do creep(2, 20 * i, 0) end
	local hidden = creep(3, 0, -5000)
	hidden.CanBeSeen = function() return false end
	creep(2, 3000, -5000)
	creep(2, 0, -5000, "npc_dota_neutral_satyr")
	local s = S.ForBot(bot)
	check("bot lane ally creeps only", s.ally.count == 3, s.ally.count)
	check("fogged enemy creep ignored", s.enemy.count == 0)
	check("no ranged or siege yet", s.ally.rangedAlive == false and s.ally.siegeAlive == false)
	check("mid lane partitioned separately", S.Get(2, Lane.Mid).ally.count == 2)
	check("overlay text", S.Describe(s, S.ScoreFor(bot, s)) == "eq=0.00 want=-0.70 score=-0.70 a3/e0 next=20s", S.Describe(s, S.ScoreFor(bot, s)))

	creep(2, 40, -5000, "npc_dota_creep_goodguys_ranged")
	creep(2, 60, -5000, "npc_dota_goodguys_siege")
	T = 101
	local s2 = S.ForBot(bot)
	check("ranged and siege now alive", s2.ally.count == 5 and s2.ally.rangedAlive and s2.ally.siegeAlive)
end

do
	local _, _, S = world()
	creep(2, 0, -5000)
	local calls = function(t) return GETUNITLIST_CALLS[t] or 0 end
	S.Get(2, Lane.Bot)
	T = 100.2
	S.Get(2, Lane.Bot)
	check("0.2 s later uses cache", calls(UnitType.AlliedCreeps) == 1 and calls(UnitType.EnemyCreeps) == 1)
	T = 100.6
	S.Get(2, Lane.Bot)
	check("0.6 s later refreshes", calls(UnitType.AlliedCreeps) == 2 and calls(UnitType.EnemyCreeps) == 2)
	T = 110
	S.Get(2, Lane.Top)
	S.Get(2, Lane.Mid)
	S.Get(2, Lane.Bot)
	check("three lanes share one scan", calls(UnitType.AlliedCreeps) == 3 and calls(UnitType.EnemyCreeps) == 3)
end

do
	local _, bot, S = world()
	local c = creep(3, 0, -5000, nil, bot)
	local s = S.ForBot(bot)
	check("aggro recorded at observation time", s.lastAllyAggroAt[1] == 100, s.lastAllyAggroAt[1])
	c.target = nil
	T = 105
	check("aggro time persists after the creep stops", S.ForBot(bot).lastAllyAggroAt[1] == 100)
	c.target = bot
	T = 110
	check("aggro time advances", S.ForBot(bot).lastAllyAggroAt[1] == 110)
end

do
	local _, bot, S = world()
	local visible = MakeUnit({ pid = 6, team = 3, loc = Vector(0, 0) })
	local fogged = MakeUnit({ pid = 5, team = 3, loc = Vector(0, 0) })
	fogged.hiddenFrom = { [1] = true }
	local dead = MakeUnit({ pid = 7, team = 3, alive = false, loc = Vector(0, 0) })
	dead.hiddenFrom = { [1] = true }
	LAST_SEEN[5] = { location = Vector(300, 400), time_since_seen = 2 }
	LAST_SEEN[7] = { location = Vector(300, 400), time_since_seen = 2 }
	local byPid = {}
	for _, e in ipairs(S.Enemies(bot, Lane.Bot)) do byPid[e.pid] = e end
	check("visible enemy listed visible", byPid[6] and byPid[6].visible and byPid[6].unit == visible)
	check("fogged enemy uses last seen", byPid[5] and byPid[5].visible == false and byPid[5].timeSinceSeen == 2 and byPid[5].location.x == 300 and byPid[5].unit == nil)
	check("dead enemy not listed", byPid[7] == nil)
	LAST_SEEN[5] = nil
	T = 101
	local again = {}
	for _, e in ipairs(S.Enemies(bot, Lane.Bot)) do again[e.pid] = e end
	check("no last-seen info, no entry", again[5] == nil and again[6] ~= nil)
end

-- console.9055828679 10:44: an enemy handle in the cached list was removed (a killed illusion) before the
-- cache expired, and countDenies' GetAttackTarget on it raised "Invalid object".
do
	local _, bot, S = world()
	local hero = MakeUnit({ pid = 6, team = 3, loc = Vector(0, -5000) })
	local illusion = MakeUnit({ pid = 6, team = 3, loc = Vector(50, -5000) })
	check("both listed while alive", #S.Enemies(bot, Lane.Bot) == 2)
	illusion.removed = true
	table.remove(UNITS[3], 2)
	T = 100.1
	local units = {}
	for _, e in ipairs(S.Enemies(bot, Lane.Bot)) do if e.unit ~= nil then table.insert(units, e.unit) end end
	check("removed handle not served from the cache", #units == 1 and units[1] == hero, #units)
end

do
	local _, bot, S = world()
	allFronts({ 0.5, 0.5 })
	local made = 0
	local function wave(t, n)
		T = t
		while made < n do made = made + 1; creep(3, 20 * made, -5000) end
		return S.ForBot(bot)
	end
	wave(92, 2)
	wave(95, 3)
	local mid = wave(100, 4)
	check("cycle second and countdown", near(mid.cycleSec, 10) and near(mid.nextWaveIn, 20))
	check("nothing completed mid-cycle", #mid.enemyWaveSizes == 0 and mid.enemyArrivalSec == nil)
	for i = #CREEPS[3], 1, -1 do table.remove(CREEPS[3], i) end
	made = 0
	local after = wave(121, 0)
	check("first cycle recorded", #after.enemyWaveSizes == 1 and after.enemyWaveSizes[1] == 4 and near(after.enemyArrivalSec, 5), after.enemyArrivalSec)
	check("eq recorded at cycle end", #after.eqHistory == 1 and near(after.eqHistory[1], 0))
	wave(127, 3)
	local last = wave(151, 3)
	check("second cycle arrives later; median of both", #last.enemyWaveSizes == 2 and last.enemyWaveSizes[2] == 3 and near(last.enemyArrivalSec, 6), last.enemyArrivalSec)
end

do
	local _, _, S = world()
	local refreshed = 0
	S.OnRefresh(function() refreshed = refreshed + 1 end)
	check("default mid desired", near(S.Get(2, Lane.Mid).desiredEq, -0.1))
	S.Get(2, Lane.Mid)
	check("callback only on refresh", refreshed == 1, refreshed)
	S.SetPreRune(function(team, lane) return lane == Lane.Mid end)
	T = 101
	check("pre-rune hook raises mid desired eq", near(S.Get(2, Lane.Mid).desiredEq, 0.15))
	check("pre-rune hook leaves other lanes", near(S.Get(2, Lane.Bot).desiredEq, -0.7))
end

do
	local flags = { "Plan", "Block", "FullPull", "HalfPull", "StackPull", "AggroPull", "Freeze", "Shove", "Stack", "Harass", "Mid", "CounterPlay", "CampBlock" }
	local allOff = { Enable = true }
	for _, f in ipairs(flags) do allOff[f] = false end
	for name, cfg in pairs({ disabled = { Enable = false }, ["no consumers"] = allOff }) do
		local H, bot, S = world(cfg)
		creep(2, 0, -5000)
		MakeUnit({ pid = 6, team = 3 })
		check(name .. ": ForBot nil", S.ForBot(bot) == nil)
		check(name .. ": Get nil and no enemies", S.Get(2, Lane.Bot) == nil and #S.Enemies(bot, Lane.Bot) == 0)
		H.Lane.Tick(bot)
		check(name .. ": no GetUnitList scans", next(GETUNITLIST_CALLS) == nil)
	end
	local H, bot, S = world()
	creep(2, 0, -5000)
	check("control: defaults produce a snapshot", S.ForBot(bot) ~= nil)
	check("control: and scan the world", (GETUNITLIST_CALLS[UnitType.AlliedCreeps] or 0) > 0)
end

do
	local _, bot, S = world()
	allFronts({ 0.6, 0.45 })
	local empty = S.ForBot(bot)
	check("no creeps: no imbalance and forecast stays at eq", empty.imbalance == 0 and empty.forecastEq == empty.eqPos, empty.imbalance)

	local ranged = { MakeCreep({ team = 2, x = 0, y = 0, hp = 300, name = "npc_dota_creep_goodguys_ranged" }),
		MakeCreep({ team = 2, x = 0, y = 0, hp = 300, name = "npc_dota_creep_goodguys_ranged" }) }
	local melee = { MakeCreep({ team = 3, x = 0, y = 0, hp = 200 }), MakeCreep({ team = 3, x = 0, y = 0, hp = 200 }),
		MakeCreep({ team = 3, x = 0, y = 0, hp = 200 }) }
	check("ranged outweigh melee of equal HP", S.Imbalance(S.LanePower(ranged), S.LanePower(melee)) > 0)
	check("a 100-HP straggler is a small imbalance", S.Imbalance(100, 0) < 0.2, S.Imbalance(100, 0))
	check("upgraded waves in proportion read alike", math.abs(S.Imbalance(2000, 1000) - S.Imbalance(4000, 2000)) < 0.05)
	check("forecast clamps at the enemy tower", S.ForecastEq(0.9, 1) == 1)
	check("forecast moves toward the winner", near(S.ForecastEq(-0.3, 0.5), -0.1))
end

do
	local _, bot, S = world()
	allFronts({ 0.5, 0.5 })
	creep(2, 0, -5000, "npc_dota_creep_goodguys_ranged")
	creep(3, 0, -5000)
	local fogged = creep(3, 0, -5000)
	fogged.CanBeSeen = function() return false end
	local s = S.ForBot(bot)
	check("fogged enemy creep adds no power", near(s.enemyPower, 550) and s.enemy.count == 1, s.enemyPower)
	check("ally power is HP weighted by type", near(s.allyPower, 550 * 1.6), s.allyPower)
	check("snapshot imbalance and forecast follow the powers",
		near(s.imbalance, S.Imbalance(s.allyPower, s.enemyPower)) and s.imbalance > 0 and s.forecastEq > s.eqPos, s.forecastEq)
end

do
	local _, _, S = world()
	local function fscore(eq, imb, skill) return S.ForecastScore(-0.7, eq, S.ForecastEq(eq, imb), S.ForesightOf(skill), 0) end
	check("skill 0 reads the lane as today", near(fscore(-0.3, 0.6, 0), S.LaneScore(-0.7, -0.3, 0)))
	check("skill 0.9, winning clash: full-pull score", fscore(-0.3, 0.6, 0.9) <= -0.5, fscore(-0.3, 0.6, 0.9))
	check("skill 0.3, same lane: still half-pull score", fscore(-0.3, 0.6, 0.3) > -0.5, fscore(-0.3, 0.6, 0.3))
	check("skill 0.9, losing clash: no longer a full-pull score", fscore(-0.1, -0.6, 0.9) > -0.5, fscore(-0.1, -0.6, 0.9))
end

do
	local _, _, S = world({ Enable = true, Forecast = false })
	check("Forecast off: no foresight at any skill", S.ForesightOf(1) == 0, S.ForesightOf(1))
end

finish()
