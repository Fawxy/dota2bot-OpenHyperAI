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
	-- Slice 4's single-stack tests run with the double off; the double-stack tests below pass double = true.
	if Customize.Ours ~= nil then Customize.Ours.DoubleStack = o.double == true end
	-- The 6:00 rune claim (slice rune-rotation) holds the pos4's 5:5x stack back; these tests run the stack alone unless rune = true.
	Customize.Ours = Customize.Ours or {}
	Customize.Ours.RuneRotation = o.rune == true
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

-- Farm's GetDesire and Think as the file's wrapper line builds them; inner stands in for OHA's file past its hook lines.
local function farmDesire(H, bot, inner)
	return H.Chooser.Gate(bot, "farm", inner or function() return H.Chooser.FarmDesire(bot) end)()
end
local function farmThink(H, bot, inner, cannotAct)
	return H.Chooser.HostThink(bot, "farm", inner or function() return H.Chooser.FarmThink(bot) end, cannotAct or function() return false end)()
end

-- One frame: farm's GetDesire, then its Think when farm wins. Moves arrive at once; a neutral hit turns on the bot.
local function frame(H, bot, dt)
	local n0 = #ACTIONS
	if farmDesire(H, bot) > 0 then
		bot.mode = FARM
		farmThink(H, bot)
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
			local sec = S.AggroSec(data)
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
end
-- evil_13, the Dire shrine pair's easy camp (user replay review of dsolo4b, 31/10/2026): south, towards the offlane, not
-- north-west towards mid; south-west since 01/11/2026, where its stand sees the camp (visprobe1/2).
do
	local H = world()
	local C = H.Lane.Camps
	local sp = C.SpawnerByIdx(idxOf("evil_13"))
	local data = C.ByIdx(sp.idx, sp.team)
	local exit = H.StackJob.ExitPath(sp, data)[1]
	local dx, dy = exit.x - sp.location.x, exit.y - sp.location.y
	check("evil_13: walk-off south-west", dy < -500 and dx < -500, exit.x .. "," .. exit.y)
	local stand = H.StackJob.Stand(sp, data)
	check("evil_13: stands south-west of the camp", stand.y < sp.location.y and stand.x < sp.location.x, stand.x .. "," .. stand.y)
end
-- The shrine pairs' camp B walks on to its wisdom shrine (user 31/10/2026): good_13 north. evil_7's south-east route was
-- blocked from a stand that sees the camp (fresh7c, fresh8c), north-east ran into the map edge (fresh9c); it stands
-- north-east (vision probe test below) and walks off north, clear of evil_13's box.
do
	local H = world({})
	local C = H.Lane.Camps
	local e7 = C.SpawnerByIdx(idxOf("evil_7"))
	local ex = H.StackJob.ExitPath(e7, C.ByIdx(e7.idx, e7.team))[1]
	check("evil_7: walk-off north, west of evil_13's box", ex.y > e7.location.y + 800 and ex.x < 8192, ex.x .. "," .. ex.y)
	for _, c in ipairs({ { "good_13", -7948, 768 } }) do
		local sp = C.SpawnerByIdx(idxOf(c[1]))
		local exit = H.StackJob.ExitPath(sp, C.ByIdx(sp.idx, sp.team))[1]
		local shrine = Vector(c[2], c[3])
		check(c[1] .. ": walk-off towards its shrine", dist(exit, shrine) < dist(sp.location, shrine), exit.x .. "," .. exit.y)
		local stand = H.StackJob.Stand(sp, C.ByIdx(sp.idx, sp.team))
		check(c[1] .. ": stands east of the camp (the walk from A passes B's east side)", stand.x > sp.location.x + 200, stand.x .. "," .. stand.y)
	end
end

-- Overrides.ShrineLane: the shrine pairs' lane route (user 31/10/2026), Radiant's B walks off east, Dire's west.
do
	local H = world({})
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	Customize.Overrides = Customize.Overrides or {}
	Customize.Overrides.ShrineLane = true
	local C = H.Lane.Camps
	for _, c in ipairs({ { "good_13", 1 }, { "evil_7", -1 } }) do
		local sp = C.SpawnerByIdx(idxOf(c[1]))
		local exit = H.StackJob.ExitPath(sp, C.ByIdx(sp.idx, sp.team))[1]
		local dx, dy = exit.x - sp.location.x, exit.y - sp.location.y
		check(c[1] .. ": ShrineLane walk-off " .. (c[2] > 0 and "east" or "west"), dx * c[2] > 800 and math.abs(dy) < 50, exit.x .. "," .. exit.y)
	end
	-- Dire stands on the north side, between the camps (lsolo4b/4c: the west stand missed every hit).
	local sp = C.SpawnerByIdx(idxOf("evil_7"))
	local stand = H.StackJob.Stand(sp, C.ByIdx(sp.idx, sp.team))
	check("evil_7: ShrineLane stands north of the camp", stand.y > sp.location.y + 200 and math.abs(stand.x - sp.location.x) < 300, stand.x .. "," .. stand.y)
	Customize.Overrides.ShrineLane = false
end

