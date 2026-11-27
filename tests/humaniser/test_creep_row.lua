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
-- The row's offer to the decider: one while its attempt runs (the latch).
local function holds(w) return w.CR.ROW.wants(w.core) ~= nil end
local function lines(all, pat) local r = {} for _, l in ipairs(all) do if l:find(pat, 1, true) then table.insert(r, l) end end return r end
local function field(line, k) return line and line:match(" " .. k .. "=(%S+)") end

local RANGED = "npc_dota_creep_badguys_ranged"

-- o.on: the switch; o.refuse: the runner refuses. w.targets: what laneTargets returns; w.starts, w.opts, w.body, w.onEnd: the
-- last Start's.
local function world(o)
	o = o or {}
	local H = LaneFresh({ Enable = true }, { skill = 1, telemetry = { Enable = true } })
	package.loaded["bots/FunLib/custom_loader"].Ours.LaneCreeps = o.on ~= false
	package.loaded["bots/FunLib/custom_loader"].Ours.CreepDeny = o.deny == true
	package.loaded["bots/FunLib/custom_loader"].Ours.SupportCreeps = o.support == true
	package.loaded["bots/FunLib/custom_loader"].Ours.TowerCreeps = o.tower == true
	package.loaded["bots/FunLib/custom_loader"].Ours.CreepSpells = o.spells == true
	package.loaded["bots/FunLib/custom_loader"].Ours.TowerStay = o.stay == true
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
			turnTime = function() return 0 end,
			cooldownLeft = function() return w.cd or 0 end,
			-- The engine's ownHitTime counts the cooldown left (ownCommitTime): 0.3 s of wind-up and turn after it.
			ownHitTime = function() return 0.3 + (w.cd or 0) end,
		}
	end
	F.Jobs = function() return {} end
	F.Running = function() return w.running end
	F.Tick = function() end
	-- The runner's current task: the decider reads it to see that the row's attempt runs; it ends with the task's onEnd.
	F.Start = function(_, opts, body)
		w.starts = w.starts + 1
		w.opts, w.body = opts, body
		if o.refuse == true then return false end
		local task = { name = opts.name }
		w.running = task
		w.onEnd = function(r)
			if w.running == task then w.running = nil end
			opts.onEnd(r)
		end
		return true
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
		a1 = holds(w)
		s1 = w.CR.ROW.step(w.core)
		w.onEnd({ success = true })
		s2 = w.CR.ROW.step(w.core)
		a3 = holds(w)
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
			holds(w)
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
			holds(w)
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
			holds(w)
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
	local kept = holds(w)
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

do -- the under-tower hit (Ours.TowerCreeps, slice oha-tower-creeps): a creep of any kind inside our tower's range is the core's
	local MELEE = "npc_dota_creep_badguys_melee"
	local function under(o, name, tower)
		local w = world(o)
		local c = ranged(900)
		c.name = name
		if tower then
			local tw = MakeLaneTowers()[2][dota.Tower.Bot1]
			tw.loc = c.loc
			TOWERS_W[2] = { [dota.Tower.Bot1] = tw }
			if tower == "attacking" then
				-- 40 HP under a tower hitting for 80: the creep is within the hero's own hit just before the killing shot.
				c.hp, tw.dmg, tw.target = 40, 80, c
			end
		end
		w.targets = { target(c, { walk = 2.0, due = 2.2, dies = 4 }) }
		local ch = lines(readThenClose(w, { c }), "kind=creep")
		return w, field(ch[1], "why"), table.concat(ch, " | ")
	end
	local w, why, ch = under({ tower = true }, MELEE, "attacking")
	check("tower creeps on: a melee creep inside our tower's range that the tower attacks is a last hit and goes", w.starts == 1 and w.CR.KindOf(w.core, "lasthit", "m", true) == "lh", tostring(w.starts) .. " | " .. ch)
	w, why, ch = under({ tower = true }, MELEE, false)
	check("tower creeps on, control: the same melee creep outside the tower's range is refused kind", w.starts == 0 and why == "kind", ch)
	w, why, ch = under({ tower = false }, RANGED, true)
	check("tower creeps off: a ranged creep inside our tower's range is still refused tower", w.starts == 0 and why == "tower", ch)
	w, why, ch = under({ tower = false }, MELEE, true)
	check("tower creeps off: a melee creep inside our tower's range is refused kind", w.starts == 0 and why == "kind", ch)
end

do -- the leftover rule (Ours.TowerCreeps, creep_row Verdict): the pure verdict
	local V = world({ tower = true }).CR.Verdict
	local function vd(...) local r = V(...) return r.vd, r.shots, r.leftover, r.need end
	local a, s, l = vd(550, 80, 72, 72, 1.5, 0, 1)
	check("verdict: a leftover within one lowest hit waits (550 HP, tower 80, hit 72: 70 left before the killing shot)", a == "wait" and s == 6 and l == 70, a .. s .. l)
	a, s, l = vd(550, 80, 43, 49, 1.5, 0, 1)
	check("verdict: the same creep under hits of 43 to 49 needs a pre-hit", a == "prehit" and s == 6 and l == 70, a .. s .. l)
	check("verdict: no tower shot left before the kill and one hit does not cover it is none", vd(62, 80, 43, 49, 1.5, 0, 1) == "none")
	check("verdict: a leftover between the lowest and highest hit is left to the verb, not pre-hit", vd(530, 80, 43, 60, 1.5, 0, 1) == "wait" and vd(530, 80, 43, 49, 1.5, 0, 1) == "prehit")
	a, s, l, n = vd(760, 130, 40, 45, 1.5, 0, 1)
	check("verdict: a leftover of 110 needs two pre-hits when there is time for two", a == "prehit" and l == 110 and n == 2, a .. l .. n)
	check("verdict: two pre-hits with the tower's shots too quick for two attack cycles is none", vd(760, 130, 40, 45, 0.3, 0, 1) == "none")
	check("verdict: the walk to the first attack counts against the time", vd(550, 80, 43, 49, 1.0, 5.5, 1) == "none" and vd(550, 80, 43, 49, 1.0, 5, 1) == "prehit")
	check("verdict: no shot before the killing one is none whatever the tower's period", vd(110, 130, 40, 45, 100, 0, 1) == "none")
	check("verdict: a leftover past three lowest hits is none", vd(550, 200, 40, 45, 1.5, 0, 1) == "none")
