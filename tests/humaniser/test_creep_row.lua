dofile(HARNESS_DIR .. "/lane_world.lua")
-- The creep row (creep_row.ts, Ours.LaneCreeps, doctrine D11): their ranged creep in the claimed cells, decided at the creep
-- offer read. The engine's laneTargets, hpForecast and task runner are stubbed (ForOurs), so these cover the decision, the
-- latch and the lines; the lastHit verb is the engine's (its own tests) and its execution is the rig's.

local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end
local function lines(all, pat) local r = {} for _, l in ipairs(all) do if l:find(pat, 1, true) then table.insert(r, l) end end return r end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

local RANGED = "npc_dota_creep_badguys_ranged"

-- o.on: the switch; o.refuse: the runner refuses. w.targets: what laneTargets returns; w.starts, w.opts, w.body, w.onEnd: the
-- last Start's.
local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = 1, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Ours.LaneCreeps = o.on ~= false
	CURRENT_TEAM = 2
	T = 100
	TOWERS_W = { [2] = {}, [3] = {} }
	local w = { targets = {}, hits = {}, starts = 0, steps = 0 }
	local F = package.loaded["bots/FunLib/humaniser/tasks"].ForOurs
	F.Verbs = function()
		return {
			laneTargets = function() return w.targets end,
			hpForecast = function(bot, creep, horizon)
				return { hp = creep.hp, regen = 0, horizon = horizon, hits = w.hits[creep] or {}, unphased = 0, unphasedTower = false, unphasedHits = {} }
			end,
			forecastHp = function(f, t)
				local hp = f.hp
				for _, h in ipairs(f.hits) do if h.t <= t then hp = hp - h.damage end end
				return hp
			end,
		}
	end
	F.Jobs = function() return {} end
	F.Tick = function() end
	F.Start = function(_, opts, body)
		w.starts = w.starts + 1
		w.onEnd, w.opts, w.body = opts.onEnd, opts, body
		return o.refuse ~= true
	end
	F.Step = function() w.steps = w.steps + 1 return true end
	package.loaded["bots/FunLib/humaniser/lane_hits"].Reset()
	w.CO, w.CR = H.CreepOffer, H.CreepRow
	w.CO.ResetCache()
	w.CR.ResetCache()
	w.CO.SETTINGS.Every = 0.1
	w.core = MakeUnit({ pid = 1, team = 2, bot = true, loc = Vector(0, -5000), hp = 600, maxhp = 600 })
	w.core.pos, w.core.lane = o.pos or 2, Lane.Bot
	return w
end

local function target(creep, o)
	local walk, due = o.walk or 0, o.due or 0
	return { creep = creep, kind = o.kind or "lasthit", eta = math.max(walk, due), due = due, walk = walk, dies = o.dies or 3, ranged = true }
end
local function ranged(x) return MakeCreep({ team = 3, x = x or 300, y = -5000, hp = 80, name = RANGED }) end
local function kill(c) RemoveCreep(c) end

-- One read at T, then the creeps killed and a read that closes their lines.
local function readThenClose(w, creeps)
	return capture(function()
		w.CO.Shadow(w.core)
		T = T + 0.1
		for _, c in ipairs(creeps) do kill(c) end
		w.targets = {}
		w.CO.Shadow(w.core)
	end)
end

local function lastHitOpts(w)
	local got
	w.body({ lastHit = function(opts) got = opts end })
	return got
end

