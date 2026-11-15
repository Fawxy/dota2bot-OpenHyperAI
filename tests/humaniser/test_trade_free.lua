-- Slice trade-free (D18, `Ours.TradeFree`): harass's second question, "is the hit free, or does the exchange favour me?",
-- in place of the lost trade's `gap`. Answer over plain inputs, then Gather's inputs from ranges, the target's swing and
-- the two estimates.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })

local world = { burst = 0.3 }
package.loaded["bots/FunLib/humaniser/transitions/phase"] = { IsLaningFor = function() return true end }
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
finish()
