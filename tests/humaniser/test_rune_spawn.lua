dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice rune-spawn: the team's 6:00 power rune plan (RunePlan) and its trips (RuneJob under Ours.RuneSpawn): the mid takes
-- the spot nearer it, one free support the other; each waits at a higher stand, walks in on time and takes, denies, stays
-- off or crosses by the race at the spawn.

local dota = require("bots/ts_libs/dota/index")
local FARM, LANING = dota.BotMode.Farm, dota.BotMode.Laning
local P1, P2 = dota.Rune.Power1, dota.Rune.Power2
local RAD, DIRE = 2, 3
local SPOT = { [P1] = Vector(-1640, 1112), [P2] = Vector(1180, -1216) }

function GetRuneSpawnLocation(r) return SPOT[r] or Vector(-9000, 9000) end
local status = {}
function GetRuneStatus(r) return status[r] or RUNE_STATUS_MISSING end
-- West of x=-2000 and south of y=-1700 is high ground; the river spots are low.
function GetHeightLevel(l) return (l.x < -2000 or l.y < -1700) and 3 or 1 end
ANCIENT.GetLocation = function() return CURRENT_TEAM == RAD and Vector(-7000, -6500) or Vector(7000, 6500) end

local meta = getmetatable(MakeUnit({ pid = 98, team = 3 })).__index
meta.Action_PickUpRune = function(self, r)
	table.insert(ACTIONS, { pid = self.pid, kind = "PickUpRune", args = { r } })
	if status[r] == RUNE_STATUS_AVAILABLE and GetUnitToLocationDistance(self, SPOT[r]) <= 150 then status[r] = RUNE_STATUS_MISSING end
end
meta.Action_AttackMove = function(self, at) table.insert(ACTIONS, { pid = self.pid, kind = "AttackMove", args = { at } }) end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function world(o)
	o = o or {}
	package.loaded["bots/FunLib/engine/tasks"] = nil
	local H = LaneFresh({ Enable = true }, { enable = false, skill = 1, telemetry = { Enable = true } })
	local C = package.loaded["bots/FunLib/custom_loader"]
	C.Ours = { StackExecute = false, DoubleStack = false, RuneRotation = true, JobChooser = true, RuneSpawn = o.spawn ~= false }
	T = o.t or 315
	CURRENT_TEAM = RAD
	status = {}
	H.StackJob.ResetCache()
	H.RuneJob.ResetCache()
	H.RunePlan.ResetCache()
	return H
end

local function hero(pid, pos, at, team)
	local u = MakeUnit({ pid = pid, team = team or RAD, loc = at })
	u.pos = pos
	return u
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

local function lines(all, ev)
	local r = {}
	for _, l in ipairs(all) do if l:find("ev=" .. ev .. " ", 1, true) then table.insert(r, l) end end
	return r
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

-- One frame: supports through the job chooser's farm host, the mid through the rune mode's branch against laning, both
-- through the chooser's mode gates as the mode files wrap them. Moves land at once, capped at the hero's speed per frame
-- so walks take their time.
local function frame(H, bots, spawnAt)
	for _, bot in ipairs(bots) do
		local n0 = #ACTIONS
		if bot.pos == 2 then
			local rune = H.Chooser.Gate(bot, "rune", function() return H.RuneJob.MidWants(bot) and H.RuneJob.MID_DESIRE or 0 end)()
			local lane = H.Chooser.Gate(bot, "laning", function() return 0.5 end)()
			if rune > lane then bot.mode = dota.BotMode.Rune H.RuneJob.MidStep(bot) else bot.mode = LANING end
		elseif H.Chooser.Gate(bot, "farm", function() return H.Chooser.FarmDesire(bot) end)() > 0 then
			bot.mode = FARM
			H.Chooser.HostThink(bot, "farm", function() return H.Chooser.FarmThink(bot) end, function() return false end)()
		else
			bot.mode = LANING
		end
		for i = #ACTIONS, n0 + 1, -1 do
			local a = ACTIONS[i]
			if a.pid == bot.pid and a.kind == "MoveToLocation" then
				local to, d = a.args[1], dist(bot.loc, a.args[1])
				local step = 300 * 0.1
				bot.loc = d <= step and Vector(to.x, to.y) or Vector(bot.loc.x + (to.x - bot.loc.x) * step / d, bot.loc.y + (to.y - bot.loc.y) * step / d)
				break
			end
		end
	end
	if spawnAt ~= nil and T < spawnAt and T + 0.1 >= spawnAt then status[SPAWN_AT] = RUNE_STATUS_AVAILABLE end
	T = T + 0.1
