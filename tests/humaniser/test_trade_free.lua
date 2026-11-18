-- Slice trade-free (D18, `Ours.TradeFree`): harass's second question, "is the hit free, or does the exchange favour me?",
-- in place of the lost trade's `gap`. Answer over plain inputs, then Gather's inputs from ranges, the target's swing and
-- the two estimates.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })

local world = { burst = 0.3 }
package.loaded["bots/FunLib/humaniser/transitions/phase"] = { LaningHeld = function() return true end }
package.loaded["bots/FunLib/humaniser/states/core_last_hit"] = { Applies = function() return true end }
package.loaded["bots/FunLib/humaniser/states/support_deny"] = { Harass = function() return false end }
local RealThreat = require("bots/FunLib/humaniser/threat")
package.loaded["bots/FunLib/humaniser/threat"] = {
	SETTINGS = RealThreat.SETTINGS,
	Read = function() return { burst = world.burst } end,
}
package.loaded["bots/FunLib/humaniser/states/core_trade"] = nil
local CoreTrade = require("bots/FunLib/humaniser/states/core_trade")

local function inputs(o)
	local i = { hp = 0.8, targetHp = 0.7, enemiesNear = 1, alliesNear = 1, enemyCreepsNear = 1, hitByCreeps = 0, tower = false,
		burst = 0.3, towerOnMe = false, free = false, ko = 0.3, kt = 0.2 }
	for k, v in pairs(o or {}) do i[k] = v end
	return i
end

do
	check("free: a target swinging at a creep", CoreTrade.Free(true, 500, 600))
	check("free: our range 100 over its", CoreTrade.Free(false, 600, 500) and CoreTrade.Free(false, 500, 150))
	check("not free: 75 over (dazzle on necrolyte), or shorter", not CoreTrade.Free(false, 575, 500) and not CoreTrade.Free(false, 500, 575))
	check("favoured: our kill share over theirs trades", CoreTrade.Answer(inputs(), 0.25, nil) == "trade")
	check("unfavoured: theirs over ours refuses", CoreTrade.Answer(inputs({ ko = 0.2, kt = 0.37 }), 0.25, nil) == "unfavoured")
	check("an even estimate is not favoured", CoreTrade.Answer(inputs({ ko = 0.3, kt = 0.3 }), 0.25, nil) == "unfavoured")
	check("free needs no comparison", CoreTrade.Answer(inputs({ free = true, ko = nil, kt = nil }), 0.25, nil) == "trade")
	check("the lost trade's gap no longer holds a favoured trade", CoreTrade.Answer(inputs(), 0.25, 0.9) == "trade")
	check("question 1 comes first: unsafe stays its respect", CoreTrade.Answer(inputs({ burst = 1.2, ko = 0.1 }), 0.25, nil) == "burst")
	check("a kill is not asked question 2", CoreTrade.Answer(inputs({ targetHp = 0.2, ko = 0.1, kt = 0.5 }), 0.25, nil) == "kill")
	local off = inputs()
	off.free, off.ko, off.kt = nil, nil, nil
	check("switch off (no answer in the inputs): the gap holds", CoreTrade.Answer(off, 0.25, 0.9) == "gap")
	-- Round 2, question 3: a due deny outbids a free or favoured trade; never a kill, and unfavoured stays its own answer.
	check("a due deny outbids a free trade", CoreTrade.Answer(inputs({ free = true, ko = nil, kt = nil, denyDue = true }), 0.25, nil) == "deny")
	check("a due deny outbids a favoured trade", CoreTrade.Answer(inputs({ denyDue = true }), 0.25, nil) == "deny")
	check("no deny due: the trade stays", CoreTrade.Answer(inputs({ denyDue = false }), 0.25, nil) == "trade")
	check("a kill is not outbid by a deny", CoreTrade.Answer(inputs({ targetHp = 0.2, denyDue = true }), 0.25, nil) == "kill")
	check("unfavoured stays unfavoured with a deny due", CoreTrade.Answer(inputs({ ko = 0.2, kt = 0.37, denyDue = true }), 0.25, nil) == "unfavoured")
	local offDeny = inputs({ denyDue = true })
	offDeny.free, offDeny.ko, offDeny.kt = nil, nil, nil
	check("switch off: a deny does not hold the trade", CoreTrade.Answer(offDeny, 0.25, nil) == "trade")
end

-- Gather: one core at x=0, one enemy hero 600 away.
local function hero(pid, team, x, hp)
	local u = MakeUnit({ pid = pid, team = team, loc = Vector(x, 0), hp = hp, mode = 1 })
	u.range = 500
	u.lane = 2
	return u
