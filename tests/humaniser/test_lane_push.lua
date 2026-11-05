dofile(HARNESS_DIR .. "/lane_world.lua")
LaneFresh({ Enable = true })
local P = require("bots/FunLib/humaniser/lane_push")
local paths = require("bots/FunLib/humaniser/lane_push_data").LANE_PATHS

-- Golden values from the offline model docs/proposals/lane-forecast/lane_sim.js (mean damage) on the same lane data, rounded
-- as lane_push_data is: the port must reproduce it, since the push reading's 65% accuracy was scored on that model.
local function near(a, b) return a ~= nil and b ~= nil and math.abs(a - b) < 0.01 end
local function at(samples, t) for _, s in ipairs(samples) do if s.t >= t then return s end end end

-- 1. Bot lane from the first spawn, no start state: both teams' waves walk, meet and settle.
do
	local smp = P.Run(paths[3], 0, 125, nil, {})
	for _, g in ipairs({ { 20, 6191.25, 12145.75 }, { 40, 9100, 9237 }, { 90, 9100, 9237 }, { 120, 9100, 9237 } }) do
		local s = at(smp, g[1])
		check("bot lane from 0: fronts at " .. g[1], near(s.front[2], g[2]) and near(s.front[3], g[3]),
			tostring(s.front[2]) .. " " .. tostring(s.front[3]))
	end
end

-- 2. Top lane from a mid-game start: a clash with a siege, a flagbearer, wounded creeps, a wave walking in and our T1 at 1200.
do
	local init = {
		{ team = 2, kind = "melee", s = 7000, hp = 400 }, { team = 2, kind = "melee", s = 7020, hp = 550 },
		{ team = 2, kind = "ranged", s = 6850, hp = 120 }, { team = 2, kind = "siege", s = 6700, hp = 935 },
		{ team = 3, kind = "melee", s = 7300, hp = 300 }, { team = 3, kind = "flag", s = 7310, hp = 500 },
		{ team = 3, kind = "ranged", s = 7480, hp = 300 }, { team = 2, kind = "melee", s = 4000, hp = 562, maxhp = 562 },
	}
	local smp = P.Run(paths[1], 250, 282, init, { [2] = 1200 })
	for _, g in ipairs({ { 250, 7036.25, 7283.75 }, { 260, 7087.5, 7228.75 }, { 270, 8933.75, 18526.75 }, { 281, 9947.5, 14951.75 } }) do
		local s = at(smp, g[1])
		check("top lane from 250: fronts at " .. g[1], near(s.front[2], g[2]) and near(s.front[3], g[3]),
			tostring(s.front[2]) .. " " .. tostring(s.front[3]))
	end
	check("clash point smoothed over +-2 s", near(P.ClashAt(smp, 250), 7158.75) and near(P.ClashAt(smp, 280), 12572.125),
		tostring(P.ClashAt(smp, 250)) .. " " .. tostring(P.ClashAt(smp, 280)))
end