end

local function run(H, bots, untilT)
	return capture(function() while T < untilT do frame(H, bots, 360) end end)
end

-- The plan: mid nearer the top spot gets it; pos4 and pos5 both free, the one nearer the bottom spot gets that; with pos5
-- on a stack, pos4 gets it even when pos5 is nearer.
do
	local H = world()
	local mid = hero(2, 2, Vector(-600, 300))
	local p4 = hero(3, 4, Vector(4000, -6000))
	local p5 = hero(4, 5, Vector(1800, -3000))
	local plan = H.RunePlan.Make(320, function() return false end)
	check("plan: the mid takes the spot nearer it", plan.mid == mid and plan.midSpot == P1, plan.midSpot)
	check("plan: the free support nearer the other spot takes it", plan.sup == p5 and plan.supSpot == P2)
	plan = H.RunePlan.Make(320, function(u) return u == p5 end)
	check("plan: a support on a stack is not free", plan.sup == p4)
end

-- The mid's trip runs in the rune mode: the chooser's gates leave that mode and its exceptions to the mode file and hold
-- the others, the farm host included, at 0 (rspchk1: the rune mode gated to 0 lost the mid to the attack mode, 9 of 10).
do
	local H = world({ t = 341 })
	SPAWN_AT = P1
	local mid = hero(2, 2, Vector(-600, 300))
	capture(function() while H.RuneJob.HostOf(mid) == nil and T < 350 do frame(H, { mid }, 360) end end)
	check("mid gate: its trip runs in the rune mode", H.RuneJob.HostOf(mid) == dota.BotMode.Rune, T)
	check("mid gate: the rune mode keeps the trip's desire", H.Chooser.Gate(mid, "rune", function() return 0.97 end)() == 0.97)
	check("mid gate: the farm host is held at 0", H.Chooser.Gate(mid, "farm", function() return 0.6 end)() == 0)
	check("mid gate: retreat stays OHA's", H.Chooser.Gate(mid, "retreat", function() return 0.8 end)() == 0.8)
end

-- Stand points: on the high ground and on our side when the map has it.
do
	local H = world()
	local bot = hero(3, 4, Vector(-3500, -500))
	local st = H.RunePlan.StandFor(bot, SPOT[P1])
	check("stand: higher than the spot", st.height > st.spotHeight, st.height)
	check("stand: within the rings", dist(st.at, SPOT[P1]) >= 500 and dist(st.at, SPOT[P1]) <= 1000)
end

-- Pos4 alone (no mid): it goes, hides at its stand, walks in on time and takes the rune at its spot with no enemy near.
do
	local H = world()
	SPAWN_AT = P1
	local bot = hero(3, 4, Vector(-4200, -1200))
	local out = run(H, { bot }, 368)
	local l = lines(out, "rune_job")[1]
	local plan = lines(out, "rune_plan")[1]
	check("pos4: the plan has no mid and gives pos4 a spot", plan ~= nil and field(plan, "why") == "no-mid" and field(plan, "sup") == "3", plan)
	check("pos4: hid at the stand before walking in", l ~= nil and tonumber(field(l, "hid") or "0") > 0, l)
	check("pos4: took the rune (first, no enemy)", field(l, "phase") == "take" and field(l, "res") == "ok", l)
	check("pos4: reached the spot by the spawn", tonumber(field(l, "arr")) <= 360.5, l)
end

-- The second support is not sent: its spot went to the mid.
do
	local H = world()
	SPAWN_AT = P1
	local mid = hero(2, 2, Vector(-600, 300))
	local p4 = hero(3, 4, Vector(1500, -3500))
	local p5 = hero(4, 5, Vector(-4000, -2000))
	local out = run(H, { mid, p4, p5 }, 368)
	local skipped, midLine
	for _, l in ipairs(lines(out, "rune_job")) do
		if field(l, "pid") == "4" and field(l, "kind") == "power" then skipped = l end
		if field(l, "pid") == "2" then midLine = l end
	end
	check("the other support skips with plan-other", skipped ~= nil and field(skipped, "res") == "skip" and field(skipped, "why") == "plan-other", skipped)
	check("the mid takes the rune at its spot through the rune mode", midLine ~= nil and field(midLine, "phase") == "take" and field(midLine, "res") == "ok", midLine)
