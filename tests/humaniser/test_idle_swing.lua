-- Slice idle-swing (lane controller design s5.6): the idle swing's kill time, safety, candidate order, ForceShove parsing, its
-- rank in lane_pick Choose, and Find on a stub lane (pre-deny, the partner's creep first, no swing while a last hit is due, shove).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
local Customize = nil
TEAM_RADIANT, TEAM_DIRE = 2, 3
LANE_TOP, LANE_MID, LANE_BOT = 1, 2, 3
FreshHumaniser({ Enable = false })
Customize = package.loaded["bots/FunLib/custom_loader"]
local Idle = require("bots/FunLib/humaniser/states/idle_swing")
local Pick = require("bots/FunLib/humaniser/states/lane_pick")

-- KillTime: our hits of 30 land at 0.5 s then every 1.5 s on a creep the others take 10 HP a second from.
do
	local hpAt = function(t) return 100 - 10 * t end
	-- 0.5: 95-30=65; 2.0: 80-60=20; 3.5: 65-90<0 -> 3.5
	check("kill time: third hit at 3.5 s", near(Idle.KillTime(hpAt, 0.5, 1.5, 30, 6), 3.5))
	check("kill time: past the horizon is huge", Idle.KillTime(function() return 1000 end, 0.5, 1.5, 30, 6) == math.huge)
	check("kill time: no damage is huge", Idle.KillTime(hpAt, 0.5, 1.5, 0, 6) == math.huge)
	-- Review F1 (isw2_A_on_1, 2026-11-05T23-49-39, pid 5 t=41.0: deny attempts on pre-denied creeps failed why=cd): their creeps
	-- take 50 HP a second from 120. 0.5 s: 95, our hit leaves 65; 2.0 s: 20 - 30 <= 0 before our second hit lands: race lost.
	check("kill time: the others kill it before our next hit, race lost",
		Idle.KillTime(function(t) return 120 - 50 * t end, 0.5, 1.5, 30, 6) == Idle.RACE_LOST)
	check("safe: enemy reach beyond our kill", Idle.SafeFromEnemy(2, 2.5))
	check("unsafe: enemy reaches first", not Idle.SafeFromEnemy(2, 1.5))
	check("safe: no enemy near", Idle.SafeFromEnemy(3.5, math.huge))
end

-- Candidate order: a creep a partner hits first (both laners on one creep, user 06/11/2026), then ranged, then lower HP.
do
	check("order: partner's creep beats a lower ranged one", Idle.Better({ focus = true, ranged = false, hp = 150 }, { focus = false, ranged = true, hp = 50 }))
	check("order: ranged beats melee", Idle.Better({ focus = false, ranged = true, hp = 150 }, { focus = false, ranged = false, hp = 50 }))
	check("order: lower HP within a kind", Idle.Better({ focus = false, ranged = false, hp = 50 }, { focus = false, ranged = false, hp = 60 }))
	check("order: higher HP loses", not Idle.Better({ focus = false, ranged = false, hp = 70 }, { focus = false, ranged = false, hp = 60 }))
end

-- ForceShove tokens.
do
	check("force: bot, both teams", Idle.ForcedIn("bot", TEAM_RADIANT, LANE_BOT) and Idle.ForcedIn("bot", TEAM_DIRE, LANE_BOT))
	check("force: r:bot is Radiant only", Idle.ForcedIn("r:bot", TEAM_RADIANT, LANE_BOT) and not Idle.ForcedIn("r:bot", TEAM_DIRE, LANE_BOT))
	check("force: list", Idle.ForcedIn("d:top, mid", TEAM_DIRE, LANE_TOP) and Idle.ForcedIn("d:top, mid", TEAM_RADIANT, LANE_MID))
	check("force: other lane no", not Idle.ForcedIn("bot", TEAM_RADIANT, LANE_TOP))
	check("force: all", Idle.ForcedIn("all", TEAM_DIRE, LANE_MID))
	check("force: empty and nil off", not Idle.ForcedIn("", TEAM_RADIANT, LANE_BOT) and not Idle.ForcedIn(nil, TEAM_RADIANT, LANE_BOT))
end

-- Choose: the idle swing only when nothing else is chosen and no attempt waits; asked lazily.
do
	local function target(kind, eta) return { creep = {}, kind = kind, eta = eta, due = eta, walk = 0, dies = math.huge, ranged = false } end
	local idle = target("prehit", 0)
	local asked = 0
	local thunk = function() asked = asked + 1 return idle end
	local lh, dn = target("lasthit", 0.3), target("deny", 0)
	check("rank: a last hit beats the idle swing", Pick.Choose({ lh }, nil, nil, nil, thunk) == lh)
	check("rank: a deny beats the idle swing", Pick.Choose({ dn }, nil, nil, nil, thunk) == dn)
	check("rank: not asked while something is chosen", asked == 0)
	local pre = target("prehit", 0)
	check("rank: a tower pre-hit beats the idle swing", Pick.Choose({}, nil, nil, pre, thunk) == pre)
	check("rank: nothing offered, the idle swing", Pick.Choose({}, nil, nil, nil, thunk) == idle and asked == 1)
	check("rank: never replaces a wait", Pick.Choose({}, lh, nil, nil, thunk) == nil)
	check("rank: no thunk, nothing", Pick.Choose({}) == nil)
end

-- Find on a stub lane: a bot at (0,0), range 500, damage 40, 1.5 s per attack; units at points along x.
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
GetTower = GetTower or function() return nil end
GetUnitToUnitDistance = function(a, b) return dist(a.loc, b.loc) end
local S = {}
S.__index = S
function S:GetTeam() return self.team end
function S:GetAssignedLane() return LANE_BOT end
function S:IsNull() return false end
function S:IsAlive() return true end
function S:CanBeSeen() return true end
function S:GetLocation() return self.loc end
function S:GetHealth() return self.hp end
function S:GetMaxHealth() return self.maxhp or 550 end
function S:GetUnitName() return self.name or "npc_dota_creep_goodguys_melee" end
function S:GetActualIncomingDamage(d) return d end
function S:GetAttackTarget() return self.target end
function S:GetAttackRange() return self.range or 150 end
function S:GetCurrentMovementSpeed() return 300 end
function S:GetAttackPoint() return 0.4 end
function S:GetAttackDamage() return 40 end
function S:GetSecondsPerAttack() return 1.5 end
function S:GetPlayerID() return self.pid or 0 end
function S:GetDenies() return 0 end
function S:GetLastHits() return 0 end
function S:GetNearbyLaneCreeps(r, enemy)
	local out = {}
	for _, c in ipairs(self.world.creeps) do
		if (c.team ~= self.team) == enemy and dist(c.loc, self.loc) <= r then out[#out + 1] = c end
	end
	return out
end
function S:GetNearbyHeroes(r, enemy)
	local out = {}
	for _, h in ipairs(self.world.heroes) do
		if (h.team ~= self.team) == enemy and dist(h.loc, self.loc) <= r then out[#out + 1] = h end
	end
	return out
end
function S:GetNearbyTowers(r, enemy)
	local out = {}
	for _, t in ipairs(self.world.towers or {}) do
		if (t.team ~= self.team) == enemy and dist(t.loc, self.loc) <= r then out[#out + 1] = t end
	end
	return out
end
local function unit(o) return setmetatable(o, S) end
local function world(o)
	local w = { creeps = o.creeps or {}, heroes = o.heroes or {} }
	local bot = unit({ team = TEAM_RADIANT, loc = Vector(0, 0), range = 500, hp = 600, world = w })
	w.heroes[#w.heroes + 1] = bot
	return bot, w
end
local function verbs(offers)
	return {
		laneTargets = function() return offers or {} end,
		hpForecast = function(_, c) return { c = c } end,
		forecastHp = function(f) return f.c.hp end,
		ownHitTime = function() return 0.4 end,
	}
end

do
	-- Our melee creep at 200 HP (36%) 300 away: three of our hits (0.4, 1.9, 3.4 s... 40 each, 200 HP: five hits) -> past 6 s
	-- the kill time is huge; with no enemy hero near it is still safe.
	local c = unit({ team = TEAM_RADIANT, loc = Vector(300, 0), hp = 200 })
	local bot = world({ creeps = { c } })
	local t = Idle.Find(bot, verbs())
	check("find: our creep under half HP, no enemy near: pre-deny", t ~= nil and t.creep == c and t.kind == "prehit")
	local n = Idle.Of(0, c)
	check("find: the note says predeny, mode safe", n ~= nil and n.kind == "predeny" and n.mode == "safe" and n.reach == math.huge)
end

do
	-- Above half HP: no pre-deny (Dota forbids attacking it).
	local c = unit({ team = TEAM_RADIANT, loc = Vector(300, 0), hp = 300 })
	local bot = world({ creeps = { c } })
	check("find: above half HP, none", Idle.Find(bot, verbs()) == nil)
end

do
	-- 40 HP, our hit 40: one hit kills it, so it is a deny (the deny pick's, with its claim), not a pre-deny. Log
	-- isw1_A_on_1 (2026-11-05T23-31-10, t=35.4 pid=5 hp=25): pre-deny swings at deny-range creeps lost them to the deny's timing.
	local c = unit({ team = TEAM_RADIANT, loc = Vector(300, 0), hp = 40 })
	local bot = world({ creeps = { c } })
	check("find: in one-hit range it is a deny, no pre-deny", Idle.Find(bot, verbs()) == nil)
	c.hp = 41
	check("find: one HP above one hit, pre-deny", Idle.Find(bot, verbs()) ~= nil)
	-- 120 HP under their creeps' 50 a second (our hits 40 at 0.4 s, then every 1.5 s): 100 at 0.4, 60 left after ours;
	-- 1.9 s: 25 - 40 <= 0 before our second hit lands. The deny would come due on our cooldown: no pre-deny.
	c.hp = 120
	local v = verbs()
	v.forecastHp = function(f, t) return f.c.hp - 50 * t end
	check("find: the others kill it before our next hit, no pre-deny", Idle.Find(bot, v) == nil)
	check("find: the same creep with no other damage, pre-deny", Idle.Find(bot, verbs()) ~= nil)
end

do
	-- 70 HP: two of our hits (0.4 s: 30 left, 1.9 s: dead). An enemy hero 200 from it, range 150, reaches in 0.17+0.4 s: unsafe.
	local c = unit({ team = TEAM_RADIANT, loc = Vector(300, 0), hp = 70 })
	local e = unit({ team = TEAM_DIRE, loc = Vector(500, 0), range = 150 })
	local bot = world({ creeps = { c }, heroes = { e } })
	check("find: an enemy hero reaches it first, none", Idle.Find(bot, verbs()) == nil)
	-- The same enemy 1,400 away (reach about 4.3 s): safe.
	e.loc = Vector(1700, 0)
	check("find: the enemy far, pre-deny", Idle.Find(bot, verbs()) ~= nil)
end

do
	-- Two candidates: a lower melee and a higher one an allied hero is hitting: the partner's creep is taken.
	local low = unit({ team = TEAM_RADIANT, loc = Vector(300, 0), hp = 100 })
	local hit = unit({ team = TEAM_RADIANT, loc = Vector(350, 0), hp = 200 })
	local ally = unit({ team = TEAM_RADIANT, loc = Vector(400, 100), target = hit })
	local bot = world({ creeps = { low, hit }, heroes = { ally } })
	local t = Idle.Find(bot, verbs())
	check("find: the creep the partner hits comes first", t ~= nil and t.creep == hit and Idle.Of(0, hit).focus == true)
end

do
	-- A last hit due within our attack cycle (walk 0 + hit 0.4 + 1.5 s) stops the swing; one the claims filter refuses does not.
	local c = unit({ team = TEAM_RADIANT, loc = Vector(300, 0), hp = 200 })
	local bot = world({ creeps = { c } })
	local lh = { creep = {}, kind = "lasthit", eta = 1.2, due = 1.2, walk = 0, dies = math.huge, ranged = false }
	check("find: a last hit due in the cycle, none", Idle.Find(bot, verbs({ lh })) == nil)
	check("find: not mine, the swing goes", Idle.Find(bot, verbs({ lh }), function(o) return o.kind == "deny" end) ~= nil)
	local late = { creep = {}, kind = "lasthit", eta = 2.5, due = 2.5, walk = 0, dies = math.huge, ranged = false }
	check("find: a last hit due after the cycle, the swing goes", Idle.Find(bot, verbs({ late })) ~= nil)
end

do
	-- ForceShove on our lane: the swing is on an enemy creep (the lowest HP), and our low creep is left alone.
	Customize.Overrides.ForceShove = "r:bot"
	local ours = unit({ team = TEAM_RADIANT, loc = Vector(300, 0), hp = 100 })
	local a = unit({ team = TEAM_DIRE, loc = Vector(400, 0), hp = 400, name = "npc_dota_creep_badguys_melee" })
	local b = unit({ team = TEAM_DIRE, loc = Vector(450, 0), hp = 300, name = "npc_dota_creep_badguys_melee" })
	local bot = world({ creeps = { ours, a, b } })
	local t = Idle.Find(bot, verbs())
	check("shove: the lowest enemy creep", t ~= nil and t.creep == b, t and tostring(t.creep.hp))
	check("shove: the note says shove", Idle.Of(0, b) ~= nil and Idle.Of(0, b).mode == "shove")
	Customize.Overrides.ForceShove = ""
	check("shove off: back to the pre-deny", Idle.Find(bot, verbs()) ~= nil and Idle.Of(0, ours) ~= nil)
end

do
	-- Ours.PreDeny off: no pre-deny; a forced shove still swings.
	Customize.Ours.PreDeny = false
	local c = unit({ team = TEAM_RADIANT, loc = Vector(300, 0), hp = 200 })
	local bot = world({ creeps = { c } })
	check("switch off: no pre-deny", Idle.Find(bot, verbs()) == nil)
	Customize.Ours.PreDeny = true
end

-- Slice lane-control 2b: the controller's mode and its setup lever. A setup is an enemy creep our next hit does not kill, whose
-- kill by our hits (SETUP_HITS at most) comes before any enemy hero reaches it; with none on offer, the pre-deny.
do
	local Ctl = require("bots/FunLib/humaniser/lane_control")
	Customize.Ours.LaneControl = true
	Customize.Ours.LaneControlDrive = true
	local now = 300
	DotaTime = function() return now end
	local function decide(mode, intent, levers)
		local who = {}
		for i = 1, #levers do who[i] = "core" end
		Ctl.Remember(TEAM_RADIANT, LANE_BOT, { wave = 300, at = 302, rule = "R1", mode = mode, intent = intent, levers = levers, who = who, cx = 0, cy = 0 })
	end
	check("hits to: kill on the third hit", Idle.HitsTo(3.4, 0.4, 1.5) == 3)
	check("setup order: fewer hits first", Idle.BetterSetup({ hits = 2, ranged = false, hp = 90 }, { hits = 3, ranged = true, hp = 50 }))
	check("setup order: ranged within the same hits", Idle.BetterSetup({ hits = 2, ranged = true, hp = 90 }, { hits = 2, ranged = false, hp = 50 }))
	-- Their melee creep at 100 HP (our 40: 0.4 s 60 left, 1.9 s 20, 3.4 s dead: three hits) 300 away, no enemy hero near.
	local theirs = unit({ team = TEAM_DIRE, loc = Vector(300, 0), hp = 100, name = "npc_dota_creep_badguys_melee" })
	local ours = unit({ team = TEAM_RADIANT, loc = Vector(250, 0), hp = 200 })
	local bot = world({ creeps = { theirs, ours } })
	decide("safe", "forward", { "setup" })
	local t = Idle.Find(bot, verbs())
	check("setup: the enemy creep", t ~= nil and t.creep == theirs and Idle.Of(0, theirs) ~= nil and Idle.Of(0, theirs).kind == "setup")
	check("setup: three hits noted", Idle.Of(0, theirs).hits == 3)
	theirs.hp = 40
	check("setup: in one-hit range it is the last-hit pick's, so the pre-deny", Idle.Find(bot, verbs()) ~= nil and Idle.Of(0, ours) ~= nil)
	theirs.hp = 200
	check("setup: five hits is too many, so the pre-deny", Idle.Find(bot, verbs()) ~= nil and Idle.Of(0, ours) ~= nil)
	theirs.hp = 100
	local e = unit({ team = TEAM_DIRE, loc = Vector(500, 0), range = 150 })
	bot.world.heroes[#bot.world.heroes + 1] = e
	-- (our creep is unsafe too: the hero reaches it in 0.73 s, so nothing is swung)
	local r = Idle.Find(bot, verbs())
	check("setup: an enemy hero could deny it first, no setup", r == nil or r.creep ~= theirs)
	e.loc = Vector(3000, 0)
	bot.world.towers = { unit({ team = TEAM_DIRE, loc = Vector(900, 0) }) }
	check("setup: their creep inside their tower's range, so the pre-deny", Idle.Find(bot, verbs()) ~= nil and Idle.Of(0, ours) ~= nil)
	bot.world.towers = nil
	decide("safe", "back", { "predeny" })
	check("back: no setup, the pre-deny", Idle.Find(bot, verbs()) ~= nil and Idle.Of(0, ours) ~= nil)
	decide("shove", "forward", { "shove" })
	check("controller shove: the mode is shove", Idle.ModeOf(bot) == "shove")
	local ts = Idle.Find(bot, verbs())
	check("controller shove: an enemy creep", ts ~= nil and ts.creep == theirs and Idle.Of(0, theirs).kind == "shove")
	now = 340
	check("decision expired: safe", Idle.ModeOf(bot) == "safe")
	now = 310
	Customize.Ours.LaneControlDrive = false
	check("drive off: safe", Idle.ModeOf(bot) == "safe")
	Customize.Ours.LaneControlDrive = true
	check("drive on again: shove", Idle.ModeOf(bot) == "shove")
	Ctl.ResetCache()
end

-- Spent swings for the later deny's `pre`.
do
	local c = {}
	check("spent: none yet", Idle.SpentOn(7, c) == nil)
	Idle.NoteSwing(7, c)
	Idle.NoteSwing(7, c)
	check("spent: two swings", Idle.SpentOn(7, c) == 2)
end

finish()
