-- Per-bot laning end and lost-lane response (task 12, Task 8).
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode, Tower = dota.Lane, dota.BotMode, dota.Tower

local FRONT = Vector(0, -5000)
local CAMP = Vector(-1600, -6200)
local FAR = Vector(0, 5000)
local PHASE, LOST = "transitions:phase", "transitions:lostlane"

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
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = opts.transitions or { Enable = true } })
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

-- LaneLostPure
do
	local P = world().P
	local function lost(d, lh, gap) return P.LaneLostPure({ deathsInWindow = d, lhPerMin = lh, expectedLhPerMin = 5, levelGap = gap }) end
	local l, r = lost(2, 5, 0)
	check("2 deaths: lost by deaths", l == true and r == "deaths", r)
	check("1 death: not lost", lost(1, 5, 0) == false)
	l, r = lost(0, 1.75, 0)
	check("LH ratio 0.35: lasthits", l == true and r == "lasthits", r)
	check("LH ratio 0.45: not lost", lost(0, 2.25, 0) == false)
	l, r = lost(0, 5, 2)
	check("level gap 2: levels", l == true and r == "levels", r)
	check("level gap 1: not lost", lost(0, 5, 1) == false)
end

-- Adapter inputs
do
	local w = world()
	die(w, w.core, 30)
	die(w, w.core, 60)
	T = 90
	check("two deaths inside the window: lost", w.P.LaneLost(w.core) == true)
	T = 310
	check("deaths older than the window are dropped", w.P.LaneLost(w.core) == false)
end

do
	-- Contrast: the same one death plus a second only counts while the second is inside the window.
	local w = world()
	die(w, w.core, 30)
	die(w, w.core, 250)
	T = 260
	check("deaths 220 s apart are both inside a 240 s window", w.P.LaneLost(w.core) == true)
	T = 275
	check("the older death drops out", w.P.LaneLost(w.core) == false)
end

do
	local w = world()
	tick(w, w.core, 70)
	w.core.lh = 2
	T = 190
	local l, r = w.P.LaneLost(w.core)
	check("1 LH/min against an expected 5: lost by lasthits", l == true and r == "lasthits", r)
	w.core.lh = 10
	check("5 LH/min: not lost", w.P.LaneLost(w.core) == false)
	w = world()
	tick(w, w.core, 70)
	T = 110
	check("a 40 s span is too short to judge last hits", w.P.LaneLost(w.core) == false)
	w = world()
	tick(w, w.sup, 70)
	T = 190
	check("a support is not judged on last hits", w.P.LaneLost(w.sup) == false)
end

do
	-- Ticks start before the horn; the core then last-hits normally (about 4 a minute from 0:30).
	local w = world()
	local lostEver = false
	T = -60
	w.P.Tick(w.core)
	for t = 0, 180, 10 do
		T = t
		w.core.lh = t < 30 and 0 or math.floor((t - 30) / 60 * 4)
		w.P.Tick(w.core)
		if t == 30 or t == 120 or t == 180 then lostEver = lostEver or w.P.LaneLost(w.core) end
	end
	check("a core last-hitting normally is never lost, pre-horn ticks included", lostEver == false)
	w = world()
	T = -60
	w.P.Tick(w.core)
	for t = 0, 180, 10 do
		T = t
		w.core.lh = 0
		w.P.Tick(w.core)
	end
	check("contrast: a core with no last hits by 3:00 is lost", w.P.LaneLost(w.core) == true)
end