-- 3. Radiant's view of mid at 2:17: one Dire creep seen at our clash; Dire's 2:00 wave is unseen and ahead of our lead, so
-- the schedule fills it at full HP (flagbearer on the minute); its 1:30 wave would be behind our lead and is left out.
do
	local own = {
		{ kind = "melee", s = 5500, hp = 600 }, { kind = "melee", s = 5480, hp = 300 }, { kind = "ranged", s = 5350, hp = 290 },
		{ kind = "melee", s = 1900, hp = 550 }, { kind = "melee", s = 1880, hp = 550 }, { kind = "flag", s = 1870, hp = 550 },
		{ kind = "ranged", s = 1730, hp = 300 },
	}
	local init = P.ViewStart(paths[2], 2, 137, own, { { kind = "melee", s = 5700, hp = 200 } })
	check("view: 7 own, 1 seen, one wave of 4 filled", #init == 12, tostring(#init))
	check("view: own HP clipped to the kind's maximum", init[1].hp == 550, tostring(init[1].hp))
	local fill = { { "melee", 6376 }, { "melee", 6376 }, { "flag", 6376 }, { "ranged", 6526 } }
	local ok = true
	for i, g in ipairs(fill) do
		local c = init[8 + i]
		ok = ok and c.team == 3 and c.kind == g[1] and near(c.s, g[2])
	end
	check("view: the 2:00 Dire wave placed where the schedule puts it", ok)

	local r = P.ReadFrom(paths[2], 2, 137, init, { [2] = 1700 })
	check("reading: clash and 30 s move as the offline model", near(r.clash, 5600) and near(r.move, 574.875),
		tostring(r.clash) .. " " .. tostring(r.move))
	check("reading: away from both T1s the model decides, OUT", r.state == "OUT" and not r.tower, r.state)
end

-- Tower rule (EC-079): a clash within 900 of our T1 bounces out, of theirs comes in, whatever the model says.
do
	local mid = paths[2]
	check("tower rule near our T1", P.TowerRule(mid, mid.towers[1].s + 800, 2) == "OUT")
	check("tower rule near their T1, Dire's side", P.TowerRule(mid, mid.towers[1].s - 500, 3) == "IN")
	check("no tower rule mid-way", P.TowerRule(mid, (mid.towers[1].s + mid.towers[2].s) / 2, 2) == nil)
	check("band 300", P.StateOf(301) == "OUT" and P.StateOf(-301) == "IN" and P.StateOf(299) == "HOLD")
end

-- Projection onto the path: a point on a vertex projects to that vertex's distance.
do
	local top = paths[1]
	local s, d = P.Project(top, top.pts[5][1], top.pts[5][2])
	check("project a path vertex", math.abs(s - top.s[5]) < 1 and d < 1, s .. " " .. d)
end

-- Slice pull-gate: the lane with a pulled wave gone. Bot lane at 65 s: our 60 s wave walking out from the spawn, theirs
-- walking in. With ours, the two meet mid-way; with it pulled, theirs walks unopposed to our T1 and meets our 90 s wave there.
do
	local bot = paths[3]
	local function wave(team, s, dir)
		return { { team = team, kind = "melee", s = s, hp = 550 }, { team = team, kind = "melee", s = s, hp = 550 },
			{ team = team, kind = "melee", s = s, hp = 550 }, { team = team, kind = "ranged", s = s - 150 * dir, hp = 300 } }
	end
	local init = wave(2, bot.spawnR + 325 * 5, 1)
	for _, c in ipairs(wave(3, bot.spawnD - 325 * 5, -1)) do table.insert(init, c) end
	local kept = P.WaveGoneFrom(bot, 2, 65, init, {}, 30, 95)
	local gone = P.WaveGoneFrom(bot, 2, 65, init, {}, 60, 95)
	check("wave gone: their wave walks in past where the waves would have met", gone.own ~= nil and kept.own ~= nil
		and gone.own < kept.own - 2000, tostring(gone.own) .. " " .. tostring(kept.own))
	check("wave gone: neither the pulled wave nor the one spawned with it counts as power", gone.ap == 0 and gone.ep == 0
		and kept.ap == 1950 and kept.ep == 1950, gone.ap .. " " .. gone.ep .. " " .. kept.ap .. " " .. kept.ep)
	check("wave gone: found (pw 1); a wave not near its scheduled spot is not found (pw 0)", gone.pw == 1 and kept.pw == 0)
	-- Decided on the spawn second itself, with the wave's creeps already in the view: still removed.
	local onSpawn = {}
	for _, c in ipairs(wave(2, bot.spawnR, 1)) do table.insert(onSpawn, c) end
	for _, c in ipairs(wave(3, bot.spawnD, -1)) do table.insert(onSpawn, c) end
	local at60 = P.WaveGoneFrom(bot, 2, 60, onSpawn, {}, 60, 90)
	check("wave gone: on the spawn second the wave in the view is removed", at60.pw == 1 and at60.ap == 0, at60.ap)

	-- Dire's side of the same lane: theirs (Radiant's) walks unopposed to Dire's T1.
	local dire = wave(3, bot.spawnD - 325 * 5, -1)
	for _, c in ipairs(wave(2, bot.spawnR + 325 * 5, 1)) do table.insert(dire, c) end
	local dKept = P.WaveGoneFrom(bot, 3, 65, dire, {}, 30, 95)
	local dGone = P.WaveGoneFrom(bot, 3, 65, dire, {}, 60, 95)
	check("wave gone, Dire: their wave walks in past the meeting point", dGone.own ~= nil and dKept.own ~= nil
		and dGone.own < dKept.own - 2000 and dGone.pw == 1 and dGone.ap == 0, tostring(dGone.own) .. " " .. tostring(dKept.own))
end

-- A wave still to spawn is pulled by leaving its spawn out of the run.
do
	local bot = paths[3]
	local at = function(smp, t) for _, s in ipairs(smp) do if s.t >= t then return s end end end
	local skipped = at(P.Run(bot, 55, 70, {}, {}, { team = 2, t = 60 }), 65)
	local plain = at(P.Run(bot, 55, 70, {}, {}), 65)
	check("skip: our 60 s wave left out, theirs spawns", skipped.front[2] == nil and skipped.front[3] ~= nil and plain.front[2] ~= nil)
end

finish()
