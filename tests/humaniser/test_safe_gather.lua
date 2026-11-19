dofile(HARNESS_DIR .. "/lane_world.lua")
-- Safe here, step 3 (design 2026-11-19-safe-here-design.md sections 2, 5): safe_gather.lua builds Decide's inputs from a read the
-- consumer made (the real Threat.Read on the lane world; only SpellReady.DamageOn is replaced, to 100 a second per `perSec`), samples
-- the HP lost per second by source, remembers a lane opponent that has gone out of sight, and logs the answer in shadow.
local HERE = Vector(-2000, -5000)
local CAMP = Vector(-1000, -6200)
local OPTS = { away = false, held = false, hold = false }

local lines
local function world()
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = true, Cut = true } })
	T = 300
	CURRENT_TEAM, OBSERVER = 2, 1
	lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	local Threat = require("bots/FunLib/humaniser/threat")
	Threat.ResetCache()
	local G = require("bots/FunLib/humaniser/safe_gather")
	G.ResetCache()
	require("bots/FunLib/humaniser/spell_ready").DamageOn = function(e, _, w) return (e.perSec or 0) * w end
	local bot = MakeUnit({ pid = 1, team = 2, loc = HERE, level = 3 })
	bot.maxhp, bot.hp = 1000, 1000
	return Threat, G, bot
end
local function enemy(pid, x, perSec)
	local e = MakeUnit({ pid = pid, team = 3, loc = Vector(x, -5000) })
	e.maxhp, e.hp, e.perSec = 600, 600, perSec
	return e
end
local function stay(Threat, bot)
	return Threat.Read(bot, HERE, HERE, 2, { engagedWindow = 6 })
