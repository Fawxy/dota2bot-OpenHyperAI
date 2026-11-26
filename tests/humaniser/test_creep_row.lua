dofile(HARNESS_DIR .. "/lane_world.lua")
-- The creep row (creep_row.ts, Ours.LaneCreeps, doctrine D11): their ranged creep in the claimed cells, decided at the creep
-- offer read. The engine's laneTargets, hpForecast and task runner are stubbed (ForOurs), so these cover the decision, the
-- latch and the lines; the lastHit verb is the engine's (its own tests) and its execution is the rig's.

-- The engine's own attackReach: the stubbed Verbs below carry the real fact, so the row and the read answer as the verb does.
local REAL_ENGINE = dofile(BOTS_ROOT .. "/bots/FunLib/engine/tasks.lua")

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
			attackReach = REAL_ENGINE.Verbs.attackReach,
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
	-- The runner's Cancel: ends the task through its onEnd, as the engine's does.
	F.Cancel = function(_, reason, message)
		w.cancelled = { reason = reason, message = message }
		w.onEnd({ success = false, reason = reason, message = message })
	end
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
				c.loc = Vector(moveIn == true and 100 or moveIn, -5000)
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
	-- 180 apart: past the range (150), inside the reach (190): the verb's test passes there, so tin is read there too.
	jobs = lines(attempt({ success = false, reason = "denied", message = "w=1.00 end=0 dt=0.30" }, 180), "job=creep")
	check("lines: tin is the first step inside the reach, past the bare range", field(jobs[2], "tin") == "0.700", jobs[2])
	jobs = lines(attempt({ success = false, reason = "taken_by_other", message = "w=1.20 why=range d=140" }, false), "job=creep")
	check("lines: never in range reads tin=-1; a pre-swing message reads sw=0 and is kept", field(jobs[2], "tin") == "-1" and field(jobs[2], "sw") == "0"
		and jobs[2]:find('msg="w=1.20 why=range d=140"', 1, true) ~= nil, jobs[2])
	jobs = lines(attempt({ success = true, message = "hit=other w=0.40 why=range d=80" }, false), "job=creep")
	check("lines: ok from a swing ordered before the verb's reads why=ok sw=0", field(jobs[2], "why") == "ok" and field(jobs[2], "sw") == "0", jobs[2])
	jobs = lines(attempt({ success = true, message = "w=1.00 hp=60 pred=0 mine=55 t=0.40 m=0.10 obs=20 idps=30 end=0 dt=0.30" }, true), "job=creep")
	check("lines: ok from the verb's own swing reads sw=1", field(jobs[2], "why") == "ok" and field(jobs[2], "sw") == "1", jobs[2])
	jobs = lines(attempt({ success = false, reason = "preempted", message = "mode=5" }, false), "job=creep")
	check("lines: a cut leaves the swing unknown", field(jobs[2], "sw") == nil, jobs[2])
end

