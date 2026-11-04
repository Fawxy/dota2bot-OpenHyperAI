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

-- One frame: supports through the job chooser's farm host, the mid through the rune mode's branch. Moves land at once,
-- capped at the hero's speed per frame so walks take their time.
local function frame(H, bots, spawnAt)
	for _, bot in ipairs(bots) do
		local n0 = #ACTIONS
		if bot.pos == 2 then
			if H.RuneJob.MidWants(bot) then bot.mode = dota.BotMode.Rune H.RuneJob.MidStep(bot) else bot.mode = LANING end
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
		if field(l, "pid") == "4" then skipped = l end
		if field(l, "pid") == "2" then midLine = l end
	end
	check("the other support skips with plan-other", skipped ~= nil and field(skipped, "res") == "skip" and field(skipped, "why") == "plan-other", skipped)
	check("the mid takes the rune at its spot through the rune mode", midLine ~= nil and field(midLine, "phase") == "take" and field(midLine, "res") == "ok", midLine)
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

finish()
