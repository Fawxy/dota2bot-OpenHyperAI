-- Reaction to enemy TPs into the lane (task 12, Task 6).
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local FRONT = Vector(0, -5000)
local SOURCE = "transitions:caution"

local function hero(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot ~= false, loc = o.loc or FRONT })
	u.lane, u.pos = o.lane, o.pos
	return u
end

local function world(opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true }, { skill = opts.skill or 1, transitions = opts.transitions or { Enable = true } })
	T = 300
	CURRENT_TEAM = 2
	local w = { H = H, TP = H.Transitions.Teleports, C = H.Transitions.Caution }
	w.mid = hero({ pid = 2, bot = false, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	w.core = hero({ pid = 1, pos = 1, lane = Lane.Bot })
	w.sup = hero({ pid = 5, pos = 5, lane = Lane.Bot })
	w.foe = MakeUnit({ pid = 10, team = 3, loc = Vector(5000, 5000) })
	w.ally = MakeUnit({ pid = 6, team = 2, loc = Vector(-6000, -6000) })
	H.Profile.SampleDelay = function() return opts.delay or 0 end
	return w
end

local function snap(w, u) return w.H.Lane.LaneState.ForBot(u) end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function tower(w) return w.H.Lane.LaneState.ForBot(w.core) and GetLocationAlongLane(Lane.Bot, w.H.Lane.Camps.ToAbsAmount(2, snap(w, w.core).ourTowerAmount)) end

do
	local w = world()
	TELEPORTS = { { playerid = 6, location = FRONT, time_remaining = 3 } }
	check("ally TPs are ignored", #w.TP.EnemyTps(2) == 0)
	TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 3 } }
	T = 301
	check("enemy TPs are listed", #w.TP.EnemyTps(2) == 1)
end

do
	local w = world()
	local s = snap(w, w.core)
	TELEPORTS = { { playerid = 10, location = tower(w), time_remaining = 3 } }
	check("TP to our T1 is incoming to lane", w.TP.IncomingToLane(w.core, s) ~= nil)
	w = world()
	TELEPORTS = { { playerid = 10, location = Vector(3000, 3000), time_remaining = 3 } }
	check("a TP 3000 away is not", w.TP.IncomingToLane(w.core, snap(w, w.core)) == nil)
end

do
	local w = world({ skill = 0.5 })
	TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 4 } }
	local tp = w.TP.EnemyTps(2)[1]
	check("skill 0.5 backs off", w.TP.Response(w.core, tp) == "back")
	STRONGER = true
	check("skill 0.5 backs off even when stronger", w.TP.Response(w.core, tp) == "back")
	STRONGER = false
end

do
	-- Contrast: the same TP, delay and time with Teleports on and off.
	local lvl = {}
	for _, on in ipairs({ true, false }) do
		local w = world({ skill = 0.5, delay = 1.0, transitions = { Enable = true, Teleports = on, Caution = true } })
		TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 6 } }
		w.TP.Tick(w.core)
		lvl[on] = { before = w.C.Level(w.core) }
		T = 300.6
		TELEPORTS[1].time_remaining = 5.4
		lvl[on].mid = w.C.Level(w.core)
		T = 301.2
		TELEPORTS[1].time_remaining = 4.8
		w.TP.Tick(w.core)
		lvl[on].after = w.C.Level(w.core)
		w.H.Transitions.Tick(w.core)
		lvl[on].claim = w.H.Intent.ClaimAge(w.core, SOURCE, BotMode.Retreat) ~= nil
	end
	check("low skill: nothing before the notice delay", lvl[true].before == 0 and lvl[true].mid == 0)
	check("low skill backs off: level 1 after the notice delay", near(lvl[true].after, 1), lvl[true].after)
	check("low skill backing off posts caution claims", lvl[true].claim)
	check("Teleports off: no level on the same scenario", lvl[false].after == 0, lvl[false].after)
	check("Teleports off: no claims", not lvl[false].claim)
