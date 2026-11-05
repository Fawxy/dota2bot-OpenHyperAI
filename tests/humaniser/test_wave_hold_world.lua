-- Slice core-in-lane, the wave hold's start in a stub world (review 2026-11-06-hold-start-f6c715e findings 1 and 4): tryStart's
-- gone and forecast starts, forecastIn's run, the creeps that do not end an attempt as met, and the skip line's rate limit.
-- LaneFresh resets T, so each world is made before its clock is set. Creeps stand on Radiant's bot lane path at their distance from Radiant's bot T1 (8,057 along it, positive towards Dire).
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local T1 = 8057
local function world(laneAggro)
	local H = LaneFresh({ Enable = true }, { telemetry = { Enable = true }, laneAggro = laneAggro })
	-- Our T1's API values as in game: range 700, tower hull 144; lane creeps' hull 16 (reach 860, floor 910).
	for _, t in pairs(TOWERS_W[2]) do t.range, t.hull = 700, 144 end
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	local W = require("bots/FunLib/humaniser/states/wave_hold")
	local P = require("bots/FunLib/humaniser/lane_push")
	local path = require("bots/FunLib/humaniser/lane_push_data").LANE_PATHS[Lane.Bot]
	local function at(own)
		local p = P.PointAt(path, T1 + own)
		return p[1], p[2]
	end
	local bot = MakeUnit({ pid = 1, team = 2, mode = BotMode.Laning, hp = 1000 })
	bot.maxhp, bot.pos, bot.lane = 1000, 1, Lane.Bot
	local bx, by = at(850)
	bot.loc = Vector(bx, by)
	local function creep(team, own, o)
		local x, y = at(own)
		o = o or {}
		local name = team == 2 and "npc_dota_creep_goodguys_" or "npc_dota_creep_badguys_"
		return MakeCreep({ team = team, x = x, y = y, hp = o.hp, name = name .. (o.kind or "melee") })
	end
	local function count(ev, pattern)
		local n = 0
		for _, l in ipairs(lines) do
			if l:find("ev=" .. ev .. " ", 1, true) and (pattern == nil or l:find(pattern, 1, true)) then n = n + 1 end
		end
		return n
	end
	return { W = W, bot = bot, creep = creep, count = count, lines = lines, H = H, at = at }
end

-- obs0611 mark 4's shape, the gone start: our pull returnee fighting at 666 under our T1, theirs at 950-990 (outside tower
-- fire). The hold starts, and the returnee's fight (within 700 of their front) does not end it as met; our next wave does.
do
	local w = world()
	T = 110
	local back = w.creep(2, 666)
	local e1 = w.creep(3, 950)
	w.creep(3, 970)
	w.creep(3, 990)
	back.target = e1
	e1.target = back
	w.W.Step(w.bot)
	T = 110.5
	w.W.Step(w.bot)
	check("gone start: the returnee fighting under our T1 neither keeps the hold off nor ends it as met", w.count("wave_hold") == 0, table.concat(w.lines, "\n"))
	T = 112
	w.W.Step(w.bot)
	check("gone start: a hold runs (left only after LeftAfter unstepped)", w.count("wave_hold") == 0)
	w.creep(2, 300)
	T = 112.5
	w.W.Step(w.bot)
	check("gone start: our next wave reaching their front ends it as met", w.count("wave_hold", "res=met") == 1 and w.count("wave_hold", "trig=gone") == 1, table.concat(w.lines, "\n"))
end

