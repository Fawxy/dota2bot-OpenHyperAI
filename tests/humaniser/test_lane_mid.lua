dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local MID_FRONT = Vector(0, 0)

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = o.loc or MID_FRONT })
	u.lane, u.pos, u.dmg = o.lane or Lane.Mid, o.pos, o.dmg
	return u
end

-- Radiant mid bot (pid 2, pos 2) alone in mid, wave in the middle of the lane (eqPos 0).
local function midWorld(skill, opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true }, { skill = skill })
	T = opts.t or 100
	CURRENT_TEAM = 2
	OBSERVER = 2
	NEXT_RUNE = opts.nextRune or 240
	SPAWNERS = {}
	H.Lane.Camps.ResetCache()
	local mid = unit({ pid = 2, pos = 2 })
	local enemy = unit({ pid = 7, team = 3, pos = 2 })
	return H, mid, enemy
end
local function setFronts(enemy, ours, theirs)
	LANE_FRONT[2][Lane.Mid], LANE_FRONT[3][Lane.Mid] = ours, theirs
	enemy.loc = GetLaneFrontLocation(2, Lane.Mid, 0)
end
local function plan(H, bot) return H.Lane.LanePlanner.Plan(bot, H.Lane.LaneState.ForBot(bot)) end
local function desc(c) return c.tech .. " (" .. c.reason .. ")" end

do
	local H = midWorld(0.9)
	local M = H.Lane.LaneMid
	check("window opens 20 s before the rune", M.IsPreRuneWindow(222, 240))
	check("not yet 21 s out", not M.IsPreRuneWindow(219, 240))
	check("window closes at 14 s out", not M.IsPreRuneWindow(226, 240))
	T = 222
	check("mid lane in the window", M.IsPreRune(2, Lane.Mid))
	check("other lanes never pre-rune", not M.IsPreRune(2, Lane.Top))
	local H2 = LaneFresh({ Enable = true, Mid = false }, { skill = 0.9 })
	NEXT_RUNE, T = 240, 222
	check("Mid flag off disables the window", not H2.Lane.LaneMid.IsPreRune(2, Lane.Mid))
end

do
	local H, mid = midWorld(0.5, { t = 222 })
	local s = H.Lane.LaneState.ForBot(mid)
	check("pre-rune desired eq", near(s.desiredEq, 0.15), s.desiredEq)
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	local c = plan(H, mid)
	check("shove inside the pre-rune window", c.tech == "shove" and c.reason == "shove before rotating", desc(c))

	H, mid = midWorld(0.5, { t = 210 })
	check("desired eq outside the window", near(H.Lane.LaneState.ForBot(mid).desiredEq, -0.1))
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	c = plan(H, mid)
	check("no shove outside the window", c.tech ~= "shove", desc(c))

	H, mid = midWorld(0.39, { t = 222 })
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	c = plan(H, mid)
	check("below the shove gate nothing shoves", c.tech ~= "shove", desc(c))
end

do
	local H, mid = midWorld(0.9, { t = 217 })
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	local c = plan(H, mid)
	check("window not open yet", c.tech ~= "shove", desc(c))
	T = 220.5
	c = plan(H, mid)
	check("entering the window mid-cycle shoves at once", c.tech == "shove" and c.reason == "shove before rotating", desc(c))
end

do
	local H, mid = midWorld(0.9)
	local M = H.Lane.LaneMid
	mid.dmg = 400
	local melee = MakeCreep({ team = 2, x = 50, y = 0, hp = 20 })
	local ranged = MakeCreep({ team = 2, x = 60, y = 0, hp = 25, name = "npc_dota_creep_goodguys_ranged" })
	check("deniable ranged creep before a deniable melee one", M.PickDeny(mid, { melee, ranged }) == ranged)
	ranged.hp = 330
	check("healthy ranged creep is left; melee is the Lua fallback's call", M.PickDeny(mid, { melee, ranged }) == nil)
	ranged.hp = 25
	local support = unit({ pid = 5, pos = 5, lane = Lane.Bot })
	support.dmg = 400
	check("non-mid bots never use mid deny control", M.PickDeny(support, { melee, ranged }) == nil)
end

