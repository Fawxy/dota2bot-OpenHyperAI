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