do -- the start line says what held the row and what the spare was: need from the verb's own range, not the offer's walk
	local function run(prep)
		local w = world()
		w.core.range = 150
		w.core.speed = 300
		local c = ranged(500)
		w.targets = { target(c, { walk = 0.3, due = 1.4, dies = 3 }) }
		local out = capture(function()
			prep(w, c)
			w.CO.Shadow(w.core)
			w.CR.ROW.applies(w.core)
		end)
		return lines(out, "job=creep")[1]
	end
	local first = run(function() end)
	-- 500 apart, reach 190 (range 150 and the hulls 24 and 16): 310 to walk at 300 a second.
	check("start line: need and spare from the verb's reach; a first read goes with no hw, nw=1 and hs=0", field(first, "gn") == "1.030"
		and field(first, "sp") == "0.370" and field(first, "rch") == "190" and field(first, "nw") == "1" and field(first, "hs") == "0" and field(first, "hw") == nil and field(first, "sa") == "0", first)
	local held = run(function(w, c)
		w.core.mode = 4
		w.CO.Shadow(w.core)
		T = T + 0.3
		w.core.mode = 0
		w.core.target = c
		w.targets = { target(c, { walk = 0.3, due = 1.4, dies = 3 }) }
	end)
	check("start line: held by retreat, then it went 0.3 s later: hw, hm, hs, sa=1 and nw=0", field(held, "hw") == "held" and field(held, "hm") == "retreat"
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
		w.core.mode = 4
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

do -- a read with no targets at all drops the record too: a creep back after it reads as new, not with the old hw
	local w = world()
	local c = ranged(500)
	local out = capture(function()
		w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
		w.core.mode = 4
		w.CO.Shadow(w.core)
		T = T + 0.1
		w.targets = {}
		w.CO.Shadow(w.core)
		T = T + 0.1
		w.core.mode = 0
		w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
		w.CO.Shadow(w.core)
	end)
	local start = lines(out, "job=creep")[1]
	check("pruned by a read with no targets: no hw and nw=1", start ~= nil and field(start, "hw") == nil and field(start, "nw") == "1", tostring(start))
end

do -- the choice line keeps the first refusal in `why` and the last in `lw`, so a notime_* reason can be counted
	local w = world()
	w.core.range, w.core.speed = 150, 300
	local c = ranged(300)
	local out = capture(function()
		w.targets = { target(c, { walk = 0.5, due = 0.8, dies = 3 }) }
		w.core.mode = 4
		w.CO.Shadow(w.core)
		T = T + 0.1
		w.targets = { target(c, { walk = 0.5, due = 0.3, dies = 3 }) }
		w.CO.Shadow(w.core)
		T = T + 0.1
		kill(c)
		w.targets = {}
		w.CO.Shadow(w.core)
	end)
	local ch = lines(out, "kind=creep")
	check("lw: held first, then not on time after held", #ch == 1 and field(ch[1], "why") == "held" and field(ch[1], "lw") == "notime_held", table.concat(ch, " | "))
	w = world()
	c = ranged(300)
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	ch = lines(readThenClose(w, { c }), "kind=creep")
	check("lw: absent on a creep that went", #ch == 1 and field(ch[1], "go") == "1" and field(ch[1], "lw") == nil, table.concat(ch, " | "))
end

do -- on time: the creep must come due no sooner than the hero can be in the verb's reach (range 150 and hulls 24 and 16: 190; speed 300, creep 300 away: 0.37 s)
	local function world3(due)
		local w = world()
		w.core.range, w.core.speed = 150, 300
		local c = ranged(300)
		w.targets = { target(c, { walk = 0.37, due = due, dies = 3 }) }
		return w, c
	end
	local w, c = world3(0.6)
	readThenClose(w, { c })
	check("on time: due 0.6 against a need of 0.37 goes", w.starts == 1)
	w, c = world3(0.3)
	local ch = lines(readThenClose(w, { c }), "kind=creep")
	check("not on time: due 0.3 against 0.37 is refused at its first read about to come due: notime_new", w.starts == 0 and #ch == 1 and field(ch[1], "why") == "notime_new", table.concat(ch, " | "))
	-- The offer's walk (0.2 here) says in range in time; the check reads the engine's reach, not that walk.
	w, c = world3(0.3)
	w.targets = { target(c, { walk = 0.2, due = 0.3, dies = 3 }) }
	readThenClose(w, { c })
	check("the verb's reach, not the offer's walk: walk 0.2 and due 0.3 is still refused", w.starts == 0, tostring(w.starts))
	-- 170 apart: past the range (150) but inside the reach (190, with the hulls), so the swing is ordered with no walk. The bare
	-- range would have said a 0.07 s walk and refused due 0.05.
	w = world()
	w.core.range, w.core.speed = 150, 300
	c = ranged(170)
	w.targets = { target(c, { walk = 0, due = 0.05, dies = 3 }) }
	readThenClose(w, { c })
	check("between the range and the reach there is nothing to walk: due 0.05 goes", w.starts == 1, tostring(w.starts))
end

do -- the refusal names what happened before, and a later read still goes once the times allow
	local function history(setup)
		local w = world()
		w.core.range, w.core.speed = 150, 300
		local c = ranged(300)
		local function read(due, mode)
			w.targets = { target(c, { walk = 0.5, due = due, dies = 3 }) }
			w.core.mode = mode or 0
			w.CO.Shadow(w.core)
			T = T + 0.1
		end
		local out = capture(function() setup(w, c, read) end)
		local starts = lines(lines(out, "job=creep"), "phase=start")
		return w, starts[#starts]
	end
	local w, start = history(function(w, c, read)
		read(0.8, 4) -- on time, stock's retreat holds the hero
		read(0.3) -- not on time any more
		read(0.7) -- on time again
	end)
	check("after a refusal on time for held, a later refusal is notime_held and the creep goes when on time again", w.starts == 1 and field(start, "hw") == "notime_held", tostring(start))
	w, start = history(function(w, c, read)
		w.core.channeling = true
		read(0.8)
		read(0.3)
		w.core.channeling = false
		read(0.7)
	end)
	check("after acting on time: notime_acting", w.starts == 1 and field(start, "hw") == "notime_acting", tostring(start))
	w, start = history(function(w, c, read)
		read(0.3) -- the first read about to come due is not on time
		read(0.7)
	end)
	check("not on time at the first read about to come due: notime_new, then it goes", w.starts == 1 and field(start, "hw") == "notime_new", tostring(start))
	w, start = history(function(w, c, read)
		w.targets = {}
		local b = ranged(200)
		local function both(dueA)
			w.targets = { target(c, { walk = 0.5, due = dueA, dies = 3 }), target(b, { walk = 0.5, due = 0.2, dies = 3 }) }
			w.CO.Shadow(w.core)
			T = T + 0.1
		end
		both(0.8) -- b is closer to due: it goes, c is refused as other (on time)
		w.onEnd({ success = false, reason = "timeout" })
		both(0.3) -- c is no longer on time
		w.targets = { target(c, { walk = 0.5, due = 0.7, dies = 3 }) }
		w.CO.Shadow(w.core)
	end)
	check("a refusal on time for something else, then not on time: plain notime", w.starts == 2 and field(start, "hw") == "notime" and field(start, "gd") == "0.700", tostring(start))
end

do -- stock is already attacking the creep: the row goes anyway (its swing lands as often as stock's)
	local w = world()
	local c = ranged()
	w.targets = { target(c, { walk = 0, due = 0.2 }) }
	w.core.target = c
	local ch = lines(readThenClose(w, { c }), "kind=creep")
	check("stock on it: the attempt starts", w.starts == 1 and #ch == 1 and field(ch[1], "go") == "1", table.concat(ch, " | "))
end

do -- the lead is the longer of one own attack cycle and EarlyLead (3 s): due past the walk plus it waits, within it goes
	local function goes(spa, walk, due)
		local w = world()
		w.core.spa = spa
		local c = ranged()
		w.targets = { target(c, { walk = walk, due = due }) }
		readThenClose(w, { c })
		return w.starts == 1
	end
	check("lead: a 1.7 s cycle goes at walk 0.5, due 3.4 (the early lead is the longer)", goes(1.7, 0.5, 3.4))
	check("control: a 1.7 s cycle waits at walk 0.5, due 3.6", not goes(1.7, 0.5, 3.6))
	check("lead: a 4 s cycle goes at walk 0.5, due 4.4 (the cycle is the longer)", goes(4, 0.5, 4.4))
	check("control: a 4 s cycle waits at walk 0.5, due 4.6", not goes(4, 0.5, 4.6))
	check("creep offer: laneTargets is asked for creeps due within the lead for a hero the row acts on, the read's own for one it is off for", (function()
		local w = world()
		w.core.spa = 1.6
		local a = w.CO.Within(w.core)
		local w2 = world({ on = false })
		w2.core.spa = 1.6
		return near(a, 3) and near(w2.CO.Within(w2.core), 1.6)
	end)())
end

do -- the hold is hard: Valve's attack does not stop it going; stock's retreat (the mode, or the decider letting go) still does
	local w = world()
	local c = ranged()
	w.core.mode = 2
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	capture(function() w.CO.Shadow(w.core) end)
	check("hard: the hero in Valve's attack mode goes", w.starts == 1 and lastHitOpts(w).target == c, tostring(w.starts))
	local D = package.loaded["bots/FunLib/humaniser/decider"]
	check("hard: while the attempt runs the decider holds the hero at HARD", D.Host(w.core, function() return 0 end)() == D.HARD)

	w = world()
	c = ranged()
	local out = capture(function()
		w.core.mode = 4
		w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
		w.CO.Shadow(w.core)
		local before = w.starts
		T = T + 0.1
		w.core.mode = 0
		w.CO.Shadow(w.core)
		check("held by retreat: nothing started while it holds", before == 0, tostring(before))
	end)
	check("held by retreat: once released the same creep goes", w.starts == 1 and lastHitOpts(w).target == c, tostring(w.starts))
	local start = lines(out, "phase=start")[1]
	check("held by retreat: the start line names it", field(start, "hw") == "held" and field(start, "hm") == "retreat", tostring(start))
end

do -- the hold per phase: HARD through every phase, the phase times and the swing order on the end line
	local D
	local function approx(s, v) return s ~= nil and math.abs(tonumber(s) - v) < 0.011 end
	local function attempt(phases, finish, due)
		local w = world()
		D = package.loaded["bots/FunLib/humaniser/decider"]
		w.targets = { target(ranged(170), { walk = 0, due = due or 2.0 }) }
		local desires, deciderLines, after = {}, {}, nil
		local out = capture(function()
			w.CO.Shadow(w.core)
			w.CR.ROW.applies(w.core)
			local t0 = T
			local verb = lastHitOpts(w)
			for _, p in ipairs(phases) do
				T = t0 + p[2]
				verb.onPhase(p[1], T)
				desires[#desires + 1] = D.Host(w.core, function() return 0 end)()
			end
			T = t0 + finish[1]
			w.onEnd(finish[2])
			after = D.Host(w.core, function() return 0.123 end)()
		end)
		for _, l in ipairs(out) do if l:find("kind=decider", 1, true) and l:find("held=creep", 1, true) then deciderLines[#deciderLines + 1] = l end end
		return desires, deciderLines, lines(out, "job=creep")[2], after
	end

	local d, dl, e, after = attempt({ { "walk", 0.1 }, { "wait", 0.5 }, { "swing", 0.7 } }, { 1.0, { success = true, message = "end=0" } })
	check("hard: the hold is HARD in every phase, with the creep due in 2 s, and the decider's line says hs=hard only", d[1] == D.HARD and d[2] == D.HARD and d[3] == D.HARD and #dl == 1 and dl[1]:find("hs=hard", 1, true), table.concat(d, " ") .. " " .. table.concat(dl, " | "))
	check("end line: seconds per phase and the swing order", approx(field(e, "pw"), 0.4) and approx(field(e, "pq"), 0.2) and approx(field(e, "ps"), 0.3) and approx(field(e, "so"), 0.7), tostring(e))

	d, dl, e, after = attempt({ { "walk", 0.1 } }, { 0.6, { success = false, reason = "preempted", message = "mode=5" } })
	check("cut while walking: only pw is spent and no swing order is recorded", approx(field(e, "pw"), 0.5) and approx(field(e, "pq"), 0) and approx(field(e, "ps"), 0) and field(e, "so") == "-1", tostring(e))
	check("control: once the attempt has ended the row no longer holds and farm's own desire is returned", after == 0.123, tostring(after))
end

do -- the early go: a creep past the walk plus one cycle but inside the walk plus EarlyLead
	local function approx(s, v) return s ~= nil and math.abs(tonumber(s) - v) < 0.011 end
	-- A creep 640 away (a 1.5 s walk at 300 to the 190 reach) due in 2.8 s: past the walk plus a 1 s cycle (2.5), inside the walk plus 3 s.
	local function early(due)
		local w = world()
		w.core.range, w.core.speed, w.core.spa = 150, 300, 1.0
		local c = ranged(640)
		w.targets = { target(c, { walk = 1.5, due = due }) }
		return w, readThenClose(w, { c })
	end
	local w, out = early(2.8)
	check("early go: due 2.8 with a 1.5 s walk goes, and its start line names the lead in force", w.starts == 1 and approx(field(lines(out, "phase=start")[1], "ld"), 3), tostring(w.starts))
	w, out = early(1.0)
	local ch = lines(out, "kind=creep")
	check("control: the early lead does not waive the on-time check: due 1.0 against a 1.5 s walk is refused notime_new", w.starts == 0 and field(ch[1], "why") == "notime_new", table.concat(ch, " | "))

	-- The row's step gaps: another mode having the hero between steps is counted, and a creep whose attempt ended is not tried again.
	local function start(due)
		local w2 = world()
		w2.core.range, w2.core.speed, w2.core.spa = 150, 300, 1.0
		w2.c = ranged(170)
		w2.targets = { target(w2.c, { walk = 0, due = due }) }
		w2.out = {}
		w2.cap = function(fn) for _, l in ipairs(capture(fn)) do w2.out[#w2.out + 1] = l end end
		w2.cap(function() w2.CO.Shadow(w2.core) end)
		w2.t0 = T
		return w2
	end
	local function read(w2, dt, due)
		T = w2.t0 + dt
		w2.targets = { target(w2.c, { walk = 0, due = due }) }
		w2.cap(function() w2.CO.Shadow(w2.core) end)
	end
	local function step(w2, dt)
		T = w2.t0 + dt
		w2.CR.ROW.step(w2.core)
	end

	w = start(2.0)
	step(w, 0.1)
	step(w, 0.2)
	step(w, 1.2)
	read(w, 1.3, 1.0)
	local kept = w.CR.ROW.applies(w.core)
	T = w.t0 + 1.5
	w.cap(function() w.onEnd({ success = true, message = "end=0" }) end)
	local e = lines(w.out, "phase=end")[1]
	check("taken during the walk and back: the attempt continues; the end line counts the time taken", kept and field(e, "tk") == "1" and approx(field(e, "tks"), 1.0), tostring(e))

	w = start(0.3)
	w.cap(function() w.onEnd({ success = false, reason = "timeout", message = "w=1.00 why=wait" }) end)
	local starts = w.starts
	read(w, 2.0, 2.0)
	check("an attempt that ended spends the creep's one try", w.starts == starts, tostring(w.starts))
end

do -- the decider has let the hero go to stock's retreat (an attempt's hold met a retreat that leads): a creep read then is not taken
	local w = world()
	local c, d = ranged(300), ranged(320)
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	capture(function() w.CO.Shadow(w.core) end)
	local D = package.loaded["bots/FunLib/humaniser/decider"]
	D.NoteDesire(w.core, "retreat", 0.9)
	D.Host(w.core, function() return 0 end)()
	local let = D.LetGo(w.core)
	w.onEnd({ success = false, reason = "preempted" })
	T = T + 0.1
	w.targets = { target(d, { walk = 0.3, due = 0.5 }) }
	capture(function() w.CO.Shadow(w.core) end)
	check("let go: the decider yields to retreat, and the next creep read starts nothing", let == true and w.starts == 1, tostring(let) .. " " .. w.starts)
end

do -- not yet about to come due, then due: waits, then goes on the same creep
	local w = world()
	local c = ranged()
	local out = capture(function()
		w.targets = { target(c, { walk = 0.5, due = 3.6 }) } -- due past walk + the 3 s lead
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
	case("an enemy hero in range of the creep that hits harder", function(_, c, t)
		t.walk, t.due = 0, 0.2
		c.loc = Vector(300, -5000)
		local foe = MakeUnit({ pid = 7, team = 3, bot = true, loc = Vector(700, -5000) })
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
