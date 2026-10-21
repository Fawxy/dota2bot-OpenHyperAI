dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, Team = dota.Lane, dota.Team

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetMostRecentPing() return self.ping or { time = 0, location = Vector(0, 0), normal_ping = true } end

local FRONT = Vector(0, -5000)

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = o.loc or FRONT })
	u.lane, u.pos = o.lane, o.pos
	return u
end

-- Radiant bot lane: the core (pid 1, pos 1) and the support (pid 5, pos 5) at the lane front.
local function world(laneCfg, opts)
	opts = opts or {}
	local H = LaneFresh(laneCfg or { Enable = true }, { skill = opts.skill })
	T = 100
	CURRENT_TEAM = 2
	OBSERVER = 1
	local core = unit({ pid = 1, bot = opts.humanCore ~= true, lane = Lane.Bot, pos = 1 })
	local support = unit({ pid = 5, bot = opts.humanSupport ~= true, lane = Lane.Bot, pos = 5, loc = opts.supportLoc })
	return H, core, support, H.Lane.LaneState, H.Lane.LanePlan
end

local function snapshot(S, observer)
	return S.Get(2, Lane.Bot, observer)
end

local function enemyCreep(hp)
	return MakeCreep({ team = 3, x = 200, y = -5000, hp = hp })
end

-- A human core attacks full-HP enemy creeps every 0.5 s from t=100 to t=107 (the shove signal is reached
-- after four hits; the 5 s hysteresis then lapses at t=106.5). Returns the last snapshot.
local function humanShoveUntil(H, core, support, S, untilT)
	local creep = enemyCreep(550)
	core.target = creep
	local s
	while T <= untilT do
		s = snapshot(S, support)
		T = T + 0.5
	end
	T = T - 0.5
	return s
end