end

do -- the leftover rule in the row: the pre-hit, the claim, the controls
	local MELEE = "npc_dota_creep_badguys_melee"
	local function gen(fn) return { ____coroutine = coroutine.create(fn) } end
	-- o.hp the creep's HP, o.attack what the tower attacks (default the creep, false none), o.mate an own creep attacking it, o.on the switch,
	-- o.stay Ours.TowerStay.
	local function towered(o)
		local w = world({ tower = o.on ~= false, stay = o.stay })
		local c = MakeCreep({ team = 3, x = 900, y = -5000, hp = o.hp or 550, name = MELEE })
		local tw = MakeLaneTowers()[2][dota.Tower.Bot1]
		tw.loc, tw.dmg, tw.spa = c.loc, 80, 1.0
		tw.target = o.attack == nil and c or o.attack or nil
		tw.targetReads = 0
		tw.GetAttackTarget = function(self) self.targetReads = self.targetReads + 1 return self.target end
		TOWERS_W[2] = { [dota.Tower.Bot1] = tw }
		w.core.dmg, w.core.spa = 46, 1.0
		w.core.GetBaseDamageVariance = function() return 3 end
		if o.mate then MakeCreep({ team = 2, x = 850, y = -5000, hp = 300, target = c }) end
		local V = w.CR.Verdict
		local real = package.loaded["bots/FunLib/humaniser/tasks"].ForOurs.Verbs
		package.loaded["bots/FunLib/humaniser/tasks"].ForOurs.Verbs = function()
			local v = real()
			v.ownHitTime = function() return 0.3 end
			return v
		end
		w.targets = { target(c, { walk = 1.0, due = o.due or 5, dies = 8 }) }
		w.tower, w.creep = tw, c
		w.order = {}
		w.ctx = {
			now = function() return T end,
			fail = function(r, m) return { success = false, reason = r, message = m } end,
			attackAndConfirm = function(pick, opts)
				return gen(function()
					table.insert(w.order, "attack")
					w.attacked = pick()
					w.prehitOpts = opts
					c.hp = c.hp - 46
					return { success = true, reason = "ok" }
				end)
			end,
			lastHit = function(opts)
				return gen(function()
					table.insert(w.order, "lasthit")
					w.lhOpts = opts
					return { success = true, reason = "ok" }
				end)
			end,
		}
		-- Runs the attempt's body to its end, the clock moving a read's step (0.1 s) at each frame.
		w.drive = function()
			local co = w.body(w.ctx).____coroutine
			for _ = 1, 60 do
				local ok, v = coroutine.resume(co)
				if not ok then error(v, 0) end
				if coroutine.status(co) == "dead" then return v end
				T = T + 0.1
			end
		end
		return w, V
	end

	local w = towered({})
	local out = capture(function()
		w.CO.Shadow(w.core)
		w.res = w.drive()
		w.onEnd(w.res)
	end)
	local jobs = lines(out, "job=creep")
	check("leftover: a fresh melee creep the tower attacks, killable by one pre-hit, is gone for at once", w.starts == 1 and field(jobs[1], "vd") == "prehit", w.starts .. " | " .. table.concat(out, " | "))
	check("leftover: one plain attack on the creep, then the last hit on the same creep", table.concat(w.order, ",") == "attack,lasthit" and w.attacked == w.creep and w.lhOpts.target == w.creep and w.prehitOpts.aggroConfirms == false, table.concat(w.order, ","))
	check("leftover: the attack order is cancelled after the pre-hit so the hero does not swing again", #ActionsOf(1, "MoveToLocation") == 1)
	check("leftover: the start line has the leftover, the tower's damage, the shots and the verdict; the end line the pre-hits", field(jobs[1], "lf") == "70" and field(jobs[1], "tT") == "80" and field(jobs[1], "ts") == "6" and field(jobs[2], "ph") == "1", table.concat(jobs, " | "))

	w = towered({ mate = true })
	local ch = lines(capture(function() w.CO.Shadow(w.core) end), "kind=creep")
	check("leftover: one of our creeps attacking it blocks the pre-hit, reason mates", w.starts == 0, w.starts .. " | " .. table.concat(ch, " | "))
	w = towered({ mate = true })
	ch = lines(readThenClose(w, { w.creep }), "kind=creep")
	check("leftover: the mates refusal is on the creep's line", field(ch[1], "why") == "mates", table.concat(ch, " | "))

	w = towered({ attack = false })
	ch = lines(readThenClose(w, { w.creep }), "kind=creep")
	check("leftover: a melee creep in our tower's range that the tower is not attacking is refused notarget", w.starts == 0 and field(ch[1], "why") == "notarget", w.starts .. " | " .. table.concat(ch, " | "))

	w = towered({ hp = 62 })
	ch = lines(readThenClose(w, { w.creep }), "kind=creep")
	check("leftover: a creep no pre-hit makes killable is refused nowindow", w.starts == 0 and field(ch[1], "why") == "nowindow", w.starts .. " | " .. table.concat(ch, " | "))

	-- A running attempt: the verdict was `wait` at the go (leftover within the hero's hit), so the body goes straight to the last hit.
	w = towered({ hp = 40, due = 1.2 })
	out = capture(function() w.CO.Shadow(w.core) w.drive() end)
	local o = w.lhOpts
	local claim = package.loaded["bots/FunLib/humaniser/creep_claim"]
	check("leftover: a wait verdict starts the attempt and goes straight to the last hit", w.starts == 1 and table.concat(w.order, ",") == "lasthit" and claim.HeldBy(1) ~= nil, table.concat(w.order, ","))
	check("leftover: while the verdict holds the attempt is not interrupted", o.interruptIf() == false)
	w.tower.target = nil
	check("leftover: the tower leaving the creep before a swing interrupts the attempt", o.interruptIf() == true)
	out = capture(function() w.onEnd({ success = false, reason = "interrupted" }) end)
	check("leftover: the claim is released at that end", claim.HeldBy(1) == nil and field(lines(out, "phase=end")[1], "cl") == "1", table.concat(out, " | "))
	w = towered({ hp = 40, due = 1.2 })
	capture(function() w.CO.Shadow(w.core) w.drive() end)
	o = w.lhOpts
	o.onPhase("swing", T)
	w.tower.target = nil
	check("leftover: an attempt whose swing is ordered is not interrupted", o.interruptIf() == false)

	-- The tower is still on the creep but the verdict turns none (more HP than any pre-hit can bring into a hit's reach): the attempt gives up.
	w = towered({ hp = 40, due = 1.2 })
	capture(function() w.CO.Shadow(w.core) w.drive() end)
	o = w.lhOpts
	check("leftover: a wait verdict that holds does not give the attempt up", o.interruptIf() == false and w.tower.target == w.creep)
	w.creep.hp = 62
	check("leftover: the verdict turning none with the tower still on the creep interrupts the attempt", o.interruptIf() == true and w.tower.target == w.creep)
	out = capture(function() w.onEnd({ success = false, reason = "interrupted" }) end)
	check("leftover: that end line says why it was given up, tl=nowindow", field(lines(out, "phase=end")[1], "tl") == "nowindow", table.concat(out, " | "))

	-- The third pre-hit is refused: two ordered, the creep's HP unchanged by them, the verdict still wants a pre-hit.
	w = towered({})
	w.ctx.attackAndConfirm = function(pick, opts)
		return gen(function()
			table.insert(w.order, "attack")
			return { success = true, reason = "ok" }
		end)
	end
	out = capture(function() w.CO.Shadow(w.core) w.res = w.drive() w.onEnd(w.res) end)
	check("leftover: a third pre-hit becomes none: two attacks, no last hit, the attempt ends interrupted", table.concat(w.order, ",") == "attack,attack" and w.res ~= nil and w.res.success == false and w.res.reason == "interrupted" and w.res.message == "nowindow", table.concat(w.order, ",") .. " | " .. tostring(w.res and w.res.message))
	check("leftover: the end line counts the two pre-hits", field(lines(out, "phase=end")[1], "ph") == "2", table.concat(out, " | "))

	-- A tower that is dead: the pre-hit's interrupt and the running attempt's both read it as the tower leaving the creep.
	w = towered({})
	capture(function() w.CO.Shadow(w.core) w.drive() end)
	check("leftover: a live tower on the creep does not interrupt the pre-hit", w.prehitOpts.interruptIf() == false)
	w.tower.alive = false
	check("leftover: a dead tower interrupts the pre-hit, even with its target still the creep", w.prehitOpts.interruptIf() == true and w.tower.target == w.creep)
	out = capture(function() w.onEnd({ success = false, reason = "interrupted" }) end)
	check("leftover: the pre-hit's end line says tl=tgt", field(lines(out, "phase=end")[1], "tl") == "tgt", table.concat(out, " | "))
	w = towered({ hp = 40, due = 1.2 })
	capture(function() w.CO.Shadow(w.core) w.drive() end)
	w.tower.alive = false
	check("leftover: a dead tower interrupts the running attempt before a swing", w.lhOpts.interruptIf() == true)
	out = capture(function() w.onEnd({ success = false, reason = "interrupted" }) end)
	check("leftover: its end line says tl=tgt", field(lines(out, "phase=end")[1], "tl") == "tgt", table.concat(out, " | "))

	-- Ours.TowerStay: the rule's refusal mid-attempt falls through to the plain last hit, noted once on the end line.
	w = towered({ hp = 40, due = 1.2, stay = true })
	capture(function() w.CO.Shadow(w.core) w.drive() end)
	o = w.lhOpts
	w.creep.hp = 62
	T = T + 0.5
	check("stay: the verdict turning none does not interrupt the last hit", o.interruptIf() == false and w.tower.target == w.creep)
	w.tower.target = nil
	check("stay: nor does the tower then leaving the creep", o.interruptIf() == false)
	out = capture(function() w.onEnd({ success = true, reason = "ok" }) end)
	local e = lines(out, "phase=end")[1]
	check("stay: the end line keeps the first refusal, its time from the go, and no creep of ours on it", field(e, "tl") == "nowindow" and tonumber(field(e, "tlt")) == 0.5 and field(e, "tlc") == "0", table.concat(out, " | "))

	local function noDamage(w)
		w.ctx.attackAndConfirm = function()
			return gen(function()
				table.insert(w.order, "attack")
				return { success = true, reason = "ok" }
			end)
		end
	end
	w = towered({ stay = true })
	noDamage(w)
	out = capture(function() w.CO.Shadow(w.core) w.res = w.drive() w.onEnd(w.res) end)
	check("stay: a refused third pre-hit falls through to the last hit", table.concat(w.order, ",") == "attack,attack,lasthit" and w.res.success == true, table.concat(w.order, ","))
	check("stay: that end line counts two pre-hits and the refusal", field(lines(out, "phase=end")[1], "ph") == "2" and field(lines(out, "phase=end")[1], "tl") == "nowindow", table.concat(out, " | "))

	w = towered({ stay = true })
	w.ctx.attackAndConfirm = function(_, opts)
		return gen(function()
			table.insert(w.order, "attack")
			w.tower.alive = false
			if opts.interruptIf() then return { success = false, reason = "interrupted" } end
			return { success = true, reason = "ok" }
		end)
	end
	out = capture(function() w.CO.Shadow(w.core) w.res = w.drive() w.onEnd(w.res) end)
	check("stay: the tower falling cuts the pre-hit, then the last hit", table.concat(w.order, ",") == "attack,lasthit" and w.res.success == true, table.concat(w.order, ","))
	check("stay: that end line says tl=tgt", field(lines(out, "phase=end")[1], "tl") == "tgt", table.concat(out, " | "))

	-- Our creep turns onto the creep after the go: the pre-hit is refused (mates). Off, the attempt ends; on, it goes to the last hit.
	for _, stay in ipairs({ false, true }) do
		w = towered({ stay = stay })
		capture(function() w.CO.Shadow(w.core) end)
		MakeCreep({ team = 2, x = 850, y = -5000, hp = 300, target = w.creep })
		out = capture(function() w.res = w.drive() w.onEnd(w.res) end)
		local tl = field(lines(out, "phase=end")[1], "tl")
		if stay then
			check("stay: our creeps on it after the go skip the pre-hit and go to the last hit, tlc=1", table.concat(w.order, ",") == "lasthit" and w.res.success == true and tl == "mates" and field(lines(out, "phase=end")[1], "tlc") == "1", table.concat(w.order, ",") .. " | " .. tostring(tl))
		else
			check("leftover: our creeps on it after the go end the attempt, tl=mates", #w.order == 0 and w.res.reason == "interrupted" and tl == "mates", table.concat(w.order, ",") .. " | " .. tostring(tl))
		end
	end

	-- The tower turns off the creep after the go, before any pre-hit is ordered. Off, the attempt ends; on, it goes to the last hit.
	for _, stay in ipairs({ false, true }) do
		w = towered({ stay = stay })
		capture(function() w.CO.Shadow(w.core) end)
		w.tower.target = nil
		out = capture(function() w.res = w.drive() w.onEnd(w.res) end)
		local tl = field(lines(out, "phase=end")[1], "tl")
		if stay then
			check("stay: the tower leaving before the pre-hit goes to the last hit, tl=tgt", table.concat(w.order, ",") == "lasthit" and w.res.success == true and tl == "tgt", table.concat(w.order, ",") .. " | " .. tostring(tl))
		else
			check("leftover: the tower leaving before the pre-hit ends the attempt, tl=tgt", #w.order == 0 and w.res.reason == "interrupted" and tl == "tgt", table.concat(w.order, ",") .. " | " .. tostring(tl))
		end
	end

	w = towered({ on = false })
	ch = lines(readThenClose(w, { w.creep }), "kind=creep")
	check("leftover: switch off, a melee creep under our tower is refused kind and the tower's target is not read", w.starts == 0 and field(ch[1], "why") == "kind" and w.tower.targetReads == 0, w.tower.targetReads .. " | " .. table.concat(ch, " | "))
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
		a = holds(w)
		T = T + 0.1
		kill(c)
		w.targets = {}
		w.CO.Shadow(w.core)
	end), "kind=creep")
	check("refused: no hold, why=refused", a == false and #ch == 1 and field(ch[1], "why") == "refused", table.concat(ch, " | "))
end

do -- the deny: a support denies our own creep of any kind on the same go; the verb is the engine's deny
	local function support(o)
		o.pos = 5
		local w = world(o)
		local c = MakeCreep({ team = 2, x = 300, y = -5000, hp = 60, name = "npc_dota_creep_goodguys_melee" })
		return w, c
	end
	local function verbs(w)
		local called = {}
		-- The verbs return a task body (truthy), as the engine's do.
		w.body({ lastHit = function(opts) called.lastHit = opts return true end, deny = function(opts) called.deny = opts return true end })
		return called
	end
	local w, c = support({ deny = true, on = false })
	w.targets = { target(c, { kind = "deny", walk = 0.3, due = 0.5 }) }
	local ch = lines(readThenClose(w, { c }), "kind=creep")
	local called = w.starts == 1 and verbs(w) or {}
	check("deny: a support starts one on a due melee creep of ours, calling deny and not lastHit", called.deny ~= nil and called.deny.target == c and called.lastHit == nil, tostring(w.starts))
	check("deny: the go line reads go=1", #ch == 1 and field(ch[1], "go") == "1", table.concat(ch, " | "))

	w, c = support({ deny = true, on = false })
	w.targets = { target(c, { kind = "deny", walk = 0.3, due = 0.5 }) }
	local jobs = lines(capture(function() w.CO.Shadow(w.core) w.onEnd({ success = true }) end), "job=creep")
	check("deny: the job lines carry k=dn", #jobs == 2 and field(jobs[1], "k") == "dn" and field(jobs[2], "k") == "dn", table.concat(jobs, " | "))

	w, c = world({ pos = 2 }), nil
	local rc = ranged()
	w.targets = { target(rc, { walk = 0.3, due = 0.5 }) }
	jobs = lines(capture(function() w.CO.Shadow(w.core) w.onEnd({ success = true }) end), "job=creep")
	check("deny: a last hit's job lines carry k=lh", #jobs == 2 and field(jobs[1], "k") == "lh" and field(jobs[2], "k") == "lh", table.concat(jobs, " | "))

	w, c = support({ deny = false, on = false })
	w.targets = { target(c, { kind = "deny", walk = 0.3, due = 0.5 }) }
	readThenClose(w, { c })
	check("deny off: the same support starts nothing", w.starts == 0, tostring(w.starts))

	w, c = support({ deny = true, on = true })
	local rcreep = ranged()
	w.targets = { target(rcreep, { walk = 0, due = 0.2 }) }
	ch = lines(readThenClose(w, { rcreep }), "kind=creep")
	check("a support's last hit of their ranged creep is refused with kind, LaneCreeps on", w.starts == 0 and field(ch[1], "why") == "kind", table.concat(ch, " | "))

	w, c = support({ deny = true, on = false })
	local tw = MakeLaneTowers()[2][dota.Tower.Bot1]
	tw.loc = c.loc
	TOWERS_W[2] = { [dota.Tower.Bot1] = tw }
	w.targets = { target(c, { kind = "deny", walk = 0, due = 0.3 }) }
	ch = lines(readThenClose(w, { c }), "kind=creep")
	check("deny inside our tower's range: not refused for tower", w.starts == 1, tostring(w.starts) .. " | " .. table.concat(ch, " | "))

	w, c = support({ deny = true, on = false })
	local melee = MakeCreep({ team = 2, x = 900, y = -5000, hp = 60, name = "npc_dota_creep_goodguys_melee" })
	local near = MakeCreep({ team = 3, x = 100, y = -5000, hp = 40 })
	w.targets = { target(melee, { kind = "deny", walk = 2.0, due = 2.2, dies = 4 }), target(near, { walk = 0, due = 1.0, dies = 5 }) }
	readThenClose(w, { melee, near })
	check("deny: another target due where the support stands does not refuse the walk-in (no given)", w.starts == 1, tostring(w.starts))
end

do -- another task running for the hero (a pull or stack) is not replaced by an attempt
	local function support(running)
		local w = world({ pos = 5, deny = true, on = false })
		w.running = running
		local c = MakeCreep({ team = 2, x = 300, y = -5000, hp = 60, name = "npc_dota_creep_goodguys_melee" })
		w.targets = { target(c, { kind = "deny", walk = 0.3, due = 0.5 }) }
		return w, lines(readThenClose(w, { c }), "kind=creep")
	end
	local w, ch = support({ name = "pull" })
	check("row: a support with a pull running starts no deny and notes row", w.starts == 0 and #ch == 1 and field(ch[1], "why") == "row", table.concat(ch, " | "))
	w, ch = support(nil)
	check("control: the same support with no task running starts the deny", w.starts == 1 and field(ch[1], "go") == "1", tostring(w.starts))
end

do -- the read's go is offered to the decider, which begins the row in the same call: its line at the read names the creep
	local w = world()
	local c = ranged()
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	local out = capture(function() w.CO.Shadow(w.core) end)
	local dl = lines(out, "kind=decider")
	local start = lines(out, "phase=start")[1]
	check("offer: one start at the read, begun by the decider", w.starts == 1 and #dl == 1 and field(dl[1], "beg") == "creep" and field(dl[1], "held") == "creep", table.concat(dl, " | "))
	check("offer: the line's target is the started creep", start ~= nil and field(dl[1], "btgt") == "creep:" .. field(start, "cid"), tostring(dl[1]))
end

-- The creep claim (creep_claim.ts, Reads.creep): taken in the row's begin, released at every end of the task.
local function claimOf(pid, cid) for _, c in ipairs(package.loaded["bots/FunLib/humaniser/creep_claim"].ClaimsOn(cid)) do if c.pid == pid then return c end end end

do -- a started attempt holds the claim until the task ends, whatever the end
	local ends = {
		{ "landed", { success = true } },
		{ "cut", { success = false, reason = "timeout" } },
		{ "taken by another mode", { success = false, reason = "preempted" } },
	}
	for _, e in ipairs(ends) do
		local w = world()
		local c = ranged()
		w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
		local out = capture(function() w.CO.Shadow(w.core) end)
		local cid = tonumber(field(lines(out, "phase=start")[1], "cid"))
		local Claim = package.loaded["bots/FunLib/humaniser/creep_claim"]
		local held = claimOf(1, cid)
		check("claim " .. e[1] .. ": held while the task runs, with the hero's rank and the due time", held ~= nil and held.rank == 60 and held.k == "lh" and near(held.due, 100.5) and Claim.HeldBy(1) == cid, tostring(held))
		local out2 = capture(function() w.onEnd(e[2]) end)
		check("claim " .. e[1] .. ": released at the end, which the end line says", claimOf(1, cid) == nil and Claim.HeldBy(1) == nil and field(lines(out2, "phase=end")[1], "cl") == "1", table.concat(out2, " | "))
	end
end

do -- the runner refusing the start leaves no claim; the verb's phase is on the claim
	local w = world({ refuse = true })
	local c = ranged()
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	capture(function() w.CO.Shadow(w.core) end)
	check("claim: a refused start takes none", package.loaded["bots/FunLib/humaniser/creep_claim"].HeldBy(1) == nil)

	w = world()
	c = ranged()
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	local out = capture(function() w.CO.Shadow(w.core) end)
	local cid = tonumber(field(lines(out, "phase=start")[1], "cid"))
	local before = claimOf(1, cid).phase
	lastHitOpts(w).onPhase("wait", 100.2)
	check("claim: the verb's phase is carried on it", before == nil and claimOf(1, cid).phase == "wait")
end

do -- two heroes on one creep: both hold, the second sees the first, one release leaves the other
	local Claim = package.loaded["bots/FunLib/humaniser/creep_claim"]
	world()
	local o1 = Claim.Take(7, { pid = 1, rank = 60, k = "lh", due = 10 })
	local o2 = Claim.Take(7, { pid = 2, rank = 60, k = "lh", due = 10.2 })
	check("two claims: the second names the first as already on the creep", #o1 == 0 and #o2 == 1 and o2[1] == 1)
	Claim.Release(1)
	local left = Claim.ClaimsOn(7)
	check("two claims: releasing one leaves the other", #left == 1 and left[1].pid == 2)
	Claim.Release(2)
	check("two claims: the last release frees the creep", #Claim.ClaimsOn(7) == 0)
end

do -- a hero's answer on a creep is dropped once a read no longer lists it
	local Claim = package.loaded["bots/FunLib/humaniser/creep_claim"]
	world()
	Claim.Touch(1, { 5, 6 }, 100)[5].why = "race"
	Claim.Touch(1, { 5 }, 100.2)
	check("answers: the creep still listed keeps its answer, the one gone is dropped", Claim.AnswerOf(1, 5).why == "race" and Claim.AnswerOf(1, 6) == nil)
end

do -- a support is covered by the read but does not act with the deny switch off
	local w = world({ deny = false })
	w.core.pos = 4
	local c = MakeCreep({ team = 2, x = 300, y = -5000, hp = 80, name = "npc_dota_creep_goodguys_melee" })
	w.targets = { target(c, { walk = 0.3, due = 0.5, kind = "deny" }) }
	local ch = lines(capture(function() w.CO.Shadow(w.core) T = T + 0.1 kill(c) w.targets = {} w.CO.Shadow(w.core) end), "kind=creep")
	check("support: a shadow line with go=0 why=off, and no task started", #ch == 1 and field(ch[1], "src") == "shadow" and field(ch[1], "go") == "0" and field(ch[1], "why") == "off" and w.starts == 0, table.concat(ch, " | "))
end

-- Supports' last hit (Ours.SupportCreeps, slice oha-support-creeps). The task runner stub is one for all heroes, so a test frees it between heroes.
local function addSupport(o)
	o = o or {}
	local u = MakeUnit({ pid = o.pid or 5, team = 2, bot = o.bot ~= false, loc = Vector(0, -5000), hp = 600, maxhp = 600 })
	u.pos, u.lane = o.pos or 4, o.lane or Lane.Bot
	return u
end
local function cidOf(c) return package.loaded["bots/FunLib/humaniser/telemetry"].CreepId(c) end
local function readOf(w, unit, c)
	local out = capture(function() w.CO.Shadow(unit) T = T + 0.1 kill(c) w.targets = {} w.CO.Shadow(unit) end)
	return lines(out, "kind=creep")
end

do -- the free rule: claimed, human, wait, refused, and a core is never asked
	local w = world({ support = true })
	local Claim = package.loaded["bots/FunLib/humaniser/creep_claim"]
	local sup = addSupport()
	check("free: a creep nobody lower has on offer is free", w.CR.FreeFor(sup, 77, T) == nil)
	Claim.Take(1, { pid = 1, rank = 60, k = "lh", due = 1 })
	check("free: a lower-cell hero's claim on another creep does not hold this one", w.CR.FreeFor(sup, 77, T) == nil)
	Claim.Release(1)
	Claim.Take(77, { pid = 1, rank = 60, k = "lh", due = 1 })
	check("free: a lower-cell hero's claim on it is `claimed`", w.CR.FreeFor(sup, 77, T) == "claimed")
	Claim.Release(1)
	Claim.Touch(1, { 77 }, T)
	check("free: on the core's offer with no refusal yet is `wait`", w.CR.FreeFor(sup, 77, T) == "wait")
	check("free: an answer the core stopped touching is not an offer", w.CR.FreeFor(sup, 77, T + 2) == nil)
	Claim.AnswerOf(1, 77).why = "race"
	check("free: once the core refuses it, free", w.CR.FreeFor(sup, 77, T) == nil)
	Claim.Take(77, { pid = 5, rank = 70, k = "lh", due = 1 })
	Claim.Touch(5, { 77 }, T)
	check("free: a core is never held by a support's claim or answer", w.CR.FreeFor(w.core, 77, T) == nil)
	Claim.Release(5)
	local human = addSupport({ pid = 3, pos = 3, bot = false })
	check("free: a human in the lane with a lower cell is `human`, a refusal of its cannot be read", w.CR.FreeFor(sup, 77, T) == "human")
	human.lane = Lane.Top
	check("free: a human in another lane does not freeze this one", w.CR.FreeFor(sup, 77, T) == nil)
	addSupport({ pid = 4, pos = 5 })
	Claim.Touch(4, { 77 }, T)
	Claim.Take(77, { pid = 4, rank = 70, k = "lh", due = 1 })
	check("free: a hero of the same cell never waits for or holds this one", w.CR.FreeFor(sup, 77, T) == nil)
end

do -- the row: the control (the core has it on offer, not refused), the core refusing, the switch off
	local w = world({ support = true })
	local Claim = package.loaded["bots/FunLib/humaniser/creep_claim"]
	local sup = addSupport()
	local c = ranged()
	local cid = cidOf(c)
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	Claim.Touch(1, { cid }, T)
	local ch = readOf(w, sup, c)
	check("support: the core has it on offer and has not refused: no task, the line reads `wait`", w.starts == 0 and #ch >= 1 and field(ch[1], "why") == "wait", table.concat(ch, " | "))

	w = world({ support = true })
	Claim = package.loaded["bots/FunLib/humaniser/creep_claim"]
	sup = addSupport()
	c = ranged()
	cid = cidOf(c)
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	Claim.Touch(1, { cid }, T)
	Claim.AnswerOf(1, cid).why = "race"
	local out = capture(function() w.CO.Shadow(sup) end)
	local held = claimOf(5, cid)
	check("support: the core refused it: the support goes, k=lh, and takes a claim at its own cell", w.starts == 1 and held ~= nil and held.rank == 70 and field(lines(out, "phase=start")[1], "k") == "lh", table.concat(out, " | "))
end

do -- the switch off: a support gets no last hit, a core keeps its own
	local w = world({ support = false })
	local sup = addSupport()
	check("switch off: a support has no lh kind and the row is off for it", w.CR.KindOf(sup, "lasthit", "r") == nil and not w.CR.On(sup) and w.CR.KindOf(w.core, "lasthit", "r") == "lh")
	w = world({ support = true })
	sup = addSupport()
	check("switch on: the support's kind is lh", w.CR.KindOf(sup, "lasthit", "r") == "lh" and w.CR.On(sup))
end

do -- Ours.TowerCreeps on: the under-tower hit stays a core's; a support takes their ranged creep outside our tower's range only (as audited)
	local w = world({ support = true, tower = true })
	local sup = addSupport()
	check("tower creeps on: a melee creep inside our tower's range is the core's kind, not the support's", w.CR.KindOf(w.core, "lasthit", "m", true) == "lh" and w.CR.KindOf(sup, "lasthit", "m", true) == nil)
	local c = ranged()
	local tw = MakeLaneTowers()[2][dota.Tower.Bot1]
	tw.loc = c.loc
	TOWERS_W[2] = { [dota.Tower.Bot1] = tw }
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	local ch = readOf(w, sup, c)
	check("tower creeps on: a support's ranged creep inside our tower's range is still refused tower", w.starts == 0 and field(ch[1], "why") == "tower", table.concat(ch, " | "))
end

do -- the yield: a lower-cell claim before the swing ends the attempt, with yd=1; after the swing order it does not
	local function supportAttempt()
		local w = world({ support = true })
		local Claim = package.loaded["bots/FunLib/humaniser/creep_claim"]
		local sup = addSupport()
		local c = ranged()
		local cid = cidOf(c)
		w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
		capture(function() w.CO.Shadow(sup) end)
		return w, Claim, cid, lastHitOpts(w)
	end
	local w, Claim, cid, opts = supportAttempt()
	check("yield: no lower-cell claim, the attempt goes on", opts.interruptIf() == false)
	Claim.Take(cid, { pid = 1, rank = 60, k = "lh", due = 1 })
	check("yield: a core takes a claim on the creep before the swing: the attempt ends", opts.interruptIf() == true)
	local out = capture(function() w.onEnd({ success = false, reason = "interrupted" }) end)
	check("yield: the end line says so", field(lines(out, "phase=end")[1], "yd") == "1", table.concat(out, " | "))

	w, Claim, cid, opts = supportAttempt()
	Claim.Take(cid, { pid = 1, rank = 60, k = "lh", due = 1 })
	opts.onPhase("swing", T)
	check("yield: the swing already ordered, the support keeps it", opts.interruptIf() == false)

	w = world({ support = true })
	Claim = package.loaded["bots/FunLib/humaniser/creep_claim"]
	local c = ranged()
	cid = cidOf(c)
	w.targets = { target(c, { walk = 0.3, due = 0.5 }) }
	capture(function() w.CO.Shadow(w.core) end)
	local copts = lastHitOpts(w)
	Claim.Take(cid, { pid = 5, rank = 70, k = "lh", due = 1 })
	Claim.Take(cid, { pid = 4, rank = 60, k = "lh", due = 1 })
	check("yield: a core never yields to a support, a hero of its own cell never yields to its mate", copts.interruptIf() == false)
end

-- The cast (Ours.CreepSpells, slice oha-creep-spells). A unit-target spell, 75 damage, range 800, cast point 0.3, landing at once; `special`
-- answers a table spell's damage key and the radius keys.
local function spell(o)
	o = o or {}
	return {
		IsNull = function() return false end, GetName = function() return o.name or "test_nuke" end, GetLevel = function() return 1 end,
		IsHidden = function() return false end, IsPassive = function() return false end, IsUltimate = function() return false end,
		IsFullyCastable = function() return true end, GetAbilityDamage = function() return o.dmg or 75 end,
		GetSpecialValueFloat = function(_, k) return (o.special or {})[k] or 0 end, GetBehavior = function() return 8 end,
		GetCastRange = function() return o.range or 800 end, GetCastPoint = function() return 0.3 end, GetManaCost = function() return o.mana or 100 end,
		GetCooldown = function() return 8 end,
	}
end

-- Their melee creep 300 away with 60 HP (one cast kills it), which a core's attack does not take (the row's kind is their ranged creep):
-- the attack ready in `cd` s and landing 0.3 s after its swing, the creep dying to the others' hits at `dies` s.
local function castWorld(o)
	o = o or {}
	local w = world({ spells = o.spells ~= false })
	w.cd = o.cd or 0.4
	w.core.mana = o.mana or 300
	w.core.abilities = o.abilities or { [0] = spell() }
	local c = MakeCreep({ team = 3, x = o.x or 300, y = -5000, hp = o.hp or 60 })
	w.targets = { target(c, { walk = o.walk or 0, due = 0, dies = o.dies or 0.5 }) }
	return w, c
end

local function castRead(w, c)
	return capture(function()
		w.CO.Shadow(w.core)
		T = T + 0.1
		kill(c)
		w.targets = {}
		w.CO.Shadow(w.core)
	end)
end

do -- the attack's hit lands after the creep dies (on cooldown): the cast goes on the creep, and the lines say so
	local w, c = castWorld()
	local out = castRead(w, c)
	local ch, jobs = lines(out, "kind=creep"), lines(out, "job=creep")
	check("cast: one task started, the row's decision", w.starts == 1, tostring(w.starts))
	local got
	w.body({ cast = function(a, opts) got = { a = a, opts = opts } end })
	check("cast: the engine's cast of that spell on the creep", got ~= nil and got.a:GetName() == "test_nuke" and got.opts.target == c, table.concat(out, " | "))
	check("cast: the creep's line reads cg=1 with the cast's attempt id, the attack's refusal kept", #ch == 1 and field(ch[1], "cg") == "1" and field(ch[1], "cw") == nil
		and field(ch[1], "aid") ~= nil and field(ch[1], "go") == "0", table.concat(ch, " | "))
	check("cast: the job start reads k=sp with the spell, its landing and its mana over the reserve", #jobs >= 1 and field(jobs[1], "k") == "sp" and field(jobs[1], "ab") == "test_nuke"
		and field(jobs[1], "al") == "0.300" and field(jobs[1], "am") == "200", table.concat(jobs, " | "))
	local claims = package.loaded["bots/FunLib/humaniser/creep_claim"].ClaimsOn(cidOf(c))
	check("cast: the claim is held as committed (phase swing, so no lower-cell start makes it yield)", #claims == 1 and claims[1].phase == "swing", #claims)
end

do -- controls: the cast waits while the attack can still take the creep, and keeps to its own rules
	local w, c = castWorld({ cd = 0, dies = 3 })
	local out = castRead(w, c)
	check("control: the attack is ready and the creep lives 3 s: no cast, the cast never weighed", w.starts == 0 and field(lines(out, "kind=creep")[1], "cg") == nil, table.concat(out, " | "))

	w, c = castWorld({ spells = false })
	out = castRead(w, c)
	check("switch off: no cast; the shadow marks the creep it would have cast on (cg=0 cw=off)", w.starts == 0 and field(lines(out, "kind=creep")[1], "cg") == "0"
		and field(lines(out, "kind=creep")[1], "cw") == "off", table.concat(out, " | "))

	w, c = castWorld({ hp = 90 })
	out = castRead(w, c)
	check("control: 90 HP against 75 damage: no cast, cw=nokill", w.starts == 0 and field(lines(out, "kind=creep")[1], "cg") == "0"
		and field(lines(out, "kind=creep")[1], "cw") == "nokill", table.concat(out, " | "))

	w, c = castWorld({ x = 1000 })
	out = castRead(w, c)
	check("control: the creep 1,000 away, range 800: no walk-in, cw=walk", w.starts == 0 and field(lines(out, "kind=creep")[1], "cw") == "walk", table.concat(out, " | "))

	w, c = castWorld({ mana = 180, abilities = { [0] = spell(), [1] = spell({ name = "sven_storm_bolt", mana = 110, special = { AbilityDamage = 100 } }) } })
	w.core.abilities[1].IsFullyCastable = function() return false end
	out = castRead(w, c)
	check("control: 180 mana less 100 leaves under the stun's 110: cw=reserve", w.starts == 0 and field(lines(out, "kind=creep")[1], "cw") == "reserve", table.concat(out, " | "))

	w, c = castWorld({ abilities = { [0] = spell({ name = "sven_storm_bolt", special = { AbilityDamage = 100 } }) } })
	out = castRead(w, c)
	check("control: a key spell with no enemy hero to hit: cw=key", w.starts == 0 and field(lines(out, "kind=creep")[1], "cw") == "key", table.concat(out, " | "))

	w, c = castWorld()
	w.core.IsCastingAbility = function() return true end
	out = castRead(w, c)
	check("control: the hero is already casting (OHA's own): no cast, cw=acting", w.starts == 0 and field(lines(out, "kind=creep")[1], "cw") == "acting", table.concat(out, " | "))

	w, c = castWorld()
	out = capture(function()
		w.CO.Shadow(w.core)
		w.onEnd({ success = false, reason = "timeout" })
		T = T + 0.1
		w.CO.Shadow(w.core)
	end)
	check("control: one attempt a creep: the cast timed out and the next read on the same creep casts again no more", w.starts == 1, tostring(w.starts))

	w, c = castWorld()
	w.core.mode = 4
	out = castRead(w, c)
	check("control: stock's retreat holds the hero: no cast, cw=held", w.starts == 0 and field(lines(out, "kind=creep")[1], "cw") == "held", table.concat(out, " | "))

	w, c = castWorld()
	w.running = { name = "pull" }
	out = castRead(w, c)
	check("control: another task runs for the hero (a pull): no cast, cw=row", w.starts == 0 and field(lines(out, "kind=creep")[1], "cw") == "row", table.concat(out, " | "))

	-- A support's cast and the core of its lane (pid 1) that has the creep on offer: still going for it, or refusing it for the creep's sake.
	for _, case in ipairs({ { why = "acting", casts = false }, { why = "covered", casts = true } }) do
		w, c = castWorld()
		local sup = addSupport({ pos = 4 })
		sup.mana, sup.abilities = 300, { [0] = spell() }
		package.loaded["bots/FunLib/humaniser/creep_claim"].Touch(1, { cidOf(c) }, T)[cidOf(c)].why = case.why
		out = capture(function() w.CO.Shadow(sup) end)
		local ch = lines(out, "job=creep")
		if case.casts then
			check("support: the core refused the creep as covered: the support casts", w.starts == 1 and field(ch[1], "k") == "sp", table.concat(out, " | "))
		else
			check("support: the core is still going for the creep (" .. case.why .. "): no cast", w.starts == 0, table.concat(out, " | "))
		end
	end

	w, c = castWorld()
	package.loaded["bots/FunLib/humaniser/creep_claim"].Take(cidOf(c), { pid = 2, rank = 60, k = "lh", due = 1 })
	out = castRead(w, c)
	check("control: a teammate holds a claim on the creep: cw=claimed", w.starts == 0 and field(lines(out, "kind=creep")[1], "cw") == "claimed", table.concat(out, " | "))
end

do -- the attack first: a ranged creep the row attacks this read, and a melee creep the cast could take
	local w, c = castWorld()
	local r = ranged(320)
	table.insert(w.targets, target(r, { walk = 0, due = 0.5, dies = 3 }))
	local out = capture(function() w.CO.Shadow(w.core) end)
	local job = lines(out, "job=creep")[1]
	check("attack first: the row's attempt is the last hit of the ranged creep", w.starts == 1 and field(job, "k") == "lh" and field(job, "cid") == tostring(cidOf(r)), table.concat(out, " | "))
end

do -- the go rule's parts, pure
	local CR = world().CR
	check("AttackLate: ready at 0.4, landing 0.3 later (the engine's 0.7 counts the cooldown), after a death at 0.5", CR.AttackLate(0, 0, 0.4, 0.7, 0.5) == true)
	check("AttackLate: the cooldown is counted once: ready at 0.6, landing at 0.9, before a death at 1.0", CR.AttackLate(0, 0, 0.6, 0.9, 1.0) == false)
	check("AttackLate: due at 1, the hit at 1.3 beats a death at 2", CR.AttackLate(1, 0, 0, 0.3, 2) == false)
	check("AttackLate: a walk of 1.5 s sets the swing", CR.AttackLate(0, 1.5, 0, 0.3, 1.7) == true)
	check("AttackCannot: the row's covered refusal leaves the creep to the cast", CR.AttackCannot("covered", nil, true, false) == "covered")
	check("AttackCannot: the hero acting, a teammate's hit, a tried creep: not the cast's", CR.AttackCannot("acting", nil, true, true) == nil
		and CR.AttackCannot("mate", nil, true, true) == nil and CR.AttackCannot("tried", nil, true, true) == nil)
	check("AttackCannot: a creep the row does not hit, the cell rule refusing it as unsafe", CR.AttackCannot("kind", "race", true, false) == "race")
	check("AttackCannot: a creep the row does not hit, refused for another target (given): not the cast's", CR.AttackCannot("kind", "given", true, true) == nil)
	check("AttackCannot: not yet due and the hero cannot be in range in time", CR.AttackCannot("early", nil, false, false) == "notime")
	check("AttackCannot: not yet due, the attack can still take it", CR.AttackCannot("early", nil, true, false) == nil)
end

finish()