do -- a near ranged creep about to come due, stock not on it: an attempt, the latch, the end
	local w = world()
	local c = ranged()
	w.targets = { target(c, { walk = 0.3, due = 0.5, dies = 3 }) }
	local a1, a2, s1, s2, a3
	local out = capture(function()
		w.CO.Shadow(w.core)
		a1 = w.CR.ROW.applies(w.core)
		s1 = w.CR.ROW.step(w.core)
		w.onEnd({ success = true })
		s2 = w.CR.ROW.step(w.core)
		a3 = w.CR.ROW.applies(w.core)
		T = T + 0.1
		kill(c)
		w.targets = {}
		w.CO.Shadow(w.core)
	end)
	local ch, jobs = lines(out, "kind=creep"), lines(out, "job=creep")
	check("go: one task started at the read, the row holds while it runs", w.starts == 1 and a1 == true and s1 == false, tostring(a1) .. " " .. w.starts)
	local opts = lastHitOpts(w)
	check("go: lastHit on that creep, waiting laneFarm's slack past the eta", opts ~= nil and opts.target == c and near(opts.maxWait, 2.0), tostring(opts and opts.maxWait))
	check("go: after the end the step finishes and the row lets go", s2 == true and a3 == false, tostring(s2) .. " " .. tostring(a3))
	check("go: the creep's line reads go=1 src=own with the read's walk", #ch == 1 and field(ch[1], "go") == "1" and field(ch[1], "src") == "own"
		and field(ch[1], "why") == nil and field(ch[1], "gw") == "0.300", table.concat(ch, " | "))
	check("go: a job start and an end why=ok", #jobs == 2 and field(jobs[1], "phase") == "start" and field(jobs[2], "why") == "ok", table.concat(jobs, " | "))
end

do -- the attempt's lines: the creep, the walk at go, when the hero was first in the verb's range, the swing, HP at start and end
	local function attempt(endWith, moveIn)
		local w = world()
		w.core.range = 150
		local c = ranged(300)
		w.targets = { target(c, { walk = 0.3, due = 0.5, dies = 3 }) }
		return capture(function()
			w.CO.Shadow(w.core)
			w.CR.ROW.applies(w.core)
			T = T + 0.4
			w.CR.ROW.step(w.core)
			if moveIn then
				c.loc = Vector(100, -5000)
				T = T + 0.3
				w.CR.ROW.step(w.core)
				T = T + 0.3
				w.CR.ROW.step(w.core)
			end
			w.core.hp = 540
			w.onEnd(endWith)
		end)
	end
	local jobs = lines(attempt({ success = false, reason = "denied", message = "w=1.00 hp=60 pred=0 mine=55 t=0.40 m=0.10 obs=20 idps=30 end=0 dt=0.30" }, true), "job=creep")
	check("lines: start names the creep and the walk at go", #jobs == 2 and field(jobs[1], "cid") ~= nil and field(jobs[1], "gw") == "0.300" and field(jobs[1], "gd") == "0.500", table.concat(jobs, " | "))
	check("lines: in range at the first step inside it, a swing read from the post-swing message, HP 600 to 540", field(jobs[2], "tin") == "0.700"
		and field(jobs[2], "sw") == "1" and field(jobs[2], "hp0") == "600" and field(jobs[2], "hp1") == "540" and field(jobs[2], "cid") == field(jobs[1], "cid"), jobs[2])
	jobs = lines(attempt({ success = false, reason = "taken_by_other", message = "w=1.20 why=range d=140" }, false), "job=creep")
	check("lines: never in range reads tin=-1; a pre-swing message reads sw=0 and is kept", field(jobs[2], "tin") == "-1" and field(jobs[2], "sw") == "0"
		and jobs[2]:find('msg="w=1.20 why=range d=140"', 1, true) ~= nil, jobs[2])
	jobs = lines(attempt({ success = false, reason = "preempted", message = "mode=5" }, false), "job=creep")
	check("lines: a cut leaves the swing unknown", field(jobs[2], "sw") == nil, jobs[2])
end

do -- the start line says what held the row and what the spare was: need from the verb's own range, not the offer's walk
	local function run(prep)
		local w = world()
		w.core.range = 150
		w.core.speed = 300
		local c = ranged(500)
		w.targets = { target(c, { walk = 0.3, due = 0.5, dies = 3 }) }
		local out = capture(function()
			prep(w, c)
			w.CO.Shadow(w.core)
			w.CR.ROW.applies(w.core)
		end)
		return lines(out, "job=creep")[1]
	end
	local first = run(function() end)
	-- 500 apart, range 150: 350 to walk at 300 a second.
	check("start line: need and spare from the verb's range; a first read goes with no hw, nw=1 and hs=0", field(first, "gn") == "1.170"
		and field(first, "sp") == "-0.670" and field(first, "nw") == "1" and field(first, "hs") == "0" and field(first, "hw") == nil and field(first, "sa") == "0", first)
	local held = run(function(w, c)
		w.core.mode = 2
		w.CO.Shadow(w.core)
		T = T + 0.3
		w.core.mode = 0
		w.core.target = c
		w.targets = { target(c, { walk = 0.3, due = 0.5, dies = 3 }) }
	end)
	check("start line: held by attack, then it went 0.3 s later: hw, hm, hs, sa=1 and nw=0", field(held, "hw") == "held" and field(held, "hm") == "attack"
		and field(held, "hs") == "0.300" and field(held, "sa") == "1" and field(held, "nw") == "0", held)
	local acting = run(function(w)
		w.core.channeling = true
		w.CO.Shadow(w.core)
		T = T + 0.2
		w.core.channeling = false
	end)
	check("start line: acting is the reason, and hm is absent", field(acting, "hw") == "acting" and field(acting, "hm") == nil, acting)
end

do -- the record is dropped for a creep that is no longer listed: a creep back after a gap reads as new
	local w = world()
	local c = ranged(500)
	local out = capture(function()
		w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
		w.core.mode = 2
		w.CO.Shadow(w.core)
		T = T + 0.1
		w.targets = { target(ranged(900), { walk = 2.0, due = 9 }) }
		w.CO.Shadow(w.core)
		T = T + 0.1
		w.core.mode = 0
		w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
		w.CO.Shadow(w.core)
	end)
	local start = lines(out, "job=creep")[1]
	check("pruned: back after a read without it, no hw and nw=1", start ~= nil and field(start, "hw") == nil and field(start, "nw") == "1", tostring(start))
end

do -- stock is already attacking the creep: the row goes anyway (its swing lands as often as stock's)
	local w = world()
	local c = ranged()
	w.targets = { target(c, { walk = 0, due = 0.2 }) }
	w.core.target = c
	local ch = lines(readThenClose(w, { c }), "kind=creep")
	check("stock on it: the attempt starts", w.starts == 1 and #ch == 1 and field(ch[1], "go") == "1", table.concat(ch, " | "))
end

do -- the lead is one own attack cycle: due past the walk plus a cycle waits, within it goes, whatever the cycle
	local function goes(spa, walk, due)
		local w = world()
		w.core.spa = spa
		local c = ranged()
		w.targets = { target(c, { walk = walk, due = due }) }
		readThenClose(w, { c })
		return w.starts == 1
	end
	check("lead: a 1.7 s cycle goes at walk 0.5, due 2.1 (0.4 s past the old lead's reach)", goes(1.7, 0.5, 2.1))
	check("control: a 1.7 s cycle waits at walk 0.5, due 2.3", not goes(1.7, 0.5, 2.3))
	check("lead: a 1.0 s cycle waits at walk 0.5, due 1.6", not goes(1.0, 0.5, 1.6))
	check("creep offer: laneTargets is asked for creeps due within one cycle, at least the engine's 1 s", (function()
		local w = world()
		w.core.spa = 1.6
		local a = w.CO.Within(w.core)
		w.core.spa = 0.8
		return near(a, 1.6) and near(w.CO.Within(w.core), 1)
	end)())
end

do -- Valve's attack or stock's retreat holds the hero: no attempt (it would be cut before a step), the creep kept for a later read
	for _, m in ipairs({ { 2, "attack" }, { 4, "retreat" } }) do
		local w = world()
		local c = ranged()
		w.core.mode = m[1]
		local out = capture(function()
			w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
			w.CO.Shadow(w.core)
			local before = w.starts
			T = T + 0.1
			w.core.mode = 0
			w.CO.Shadow(w.core)
			check("held by " .. m[2] .. ": nothing started while it holds", before == 0, tostring(before))
		end)
		check("held by " .. m[2] .. ": once released the same creep goes", w.starts == 1 and lastHitOpts(w).target == c, tostring(w.starts))
	end
end

do -- not yet about to come due, then due: waits, then goes on the same creep
	local w = world()
	local c = ranged()
	local out = capture(function()
		w.targets = { target(c, { walk = 0.5, due = 2.4 }) } -- due past walk + one 1.7 s cycle
		w.CO.Shadow(w.core)
		local early = w.starts
		T = T + 0.1
		w.targets = { target(c, { walk = 0.4, due = 2.0 }) }
		w.CO.Shadow(w.core)
		check("early: nothing started on the first read", early == 0, tostring(early))
	end)
	check("then due: the attempt starts", w.starts == 1, tostring(w.starts))
end

do -- the cells: a long free walk goes; a covered long walk, an out-damaging enemy, our tower's range, a melee creep do not
	local function case(name, setup, want)
		local w = world()
		local c = ranged(900)
		local t = { walk = 2.0, due = 2.2, dies = 4 }
		setup(w, c, t)
		w.targets = { target(c, t) }
		local ch = lines(readThenClose(w, { c }), "kind=creep")
		local got = w.starts == 1 and "go" or field(ch[1], "why")
		check("cell: " .. name .. " -> " .. want, got == want, tostring(got) .. " | " .. table.concat(ch, " | "))
	end
	case("a 2 s walk with no enemy hero", function() end, "go")
	case("a 2 s walk to a spot an enemy hero's range covers", function()
		local foe = MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(700, -5000) })
		foe.dmg, foe.range, foe.spa = 20, 550, 1.7
	end, "covered")
	case("an enemy hero in range of the creep that hits harder", function(_, _, t)
		t.walk, t.due = 0, 0.2
		local foe = MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(1300, -5000) })
		foe.dmg, foe.range, foe.spa = 90, 600, 1.7
	end, "outdmg")
	case("inside our tower's range", function(_, c)
		local tw = MakeLaneTowers()[2][dota.Tower.Bot1]
		tw.loc = c.loc
		TOWERS_W[2] = { [dota.Tower.Bot1] = tw }
	end, "tower")
	-- The race: a melee enemy 800 from the creep reaches its own range of it in about 2.0 s, before the creep is due (2.2 s).
	local function foeAt(x, dmg)
		return function()
			local foe = MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(x, -5000) })
			foe.dmg, foe.range, foe.spa = dmg, 150, 1.4
		end
	end
	case("a 2 s walk with an enemy that can reach the creep first, hitting as hard", foeAt(1700, 55), "race")
	case("control: the same enemy hitting softer", foeAt(1700, 40), "go")
	case("control: the same enemy too far to reach it before it is due", foeAt(2400, 55), "go")
	case("control: in range, the enemy as close does not stop the swing", function(w, c, t)
		t.walk, t.due = 0, 0.3
		c.loc = Vector(300, -5000)
		foeAt(500, 55)()
	end, "go")
	case("a melee creep", function(_, c) c.name = "npc_dota_creep_badguys_melee" end, "kind")
	case("their deny of our creep", function(_, c, t) t.kind = "deny" end, "kind")
	case("a walk it cannot make before the creep dies", function(_, _, t) t.dies = 2.1 end, "late")