do
	local w = world()
	local e = hero({ pid = 10, team = 3, level = 5 })
	w.core.level = 3
	check("visible opponent 2 levels up: lost by levels", select(2, w.P.LaneLost(w.core)) == "levels")
	w.core.level = 4
	check("1 level up: not lost", w.P.LaneLost(w.core) == false)
	-- Last-known level: noted while visible, used once the enemy leaves sight.
	w = world()
	e = hero({ pid = 10, team = 3, level = 5 })
	w.core.level = 3
	tick(w, w.core, 100)
	hide(e)
	LAST_SEEN[10] = { location = FRONT, time_since_seen = 6 }
	e.level = 99
	w.H.Lane.LaneState.ResetCache()
	T = 110
	check("an unseen opponent counts at its last seen level", select(2, w.P.LaneLost(w.core)) == "levels")
	w = world()
	e = hero({ pid = 10, team = 3, level = 9 })
	hide(e)
	LAST_SEEN[10] = { location = FRONT, time_since_seen = 6 }
	w.core.level = 3
	check("an opponent never seen has no known level", w.P.LaneLost(w.core) == false)
end

do
	-- Supports are judged by deaths only: a pos 5 two levels under the enemy offlaner, beside its level 4 core, at 3:00.
	local w = world({ T = 180 })
	hero({ pid = 10, team = 3, level = 4 })
	w.sup.level, w.core.level = 2, 4
	check("pos 5 level 2, core level 4, enemy offlaner level 4 at 3:00: not lost", w.P.LaneLost(w.sup) == false, select(2, w.P.LaneLost(w.sup)))
	w.core.level = 2
	check("contrast: a level 2 core against the level 4 offlaner is lost by levels", select(2, w.P.LaneLost(w.core)) == "levels")
end

do
	-- Deaths while farming away from the lane do not count against the lane.
	local w = world()
	w.core.items = { [0] = { name = "item_maelstrom" } }
	tick(w, w.core, 20)
	die(w, w.core, 30)
	die(w, w.core, 60)
	w.core.items = {}
	tick(w, w.core, 80)
	T = 90
	check("deaths while not laning do not read as lost", w.P.LaneLost(w.core) == false)
	w = world()
	tick(w, w.core, 20)
	die(w, w.core, 30)
	die(w, w.core, 60)
	T = 90
	check("contrast: the same deaths while laning do", w.P.LaneLost(w.core) == true)
end

-- Response: a lost core
do
	local res = {}
	for _, on in ipairs({ true, false }) do
		local w = world({ transitions = { Enable = true, LostLane = on } })
		die(w, w.core, 30)
		die(w, w.core, 60)
		tick(w, w.core, 100)
		res[on] = { allowed = w.P.FarmAllowedInLaning(w.core), cap = claim(w, w.core, LOST), said = count(w.said, "say_going_jungle") }
		tick(w, w.core, 140)
		tick(w, w.core, 141)
		res[on].saidAfter = count(w.said, "say_going_jungle")
	end
	check("enabled: a lost core may farm in laning", res[true].allowed == true)
	check("enabled: the Laning cap is posted", res[true].cap ~= nil)
	check("enabled: says going jungle, once", res[true].said == 1 and res[true].saidAfter == 1, res[true].saidAfter)
	check("LostLane off: the core may not farm", res[false].allowed == false)
	check("LostLane off: no cap, no chat", res[false].cap == nil and res[false].said == 0)
end

