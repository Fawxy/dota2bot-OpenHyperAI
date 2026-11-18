-- The laning hold (Phase.LaningHeld): one read per hero, from its first laning read to the clock or a fallen tier-1.
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, Tower = dota.Lane, dota.Tower

local FRONT = Vector(0, -5000)
local CAMP = Vector(-1600, -6200)

local function hero(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot ~= false, loc = o.loc or FRONT, level = o.level })
	u.lane, u.pos = o.lane, o.pos
	return u
end

-- Radiant bottom lane: core pid 1, support pid 5, a human mid so the team counts as an ally of a human.
local function world(opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = { Enable = true }, telemetry = opts.telemetry })
	T = opts.T or 100
	CURRENT_TEAM = 2
	LANING = true
	TOWERS_W = MakeLaneTowers()
	SPAWNERS = { { team = 2, type = "small", location = CAMP, min = Vector(CAMP.x - 150, CAMP.y - 150, 0), max = Vector(CAMP.x + 150, CAMP.y + 150, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	local w = { H = H, P = H.Transitions.Phase }
	w.mid = hero({ pid = 2, bot = false, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	w.core = hero({ pid = 1, pos = 1, lane = Lane.Bot })
	w.sup = hero({ pid = 5, pos = 5, lane = Lane.Bot })
	H.Profile.SampleDelay = function() return 0 end
	return w
end

local function capture(w)
	local lines = {}
	w.H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	return function()
		local out = {}
		for _, l in ipairs(lines) do if l:find("ev=arb ", 1, true) then table.insert(out, l) end end
		return out
	end
end

local function has(l, ...)
	for _, s in ipairs({ ... }) do if not (l or ""):find(s, 1, true) then return false end end
	return true
end

-- A tier-1 of the hero's own lane ends the hold, ours or theirs; another lane's does not.
do
	local w = world()
	check("held from the first laning read", w.P.LaningHeld(w.core) and w.P.LaningHeld(w.sup))
	TOWERS_W[3][Tower.Top1] = nil
	T = 102
	check("a T1 in another lane does not end it", w.P.LaningHeld(w.core))
	TOWERS_W[2][Tower.Bot1] = nil
	T = 104
	check("our T1 of its lane falls: the hold ends", not w.P.LaningHeld(w.core))
	w = world()
	w.P.LaningHeld(w.core)
	TOWERS_W[3][Tower.Bot1].alive = false
	T = 102
	check("their T1 of its lane falls: the hold ends", not w.P.LaningHeld(w.core))
end

-- OHA's clock ends it, and once ended the hold never comes back.
do
	local w = world()
	w.P.LaningHeld(w.core)
	LANING = false
	T = 102
	check("the clock ends the hold", not w.P.LaningHeld(w.core))
	LANING = true
	T = 104
	check("the helper turning true again does not restart it", not w.P.LaningHeld(w.core))
end

-- The deleted exits (a support's smoke, a core's farm item) no longer end it.
do
	local w = world({ T = 420 })
	w.P.LaningHeld(w.core)
	w.P.LaningHeld(w.sup)
	w.sup.level = 7
	w.sup.items = { [0] = { name = "item_smoke_of_deceit" } }
	w.core.items = { [0] = { name = "item_maelstrom" } }
	T = 425
	check("a support's smoke and a core's farm item with a clear jungle: both still held", w.P.LaningHeld(w.sup) and w.P.LaningHeld(w.core))
end

-- A hero whose first read comes after its laning is over is never held.
do
	local w = world()
	LANING = false
	check("first read after the clock: not held", not w.P.LaningHeld(w.core))
end

-- The overlay reads the hold.
do
	local w = world()
	w.P.LaningHeld(w.core)
	w.P.LaningHeld(w.sup)
	TOWERS_W[2][Tower.Bot1] = nil
	T = 102
	check("overlay reports the laning end", w.H.Transitions.Overlay(w.core):find("^phase: post ") ~= nil)
	w = world()
	check("overlay of a bot still laning", w.H.Transitions.Overlay(w.sup):find("^phase: laning ") ~= nil)
end

-- The start and the end are logged once each.
do
	local w = world({ telemetry = { Enable = true } })
	local ev = capture(w)
	w.P.LaningHeld(w.core)
	T = 101.5
	w.P.LaningHeld(w.core)
	TOWERS_W[2][Tower.Bot1].alive = false
	T = 103
	w.P.LaningHeld(w.core)
	T = 105
	w.P.LaningHeld(w.core)
	local l = ev()
	check("ev=arb: one own, then one end with why=tower", #l == 2 and has(l[1], "pid=1", "ph=own") and has(l[2], "pid=1", "ph=end", "why=tower"), table.concat(l, "\n"))
end

finish()
