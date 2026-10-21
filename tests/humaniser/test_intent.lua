dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local BotMode, Lane = dota.BotMode, dota.Lane


local FARM, LANING, RETREAT, ROSHAN = BotMode.Farm, BotMode.Laning, BotMode.Retreat, BotMode.Roshan

local function fresh(intent)
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, Intent = intent or { Enable = true } })
	local b = MakeUnit({ pid = 1, mode = LANING })
	return H, H.Intent, b
end

-- A higher tier overrides a lower tier in both directions.
do
	local H, I, b = fresh()
	I.Claim(b, { source = "lane:stack", tier = "CAMP_JOB", mode = FARM, floor = 0.9 })
	I.Claim(b, { source = "orders:DEFEND", tier = "HUMAN_ORDER", mode = FARM, cap = 0.3 })
	check("higher-tier cap beats lower-tier floor", near(I.Resolve(b, FARM, 0.5), 0.3), I.Resolve(b, FARM, 0.5))
	I.Claim(b, { source = "orders:ROSHAN", tier = "HUMAN_ORDER", mode = ROSHAN, floor = 0.85 })
	I.Claim(b, { source = "intent:stuck", tier = "LANE_PLAN", mode = ROSHAN, cap = 0.2 })
	check("higher-tier floor beats lower-tier cap", near(I.Resolve(b, ROSHAN, 0.4), 0.85), I.Resolve(b, ROSHAN, 0.4))
	check("claims only touch their mode", near(I.Resolve(b, LANING, 0.4), 0.4))
end

-- Same tier: the later-expiring claim wins.
for _, case in ipairs({ { floorUntil = 10, capUntil = 5, expect = 0.8 }, { floorUntil = 5, capUntil = 10, expect = 0.4 } }) do
	local H, I, b = fresh()
	I.Claim(b, { source = "mood:greedy", tier = "MOOD", mode = FARM, floor = 0.8, ["until"] = case.floorUntil })
	I.Claim(b, { source = "mood:scared", tier = "MOOD", mode = FARM, cap = 0.4, ["until"] = case.capUntil })
	check("later expiry wins " .. case.expect, near(I.Resolve(b, FARM, 0.6), case.expect), I.Resolve(b, FARM, 0.6))
end

-- Same tier and expiry: the source name decides, whatever order the claims were posted in.
for _, order in ipairs({ { "a", "b" }, { "b", "a" } }) do
	local H, I, b = fresh()
	local claims = {
		a = { source = "a:floor", tier = "FIGHT", mode = FARM, floor = 0.8, ["until"] = 10 },
		b = { source = "b:cap", tier = "FIGHT", mode = FARM, cap = 0.4, ["until"] = 10 },
	}
	I.Claim(b, claims[order[1]])
	I.Claim(b, claims[order[2]])
	check("tie broken by source, posted " .. order[1] .. order[2], near(I.Resolve(b, FARM, 0.6), 0.4), I.Resolve(b, FARM, 0.6))
end

-- Scale claims combine but are clamped to +-30%; floors and caps still apply after scaling.
do
	local H, I, b = fresh()
	I.Claim(b, { source = "mood:tilt", tier = "MOOD", mode = FARM, scale = 0.5 })
	I.Claim(b, { source = "mistake:greed", tier = "MOOD", mode = FARM, scale = 0.5 })
	check("scale clamped to 0.7", near(I.Resolve(b, FARM, 0.5), 0.35), I.Resolve(b, FARM, 0.5))
	I.Claim(b, { source = "orders:PUSH", tier = "HUMAN_ORDER", mode = FARM, floor = 0.85 })
	check("order floor not scaled down", near(I.Resolve(b, FARM, 0.5), 0.85), I.Resolve(b, FARM, 0.5))
end

-- SURVIVAL beats a human order unless the order explicitly accepts the risk.
do
	local H, I, b = fresh()
	I.Claim(b, { source = "orders:ROSHAN", tier = "HUMAN_ORDER", mode = ROSHAN, floor = 0.85 })
	I.Claim(b, { source = "guard:hp", tier = "SURVIVAL", mode = ROSHAN, cap = 0 })
	check("survival cap beats order", near(I.Resolve(b, ROSHAN, 0.5), 0), I.Resolve(b, ROSHAN, 0.5))
	I.Claim(b, { source = "orders:ROSHAN", tier = "HUMAN_ORDER", mode = ROSHAN, floor = 0.85, allowRisk = true })
	check("order that allows risk beats survival", near(I.Resolve(b, ROSHAN, 0.5), 0.85), I.Resolve(b, ROSHAN, 0.5))
