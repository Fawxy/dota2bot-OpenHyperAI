-- Caution for alone cores and missing enemies (task 12, Task 5).
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

-- The bottom lane front at the default amount 0.5.
local FRONT = Vector(0, -5000)
local SOURCE = "transitions:caution"

local function hero(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot ~= false, loc = o.loc or FRONT, alive = o.alive })
	u.lane, u.pos = o.lane, o.pos
	return u
end

local function hide(u) u.hiddenFrom = setmetatable({}, { __index = function() return true end }) end

-- An enemy laner: visible at the front, or unseen for `unseen` seconds with its last-seen spot there.
local function enemy(pid, o)
	o = o or {}
	local u = MakeUnit({ pid = pid, team = 3, loc = o.loc or FRONT, alive = o.alive })
	if o.unseen ~= nil then
		hide(u)
		LAST_SEEN[pid] = { location = o.loc or FRONT, time_since_seen = o.unseen }
	end
	return u
end

-- Radiant bottom lane: a bot carry and a bot pos 5 at the front; a human mid unless `noHuman`.
local function world(opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true }, { skill = opts.skill or 1, transitions = opts.transitions or { Enable = true }, telemetry = opts.telemetry })
	T = 300
	CURRENT_TEAM = 2
	local w = { H = H, C = H.Transitions.Caution, said = {} }
	w.mid = hero({ pid = 2, bot = opts.noHuman == true, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	w.core = hero({ pid = 1, pos = 1, lane = Lane.Bot })
	w.sup = hero({ pid = 5, pos = 5, lane = Lane.Bot })
	H.Orders.SetAnnouncer(function(_, key) table.insert(w.said, key) end)
	local delay = opts.delay or 0
	H.Profile.SampleDelay = function() return delay end
	return w
end

local function snap(w, u) return w.H.Lane.LaneState.ForBot(u) end

local function count(list, key)
	local n = 0
	for _, v in ipairs(list) do if v == key then n = n + 1 end end
	return n
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

do
	local C = world().C
	check("alone vs 1 enemy at skill 1 gives 0.5", near(C.CautionLevel({ alone = true, laneEnemies = 1, missing = 0, skill = 1 }), 0.5))
	check("alone vs 3 gives 1.0", near(C.CautionLevel({ alone = true, laneEnemies = 3, missing = 0, skill = 1 }), 1.0))
	check("missing at skill 0 gives 0.5", near(C.CautionLevel({ alone = false, laneEnemies = 1, missing = 1, skill = 0 }), 0.5))
	check("not alone and nobody missing gives 0", C.CautionLevel({ alone = false, laneEnemies = 2, missing = 0, skill = 1 }) == 0)
end

do
	-- The core stands 1,500 behind the front, the support at the front: apart, but the support is not far from the front.
	local w = world()
	w.core.loc = Vector(-1500, -5000)
	check("support in lane: the core is not alone", not w.C.IsAlone(w.core, snap(w, w.core)))
	w.H.Transitions.Rotation.Active = function(u) if u:GetPlayerID() == 5 then return { go = true } end end
	check("support rotating and gone from the core: the core is alone", w.C.IsAlone(w.core, snap(w, w.core)))
	w = world()
	w.H.Transitions.Rotation.Active = function(u) if u:GetPlayerID() == 5 then return { go = true } end end
	check("support rotating but still beside the core: not alone", not w.C.IsAlone(w.core, snap(w, w.core)))
end

do
	local w = world()
	w.sup.lane = Lane.Top
	enemy(10)
	check("solo vs 1 enemy laner is not alone", not w.C.IsAlone(w.core, snap(w, w.core)))
	w = world()
	w.sup.lane = Lane.Top
	enemy(10)
	enemy(11)
	check("solo vs 2 enemy laners is alone", w.C.IsAlone(w.core, snap(w, w.core)))
end

do
	local w = world()
	enemy(10, { unseen = 10, alive = false })
	check("dead enemy is not missing", w.C.Missing(w.core, snap(w, w.core), false) == 0)
	w = world()
	enemy(10, { unseen = 10 })
	check("alive enemy unseen 10 s is missing", w.C.Missing(w.core, snap(w, w.core), false) == 1)
end

do
	local w = world()
	enemy(10, { unseen = 30 })
	check("unseen 30 s is missing", w.C.Missing(w.core, snap(w, w.core), false) == 1)
	w = world()
	enemy(10, { unseen = 61 })
	check("unseen longer than MissingMaxAge (60 s) is no longer missing", w.C.Missing(w.core, snap(w, w.core), false) == 0)
end

do
	local w = world()
	enemy(10, { unseen = 5 })
	check("missing waits for the threshold: 5 s is not missing", w.C.Missing(w.core, snap(w, w.core), false) == 0)
	w = world()
	enemy(10, { unseen = 7 })
	check("missing waits for the threshold: 7 s is missing", w.C.Missing(w.core, snap(w, w.core), false) == 1)
	w = world()
	enemy(10, { unseen = 5 })
	check("an alone laner counts 5 s as missing", w.C.Missing(w.core, snap(w, w.core), true) == 1)
end

do
	local w = world({ delay = 1.0 })
	w.core.alive = false
	check("alone support: nothing before the notice delay", w.C.Level(w.sup) == 0)
	T = 301.1
	check("alone support gets caution", w.C.Level(w.sup) > 0, w.C.Level(w.sup))
end

do
	-- The same support and the same elapsed time; only whether the core is alive differs.
	local level = {}
	for _, dead in ipairs({ true, false }) do
		local w = world({ delay = 1.0 })
		w.core.alive = not dead
		w.C.Level(w.sup)
		T = 301.1
		level[dead] = w.C.Level(w.sup)
	end
	check("core dead: the support is cautious", level[true] > 0, level[true])
	check("core alive: the support is not", level[false] == 0, level[false])
end

do
	-- A duo backing off together, both 2,000 from the front: neither is alone.
	local w = world()
	w.core.loc, w.sup.loc = Vector(-2000, -5000), Vector(-2100, -5000)
	check("partner beside the bot, both far from the front: not alone", not w.C.IsAlone(w.core, snap(w, w.core)))
	w = world()
	w.sup.loc = Vector(-2000, -5000)
	check("partner far from the front and from the bot: alone", w.C.IsAlone(w.core, snap(w, w.core)))
end

do
	local w = world({ delay = 1.0 })
	enemy(10, { unseen = 7 })
	check("notice delay: 0 when first seen missing", w.C.Level(w.core) == 0)
	T = 300.5
	check("notice delay holds the old level at +0.5 s", w.C.Level(w.core) == 0, w.C.Level(w.core))
	T = 301.1
	check("notice delay: the new level applies at +1.1 s", w.C.Level(w.core) > 0, w.C.Level(w.core))
	check("a cautious bot reads as cautious to the lane plan", w.H.Lane.Hooks.IsCautious(w.core))
end

do
	local P = world().H.Lane.LanePlan
	local base = { skill = 1, laneScore = -1, eqPos = 0, stronger = false, enemyLaners = 0 }
	local function with(t) local r = {} for k, v in pairs(base) do r[k] = v end for k, v in pairs(t) do r[k] = v end return r end
	check("rotating core shoves", P.PickCorePlan(with({ rotating = true, cautious = false })) == "SHOVE")
	check("cautious core never shoves while rotating", P.PickCorePlan(with({ rotating = true, cautious = true })) ~= "SHOVE")
	check("empty lane: a core shoves", P.PickCorePlan(with({ rotating = false, cautious = false })) == "SHOVE")
	check("empty lane: a cautious core does not shove", P.PickCorePlan(with({ rotating = false, cautious = true })) ~= "SHOVE")
end

do
	local loc = Vector(0, -5000)
	local w = world()
	enemy(10, { unseen = 7 })
	w.C.Level(w.core)
	T = 300.6
	local level = w.C.Level(w.core)
	local moved = w.H.Lane.AdjustPosition(w.core, loc)
	check("cautious laner (precondition): level 1 at skill 1", near(level, 1), level)
	check("cautious laner steps back by OffsetMax", math.abs(dist(moved, loc) - 300) < 1e-6, dist(moved, loc))
	check("the step is toward our tower", moved.x < loc.x and math.abs(moved.y - loc.y) < 1e-6, moved.x)

	w = world({ noHuman = true })
	enemy(10, { unseen = 7 })
	w.C.Level(w.core)
	T = 300.6
	check("not-OHA laner (precondition): cautious", w.C.Level(w.core) > 0)
	check("position offset only where OHA owns laning", w.C.AdjustPosition(w.core, loc) == loc)
end

do
	local w = world({ skill = 0.2 })
	enemy(10, { unseen = 7 })
	w.C.Level(w.core)
	T = 300.6
	check("level 0.6 at skill 0.2 with a missing enemy", near(w.C.Level(w.core), 0.6), w.C.Level(w.core))
	STRONGER = false
	check("trades suppressed when not stronger", w.H.Lane.Hooks.TradesSuppressed(w.core))
	check("suppressed trades stop the harass step", w.H.Lane.HarassThink(w.core, {}, {}, {}, false) == false)
	STRONGER = true
	check("trades allowed when stronger", not w.C.SuppressTrades(w.core))
	STRONGER = false
	w = world({ skill = 0 })
	w.sup.alive = false
	w.C.Level(w.core)
	T = 300.6
	check("level below 0.5 never suppresses (precondition)", w.C.Level(w.core) > 0 and w.C.Level(w.core) < 0.5, w.C.Level(w.core))
	check("level below 0.5 never suppresses", not w.C.SuppressTrades(w.core))
end

do
	local w = world()
	enemy(10, { unseen = 7 })
	w.C.Tick(w.core)
	T = 300.6
	w.C.Tick(w.core)
	check("caution claims retreat", w.H.Intent.ClaimAge(w.core, SOURCE, BotMode.Retreat) ~= nil)
	check("caution scales retreat up by 1.3 at level 1", near(w.H.Intent.Resolve(w.core, BotMode.Retreat, 0.5), 0.65), w.H.Intent.Resolve(w.core, BotMode.Retreat, 0.5))
	check("caution scales attack down by 0.7 at level 1", near(w.H.Intent.Resolve(w.core, BotMode.Attack, 0.5), 0.35), w.H.Intent.Resolve(w.core, BotMode.Attack, 0.5))
	LAST_SEEN[10] = nil
	w.H.Lane.LaneState.ResetCache()
	T = 301.2
	w.C.Tick(w.core)
	check("caution releases its claims at level 0", w.H.Intent.ClaimAge(w.core, SOURCE, BotMode.Retreat) == nil)
end

-- Kill switch: the same cautious scenario with the feature off, and with the sub-flag off.
for _, tcfg in ipairs({ { Enable = false }, { Enable = true, Caution = false } }) do
	local label = tcfg.Enable and "caution flag off" or "transitions off"
	local loc = Vector(0, -5000)
	local w = world({ transitions = tcfg })
	enemy(10, { unseen = 7 })
	w.H.Transitions.Tick(w.core)
	T = 300.6
	w.H.Transitions.Tick(w.core)
	STRONGER = false
	check(label .. ": no level", w.C.Level(w.core) == 0)
	check(label .. ": AdjustPosition returns loc", w.C.AdjustPosition(w.core, loc) == loc)
	check(label .. ": position hook returns loc", w.H.Lane.Hooks.PositionOverride(w.core, loc) == loc)
	check(label .. ": trades not suppressed", not w.H.Lane.Hooks.TradesSuppressed(w.core))
	check(label .. ": no claims", w.H.Intent.ClaimAge(w.core, SOURCE, BotMode.Retreat) == nil)
	check(label .. ": no callout", #w.said == 0, #w.said)
end

do
	local w = world()
	enemy(10, { unseen = 7 })
	w.C.Tick(w.core)
	w.C.Tick(w.sup)
	check("missing callout for the lane", count(w.said, "say_ss_bot") == 1, #w.said)
	T = 300.6
	w.C.Tick(w.core)
	w.C.Tick(w.sup)
	check("one callout per team per lane per episode", count(w.said, "say_ss_bot") == 1, #w.said)
	-- Seen again, then missing again inside the cooldown: no second line.
	LAST_SEEN[10] = { location = FRONT, time_since_seen = 1 }
	w.H.Lane.LaneState.ResetCache()
	T = 301.2
	w.C.Tick(w.core)
	LAST_SEEN[10] = { location = FRONT, time_since_seen = 7 }
	w.H.Lane.LaneState.ResetCache()
	T = 302
	w.C.Tick(w.core)
	check("a new episode inside the cooldown is not called", count(w.said, "say_ss_bot") == 1, #w.said)
	w.H.Lane.LaneState.ResetCache()
	T = 331
	w.C.Tick(w.core)
	check("that episode is not called once the cooldown ends", count(w.said, "say_ss_bot") == 1, #w.said)
	LAST_SEEN[10] = { location = FRONT, time_since_seen = 1 }
	w.H.Lane.LaneState.ResetCache()
	T = 340
	w.C.Tick(w.core)
	LAST_SEEN[10] = { location = FRONT, time_since_seen = 7 }
	w.H.Lane.LaneState.ResetCache()
	T = 345
	w.C.Tick(w.core)
	check("a new episode after the cooldown is called", count(w.said, "say_ss_bot") == 2, #w.said)

	w = world({ noHuman = true })
	enemy(10, { unseen = 7 })
	w.C.Tick(w.core)
	check("no callout without a human ally", #w.said == 0, #w.said)
end

do
	local function midWorld(signal)
		local w = world()
		w.mid.lane, w.mid.pos = Lane.Top, 3
		w.solo = hero({ pid = 3, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
		enemy(10, { unseen = 7, loc = Vector(0, 0) })
		if signal then w.H.Lane.Counter.Signals = function() return { { kind = "mid_missing", at = T - 5 } } end end
		w.C.Tick(w.solo)
		return w
	end
	check("mid missing is called", count(midWorld(false).said, "say_ss_mid") == 1)
	check("mid callout skipped after a recent counterplay mid_missing", count(midWorld(true).said, "say_ss_mid") == 0)
end

-- Caution and its callout are laning-phase transitions: after laning (LANING = false at 11:40) or with our T1 down
-- before 10:00 there is no level, no claim and no line. Each case runs in laning first, as the contrast.
do
	local function run(laning, t1Dead)
		local w = world()
		T = 700
		enemy(10, { unseen = 10 })
		if not laning then LANING = false end
		if t1Dead then T = 300; TOWERS_W[2][dota.Tower.Bot1].alive = false end
		local t0 = T
		w.C.Tick(w.core)
		T = t0 + 0.6
		w.C.Tick(w.core)
		return { level = w.C.Level(w.core), claim = w.H.Intent.ClaimAge(w.core, SOURCE, BotMode.Retreat) ~= nil,
			said = count(w.said, "say_ss_bot"), pos = w.C.AdjustPosition(w.core, FRONT) }
	end
	local on, off, dead = run(true), run(false), run(true, true)
	check("in laning at 11:40 (contrast): cautious with a claim and a callout", on.level > 0 and on.claim and on.said == 1, on.level)
	check("after laning: caution level 0", off.level == 0, off.level)
	check("after laning: no caution claim", not off.claim)
	check("after laning: no missing callout", off.said == 0, off.said)
	check("after laning: no position offset", off.pos == FRONT)
	check("our T1 down before 10:00: level 0, no claim, no callout", dead.level == 0 and not dead.claim and dead.said == 0, dead.level)
end

do
	-- Laning ends while cautious: the claim goes on the next tick, not after the notice delay or the claim TTL.
	local w = world({ delay = 1.0 })
	enemy(10, { unseen = 10 })
	w.C.Tick(w.core)
	T = 301.1
	w.C.Tick(w.core)
	check("precondition: cautious with a claim", w.C.Level(w.core) > 0 and w.H.Intent.ClaimAge(w.core, SOURCE, BotMode.Retreat) ~= nil)
	LANING = false
	T = 301.7
	w.C.Tick(w.core)
	check("laning ends: level 0 at once", w.C.Level(w.core) == 0, w.C.Level(w.core))
	check("laning ends: the claim is released at once", w.H.Intent.ClaimAge(w.core, SOURCE, BotMode.Retreat) == nil)
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
	-- Caution reports each applied level once, including the drop to 0 when laning ends.
	local w = world({ telemetry = { Enable = true } })
	local ev = capture(w)
	w.core.alive = false
	w.H.Transitions.Tick(w.sup)
	T = 300.6
	w.H.Transitions.Tick(w.sup)
	local l = ev("tr_caution")
	check("tr_caution: one line when the alone support turns cautious", #l == 1 and has(l[1], "pid=5", "alone=1") and not has(l[1], "level=0 "), l[1])
	LANING = false
	T = 301.2
	w.H.Transitions.Tick(w.sup)
	l = ev("tr_caution")
	check("tr_caution: the end of laning reports level 0", #l == 2 and has(l[2], "pid=5", "level=0 "), l[2])
end

finish()