end
local bot = hero(1, 2, 0, 80)
local enemy = hero(6, 3, 600, 70)
local creep = MakeUnit({ pid = -1, team = 3, loc = Vector(700, 0), hp = 100 })
creep.IsCreep = function() return true end
creep.IsHero = function() return false end
local Unit = getmetatable(bot)
function Unit:GetBoundingRadius() return 24 end
function Unit:GetNearbyHeroes(r, enemies)
	if self ~= bot then return {} end
	if enemies then return { enemy } end
	return { self }
end
function Unit:GetNearbyLaneCreeps() return {} end
function Unit:GetNearbyTowers() return {} end
function Unit:GetAttackTarget() return self.attacking end
-- Gather asks whether the target is hitting the core (slice hitback-fold): here it never is.
function Unit:WasRecentlyDamagedByHero() return false end
function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end

do
	bot.estDamage, enemy.estDamage = 14, 32
	local i = CoreTrade.Gather(bot, enemy)
	check("Gather: same range, not swinging at a creep: not free, both shares read",
		i.free == false and math.abs(i.ko - 0.2) < 1e-9 and math.abs(i.kt - 0.4) < 1e-9 and CoreTrade.Answer(i, 0.25, nil) == "unfavoured")
	enemy.attacking = creep
	i = CoreTrade.Gather(bot, enemy)
	check("Gather: the target swings at a creep: free, no estimate read", i.free == true and i.ko == nil and CoreTrade.Answer(i, 0.25, nil) == "trade")
	enemy.attacking = nil
	enemy.range = 150
	i = CoreTrade.Gather(bot, enemy)
	check("Gather: a melee target we outrange: free", i.free == true and CoreTrade.Answer(i, 0.25, nil) == "trade")
	enemy.range = 500
	package.loaded["bots/FunLib/custom_loader"].Ours.TradeFree = false
	i = CoreTrade.Gather(bot, enemy)
	check("switch off: no question-2 inputs", i.free == nil and i.ko == nil and i.kt == nil)
	package.loaded["bots/FunLib/custom_loader"].Ours.TradeFree = true
end

-- Round 2: Gather reads the laning body's deny offer (Laning.DenyDue, laneTargets' denies under the reach rule).
do
	local Ours = package.loaded["bots/FunLib/custom_loader"].Ours
	local yield = Ours.CoreDenyYield
	Ours.CoreDenyYield = false
	local Tasks = require("bots/FunLib/humaniser/tasks")
	-- Laning loaded with the real CoreLastHit before this file's stub: the bot is a core whose lane hits are ours.
	local Laning = require("bots/FunLib/humaniser/states/laning")
	local owns = Laning.OwnsLastHit
	Laning.OwnsLastHit = function() return true end
	local verbs = Tasks.Verbs
	local offered = {}
	Tasks.Verbs = function() return { laneTargets = function(_, opts) return opts.lastHit == false and offered or {} end } end
	enemy.range = 150
	local i = CoreTrade.Gather(bot, enemy)
	check("Gather: no deny offered: the free trade stays", i.denyDue == false and CoreTrade.Answer(i, 0.25, nil) == "trade")
	offered = { { creep = creep, kind = "deny", eta = 0.1, due = 0.1, walk = 0, dies = 2, ranged = false } }
	check("DenyDue is read once per game time", Laning.DenyDue(bot) == false)
	T = T + 0.1
	i = CoreTrade.Gather(bot, enemy)
	check("Gather: a deny in range is due and outbids the trade", i.denyDue == true and CoreTrade.Answer(i, 0.25, nil) == "deny")
	offered = { { creep = creep, kind = "deny", eta = 0.9, due = 0, walk = 0.9, dies = 1.0, ranged = false } }
	T = T + 0.1
	i = CoreTrade.Gather(bot, enemy)
	check("Gather: a deny that dies before our walk and swing is not due", i.denyDue == false)
	-- A support: its body takes a hit only within the leash (900) of its spot (review of round 2).
	local ownsSup, spot = Laning.OwnsSupportHits, Laning.Spot
	Laning.OwnsLastHit = function() return false end
	Laning.OwnsSupportHits = function() return true end
	offered = { { creep = creep, kind = "deny", eta = 0.1, due = 0.1, walk = 0, dies = 2, ranged = false } }
	Laning.Spot = function() return Vector(300, 0) end
	T = T + 0.1
	check("a support near its spot: a deny is due", Laning.DenyDue(bot) == true)
	Laning.Spot = function() return Vector(-1000, 0) end
	T = T + 0.1
	check("a support beyond the leash: no deny is due (its body would not step)", Laning.DenyDue(bot) == false)
	Laning.OwnsSupportHits, Laning.Spot = ownsSup, spot
	Tasks.Verbs = verbs
	Laning.OwnsLastHit = owns
	Ours.CoreDenyYield = yield
	enemy.range = 500
end
finish()