end

-- Claims without `until` expire after ClaimTTL unless re-posted.
do
	local H, I, b = fresh()
	I.Claim(b, { source = "lane:pull", tier = "LANE_PLAN", mode = FARM, cap = 0.1 })
	T = 0.1
	check("claim live within TTL", near(I.Resolve(b, FARM, 0.5), 0.1))
	T = 0.3
	check("claim gone after TTL", near(I.Resolve(b, FARM, 0.5), 0.5), I.Resolve(b, FARM, 0.5))
end

-- Low HP and a retreat that wants out: every other mode is capped below retreat, even a camp-job floor.
do
	local H, I, b = fresh()
	b.hp = 15
	I.Claim(b, { source = "lane:stack", tier = "CAMP_JOB", mode = FARM, floor = 0.9, ["until"] = 10 })
	local retreat = I.Resolve(b, RETREAT, 0.7)
	local farm = I.Resolve(b, FARM, 0.3)
	check("retreat wins over a lifted floor at low HP", near(farm, 0.65), string.format("farm %.2f retreat %.2f", farm, retreat))
	check("survival leaves an unlifted raw desire alone", near(I.Resolve(b, ROSHAN, 0.9), 0.9), I.Resolve(b, ROSHAN, 0.9))
end
do
	local H, I, b = fresh()
	b.hp = 60
	I.Claim(b, { source = "lane:stack", tier = "CAMP_JOB", mode = FARM, floor = 0.9, ["until"] = 10 })
	I.Resolve(b, RETREAT, 0.7)
	check("healthy bot keeps the camp job", near(I.Resolve(b, FARM, 0.3), 0.9), I.Resolve(b, FARM, 0.3))
end

-- Order shims: the floor and the retreat cap are posted as HUMAN_ORDER claims that beat lower tiers.
do
	local H, I, b = fresh()
	MakeUnit({ pid = 0, bot = false })
	H.Orders.Post(2, { type = "DEFEND", sourceKey = "d", issuerPID = 0, location = Vector(0, 0), lane = Lane.Mid, duration = 20, maxResponders = 1 })
	T = 5
	local defend = BotMode.DefendTowerMid
	I.Claim(b, { source = "intent:stuck", tier = "LANE_PLAN", mode = defend, cap = 0.2, ["until"] = 10 })
	local floor = H.Orders.DesireFloor(b, defend, Lane.Mid)
	check("ordered defend survives a lower-tier cap", near(I.Resolve(b, defend, floor), 0.85), I.Resolve(b, defend, floor))
	I.Claim(b, { source = "lane:stack", tier = "CAMP_JOB", mode = RETREAT, floor = 0.95, ["until"] = 10 })
	local capped = H.Orders.CapRetreatDesire(b, 0.9)
	check("order caps retreat above a lower-tier floor", near(I.Resolve(b, RETREAT, capped), 0.75), I.Resolve(b, RETREAT, capped))
	check("order floor claim lasts only its frame", (function() T = 5.05 return near(I.Resolve(b, defend, 0.4), 0.2) end)())
end

-- Stickiness: full bonus for MinDwell, decays to 0 over the next second, only for the active mode.
do
	local H, I, b = fresh()
	b.mode = FARM
	H.Tick(b)
	T = 0.5
	check("sticky bonus while dwelling", near(I.Resolve(b, FARM, 0.4), 0.46), I.Resolve(b, FARM, 0.4))
	check("no bonus for inactive mode", near(I.Resolve(b, LANING, 0.4), 0.4))
	T = 1.5
	check("bonus half-decayed", near(I.Resolve(b, FARM, 0.4), 0.43), I.Resolve(b, FARM, 0.4))
	T = 2.5
	check("bonus gone", near(I.Resolve(b, FARM, 0.4), 0.4), I.Resolve(b, FARM, 0.4))
	T = 2.6
	H.Tick(b)
	I.Claim(b, { source = "orders:DEFEND", tier = "HUMAN_ORDER", mode = BotMode.DefendTowerMid, floor = 0.85 })
	b.mode = LANING
	H.Tick(b)
	check("an active order bypasses stickiness", near(I.Resolve(b, LANING, 0.4), 0.4), I.Resolve(b, LANING, 0.4))