do
	local H, mid = midWorld(0.9)
	local M = H.Lane.LaneMid
	local human = unit({ pid = 3, pos = 2, bot = false })
	local support = unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(300, 0) })
	local creep = MakeCreep({ team = 3, x = 100, y = 0 })
	check("support hands off a human mid's wave", M.MayTouchWave(support, creep) == false)
	check("the mid bot itself may touch it", M.MayTouchWave(mid, creep) == true)
	T = 700
	LANING = false
	check("after laning anyone may touch it", M.MayTouchWave(support, creep) == true)
	LANING = nil
	T = 100
	human.loc = Vector(0, 3000)
	H.Lane.LaneState.ResetCache()
	check("human away from the wave", M.MayTouchWave(support, creep) == true)
	human.loc = MID_FRONT
	H.Lane.LaneState.ResetCache()
	check("human back", M.MayTouchWave(support, creep) == false)
	local far = MakeCreep({ team = 3, x = 2000, y = 0 })
	check("a creep away from the mid front is fair game", M.MayTouchWave(support, far) == true)
	human.bot = true
	H.Lane.LaneState.ResetCache()
	check("a bot mid is not protected", M.MayTouchWave(support, creep) == true)
end

local MID_CAMP = { team = 2, type = "small", location = Vector(-2800, 400, 0), min = Vector(-2950, 250, 0),
	max = Vector(-2650, 550, 0), speed = 0 }

do
	local H, mid, enemy = midWorld(0.9)
	SPAWNERS = { MID_CAMP }
	H.Lane.Camps.ResetCache()
	check("seed data has no mid pull camp", not H.Lane.LaneMid.MidPullAllowed(2))
	setFronts(enemy, 0.64, 0.36)
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	local c = plan(H, mid)
	check("planner never pulls mid from seed data", c.tech == "aggro_pull" and c.reason == "small correction", desc(c))
end

-- A mid pull camp injected into the data, wave 0.7 or 0.9 of the way to the enemy tower.
local function campPlan(ours, theirs)
	local H, mid, enemy = midWorld(0.9)
	local data = require("bots/FunLib/humaniser/camps_data")
	table.insert(data.CAMP_DATA, { key = "mid_test", team = 2, type = "small", laneKind = "mid", pullAggroSec = { 15, 45 }, source = "seed" })
	SPAWNERS = { MID_CAMP }
	H.Lane.Camps.ResetCache()
	check("precondition: injected mid pull camp", H.Lane.LaneMid.MidPullAllowed(2))
	setFronts(enemy, ours, theirs)
	SetRandomSequence({ 0.0, 0.0, 0.0, 0.0 })
	return plan(H, mid)
end

do
	local c = campPlan(0.68, 0.32)
	check("wave at the enemy tower aggro-pulls", c.tech == "aggro_pull" and c.reason == "mid: out of tower range", desc(c))
	c = campPlan(0.64, 0.36)
	check("short of the tower range the camp pull decides", c.tech == "full_pull", desc(c))
end

-- mode_rune_generic keeps its old rule: odd minute and second > 53 is the same as under 7 s to the next even minute.
do
	local src = io.open("bots/FunLib/jmz_func.lua", "r"):read("a")
	local body = src:match("function J%.GetNextPowerRuneSpawnTime%(%)(.-)\nend\n")
	check("helper present in jmz_func", body ~= nil)
	local J = {}
	local fn = load("local J = ... ; return function()" .. body .. " end")
	local nextRune = fn(J)
	local runeSrc = io.open("bots/mode_rune_generic.lua", "r"):read("a")
	check("rune mode uses the shared helper", runeSrc:find("J.GetNextPowerRuneSpawnTime() - DotaTime() < 7", 1, true) ~= nil)
	local mismatch
	for tenth = 601, 12000 do
		T = tenth / 10
		local minute, second = math.floor(T / 60), T % 60
		local old = (minute % 2 == 1 and second > 53)
		local new = (nextRune() - DotaTime() < 7)
		if old ~= new then mismatch = T break end
	end
	check("rune mode window identical to the old rule", mismatch == nil, mismatch)
	T = 30
	check("before 2:00 the next rune is 2:00", nextRune() == 120)
end

finish()
