dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")

local function bot()
	return MakeUnit({ pid = 2, team = 2, bot = true, loc = Vector(0, 0) })
end

do
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = { Enable = true } })
	check("positive control: active by default", H.Transitions.IsActive())
end

do
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = { Enable = false } })
	local b = bot()
	T = 100
	H.Transitions.Tick(b)
	check("disabled: no unit scans", next(GETUNITLIST_CALLS) == nil)
	local why = H.Intent.Explain(b, dota.BotMode.Laning)
	check("disabled: no claims posted", why:find("valve", 1, true) ~= nil, why)
	check("disabled: sub-flags report off", not H.Transitions.Settings.IsOn("Rotation"))
	H = LaneFresh({ Enable = true }, { enable = false })
	check("humaniser off also deactivates", not H.Transitions.IsActive())
end

do
	local H = LaneFresh({ Enable = true }, { transitions = { Rotation = false } })
	local S = H.Transitions.Settings
	check("flag off", not S.IsOn("Rotation"))
	check("other flags keep defaults", S.IsOn("MidRunes") and S.IsOn("LostLane"))
	check("untouched values keep defaults", near(S.Get().Refresh, 0.5) and near(S.Get().RotateChance.Low, 0.3))
	H = LaneFresh({ Enable = true }, { transitions = { RotateChance = { High = 1.0 } } })
	S = H.Transitions.Settings
	check("partial lerp pair merges", near(S.Get().RotateChance.High, 1.0) and near(S.Get().RotateChance.Low, 0.3))
end

do
	local S = LaneFresh({ Enable = true }).Transitions.Settings
	local pair = { Low = 0.3, High = 0.9 }
	check("lerp interpolates", near(S.Lerp(pair, 0.5), 0.6))
	check("lerp clamps skill", near(S.Lerp(pair, 2), 0.9) and near(S.Lerp(pair, -1), 0.3))
	check("falling pair interpolates", near(S.Lerp(S.Get().ArriveSigma, 1), 1))
end

do
	local H = LaneFresh({ Enable = true }, { skill = 0.5 })
	local b = bot()
	T = 100
	LANING = true
	local line = H.Transitions.Overlay(b)
	check("overlay format", line:match("^phase: laning busy=%a+ spare=%a+ alone=%a+ rot=%-$") ~= nil, line)
	LANING = false
	check("overlay phase after laning", H.Transitions.Overlay(b):find("^phase: post ") ~= nil)
	H.Transitions.SetOverlayProviders({ Busy = function() return true end, Rotation = function() return "top" end })
	line = H.Transitions.Overlay(b)
	check("overlay reads providers", line:find("busy=true", 1, true) ~= nil and line:find("rot=top", 1, true) ~= nil, line)
end

-- Regression pin (spec test 7): every hook in a scenario where it fires returns its upstream value with the kill switch
-- off. Each scenario runs with Transitions enabled first, so a hook that never fires cannot pass the disabled run vacuously.
local Lane, BotMode, Rune = dota.Lane, dota.BotMode, dota.Rune

local TOP_SPOT, BOT_SPOT = Vector(-1500, 1500), Vector(1500, -1500)
local SPOT = { [Rune.Power1] = TOP_SPOT, [Rune.Power2] = BOT_SPOT }
function GetRuneSpawnLocation(r) return SPOT[r] or Vector(-9000, 9000) end

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot ~= false, loc = o.loc, level = o.level })
	u.lane, u.pos, u.mode = o.lane, o.pos, 0
	return u
end

local function scans() return next(GETUNITLIST_CALLS) ~= nil end
-- SELF_TEST names the scenario's subject as the trainer self-test bot, which the transitions leave alone.
local SELF_TEST = nil
local function selfTest(H) if SELF_TEST ~= nil then H.Trainer.IsSelfTestBot = function(u) return u:GetPlayerID() == SELF_TEST end end end
local function claimed(H, u, source, mode) return H.Intent.ClaimAge(u, source, mode) ~= nil end