-- Only the pos5 with the switch on; switch off (the OFF arm) never stacks.
do
	do
		-- ev=camp: one line per spawner with its box, once per game (hlog stacktruth.js grades replays with it).
		local H0, bot0 = world({ t = 233 })
		local camps = {}
		for _, l in ipairs(capture(function() for _ = 1, 3 do frame(H0, bot0) end end)) do
			if l:find("ev=camp ", 1, true) then table.insert(camps, l) end
		end
		local g1 = camps[idxOf("good_1")]
		check("ev=camp: one line per spawner, once", #camps == #MAP, #camps)
		check("ev=camp: good_1's box", g1 ~= nil and field(g1, "x0") == "3828" and field(g1, "y1") == "-4877" and field(g1, "type") == "small", g1)
	end
	local H, bot = world({ t = 233 })
	bot.pos = 4
	check("pos4: no job", farmDesire(H, bot) == 0)
	H, bot = world({ t = 233, ours = { StackExecute = false } })
	local lines = capture(function() for _ = 1, 400 do frame(H, bot) end end)
	check("switch off: no job and no line", #stackLines(lines) == 0 and bot.mode == LANING, #stackLines(lines))
	check("switch off: Tasks stay off with the humaniser off", H.Tasks.Enabled() == false and package.loaded[BUNDLE] == nil)
end

-- A full stack at 3:5x on good_1: starts in time, hit inside the window, outcome stacked, away <= 25 s.
local function stackRun(o)
	o = o or {}
	local H, bot = world({ t = 3 * 60 + 15, fogged = o.fogged, double = o.double, at = o.at })
	if o.range then bot.range = o.range end
	local camp = SPAWNERS[idxOf("good_1")].location
	neutrals(camp, o.bN or 3)
	local first = SPAWNERS[idxOf("good_2")].location
	if o.double then MakeNeutral({ x = first.x, y = first.y }) MakeNeutral({ x = first.x + 20, y = first.y }) end
	local lines = capture(function()
		-- blind: until the hit a neutral is seen only within 350 of the bot (trees or high ground; lich saw evil_1 from 274, not 428).
		local function step()
			if o.blind then local blind = T < 4 * 60 - 3 for _, n in ipairs(NEUTRALS) do n.unseen = blind and dist(bot.loc, n.loc) > 350 end end
			if o.onFrame then o.onFrame(H, bot) end
			frame(H, bot)
		end
		while T < 4 * 60 do step() end
		if not o.noSpawn and not o.noBSpawn then neutrals(camp, 3) end
		if o.double and not o.noSpawn then MakeNeutral({ x = first.x + 40, y = first.y }) end
		while T < 4 * 60 + (o.tail or 8) do step() end
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
		if before == nil then before = H.Chooser.HoldsCasts(bot) end
		if H.Chooser.HoldsRun(bot) and H.Chooser.HoldsCasts(bot) then during = true end
		if H.Chooser.HoldsRun(bot) and enemy == nil and T >= 3 * 60 + 56 then
			local e = MakeUnit({ pid = 12, team = 3, loc = Vector(bot.loc.x + 300, bot.loc.y) })
			enemy = H.Chooser.HoldsCasts(bot)
			e.alive = false
			for i, u in ipairs(UNITS[3]) do if u == e then table.remove(UNITS[3], i) break end end
		end
	end })
	check("no job yet: casts free", before == false)
	check("job running: casts held", during)
	check("enemy hero in reach: hold lifted", enemy == false, tostring(enemy))
end

-- Hit telemetry (s4 A_on_1: two `no-aggro` misses could not tell a hit that never landed from a camp slow to react): the
-- second the aimed neutral first lost HP (dmg) and the second a camp neutral first targeted the bot (react).
do
	local lines = stackRun({ onFrame = function(_, bot) for _, n in ipairs(NEUTRALS) do if n.target == bot then n.hp = n.hp - 1 end end end })
	local l = lines[1]
	local hit0, dmg, react = tonumber(field(l, "hit0")), tonumber(field(l, "dmg")), tonumber(field(l, "react"))
	check("dmg and react logged at or after the hit order", hit0 ~= nil and dmg ~= nil and react ~= nil and dmg >= hit0 and react >= hit0, l)
	-- The camp never turns and the hit never lands: both unknown, the attempt fails no-aggro.
	lines = stackRun({ onFrame = function() for _, n in ipairs(NEUTRALS) do n.target = nil end end })
	l = lines[1]
	check("no hit: dmg=? react=?, no-aggro", field(l, "dmg") == "?" and field(l, "react") == "?" and (field(l, "why") or ""):find("no%-aggro") ~= nil, l)
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

-- A camp far from the bot (s4 A_on_4 3:31: lich out of lane, a 14.6 s walk to camp 23, away 30.7): skipped as far under
-- KR S.2's old 25 s away; no blanket limit since 02/11/2026 (user), so the job runs and is never skipped `far`.
do
	local H, bot = world({ t = 3 * 60 + 15, at = Vector(6000, 6000) })
	local lines = stackLines(capture(function() while T < 4 * 60 + 8 do frame(H, bot) end end))
	local far = false
	for _, l in ipairs(lines) do if field(l, "why") == "far" then far = true end end
	check("far camp: no far skip", #lines >= 1 and not far, lines[1])
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
	local lines = stackRun({ blind = true, onFrame = function(H, bot) held = held or H.Chooser.HoldsRun(bot) end })
	check("HoldsRun while the job runs (OHA's creep clause skipped)", held)
	check("unseen from the stand: still stacked", field(lines[1], "res") == "stacked", lines[1])
	check("unseen from the stand: hit inside the window", tonumber(field(lines[1], "aggro") or "99") <= 58, lines[1])
end

-- OHA's idle relocation (jmz_func CheckBotIdleState, every 3 s from team_roam's GetDesire) replaced the hit order with an
-- attack-move to the lane in all 4 slice 4 no-aggro misses (s4 A_on_1 5:55 and 7:53, s4r3 C_on_3 7:54, s4x1 A_on_1 5:55:
-- ev=snap act=5 from the order to the miss). The job holds it while it runs and counts each hold on its line.
do
	local before, during, calls = nil, false, 0
	local lines = stackRun({ onFrame = function(H, bot)
		if before == nil then before = H.Chooser.HoldsIdle(bot) end
		if H.Chooser.HoldsRun(bot) and T >= 3 * 60 + 50 and T < 3 * 60 + 53 then
			during = H.Chooser.HoldsIdle(bot) or during
			calls = calls + 1
		end
	end })
	check("no job yet: idle check free", before == false, tostring(before))
	check("job running: idle check held", during)
	check("holds counted on the line: idle=<calls>", tonumber(field(lines[1], "idle")) == calls and calls > 0, lines[1])
	check("held relocations do not change the outcome", field(lines[1], "res") == "stacked", lines[1])
	local plain = stackRun()
	check("no hold asked: idle=0", field(plain[1], "idle") == "0", plain[1])
	local src = io.open(HARNESS_DIR .. "/../../bots/FunLib/jmz_func.lua", "r"):read("a")
	local body = src:match("function J%.CheckBotIdleState%(%)(.-)\nend\n")
	local hook = body and body:find("J.Humaniser.Chooser.HoldsIdle(bot)", 1, true)
	local clear = body and body:find("bot:Action_ClearActions(true)", 1, true)
	check("CheckBotIdleState asks HoldsIdle before it clears the bot's actions", hook ~= nil and clear ~= nil and hook < clear)
	check("CheckBotIdleState logs ev=oha_idle", body ~= nil and body:find("J.Humaniser.Telemetry.NoteOhaIdle(bot, bHeld)", 1, true) ~= nil)
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
	check("lane opponent at 900: the job starts", #lines == 0 and farmDesire(H, bot) > 0)
	check("attack mode: gate says busy", (function() bot.mode = dota.BotMode.Attack return H.Chooser.MayStart(bot) == "busy" end)())

	H, bot = world({ t = 3 * 60 + 15 })
	neutrals(SPAWNERS[idxOf("good_1")].location, 3)
	lines = stackLines(capture(function()
		while T < 3 * 60 + 50 do frame(H, bot) end
		H.Chooser.Abort(bot, "run")
		frame(H, bot)
	end))
	check("run abort: failed, cancelled:run", field(lines[1], "res") == "failed" and field(lines[1], "why") == "cancelled:run", lines[1])
	check("run abort: farm released", farmDesire(H, bot) == 0)

	-- Hero damage mid-job ends it (1x probe s4p7: the pos5 walked on after hero hits and died at the camp); an enemy hero
	-- in reach alone does not (probe s4p8: lane opponents ended 4 jobs 1-6 s after their start).
	H, bot = world({ t = 3 * 60 + 15, ours = { StackExecute = true, JobChooser = false } })
	neutrals(SPAWNERS[idxOf("good_1")].location, 3)
	lines = stackLines(capture(function()
		while T < 3 * 60 + 50 do frame(H, bot) end
		MakeUnit({ pid = 12, team = 3, loc = Vector(bot.loc.x + 300, bot.loc.y) })
		frame(H, bot)
	end))
	check("enemy in reach mid-job: the job runs on", #lines == 0 and farmDesire(H, bot) > 0, lines[1])
	lines = stackLines(capture(function()
		bot.heroHitAt = T
		frame(H, bot)
	end))
	check("hero hit mid-job: failed, cancelled:hit", field(lines[1], "res") == "failed" and field(lines[1], "why") == "cancelled:hit", lines[1])
	check("hero hit mid-job: farm released", farmDesire(H, bot) == 0)
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
	check("solo off: nobody benched", not H.Chooser.Benched(bot) and not H.Chooser.Bench(bot))
	check("solo off: trigger minutes", #H.StackJob.Minutes() == 3 and H.StackJob.Minutes()[1] == 3)
	Customize.Overrides = { Solo = 5 }
	check("solo is this hero: not benched", not H.Chooser.Benched(bot))
	local other = MakeUnit({ pid = 6, team = 3, loc = Vector(0, 0, 0) })
	check("another hero: benched", H.Chooser.Benched(other) and H.Chooser.Bench(other))
	local mv = ActionsOf(6, "MoveToLocation")
	local to = mv[#mv] and mv[#mv].args[1]
	check("benched: walks to its own fountain", to ~= nil and to.x > 6000 and to.y > 6000, to and (to.x .. "," .. to.y) or "no move")
	local home = MakeUnit({ pid = 1, team = 2, loc = Vector(-6600, -6300, 0) })
	check("benched at the fountain: no move", H.Chooser.Bench(home) and #ActionsOf(1, "MoveToLocation") == 0)
	Customize.Overrides = { Solo = 0 }
	check("solo pid 0 counts", H.Chooser.Benched(bot))
	Customize.Overrides = { StackEvery = true }
	local m = H.StackJob.Minutes()
	check("stack every: from 2:00, each minute", m[1] == 2 and m[2] == 3 and m[3] == 4)
	T = 4 * 60 + 15
	local lines = stackLines(capture(function()
		while T < 4 * 60 + 59 do frame(H, bot) end
	end))
	check("stack every: minute 4 gets an attempt", #lines >= 1 and field(lines[1], "min") == "4", lines[1])
	Customize.Overrides = { StackEvery = 3 }
	m = H.StackJob.Minutes()
	check("stack every 3: every third minute from 2:00", m[1] == 2 and m[2] == 5 and m[3] == 8)
	Customize.Overrides = { Solo = "0,5," }
	check("solo list: a listed hero plays", not H.Chooser.Benched(bot))
	check("solo list: an unlisted one is benched", H.Chooser.Benched(other))
	Customize.Overrides = { Solo = "50," }
	check("solo list: pid 5 is not 50's 5", H.Chooser.Benched(bot))
	Customize.Overrides = nil
end

-- Hook (source pin: mode_farm_generic has no test world): the stack job comes first in GetDesire and Think; OHA's run aborts it.
do
	local function source(rel) return io.open(BOTS_ROOT .. '/' .. rel, 'r'):read('a') end
	local function has(text, needle) return text:find(needle, 1, true) ~= nil end
	local farm = source('bots/mode_farm_generic.lua')
	local desire = farm:find('J.Humaniser.Chooser.FarmDesire(bot)', 1, true)
	check('farm: stack desire before the camp-job desire', desire ~= nil and desire < farm:find('J.Humaniser.Lane.CampJobDesire(bot)', 1, true))
	check('farm: stack desire returned when owned', has(farm, 'if nStackDesire > 0 then return nStackDesire end'))
	local think = farm:find('J.Humaniser.Chooser.FarmThink(bot)', 1, true)
	check('farm: stack Think first', think ~= nil and think < farm:find('J.Humaniser.Lane.CampJobThink(bot)', 1, true))
	check('farm: OHA run aborts the job', has(farm, 'J.Humaniser.Chooser.Abort(bot, "run")'))
	-- A benched hero (Overrides.Solo) wins farm before OHA's run and defend-ping checks, and its Think comes first.
	local bench = farm:find('if J.Humaniser.Chooser.Benched(bot) then return BOT_MODE_DESIRE_ABSOLUTE * 1.2 end', 1, true)
	check('farm: bench desire first', bench ~= nil and bench < farm:find('function GetDesireHelper', 1, true))
	local benchThink = farm:find('if J.Humaniser.Chooser.Bench(bot) then return end', 1, true)
	check('farm: bench Think before the stack Think', benchThink ~= nil and benchThink < think)
	local usage = source('bots/ability_item_usage_generic.lua')
	local _, holds = usage:gsub('if J.Humaniser.Chooser.HoldsCasts%(bot%) then return end', '')
	check('usage: spells and items held for the stack job and the bench', holds == 2, holds)
	-- OHA's creep clause in ShouldRun skips a running stack job (probe s4p4: 5 of 9 attempts cancelled after the hit).
	check('farm: creep clause holds for the stack job', has(farm, "and not J.Humaniser.Lane.CampJobHoldsRetreat(bot)\n\tand not J.Humaniser.Chooser.HoldsRun(bot) then\n"))
	-- cil4: with only the two trade triggers skipped, the tower branches still ran our cores out of their lane.
	check('farm: our core in lane skips every ShouldRun branch (Ours.CoreTrade)', has(farm, 'shouldRunTime = J.Humaniser.CoreTrade.TradeOwnsLaneRun(bot) and 0 or X.ShouldRun(bot);'))
	-- A defend ping zeroes farm before the hook (probe s4p2: three `preempted:stalled`); the job ends with its reason.
	local ping = farm:find("defendPings'%]%.pingedTime <= 5%.0 then")
	local abort = farm:find('J.Humaniser.Chooser.Abort(bot, "defend-ping")', 1, true)
	check('farm: a defend ping aborts the job', ping ~= nil and abort ~= nil and abort > ping and abort - ping < 200, tostring(ping) .. ' ' .. tostring(abort))
	-- Slice job-chooser: the job never names OHA or modes, and OHA's files reach it only through the chooser.
	local jobSrc = source('typescript/bots/FunLib/humaniser/stack_job.ts')
	for _, word in ipairs({ 'BotMode', 'GetActiveMode', 'OHA', 'mode_farm', 'ability_item', 'jmz_func' }) do
		check('StackJob does not mention ' .. word, not has(jobSrc, word))
	end
	for _, rel in ipairs({ 'bots/mode_farm_generic.lua', 'bots/mode_retreat_generic.lua', 'bots/ability_item_usage_generic.lua', 'bots/FunLib/jmz_func.lua' }) do
		check(rel .. ' calls no job', not has(source(rel), 'Humaniser.StackJob'))
	end
end

-- Slice double-stack (Ours.DoubleStack): the safe-lane partners (EC-063), the fit of the walk from A to B's hit, and one
-- minute that stacks both camps.
do
	local H, bot = world({ double = true })
	local C = H.Lane.Camps
	local function partner(name)
		local sp = C.SpawnerByIdx(idxOf(name))
		local p = H.StackJob.Partner(C.ByIdx(sp.idx, sp.team))
		return p and MAP[p.a.campIdx][1]
	end
	check("good_1's partner is good_2", partner("good_1") == "good_2", partner("good_1"))
	check("evil_2's partner is evil_1", partner("evil_2") == "evil_1", partner("evil_2"))
	check("good_5 has no partner", partner("good_5") == nil, partner("good_5"))
	-- From camp A too (ds1: the pos5 stood nearer good_2 or evil_1 in 14 of 20 started attempts); B stays the small camp.
	local fromA = H.StackJob.Partner(C.ByIdx(idxOf("good_2"), RAD))
	check("from good_2: the pair, B good_1", fromA ~= nil and MAP[fromA.a.campIdx][1] == "good_2" and MAP[fromA.b.campIdx][1] == "good_1")
	local function fits(a, b, range)
		bot.range = range
		local sb = C.SpawnerByIdx(idxOf(b))
		local d = H.StackJob.Partner(C.ByIdx(sb.idx, sb.team))
		return d ~= nil and MAP[d.a.campIdx][1] == a and H.StackJob.Fits(bot, d)
	end
	-- EC-063's table: evil_1 then evil_2 fits a ranged hero only.
	check("good_2 then good_1 fits ranged", fits("good_2", "good_1", 550))
	-- EC-063 had it fit a melee hero too; with good_1 hit at :55 (dsvA, 02/11/2026) a melee one at 300 runs single.
	check("good_2 then good_1 does not fit melee at 300", not fits("good_2", "good_1", 150))
	check("evil_1 then evil_2 fits ranged", fits("evil_1", "evil_2", 550))
	check("evil_1 then evil_2 does not fit melee", not fits("evil_1", "evil_2", 150))
	local d = H.StackJob.Partner(C.ByIdx(idxOf("good_1"), RAD))
	-- Solo runs on f215060: B was hit about 1 s after its plan, so both hits moved earlier (good_2 before its own 52-54).
	check("hits: good_2 at 51-52, good_1 in 55-56", d.fsec >= 51 and d.fsec < 52 and d.sec >= 55 and d.sec <= 56, d.fsec .. " " .. d.sec)
end

-- The pos4's offlane camps: each ancient camp and its neighbour as a pair (user 31/10/2026), and each wisdom shrine's large
-- camp single (user 01/11/2026: the shrine double dropped); one per trigger minute in turn; A's stand faces B. Fit for a
-- 550-range hero per E1 (31/10/2026): good_8 then good_7 fits, evil_8 then evil_9 does not (EC-063's weakest pair).
do
	local H, bot = world({ double = true })
	local seen, single = { [RAD] = {}, [DIRE] = {} }, { [RAD] = {}, [DIRE] = {} }
	for _, team in ipairs({ RAD, DIRE }) do
		for _, minute in ipairs({ 3, 5, 7 }) do
			local job = H.StackJob.Pos4For(team, minute)
			local d = job[2]
			if d then seen[team][MAP[d.a.campIdx][1] .. ">" .. MAP[d.b.campIdx][1]] = d else single[team][MAP[job[1].campIdx][1]] = true end
			local pf = H.StackJob.PairFor(team, minute)
			check("PairFor agrees with Pos4For", (pf and pf.b.campIdx) == (d and d.b.campIdx))
		end
	end
	check("pos4 radiant: pair good_8>good_7, single good_13", seen[RAD]["good_8>good_7"] ~= nil and single[RAD]["good_13"] and next(seen[RAD], next(seen[RAD])) == nil)
	check("pos4 dire: pair evil_8>evil_9, single evil_7", seen[DIRE]["evil_8>evil_9"] ~= nil and single[DIRE]["evil_7"] and next(seen[DIRE], next(seen[DIRE])) == nil)
	check("pos4: minutes 3 and 5 take different camps", H.StackJob.Pos4For(RAD, 3)[1].campIdx ~= H.StackJob.Pos4For(RAD, 5)[1].campIdx)
	bot.range = 550
	local function fitsPair(team, k) return H.StackJob.Fits(bot, seen[team][k]) end
	check("good_8>good_7 fits ranged", fitsPair(RAD, "good_8>good_7"))
	check("evil_8>evil_9 does not fit ranged", not fitsPair(DIRE, "evil_8>evil_9"))
	-- The walk counts from where A is hit (dsvA: earthshaker walked 430 into good_8's box from its stand): from a stand 650
	-- from A's origin towards B, a 550-range hero hits A there and fits; a melee one hits from 300 and does not.
	do
		local d = seen[RAD]["good_8>good_7"]
		local a, b = H.Lane.Camps.SpawnerByIdx(d.a.campIdx).location, H.Lane.Camps.SpawnerByIdx(d.b.campIdx).location
		local ab = dist(a, b)
		local near = { b = d.b, a = d.a, fsec = d.fsec, sec = d.sec, stand = Vector(a.x + (b.x - a.x) * 650 / ab, a.y + (b.y - a.y) * 650 / ab, 0) }
		local half = (H.Lane.Camps.SpawnerByIdx(d.b.campIdx).max.x - H.Lane.Camps.SpawnerByIdx(d.b.campIdx).min.x) / 2
		-- The speed at which a 550-range hero's walk from the stand takes the whole gap less the slack.
		bot.speed = math.max(1, ab - 650 - 550 - half) / (d.sec - d.fsec - 0.5) + 1
		bot.range = 550
		check("good_8>good_7 from a stand near B: ranged fits", H.StackJob.Fits(bot, near))
		bot.range = 150
		check("good_8>good_7 from a stand near B: melee walks from its hit in A, no fit", not H.StackJob.Fits(bot, near))
		-- The walk in to A counts (fix1A: A confirmed late by about it): a 400-range hero 900 from A's origin, on the far side
		-- from B, walks in 350 first; at the speed where only the walk from its hit point would fit, it does not.
		local far = { b = d.b, a = d.a, fsec = d.fsec, sec = d.sec, stand = Vector(a.x - (b.x - a.x) * 900 / ab, a.y - (b.y - a.y) * 900 / ab, 0) }
		bot.range = 400
		bot.speed = (ab + 550 - 400 - half) / (d.sec - d.fsec - 0.5) + 1
		check("a walk in to A counts against the gap", not H.StackJob.Fits(bot, far))
		bot.speed = (ab + 550 - 400 - half + 350) / (d.sec - d.fsec - 0.5) + 1
		check("and fits when the gap covers it too", H.StackJob.Fits(bot, far))
		bot.range = 550
		bot.speed = nil
	end
	for k, d in pairs(seen[RAD]) do
		local spa, spb = H.Lane.Camps.SpawnerByIdx(d.a.campIdx), H.Lane.Camps.SpawnerByIdx(d.b.campIdx)
		check(k .. ": A's stand faces B", dist(d.stand, spb.location) < dist(spa.location, spb.location), k)
		check(k .. ": A's hit by :54, before B's", d.fsec <= 54 and d.fsec < d.sec, k)
	end
	-- The pos4 runs no job with the double off (it stacks only its pairs).
	local H2, b2 = world({ t = 3 * 60 + 40 })
	b2.pos = 4
	check("pos4, DoubleStack off: no job", farmDesire(H2, b2) == 0 and not H2.StackJob.Applies(b2))
end

-- A full pos4 double from the Radiant offlane T1 at 5:5x: good_8 (ancient) then good_7.
do
	local H, bot = world({ t = 5 * 60 + 15, double = true, at = Vector(-6336, 1856), pos = 4 })
	local d = H.StackJob.PairFor(RAD, 5)
	check("pos4 minute 5: good_8 then good_7", MAP[d.a.campIdx][1] == "good_8" and MAP[d.b.campIdx][1] == "good_7")
	local a, b = H.Lane.Camps.SpawnerByIdx(d.a.campIdx).location, H.Lane.Camps.SpawnerByIdx(d.b.campIdx).location
	MakeNeutral({ x = a.x, y = a.y }) MakeNeutral({ x = a.x + 20, y = a.y })
	neutrals(b, 3)
	local lines = stackLines(capture(function()
		while T < 6 * 60 do frame(H, bot) end
		neutrals(b, 3) MakeNeutral({ x = a.x + 40, y = a.y })
		while T < 6 * 60 + 8 do frame(H, bot) end
	end))
	local l = lines[1]
	check("pos4 good_8>good_7: double=1, both stacked", l ~= nil and field(l, "double") == "1" and field(l, "res") == "stacked" and field(l, "fres") == "stacked", l)
	check("pos4 good_8>good_7: away at most 25 s, no death", tonumber(field(l, "away")) ~= nil and tonumber(field(l, "away")) <= 25 and field(l, "death") == "0", l)
	local fag, ag = tonumber(field(l, "faggro")), tonumber(field(l, "aggro"))
	check("pos4 good_8>good_7: A hit near its second, B near its own (1 s for the confirm)", fag ~= nil and ag ~= nil and math.abs(fag - d.fsec) <= 1 and ag >= d.sec - 0.5 and ag <= d.sec + 1, l)
	-- Each confirmed hit carries its camp's Valve window and the offset from it (user 02/11/2026).
	check("pos4 good_8>good_7: win and fwin, woff and fwoff numbers", field(l, "win") ~= "?" and field(l, "fwin") ~= "?" and tonumber(field(l, "woff")) ~= nil and tonumber(field(l, "fwoff")) ~= nil, l)
end

-- Reach (E1, 31/10/2026): from the Radiant offlane T1 the shrine's large camp good_13 (minute 3, single since 01/11/2026)
-- plans over 25 s away, which skipped the minute as far until the away limit went (user 02/11/2026): now the job runs.
do
	local H, bot = world({ t = 3 * 60 + 15, double = true, at = Vector(-6336, 1856), pos = 4 })
	local lines = stackLines(capture(function() while T < 3 * 60 + 58 do frame(H, bot) end end))
	check("pos4 shrine camp from the T1: no far skip", #lines >= 1 and field(lines[1], "why") ~= "far", lines[1])
end
-- Overrides.StackFar (scenario games only): the same minute starts good_13's single instead.
do
	local H, bot = world({ t = 3 * 60 + 15, double = true, at = Vector(-6336, 1856), pos = 4 })
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	Customize.Overrides = Customize.Overrides or {}
	Customize.Overrides.StackFar = true
	local started = false
	local lines = stackLines(capture(function() while T < 4 * 60 + 8 do frame(H, bot) if H.Chooser.HoldsRun(bot) then started = true end end end))
	Customize.Overrides.StackFar = false
	check("StackFar: good_13's single starts from the T1", started)
	check("StackFar: the line is good_13, no double", lines[1] ~= nil and tonumber(field(lines[1], "camp")) == idxOf("good_13") and field(lines[1], "double") == nil, lines[1])
end


do
	local lines, H = stackRun({ double = true })
	local l = lines[1]
	check("double: one line for the minute", #lines == 1, #lines)
	check("double: double=1, camp A good_2", field(l, "double") == "1" and tonumber(field(l, "fcamp")) == idxOf("good_2"), l)
	check("double: both camps stacked", field(l, "res") == "stacked" and field(l, "fres") == "stacked", l)
	local fag, ag = tonumber(field(l, "faggro")), tonumber(field(l, "aggro"))
	check("double: A hit before B", fag ~= nil and ag ~= nil and fag < ag, l)
	local pd = H.StackJob.Partner(H.Lane.Camps.ByIdx(idxOf("good_1"), RAD))
	check("double: A hit within 1 s of its second, B within -1 to +1.5 s of its own (the confirm)", math.abs(fag - pd.fsec) <= 1 and ag >= pd.sec - 1 and ag <= pd.sec + 1.5, l)
	check("double: A before 2, B before 3", field(l, "fbefore") == "2" and field(l, "before") == "3", l)
	-- trk/ftrk (user replay review of shsolo4b): each pulled neutral's furthest distance and the second it gave up.
	local trk, ftrk = field(l, "trk"), field(l, "ftrk")
	check("double: trk and ftrk list name:max:drop", trk ~= nil and trk:match("^[%w_]+:%d+:[%w%.%-]+") ~= nil and ftrk ~= nil and ftrk:match("^[%w_]+:%d+:[%w%.%-]+") ~= nil, tostring(trk) .. " | " .. tostring(ftrk))
	check("double: A arrived before its hit", tonumber(field(l, "farr")) ~= nil and tonumber(field(l, "farr")) <= fag, l)
	check("double: away at most 25 s", tonumber(field(l, "away")) ~= nil and tonumber(field(l, "away")) <= 25, l)
	check("double: A sampled at :59.5", tonumber(field(l, "fbox59")) ~= nil, l)
	-- ds2: A's spawn read 0 with no record of its neutrals; now A's neutrals at +2 s and :59.5, and A's box seen in the watch.
	local _, a2 = (field(l, "fn2") or ""):gsub("kobold:%d+:", "")
	local _, a59 = (field(l, "fn59") or ""):gsub("kobold:%d+:", "")
	check("double: fn2 and fn59 list A's two neutrals, fseen=1", a2 == 2 and a59 == 2 and field(l, "fseen") == "1", l)
end

-- Stacks already in the box block each other (EC-066): a double hits a camp PileEarlier (0.5) s earlier per stack past the
-- first, PileSize (4) visible neutrals each; sdsolo5a/5c B stacked 1 of 12 with 7 or more neutrals in it. Singles unchanged.
do
	local base = stackRun({ double = true })[1]
	local piled = stackRun({ double = true, bN = 9 })[1]
	local ag0, ag1 = tonumber(field(base, "aggro")), tonumber(field(piled, "aggro"))
	check("pile: early=0 with 3 in B, early=1 with 9", field(base, "early") == "0" and field(piled, "early") == "1", piled)
	check("pile: A (2 neutrals) not pulled forward", field(piled, "fearly") == "0", piled)
	check("pile: B hit about 1 s earlier", ag0 ~= nil and ag1 ~= nil and ag0 - ag1 >= 0.6 and ag0 - ag1 <= 1.4, ag0 .. " " .. tostring(ag1))
	local single0, single1 = stackRun()[1], stackRun({ bN = 9 })[1]
	check("pile: a single stack's hit is unchanged", field(single1, "early") == nil and math.abs(tonumber(field(single0, "aggro")) - tonumber(field(single1, "aggro"))) < 0.2, single1)
end

-- dsolo4b-5c (31/10/2026): A was read only after B stacked, so a B that did not stack left A unread and logged as
-- not_stacked. Now B is read for BReadFor, then the watch walks to A and reads it.
-- Under AwayMax that walk does not fit (A is ~1,100 from B's stand), so this runs with Overrides.StackFar as the solo games do.
do
	local lines = stackRun({ double = true, noBSpawn = true, tail = 15, onFrame = function()
		local C = package.loaded["bots/FunLib/custom_loader"]
		C.Overrides = C.Overrides or {}
		C.Overrides.StackFar = true
	end })
	package.loaded["bots/FunLib/custom_loader"].Overrides.StackFar = false
	local l = lines[1]
	check("B not stacked: the watch still reads A (StackFar)", field(l, "res") == "not_stacked" and field(l, "fres") == "stacked" and tonumber(field(l, "fchk")) ~= nil, l)
end
-- A's box never in sight after :00: fres=unseen, not not_stacked.
do
	-- tail: with no away limit (02/11/2026) the watch is not cut short and walks on to A, so its line comes later.
	local lines = stackRun({ double = true, tail = 15, fogged = function(v)
		local g2 = SPAWNERS[idxOf("good_2")].location
		return T >= 4 * 60 and math.abs(v.x - g2.x) < 1 and math.abs(v.y - g2.y) < 1
	end })
	local l = lines[1]
	check("A unread after :00: fres=unseen, fchk=?", field(l, "res") == "stacked" and field(l, "fres") == "unseen" and field(l, "fchk") == "?", l)
end

-- User replay review of dsolo4b (31/10/2026): the pos4 tanked camp A from its arrival, 3 s before the hit. A double's wait
-- keeps WaitClear (850) from A's visible neutrals, then walks in on the lead; the hit still lands in A's window.
do
	local minD = math.huge
	local lines = stackRun({ double = true, onFrame = function(H, bot)
		if T >= 3 * 60 + 40 and T < 3 * 60 + 51 then
			local a = SPAWNERS[idxOf("good_2")].location
			for _, n in ipairs(NEUTRALS) do
				if dist(n.loc, a) < 300 then minD = math.min(minD, dist(bot.loc, n.loc)) end
			end
		end
	end })
	local l = lines[1]
	check("wait clear: at least ~825 from A's neutrals until :51", minD >= 820, minD)
	check("wait clear: both stacked, A hit in 50.5-52.5, fauto=?", field(l, "fres") == "stacked" and field(l, "res") == "stacked" and tonumber(field(l, "faggro")) >= 50.5 and tonumber(field(l, "faggro")) <= 52.5 and field(l, "fauto") == "?", l)
	check("wait clear: fhit0 and fhpa logged", tonumber(field(l, "fhit0")) ~= nil and tonumber(field(l, "fhpa")) ~= nil, l)
end

-- Nearer good_2 than good_1 (ds1: 8 of 10 Radiant starts): still the pair, logged on good_1 with good_2 as camp A.
do
	local lines = stackRun({ double = true, at = Vector(4700, -3000) })
	local l = lines[1]
	check("near good_2: double on good_1 after good_2, both stacked", field(l, "double") == "1" and tonumber(field(l, "camp")) == idxOf("good_1") and tonumber(field(l, "fcamp")) == idxOf("good_2") and field(l, "res") == "stacked" and field(l, "fres") == "stacked", l)
end
-- And single with the double off: slice 4 stacks the nearest camp, good_2.
do
	local H, bot = world({ t = 3 * 60 + 15, at = Vector(4700, -3000) })
	local data = H.StackJob.Nearest(RAD, bot.loc)
	check("near good_2, double off: nearest good_2", MAP[data.campIdx][1] == "good_2", MAP[data.campIdx][1])
end

-- B's hit skips A's neutrals: they chase the bot into B's box margin and target it, which must not count as B's hit.
do
	local moved = false
	-- After A's hit (~:52.5) its two neutrals arrive in B's margin, nearer the bot than B's own, and target it.
	local lines = stackRun({ double = true, onFrame = function(H, bot)
		if moved or T < 3 * 60 + 54 then return end
		moved = true
		local c = SPAWNERS[idxOf("good_1")].location
		for _, m in ipairs(NEUTRALS) do
			if dist(m.loc, SPAWNERS[idxOf("good_2")].location) < 100 then
				m.loc = Vector(c.x + 280, c.y)
				m.target = bot
			end
		end
	end })
	local l = lines[1]
	check("chasers in B's margin: B still hit (before 3, a good_1 neutral)", moved and field(l, "before") == "3" and field(l, "res") == "stacked", l)
end

-- A walk from A to B that does not fit the gap (melee on evil_1 then evil_2, above; forced here with the slack): the
-- minute runs single on good_1 with double=0 dwhy=walk.
do
	local slack = nil
	local lines = stackRun({ double = true, onFrame = function(H)
		if slack == nil then slack = H.StackJob.SETTINGS.DoubleSlack H.StackJob.SETTINGS.DoubleSlack = 10 end
	end })
	local H = world()
	H.StackJob.SETTINGS.DoubleSlack = slack
	local l = lines[1]
	check("no fit: single on good_1 stacked, double=0 dwhy=walk", field(l, "res") == "stacked" and tonumber(field(l, "camp")) == idxOf("good_1") and field(l, "double") == "0" and field(l, "dwhy") == "walk" and field(l, "fcamp") == nil, l)
end

-- Switch off: no double fields at all (slice 4's line).
do
	local lines = stackRun({})
	check("DoubleStack off: no double field", field(lines[1], "double") == nil, lines[1])
end

-- Overrides.Sweep (KR S.2a tier 1, 01/11/2026): the pos5 takes each own-side camp once, nearest untried first, so every
-- attempt is on a fresh camp; ancients are in the sweep.
do
	local H, bot = world({ t = 2 * 60 + 15 })
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	Customize.Overrides = Customize.Overrides or {}
	Customize.Overrides.Sweep, Customize.Overrides.StackEvery, Customize.Overrides.StackFar = true, true, true
	for _, s in ipairs(SPAWNERS) do if s.team == RAD then neutrals(s.location, 2) end end
	local lines = stackLines(capture(function() while T < 6 * 60 + 8 do frame(H, bot) end end))
	Customize.Overrides.Sweep, Customize.Overrides.StackEvery, Customize.Overrides.StackFar = false, false, false
	local seen, started, dup = {}, 0, false
	for _, l in ipairs(lines) do
		if field(l, "res") ~= "skip" then
			local c = field(l, "camp")
			if seen[c] then dup = true end
			seen[c], started = true, started + 1
		end
	end
	check("sweep: a job most minutes from 2:00 to 5:00", started >= 3, started)
	check("sweep: no camp twice", not dup, table.concat(lines, " | "))
	-- Overrides.SweepCamps: only the listed camp numbers.
	local H2, b2 = world({ t = 2 * 60 + 15 })
	local only = idxOf("good_5") .. "," .. idxOf("good_9")
	Customize = package.loaded["bots/FunLib/custom_loader"]
	Customize.Overrides = Customize.Overrides or {}
	Customize.Overrides.Sweep, Customize.Overrides.StackEvery, Customize.Overrides.StackFar, Customize.Overrides.SweepCamps = true, true, true, only
	local l2 = stackLines(capture(function() while T < 6 * 60 + 8 do frame(H2, b2) end end))
	Customize.Overrides.Sweep, Customize.Overrides.StackEvery, Customize.Overrides.StackFar, Customize.Overrides.SweepCamps = false, false, false, nil
	local okCamps, started2 = true, 0
	for _, l in ipairs(l2) do
		if field(l, "res") ~= "skip" then
			started2 = started2 + 1
			local c = tonumber(field(l, "camp"))
			if c ~= idxOf("good_5") and c ~= idxOf("good_9") then okCamps = false end
		end
	end
	check("SweepCamps: only the listed camps, each once", okCamps and started2 >= 1 and started2 <= 2, table.concat(l2, " | "))
	-- A far camp (sweepfara/c: skipped late every minute): the bot walks to its stand and stacks it a minute later.
	local H3, b3 = world({ t = 2 * 60 + 15, at = Vector(6000, 6000) })
	Customize = package.loaded["bots/FunLib/custom_loader"]
	Customize.Overrides = Customize.Overrides or {}
	Customize.Overrides.Sweep, Customize.Overrides.StackEvery, Customize.Overrides.StackFar, Customize.Overrides.SweepCamps = true, true, true, tostring(idxOf("good_5")) .. ","
	local l3 = stackLines(capture(function() while T < 4 * 60 + 8 do frame(H3, b3) end end))
	Customize.Overrides.Sweep, Customize.Overrides.StackEvery, Customize.Overrides.StackFar, Customize.Overrides.SweepCamps = false, false, false, nil
	local late = false
	for _, l in ipairs(l3) do if field(l, "why") == "late" then late = true end end
	check("sweep: a far camp is walked to, not skipped late", not late and #l3 >= 1 and tonumber(field(l3[1], "camp")) == idxOf("good_5"), table.concat(l3, " | "))
end

-- Sweep (01/11/2026): good_15's single stack hits 1 s before Valve's window middle, good_13's 0.5 s (dsvA); others unchanged.
do
	local H = world()
	local C, S = H.Lane.Camps, H.Lane.Stacking
	for _, c in ipairs({ { "good_15", RAD, 1 }, { "good_13", RAD, 0.5 }, { "evil_7", DIRE, 0 }, { "evil_4", DIRE, 0 }, { "evil_5", DIRE, 0 }, { "good_9", RAD, 0 }, { "good_1", RAD, 0 }, { "evil_6", DIRE, 0 } }) do
		local d = C.ByIdx(idxOf(c[1]), c[2])
		check(c[1] .. ": single hit " .. c[3] .. " s before the window middle", math.abs(S.AggroSec(d) - H.StackJob.SingleSec(d) - c[3]) < 1e-6, H.StackJob.SingleSec(d))
	end
end

-- Overrides.VisionProbe (KR S.2a tier 1, 01/11/2026): from 1:00 the pos5 visits each own-side camp, nearest first, and logs
-- at its stand point and 8 points round the box whether the camp's neutrals are in sight; nothing is hit.
do
	local H, bot = world({ t = 59 })
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	Customize.Overrides = Customize.Overrides or {}
	Customize.Overrides.VisionProbe = true
	local oldVis, oldTod = IsLocationVisible, GetTimeOfDay
	IsLocationVisible, GetTimeOfDay = function() return true end, function() return 0.5 end
	local g1 = SPAWNERS[idxOf("good_1")].location
	neutrals(g1, 3)
	local lines = {}
	for _, l in ipairs(capture(function() while T < 120 do frame(H, bot) end end)) do
		if l:find("ev=visprobe ", 1, true) then table.insert(lines, l) end
	end
	Customize.Overrides.VisionProbe = false
	IsLocationVisible, GetTimeOfDay = oldVis, oldTod
	check("visprobe: nothing before 1:00, then a line per point", #lines >= 9, #lines)
	local camp, ks, attacked = lines[1] and field(lines[1], "camp"), {}, false
	for i = 1, 9 do if lines[i] and field(lines[i], "camp") == camp then ks[tonumber(field(lines[i], "k"))] = true end end
	for k = -1, 7 do check("visprobe: first camp has point k=" .. k, ks[k] == true) end
	for _, a in ipairs(ACTIONS) do if a.pid == bot.pid and a.kind == "AttackUnit" then attacked = true end end
	check("visprobe: no hit", not attacked)
	check("visprobe: the first camp is the nearest (good_1 from the safe T1)", tonumber(camp) == idxOf("good_1"), camp)
	local seen = 0
	for i = 1, 9 do seen = seen + tonumber(field(lines[i], "seen") or 0) end
	check("visprobe: good_1's neutrals counted in sight", seen > 0, seen)
end

-- Vision probe (visprobe1, 01/11/2026): five camps stand on a side that sees their neutrals, and walk off that way.
do
	local H = world()
	local C = H.Lane.Camps
	for _, c in ipairs({ { "good_5", RAD, 0, -1 }, { "good_9", RAD, 1, 0 }, { "evil_11", DIRE, 0.71, 0.71 }, { "evil_4", DIRE, -1, 0 }, { "evil_5", DIRE, 0.71, 0.71 }, { "evil_7", DIRE, 0.71, 0.71 } }) do
		local sp = C.SpawnerByIdx(idxOf(c[1]))
		local stand = H.StackJob.Stand(sp, C.ByIdx(idxOf(c[1]), c[2]))
		local dx, dy = stand.x - sp.location.x, stand.y - sp.location.y
		local len = math.sqrt(dx * dx + dy * dy)
		check(c[1] .. ": stand on the seeing side", (dx * c[3] + dy * c[4]) / len > 0.9, stand.x .. "," .. stand.y)
	end
end

-- Slice job-chooser, switch on: the chooser hosts the job, retreat comes first, and a hero hit alone no longer ends it.
do
	local function running()
		local H, bot = world({ t = 3 * 60 + 15 })
		neutrals(SPAWNERS[idxOf("good_1")].location, 3)
		capture(function() while T < 3 * 60 + 50 do frame(H, bot) end end)
		check("chooser: the job runs", H.StackJob.Running(bot))
		return H, bot
	end

	local H, bot = running()
	local lines = stackLines(capture(function() bot.heroHitAt = T frame(H, bot) end))
	check("hero hit mid-job, on: no line, the job runs on", #lines == 0 and H.StackJob.Running(bot), lines[1])

	H, bot = world({ t = 3 * 60 + 15 })
	bot.heroHitAt = 1e9
	lines = stackLines(capture(function() while T < 3 * 60 + 58 do frame(H, bot) end end))
	check("hero hit before the start, on: one skip why=hit", #lines == 1 and field(lines[1], "res") == "skip" and field(lines[1], "why") == "hit", lines[1])

	-- Retreat first: at 0.976 (the lowest banked ending) retreat's own desire beats the job's through Valve's arbitration.
	H, bot = running()
	local retreat = H.Chooser.Gate(bot, "retreat", function() return 0.976 end)()
	check("retreat passes the gate and beats the job", retreat == 0.976 and retreat > H.Chooser.SETTINGS.JobDesire, retreat)

	H, bot = running()
	bot.heroHitAt = T
	bot.hp = 49
	local d
	lines = stackLines(capture(function() d = H.Chooser.Decide(bot, "farm") end))
	check("hero hit at 49% HP: farm's next Decide is undefined", d == nil, d)
	check("hero hit at 49% HP: failed, cancelled:retreat", field(lines[1], "res") == "failed" and field(lines[1], "why") == "cancelled:retreat", lines[1])

	H, bot = running()
	bot.heroHitAt = T
	bot.hp = 50
	lines = stackLines(capture(function() frame(H, bot) end))
	check("hero hit at 50% HP: the job runs on", #lines == 0 and H.StackJob.Running(bot), lines[1])

	H, bot = running()
	bot.hp = 10
	lines = stackLines(capture(function() frame(H, bot) end))
	check("neutrals alone at 10% HP: the job runs on", #lines == 0 and H.StackJob.Running(bot), lines[1])

	-- OHA's farm is not entered during a job, so neither its defend-ping nor its run abort can fire.
	H, bot = running()
	local entered = false
	local v = farmDesire(H, bot, function() entered = true return 0.5 end)
	check("host desire during a job: JobDesire, OHA's farm not entered", v == 0.92 and not entered, v)

	H, bot = running()
	local innerThink = false
	T = T + 0.1
	farmThink(H, bot, function() innerThink = true end)
	check("host Think during a job: the job steps, OHA's farm does not", not innerThink)
	innerThink = false
	local stepped = false
	local step = H.StackJob.Step
	H.StackJob.Step = function(...) stepped = true return step(...) end
	farmThink(H, bot, function() innerThink = true end, function() return true end)
	check("host Think, bot cannot act: neither runs", not innerThink and not stepped)
	H.StackJob.Step = step
	H, bot = world({ t = 100 })
	innerThink = false
	farmThink(H, bot, function() innerThink = true end)
	check("host Think, no job: OHA's farm runs", innerThink)

	-- The start checks still refuse, with OHA's farm in its run state or not: the wrapper comes first but danger does not start a job.
	local function refused(setup, why)
		local H1, b1 = world({ t = 3 * 60 + 15 })
		setup(b1)
		local ls = stackLines(capture(function()
			while T < 3 * 60 + 58 do
				farmDesire(H1, b1, function() return 1.1 end)
				T = T + 0.1
			end
		end))
		check("start refused on: " .. why, #ls == 1 and field(ls[1], "res") == "skip" and field(ls[1], "why") == why and not H1.StackJob.Running(b1), ls[1])
	end
	refused(function(b) b.hp = 40 end, "low-hp")
	refused(function(b) MakeUnit({ pid = 10, team = 3, loc = Vector(b.loc.x + 300, b.loc.y) }) end, "enemy-near")
	refused(function(b) b.mode = dota.BotMode.Attack end, "busy")

	-- A benched hero (Overrides.Solo) stays with farm's own file: no job, its Think runs.
	H, bot = world({ t = 3 * 60 + 40 })
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	Customize.Overrides = { Solo = 0 }
	neutrals(SPAWNERS[idxOf("good_1")].location, 3)
	local benchDesire = farmDesire(H, bot, function() return 1.2 end)
	innerThink = false
	farmThink(H, bot, function() innerThink = true end)
	check("benched: desire and Think stay with farm's file, no job", benchDesire == 1.2 and innerThink and not H.StackJob.Running(bot))
	Customize.Overrides = nil

	-- ev=job: one start and one end per attempt in both arms, with the stack line's why.
	local function jobLines(ls) local r = {} for _, l in ipairs(ls) do if l:find("ev=job ", 1, true) then table.insert(r, l) end end return r end
	for _, on in ipairs({ true, false }) do
		local arm = on and "on" or "off"
		local H1, b1 = world({ t = 3 * 60 + 15, ours = { StackExecute = true, JobChooser = on } })
		neutrals(SPAWNERS[idxOf("good_1")].location, 3)
		local ls = capture(function()
			while T < 3 * 60 + 50 do frame(H1, b1) end
			b1.heroHitAt = T
			frame(H1, b1)
			b1.heroHitAt = T
			b1.hp = 40
			frame(H1, b1)
		end)
		local js, st = jobLines(ls), stackLines(ls)
		check("ev=job " .. arm .. ": one start, one end", #js == 2 and field(js[1], "phase") == "start" and field(js[2], "phase") == "end", #js)
		check("ev=job " .. arm .. ": fields", field(js[1], "job") == "stack" and field(js[1], "pid") == "5" and tonumber(field(js[1], "host")) == FARM, js[1])
		check("ev=job " .. arm .. ": why as on the stack line", field(js[2], "why") == field(st[1], "why") and field(js[2], "why") == (on and "cancelled:retreat" or "cancelled:hit"), js[2])
		check("ev=job " .. arm .. ": hit=1 after a hero hit", field(js[2], "hit") == "1", js[2])
	end
	local H1, b1 = world({ t = 3 * 60 + 15 })
	neutrals(SPAWNERS[idxOf("good_1")].location, 3)
	local ls = capture(function()
		while T < 3 * 60 + 50 do frame(H1, b1) end
		H1.StackJob.End(b1, "test")
	end)
	check("ev=job: hit=0 with no hero hit", field(jobLines(ls)[2], "hit") == "0", jobLines(ls)[2])

	-- A run state from before a job ends by its clock and on OnEnd, so skipping OHA's farm during the job leaves it no longer.
	local farmSrc = io.open(BOTS_ROOT .. "/bots/mode_farm_generic.lua", "r"):read("a")
	local helper = farmSrc:match("function GetDesireHelper%(%)(.-)\nend\n")
	local clock = helper and helper:find("DotaTime() < runTime + shouldRunTime", 1, true)
	local clear = helper and helper:find("runMode = false", 1, true)
	check("farm after a job: runMode ends by its clock on the next desire", clock ~= nil and clear ~= nil and clock < clear)
	local onEnd = farmSrc:match("function OnEnd%(%)(.-)\nend\n")
	check("farm after a job: OnEnd clears runMode", onEnd ~= nil and onEnd:find("runMode = false", 1, true) ~= nil)

	-- The farm file's line builds both wrappers.
	local farm = io.open(BOTS_ROOT .. "/bots/mode_farm_generic.lua", "r"):read("a")
	check("farm: wrapper line hosts Think", farm:find("C.HostThink(GetBot(), 'farm', Think, J.CanNotUseAction)", 1, true) ~= nil)
end

finish()
