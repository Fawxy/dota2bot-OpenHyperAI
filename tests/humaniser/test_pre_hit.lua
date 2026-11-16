-- Slice pre-hit: the plan of our swings against a tower's hits (states/pre_hit Plan) and the pre-hit's rank in lane_pick Choose.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local PreHit = require("bots/FunLib/humaniser/states/pre_hit")
local Pick = require("bots/FunLib/humaniser/states/lane_pick")

-- Our tower: 80 after armour every 0.81 s, the first landing at `first` (default 0.3 s); the creep's forecast HP without our
-- hits, and the landing times the engine's forecast would list within the horizon.
local TOWER, TOWER_PERIOD = 80, 0.81
local function tower(hp, first)
	first = first or 0.3
	local hpAt = function(t)
		local n = t >= first and math.floor((t - first) / TOWER_PERIOD) + 1 or 0
		return hp - TOWER * n
	end
	local lands = {}
	for k = 0, 10 do
		local t = first + k * TOWER_PERIOD
		if t <= PreHit.HORIZON then lands[#lands + 1] = t end
	end
	return hpAt, lands
end

-- The plans below to "Choose" read the forecast as exact (NoError): the search itself. The fitted error's checks follow them.
-- Our core: 54 at the low roll, 60 mean, first landing at 0.6 s, 1.4 s between attacks (an early-game ranged core).
local LO, MEAN, FIRST, PERIOD = 54, 60, 0.6, 1.4
local function plan(hp, opts)
	opts = opts or {}
	local hpAt, lands = tower(hp, opts.towerFirst)
	return PreHit.Plan(hpAt, PreHit.HORIZON, lands, FIRST, opts.period or PERIOD, LO, MEAN, opts.err or PreHit.NoError)
end
local function near(a, b) return math.abs(a - b) < 1e-6 end

-- 388 HP (prhchk5 game A, t=90.2): the tower steps it 308, 228, 148, 68, dead: never in (0, 54]. One hit of ours at 0.6 s
-- makes 248, 168, 88, 8: the kill lands after the fourth tower hit (2.73 s) on 8 HP. Every plan here ends on 8 (the final HP
-- is set by how many hits land, not when), so the earliest pre-hit is taken: go.
do
	local p = plan(388)
	check("plan 388: a pre-hit now then the kill", p ~= nil and #p.swings == 2 and near(p.swings[1], FIRST))
	check("plan 388: the kill lands just after the fourth tower hit", p ~= nil and near(p.swings[2], 0.3 + 3 * TOWER_PERIOD + PreHit.AFTER))
	check("plan 388: on 8 HP, margin 8", p ~= nil and near(p.hpKill, 8) and near(p.margin, 8))
end

-- 360 HP: the tower alone leaves 40 after its fourth hit, inside our range with 14 to spare either side, better than any plan
-- with a hit of ours. The first swing is the kill, later than now: the last-hit verb's, no pre-hit (wait).
do
	local p = plan(360)
	check("plan 360: one swing, the kill", p ~= nil and #p.swings == 1)
	check("plan 360: it waits for the tower's fourth hit", p ~= nil and p.swings[1] > FIRST and near(p.swings[1], 0.3 + 3 * TOWER_PERIOD + PreHit.AFTER))
	check("plan 360: lands on 40 with margin 14", p ~= nil and near(p.hpKill, 40) and near(p.margin, 14))
end

-- 130 HP: 50 once the tower's first hit lands at 0.3 s, so a swing landing now (0.6 s) kills: the plan is that one swing.
do
	local p = plan(130)
	check("plan 130: kill now", p ~= nil and #p.swings == 1 and near(p.swings[1], FIRST) and near(p.hpKill, 50))
end

-- A tower hit landing inside AFTER before our swing would land is not relied on: the swing is planned just after it instead.
do
	local p = plan(130, { towerFirst = FIRST - 0.05 })
	check("plan: a swing is not planned within AFTER of a tower hit", p ~= nil and near(p.swings[1], FIRST - 0.05 + PreHit.AFTER))
end

-- 300 HP is 60 + 3 x 80 exactly: with one hit of ours the tower's third hit leaves 0, without it the fourth leaves -20 and the
-- third 60, above our range; two hits cannot both land before the tower's third. No plan ends in a kill.
check("plan 300: no plan", plan(300) == nil)

-- Margin decides: a faster core (0.9 s between attacks) on 388 HP can pre-hit twice (0.6 s and 1.5 s) and kill at 2.4 s on 28
-- HP (margin 26), better than one pre-hit and the kill on 8 (margin 8).
do
	local p = plan(388, { period = 0.9 })
	check("plan fast 388: two pre-hits then the kill", p ~= nil and #p.swings == 3)
	check("plan fast 388: lands on 28 with margin 26", p ~= nil and near(p.hpKill, 28) and near(p.margin, 26))
	check("plan fast 388: the pre-hits at 0.6 and 1.5, the kill at 2.4", p ~= nil and near(p.swings[1], 0.6) and near(p.swings[2], 1.5) and near(p.swings[3], 2.4))
end

-- At most MAX_PREHITS pre-hits: 1000 HP loses 480 to the tower within the horizon and 120 to two pre-hits, never reaching our
-- range, so no plan comes back; without the cap a core swinging every 0.5 s would plan eight swings and a kill on 40
-- (review 2026-11-05-prehit-0f91d73 L3: the earlier check also passed on nil).
do
	local hpAt, lands = tower(1000)
	local p = PreHit.Plan(hpAt, PreHit.HORIZON, lands, FIRST, 0.5, LO, MEAN, PreHit.NoError)
	check("plan: a kill needing more than MAX_PREHITS pre-hits is no plan", p == nil)
end

-- The fitted error (ERROR, slice prehit-odds): the real HP runs below the forecast, so the plan aims its kill higher.
do
	local F = PreHit.FittedError
	check("error: no chance far below the table, all far above", F(1, -500) == 0 and F(1, 500) == 1)
	local rising = true
	for x = -120, 220, 5 do if F(1.2, x + 5) < F(1.2, x) then rising = false end end
	check("error: the chance rises with the error allowed", rising)
	check("error: at 1-1.5 s ahead the real HP is at or above the forecast about 1 time in 5", F(1.2, 0) > 0.1 and F(1.2, 0) < 0.3)
	check("error: beyond the table's last row, its last row", F(4, 30) == F(2.2, 30))
end

-- 388 HP: the exact plan's kill on 8 HP (a pre-hit now) has under a third of a chance once the creep may lose 20-120 more; the
-- tower alone leaves 68 after its fourth hit, above our range on the forecast and in it on the likeliest error: wait for it.
do
	local p = plan(388, { err = PreHit.FittedError })
	check("plan fitted 388: one swing after the tower's fourth hit, on 68 forecast", p ~= nil and #p.swings == 1 and near(p.swings[1], 0.3 + 3 * TOWER_PERIOD + PreHit.AFTER) and near(p.hpKill, 68))
	local exact = plan(388)
	check("plan fitted 388: its odds beat the exact plan's kill on 8", p ~= nil and exact ~= nil and p.odds > PreHit.FittedError(exact.swings[2], 8) - PreHit.FittedError(exact.swings[2], 8 - LO))
end

-- 420 HP: exactly, the tower alone leaves 20 at 3.64 s (wait); with the error that kill is likelier lost, and a pre-hit now
-- for a kill on 40 forecast at 2.83 s is the better bet: go.
do
	local p = plan(420, { err = PreHit.FittedError })
	check("plan fitted 420: a pre-hit now then the kill on 40", p ~= nil and #p.swings == 2 and near(p.swings[1], FIRST) and near(p.hpKill, 40))
	check("plan exact 420: the wait for 20", #plan(420).swings == 1)
end

-- 300 HP: no exact plan (above), but the third tower hit leaves 60, six above our range, and the creep is likely lower.
do
	local p = plan(300, { err = PreHit.FittedError })
	check("plan fitted 300: a later kill on 60 forecast", p ~= nil and #p.swings == 1 and near(p.hpKill, 60) and p.odds > 0.2)
end

-- A swing landing now is the last-hit verb's, which swings only on a forecast kill: above our range it is never the kill.
-- 144 HP is 64 at our first landing: not killed now; a pre-hit leaves 4 that the tower's next hit takes.
do
	local p = plan(144, { err = PreHit.FittedError })
	check("plan fitted 144: no kill now above the range", p == nil or not (#p.swings == 1 and near(p.swings[1], FIRST)))
end

-- Choose: the pre-hit ranks below a reachable last hit on another creep, whatever its eta (a pre-hit spends our attack cycle;
-- user 04/11/2026), above every deny, and replaces a wait on its own creep.
local function target(kind, eta, creep, walk, dies)
	return { creep = creep or {}, kind = kind, eta = eta, due = eta, walk = walk or 0, dies = dies or math.huge, ranged = false }
end
do
	local c = {}
	local pre = target("prehit", 0, c)
	local lh = target("lasthit", 0.9)
	check("choose: a reachable last hit on another creep beats the pre-hit", Pick.Choose({ lh }, nil, nil, pre) == lh)
	local far = target("lasthit", 0, nil, 2, 1)
	check("choose: an unreachable last hit does not block it", Pick.Choose({ far }, nil, nil, pre) == pre)
	local d = target("deny", 0)
	check("choose: the pre-hit beats a deny due now", Pick.Choose({ d }, nil, nil, pre) == pre)
	local same = target("lasthit", 0.8, c)
	check("choose: the pre-hit replaces a wait on its own creep", Pick.Choose({ same }, same, nil, pre) == pre)
	check("choose: with nothing offered, the pre-hit", Pick.Choose({}, nil, nil, pre) == pre)
	-- A last hit that is not this laner's (a support's claims) does not block it.
	local function denies(t) return t.kind == "deny" end
	check("choose: a last hit not mine does not block it", Pick.Choose({ lh }, nil, denies, pre) == pre)
end


-- Find (states/pre_hit consider): the verdict path on a fake engine `verbs` and one own tower on an enemy creep, and the
-- probe's two in-game faults as fixtures: prhfc1 (bot eecdf00) called the tower's GetSecondsPerAttack without self (the
-- stub below asserts on self); prhfc3 game B (t=117.967) called IsAlive on a removed creep in sampleWatch and failed the
-- laning task on every later scan (the creep below is removed between two looks).
FreshHumaniser({ Enable = true })
PreHit = require("bots/FunLib/humaniser/states/pre_hit")
Pick = require("bots/FunLib/humaniser/states/lane_pick")
local Customize = require("bots.Customize.general")
require("bots/FunLib/humaniser/lane_config").SetHelpers({ GetPosition = function() return 1 end })
ResetWorld()
local Unit = getmetatable(MakeUnit({ pid = 97 }))
function Unit:IsCreep() return self.creep == true end
-- A removed unit raises on IsAlive in Dota (prhfc3 game B); the stub does the same so the guard is what the test proves.
function Unit:IsAlive() assert(not self.removed, "IsAlive on a removed unit") return self.alive end
function Unit:IsHero() return self.creep ~= true end
function Unit:GetNearbyTowers(_, enemies) if enemies then return {} end return TOWERS end
function Unit:GetNearbyLaneCreeps() return {} end
function Unit:GetNearbyHeroes() return {} end
function Unit:GetAttackTarget() return self.target end
function Unit:GetAttackDamage() return self.damage or 60 end
function Unit:GetBaseDamageVariance() return 6 end
function Unit:GetActualIncomingDamage(d) return d end
function Unit:GetCurrentMovementSpeed() return 300 end
function Unit:GetLastAttackTime() return 0 end
function Unit:GetSecondsPerAttack()
	assert(getmetatable(self) == Unit, "GetSecondsPerAttack called without self")
	return self.period or 0.81
end
if GetUnitToUnitDistance == nil then
	function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end
end

local function world(hp, o)
	o = o or {}
	ResetWorld()
	local creep = MakeUnit({ pid = -2, team = 3, hp = hp, loc = Vector(o.creepX or 100, 0) })
	creep.creep = true
	local tw = MakeUnit({ pid = -3, team = 2, loc = Vector(-400, 0) })
	tw.target = creep
	tw.damage = 80
	TOWERS = { tw }
	local bot = MakeUnit({ pid = 1, team = 2, loc = Vector(0, 0) })
	bot.period = 1.4
	bot.range = 150
	local hpAt, lands = tower(hp)
	local hits = {}
	for _, t in ipairs(lands) do hits[#hits + 1] = { t = t, damage = TOWER, by = "tower" } end
	local f = { hp = hp, regen = 0, horizon = PreHit.HORIZON, hits = hits, unphased = 0, unphasedTower = o.unphasedTower == true, unphasedHits = {} }
	local verbs = {
		hpForecast = function() return f end,
		forecastHp = function(_, t) return hpAt(t) end,
		ownHitTime = function() return FIRST end,
		laneTargets = function() return o.offers or {} end,
	}
	return bot, creep, verbs
end

do -- 420 HP (the fitted plan test above): go, a prehit LaneTarget on the tower's creep; the tower's period was read with self
	local bot, creep, verbs = world(420)
	local ok, pre = pcall(PreHit.Find, bot, verbs)
	check("find: a go on 420 HP under the tower is a prehit pick on that creep", ok and pre ~= nil and pre.kind == "prehit" and pre.creep == creep)
	-- the probe's watch is running from the go; the creep is removed before the next look (prhfc3 fixture): first while the
	-- tower still names it (consider's guard), then with the tower on nothing (sampleWatch's guard)
	T = T + 0.2
	creep.removed = true
	creep.alive = false
	local ok2, pre2 = pcall(PreHit.Find, bot, verbs)
	check("find: a removed creep the tower still names raises nothing and offers no pre-hit", ok2 and pre2 == nil)
	TOWERS[1].target = nil
	local ok3, pre3 = pcall(PreHit.Find, bot, verbs)
	check("find: the watch on a removed creep ends without raising", ok3 and pre3 == nil)
end

do -- 130 HP: the first swing kills (kills), no pre-hit
	local bot, _, verbs = world(130)
	check("find: a kill now is left to the last-hit verb", PreHit.Find(bot, verbs) == nil)
end

do -- the tower's phase unknown: no pre-hit
	local bot, _, verbs = world(420, { unphasedTower = true })
	check("find: an unphased tower blocks the pre-hit", PreHit.Find(bot, verbs) == nil)
end

do -- the core more than MAX_WALK from the creep: far
	local bot, _, verbs = world(420, { creepX = 150 + 300 * (Pick.MAX_WALK + 0.5) })
	check("find: a creep beyond MAX_WALK is far", PreHit.Find(bot, verbs) == nil)
end

do -- a reachable last hit on another creep due before our attack is ready again: lh, no pre-hit
	local other = MakeUnit({ pid = -4, team = 3, hp = 40, loc = Vector(120, 50) })
	other.creep = true
	local bot, _, verbs = world(420, { offers = { { creep = other, kind = "lasthit", eta = 0.5, due = 0.5, walk = 0, dies = 1.0, ranged = false } } })
	check("find: a last hit on another creep due first blocks the pre-hit", PreHit.Find(bot, verbs) == nil)
end

do -- the switch off: Find offers nothing
	Customize.Ours.PreHit = false
	local bot, _, verbs = world(420)
	check("find: Ours.PreHit off offers no pre-hit", PreHit.Find(bot, verbs) == nil)
	Customize.Ours.PreHit = true
end

finish()
