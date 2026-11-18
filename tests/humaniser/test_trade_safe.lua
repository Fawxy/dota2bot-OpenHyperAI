-- Slice trade-safe (D18, `Ours.TradeSafe`): harass asks "is it safe?" of the threat read. Decide over plain inputs with
-- `burst` present, then Gather's read: the burst from Threat.Read and the tower test on the bot's attack point.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })

local world = { laning = true, applies = true, burst = 0.3, reads = 0 }
package.loaded["bots/FunLib/humaniser/transitions/phase"] = { LaningHeld = function() return world.laning end }
package.loaded["bots/FunLib/humaniser/states/core_last_hit"] = { Applies = function() return world.applies end }
package.loaded["bots/FunLib/humaniser/states/support_deny"] = { Harass = function() return false end }
local RealThreat = require("bots/FunLib/humaniser/threat")
package.loaded["bots/FunLib/humaniser/threat"] = {
	SETTINGS = RealThreat.SETTINGS,
	Read = function(_, _, _, horizon, opts)
		world.reads = world.reads + 1
		world.horizon = horizon
		world.engaged = opts and opts.engagedWindow
		return { burst = world.burst }
	end,
}
package.loaded["bots/FunLib/humaniser/states/core_trade"] = nil
local CoreTrade = require("bots/FunLib/humaniser/states/core_trade")

local function inputs(o)
	local i = { hp = 0.8, targetHp = 0.7, enemiesNear = 1, alliesNear = 1, enemyCreepsNear = 1, hitByCreeps = 0, tower = false,
		burst = 0.3, towerOnMe = false }
	for k, v in pairs(o or {}) do i[k] = v end
	return i
end

do
	check("safe: even lane, healthy, low burst: trade", CoreTrade.Decide(inputs()).kind == "trade")
	check("well behind the target on HP but safe: trade (behind is gone)",
		CoreTrade.Decide(inputs({ hp = 0.6, targetHp = 0.95 })).kind == "trade")
	check("the target alone by its tower, our attack point outside it: trade",
		CoreTrade.Decide(inputs({ tower = true })).kind == "trade")
	check("but a low target by its tower is no kill (a commit chases): trade, not kill",
		CoreTrade.Decide(inputs({ tower = true, targetHp = 0.1 })).kind == "trade")
	check("their tower on our attack point: no trade, not even for a kill",
		CoreTrade.Decide(inputs({ towerOnMe = true, targetHp = 0.1 })).respect == "tower")
	check("more of them than us in reach: no trade, not even for a kill",
		CoreTrade.Decide(inputs({ enemiesNear = 2, targetHp = 0.1 })).respect == "outnumbered")
	check("a low target clear of their tower is a kill", CoreTrade.Decide(inputs({ targetHp = 0.2 })).kind == "kill")
	check("under half HP: no trade", CoreTrade.Decide(inputs({ hp = 0.45, targetHp = 0.4 })).respect == "low_hp")
	check("their burst in reach at our HP: no trade (the control)",
		CoreTrade.Decide(inputs({ hp = 0.6, targetHp = 0.95, burst = 1.0 })).respect == "burst")
	check("a running trade keeps going just over the burst bar (slack), and stops past it",
		CoreTrade.Decide(inputs({ burst = 1.02 }), true).kind == "trade"
			and CoreTrade.Decide(inputs({ burst = 1.1 }), true).respect == "burst")
	check("two creeps already on us: no trade", CoreTrade.Decide(inputs({ hitByCreeps = 2 })).respect == "creeps")
	check("inside a big enemy wave: no trade", CoreTrade.Decide(inputs({ enemyCreepsNear = 4 })).respect == "wave")
	local old = inputs({ hp = 0.6, targetHp = 0.95 })
	old.burst = nil
	check("without a burst read the old rule decides (switch off): behind", CoreTrade.Decide(old).respect == "behind")
end

-- Gather: one core at x=0, one enemy hero, an enemy tower at x=2000 (reach 868 by default).
local LANING = 1
local function hero(pid, team, x, hp)
	local u = MakeUnit({ pid = pid, team = team, loc = Vector(x, 0), hp = hp, mode = LANING })
	u.range = 500
	u.lane = 2
	return u
end
local bot = hero(1, 2, 0, 80)
local enemy = hero(6, 3, 900, 70)
local tower = MakeUnit({ pid = -1, team = 3, loc = Vector(2000, 0), hp = 100 })
local Unit = getmetatable(bot)
function Unit:GetBoundingRadius() return 24 end
function Unit:GetNearbyHeroes(r, enemies)
	if self ~= bot then return {} end
	if enemies then return GetUnitToUnitDistance(self, enemy) <= r and { enemy } or {} end
	return { self }
end
function Unit:GetNearbyLaneCreeps() return {} end
function Unit:GetNearbyTowers(_, enemies) return enemies and { tower } or {} end
function Unit:GetAttackTarget() return self.attacking end
-- Gather asks whether the target is hitting the core (slice hitback-fold): here it never is.
function Unit:WasRecentlyDamagedByHero() return false end
function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end

do
	-- The target 900 away, 1,100 from the tower (outside reach); we attack from 548 short of it, x=352: far from the tower.
	local i = CoreTrade.Gather(bot, enemy)
	check("Gather fills the burst from one threat read, retreat's stay read (2 s, engaged over 6 s)",
		i.burst == 0.3 and world.reads == 1 and world.horizon == 2 and world.engaged == 6)
	local Retreat = require("bots/FunLib/humaniser/retreat")
	check("the copied read constants equal retreat's stay read (an import cycle stops core_trade reading them)",
		world.horizon == Retreat.SETTINGS.Horizon and world.engaged == Retreat.SETTINGS.EngagedWindow)
	check("target and attack point clear of the tower: no tower either way", i.towerOnMe == false and i.tower == false)
	-- The target at 1,300, inside the tower's reach; our attack point x=752 is 1,248 from the tower: outside.
	enemy.loc = Vector(1300, 0)
	i = CoreTrade.Gather(bot, enemy)
	check("the target alone by its tower: tower (old) but not on me", i.tower == true and i.towerOnMe == false)
	check("and the safe rule trades it", CoreTrade.Decide(i).kind == "trade")
	-- Standing at 1,400 the bot is in reach of the tower itself (600 from it).
	bot.loc = Vector(1400, 0)
	i = CoreTrade.Gather(bot, enemy)
	check("our own spot in their tower's reach: tower on me", i.towerOnMe == true and CoreTrade.Decide(i).respect == "tower")
	bot.loc = Vector(0, 0)
	tower.attacking = bot
	i = CoreTrade.Gather(bot, enemy)
	check("a tower attacking us is a tower on me", i.towerOnMe == true)
	tower.attacking = nil
	-- Switch off: no read, the old inputs.
	package.loaded["bots/FunLib/custom_loader"].Ours.TradeSafe = false
	world.reads = 0
	i = CoreTrade.Gather(bot, enemy)
	check("switch off: no threat read, no burst, the old rule", i.burst == nil and world.reads == 0 and CoreTrade.Decide(i).respect == "tower")
	package.loaded["bots/FunLib/custom_loader"].Ours.TradeSafe = true
end
finish()
