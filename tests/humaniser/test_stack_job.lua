dofile(HARNESS_DIR .. "/lane_world.lua")
-- Slice 4: StackJob (Ours.StackExecute), the pos5's stack on a placeholder trigger, with the humaniser off as in the
-- slice's arms. E1 geometry and timing per camp on the 7.41 spawner origins, then the trigger, gate and outcome line.
local dota = require("bots/ts_libs/dota/index")
local FARM, LANING = dota.BotMode.Farm, dota.BotMode.Laning
local RAD, DIRE = dota.Team.Radiant, dota.Team.Dire
local BUNDLE = "bots/FunLib/engine/tasks"

-- 7.41 spawner origins (test_lane_camps.lua's MAP_SPAWNERS, from maps/dota.vpk); boxes are 300 wide here.
local MAP = {
	{ "evil_1", DIRE, "large", -4824, 3915 }, { "evil_11", DIRE, "small", -2880, 7376 }, { "evil_12", DIRE, "medium", 2016, 7896 },
	{ "evil_13", DIRE, "small", 8430, 1263 }, { "evil_14", DIRE, "medium", 336, 7696 }, { "evil_15", DIRE, "medium", -2596, 3850 },
	{ "evil_2", DIRE, "small", -3911, 4829 }, { "evil_20", DIRE, "medium", -4208, 8336 }, { "evil_4", DIRE, "medium", 1224, 4176 },
	{ "evil_5", DIRE, "large", 1064, 2580 }, { "evil_6", DIRE, "medium", -852, 4940 }, { "evil_7", DIRE, "large", 7928, -120 },
	{ "evil_8", DIRE, "ancient", 4352, 48 }, { "evil_9", DIRE, "medium", 3392, -1408 },
	{ "good_1", RAD, "small", 3978, -5027 }, { "good_11", RAD, "medium", -720, -7696 }, { "good_12", RAD, "medium", -2415, -8402 },
	{ "good_13", RAD, "large", -8313, -553 }, { "good_14", RAD, "small", 2768, -8336 }, { "good_15", RAD, "medium", 1922, -3975 },
	{ "good_16", RAD, "small", -8023, -1838 }, { "good_2", RAD, "large", 4649, -3699 }, { "good_20", RAD, "medium", 4416, -8432 },
	{ "good_4", RAD, "medium", 186, -5197 }, { "good_5", RAD, "large", -1454, -3356 }, { "good_7", RAD, "medium", -4013, 992 },
	{ "good_8", RAD, "ancient", -5015, -96 }, { "good_9", RAD, "medium", -1983, -4815 },
}
-- Where each team's safe-lane pos5 stands at the trigger: beside its T1 (MAP_TOWERS in test_lane_camps.lua).
local SAFE_T1 = { [RAD] = Vector(4860, -6379), [DIRE] = Vector(-5275, 6036) }

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function world(o)
	o = o or {}
	package.loaded[BUNDLE] = nil
	local H = LaneFresh({ Enable = true }, { enable = false, skill = 1, telemetry = { Enable = true } })
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	if o.ours ~= nil then Customize.Ours = o.ours end
	T = o.t or 200
	CURRENT_TEAM = 2
	FOGGED = o.fogged
	SPAWNERS = {}
	for _, s in ipairs(MAP) do
		table.insert(SPAWNERS, { team = s[2], type = s[3], location = Vector(s[4], s[5], 0), min = Vector(s[4] - 150, s[5] - 150, 0),
			max = Vector(s[4] + 150, s[5] + 150, 0), speed = 0 })
	end
	H.Lane.Camps.ResetCache()
	H.StackJob.ResetCache()
	local bot = MakeUnit({ pid = 5, team = 2, loc = o.at or SAFE_T1[RAD] })
	bot.pos = o.pos or 5
	return H, bot
end

local function idxOf(name) for i, s in ipairs(MAP) do if s[1] == name then return i end end end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

local function stackLines(lines)
	local r = {}
	for _, l in ipairs(lines) do if l:find("ev=stack ", 1, true) then table.insert(r, l) end end
	return r
end

local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

-- One frame: farm's GetDesire, then its Think when farm wins. Moves arrive at once; a neutral hit turns on the bot.
local function frame(H, bot, dt)
	local n0 = #ACTIONS
	if H.StackJob.Desire(bot) > 0 then
		bot.mode = FARM
		H.StackJob.Think(bot)
	else
		bot.mode = LANING
	end
	for i = #ACTIONS, n0 + 1, -1 do
		local a = ACTIONS[i]
		if a.pid == bot.pid and a.kind == "MoveToLocation" then bot.loc = Vector(a.args[1].x, a.args[1].y) break end
	end
	for i = n0 + 1, #ACTIONS do
		local a = ACTIONS[i]
		if a.pid == bot.pid and a.kind == "AttackUnit" and a.args[1].team == 4 then a.args[1].target = bot end
	end
	T = T + (dt or 0.1)
end

local function neutrals(at, n)
	for i = 1, n do MakeNeutral({ x = at.x + i * 10, y = at.y }) end
end

-- E1: geometry and timing per camp, both teams.
do
	local H = world()
	local C, S = H.Lane.Camps, H.Lane.Stacking
	local R = H.Lane.Config.Settings().Radii
	for _, team in ipairs({ RAD, DIRE }) do
		local cands = H.StackJob.Candidates(team)
		check("candidates found for team " .. team, #cands >= 8, #cands)
		for _, data in ipairs(cands) do
			local name = MAP[data.campIdx][1]
			local sp = C.SpawnerByIdx(data.campIdx)
			check(name .. ": own side, not ancient", sp.team == team and sp.type ~= "ancient")
			local stand = H.StackJob.Stand(sp, data)
			check(name .. ": stand point outside the box", not C.InBox(data.campIdx, stand, 0))
			check(name .. ": stand point within reach of the origin", dist(stand, sp.location) <= R.StandReach + 300, dist(stand, sp.location))
			local path = H.StackJob.ExitPath(sp, data)
			local exit = path[#path]
			check(name .. ": exit ends outside the box and its margin", not C.InBox(data.campIdx, exit, R.BoxMargin))
			local from, to = S.Window(data.campIdx)
			local sec = H.StackJob.HitSec(sp, data)
			check(name .. ": hit second inside Valve's window", from ~= nil and sec >= from and sec <= to, tostring(sec) .. " vs " .. tostring(from) .. "-" .. tostring(to))
		end
	end
	-- Nearest camp to each team's safe-lane pos5 spot.
	local r = H.StackJob.Nearest(RAD, SAFE_T1[RAD])
	check("radiant safe-lane pos5 stacks good_1", r and MAP[r.campIdx][1] == "good_1", r and MAP[r.campIdx][1])
	local d = H.StackJob.Nearest(DIRE, SAFE_T1[DIRE])
	check("dire safe-lane pos5 stacks evil_2", d and MAP[d.campIdx][1] == "evil_2", d and MAP[d.campIdx][1])
end

-- Hand-set walk-offs (user 30/10/2026): good_1 runs east along the bottom lane, evil_2 west along the top lane.
do
	local H = world()
	local C = H.Lane.Camps
	for _, c in ipairs({ { "good_1", 1 }, { "evil_2", -1 } }) do
		local sp = C.SpawnerByIdx(idxOf(c[1]))
		local data = C.ByIdx(sp.idx, sp.team)
		local exit = H.StackJob.ExitPath(sp, data)[1]
		check(c[1] .. ": walk-off along the lane", (exit.x - sp.location.x) * c[2] > 800 and math.abs(exit.y - sp.location.y) < 50, exit.x .. "," .. exit.y)
		local stand = H.StackJob.Stand(sp, data)
		check(c[1] .. ": stands on the walk-off side", (stand.x - sp.location.x) * c[2] > 0, stand.x)
	end
end
do
	local H = world()
	local C = H.Lane.Camps
	local sp = C.SpawnerByIdx(idxOf("evil_1"))
	local data = C.ByIdx(sp.idx, sp.team)
	local exit = H.StackJob.ExitPath(sp, data)[1]
	local dx, dy = exit.x - sp.location.x, exit.y - sp.location.y
	check("evil_1: walk-off north", dy > 800 and math.abs(dx) < 50, exit.x .. "," .. exit.y)
	local stand = H.StackJob.Stand(sp, data)
	check("evil_1: stands north of the camp", stand.y > sp.location.y and math.abs(stand.x - sp.location.x) < 50, stand.x .. "," .. stand.y)
	-- Measured hit second (s4solo7/8: hits confirmed from 55.0 on mostly missed); others keep Stacking.AggroSec.
	check("evil_1: hit second 54.4", H.StackJob.HitSec(sp, data) == 54.4, H.StackJob.HitSec(sp, data))
	local g = C.SpawnerByIdx(idxOf("good_2"))
	local gd = C.ByIdx(g.idx, g.team)
	check("good_2: hit second from Stacking.AggroSec", H.StackJob.HitSec(g, gd) == H.Lane.Stacking.AggroSec(gd))
end

-- Only the pos5 with the switch on; switch off (the OFF arm) never stacks.
do
	local H, bot = world({ t = 233 })
	bot.pos = 4
	check("pos4: no job", H.StackJob.Desire(bot) == 0)
	H, bot = world({ t = 233, ours = { StackExecute = false } })
	local lines = capture(function() for _ = 1, 400 do frame(H, bot) end end)
	check("switch off: no job and no line", #stackLines(lines) == 0 and bot.mode == LANING, #stackLines(lines))
	check("switch off: Tasks stay off with the humaniser off", H.Tasks.Enabled() == false and package.loaded[BUNDLE] == nil)
end

-- A full stack at 3:5x on good_1: starts in time, hit inside the window, outcome stacked, away <= 25 s.
local function stackRun(o)
	o = o or {}
	local H, bot = world({ t = 3 * 60 + 15, fogged = o.fogged })
	local camp = SPAWNERS[idxOf("good_1")].location
	neutrals(camp, 3)
	local lines = capture(function()
		-- blind: until the hit a neutral is seen only within 350 of the bot (trees or high ground; lich saw evil_1 from 274, not 428).
		local function step()
			if o.blind then local blind = T < 4 * 60 - 3 for _, n in ipairs(NEUTRALS) do n.unseen = blind and dist(bot.loc, n.loc) > 350 end end
			if o.onFrame then o.onFrame(H, bot) end
			frame(H, bot)
		end
		while T < 4 * 60 do step() end
		if not o.noSpawn then neutrals(camp, 3) end
		while T < 4 * 60 + 8 do step() end
	end)
	return stackLines(lines), H, bot
end

do
	local lines, H = stackRun()
	local l = lines[1]
	check("one line for the minute", #lines == 1, #lines)
	check("stacked", field(l, "res") == "stacked", l)
	check("camp good_1", tonumber(field(l, "camp")) == idxOf("good_1"), l)
	local from, to = H.Lane.Stacking.Window(idxOf("good_1"))
	local aggro = tonumber(field(l, "aggro"))
	check("hit inside the window (1 s slack for the confirm)", aggro ~= nil and aggro >= from - 0.5 and aggro <= to + 1, l)
	check("before 3, after 6", field(l, "before") == "3" and field(l, "after") == "6", l)
	local away = tonumber(field(l, "away"))
	check("away at most 25 s", away ~= nil and away <= 25, l)
	check("no death", field(l, "death") == "0", l)
	-- Stub neutrals never move, so box59 stays 3 here; the sample is taken with the bot out of the box at the exit point.
	check(":59.5 sample taken: bot outside the box, at the exit", tonumber(field(l, "box59")) ~= nil and field(l, "bot59") == "0" and field(l, "exit59") == "0", l)
	check("started just in time (after 3:40)", tonumber(field(l, "start")) >= 220, l)
	-- Phases and per-neutral state (user replay s4solo1: a cask and a neutral left in the box were not in the log).
	local arr, hit0, exit = tonumber(field(l, "arr")), tonumber(field(l, "hit0")), tonumber(field(l, "exit"))
	check("phases: at the stand, then hit order, then walk-off", arr ~= nil and hit0 ~= nil and exit ~= nil and arr <= hit0 and hit0 <= exit, l)
	check("hp at the hit order and walk-off", tonumber(field(l, "hpa")) ~= nil and tonumber(field(l, "hpe")) ~= nil and tonumber(field(l, "hp59")) ~= nil, l)
	check("no cast: casts=-", field(l, "casts") == "-", l)
	local n59 = field(l, "n59") or ""
	local _, kobolds = n59:gsub("kobold:%d+:in:", "")
	check("n59: the three camp neutrals, still in the box (stubs do not move)", kobolds == 3, n59)
	check("n2 sampled", (field(l, "n2") or "?") ~= "?", l)
	check("no lane creeps near the camp: lane=0", field(l, "lane") == "0", l)
end

-- A wave dragged into the camp (user watching s4solo7ab: evil_1's north-west route pulled the top lane): two creeps of each
-- team reach the camp after the hit, one stays on the lane.
do
	local placed = false
	local lines = stackRun({ onFrame = function()
		if placed or T < 3 * 60 + 58 then return end
		placed = true
		local c = SPAWNERS[idxOf("good_1")].location
		for _, team in ipairs({ 2, 3 }) do
			for i = 1, 2 do MakeCreep({ team = team, x = c.x + 100 * i, y = c.y + 200 }) end
		end
		MakeCreep({ team = 3, x = c.x + 1500, y = c.y })
	end })
	check("pull: four lane creeps near the camp, lane=4", field(lines[1] or "", "lane") == "4", lines[1])
end

-- Spells and items wait while the job runs (a cask before the hit drew the camp early, s4solo2); an enemy hero in reach
-- lifts the hold; no job, no hold.
do
	local before, during, enemy = nil, false, nil
	stackRun({ onFrame = function(H, bot)
		if before == nil then before = H.StackJob.HoldsCasts(bot) end
		if H.StackJob.HoldsRun(bot) and H.StackJob.HoldsCasts(bot) then during = true end
		if H.StackJob.HoldsRun(bot) and enemy == nil and T >= 3 * 60 + 56 then
			local e = MakeUnit({ pid = 12, team = 3, loc = Vector(bot.loc.x + 300, bot.loc.y) })
			enemy = H.StackJob.HoldsCasts(bot)
			e.alive = false
			for i, u in ipairs(UNITS[3]) do if u == e then table.remove(UNITS[3], i) break end end
		end
	end })
	check("no job yet: casts free", before == false)
	check("job running: casts held", during)
	check("enemy hero in reach: hold lifted", enemy == false, tostring(enemy))
end

-- A spell cast while the job runs is logged with its second (witch doctor's cask, s4solo1 3:5x).
do
	local cask = { GetName = function() return "witch_doctor_paralyzing_cask" end }
	local lines = stackRun({ onFrame = function(_, bot) bot.casting = (T >= 3 * 60 + 55 and T < 3 * 60 + 55.3) and cask or nil end })
	check("cast logged once with its second", (field(lines[1], "casts") or ""):match("^witch_doctor_paralyzing_cask@55%.%d$") ~= nil, lines[1])
end

-- Neutrals that walk back into the box after :00 are not a spawn (s4solo3 11:0x, 12:0x: after rose by one with the box
-- occupied): the outcome counts only neutrals the bot had not seen before the spawn check.
do
	local phase = "in"
	local lines = stackRun({ noSpawn = true, onFrame = function()
		local shift = (phase == "in" and 700) or (phase == "out" and T >= 4 * 60 + 1 and -700) or nil
		if shift == nil then return end
		for i = 2, 3 do NEUTRALS[i].loc = Vector(NEUTRALS[i].loc.x + shift, NEUTRALS[i].loc.y) end
		phase = phase == "in" and "out" or "back"
	end })
	local l = lines[1]
	check("returning neutrals: before 1, after 3", field(l, "before") == "1" and field(l, "after") == "3", l)
	check("returning neutrals: fresh 0, not stacked", field(l, "fresh") == "0" and field(l, "res") == "not_stacked", l)
end

-- A stand point the bot cannot reach (trees): ~300 short and no closer for 1.5 s counts as reached, so the job waits and
-- hits instead of failing late (s4solo5: omniknight short of evil_1's lane-side stand, 15 of 20 Dire attempts late).
do
	local st
	local lines = stackRun({ onFrame = function(H, bot)
		if st == nil then
			local sp = SPAWNERS[idxOf("good_1")]
			st = H.StackJob.Stand(H.Lane.Camps.SpawnerByIdx(idxOf("good_1")), H.Lane.Camps.ByIdx(idxOf("good_1"), RAD))
		end
		if T < 3 * 60 + 52 and dist(bot.loc, st) < 300 then bot.loc = Vector(st.x, st.y + 300) end
	end })
	check("unreachable stand: not late", field(lines[1], "why") ~= "timeout:late", lines[1])
	check("unreachable stand: waited (arr) before the hit", tonumber(field(lines[1], "arr")) ~= nil and tonumber(field(lines[1], "arr")) < tonumber(field(lines[1], "hit0") or "0"), lines[1])
end

-- Nothing new in the box after :00: not stacked. Box never in sight: not stacked, after=?.
do
	local lines = stackRun({ noSpawn = true })
	check("no spawn: not stacked", field(lines[1], "res") == "not_stacked" and field(lines[1], "after") == "3", lines[1])
	lines = stackRun({ fogged = function() return true end })
	check("fogged: not stacked, after unknown", field(lines[1], "res") == "not_stacked" and field(lines[1], "after") == "?", lines[1])
end

-- Camp unseen from the stand point (evil_1 in probe games 2-3: near=0 at 428 from the origin): the job steps in to
-- StandApproach from the origin StandApproachLead s before the hit, as camp_jobs does, and still stacks.
do
	local held = false
	local lines = stackRun({ blind = true, onFrame = function(H, bot) held = held or H.StackJob.HoldsRun(bot) end })
	check("HoldsRun while the job runs (OHA's creep clause skipped)", held)
	check("unseen from the stand: still stacked", field(lines[1], "res") == "stacked", lines[1])
	check("unseen from the stand: hit inside the window", tonumber(field(lines[1], "aggro") or "99") <= 58, lines[1])
end

-- Gate: an enemy hero near the pos5 for the whole window skips the minute with that reason; OHA's run aborts a job.
do
	local H, bot = world({ t = 3 * 60 + 15 })
	MakeUnit({ pid = 10, team = 3, loc = Vector(SAFE_T1[RAD].x + 500, SAFE_T1[RAD].y) })
	local lines = stackLines(capture(function() while T < 3 * 60 + 58 do frame(H, bot) end end))
	check("enemy near: one skip line", #lines == 1 and field(lines[1], "res") == "skip" and field(lines[1], "why") == "enemy-near", lines[1])

	H, bot = world({ t = 3 * 60 + 15 })
	MakeUnit({ pid = 11, team = 3, loc = Vector(SAFE_T1[RAD].x + 900, SAFE_T1[RAD].y) })
	neutrals(SPAWNERS[idxOf("good_1")].location, 3)
	lines = stackLines(capture(function() while T < 3 * 60 + 50 do frame(H, bot) end end))
	check("lane opponent at 900: the job starts", #lines == 0 and H.StackJob.Desire(bot) > 0)
	check("attack mode: gate says busy", (function() bot.mode = dota.BotMode.Attack return H.StackJob.Gate(bot) == "busy" end)())

	H, bot = world({ t = 3 * 60 + 15 })
	neutrals(SPAWNERS[idxOf("good_1")].location, 3)
	lines = stackLines(capture(function()
		while T < 3 * 60 + 50 do frame(H, bot) end
		H.StackJob.Abort(bot, "run")
		frame(H, bot)
	end))
	check("run abort: failed, cancelled:run", field(lines[1], "res") == "failed" and field(lines[1], "why") == "cancelled:run", lines[1])
	check("run abort: farm released", H.StackJob.Desire(bot) == 0)

	-- Hero damage mid-job ends it (1x probe s4p7: the pos5 walked on after hero hits and died at the camp); an enemy hero
	-- in reach alone does not (probe s4p8: lane opponents ended 4 jobs 1-6 s after their start).
	H, bot = world({ t = 3 * 60 + 15 })
	neutrals(SPAWNERS[idxOf("good_1")].location, 3)
	lines = stackLines(capture(function()
		while T < 3 * 60 + 50 do frame(H, bot) end
		MakeUnit({ pid = 12, team = 3, loc = Vector(bot.loc.x + 300, bot.loc.y) })
		frame(H, bot)
	end))
	check("enemy in reach mid-job: the job runs on", #lines == 0 and H.StackJob.Desire(bot) > 0, lines[1])
	lines = stackLines(capture(function()
		bot.heroHitAt = T
		frame(H, bot)
	end))
	check("hero hit mid-job: failed, cancelled:hit", field(lines[1], "res") == "failed" and field(lines[1], "why") == "cancelled:hit", lines[1])
	check("hero hit mid-job: farm released", H.StackJob.Desire(bot) == 0)
end

-- A start held back by the gate goes ahead only with MinSlack s to spare (probe s4p5: starts at 0 s slack missed the window).
do
	local function heldUntil(slackOf)
		local H, bot = world({ t = 3 * 60 + 15 })
		neutrals(SPAWNERS[idxOf("good_1")].location, 3)
		local data, stand = H.StackJob.Nearest(RAD, SAFE_T1[RAD])
		local walk = dist(bot.loc, stand) / bot:GetCurrentMovementSpeed()
		local free = 3 * 60 + H.Lane.Stacking.AggroSec(data) - walk - slackOf(H)
		local lines = stackLines(capture(function()
			while T < 3 * 60 + 50 do
				if T < free then bot.mode = dota.BotMode.Attack end
				frame(H, bot)
			end
		end))
		return lines
	end
	local lines = heldUntil(function(H) return H.StackJob.SETTINGS.MinSlack + 0.5 end)
	check("busy until MinSlack + 0.5 s left: starts", #lines == 0 or field(lines[1], "res") ~= "skip", lines[1])
	lines = heldUntil(function() return 1 end)
	check("busy until 1 s left: skip busy", #lines == 1 and field(lines[1], "res") == "skip" and field(lines[1], "why") == "busy", lines[1])
end

-- Diagnosis harness (user 30/10/2026): Overrides.Solo benches every other hero in its fountain; StackEvery tries each minute.
do
	local H, bot = world()
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	check("solo off: nobody benched", not H.StackJob.Benched(bot) and not H.StackJob.Bench(bot))
	check("solo off: trigger minutes", #H.StackJob.Minutes() == 3 and H.StackJob.Minutes()[1] == 3)
	Customize.Overrides = { Solo = 5 }
	check("solo is this hero: not benched", not H.StackJob.Benched(bot))
	local other = MakeUnit({ pid = 6, team = 3, loc = Vector(0, 0, 0) })
	check("another hero: benched", H.StackJob.Benched(other) and H.StackJob.Bench(other))
	local mv = ActionsOf(6, "MoveToLocation")
	local to = mv[#mv] and mv[#mv].args[1]
	check("benched: walks to its own fountain", to ~= nil and to.x > 6000 and to.y > 6000, to and (to.x .. "," .. to.y) or "no move")
	local home = MakeUnit({ pid = 1, team = 2, loc = Vector(-6600, -6300, 0) })
	check("benched at the fountain: no move", H.StackJob.Bench(home) and #ActionsOf(1, "MoveToLocation") == 0)
	Customize.Overrides = { Solo = 0 }
	check("solo pid 0 counts", H.StackJob.Benched(bot))
	Customize.Overrides = { StackEvery = true }
	local m = H.StackJob.Minutes()
	check("stack every: from 2:00, each minute", m[1] == 2 and m[2] == 3 and m[3] == 4)
	T = 4 * 60 + 15
	local lines = stackLines(capture(function()
		while T < 4 * 60 + 59 do frame(H, bot) end
	end))
	check("stack every: minute 4 gets an attempt", #lines >= 1 and field(lines[1], "min") == "4", lines[1])
	Customize.Overrides = nil
end

-- Hook (source pin: mode_farm_generic has no test world): the stack job comes first in GetDesire and Think; OHA's run aborts it.
do
	local function source(rel) return io.open(BOTS_ROOT .. '/' .. rel, 'r'):read('a') end
	local function has(text, needle) return text:find(needle, 1, true) ~= nil end
	local farm = source('bots/mode_farm_generic.lua')
	local desire = farm:find('J.Humaniser.StackJob.Desire(bot)', 1, true)
	check('farm: stack desire before the camp-job desire', desire ~= nil and desire < farm:find('J.Humaniser.Lane.CampJobDesire(bot)', 1, true))
	check('farm: stack desire returned when owned', has(farm, 'if nStackDesire > 0 then return nStackDesire end'))
	local think = farm:find('J.Humaniser.StackJob.Think(bot)', 1, true)
	check('farm: stack Think first', think ~= nil and think < farm:find('J.Humaniser.Lane.CampJobThink(bot)', 1, true))
	check('farm: OHA run aborts the job', has(farm, 'J.Humaniser.StackJob.Abort(bot, "run")'))
	-- A benched hero (Overrides.Solo) wins farm before OHA's run and defend-ping checks, and its Think comes first.
	local bench = farm:find('if J.Humaniser.StackJob.Benched(bot) then return BOT_MODE_DESIRE_ABSOLUTE * 1.2 end', 1, true)
	check('farm: bench desire first', bench ~= nil and bench < farm:find('function GetDesireHelper', 1, true))
	local benchThink = farm:find('if J.Humaniser.StackJob.Bench(bot) then return end', 1, true)
	check('farm: bench Think before the stack Think', benchThink ~= nil and benchThink < think)
	local usage = source('bots/ability_item_usage_generic.lua')
	local _, holds = usage:gsub('if J.Humaniser.StackJob.HoldsCasts%(bot%) then return end', '')
	check('usage: spells and items held for the stack job and the bench', holds == 2, holds)
	-- OHA's creep clause in ShouldRun skips a running stack job (probe s4p4: 5 of 9 attempts cancelled after the hit).
	check('farm: creep clause holds for the stack job', has(farm, "and not J.Humaniser.Lane.CampJobHoldsRetreat(bot)\n\tand not J.Humaniser.StackJob.HoldsRun(bot) then"))
	-- A defend ping zeroes farm before the hook (probe s4p2: three `preempted:stalled`); the job ends with its reason.
	local ping = farm:find("defendPings'%]%.pingedTime <= 5%.0 then")
	local abort = farm:find('J.Humaniser.StackJob.Abort(bot, "defend-ping")', 1, true)
	check('farm: a defend ping aborts the job', ping ~= nil and abort ~= nil and abort > ping and abort - ping < 200, tostring(ping) .. ' ' .. tostring(abort))
end

finish()