end

-- Stickiness never lifts a mode past its own cap, nor over a retreat that is already as strong.
do
	local H, I, b = fresh()
	b.mode = FARM
	H.Tick(b)
	T = 0.5
	I.Claim(b, { source = "lane:plan", tier = "LANE_PLAN", mode = FARM, cap = 0.3 })
	check("no sticky bonus over a cap", near(I.Resolve(b, FARM, 0.5), 0.3), I.Resolve(b, FARM, 0.5))
	I.Release(b, "lane:plan", FARM)
	I.Resolve(b, RETREAT, 0.45)
	check("no sticky bonus against a contending retreat", near(I.Resolve(b, FARM, 0.4), 0.4), I.Resolve(b, FARM, 0.4))
	I.Resolve(b, RETREAT, 0.2)
	check("bonus back once retreat is weaker", near(I.Resolve(b, FARM, 0.4), 0.46), I.Resolve(b, FARM, 0.4))
end

-- Thrash limiter: more than 4 switches in 5 s raises the current mode's bonus to 0.12 for 3 s.
do
	local H, I, b = fresh()
	H.Tick(b)
	local modes = { FARM, LANING, FARM, LANING, FARM }
	for i, m in ipairs(modes) do
		T = i * 0.5
		b.mode = m
		H.Tick(b)
	end
	T = 2.5 + 2.5
	check("thrash bonus after the dwell has decayed", near(I.Resolve(b, FARM, 0.4), 0.52), I.Resolve(b, FARM, 0.4))
	T = 2.5 + 3.1
	check("thrash bonus ends", near(I.Resolve(b, FARM, 0.4), 0.4), I.Resolve(b, FARM, 0.4))
	check("one thrash episode counted", I.SummaryLine(b):find("thrash=1") ~= nil, I.SummaryLine(b))
end
do
	local H, I, b = fresh()
	H.Tick(b)
	for i, m in ipairs({ FARM, LANING, FARM, LANING, FARM, LANING, FARM }) do
		T = i * 1.5
		b.mode = m
		H.Tick(b)
	end
	check("slow switching is not thrash", I.SummaryLine(b):find("thrash=0") ~= nil, I.SummaryLine(b))
end

-- Stuck detector against a scripted bot: active farm, desire 0.5, issuing nothing and not moving.
local function runStuck(intent, setup)
	local H, I, b = fresh(intent)
	b.mode, b.desire = FARM, 0.5
	if setup then setup(b) end
	for i = 0, 20 do
		T = 1 + i * 0.1
		I.Resolve(b, FARM, 0.5)
		H.Tick(b)
	end
	return H, I, b
end
do
	local H, I, b = runStuck()
	check("frozen bot detected", I.SummaryLine(b):find("stuck=farm:1") ~= nil, I.SummaryLine(b))
	check("frozen mode yields 0.15", near(I.Resolve(b, FARM, 0.5), 0.35), I.Resolve(b, FARM, 0.5))
	for i = 1, 10 do T = T + 0.1 H.Tick(b) end
	check("one episode while it stays frozen", I.SummaryLine(b):find("stuck=farm:1") ~= nil, I.SummaryLine(b))
end
do
	-- Raw desire 0.2: the stuck cap pulls the active desire below MinDesire, which must not end the episode.
	local H, I, b = fresh()
	b.mode, b.desire = FARM, 0.05
	for i = 0, 60 do
		T = 1 + i * 0.1
		I.Resolve(b, FARM, 0.2)
		H.Tick(b)
	end
	check("one episode for a long low-desire freeze", I.SummaryLine(b):find("stuck=farm:1") ~= nil, I.SummaryLine(b))
