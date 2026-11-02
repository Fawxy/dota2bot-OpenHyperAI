-- Slice core-in-lane: a core's in-lane trades (states/core_trade). The decision rules over plain inputs, then one trade's life
-- through Desire/Think/OnEnd: a window attack mode never takes is logged lost, a taken trade stops at its time cap and rests,
-- and laning's last-hit desire yields to a retreat the core is already in.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true } })
local lines = {}
H.Telemetry.SetSink(function(line) table.insert(lines, line) end)

local world = { laning = true, applies = true }
package.loaded["bots/FunLib/humaniser/transitions/phase"] = { IsLaningFor = function() return world.laning end }
package.loaded["bots/FunLib/humaniser/states/core_last_hit"] = { Applies = function() return world.applies end }
package.loaded["bots/FunLib/humaniser/states/core_trade"] = nil
local CoreTrade = require("bots/FunLib/humaniser/states/core_trade")

local function inputs(o)
	local i = { hp = 0.8, targetHp = 0.7, enemiesNear = 1, alliesNear = 1, enemyCreepsNear = 1, hitByCreeps = 0, tower = false }
	for k, v in pairs(o or {}) do i[k] = v end
	return i
end

do
	check("even lane, healthy, small wave: trade", CoreTrade.Decide(inputs()).kind == "trade")
	check("their tower covers us or the target: no trade, not even for a kill",
		CoreTrade.Decide(inputs({ tower = true, targetHp = 0.1 })).respect == "tower")
	check("more of them than us in reach: no trade, not even for a kill",
		CoreTrade.Decide(inputs({ enemiesNear = 2, targetHp = 0.1 })).respect == "outnumbered")
	check("a target at a quarter HP is a kill even with our HP under the trade floor",
		CoreTrade.Decide(inputs({ hp = 0.3, targetHp = 0.2, enemyCreepsNear = 6 })).kind == "kill")
	check("a low target is not a kill when we are lower still", CoreTrade.Decide(inputs({ hp = 0.15, targetHp = 0.2 })).kind == nil)
	check("under half HP: no trade", CoreTrade.Decide(inputs({ hp = 0.45, targetHp = 0.4 })).respect == "low_hp")
	check("well behind the target on HP: no trade", CoreTrade.Decide(inputs({ hp = 0.6, targetHp = 0.9 })).respect == "behind")
	check("two creeps already on us: no trade", CoreTrade.Decide(inputs({ hitByCreeps = 2 })).respect == "creeps")
	check("inside a big enemy wave: no trade", CoreTrade.Decide(inputs({ enemyCreepsNear = 4 })).respect == "wave")
end

-- A world for Desire: one core, one enemy hero in reach, nothing else nearby.
local LANING = 1
local function hero(pid, team, x, hp)
	local u = MakeUnit({ pid = pid, team = team, loc = Vector(x, 0), hp = hp, mode = LANING })
	u.range = 500
	u.lane = 2
	return u
end
local bot = hero(1, 2, 0, 80)
local enemy = hero(6, 3, 400, 70)
local Unit = getmetatable(bot)
function Unit:GetBoundingRadius() return 24 end
function Unit:GetNearbyHeroes(r, enemies)
	if enemies then return GetUnitToUnitDistance(self, enemy) <= r and { enemy } or {} end
	return { self }
end
function Unit:GetNearbyLaneCreeps() return {} end
function Unit:GetNearbyTowers() return {} end
function Unit:GetAttackTarget() return self.attacking end
function Unit:Action_AttackUnit(u) self.attacking = u self.orders = (self.orders or 0) + 1 end
function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end

local function last() return lines[#lines] or "" end

do
	T = 100
	check("in lane with a trade on: our trade desire", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE and CoreTrade.OwnsFrame(bot))
	T = 101.5
	local n = #lines
	CoreTrade.Desire(bot)
	check("a window attack mode did not take within 1 s is logged lost", #lines == n + 1 and last():find("ev=trade") and last():find("result=lost") and last():find("why=not_taken"))
end

do
	CoreTrade.Reset()
	bot.attacking = nil
	T = 200
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	check("Think attacks the window's target", bot.attacking == enemy)
	enemy.hp = 60
	bot.hp = 75
	T = 202
	check("inside the time cap the trade keeps its desire", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
	T = 203.5
	check("past the 3 s cap the trade ends", CoreTrade.Desire(bot) == 0)
	check("the end line carries HP traded both ways", last():find("result=done") and last():find("why=time") and last():find("hpd=5") and last():find("thpd=10"))
	T = 205
	check("then the core rests from trades though the window is still open", CoreTrade.Desire(bot) == 0)
	T = 207
	check("after the rest a new trade opens", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
end

do
	CoreTrade.Reset()
	world.laning = false
	T = 300
	check("out of the laning phase: no desire of ours, OHA's port decides", CoreTrade.Desire(bot) == nil and not CoreTrade.OwnsFrame(bot))
	world.laning = true
	bot.loc = Vector(0, 0)
	local along = GetAmountAlongLane
	GetAmountAlongLane = function() return { amount = 0.5, distance = 2000 } end
	check("laning phase but away from its lane: OHA's port decides", CoreTrade.Desire(bot) == nil)
	GetAmountAlongLane = along
end

do
	bot.mode = BOT_MODE_RETREAT
	check("a core already retreating keeps its retreat over a last hit", CoreTrade.LastHitYieldsToRetreat(bot))
	bot.mode = LANING
	check("a laning core still takes the last-hit desire", not CoreTrade.LastHitYieldsToRetreat(bot))
	bot.mode = BOT_MODE_RETREAT
	world.applies = false
	check("not our core (switch off, or a support): laning's desire unchanged", not CoreTrade.LastHitYieldsToRetreat(bot))
end

finish()
