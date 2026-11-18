-- Slice trade-lands (D18, kill-chances T1, `Ours.TradeLands`): a trade outside attack range opens only when the hero can reach
-- range within WALK_IN, and a taken trade waits for its first attack through a due deny and a join on another hero.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true, Cut = false } })
local Ours = package.loaded["bots/FunLib/custom_loader"].Ours
Ours.TradeSafe = false
Ours.TradeFree = false
local lines = {}
H.Telemetry.SetSink(function(line) table.insert(lines, line) end)

package.loaded["bots/FunLib/humaniser/transitions/phase"] = { IsLaningFor = function() return true end }
package.loaded["bots/FunLib/humaniser/states/core_last_hit"] = { Applies = function() return true end }
package.loaded["bots/FunLib/humaniser/states/support_deny"] = { Harass = function() return false end }
package.loaded["bots/FunLib/humaniser/states/core_trade"] = nil
local CoreTrade = require("bots/FunLib/humaniser/states/core_trade")
local Laning = require("bots/FunLib/humaniser/states/laning")
local PairJoin = require("bots/FunLib/humaniser/pair_join")

do
	-- Past attack range by `gap`: closing speed is our speed less the target's away speed.
	check("arrives: a standing target within 1.5 s of walking", CoreTrade.Arrives(300, 300, 0, 1.5))
	check("arrives: a standing target past it does not", not CoreTrade.Arrives(500, 300, 0, 1.5))
	check("arrives: a target walking away at our speed never does", not CoreTrade.Arrives(1, 300, 300, 1.5))
	check("arrives: a faster one does not", not CoreTrade.Arrives(1, 300, 400, 1.5))
	check("arrives: a target walking at us closes the gap faster", CoreTrade.Arrives(600, 300, -300, 1.5))
	check("arrives: in range already counts, whatever it does next", CoreTrade.Arrives(-5, 300, 500, 1.5))
end

local LANING = 1
local function hero(pid, team, x, hp)
	local u = MakeUnit({ pid = pid, team = team, loc = Vector(x, 0), hp = hp, mode = LANING })
	u.range = 500
	u.lane = 2
	return u
end
local bot = hero(1, 2, 0, 80)
local enemy = hero(6, 3, 400, 70)
local other = hero(7, 3, 300, 70)
local Unit = getmetatable(bot)
function Unit:GetBoundingRadius() return 24 end
function Unit:GetNearbyHeroes(r, enemies)
	if enemies then return GetUnitToUnitDistance(self, enemy) <= r and { enemy } or {} end
	return { self }
end
function Unit:GetNearbyLaneCreeps() return {} end
function Unit:WasRecentlyDamagedByHero() return false end
function Unit:GetNearbyTowers() return {} end
function Unit:GetAttackTarget() return self.attacking end
function Unit:GetLastAttackTime() return self.lastAttack or -1000 end
function Unit:Action_AttackUnit(u) self.attacking = u end
function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end
function IsHeroAlive(pid) return pid == enemy.pid and not enemy.dead or pid == bot.pid end
function GetUnitList() local r = {} for _, u in ipairs(UNITS[3]) do if u.alive and u.pid <= 10 then table.insert(r, u) end end return r end
function GetTower() return nil end
CURRENT_TEAM = 2

local denyDue, joinOn = false, nil
Laning.DenyDue = function() return denyDue end
PairJoin.Joins = function() return joinOn end

local function lastWhy()
	for k = #lines, 1, -1 do
		local w = lines[k]:match("ev=trade .*why=(%S+)")
		if w and lines[k]:find("kind=trade") then return w end
	end
end

local function reset(x)
	CoreTrade.Reset()
	lines = {}
	denyDue, joinOn = false, nil
	Ours.TradeLands, Ours.TradeFree = true, false
	bot.hp, bot.attacking, bot.lastAttack = 80, nil, nil
	enemy.hp, enemy.dead, enemy.loc = 70, nil, Vector(x, 0)
end

-- The gate. Our range with hulls is 548, our speed 300: 1.5 s covers 450.
do
	reset(600)
	T = 100
	check("gate: a standing target 52 past range opens", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)

	-- A target walking away at 300 from just past range: one frame (hp too low to trade) reads its heading, the next decides.
	local function flee(on)
		reset(400)
		Ours.TradeLands = on
		bot.hp = 40
		T = 200
		CoreTrade.Desire(bot)
		bot.hp = 80
		enemy.loc = Vector(550, 0)
		T = 200.5
		return CoreTrade.Desire(bot)
	end
	check("gate: a target fleeing at our speed is not opened on", flee(true) == 0)
	check("gate control: the same chase opens with the switch off", flee(false) == CoreTrade.DESIRE_TRADE)
end

-- The wait: a trade taken in range, its first attack not yet fired.
local function taken(x)
	reset(x)
	T = 300
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	Ours.TradeFree = true
end

do
	taken(400)
	denyDue = true
	T = 300.5
	check("wait: a due deny does not end a trade before its first attack", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
	bot.lastAttack = 399
	T = 301
	CoreTrade.Desire(bot)
	check("wait: once an attack has fired the deny ends it", lastWhy() == "deny")

	taken(400)
	denyDue = true
	enemy.loc = Vector(1000, 0)
	T = 300.5
	CoreTrade.Desire(bot)
	check("wait: a target the read says we cannot reach no longer holds the deny back", lastWhy() == "deny")

	taken(400)
	denyDue = true
	T = 304.5
	CoreTrade.Desire(bot)
	check("wait: the 4 s backstop ends it as hold_time", lastWhy() == "hold_time")

	taken(400)
	Ours.TradeLands = false
	denyDue = true
	T = 300.5
	CoreTrade.Desire(bot)
	check("wait control: switch off, the deny ends it at once", lastWhy() == "deny")
end

do
	taken(400)
	joinOn = other
	T = 300.5
	check("join: a pair join on another hero waits for the first attack", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE and lastWhy() == nil)
	bot.lastAttack = 399
	T = 301
	CoreTrade.Desire(bot)
	check("join: after the first attack it takes over", lastWhy() == "pair_join")

	taken(400)
	joinOn = enemy
	T = 300.5
	CoreTrade.Desire(bot)
	check("join: a join on the trade's own target passes at once", lastWhy() == "pair_join")

	taken(400)
	joinOn = other
	Ours.TradeLands = false
	T = 300.5
	CoreTrade.Desire(bot)
	check("join control: switch off, a join on another hero takes over at once", lastWhy() == "pair_join")
end

do
	taken(400)
	denyDue = true
	T = 300.5
	CoreTrade.Desire(bot)
	check("a last hit still takes the frame from a waiting trade", not CoreTrade.LastHitYields(bot))
end

finish()