-- A bot pos 4 rotating to the power rune beside our mid at 5:55.
local function rotationScenario(tcfg)
	local H = LaneFresh({ Enable = true }, { skill = 0.9, transitions = tcfg })
	selfTest(H)
	T, CURRENT_TEAM = 335, 2
	local p4 = unit({ pid = 4, pos = 4, lane = Lane.Top, loc = Vector(0, 5000) })
	local mid = unit({ pid = 2, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	unit({ pid = 1, bot = false, pos = 1, lane = Lane.Bot, loc = Vector(0, -5000) })
	unit({ pid = 3, pos = 3, lane = Lane.Top, loc = Vector(0, 5000) })
	unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(0, -5000) })
	for _, u in ipairs({ p4, mid }) do H.Lane.Config.SkillOf(u) end
	SetRandomSequence({ 0, 0.5, 0.25, 0.9 })
	H.Transitions.Tick(p4)
	T = 355
	H.Transitions.Tick(p4)
	local r = { target = H.Transitions.RuneTarget(p4), scans = scans() }
	p4.loc = Vector(-1000, 0)
	r.midDesire = H.Transitions.MidRuneDesire(mid)
	r.rotateClaim = claimed(H, p4, "transitions:rotate", BotMode.Rune)
	r.planned = H.Lane.Hooks.IsRotationPlanned(p4)
	return r
end

-- Our mid 15 s before the 6:00 spawn.
local function midRuneScenario(tcfg)
	local H = LaneFresh({ Enable = true }, { skill = 0.9, transitions = tcfg })
	selfTest(H)
	T, CURRENT_TEAM = 345, 2
	local mid = unit({ pid = 2, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	H.Transitions.Tick(mid)
	local focus, due = H.Transitions.MidRuneFocus(mid)
	return { on = H.Transitions.MidRunesOn(mid), focus = focus, due = due, claim = claimed(H, mid, "transitions:mid_rune", BotMode.Rune) }
end

-- The pos 5 on the safe lane at 3:20, asked for an observer spot.
local function wardScenario(tcfg)
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = tcfg })
	selfTest(H)
	T, CURRENT_TEAM = 200, 2
	unit({ pid = 1, pos = 1, lane = Lane.Bot, loc = Vector(0, -5000) })
	unit({ pid = 2, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	unit({ pid = 3, pos = 3, lane = Lane.Top, loc = Vector(0, 5000) })
	unit({ pid = 4, pos = 4, lane = Lane.Top, loc = Vector(0, 5000) })
	local p5 = unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(0, -5000) })
	RANDOM_FRACTION = 0.1
	local near = { location = Vector(3000, -4000) }
	local pick = H.Transitions.PickLaneWard(p5, { { location = Vector(-4000, 2500) }, near, { location = Vector(-7000, 4000) } })
	if pick ~= nil then H.Transitions.ConfirmLaneWard(p5, pick) end
	H.Transitions.Tick(p5)
	RANDOM_FRACTION = nil
	return { picked = pick == near, claim = claimed(H, p5, "transitions:ward", BotMode.Ward), scans = scans() }
end

-- The bot core on the bottom lane after its support left (a lane opponent unseen 7 s), then an enemy TP into the lane.
local function cautionScenario(tcfg)
	local H = LaneFresh({ Enable = true }, { skill = 1, transitions = tcfg })
	selfTest(H)
	T, CURRENT_TEAM = 300, 2
	local FRONT = Vector(0, -5000)
	unit({ pid = 2, bot = false, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	local core = unit({ pid = 1, pos = 1, lane = Lane.Bot, loc = FRONT })
	-- Hit by a hero just now, so caution's retreat scale applies (it only does for a threatened bot).
	core.heroHitAt = 300
	unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = FRONT })
	local foe = MakeUnit({ pid = 10, team = 3, loc = FRONT })
	foe.hiddenFrom = setmetatable({}, { __index = function() return true end })
	LAST_SEEN[10] = { location = FRONT, time_since_seen = 7 }
	H.Profile.SampleDelay = function() return 0 end
	H.Orders.SetAnnouncer(function() end)
	H.Transitions.Tick(core)
	T = 300.6
	H.Transitions.Tick(core)
	local loc = Vector(0, -5000)
	local r = {
		override = H.Lane.Hooks.PositionOverride(core, loc) ~= loc,
		suppressed = H.Lane.Hooks.TradesSuppressed(core),
		cautious = H.Lane.Hooks.IsCautious(core),
		claim = claimed(H, core, "transitions:caution", BotMode.Retreat),
		scans = scans(),
	}
	-- 07's own position step may scan for its techniques, so it comes after the scan reading.
	r.moved = H.Lane.AdjustPosition(core, loc) ~= loc
	return r
end