end

-- The planned support's start gate drops it (low HP at its leave time): the spot goes to the other support, skipped as
-- plan-other at the plan, which starts late, walks straight in and still takes the rune (rspchk2: 3 of 10 plans uncovered).
do
	local H = world()
	SPAWN_AT = P2
	local mid = hero(2, 2, Vector(-600, 300))
	local p4 = hero(3, 4, Vector(1500, -3500))
	local p5 = hero(4, 5, Vector(-1000, -2500))
	p4.hp, p4.maxhp = 10, 100
	local out = run(H, { mid, p4, p5 }, 368)
	local plans = lines(out, "rune_plan")
	local first, swap = plans[1], plans[#plans]
	local p4Line, p5Lines = nil, {}
	for _, l in ipairs(lines(out, "rune_job")) do
		if field(l, "pid") == "3" and field(l, "kind") == "power" then p4Line = l end
		if field(l, "pid") == "4" and field(l, "kind") == "power" then table.insert(p5Lines, l) end
	end
	check("drop: the plan names pos4 first", field(first, "sup") == "3", first)
	check("drop: pos4's gate skips it with its reason", field(p4Line, "res") == "skip" and field(p4Line, "why") == "low-hp", p4Line)
	check("drop: the plan hands the spot to pos5", #plans == 2 and field(swap, "sup") == "4" and field(swap, "ss") == tostring(P2) and field(swap, "why") == "swap:low-hp", swap)
	local last = p5Lines[#p5Lines]
	check("drop: pos5 skipped at the plan, then took the rune at the spot", #p5Lines == 2 and field(p5Lines[1], "why") == "plan-other"
		and field(last, "phase") == "take" and field(last, "res") == "ok" and tonumber(field(last, "arr")) <= 360.5, last)
end

-- No support to hand the spot to: the plan logs the drop and nobody else is sent.
do
	local H = world()
	SPAWN_AT = P2
	local mid = hero(2, 2, Vector(-600, 300))
	local p4 = hero(3, 4, Vector(1500, -3500))
	p4.hp, p4.maxhp = 10, 100
	local out = run(H, { mid, p4 }, 368)
	local plans = lines(out, "rune_plan")
	check("drop, no one free: the plan logs drop with no support", #plans == 2 and field(plans[2], "why") == "drop:low-hp" and field(plans[2], "sup") == nil, plans[2])
end

-- The mid's trip has an HP gate: under half HP at its leave time it is held, then skipped with low-hp, and no trip runs.
do
	local H = world()
	SPAWN_AT = P1
	local mid = hero(2, 2, Vector(-600, 300))
	mid.hp, mid.maxhp = 30, 100
	local out = run(H, { mid }, 368)
	local l = lines(out, "rune_job")[1]
	check("mid gate: low HP skips the trip", l ~= nil and field(l, "res") == "skip" and field(l, "why") == "low-hp" and #lines(out, "rune_job") == 1, l)
end

-- The race at the spawn: an enemy hero beside the spot. A ranged hero whose hit lands first denies, a melee one stays off.
do
	local H = world()
	local bot = hero(3, 4, Vector(-1640 - 700, 1112))
	local enemy = hero(9, 3, Vector(-1640 + 250, 1112), DIRE)
	enemy.speed = 300
	status[P1] = RUNE_STATUS_AVAILABLE
	bot.attackRange = 600
	bot.GetAttackRange = function() return 600 end
	check("race: a ranged hero second to the rune denies it", H.RunePlan.Race(bot, P1)[1] == "deny")
	bot.GetAttackRange = function() return 150 end
	check("race: a melee hero second to the rune stays off", H.RunePlan.Race(bot, P1)[1] == "off")
	enemy.loc = Vector(5000, 5000)
	check("race: first to the rune takes it", H.RunePlan.Race(bot, P1)[1] == "take")
end

-- The rune spawned at the other spot: cross when the planned holder there is dead and no enemy beats us; else none.
do
	local H = world()
	local mid = hero(2, 2, Vector(-600, 300))
	local p4 = hero(3, 4, Vector(1180, -1216))
	H.RunePlan.For(RAD, function() return false end, 320)
	status[P1] = RUNE_STATUS_AVAILABLE
	check("other spot: its holder alive and nearer, no cross", H.RunePlan.Race(p4, P2)[1] == "none")
	mid.alive = false
	p4.loc = Vector(-300, 0)
	check("other spot: its holder dead, we beat every enemy: cross", H.RunePlan.Race(p4, P2)[1] == "cross")
end

-- Switch off: the plain trip (no plan, no stand).
do
	local H = world({ spawn = false })
	SPAWN_AT = P1
	local bot = hero(3, 4, Vector(-4200, -1200))
	local out = run(H, { bot }, 368)
	check("switch off: no plan and no hide", #lines(out, "rune_plan") == 0 and field(lines(out, "rune_job")[1], "hid") == nil)
end

local function draws(H, x) H.Lane.Config.SetRng(function() return { random = function() return x end, gauss = function() return 0 end } end) end
meta.Action_AttackUnit = function(self, u) table.insert(ACTIONS, { pid = self.pid, kind = "AttackUnit", args = { u } }) end

-- After the trip: a gank chance on the nearest enemy hero in reach. A low draw fires it and the support goes in; the play
-- ends with a line, and the trip's line names it.
do
	local H = world()
	SPAWN_AT = P1
	draws(H, 0.0)
	local bot = hero(3, 4, Vector(-4200, -1200))
	local enemy = hero(9, 2, Vector(-200, 400), DIRE)
	enemy.speed = 0
	local out = run(H, { bot }, 400)
	local trip = lines(out, "rune_job")[1]
	local roll, ended
	for _, l in ipairs(lines(out, "play")) do if field(l, "kind") == "gank" then roll = l end end
	ended = lines(out, "play_end")[1]
	check("gank: rolled after the trip and fired", roll ~= nil and field(roll, "fire") == "1", roll)
	check("gank: the support attacked its target", (function() for _, a in ipairs(ACTIONS) do if a.pid == 3 and a.kind == "AttackUnit" and a.args[1] == enemy then return true end end end)())
	check("gank: the play ended with a line, the trip names it", ended ~= nil and field(trip, "gank") == field(roll, "id"), tostring(trip) .. " / " .. tostring(ended))
end

-- A high draw: the chance is logged and nothing fires; the support's trip ends as before.
do
	local H = world()
	SPAWN_AT = P1
	draws(H, 0.99)
	local bot = hero(3, 4, Vector(-4200, -1200))
	hero(9, 2, Vector(-200, 400), DIRE)
	local out = run(H, { bot }, 375)
	local roll = lines(out, "play")[1]
	check("gank not fired: logged with fire=0, no play end", roll ~= nil and field(roll, "fire") == "0" and #lines(out, "play_end") == 0, roll)
end

-- The enemy shrine: a free pos5 rolls at its leave time; a miss skips with why=roll, a hit walks it there to channel.
do
	local H = world({ t = 395 })
	draws(H, 0.99)
	local p5 = hero(4, 5, Vector(6500, -1500))
	local out = run(H, { p5 }, 412)
	local l
	for _, x in ipairs(lines(out, "rune_job")) do if field(x, "kind") == "contest" then l = x end end
	check("shrine: a missed roll skips the contest", l ~= nil and field(l, "res") == "skip" and field(l, "why") == "roll", l)
	H = world({ t = 395 })
	draws(H, 0.0)
	p5 = hero(4, 5, Vector(6500, -1500))
	run(H, { p5 }, 412)
	check("shrine: a fired roll sends the pos5 to the enemy shrine", H.RuneJob.Running(p5) and dist(p5.loc, Vector(8029, -1126)) < dist(Vector(6500, -1500), Vector(8029, -1126)))
end

-- An enemy hero on the spot at the spawn: the rune-fight roll; fired, the support fights it instead of the race's act.
do
	local H = world()
	SPAWN_AT = P1
	draws(H, 0.0)
	local bot = hero(3, 4, Vector(-4200, -1200))
	local enemy = hero(9, 4, Vector(-1640 + 300, 1112), DIRE)
	enemy.speed = 0
	local out = run(H, { bot }, 368)
	local fight
	for _, l in ipairs(lines(out, "play")) do if field(l, "kind") == "rune_fight" then fight = l end end
	check("rune fight: rolled on the enemy at the spot and fired", fight ~= nil and field(fight, "fire") == "1" and field(fight, "tgt") == "9", fight)
end

finish()