end
do
	local H, I, b = runStuck(nil, function(b) b.action = BOT_ACTION_TYPE_MOVE_TO end)
	check("standing still while acting is not stuck by default", I.SummaryLine(b):find("stuck=-") ~= nil, I.SummaryLine(b))
	local H2, I2, b2 = runStuck({ Enable = true, Stuck = { Match = "idle_or_still" } }, function(b) b.action = BOT_ACTION_TYPE_MOVE_TO end)
	check("idle_or_still flags it", I2.SummaryLine(b2):find("stuck=farm:1") ~= nil, I2.SummaryLine(b2))
end
do
	local H, I, b = runStuck(nil, function(b) b.fountainDist = 1000 end)
	check("idle in base is not stuck", I.SummaryLine(b):find("stuck=-") ~= nil, I.SummaryLine(b))
end
do
	local H, I, b = fresh()
	b.mode, b.desire = FARM, 0.5
	for i = 0, 20 do
		T = 1 + i * 0.1
		b.loc = Vector(i * 30, 0)
		H.Tick(b)
	end
	check("moving idle bot is not stuck", I.SummaryLine(b):find("stuck=-") ~= nil, I.SummaryLine(b))
end

-- A Hold that begins during a stuck episode lifts the cap at once instead of leaving it for its Duration.
do
	local H, I, b = runStuck()
	check("precondition: frozen mode is capped", near(I.Resolve(b, FARM, 0.5), 0.35), I.Resolve(b, FARM, 0.5))
	I.Hold(b, "lane:job_wait")
	H.Tick(b)
	check("a new hold releases the stuck cap", near(I.Resolve(b, FARM, 0.5), 0.5), I.Resolve(b, FARM, 0.5))
end

-- A deliberate stand-still (Hold, re-posted each frame) is not a freeze; the timers restart once it ends.
do
	local H, I, b = fresh()
	b.mode, b.desire = FARM, 0.5
	for i = 0, 30 do
		T = 1 + i * 0.1
		I.Hold(b, "lane:job_wait")
		I.Resolve(b, FARM, 0.5)
		H.Tick(b)
	end
	check("held bot is not stuck", I.SummaryLine(b):find("stuck=-") ~= nil, I.SummaryLine(b))
	check("hold source reported", I.HeldBy(b) == "lane:job_wait", I.HeldBy(b))
	for i = 1, 10 do
		T = 4 + i * 0.1
		I.Resolve(b, FARM, 0.5)
		H.Tick(b)
	end
	check("a freeze right after the hold needs its own full After", I.SummaryLine(b):find("stuck=-") ~= nil, I.SummaryLine(b))
	for i = 11, 20 do
		T = 4 + i * 0.1
		I.Resolve(b, FARM, 0.5)
		H.Tick(b)
	end
	check("still frozen past After once the hold is over: stuck", I.SummaryLine(b):find("stuck=farm:1") ~= nil, I.SummaryLine(b))
end
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, Intent = { Enable = false } })
	local b = MakeUnit({ pid = 1, mode = FARM })
	H.Intent.Hold(b, "lane:job_wait")
	check("intent off: Hold records nothing", H.Intent.HeldBy(b) == nil)
end

