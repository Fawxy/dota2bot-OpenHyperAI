-- Early lane ward on the gank path (task 12, Task 7).
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local SOURCE = "transitions:ward"
RANDOM_FRACTION = nil
local ANCHOR = Vector(3097, -4069)

local function hero(o)
	local u = MakeUnit({ pid = o.pid, team = 2, bot = true, loc = o.loc or Vector(0, -5000) })
	u.lane, u.pos = o.lane, o.pos
	return u
end

-- Radiant: safelane is Bot (carry + pos 5), offlane is Top (pos 3 + pos 4).
local function world(opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true }, { skill = opts.skill or 0.5, transitions = opts.transitions or { Enable = true } })
	T = opts.T or 200
	CURRENT_TEAM = 2
	local w = { H = H, W = H.Transitions.LaneWard }
	w.carry = hero({ pid = 1, pos = 1, lane = Lane.Bot })
	w.mid = hero({ pid = 2, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	w.off = hero({ pid = 3, pos = 3, lane = Lane.Top, loc = Vector(0, 5000) })
	w.p4 = hero({ pid = 4, pos = 4, lane = Lane.Top, loc = Vector(0, 5000) })
	w.p5 = hero({ pid = 5, pos = 5, lane = Lane.Bot })
	return w
end

local function ward(loc)
	local u = { loc = loc }
	function u:GetUnitName() return "npc_dota_observer_wards" end
	function u:GetLocation() return self.loc end
	table.insert(WARDS[2], u)
end

local NEAR = { location = Vector(3000, -4000) }
local SPOTS = { { location = Vector(-4000, 2500) }, NEAR, { location = Vector(-7000, 4000) } }
-- Other systems draw randoms too, so the dice are a constant fraction rather than a queue.
local PASS, FAIL = 0.1, 0.99
local function dice(f) RANDOM_FRACTION = f end

do
	local w = world()
	dice(PASS)
	check("picks the spot nearest the safelane anchor", w.W.Pick(w.p5, SPOTS) == NEAR)
	w = world()
	dice(PASS)
	local top = w.W.Pick(w.p4, SPOTS)
	check("the offlane support is drawn to the offlane anchor instead", top == SPOTS[1])
end

do
	local w = world({ T = 120 })
	dice(PASS)
	check("2:00 is before the window", w.W.Pick(w.p5, SPOTS) == nil)
	T = 280
	check("4:40 is after the window", w.W.Pick(w.p5, SPOTS) == nil)
	T = 200
	check("inside the window the same bot gets a pick", w.W.Pick(w.p5, SPOTS) == NEAR)
end

do
	local w = world()
	dice(PASS)
	ward(Vector(ANCHOR.x + 1000, ANCHOR.y))
	check("an observer 1000 from the anchor covers the lane", w.W.Pick(w.p5, SPOTS) == nil)
	w = world()
	dice(PASS)
	ward(Vector(ANCHOR.x + 2500, ANCHOR.y))
	check("an observer 2500 away does not", w.W.Pick(w.p5, SPOTS) == NEAR)
end

do
	local w = world()
	dice(PASS)
	check("pos 4 asked about the safelane gets no pick", w.W.Pick(hero({ pid = 6, pos = 4, lane = Lane.Bot }), SPOTS) == nil)
	check("the safelane carry gets no pick", w.W.Pick(w.carry, SPOTS) == nil)
	check("the mid gets no pick", w.W.Pick(w.mid, SPOTS) == nil)
	check("the offlane pos 3 gets no pick", w.W.Pick(w.off, SPOTS) == nil)
end

do
	-- The safelane pos 5 is absent: the lane's lowest support (the pos 4 sent there) takes the job.
	local w = world()
	w.p5.lane = Lane.Top
	w.p4.lane = Lane.Bot
	w.H.Lane.LaneState.ResetCache()
	dice(PASS)
	check("the lowest support present stands in", w.W.Pick(w.p4, SPOTS) == NEAR)
	-- A lane with no core gets no pick.
	w = world()
	w.carry.lane = Lane.Top
	w.H.Lane.LaneState.ResetCache()
	dice(PASS)
	check("no core in the lane: no pick", w.W.Pick(w.p5, SPOTS) == nil)
end

do
	local w = world()
	dice(FAIL)
	check("a failed roll gives no pick", w.W.Pick(w.p5, SPOTS) == nil)
	dice(PASS)
	T = 210
	check("a failed roll stays failed for the rest of the window", w.W.Pick(w.p5, SPOTS) == nil)
	T = 260
	check("... even when the dice would now pass", w.W.Pick(w.p5, SPOTS) == nil)
	dice(FAIL)
	w = world()
	dice(PASS)
	check("a passed roll stays passed", w.W.Pick(w.p5, SPOTS) == NEAR)
	dice(FAIL)
	T = 230
	check("... even when the dice would now fail", w.W.Pick(w.p5, SPOTS) == NEAR)
end

do
	-- Contrast: the same scenario with LaneWard on and off.
	local res = {}
	for _, on in ipairs({ true, false }) do
		local w = world({ transitions = { Enable = true, LaneWard = on } })
		dice(PASS)
		local pick = w.W.Pick(w.p5, SPOTS)
		if pick then w.H.Transitions.ConfirmLaneWard(w.p5, pick) end
		w.H.Transitions.Tick(w.p5)
		res[on] = { pick = pick, claim = w.H.Intent.ClaimAge(w.p5, SOURCE, BotMode.Ward) }
	end
	check("enabled: picks the spot", res[true].pick == NEAR)
	check("enabled: posts the ward claim", res[true].claim ~= nil)
	check("disabled: no pick", res[false].pick == nil)
	check("disabled: no claim", res[false].claim == nil)

	-- The kill switch gives the same.
	local w = world({ transitions = { Enable = false } })
	dice(PASS)
	check("kill switch: no pick", w.W.Pick(w.p5, SPOTS) == nil)
	w.H.Transitions.Tick(w.p5)
	check("kill switch: no claim", w.H.Intent.ClaimAge(w.p5, SOURCE, BotMode.Ward) == nil)
	check("kill switch: no GetUnitList call at all", next(GETUNITLIST_CALLS) == nil)
end

do
	local w = world()
	dice(PASS)
	w.H.Transitions.ConfirmLaneWard(w.p5, w.W.Pick(w.p5, SPOTS))
	w.H.Transitions.Tick(w.p5)
	check("claim is posted while the pick is live", w.H.Intent.ClaimAge(w.p5, SOURCE, BotMode.Ward) ~= nil)
	T = 203
	w.H.Transitions.Tick(w.p5)
	check("claim is released once the ward mode stops asking", w.H.Intent.ClaimAge(w.p5, SOURCE, BotMode.Ward) == nil)
end

do
	local w = world()
	dice(PASS)
	GETUNITLIST_CALLS = {}
	local base = GETUNITLIST_CALLS[dota.UnitType.AlliedWards] or 0
	for i = 0, 8 do
		T = 200 + i
		w.W.Pick(w.p5, SPOTS)
		w.W.Pick(w.p5, SPOTS)
	end
	local n = (GETUNITLIST_CALLS[dota.UnitType.AlliedWards] or 0) - base
	check("allied-ward scans: at most one per 5 s for the team", n == 2, n)
end

do
	-- The ward mode rejected the spot (enemy closer / too far / cooldown): it never confirms, so no claim.
	local w = world()
	dice(PASS)
	check("pick is returned", w.W.Pick(w.p5, SPOTS) == NEAR)
	w.H.Transitions.Tick(w.p5)
	check("unconfirmed pick: no claim", w.H.Intent.ClaimAge(w.p5, SOURCE, BotMode.Ward) == nil)
	w.H.Transitions.ConfirmLaneWard(w.p5, NEAR)
	w.H.Transitions.Tick(w.p5)
	check("confirmed pick: claim", w.H.Intent.ClaimAge(w.p5, SOURCE, BotMode.Ward) ~= nil)
	w.H.Transitions.ConfirmLaneWard(w.p5, SPOTS[1])
	local w2 = world()
	dice(PASS)
	w2.W.Pick(w2.p5, SPOTS)
	w2.H.Transitions.ConfirmLaneWard(w2.p5, SPOTS[3])
	w2.H.Transitions.Tick(w2.p5)
	check("confirming a different spot: no claim", w2.H.Intent.ClaimAge(w2.p5, SOURCE, BotMode.Ward) == nil)
end

do
	-- A later Pick that declines (outside the window) drops the earlier pending pick, so upstream choosing
	-- that same spot object for its own reasons does not post the lane-ward floor.
	local w = world()
	dice(PASS)
	check("stale pending: first pick returned", w.W.Pick(w.p5, SPOTS) == NEAR)
	T = 300
	check("stale pending: outside the window no pick", w.W.Pick(w.p5, SPOTS) == nil)
	w.H.Transitions.ConfirmLaneWard(w.p5, NEAR)
	w.H.Transitions.Tick(w.p5)
	check("stale pending: no claim", w.H.Intent.ClaimAge(w.p5, SOURCE, BotMode.Ward) == nil)
end

do
	local w = world()
	dice(PASS)
	check("only far spots: no pick", w.W.Pick(w.p5, { SPOTS[1], SPOTS[3] }) == nil)
	check("a spot 1400 from the anchor is still taken", w.W.Pick(w.p5, { { location = Vector(ANCHOR.x + 1400, ANCHOR.y) } }) ~= nil)
	check("a spot 1600 away is not", w.W.Pick(w.p5, { { location = Vector(ANCHOR.x + 1600, ANCHOR.y) } }) == nil)
end

do
	-- The support's own fresh ward covers the lane before the scan cache catches up.
	local w = world()
	dice(PASS)
	local pick = w.W.Pick(w.p5, SPOTS)
	w.H.Transitions.ConfirmLaneWard(w.p5, pick)
	check("precondition: still a pick before planting", w.W.Pick(w.p5, SPOTS) == pick)
	pick.plant_time_obs = T
	T = 202
	check("after planting: lane covered despite the cached scan", w.W.Pick(w.p5, SPOTS) == nil)
end

do
	-- Dire: safelane is Top, offlane is Bot; anchors are Dire's own river spots.
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = { Enable = true } })
	T, CURRENT_TEAM = 200, 3
	local function d(o) local u = MakeUnit({ pid = o.pid, team = 3, bot = true, loc = Vector(0, 0) }); u.lane, u.pos = o.lane, o.pos; return u end
	d({ pid = 11, pos = 1, lane = Lane.Top }); d({ pid = 12, pos = 5, lane = Lane.Top })
	d({ pid = 13, pos = 3, lane = Lane.Bot }); local off = d({ pid = 14, pos = 4, lane = Lane.Bot })
	dice(PASS)
	local spots = { { location = Vector(-4310, 3639) }, { location = Vector(3810, -4562) }, { location = Vector(-2159, 1987) } }
	check("Dire offlane support gets the spot nearest Dire's bot-lane anchor", H.Transitions.LaneWard.Pick(off, spots) == spots[2])
end

finish()
