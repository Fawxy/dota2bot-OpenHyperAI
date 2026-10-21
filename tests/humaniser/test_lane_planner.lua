dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local FRONT = Vector(0, -5000)

-- Choose: a duo-lane support in a safe lane mid-game with everything allowed and the wave fine.
local function view(over)
	local v = { plan = "NEUTRAL", source = "picked", handsOff = false, pullAllowed = true, pullForced = false,
		stackRequested = false, coreIsHuman = false }
	for k, x in pairs(over or {}) do v[k] = x end
	return v
end

local function input(over)
	local i = {
		skill = 0.9, role = "support", isMid = false, now = 100, dotaTime = 100, plan = view(), laneScore = 0,
		eqPos = -0.7, allyCreeps = 4, enemyCreeps = 4, enemyLaners = 1, pullCamp = true, stackedPullCamp = false,
		mayRunCampJob = true, partnerSafe = true, coverAbsentCore = false, rotationPlanned = false,
		humanCoreInLane = false, desiredEq = -0.7,
	}
	for k, x in pairs(over or {}) do i[k] = x end
	return i
end

local P = LaneFresh({ Enable = true }).Lane.LanePlanner
local function choose(over) return P.Choose(input(over)) end
local function desc(c) return c.tech .. " (" .. c.reason .. ")" end

do
	check("half pull at 0.9 on small drift", choose({ laneScore = -0.3 }).tech == "half_pull", desc(choose({ laneScore = -0.3 })))
	local c = choose({ laneScore = -0.3, skill = 0.55 })
	check("below the half-pull gate falls back to aggro pull", c.tech == "aggro_pull", desc(c))
	c = choose({ laneScore = -0.3, skill = 0.4 })
	check("below both gates does nothing", c.tech == "none", desc(c))
end

do
	check("full pull at the 0.3 gate", choose({ laneScore = -1.6, skill = 0.3 }).tech == "full_pull")
	check("no full pull at 0.29", choose({ laneScore = -1.6, skill = 0.29 }).tech ~= "full_pull")
end

do
	local c = choose({ laneScore = -1.6 })
	check("full pull when pushed to the enemy T1", c.tech == "full_pull", desc(c))
	c = choose({ laneScore = -1.6, partnerSafe = false })
	check("no pull while the partner is in danger", c.tech ~= "full_pull" and c.tech ~= "half_pull", desc(c))
	c = choose({ laneScore = -1.6, mayRunCampJob = false })
	check("non-owner corrects with an aggro pull instead", c.tech == "aggro_pull", desc(c))
end

do
	local c = choose({ plan = view({ plan = "FREEZE" }), laneScore = -1.0 })
	check("support freezes instead of full-pulling under FREEZE", c.tech == "freeze", desc(c))
	c = choose({ plan = view({ plan = "FREEZE" }), laneScore = -0.3, allyCreeps = 7, enemyCreeps = 4 })
	check("large wave under FREEZE is thinned with a half pull", c.tech == "half_pull" and c.reason == "freeze: thin large wave", desc(c))
	c = choose({ plan = view({ plan = "FREEZE" }), laneScore = -0.3, allyCreeps = 5, enemyCreeps = 4 })
	check("wave not large enough under FREEZE keeps freezing", c.tech == "freeze", desc(c))
	c = choose({ plan = view({ plan = "HOLD" }), laneScore = -1.6 })
	check("full pull allowed under HOLD", c.tech == "full_pull", desc(c))
end

do
	local frz = view({ plan = "FREEZE" })
	local c = choose({ plan = frz, role = "core", skill = 0.8, eqPos = -0.4, desiredEq = -0.7 })
	check("core drags a drifting freeze back", c.tech == "aggro_pull" and c.reason == "freeze: drag back", desc(c))
	c = choose({ plan = frz, role = "core", skill = 0.8, eqPos = -0.6, desiredEq = -0.7 })
	check("core inside the margin keeps freezing", c.tech == "freeze", desc(c))
	c = choose({ plan = frz, role = "support", skill = 0.8, eqPos = -0.4, desiredEq = -0.7 })
	check("support never drags the freeze back", c.tech == "freeze", desc(c))
end

do
	local c = choose({ plan = view({ plan = "HOLD" }), skill = 0.5, override = "shove" })
	check("counter override chooses its technique", c.tech == "shove" and c.reason == "counter: shove", desc(c))
	c = choose({ plan = view({ plan = "HOLD" }), skill = 0.3, override = "shove" })
	check("unknown counter override is ignored", c.tech ~= "shove", desc(c))
end

do
	local c = choose({ plan = view({ plan = "HOLD" }), laneScore = 0.5 })
	check("support does not shove under HOLD", c.tech ~= "shove", desc(c))
	c = choose({ plan = view({ plan = "SHOVE" }), laneScore = 0.5 })
	check("support shoves under SHOVE", c.tech == "shove", desc(c))
	c = choose({ plan = view({ plan = "SHOVE" }), laneScore = -1.6, skill = 0.35 })
	check("support that cannot shove does not pull under SHOVE", c.tech == "none", desc(c))