-- The same lane with our fresh wave walking out under our T1 (no attack target): our wave, no start, and no skip line while
-- their wave is past the lane target.
do
	local w = world()
	T = 27
	for _, o in ipairs({ -205, -8, 115, 215 }) do w.creep(2, o) end
	w.creep(3, 2190)
	w.creep(3, 2290)
	w.W.Step(w.bot)
	T = 27.5
	w.W.Step(w.bot)
	-- A hold started here would end as met once the waves meet; none started, so no line.
	w.creep(2, 1800)
	T = 28
	w.W.Step(w.bot)
	check("fresh wave walking out: no hold starts", w.count("wave_hold") == 0 and #w.lines == 0, table.concat(w.lines, "\n"))
end

-- obs0611 mark 5's shape (moved out of tower fire), the forecast start: 2 weak creeps of ours fighting 4 of theirs at 950-1,060. lane_push's run has their
-- front under our T1 within 8 s, so the hold starts while ours still fights; our next wave already on the map 3,000 behind our
-- T1 is not in the clash, so it ends the attempt as met when it arrives.
do
	local w = world()
	T = 150
	local m = w.creep(2, 950, { hp = 200 })
	local r = w.creep(2, 940, { hp = 150, kind = "ranged" })
	local nextWave = w.creep(2, -3000)
	local es = {}
	for i, o in ipairs({ 1000, 1020, 1040, 1060 }) do es[i] = w.creep(3, o) end
	m.target, r.target = es[1], es[1]
	es[1].target, es[2].target = m, m
	w.W.Step(w.bot)
	T = 150.5
	w.W.Step(w.bot)
	check("forecast start: no line while the losing wave fights on (its fight is not met)", w.count("wave_hold") == 0, table.concat(w.lines, "\n"))
	local x, y = nextWave.loc.x, nextWave.loc.y
	local fx, fy = es[1].loc.x, es[1].loc.y
	nextWave.loc = Vector(fx + (x - fx) * 0.05, fy + (y - fy) * 0.05)
	T = 151
	w.W.Step(w.bot)
	check("forecast start: our next wave reaching their front ends it as met", w.count("wave_hold", "res=met") == 1 and w.count("wave_hold", "trig=forecast") == 1 and w.count("wave_hold", "why=losing") == 1, table.concat(w.lines, "\n"))
end

-- A full wave of ours fighting 2 weak creeps of theirs at 900 (inside the 910 floor): no start, and one skip line `ours` for
-- every SkipEvery (5 s) however often the core reads it.
do
	local w = world()
	T = 150
	local ours = {}
	for i, o in ipairs({ 860, 870, 880 }) do ours[i] = w.creep(2, o) end
	local e1, e2 = w.creep(3, 900, { hp = 120 }), w.creep(3, 920, { hp = 120 })
	for _, c in ipairs(ours) do c.target = e1 end
	e1.target, e2.target = ours[1], ours[1]
	for i = 0, 16 do
		T = 150 + i * 0.5
		w.W.Step(w.bot)
	end
	check("winning clash: no hold", w.count("wave_hold") == 0)
	check("skip `ours` at most once per 5 s over 8 s of reads: 2 lines", w.count("wave_hold_skip", "why=ours") == 2, w.count("wave_hold_skip", "why=ours"))
end

-- hschk2 8:18 top (user, 06/11/2026: "pudge is holding their creeps under tower fire"): their creeps at 792-830 from our T1 with
-- ours gone are inside its fire (reach 860): no hold, a `late` skip line with the reach. With a smaller tower hull from the API
-- (100: reach 816, floor 866) a front at 880 starts, held at 880.
do
	local w = world()
	T = 498
	w.creep(3, 792)
	w.creep(3, 830)
	w.creep(3, 1188)
	w.W.Step(w.bot)
	check("hschk2: their front under tower fire: no hold, skip late with rch=860", w.count("wave_hold") == 0 and w.count("wave_hold_skip", "why=late") == 1 and w.count("wave_hold_skip", "rch=860") == 1, table.concat(w.lines, "\n"))
	local w2 = world()
	for _, t in pairs(TOWERS_W[2]) do t.hull = 100 end
	T = 498
	w2.creep(3, 880)
	w2.creep(3, 900)
	w2.W.Step(w2.bot)
	T = 498.5
	w2.creep(2, 700)
	w2.W.Step(w2.bot)
	check("the API's tower hull sets the floor: front 880 starts and holds at 880", w2.count("wave_hold", "rch=816") == 1 and w2.count("wave_hold", "hd=879") + w2.count("wave_hold", "hd=880") == 1, table.concat(w2.lines, "\n"))
end

-- The hold takes their wave's aggro (decided 06/11/2026, hschk3: holds ended `tower` with the core at its point and their
-- creeps walking past it): our wave gone, theirs walking in 1,150-1,190 out, an enemy hero in sight; the core stands at the
-- hold point (910). Their front is under 1 s from it, so lane_aggro's draw starts.
do
	local w = world(true)
	T = 200
	local x, y = w.at(910)
	w.bot.loc = Vector(x, y)
	w.creep(3, 1150)
	w.creep(3, 1170)
	w.creep(3, 1190)
	local hx, hy = w.at(1500)
	MakeUnit({ pid = 7, team = 3, loc = Vector(hx, hy) }).lane = Lane.Bot
	w.W.Step(w.bot)
	local A = require("bots/FunLib/humaniser/lane_aggro")
	check("hold draw: lane_aggro's draw runs for the holding core", A.Acting(w.bot), table.concat(w.lines, "\n"))
end

-- An enemy hero pushing the held spot inside the floor ends the attempt `unsafe` once their front is within 1 s of the floor
-- (lane_spot's last reading, here set by hand).
do
	local w = world()
	T = 300
	local c1, c2 = w.creep(3, 1500), w.creep(3, 1520)
	w.W.Step(w.bot)
	local L = require("bots/FunLib/humaniser/states/laning")
	local x, y = w.at(600)
	L.SpotInfo = function() return { spot = Vector(x, y), pushed = 6, anchor = "hold", why = "hero", margin = 0, covered = 0 } end
	T = 300.5
	w.W.Step(w.bot)
	check("pushed by a hero to 600 with their front 1,500 out: the hold runs on", w.count("wave_hold") == 0, table.concat(w.lines, "\n"))
	local x1, y1 = w.at(1150)
	local x2, y2 = w.at(1170)
	c1.loc, c2.loc = Vector(x1, y1), Vector(x2, y2)
	T = 301
	w.W.Step(w.bot)
	check("unsafe: still pushed to 600 with their front at 1,150 (within 1 s of the floor) ends the attempt", w.count("wave_hold", "res=unsafe") == 1, table.concat(w.lines, "\n"))
end

finish()

