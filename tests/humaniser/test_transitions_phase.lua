-- Per-bot laning end (task 12, Task 8).
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode, Tower = dota.Lane, dota.BotMode, dota.Tower

local FRONT = Vector(0, -5000)
local CAMP = Vector(-1600, -6200)
local FAR = Vector(0, 5000)
local PHASE = "transitions:phase"

local function hero(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot ~= false, loc = o.loc or FRONT, level = o.level })
	u.lane, u.pos = o.lane, o.pos
	return u
end

local function hide(u) u.hiddenFrom = setmetatable({}, { __index = function() return true end }) end

-- Radiant bottom lane: core pid 1, support pid 5, a human mid so the team counts as an ally of a human.
-- opts.humanCore / opts.humanSupport make that laner a human.
local function world(opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true }, { skill = opts.skill or 0.5, transitions = opts.transitions or { Enable = true }, telemetry = opts.telemetry })
	T = opts.T or 100
	CURRENT_TEAM = 2
	LANING = true
	SPAWNERS = { { team = 2, type = "small", location = CAMP, min = Vector(CAMP.x - 150, CAMP.y - 150, 0), max = Vector(CAMP.x + 150, CAMP.y + 150, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	local w = { H = H, P = H.Transitions.Phase, said = {} }
	w.mid = hero({ pid = 2, bot = false, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	w.core = hero({ pid = 1, bot = not opts.humanCore, pos = 1, lane = Lane.Bot })
	w.sup = hero({ pid = 5, bot = not opts.humanSupport, pos = 5, lane = Lane.Bot })
	w.sup.ActionImmediate_Ping = function() end
	w.core.ActionImmediate_Ping = function() end
	H.Orders.SetAnnouncer(function(_, key) table.insert(w.said, key) end)
	H.Profile.SampleDelay = function() return 0 end
	return w
end

local function count(list, key)
	local n = 0
	for _, v in ipairs(list) do if v == key then n = n + 1 end end
	return n
end

-- The unit dies and respawns across two ticks, as the bot's own Tick would see it.
local function die(w, u, at)
	T = at - 1
	w.P.Tick(u)
	T = at
	u.alive = false
	w.P.Tick(u)
	T = at + 1
	u.alive = true
	w.P.Tick(u)
end

local function tick(w, u, at)
	T = at
	w.P.Tick(u)
end

local function claim(w, u, source) return w.H.Intent.ClaimAge(u, source, BotMode.Laning) end

-- IsLaningFor
do
	local w = world()
	check("laning by default", w.P.IsLaningFor(w.core) and w.P.IsLaningFor(w.sup))
	TOWERS_W[2][Tower.Bot1] = nil
	check("our T1 dead: not laning", not w.P.IsLaningFor(w.core))
	TOWERS_W = MakeLaneTowers()
	TOWERS_W[3][Tower.Bot1] = nil
	check("their T1 dead: not laning", not w.P.IsLaningFor(w.core))
	TOWERS_W = MakeLaneTowers()
	TOWERS_W[3][Tower.Top1] = nil
	check("a T1 in another lane does not matter", w.P.IsLaningFor(w.core))
end

do
	local w = world({ T = 420 })
	w.sup.level = 7
	w.sup.items = { [0] = { name = "item_smoke_of_deceit" } }
	check("pos 5 level 7 at 7:00 with smoke: not laning", not w.P.IsLaningFor(w.sup))
	w.sup.level = 5
	check("pos 5 level 5: laning", w.P.IsLaningFor(w.sup))
	w.sup.level = 7
	w.sup.items = {}
	check("level 7 without a smoke or order: laning", w.P.IsLaningFor(w.sup))
	w.sup.items = { [0] = { name = "item_smoke_of_deceit" } }
	T = 500
	check("smoke after the window: laning", w.P.IsLaningFor(w.sup))
	T = 420
	w.core.level = 7
	w.core.items = { [0] = { name = "item_smoke_of_deceit" } }
	check("a core with a smoke is unaffected", w.P.IsLaningFor(w.core))
end

do
	local w = world()
	w.core.items = { [0] = { name = "item_maelstrom" } }
	check("core with Maelstrom and a clear jungle: not laning", not w.P.IsLaningFor(w.core))
	w = world()
	w.core.items = { [0] = { name = "item_maelstrom" } }
	local e = hero({ pid = 10, team = 3, loc = Vector(CAMP.x + 500, CAMP.y) })
	hide(e)
	LAST_SEEN[10] = { location = Vector(CAMP.x + 500, CAMP.y), time_since_seen = 2 }
	check("enemy seen 2 s ago near the camp: still laning", w.P.IsLaningFor(w.core))
	w = world()
	w.core.items = { [0] = { name = "item_maelstrom" } }
	e = hero({ pid = 10, team = 3, loc = Vector(CAMP.x + 500, CAMP.y) })
	hide(e)
	LAST_SEEN[10] = { location = Vector(CAMP.x + 500, CAMP.y), time_since_seen = 4 }
	check("enemy last seen 4 s ago: the jungle is clear", not w.P.IsLaningFor(w.core))
	w = world()
	w.core.items = { [0] = { name = "item_maelstrom" } }
	e = hero({ pid = 10, team = 3, loc = Vector(CAMP.x + 3500, CAMP.y) })
	check("enemy 3500 from the camp: the jungle is clear", not w.P.IsLaningFor(w.core))
	w = world()
	w.core.items = { [0] = { name = "item_quelling_blade" } }
	check("a non-farm item does not end laning", w.P.IsLaningFor(w.core))
	w = world()
	w.sup.items = { [0] = { name = "item_maelstrom" } }
	check("a support with a farm item is unaffected", w.P.IsLaningFor(w.sup))
end

do
	local w = world()
	LANING = false
	check("after the helper turns false: not laning", not w.P.IsLaningFor(w.core))
end

-- LaningHeld: deaths and levels never end the hold
do
	-- A core two levels under its lane opponent and dead twice in a minute stays held, and is not sent to farm.
	local w = world()
	hero({ pid = 10, team = 3, level = 5 })
	w.core.level = 3
	tick(w, w.core, 20)
	check("precondition: held from the first laning read", w.P.LaningHeld(w.core))
	die(w, w.core, 30)
	die(w, w.core, 60)
	tick(w, w.core, 100)
	T = 102
	check("two levels behind and twice dead: still held", w.P.LaningHeld(w.core))
	check("... and not released to farm", not w.P.FarmAllowedInLaning(w.core))
	TOWERS_W[2][Tower.Bot1].alive = false
	T = 104
	check("contrast: its tier-1 falls, the hold ends", not w.P.LaningHeld(w.core))
	TOWERS_W = MakeLaneTowers()
end

do
	local w = world()
	w.core.items = { [0] = { name = "item_maelstrom" } }
	tick(w, w.core, 100)
	local cap = w.H.Intent.Resolve(w.core, BotMode.Laning, 0.9)
	check("the cap lowers the Laning desire", cap < 0.9 and cap <= 0.3 + 1e-6, cap)
	w = world({ transitions = { Enable = false } })
	w.core.items = { [0] = { name = "item_maelstrom" } }
	tick(w, w.core, 100)
	check("kill switch: farm not allowed, no claim, no chat", w.P.FarmAllowedInLaning(w.core) == false and claim(w, w.core, PHASE) == nil and #w.said == 0)
	check("kill switch: Laning desire untouched", w.H.Intent.Resolve(w.core, BotMode.Laning, 0.9) == 0.9)
end

-- Response: laning ended by phase
do
	local res = {}
	for _, on in ipairs({ true, false }) do
		local w = world({ transitions = { Enable = true, Phase = on } })
		w.core.items = { [0] = { name = "item_maelstrom" } }
		tick(w, w.core, 100)
		res[on] = { allowed = w.P.FarmAllowedInLaning(w.core), cap = claim(w, w.core, PHASE) }
	end
	check("Maelstrom core with a clear jungle may farm", res[true].allowed == true and res[true].cap ~= nil)
	check("Phase off: not allowed and no cap", res[false].allowed == false and res[false].cap == nil)
	local jw = world()
	jw.core.items = { [0] = { name = "item_maelstrom" } }
	tick(jw, jw.core, 100)
	tick(jw, jw.core, 101)
	tick(jw, jw.core, 160)
	check("a core leaving by phase end says going jungle once", count(jw.said, "say_going_jungle") == 1, count(jw.said, "say_going_jungle"))
	jw = world({ transitions = { Enable = true, Phase = false } })
	jw.core.items = { [0] = { name = "item_maelstrom" } }
	tick(jw, jw.core, 100)
	check("Phase off: no jungle line", count(jw.said, "say_going_jungle") == 0)
	local w = world()
	w.core.items = { [0] = { name = "item_maelstrom" } }
	tick(w, w.core, 100)
	check("claim released once laning resumes", claim(w, w.core, PHASE) ~= nil)
	w.core.items = {}
	tick(w, w.core, 101)
	check("... the core no longer farms", w.P.FarmAllowedInLaning(w.core) == false and claim(w, w.core, PHASE) == nil)
	LANING = false
	w.core.items = { [0] = { name = "item_maelstrom" } }
	tick(w, w.core, 102)
	check("no cap once the laning phase is over", claim(w, w.core, PHASE) == nil)
end

do
	-- Through the facade, as the bot's Tick calls it.
	local w = world()
	w.core.items = { [0] = { name = "item_maelstrom" } }
	T = 100
	w.H.Transitions.Tick(w.core)
	check("facade Tick drives the phase claim", claim(w, w.core, PHASE) ~= nil and w.H.Transitions.FarmAllowedInLaning(w.core) == true)
	check("overlay reports the laning end", w.H.Transitions.Overlay(w.core):find("^phase: post ") ~= nil)
	check("overlay of a bot still laning", w.H.Transitions.Overlay(w.sup):find("^phase: laning ") ~= nil)
end


-- tr_* telemetry: captured lines for one event name.
local function capture(w)
	local lines = {}
	w.H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	return function(ev)
		local out = {}
		for _, l in ipairs(lines) do if l:find("ev=" .. ev .. " ", 1, true) then table.insert(out, l) end end
		return out
	end
end
local function has(l, ...)
	for _, s in ipairs({ ... }) do if not (l or ""):find(s, 1, true) then return false end end
	return true
end

do
	local w = world({ telemetry = { Enable = true } })
	local ev = capture(w)
	tick(w, w.core, 100)
	LANING = false
	tick(w, w.core, 101)
	local laning = ev("tr_laning")
	check("tr_laning: the end of laning says why", has(laning[#laning], "pid=1", "laning=0", "why=phase"), laning[#laning])
end


do
	local w = world({ telemetry = { Enable = true } })
	local ev = capture(w)
	tick(w, w.core, 100)
	tick(w, w.core, 101)
	check("tr_laning: nothing while the bot keeps laning", #ev("tr_laning") == 0, #ev("tr_laning"))
	TOWERS_W[2][Tower.Bot1].alive = false
	tick(w, w.core, 102)
	tick(w, w.core, 103)
	local l = ev("tr_laning")
	check("tr_laning: a fallen T1 ends laning once, with why=tower", #l == 1 and has(l[1], "laning=0", "why=tower"), l[1])
end

finish()