end

do
	local base = { laneScore = -1.6, stackedPullCamp = true, enemyLaners = 1 }
	local function with(o) local r = {} for k, v in pairs(base) do r[k] = v end for k, v in pairs(o) do r[k] = v end return r end
	check("stacked camp is stack-pulled at 0.8", choose(with({ skill = 0.8 })).tech == "stack_pull")
	check("below the stack-pull gate full-pulls", choose(with({ skill = 0.7 })).tech == "full_pull")
	check("unstacked camp full-pulls", choose(with({ skill = 0.8, stackedPullCamp = false })).tech == "full_pull")
	check("stack pull without an enemy laner full-pulls", choose(with({ skill = 0.8, enemyLaners = 0 })).tech == "full_pull")
end

do
	local c = choose({ plan = view({ handsOff = true }), dotaTime = 5, now = 5, laneScore = -1.6 })
	check("handsoff beats block and pull", c.tech == "none" and c.reason == "handsoff", desc(c))
end

do
	local start = { dotaTime = 5, now = 5 }
	local function with(o) local r = {} for k, v in pairs(start) do r[k] = v end for k, v in pairs(o) do r[k] = v end return r end
	check("support blocks at 0:00 with skill 0.3", choose(with({ skill = 0.3 })).tech == "block")
	check("skill 0.29 does not block", choose(with({ skill = 0.29 })).tech ~= "block")
	check("bot core blocks its own lane", choose(with({ role = "core" })).tech == "block")
	check("bot core skips the block next to a human core", choose(with({ role = "core", humanCoreInLane = true })).tech ~= "block")
	check("support still blocks next to a human core", choose(with({ humanCoreInLane = true })).tech == "block")
	check("no block after 0:30", choose({ dotaTime = 31, now = 31 }).tech ~= "block")
end

do
	local c = choose({ coverAbsentCore = true, skill = 0.8 })
	check("covering support freezes", c.tech == "freeze" and c.reason == "cover core: freeze", desc(c))
	c = choose({ coverAbsentCore = true, skill = 0.55, laneScore = -0.3 })
	check("covering support below freeze gate aggro-pulls", c.tech == "aggro_pull", desc(c))
	c = choose({ coverAbsentCore = true, skill = 0.3, laneScore = -0.3 })
	check("covering support below both gates holds", c.tech == "hold", desc(c))
end

do
	local c = choose({ laneScore = 0.1, plan = view({ pullForced = true }) })
	check("ordered pull bypasses the band", c.tech == "full_pull", desc(c))
	c = choose({ laneScore = 0.1, plan = view({ pullForced = true }), pullCamp = false })
	check("ordered pull still needs a camp", c.tech ~= "full_pull", desc(c))
	c = choose({ laneScore = -1.6, plan = view({ pullAllowed = false }) })
	check("nopull blocks the full pull", c.tech == "aggro_pull", desc(c))
end

do
	check("lane fine does nothing", choose({ laneScore = 0.1 }).tech == "none")
	check("mid without a pull camp never pulls", choose({ isMid = true, pullCamp = false, laneScore = -1.6 }).tech == "aggro_pull")
end

-- Plan: Radiant bot lane, bot core pid 1 (pos 1), bot support pid 5 (pos 5), one enemy laner at the front.
-- Default fronts put eqPos at 0, so laneScore = -0.7 - 0.2 * 0.5 = -0.8 (full-pull band).
local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = o.loc or FRONT })
	u.lane, u.pos = o.lane or Lane.Bot, o.pos
	return u
end