local function teleportScenario(tcfg)
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = tcfg })
	selfTest(H)
	T, CURRENT_TEAM = 300, 2
	local FRONT = Vector(0, -5000)
	unit({ pid = 2, bot = false, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	local core = unit({ pid = 1, pos = 1, lane = Lane.Bot, loc = FRONT })
	unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = FRONT })
	MakeUnit({ pid = 10, team = 3, loc = Vector(5000, 5000) })
	H.Profile.SampleDelay = function() return 0 end
	TELEPORTS = { { playerid = 10, location = FRONT, time_remaining = 6 } }
	H.Transitions.Tick(core)
	return { level = H.Transitions.Caution.Level(core), claim = claimed(H, core, "transitions:caution", BotMode.Retreat), reads = TELEPORT_READS }
end

local function dies(H, u, at)
	T = at - 1
	H.Transitions.Tick(u)
	T = at
	u.alive = false
	H.Transitions.Tick(u)
	T = at + 1
	u.alive = true
	H.Transitions.Tick(u)
end

-- A core that died twice in lane, and another with a Maelstrom and a clear jungle.
local function phaseScenario(tcfg, lost)
	local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = tcfg })
	selfTest(H)
	T, CURRENT_TEAM, LANING = 100, 2, true
	local CAMP = Vector(-1600, -6200)
	SPAWNERS = { { team = 2, type = "small", location = CAMP, min = Vector(CAMP.x - 150, CAMP.y - 150, 0), max = Vector(CAMP.x + 150, CAMP.y + 150, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	unit({ pid = 2, bot = false, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	local core = unit({ pid = 1, pos = 1, lane = Lane.Bot, loc = Vector(0, -5000) })
	unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(0, -5000) })
	core.ActionImmediate_Ping = function() end
	H.Orders.SetAnnouncer(function() end)
	H.Profile.SampleDelay = function() return 0 end
	if lost then
		dies(H, core, 30)
		dies(H, core, 60)
	else
		core.items = { [0] = { name = "item_maelstrom" } }
	end
	T = 100
	H.Transitions.Tick(core)
	local r = { allowed = H.Transitions.FarmAllowedInLaning(core) }
	LANING = nil
	return r
end

local function eq(a, b) return a == b end

do
	local on, off = rotationScenario({ Enable = true }), rotationScenario({ Enable = false })
	check("rotation (enabled): rune target, mid floor, claim and lane-plan probe", on.target == Rune.Power1 and near(on.midDesire, 0.55) and on.rotateClaim and on.planned, tostring(on.target))
	check("rotation (enabled): the scenario scans units", on.scans)
	check("rotation (disabled): every hook is upstream", off.target == nil and off.midDesire == 0 and not off.rotateClaim and not off.planned and not off.scans)
	local flagOff = rotationScenario({ Enable = true, Rotation = false })
	check("Rotation off: rune target, mid floor, claim and probe are upstream", flagOff.target == nil and flagOff.midDesire == 0 and not flagOff.rotateClaim and not flagOff.planned)
	check("MidRunes off leaves the rotation alone", rotationScenario({ Enable = true, MidRunes = false }).target == Rune.Power1)
end

do
	local on, off = midRuneScenario({ Enable = true }), midRuneScenario({ Enable = false })
	check("mid runes (enabled): on, focused 15 s before the spawn, floor claimed", on.on and on.focus and on.due and on.claim)
	check("mid runes (disabled): every hook is upstream", not off.on and not off.focus and not off.due and not off.claim)
	local flagOff = midRuneScenario({ Enable = true, MidRunes = false })
	check("MidRunes off: upstream", not flagOff.on and not flagOff.focus and not flagOff.claim)
end

do
	local on, off = wardScenario({ Enable = true }), wardScenario({ Enable = false })
	check("lane ward (enabled): the spot nearest the anchor and a ward floor", on.picked and on.claim)
	check("lane ward (disabled): no pick, confirm is a no-op, no claim, no scans", not off.picked and not off.claim and not off.scans)
	local flagOff = wardScenario({ Enable = true, LaneWard = false })
	check("LaneWard off: no pick and no claim", not flagOff.picked and not flagOff.claim)
end

do
	-- A pick made while enabled, then the kill switch thrown before the ward mode confirms it:
	-- Confirm must refuse on the switch itself, since the pending pick is still there to match.
	for _, flag in ipairs({ "Enable", "LaneWard" }) do
		local H = LaneFresh({ Enable = true }, { skill = 0.5, transitions = { Enable = true } })
		T, CURRENT_TEAM = 200, 2
		unit({ pid = 1, pos = 1, lane = Lane.Bot, loc = Vector(0, -5000) })
		local p5 = unit({ pid = 5, pos = 5, lane = Lane.Bot, loc = Vector(0, -5000) })
		RANDOM_FRACTION = 0.1
		local pick = H.Transitions.PickLaneWard(p5, { { location = Vector(3000, -4000) } })
		RANDOM_FRACTION = nil
		check("confirm after kill switch (" .. flag .. "): pick was pending", pick ~= nil)
		local dir = GetScriptDirectory()
		require(dir .. "/FunLib/humaniser/config").Get().Transitions[flag] = false
		require(dir .. "/FunLib/humaniser/transitions/settings").ResetSettings()
		H.Transitions.ConfirmLaneWard(p5, pick)
		H.Transitions.Tick(p5)
		check("confirm after kill switch (" .. flag .. "): no claim", not claimed(H, p5, "transitions:ward", BotMode.Ward))
	end
end

do
	local on, off = cautionScenario({ Enable = true }), cautionScenario({ Enable = false })
	check("caution (enabled): position moved, trades suppressed, plan cautious, retreat claim", on.override and on.moved and on.suppressed and on.cautious and on.claim and on.scans)
	check("caution (disabled): same table back, trades allowed, not cautious, no claim, no scans", not off.override and not off.moved and not off.suppressed and not off.cautious and not off.claim and not off.scans, tostring(off.moved)..tostring(off.suppressed)..tostring(off.cautious)..tostring(off.claim)..tostring(off.scans))
	local flagOff = cautionScenario({ Enable = true, Caution = false })
	check("Caution off: upstream", not flagOff.override and not flagOff.moved and not flagOff.suppressed and not flagOff.cautious and not flagOff.claim)
end

do
	local on, off = teleportScenario({ Enable = true }), teleportScenario({ Enable = false })
	check("teleports (enabled): the incoming TP is read, the core backs off", on.reads > 0 and near(on.level, 1) and on.claim, on.reads)
	check("teleports (disabled): GetIncomingTeleports never called, no level, no claim", off.reads == 0 and off.level == 0 and not off.claim, off.reads)
	local flagOff = teleportScenario({ Enable = true, Teleports = false })
	check("Teleports off: no reads, no level", flagOff.reads == 0 and flagOff.level == 0 and not flagOff.claim, flagOff.reads)
	local noCaution = teleportScenario({ Enable = true, Caution = false })
	check("Caution off: a TP still backs the core off (independent flags)", near(noCaution.level, 1) and noCaution.reads > 0)
end

do
	check("phase: a lost core farms (enabled)", phaseScenario({ Enable = true }, true).allowed == true)
	check("phase: a lost core does not farm (disabled)", phaseScenario({ Enable = false }, true).allowed == false)
	check("LostLane off: a lost core does not farm", phaseScenario({ Enable = true, LostLane = false }, true).allowed == false)
	check("phase: a Maelstrom core farms (enabled)", phaseScenario({ Enable = true }, false).allowed == true)
	check("phase: a Maelstrom core does not farm (disabled)", phaseScenario({ Enable = false }, false).allowed == false)
	check("Phase off: a Maelstrom core does not farm", phaseScenario({ Enable = true, Phase = false }, false).allowed == false)
	check("LostLane off leaves the phase end alone", phaseScenario({ Enable = true, LostLane = false }, false).allowed == true)
end

-- The trainer self-test bot (2bf9a81 skips Lane.PreThink for it) gets none of the transitions: every hook upstream,
-- no claims, no forced levels. The enabled scenarios above are the contrast.
do
	SELF_TEST = 4
	local rot = rotationScenario({ Enable = true })
	check("self-test pos 4: no rune target, no claim, no rotation probe", rot.target == nil and not rot.rotateClaim and not rot.planned, tostring(rot.target))
	SELF_TEST = 2
	local mid = midRuneScenario({ Enable = true })
	check("self-test mid: mid runes off, no focus, no floor", not mid.on and not mid.focus and not mid.claim)
	SELF_TEST = 5
	check("self-test pos 5: no lane ward pick or claim", not wardScenario({ Enable = true }).picked)
	SELF_TEST = 1
	local c = cautionScenario({ Enable = true })
	check("self-test core: no caution offset, trade suppression or claim", not c.override and not c.moved and not c.suppressed and not c.cautious and not c.claim)
	local tp = teleportScenario({ Enable = true })
	check("self-test core: no TP back-off", tp.level == 0 and not tp.claim, tp.level)
	check("self-test core: the phase does not release it to farm", phaseScenario({ Enable = true }, true).allowed == false)
	SELF_TEST = nil
end

finish()