end

do -- something else due where the hero stands: the walk-in gives it up, so the row stays
	local w = world()
	local c = ranged(900)
	local here = MakeCreep({ team = 3, x = 100, y = -5000, hp = 40 })
	w.targets = { target(c, { walk = 2.0, due = 2.2, dies = 4 }), target(here, { walk = 0, due = 1.0, dies = 5 }) }
	local ch = lines(readThenClose(w, { c, here }), "ck=r")
	check("given up: no attempt, why=given", w.starts == 0 and #ch == 1 and field(ch[1], "why") == "given", table.concat(ch, " | "))
end

do -- two claimed creeps: the one closest to due; one attempt a creep
	local w = world()
	local a, b = ranged(300), ranged(320)
	w.targets = { target(a, { walk = 0, due = 0.4 }), target(b, { walk = 0, due = 0.1 }) }
	local first
	capture(function()
		w.CO.Shadow(w.core)
		first = w.starts == 1 and lastHitOpts(w).target or nil
		w.onEnd({ success = false, reason = "timeout" })
		T = T + 0.1
		w.CO.Shadow(w.core)
	end)
	check("two: the first attempt is on b, due first", first == b, tostring(first))
	check("one attempt a creep: after b's ended, the next read went for a", w.starts == 2 and lastHitOpts(w).target == a, tostring(w.starts))
end

do -- off: the read's shadow lines, nothing started
	local w = world({ on = false })
	local c = ranged()
	w.targets = { target(c, { walk = 0, due = 0.2 }) }
	local ch = lines(readThenClose(w, { c }), "kind=creep")
	check("off: no attempt, the shadow line", w.starts == 0 and #ch == 1 and field(ch[1], "src") == "shadow" and field(ch[1], "why") == "off", table.concat(ch, " | "))
end

do -- a support: the trip table does not let it act (and the read does not cover it)
	local w = world({ pos = 5 })
	local c = ranged()
	w.targets = { target(c, { walk = 0, due = 0.2 }) }
	readThenClose(w, { c })
	check("pos 5: no attempt", w.starts == 0, tostring(w.starts))
end

do -- refused by the runner: no hold, why=refused
	local w = world({ refuse = true })
	local c = ranged()
	w.targets = { target(c, { walk = 0, due = 0.2 }) }
	local a
	local ch = lines(capture(function()
		w.CO.Shadow(w.core)
		a = w.CR.ROW.applies(w.core)
		T = T + 0.1
		kill(c)
		w.targets = {}
		w.CO.Shadow(w.core)
	end), "kind=creep")
	check("refused: no hold, why=refused", a == false and #ch == 1 and field(ch[1], "why") == "refused", table.concat(ch, " | "))
end

finish()