local ROTATING = false
local function planWorld(skill, opts)
	opts = opts or {}
	local H = LaneFresh({ Enable = true }, { skill = skill })
	T = opts.t or 95
	CURRENT_TEAM = 2
	OBSERVER = 1
	ROTATING = false
	SPAWNERS = { { team = 2, type = "small", location = Vector(-1600, -5000, 0), min = Vector(-1750, -5150, 0),
		max = Vector(-1450, -4850, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	H.Lane.Hooks.SetRotationProbe(function() return ROTATING end)
	local core = unit({ pid = 1, pos = 1 })
	local support = unit({ pid = 5, pos = 5 })
	unit({ pid = 10, team = 3, pos = 3, lane = Lane.Top })
	return H, core, support, H.Lane.LanePlanner
end
local function plan(H, P, bot) return P.Plan(bot, H.Lane.LaneState.ForBot(bot)) end

do
	local H, core, _, P = planWorld(0.9)
	ROTATING = true
	SetRandomSequence({ 0.5 })
	local c = plan(H, P, core)
	check("attempt roll under the rate keeps the technique", c.tech == "shove", desc(c))
	check("one draw for the new (cycle, technique)", RandomUnread() == 0)
end

do
	local H, core, _, P = planWorld(0.4)
	ROTATING = true
	SetRandomSequence({ 0.5 })
	local c = plan(H, P, core)
	check("attempt roll over the rate skips", c.tech == "none" and c.reason == "skip: attempt-roll shove", desc(c))
	T = T + 10
	SetRandomSequence({ 0.0 })
	c = plan(H, P, core)
	check("roll is cached for the cycle", c.reason == "skip: attempt-roll shove", desc(c))
	check("cached roll consumes no draw", RandomUnread() == 1)
	T = 125
	c = plan(H, P, core)
	check("next cycle rolls again", c.tech == "shove", desc(c))
end

do
	local H, _, support, P = planWorld(0.9)
	local c = plan(H, P, support)
	check("precondition: support full-pulls", c.tech == "full_pull", desc(c))
	H.Orders.Post(2, { type = "LANE_HANDSOFF", sourceKey = "ping", issuerPID = 0, lane = Lane.Bot, duration = 30,
		maxResponders = 1, onlyPIDs = { 5 }, delayKind = "ping" })
	T = 100
	check("precondition: ping accepted", H.Orders.GetAcceptedForLane(support, "LANE_HANDSOFF", Lane.Bot) ~= nil)
	c = plan(H, P, support)
	check("ping mid-cycle stops the technique", c.tech == "none" and c.reason == "handsoff", desc(c))
end

do
	local H, core, _, P = planWorld(0.45, { t = 93 })
	local c = plan(H, P, core)
	check("precondition: core idle before the rotation", c.tech == "none", desc(c))
	T = 102
	ROTATING = true
	SetRandomSequence({ 0.0 })
	c = plan(H, P, core)
	check("rotation probe turning true shoves mid-cycle", c.tech == "shove" and c.reason == "shove before rotating", desc(c))
end

do
	local H, core, support, P = planWorld(0.9)
	local c = plan(H, P, support)
	check("precondition: full pull", c.tech == "full_pull", desc(c))
	P.Commit(support, "full_pull")
	check("committed for the cycle", P.Committed(support) == "full_pull")
	core.hp = 30
	T = 97
	c = plan(H, P, support)
	check("one technique per cycle", c.tech == "none" and c.reason == "one per cycle (full_pull)", desc(c))
	T = 121
	check("commit clears with the cycle", P.Committed(support) == nil)
	c = plan(H, P, support)
	check("next cycle picks the new technique", c.tech == "aggro_pull", desc(c))
end

local function forcePull(H)
	H.Orders.Post(2, { type = "LANE_PULL", sourceKey = "pull", issuerPID = 0, lane = Lane.Bot, duration = 120,
		maxResponders = 2, onlyPIDs = { 1, 5 }, delayKind = "chat" })
	T = T + 20
end

do
	local H, core, _, P = planWorld(0.4)
	forcePull(H)
	ROTATING = true
	check("precondition: pull ordered", H.Lane.LanePlan.View(core, H.Lane.LaneState.ForBot(core)).pullForced)
	SetRandomSequence({ 0.9 })
	local c = plan(H, P, core)
	check("ordered pull does not waive the roll for a rotation shove", c.tech == "none" and c.reason == "skip: attempt-roll shove", desc(c))
end

do
	local H, _, support, P = planWorld(0.4, { t = 75 })
	forcePull(H)
	SetRandomSequence({ 0.9, 0.9 })
	local c = plan(H, P, support)
	check("the ordered pull itself skips the roll", c.tech == "full_pull", desc(c))
end

-- PF9: the core's own aggro stagger counts from when the planner first chose aggro_pull.
local function mayDraw(H, bot)
	local ok, why = H.Lane.LaneRoles.MayDrawAggro(bot, H.Lane.LaneState.ForBot(bot))
	return why
end

do
	local H, core = planWorld(0.9)
	T = 96.6
	check("control: without a plan the stagger starts now", mayDraw(H, core) == "yield: stagger", mayDraw(H, core))
end

do
	local H, core, _, P = planWorld(0.9)
	local c = plan(H, P, core)
	check("precondition: core aggro-pulls", c.tech == "aggro_pull", desc(c))
	T = 96.6
	check("need noted when aggro pull was chosen", mayDraw(H, core) == "ok", mayDraw(H, core))
end

do
	local H, core, _, P = planWorld(0.9)
	plan(H, P, core)
	T = 96.6
	ROTATING = true
	check("precondition: choice changes to shove", plan(H, P, core).tech == "shove")
	T = 97
	ROTATING = false
	check("precondition: back to aggro pull", plan(H, P, core).tech == "aggro_pull")
	T = 97.5
	check("changed choice restarts the need", mayDraw(H, core) == "yield: stagger", mayDraw(H, core))
	check("Current mirrors the last plan", P.Current(core).tech == "aggro_pull")
end

do
	local H = LaneFresh({ Enable = false }, { skill = 0.9 })
	T = 95
	CURRENT_TEAM = 2
	local core = unit({ pid = 1, pos = 1 })
	local c = H.Lane.LanePlanner.Plan(core, { team = 2, lane = Lane.Bot })
	check("lane off plans nothing", c.tech == "none" and c.reason == "lane off", desc(c))
end

finish()