end

do
	local w = world({ skill = 0.9 })
	STRONGER = true
	TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 5 } }
	w.TP.Tick(w.core)
	local tp = w.TP.EnemyTps(2)[1]
	check("high skill and stronger sets up", w.TP.Response(w.core, tp) == "setup")
	local loc = Vector(0, -5000)
	local moved = w.H.Lane.AdjustPosition(w.core, loc)
	local tw = tower(w)
	local d = dist(FRONT, tw)
	local expect = Vector(FRONT.x + (tw.x - FRONT.x) / d * 600, FRONT.y + (tw.y - FRONT.y) / d * 600)
	check("setup point is TpSetupDistance from the TP toward our tower", dist(moved, expect) < 50, dist(moved, expect))
	check("setup is position-only: no level", w.C.Level(w.core) == 0)
	w.H.Transitions.Tick(w.core)
	check("setup posts no retreat claim", w.H.Intent.ClaimAge(w.core, SOURCE, BotMode.Retreat) == nil)
	STRONGER = true
	check("setup does not suppress trades", not w.C.SuppressTrades(w.core))

	STRONGER = false
	T = 300.6
	TELEPORTS[1].time_remaining = 4.4
	w.TP.Tick(w.core)
	check("no longer stronger: switches to backing off", near(w.C.Level(w.core), 1))
	check("backing off drops the setup point", w.C.AdjustPosition(w.core, loc) ~= moved)

	-- Where OHA does not own laning the position is left alone; the level claims still apply.
	local other = world({ skill = 0.9 })
	other.mid.bot = true
	STRONGER = true
	TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 5 } }
	T = 300
	other.TP.Tick(other.core)
	check("setup: position unchanged where OHA does not own laning", other.C.AdjustPosition(other.core, loc) == loc)
end

do
	local w = world({ skill = 0.9, transitions = { Enable = true, Teleports = false } })
	STRONGER = true
	TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 5 } }
	w.TP.Tick(w.core)
	check("Teleports off: no setup on the same scenario", w.C.AdjustPosition(w.core, Vector(0, -5000)).x == 0)
	check("Teleports off: GetIncomingTeleports never read", TELEPORT_READS == 0, TELEPORT_READS)
	w.H.Transitions.Busy.LaneCanSpare(w.core, false)
	check("Teleports off: busy probe does not read either", TELEPORT_READS == 0, TELEPORT_READS)
	w = world({ transitions = { Enable = false } })
	w.H.Transitions.Tick(w.core)
	w.TP.Tick(w.core)
	check("Enable off: no reads", TELEPORT_READS == 0, TELEPORT_READS)
	STRONGER = false
end

do
	local w = world({ skill = 0.5 })
	TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 4 } }
	w.TP.Tick(w.core)
	check("reaction active while the TP is incoming", near(w.C.Level(w.core), 1))
	TELEPORTS = {}
	T = 300 + 4 + 2 + 0.5
	w.TP.Tick(w.core)
	check("reaction ends after the TP lands", w.C.Level(w.core) == 0, w.C.Level(w.core))
end

do
	local w = world({ skill = 0.5 })
	TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 4 } }
	TELEPORT_READS = 0
	for i = 0, 10 do
		T = 300 + i * 0.02
		w.TP.EnemyTps(2)
	end
	check("one read within 0.25 s", TELEPORT_READS == 1, TELEPORT_READS)
	T = 300.3
	w.TP.EnemyTps(2)
	check("a second read after 0.25 s", TELEPORT_READS == 2, TELEPORT_READS)
end

do
	local w = world()
	STRONGER = false
	TELEPORTS = {}
	TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 4 } }
	T = 310
	local spare, why = w.H.Transitions.Busy.LaneCanSpare(w.core, false)
	check("an incoming enemy TP stops the lane sparing a bot", spare == false and why == "enemy tp", why)
end

finish()