-- An unsticks claim on another mode (a camp job's farm) takes the active mode's dwell bonus away.
do
	local H, I, b = fresh()
	b.mode = LANING
	H.Tick(b)
	T = 0.5
	check("precondition: laning gets its dwell bonus", near(I.Resolve(b, LANING, 0.66), 0.72), I.Resolve(b, LANING, 0.66))
	I.Claim(b, { source = "lane:camp_job", tier = "CAMP_JOB", mode = FARM, unsticks = true })
	I.Claim(b, { source = "lane:full_pull", tier = "CAMP_JOB", mode = FARM, floor = 0.7, ["until"] = T })
	check("no dwell bonus against a camp job", near(I.Resolve(b, LANING, 0.66), 0.66), I.Resolve(b, LANING, 0.66))
	check("the job's farm floor wins", I.Resolve(b, FARM, 0) > I.Resolve(b, LANING, 0.66))
	b.mode = FARM
	H.Tick(b)
	check("the claim's own mode keeps its bonus", near(I.Resolve(b, FARM, 0), 0.76), I.Resolve(b, FARM, 0))
end

-- Lane orders (LANE_*) have no mode: they post no HUMAN_ORDER claims, so they are no floors and leave stickiness on.
do
	local H, I, b = fresh()
	H.Orders.Post(2, { type = "LANE_FREEZE", sourceKey = "f", issuerPID = 0, lane = Lane.Bot, duration = 60,
		maxResponders = 1, onlyPIDs = { 1 }, delayKind = "chat" })
	T = 5
	check("precondition: the lane order is accepted", H.Orders.GetAcceptedForLane(b, "LANE_FREEZE", Lane.Bot) ~= nil)
	check("lane order gives no mode floor", H.Orders.DesireFloor(b, LANING) == 0 and H.Orders.DesireFloor(b, FARM) == 0)
	check("lane order leaves retreat uncapped", near(H.Orders.CapRetreatDesire(b, 0.9), 0.9))
	b.mode = LANING
	H.Tick(b)
	T = 5.5
	check("lane order leaves stickiness on", near(I.Resolve(b, LANING, 0.4), 0.46), I.Resolve(b, LANING, 0.4))
end

-- End-of-game summary prints once, when an ancient falls.
do
	local H, I, b = fresh()
	local printed, realPrint = {}, print
	print = function(line) table.insert(printed, line) end
	T = 1
	H.Tick(b)
	ANCIENT = { IsAlive = function() return false end, GetHealth = function() return 0 end }
	T = 3
	H.Tick(b)
	T = 5
	H.Tick(b)
	print = realPrint
	local n = 0
	for _, line in ipairs(printed) do if line:find("%[H:intent%] summary") then n = n + 1 end end
	check("summary printed once", n == 1, n)
	ANCIENT = { IsAlive = function() return true end, GetHealth = function() return 4500 end }
end

-- Conflicts are counted once per episode, not once per frame or once per game.
do
	local H, I, b = fresh()
	local function episode(t0)
		for i = 0, 3 do
			T = t0 + i * 0.05
			I.Claim(b, { source = "lane:stack", tier = "CAMP_JOB", mode = FARM, floor = 0.9 })
			I.Claim(b, { source = "orders:DEFEND", tier = "HUMAN_ORDER", mode = FARM, cap = 0.2 })
			I.Resolve(b, FARM, 0.5)
		end
	end
	episode(1)
	T = 2
	I.Resolve(b, FARM, 0.5)
	episode(3)
	check("two conflict episodes", I.SummaryLine(b):find("orders:DEFEND>lane:stack:2") ~= nil, I.SummaryLine(b))
end

-- Units that share a player ID (Meepo, tempest double) are left alone.
do
	local H, I, b = fresh()
	local double = MakeUnit({ pid = 1, modifiers = { modifier_arc_warden_tempest_double = 0 } })
	I.Claim(double, { source = "lane:stack", tier = "CAMP_JOB", mode = FARM, floor = 0.9 })
	check("double posts no claims for the main hero", near(I.Resolve(b, FARM, 0.3), 0.3), I.Resolve(b, FARM, 0.3))
	I.Claim(b, { source = "lane:stack", tier = "CAMP_JOB", mode = FARM, floor = 0.9 })
	check("double's desire passes through", near(I.Resolve(double, FARM, 0.3), 0.3), I.Resolve(double, FARM, 0.3))
	check("main hero still resolved", near(I.Resolve(b, FARM, 0.3), 0.9))
end

-- Kill switches: claims and stickiness set up while enabled are ignored once disabled.
for _, switch in ipairs({ function(cfg) cfg.Intent.Enable = false end, function(cfg) cfg.Enable = false end }) do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, Intent = { Enable = true } })
	local b = MakeUnit({ pid = 1, mode = LANING })
	H.Tick(b)
	H.Intent.Claim(b, { source = "lane:stack", tier = "CAMP_JOB", mode = FARM, floor = 0.9, ["until"] = 10 })
	check("enabled: claim applies", near(H.Intent.Resolve(b, FARM, 0.3), 0.9))
	switch(H.Config.Get())
	check("disabled: raw desire returned", near(H.Intent.Resolve(b, FARM, 0.3), 0.3), H.Intent.Resolve(b, FARM, 0.3))
end

finish()