end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end
local function safeLines(who)
	local r = {}
	for _, l in ipairs(lines) do
		if l:find("kind=safe", 1, true) and (who == nil or field(l, "who") == who) then r[#r + 1] = l end
	end
	return r
end
local function row(i, pid)
	for _, x in ipairs(i.reach) do if x.pid == pid then return x end end
end

-- FromRead: an engaged hero is hitting and carries the read's long-window damage, a hero that is not carries the short one.
do
	local Threat, G, bot = world()
	local hitter = enemy(10, -1700, 100)
	local idle = enemy(11, -1400, 50)
	bot.hitBy = { [hitter] = T }
	local i = G.FromRead(bot, stay(Threat, bot), OPTS)
	local a, b = row(i, 10), row(i, 11)
	check("an engaged reacher is hitting with its 6 s damage, one that is not carries its 2 s damage",
		a and b and a.hitting and a.dmg == 600 and not b.hitting and b.dmg == 100, a and a.dmg)
	check("hp from the handle, the read's unseen weight and tower, the caller's flags",
		i.hp == 1000 and i.hpMax == 1000 and i.missing == 0 and i.tower == false and i.towerOnMe == false
			and G.FromRead(bot, stay(Threat, bot), { away = true, held = true, hold = true }).hold == true)
	-- the hitter stands 300 away and its reach is 1,198 (run 600, range 550, hulls 48): 898 to walk at 300 a second; the other hero's is 598
	check("exit: the longest walk out of any reacher's range", math.abs(i.exit - 898 / 300) < 1e-6, i.exit)
	hitter.loc, idle.loc = Vector(-9000, -5000), Vector(-9000, -5000)
	check("nobody in reach: no rows and no exit", #G.FromRead(bot, stay(Threat, bot), OPTS).reach == 0 and G.FromRead(bot, stay(Threat, bot), OPTS).exit == nil)
end

-- A lane opponent that reached us and is out of sight now still counts while its run could reach the place.
do
	local function unseenRow(ago, tss, where, alive)
		local Threat, G, bot = world()
		local e = enemy(10, -1700, 100)
		G.FromRead(bot, stay(Threat, bot), OPTS)
		T = 300 + ago
		e.hiddenFrom = { [OBSERVER] = true }
		e.alive = alive ~= false
		LAST_SEEN[10] = { location = where, time_since_seen = tss }
		local i = G.FromRead(bot, stay(Threat, bot), OPTS)
		return row(i, 10), i
	end
	local r, i = unseenRow(4, 4, Vector(-1700, -5000))
	check("a hero that reached us 4 s ago and is unseen is a row with its last damage, flagged unseen, and counts in the kill line",
		r and r.unseen == true and r.dmg == 200 and r.hitting == false and require("bots/FunLib/humaniser/safe").Decide(i).kill == 200, r and r.dmg)
	check("control: one that last reached us 12 s ago is forgotten", unseenRow(12, 12, Vector(-1700, -5000)) == nil)
	check("control: one whose run since the sighting cannot reach the place is not counted", unseenRow(4, 4, Vector(-9000, -5000)) == nil)
	check("control: a dead hero is not counted", unseenRow(4, 4, Vector(-1700, -5000), false) == nil)
	local late = unseenRow(10, 10, Vector(-1700, -5000))
	check("the memory is 10 s: a hero last a reacher 10 s ago still counts", late ~= nil)
end

-- Only a read of our own position feeds the lane memory; other reads use it and never write it.
do
	local FAR = Vector(-1000, -6200)
	local function unseenAfter(first)
		local Threat, G, bot = world()
		local e = enemy(10, -1700, 100)
		-- a walk to FAR from HERE: the hero at (-1700,-5000) is within its reach as well
		first(Threat, G, bot)
		T = 304
		e.hiddenFrom = { [OBSERVER] = true }
		LAST_SEEN[10] = { location = Vector(-1700, -5000), time_since_seen = 4 }
		return row(G.FromRead(bot, stay(Threat, bot), OPTS), 10)
	end
	check("control: a hero that reached our own place and then went unseen is remembered",
		unseenAfter(function(Threat, G, bot) G.FromRead(bot, stay(Threat, bot), OPTS) end) ~= nil)
	check("a hero that reached only a far place read is not remembered",
		unseenAfter(function(Threat, G, bot) G.FromRead(bot, Threat.Read(bot, HERE, FAR, 4), OPTS) end) == nil)
	local Threat, G, bot = world()
	local e = enemy(10, -1700, 100)
	G.FromRead(bot, stay(Threat, bot), OPTS)
	e.perSec = 1
	G.FromRead(bot, Threat.Read(bot, HERE, FAR, 4), OPTS)
	T = 304
	e.hiddenFrom = { [OBSERVER] = true }
	LAST_SEEN[10] = { location = Vector(-1700, -5000), time_since_seen = 4 }
	local r = row(G.FromRead(bot, stay(Threat, bot), OPTS), 10)
	check("a far read after an own-place read does not overwrite the remembered damage (200, not the 3 s read's 3)", r and r.dmg == 200, r and r.dmg)
end

-- The landing sampler.
do
	local _, G, bot = world()
	bot.hp = 1000
	G.Sample(bot, 300)
	T = 300.5
	bot.hp, bot.heroHitAt = 900, 300.4
	G.Sample(bot, T)
	local l = G.Landing(bot, T)
	check("a drop flagged to a hero lands on the hero, per second over the 2 s window", near(l.hero, 50) and l.creeps == 0 and l.tower == 0, l.hero)
	T = 301
	bot.hp, bot.heroHitAt, bot.creepHitAt = 840, 300.9, 300.9
	G.Sample(bot, T)
	G.Sample(bot, T)
	l = G.Landing(bot, T)
	check("a drop with two flagged sources is split equally; a second sample in the same frame adds nothing", near(l.hero, 65) and near(l.creeps, 15), l.hero)
	T = 301.5
	bot.hp = 640
	G.Sample(bot, T)
	check("a drop with no flag in the window is not counted", near(G.Landing(bot, T).hero, 65))
	T = 302
	bot.hp = 690
	G.Sample(bot, T)
	check("a rise is ignored", near(G.Landing(bot, T).hero, 65))
	check("a sample 1.9 s old still counts; at 2.1 s it is forgotten, the later one stays",
		near(G.Landing(bot, 302.4).hero, 65) and near(G.Landing(bot, 302.6).hero, 15) and near(G.Landing(bot, 302.6).creeps, 15))
	T = 304
	bot.hp, bot.towerHitAt = 600, 303.9
	G.Sample(bot, T)
	check("a gap of over a second between samples gives no drop (the flags cannot say who)", G.Landing(bot, T).tower == 0)
end

-- Shadow: a line on a change of level or reason, then at most every 2 s while a hero is in reach; nothing for a quiet safe answer.
do
	local Threat, G, bot = world()
	local hitter = enemy(10, -1700, 150)
	bot.hitBy = { [hitter] = T }
	local r = stay(Threat, bot)
	G.Shadow(bot, "leave", r, OPTS)
	local first = safeLines("leave")
	check("a first deadly answer logs once, with the inputs and the answer",
		#first == 1 and field(first[1], "lv") == "deadly" and field(first[1], "why") == "kill" and field(first[1], "rr") == "10,1,900,0"
			and field(first[1], "hpa") == "1000" and field(first[1], "pl") == "-2000,-5000" and field(first[1], "awy") == "0" and field(first[1], "kill") == "900",
		first[1])
	T = 300.5
	G.Shadow(bot, "leave", r, OPTS)
	check("the same answer 0.5 s later logs nothing", #safeLines("leave") == 1)
	T = 302.6
	bot.hitBy[hitter] = T
	G.Shadow(bot, "leave", stay(Threat, bot), OPTS)
	check("the same answer over 2 s later logs again while a hero is in reach", #safeLines("leave") == 2)
	G.Shadow(bot, "spot", r, OPTS)
	check("another consumer has its own cadence", #safeLines("spot") == 1)
	hitter.perSec = 10
	T = 302.7
	bot.hitBy[hitter] = T
	G.Shadow(bot, "leave", stay(Threat, bot), OPTS)
	local now = safeLines("leave")
	check("a change of level logs at once", #now == 3 and field(now[3], "lv") == "safe" and field(now[3], "why") == "safe")
	hitter.loc = Vector(-9000, -5000)
	T = 310
	G.Shadow(bot, "leave", stay(Threat, bot), OPTS)
	T = 320
	G.Shadow(bot, "leave", stay(Threat, bot), OPTS)
	check("a safe answer with nobody in reach and no price is not repeated", #safeLines("leave") == 3)
end

-- At: the one call a consumer makes. Reader constructions and enemy-hero scans are counted through a wrapper on Threat.Reader and GetUnitList.
do
	local Threat, G, bot = world()
	local hitter = enemy(10, -1700, 150)
	bot.hitBy = { [hitter] = T }
	local made, scans = 0, 0
	local realReader, realList = Threat.Reader, GetUnitList
	Threat.Reader = function(...) made = made + 1; return realReader(...) end
	GetUnitList = function(t) if t == require("bots/ts_libs/dota/index").UnitType.EnemyHeroes then scans = scans + 1 end return realList(t) end
	local a1 = G.At(bot, HERE)
	G.At(bot, CAMP)
	G.At(bot, Vector(-1500, -5200), { from = CAMP })
	check("three places in one frame build one reader and scan the enemy heroes once", made == 1 and scans == 1, made .. "/" .. scans)
	G.At(bot, HERE, { horizon = 4 })
	check("control: another horizon in the same frame has its own reader", made == 2 and scans == 2, made)
	G.At(bot, HERE, { engaged = false })
	check("control: the engaged option is part of the key", made == 3, made)
	T = 300.1
	G.At(bot, HERE)
	check("a new frame builds a new reader", made == 4 and scans == 4, made)
	Threat.Reader, GetUnitList = realReader, realList

	T = 300.2
	bot.hitBy[hitter] = T
	local a2 = G.At(bot, HERE, { who = "probe" })
	G.Shadow(bot, "shadow", stay(Threat, bot), OPTS)
	local la, ls = safeLines("probe"), safeLines("shadow")
	check("At answers what Shadow logs for the same read, and logs the same fields",
		a2.level == "deadly" and #la == 1 and #ls == 1 and field(la[1], "lv") == field(ls[1], "lv") and field(la[1], "why") == field(ls[1], "why")
			and field(la[1], "kill") == field(ls[1], "kill") and field(la[1], "rr") == field(ls[1], "rr") and field(la[1], "lv") == a2.level
			and a1.kill == a2.kill, la[1])
	G.At(bot, HERE)
	check("control: no who, no line", #safeLines("probe") == 1 and #safeLines(nil) == 2)
end

-- At needs no telemetry: a deadly place reads deadly, a safe place safe, and nothing is logged.
do
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = false } })
	T = 300
	CURRENT_TEAM, OBSERVER = 2, 1
	lines = {}
	local Threat = require("bots/FunLib/humaniser/threat")
	Threat.ResetCache()
	local G = require("bots/FunLib/humaniser/safe_gather")
	G.ResetCache()
	require("bots/FunLib/humaniser/spell_ready").DamageOn = function(e, _, w) return (e.perSec or 0) * w end
	local bot = MakeUnit({ pid = 1, team = 2, loc = HERE, level = 3 })
	bot.maxhp, bot.hp = 1000, 1000
	local hitter = enemy(10, -1700, 150)
	bot.hitBy = { [hitter] = T }
	local deadly = G.At(bot, HERE, { who = "probe" })
	local calm = G.At(bot, Vector(-9000, -5000), { from = Vector(-9000, -5000), who = "probe" })
	check("with telemetry off a deadly place is deadly (kill) and a place nobody reaches is safe, and no line is written",
		deadly.level == "deadly" and deadly.reason == "kill" and calm.level == "safe" and #lines == 0, calm.reason)
	local ok = pcall(G.At, bot, nil)
	check("an error in the read is not swallowed", not ok)
end

-- At passes away / held / hold to Decide.
do
	local Threat, G, bot = world()
	local e = enemy(10, -1700, 420)
	local function at(o) T = T + 0.1; return G.At(bot, HERE, o) end
	check("a place deadly fresh (ratio 1.19 against 1.25) is not deadly held (1.06), and control: still deadly with neither",
		at({}).level == "deadly" and at({ held = true }).level ~= "deadly" and at({ held = false }).level == "deadly")
	check("a hold stays down to 1.0, so the same place is not deadly with hold", at({ hold = true }).level ~= "deadly")
	e.perSec = 100
	local realReader = Threat.Reader
	Threat.Reader = function(...)
		local rd = realReader(...)
		return function(from, place) local r = rd(from, place); r.missing = 0.6; return r end
	end
	check("a walk with missing 0.6 is deadly (unknown) only with away", at({ away = true }).reason == "unknown" and at({}).level == "safe")
	Threat.Reader = realReader
end

-- The landing sampler is a Tick step, independent of telemetry.
do
	local H = LaneFresh({ Enable = true }, { skill = 0.9, telemetry = { Enable = false } })
	T = 300
	local G = require("bots/FunLib/humaniser/safe_gather")
	G.ResetCache()
	local bot = MakeUnit({ pid = 1, team = 2, loc = HERE, level = 3 })
	bot.maxhp, bot.hp = 1000, 1000
	G.Tick(bot)
	T = 300.5
	bot.hp, bot.heroHitAt = 900, 300.4
	G.Tick(bot)
	G.Tick(bot)
	check("with telemetry off, a drop with the hero flag lands on the hero rate once, though the step ran twice in the tick",
		near(G.Landing(bot, T).hero, 50) and G.Landing(bot, T).creeps == 0, G.Landing(bot, T).hero)
	T = 301
	bot.hp, bot.heroHitAt = 800, nil
	G.Tick(bot)
	check("a drop with no flag adds nothing", near(G.Landing(bot, T).hero, 50))
	T = 301.5
	bot.hp, bot.alive, bot.heroHitAt = 0, false, 301.4
	G.Tick(bot)
	bot.hp, bot.alive = 1000, true
	T = 302
	G.Tick(bot)
	check("a dead hero is not sampled: its killing blow (flagged, 800 HP) is not counted", near(G.Landing(bot, T).hero, 50), G.Landing(bot, T).hero)
end

-- A fault inside Shadow never reaches the consumer, and is reported.
do
	local _, G, bot = world()
	local bad = { t = T, from = HERE, place = HERE, missing = 0, tower = false }
	check("control: the same read fails in FromRead", not pcall(G.FromRead, bot, bad, OPTS))
	local ok = pcall(G.Shadow, bot, "leave", bad, OPTS)
	local errors = 0
	for _, l in ipairs(lines) do if l:find("ev=lua_error", 1, true) and l:find("SafeGather.Shadow", 1, true) then errors = errors + 1 end end
	check("Shadow swallows it and reports one lua_error", ok and errors == 1, errors)
end

-- Threat.Gate's shadow: a trip's walk, away.
do
	local Threat, _, bot = world()
	local hitter = enemy(10, -1700, 100)
	local res = Threat.Gate(bot, HERE, CAMP, "core_camp")
	local l = safeLines("core_camp")
	check("a gate logs its read as who=<consumer> with away, and its own answer is unchanged",
		#l == 1 and field(l[1], "awy") == "1" and res.why == "threat" and field(l[1], "rr") == "10,0,300,0", l[1])
end

finish()