local function post(H, type_, lane, key, pids, duration)
	return H.Orders.Post(2, { type = type_, sourceKey = key, issuerPID = 0, lane = lane, duration = duration or 90,
		maxResponders = #pids, onlyPIDs = pids, delayKind = "chat" })
end

do
	local H, _, _, _, P = world()
	local base = { skill = 0.8, laneScore = -0.5, eqPos = -0.5, stronger = true, rotating = false, enemyLaners = 1 }
	local function with(over) local i = {} for k, v in pairs(base) do i[k] = v end for k, v in pairs(over) do i[k] = v end return i end
	check("freeze conditions pick FREEZE", P.PickCorePlan(base) == "FREEZE")
	check("rotating beats freeze conditions", P.PickCorePlan(with({ rotating = true })) == "SHOVE")
	check("below the freeze gate holds", P.PickCorePlan(with({ skill = 0.6 })) == "HOLD")
	check("not stronger holds", P.PickCorePlan(with({ stronger = false })) == "HOLD")
	check("eq above the freeze max holds", P.PickCorePlan(with({ eqPos = -0.2 })) == "HOLD")
	check("no enemy laner and negative score shoves", P.PickCorePlan(with({ enemyLaners = 0 })) == "SHOVE")
	check("no enemy laner but positive score holds", P.PickCorePlan(with({ enemyLaners = 0, laneScore = 0.2 })) == "HOLD")
end

do
	local _, _, _, _, P = world()
	local function tally(o)
		local t = P.NewTally()
		for k, v in pairs(o) do t[k] = v end
		return t
	end
	check("five shove hits shove", P.ClassifyTally(tally({ shoveHits = 5, samples = 5 })) == "SHOVE")
	check("denies at low eq freeze", P.ClassifyTally(tally({ denies = 3, eqSum = -3.6, samples = 6 })) == "FREEZE")
	check("denies at mild eq do not freeze", P.ClassifyTally(tally({ denies = 3, eqSum = -1.2, samples = 6 })) ~= "FREEZE")
	check("any shove hit blocks freeze", P.ClassifyTally(tally({ shoveHits = 1, denies = 3, eqSum = -3.6, samples = 6 })) ~= "FREEZE")
	check("aggro plus step back holds", P.ClassifyTally(tally({ aggroDraws = 1, stepBacks = 1, samples = 2 })) == "HOLD")
	check("only last hits stay neutral", P.ClassifyTally(tally({ lastHitTries = 8, samples = 8 })) == "NEUTRAL")
end

do
	local _, _, _, _, P = world()
	local inf = P.NewInference()
	for t = 0, 19 do inf = P.Step(inf, t % 2 == 0 and "SHOVE" or "NEUTRAL", t) end
	check("alternating candidates never switch", inf.current == "NEUTRAL", inf.current)
	local switchedAt
	for t = 20, 30 do
		inf = P.Step(inf, "SHOVE", t)
		if inf.current == "SHOVE" and switchedAt == nil then switchedAt = t end
	end
	check("sustained shove switches after 5 s", switchedAt == 25, switchedAt)
	local freezeAt
	for t = 26, 50 do
		inf = P.Step(inf, "FREEZE", t)
		if inf.current == "FREEZE" and freezeAt == nil then freezeAt = t end
	end
	check("new plan waits out the 15 s dwell", freezeAt == 40, freezeAt)
end

do
	local H, core, support, S, P = world(nil, { humanCore = true })
	local s = humanShoveUntil(H, core, support, S, 104)
	check("not inferred before the sustain window", P.View(support, s).plan == "NEUTRAL", P.View(support, s).plan)
	s = humanShoveUntil(H, core, support, S, 107)
	local v = P.View(support, s)
	check("human shoving is inferred", v.plan == "SHOVE" and v.source == "inferred" and v.coreIsHuman and v.corePid == 1, P.Describe(v))
end

do
	local H, core, support, S, P = world(nil, { humanCore = true })
	core.target = enemyCreep(40)
	local s
	for _ = 1, 15 do s = snapshot(S, support) T = T + 0.5 end
	check("last-hit attempts alone do not infer a shove", P.View(support, s).plan == "NEUTRAL", P.View(support, s).plan)
end

do
	local H, core, support, S, P = world(nil, { humanCore = true })
	local s = humanShoveUntil(H, core, support, S, 107)
	check("precondition: shove inferred", P.View(support, s).plan == "SHOVE")
	post(H, "LANE_FREEZE", Lane.Bot, "freeze1", { 5 })
	check("order not yet read keeps the inferred plan", P.View(support, s).plan == "SHOVE")
	T = T + 20
	s = snapshot(S, support)
	local v = P.View(support, s)
	check("accepted order overrides the inference", v.plan == "FREEZE" and v.source == "order", P.Describe(v))
end

do
	local H = world()
	unit({ pid = 6, bot = true, lane = Lane.Mid, pos = 2 })
	post(H, "LANE_SHOVE", Lane.Mid, "mid", { 6 })
	post(H, "LANE_SHOVE", Lane.Bot, "bot1", { 5 })
	post(H, "LANE_FREEZE", Lane.Bot, "bot2", { 5 })
	local active = H.Orders.GetActive(2)
	local byLane = {}
	for _, o in ipairs(active) do byLane[o.lane] = (byLane[o.lane] or "") .. o.type end
	check("freeze replaces shove in its lane", byLane[Lane.Bot] == "LANE_FREEZE", byLane[Lane.Bot])
	check("other lanes untouched", byLane[Lane.Mid] == "LANE_SHOVE" and #active == 2, #active)
	post(H, "LANE_PULL", Lane.Bot, "p1", { 5 })
	post(H, "LANE_NOPULL", Lane.Bot, "p2", { 5 })
	local pulls = {}
	for _, o in ipairs(H.Orders.GetActive(2)) do if o.lane == Lane.Bot then table.insert(pulls, o.type) end end
	table.sort(pulls)
	check("nopull replaces pull", table.concat(pulls, ",") == "LANE_FREEZE,LANE_NOPULL", table.concat(pulls, ","))
end

do
	local H, _, support = world()
	post(H, "LANE_FREEZE", Lane.Bot, "f", { 5 })
	T = T + 20
	check("freeze accepted", H.Orders.GetAcceptedForLane(support, "LANE_FREEZE", Lane.Bot) ~= nil)
	check("accepted lane order alone is no executed order", H.Orders.GetFor(support) == nil)
	check("accepted for its own lane only", H.Orders.GetAcceptedForLane(support, "LANE_FREEZE", Lane.Top) == nil)
	H.Orders.Post(2, { type = "PUSH", sourceKey = "push", issuerPID = 0, lane = Lane.Bot, duration = 60, maxResponders = 1, onlyPIDs = { 5 }, delayKind = "chat" })
	T = T + 20
	local executed = H.Orders.GetFor(support)
	check("lane order does not hide an executed order", executed ~= nil and executed.type == "PUSH", executed and executed.type)
	check("lane order still adopted next to it", H.Orders.GetAcceptedForLane(support, "LANE_FREEZE", Lane.Bot) ~= nil)
end

do
	local H, _, support = world()
	support.alive = false
	post(H, "LANE_SHOVE", Lane.Bot, "dead", { 5 })
	T = T + 20
	check("a dead bot still adopts the lane order", H.Orders.GetAcceptedForLane(support, "LANE_SHOVE", Lane.Bot) ~= nil)
end

-- Commands and pings
local function humanTeam(laneCfg)
	local H = LaneFresh(laneCfg or { Enable = true })
	T = 100
	CURRENT_TEAM = 2
	local human = MakeUnit({ pid = 0, bot = false, loc = Vector(0, -4000) })
	local bots = {
		unit({ pid = 1, lane = Lane.Bot, pos = 1 }),
		unit({ pid = 2, lane = Lane.Bot, pos = 5 }),
		unit({ pid = 3, lane = Lane.Top, pos = 3, loc = Vector(0, 5000) }),
		unit({ pid = 4, lane = Lane.Mid, pos = 2, loc = Vector(0, 0) }),
	}
	return H, human, bots
end
local function say(pid, text)
	T = T + 0.5
	for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = pid, string = text, team_only = true }) end
end
local function ids(list) local r = {} for _, v in ipairs(list) do table.insert(r, v) end table.sort(r) return table.concat(r, ",") end

do
	local H, _, bots = humanTeam({ Enable = true, Plan = false })
	local said = {}
	H.Orders.SetAnnouncer(function(bot, key) table.insert(said, key) end)
	for _, b in ipairs(bots) do H.Tick(b) end
	say(0, "!freeze bot")
	check("lane commands are ignored with Plan off", #H.Orders.GetActive(2) == 0)
	say(0, "!bhelp")
	for _ = 1, 3 do
		T = T + 11
		for _, b in ipairs(bots) do H.Tick(b) end
	end
	check("help is unchanged with Plan off", #said == 1 and said[1] == "say_cmd_help", table.concat(said, " "))
end

do
	local H, _, bots = humanTeam()
	local said = {}
	H.Orders.SetAnnouncer(function(bot, key) table.insert(said, key) end)
	for _, b in ipairs(bots) do H.Tick(b) end
	say(0, "!freeze bot")
	local list = H.Orders.GetActive(2)
	local o = list[1]
	check("freeze posts a lane order", #list == 1 and o.type == "LANE_FREEZE" and o.lane == Lane.Bot and o.duration == 90, o and o.type)
	check("only the lane's bots respond", o and ids(o.responders) == "1,2", o and ids(o.responders))
	say(0, "!nopull")
	local nopull
	for _, x in ipairs(H.Orders.GetActive(2)) do if x.type == "LANE_NOPULL" then nopull = x end end
	check("default lane is the one nearest the issuer", nopull and nopull.lane == Lane.Bot and nopull.duration == 120)
	say(0, "!stack top")
	local stack
	for _, x in ipairs(H.Orders.GetActive(2)) do if x.type == "LANE_STACK" then stack = x end end
	check("explicit lane word wins", stack and stack.lane == Lane.Top and ids(stack.responders) == "3" and stack.duration == 60)
	say(0, "!2 shove bot")
	local shove
	for _, x in ipairs(H.Orders.GetActive(2)) do if x.type == "LANE_SHOVE" then shove = x end end
	check("a selector targets one bot", shove and ids(shove.responders) == "1", shove and ids(shove.responders))
	say(0, "!bhelp")
	for _ = 1, 3 do
		T = T + 11
		for _, b in ipairs(bots) do H.Tick(b) end
	end
	local help = {}
	for _, key in ipairs(said) do if key:find("^say_cmd_help") then table.insert(help, key) end end
	check("help adds the lane line", table.concat(help, ",") == "say_cmd_help,say_cmd_help_lane", table.concat(said, " "))
	check("lane orders are acknowledged with their own line", table.concat(said, " "):find("say_order_ack_lane_stack", 1, true) ~= nil, table.concat(said, " "))
end

do
	local function pinged(laneCfg, laning, at)
		local H, human = humanTeam(laneCfg)
		LANING = laning
		T = 10
		human.ping = { time = 10, location = at, normal_ping = true }
		H.Pings.Scan(2)
		return H.Orders.GetActive(2)[1]
	end
	local o = pinged({ Enable = true }, true, Vector(100, -5000))
	check("lane front ping hands off", o and o.type == "LANE_HANDSOFF" and o.lane == Lane.Bot and o.duration == 30, o and o.type)
	check("hands off goes to that lane's bots", o and ids(o.onlyPIDs) == "1,2")
	o = pinged({ Enable = true, Plan = false }, true, Vector(100, -5000))
	check("Plan off keeps the gather", o and o.type == "GATHER", o and o.type)
	o = pinged({ Enable = true }, false, Vector(100, -5000))
	check("after laning keeps the gather", o and o.type == "GATHER", o and o.type)
	o = pinged({ Enable = true }, true, Vector(100, -2500))
	check("away from every front keeps the gather", o and o.type == "GATHER", o and o.type)
end

-- Misread: SHOVE inferred from a human core that also steps back each sample, so HOLD is the runner-up.
local function misreadWorld(skill)
	local H, core, support, S, P = world(nil, { humanCore = true, skill = skill })
	core.extrap = Vector(-300, -5000)
	local s = humanShoveUntil(H, core, support, S, 107)
	return H, support, s, P
end
do
	local _, support, s, P = misreadWorld(0)
	check("precondition: shove inferred", P.View(support, s).plan == "SHOVE")
	RANDOM_FRACTION = 0.1
	local v = P.ForSupport(support, s)
	check("low skill misreads to the runner-up plan", v.plan == "HOLD" and v.source == "inferred", P.Describe(v))
	RANDOM_FRACTION = 0.9
	check("one roll per wave cycle", P.ForSupport(support, s).plan == "HOLD")
	RANDOM_FRACTION = nil
end
do
	local _, support, s, P = misreadWorld(0)
	RANDOM_FRACTION = 0.5
	check("roll above the window reads correctly", P.ForSupport(support, s).plan == "SHOVE")
	RANDOM_FRACTION = nil
end
do
	local _, support, s, P = misreadWorld(1)
	RANDOM_FRACTION = 0.1
	check("high skill rarely misreads", P.ForSupport(support, s).plan == "SHOVE")
	RANDOM_FRACTION = nil
end
do
	local H, core, support, S, P = world(nil, { humanCore = true, skill = 0 })
	core.target = enemyCreep(550)
	local s
	while T <= 107 do s = snapshot(S, support) T = T + 0.5 end
	post(H, "LANE_FREEZE", Lane.Bot, "f", { 5 })
	T = T + 20
	s = snapshot(S, support)
	RANDOM_FRACTION = 0.01
	check("orders are never misread", P.ForSupport(support, s).plan == "FREEZE")
	RANDOM_FRACTION = nil
end

-- Human pulling
do
	local function spawner(x, y)
		return { team = Team.Radiant, type = "small", location = Vector(x, y, 0), min = Vector(x - 150, y - 150, 0), max = Vector(x + 150, y + 150, 0), speed = 0 }
	end
	local H, core, human, S, P = world(nil, { humanSupport = true, supportLoc = Vector(-1600, -5000) })
	SPAWNERS = { spawner(-1600, -5000) }
	H.Lane.Camps.ResetCache()
	check("seed pull camp resolved", #H.Lane.Camps.PullCampsFor(Team.Radiant, Lane.Bot) == 1)
	T = 14
	local s = snapshot(S, core)
	check("human at the camp in the pull window blocks bot pulls", P.View(core, s).pullAllowed == false)
	T = 29
	s = snapshot(S, core)
	check("block lasts the rest of the cycle", P.View(core, s).pullAllowed == false)
	T = 55
	s = snapshot(S, core)
	check("next cycle outside the window allows pulls", P.View(core, s).pullAllowed == true)
	human.loc = Vector(-600, -5000)
	T = 75
	s = snapshot(S, core)
	check("human too far from the camp allows pulls", P.View(core, s).pullAllowed == true)
end

-- Rotation is read live
do
	local H, core, support, S, P = world()
	MakeUnit({ pid = 6, team = 3, loc = Vector(200, -5000) })
	local s = snapshot(S, support)
	local before = P.View(support, s)
	check("no rotation: the bot core holds", before.plan == "HOLD" and before.source == "picked", P.Describe(before))
	H.Lane.Hooks.SetRotationProbe(function(b) return b == core end)
	local after = P.View(support, s)
	check("a rotation probe changes the plan within the same snapshot", after.plan == "SHOVE", P.Describe(after))
end

finish()