do
	local w = world()
	die(w, w.core, 30)
	die(w, w.core, 60)
	tick(w, w.core, 100)
	local cap = w.H.Intent.Resolve(w.core, BotMode.Laning, 0.9)
	check("the cap lowers the Laning desire", cap < 0.9 and cap <= 0.3 + 1e-6, cap)
	w = world({ transitions = { Enable = false } })
	die(w, w.core, 30)
	die(w, w.core, 60)
	tick(w, w.core, 100)
	check("kill switch: farm not allowed, no claim, no chat", w.P.FarmAllowedInLaning(w.core) == false and claim(w, w.core, LOST) == nil and #w.said == 0)
	check("kill switch: Laning desire untouched", w.H.Intent.Resolve(w.core, BotMode.Laning, 0.9) == 0.9)
end

do
	-- A lost support is capped but never farms through the core's hook.
	local w = world()
	die(w, w.sup, 30)
	die(w, w.sup, 60)
	tick(w, w.sup, 100)
	check("lost support: Laning capped", claim(w, w.sup, LOST) ~= nil)
	check("lost support: farm hook stays false", w.P.FarmAllowedInLaning(w.sup) == false)
	check("lost support: no jungle line", count(w.said, "say_going_jungle") == 0)
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

-- Human partner
do
	local function setup(opts)
		local w = world(opts)
		die(w, w.sup, 90)
		die(w, w.sup, 95)
		return w
	end

	local w = setup({ humanCore = true })
	tick(w, w.sup, 100)
	check("human core: one suggestion", count(w.said, "say_lane_lost_roam") == 1, count(w.said, "say_lane_lost_roam"))
	check("human core: no cap yet", claim(w, w.sup, LOST) == nil)
	tick(w, w.sup, 130)
	check("30 s of silence: still no cap and no second line", claim(w, w.sup, LOST) == nil and count(w.said, "say_lane_lost_roam") == 1)
	tick(w, w.sup, 154)
	check("59 s after the first line: no second", count(w.said, "say_lane_lost_roam") == 1)
	tick(w, w.sup, 156)
	check("60 s after the first: a second suggestion", count(w.said, "say_lane_lost_roam") == 2, count(w.said, "say_lane_lost_roam"))
	check("... still no cap", claim(w, w.sup, LOST) == nil)
	w.core.loc = FAR
	tick(w, w.sup, 165)
	tick(w, w.sup, 170)
	check("human absent for 5 s: no cap", claim(w, w.sup, LOST) == nil)
	tick(w, w.sup, 175.5)
	check("human absent for 10 s: the cap starts", claim(w, w.sup, LOST) ~= nil)
	tick(w, w.sup, 190)
	check("the cap stays and no further line", claim(w, w.sup, LOST) ~= nil and count(w.said, "say_lane_lost_roam") == 2)

	-- Absence timing restarts when the human comes back.
	w = setup({ humanCore = true })
	tick(w, w.sup, 100)
	w.core.loc = FAR
	tick(w, w.sup, 101)
	tick(w, w.sup, 106)
	w.core.loc = FRONT
	tick(w, w.sup, 108)
	w.core.loc = FAR
	tick(w, w.sup, 109)
	tick(w, w.sup, 115)
	check("an interrupted absence restarts the 10 s", claim(w, w.sup, LOST) == nil)
	tick(w, w.sup, 120)
	check("... and counts again from the new start", claim(w, w.sup, LOST) ~= nil)

	-- A ping near the bot answers the suggestion.
	w = setup({ humanCore = true })
	tick(w, w.sup, 100)
	-- Pings can also become orders; hide those so only the ping trigger is under test.
	w.H.Orders.GetFor = function() return nil end
	w.core.GetMostRecentPing = function() return { time = 105, location = Vector(100, -4900), normal_ping = true } end
	T = 106
	w.H.Pings.Scan(2)
	tick(w, w.sup, 106)
	check("a human ping within 1500 of the bot starts the cap", claim(w, w.sup, LOST) ~= nil)

	w = setup({ humanCore = true })
	tick(w, w.sup, 100)
	w.H.Orders.GetFor = function() return nil end
	w.core.GetMostRecentPing = function() return { time = 105, location = Vector(1600, -5000), normal_ping = true } end
	T = 106
	w.H.Pings.Scan(2)
	tick(w, w.sup, 106)
	check("a ping 1600 from the bot does not start the cap", claim(w, w.sup, LOST) == nil)

	-- A ping from before the suggestion does not.
	w = setup({ humanCore = true })
	w.core.GetMostRecentPing = function() return { time = 80, location = Vector(100, -4900), normal_ping = true } end
	T = 90
	w.H.Pings.Scan(2)
	tick(w, w.sup, 100)
	tick(w, w.sup, 105)
	check("a ping before the suggestion is not an answer", claim(w, w.sup, LOST) == nil)

	-- An accepted order answers it.
	w = setup({ humanCore = true })
	tick(w, w.sup, 100)
	w.H.Orders.Post(2, { type = "DEFEND", sourceKey = "d", issuerPID = 1, location = Vector(0, 0), lane = Lane.Mid, radius = 3000, duration = 30, maxResponders = 5 })
	tick(w, w.sup, 101)
	check("an accepted order starts the cap", claim(w, w.sup, LOST) ~= nil)

	-- Contrast: with a bot partner there is no suggestion and the cap is immediate.
	w = setup()
	tick(w, w.sup, 100)
	check("bot partner: cap straight away", claim(w, w.sup, LOST) ~= nil)
	check("bot partner: no suggestion", count(w.said, "say_lane_lost_roam") == 0)

	-- A bot core with a human support partner waits the same way.
	w = world({ humanSupport = true })
	die(w, w.core, 90)
	die(w, w.core, 95)
	tick(w, w.core, 100)
	check("bot core, human support: suggestion and no farm", count(w.said, "say_lane_lost_roam") == 1 and not w.P.FarmAllowedInLaning(w.core) and claim(w, w.core, LOST) == nil)
	check("... and no jungle line while waiting", count(w.said, "say_going_jungle") == 0)
	w.sup.loc = FAR
	tick(w, w.sup, 101)
	tick(w, w.core, 101)
	tick(w, w.core, 112)
	check("... the absent human support releases the core", w.P.FarmAllowedInLaning(w.core) and claim(w, w.core, LOST) ~= nil)
	check("... and the core announces the jungle once", count(w.said, "say_going_jungle") == 1)

	-- Kill switch on the same scenario.
	w = world({ humanCore = true, transitions = { Enable = false } })
	die(w, w.sup, 90)
	die(w, w.sup, 95)
	tick(w, w.sup, 100)
	check("kill switch: no suggestion, no cap", #w.said == 0 and claim(w, w.sup, LOST) == nil)
end

do
	-- The lost state clears when the deaths age out, and the human flow starts over.
	local w = world({ humanCore = true })
	die(w, w.sup, 90)
	die(w, w.sup, 95)
	w.core.loc = FAR
	tick(w, w.sup, 100)
	tick(w, w.sup, 111)
	check("cap started by absence", claim(w, w.sup, LOST) ~= nil)
	tick(w, w.sup, 400)
	check("the lost response is latched for the rest of laning: deaths aged out, the cap stays", claim(w, w.sup, LOST) ~= nil)
	check("... although the lane no longer reads lost", w.P.LaneLost(w.sup) == false)
	LANING = false
	tick(w, w.sup, 401)
	check("... and goes when laning ends", claim(w, w.sup, LOST) == nil)
end

do
	-- A core lost on last hits at 2:40 farms neutrals at 8 a minute: its jungle last hits must not send it back to the lane.
	local w = world({ T = 60 })
	for t = 60, 160, 5 do
		w.core.lh = 0
		tick(w, w.core, t)
	end
	check("precondition: lost by last hits at 2:40, released to farm", w.P.FarmAllowedInLaning(w.core) and select(2, w.P.LaneLost(w.core)) == "lasthits")
	check("precondition: one jungle line", count(w.said, "say_going_jungle") == 1)
	w.core.loc = CAMP
	for t = 165, 260, 5 do
		w.core.lh = math.floor((t - 160) / 60 * 8)
		tick(w, w.core, t)
	end
	check("the jungle farm lifts the last-hit rate: the lane no longer reads lost", w.P.LaneLost(w.core) == false)
	check("still released to farm at 4:20", w.P.FarmAllowedInLaning(w.core))
	check("still one jungle line", count(w.said, "say_going_jungle") == 1, count(w.said, "say_going_jungle"))
end

finish()
