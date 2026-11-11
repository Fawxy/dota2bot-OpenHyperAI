-- Slice core-in-lane: a core's in-lane trades (states/core_trade). The decision rules over plain inputs, then one trade's life
-- through Desire/Think/OnEnd: a window attack mode never takes is logged lost, a taken trade runs until the exchange turns, then
-- waits for the HP gap to recover,
-- and laning's last-hit desire yields to a retreat the core is already in.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true } })
local lines = {}
H.Telemetry.SetSink(function(line) table.insert(lines, line) end)

local world = { laning = true, applies = true }
package.loaded["bots/FunLib/humaniser/transitions/phase"] = { IsLaningFor = function() return world.laning end }
package.loaded["bots/FunLib/humaniser/states/core_last_hit"] = { Applies = function() return world.applies end }
package.loaded["bots/FunLib/humaniser/states/support_deny"] = { Harass = function() return world.support == true end }
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
-- The hero that hit us last (slice hit-back); nobody by default.
function Unit:WasRecentlyDamagedByHero(h) return self.hitBy == h end
function Unit:GetNearbyTowers() return {} end
function Unit:GetAttackTarget() return self.attacking end
function Unit:Action_AttackUnit(u) self.attacking = u self.orders = (self.orders or 0) + 1 end
function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end
-- The game's per-player answer; a unit handle out of sight reads as dead (below).
function IsHeroAlive(pid) return pid == enemy.pid and not enemy.dead or pid == bot.pid end

local function last() return lines[#lines] or "" end
-- The play roll's readings (fight_readings): the enemy heroes (pids 6-10; creeps here are pids 20 and up), no towers; our team
-- is Radiant.
function GetUnitList() local r = {} for _, u in ipairs(UNITS[3]) do if u.alive and u.pid <= 10 then table.insert(r, u) end end return r end
function GetTower() return nil end
CURRENT_TEAM = 2

do
	T = 100
	check("in lane with a trade on: our trade desire", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE and CoreTrade.OwnsFrame(bot))
	T = 101.5
	local n = #lines
	CoreTrade.Desire(bot)
	check("a window attack mode did not take within 1 s is logged lost", #lines == n + 1 and last():find("ev=trade") and last():find("result=lost") and last():find("why=not_taken"))
end

do
	check("a running trade keeps going one creep past the wave limit that blocks a new one",
		CoreTrade.Decide(inputs({ enemyCreepsNear = 4 }), true).kind == "trade" and CoreTrade.Decide(inputs({ enemyCreepsNear = 4 })).kind == nil)
	check("a running trade keeps going just under the HP floor that blocks a new one",
		CoreTrade.Decide(inputs({ hp = 0.47, targetHp = 0.4 }), true).kind == "trade" and CoreTrade.Decide(inputs({ hp = 0.47, targetHp = 0.4 })).kind == nil)
	check("the slack has an end: well under the floor stops a running trade", CoreTrade.Decide(inputs({ hp = 0.4, targetHp = 0.4 }), true).respect == "low_hp")
	check("deficit: the core lost 20 of 100 more than the target", near(CoreTrade.Deficit(500, 450, 600, 570, 250), 0.08))
end

do
	CoreTrade.Reset()
	bot.attacking = nil
	bot.hp, enemy.hp = 80, 70
	T = 200
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	check("Think attacks the window's target", bot.attacking == enemy)
	-- An even exchange for 10 s: no time limit ends it.
	bot.hp, enemy.hp = 72, 60
	T = 210
	check("an even trade keeps its desire however long it runs", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
	-- The core then loses 6 of 100 more than the target since the start: the exchange has turned.
	bot.hp, enemy.hp = 58, 64
	T = 211
	check("a trade the core is losing by more than 5% of its HP ends", CoreTrade.Desire(bot) == 0)
	check("the end line names it and carries HP traded both ways", last():find("result=done") and last():find("why=losing") and last():find("hpd=22") and last():find("thpd=6"))
	-- The trade began at a gap of +0.10 (80 against 70); now 58 against 64 is -0.06.
	T = 230
	check("after a lost trade no new one opens while the core is behind its starting HP gap", CoreTrade.Desire(bot) == 0)
	bot.hp = 74
	check("once the gap is back a new trade opens", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
end

-- Slice lane-fight: a core whose lane fights are ours commits on a target at 40% HP or less; with the switch off the trade's 25%
-- kill cut stands, so the same 35% target is only a trade. Out of lane the core's fights are not ours (OHA's team roam).
do
	local Ours = package.loaded["bots/FunLib/custom_loader"].Ours
	local function open(lf)
		Ours.CoreLaneFight = lf
		CoreTrade.Reset()
		bot.attacking, enemy.dead = nil, false
		bot.hp, enemy.hp = 80, 35
		T = T + 50
		return CoreTrade.Desire(bot)
	end
	check("lane fights ours: a 35% target is a commit", open(true) == CoreTrade.DESIRE_KILL and CoreTrade.OwnsLaneFights(bot))
	CoreTrade.Think(bot)
	T = T + 0.5
	enemy.dead = true
	CoreTrade.Desire(bot)
	check("the commit's line carries lf=1 and the kill", last():find("kind=kill") and last():find("lf=1") and last():find("result=kill"))
	-- A commit that ends in the core's death keeps the offer's lf=1, so @lane_commits counts the death.
	open(true)
	CoreTrade.Think(bot)
	T = T + 0.5
	bot.alive = false
	CoreTrade.Desire(bot)
	check("a commit ended by the core's death still carries lf=1", last():find("why=dead") and last():find("lf=1"), last())
	bot.alive = true
	check("switch off: the same target is a trade", open(false) == CoreTrade.DESIRE_TRADE and not CoreTrade.OwnsLaneFights(bot))
	Ours.CoreLaneFight = true
	world.laning = false
	check("out of the laning phase the core's fights are not ours", not CoreTrade.OwnsLaneFights(bot))
	world.laning = true
	CoreTrade.Reset()
end

do
	check("aggro: inside its own order's cooldown the core just attacks", CoreTrade.AggroPlan(10, 8, 3) == "attack")
	check("aggro: cooldown over and no creep within 550: a fresh order primes it", CoreTrade.AggroPlan(10, 7, 0) == "prime")
	check("aggro: cooldown over with creeps near: step out before ordering", CoreTrade.AggroPlan(10, 7, 2) == "step_out")
	check("aggro: the last 0.3 s of the cooldown is not relied on", CoreTrade.AggroPlan(10, 7.25, 2) == "step_out")
end

do
	-- One trade beside an enemy creep: step out, prime clear of it, hit inside the cooldown, step out again when it runs low.
	CoreTrade.Reset()
	bot.hp, enemy.hp, bot.attacking, bot.moves, bot.orders = 80, 70, nil, {}, 0
	bot.loc = Vector(0, 0)
	local creepUnit = MakeUnit({ pid = 20, team = 3, loc = Vector(-300, 0) })
	local creeps = { creepUnit }
	function Unit:GetNearbyLaneCreeps(r, enemies)
		local out = {}
		if enemies then for _, c in ipairs(creeps) do if GetUnitToUnitDistance(self, c) <= r then table.insert(out, c) end end end
		return out
	end
	T = 400
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	local away = bot.moves[#bot.moves]
	check("creep within 550 and no cooldown: the core steps out, away from the creep, without an attack order",
		bot.orders == 0 and away ~= nil and away.x > 0)
	bot.loc = Vector(300, 0)
	T = 400.5
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	check("clear of the creep: one attack order primes the cooldown", bot.orders == 1 and bot.attacking == enemy)
	bot.loc = Vector(0, 0)
	T = 402
	CoreTrade.Desire(bot)
	local moves = #bot.moves
	CoreTrade.Think(bot)
	check("back beside the creep inside the cooldown: it keeps hitting, no step out, no new order", #bot.moves == moves and bot.orders == 1)
	T = 403.3
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	check("cooldown running low beside the creep: it steps out again", #bot.moves == moves + 1)
	creepUnit.attacking = bot
	T = 403.5
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	T = 406
	CoreTrade.Desire(bot)
	check("a step out that never clears ends the trade, which logs its primes, step outs and peak aggro",
		last():find("why=no_clear") and last():find("pr=1") and last():find("so=2") and last():find("ag=1"), last())
	creeps = {}
end

do
	-- The step out leaves the target out of reach; the order primed there must get to walk back in (cil2: 144 trades ended
	-- out_of_reach 1.2 s in, most right after a prime).
	CoreTrade.Reset()
	bot.hp, enemy.hp, bot.attacking, bot.moves, bot.orders = 80, 70, nil, {}, 0
	bot.loc = Vector(0, 0)
	local creeps = { MakeUnit({ pid = 21, team = 3, loc = Vector(300, 0) }) }
	function Unit:GetNearbyLaneCreeps(r, enemies)
		local out = {}
		if enemies then for _, c in ipairs(creeps) do if GetUnitToUnitDistance(self, c) <= r then table.insert(out, c) end end end
		return out
	end
	T = 450
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	bot.loc = Vector(-400, 0)
	T = 450.5
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	check("primed from clear ground out of the target's reach", bot.orders == 1)
	T = 451
	check("walking back in under the primed cooldown keeps the trade", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
	T = 453.5
	check("still out of reach once the cooldown no longer covers it: the trade ends", CoreTrade.Desire(bot) == 0 and last():find("why=out_of_reach"), last())
	creeps = {}
	function Unit:GetNearbyLaneCreeps() return {} end
end

do
	-- cil2 A_on_1 t=776.3: a creep listed as alive returned no location and Think raised.
	CoreTrade.Reset()
	bot.hp, enemy.hp, bot.attacking, bot.moves, bot.orders = 80, 70, nil, {}, 0
	bot.loc = Vector(0, 0)
	local seen = MakeUnit({ pid = 22, team = 3, loc = Vector(-300, 0) })
	local fogged = MakeUnit({ pid = 23, team = 3, loc = Vector(-200, 0) })
	function fogged:GetLocation() return nil end
	function Unit:GetNearbyLaneCreeps(r, enemies) return enemies and { seen, fogged } or {} end
	T = 600
	CoreTrade.Desire(bot)
	local ok, err = pcall(CoreTrade.Think, bot)
	local away = bot.moves[#bot.moves]
	check("a creep with no location is skipped: the core still steps out away from the located one", ok and away ~= nil and away.x > 0, tostring(err))
	function Unit:GetNearbyLaneCreeps() return {} end
end

do
	-- cil3 A_on_4 t=89.3: a target at 77% HP left sight, its handle read as dead, and the trade logged a kill with all its HP.
	CoreTrade.Reset()
	bot.hp, enemy.hp, bot.attacking, bot.loc = 80, 70, nil, Vector(0, 0)
	T = 700
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	enemy.hp = 60
	T = 701
	CoreTrade.Desire(bot)
	enemy.alive = false
	T = 702
	CoreTrade.Desire(bot)
	check("a target out of sight but alive ends as lost from sight, with the HP it had when last seen",
		last():find("result=done") and last():find("why=target_lost") and last():find("thpd=10"), last())
	enemy.alive = true
	CoreTrade.Reset()
	T = 710
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	enemy.alive, enemy.dead = false, true
	T = 711
	CoreTrade.Desire(bot)
	check("a target the game says is dead ends as a kill", last():find("result=kill") and last():find("why=target_dead"), last())
	enemy.alive, enemy.dead = true, nil
end

do
	-- Valve calls OnEnd while the active mode still reads attack: the trade's end names the mode that took the bot.
	CoreTrade.Reset()
	bot.hp, enemy.hp, bot.loc = 80, 70, Vector(0, 0)
	T = 500
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	bot.mode = 2
	local n = #lines
	CoreTrade.OnEnd(bot)
	check("OnEnd alone logs nothing yet", #lines == n)
	bot.mode, bot.desire = BOT_MODE_RETREAT, 0.8
	T = 500.1
	CoreTrade.Desire(bot)
	check("the next Desire closes it with the mode that took over and its desire", last():find("why=mode_4") and last():find("md=0.8"), last())
	bot.mode, bot.desire = LANING, 0
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
	check("a core already retreating keeps its retreat over a last hit", CoreTrade.LastHitYields(bot))
	bot.mode = LANING
	check("a laning core still takes the last-hit desire", not CoreTrade.LastHitYields(bot))
	bot.mode = BOT_MODE_RETREAT
	world.applies = false
	check("not our core (switch off, or a support): laning's desire unchanged", not CoreTrade.LastHitYields(bot))
	bot.mode = LANING
	check("not our core: OHA's run-from-a-trade triggers stay", not CoreTrade.TradeOwnsLaneRun(bot))
	world.applies = true
	check("our core in lane: the trade rule, not OHA's run, ends a trade", CoreTrade.TradeOwnsLaneRun(bot))
	local along = GetAmountAlongLane
	GetAmountAlongLane = function() return { amount = 0.5, distance = 2000 } end
	check("our core away from its lane: OHA's run triggers stay", not CoreTrade.TradeOwnsLaneRun(bot))
	GetAmountAlongLane = along
end

-- Slice support-spot: a support's harass is the same rule with a longer reach (attack range + radii + 300, against the core's
-- + 100), and it prefers an enemy hero swinging at a lane creep.
do
	CoreTrade.Reset()
	bot.mode, bot.desire, bot.attacking = LANING, 0, nil
	bot.loc = Vector(0, 0)
	bot.hp, enemy.hp = 80, 70
	function Unit:GetNearbyLaneCreeps() return {} end
	enemy.loc = Vector(750, 0)
	T = 600
	check("a core does not trade with an enemy hero 750 away (reach 648)", CoreTrade.Desire(bot) == 0)
	world.applies, world.support = false, true
	check("support harass owned: our attack mode for the support", CoreTrade.Owns(bot))
	check("a support harasses the same hero 750 away (reach 848)", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
	CoreTrade.Think(bot)
	check("the harass attacks that hero", bot.attacking == enemy)
	enemy.dead = true
	CoreTrade.Desire(bot)
	check("the harass line says role=support", last():find("ev=trade") and last():find("role=support"))
	enemy.dead = false
	world.support = false
	check("switch off (neither core nor harassing support): OHA's attack mode", not CoreTrade.Owns(bot))

	-- Two enemy heroes: the nearer one idle, the farther one swinging at one of our creeps.
	CoreTrade.Reset()
	local ours = MakeUnit({ pid = 30, team = 2, loc = Vector(700, 100) })
	local ally = hero(2, 2, -100, 90)
	function ours:IsHero() return false end
	function ours:IsCreep() return true end
	local busy = hero(7, 3, 800, 70)
	busy.attacking = ours
	enemy.loc = Vector(600, 0)
	local heroes = Unit.GetNearbyHeroes
	function Unit:GetNearbyHeroes(r, enemies)
		-- Two of us against the two of them, so the window is not outnumbered.
		if not enemies then return { self, ally } end
		local out = {}
		for _, h in ipairs({ enemy, busy }) do if GetUnitToUnitDistance(self, h) <= r then table.insert(out, h) end end
		return out
	end
	local alive = IsHeroAlive
	IsHeroAlive = function(pid) return pid == 7 or alive(pid) end
	world.support = true
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	check("a support prefers the enemy hero busy last-hitting over a nearer idle one", bot.attacking == busy)
	CoreTrade.Reset()
	bot.attacking = nil
	world.applies, world.support = true, false
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	check("a core takes the nearest", bot.attacking == enemy)
	Unit.GetNearbyHeroes = heroes
	IsHeroAlive = alive
	enemy.loc = Vector(400, 0)
end

-- Slice lane-fight, the play roll: an owned core with no clear window rolls a `lane_fight` play at most every 15 s per target
-- (one draw from the engine's Skill rng, none without it), joins an ally's running play near it, and defers to a play of
-- another context it started. A fight commits like a kill and ends below the roll's HP floor, ending its play.
do
	local LaneConfig = require("bots/FunLib/humaniser/lane_config")
	local Plays = require("bots/FunLib/humaniser/plays/plays")
	local draw
	LaneConfig.SetRng(function() return draw ~= nil and { random = function() return draw end, gauss = function() return 0 end } or nil end)
	local function count(ev) local n = 0 for _, l in ipairs(lines) do if l:find("ev=" .. ev .. " ", 1, true) then n = n + 1 end end return n end
	local function lastOf(ev) for i = #lines, 1, -1 do if lines[i]:find("ev=" .. ev .. " ", 1, true) then return lines[i] end end return "" end
	local function fresh()
		CoreTrade.Reset()
		Plays.ResetCache()
		bot.loc, enemy.loc = Vector(0, 0), Vector(400, 0)
		bot.hp, enemy.hp, bot.attacking, enemy.dead, bot.alive = 80, 70, nil, false, true
		T = T + 100
	end

	fresh()
	draw = 0.99
	local plays = count("play")
	check("a healthy even encounter with the draw above the weight: the trade rule", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
	check("the chance is logged, not fired", count("play") == plays + 1 and lastOf("play"):find("kind=lane_fight") and lastOf("play"):find("fire=0"))
	CoreTrade.Think(bot)
	check("a running trade still gives way to laning's last hit", not CoreTrade.LastHitYields(bot))
	T = T + 5
	draw = 0.01
	CoreTrade.Desire(bot)
	check("no second chance on the same target within 15 s, even with a winning draw", count("play") == plays + 1 and not Plays.Of(bot))

	fresh()
	draw = 0.01
	check("a winning draw fires a lane fight: the commit's desire", CoreTrade.Desire(bot) == CoreTrade.DESIRE_KILL and Plays.Of(bot) ~= nil)
	function Unit:GetNearbyLaneCreeps() return { MakeUnit({ pid = 40, team = 3, loc = Vector(100, 0) }) } end
	CoreTrade.Think(bot)
	check("a fight attacks with enemy creeps beside it (no step out)", bot.attacking == enemy)
	check("a running fight is not cut by laning's last hit (lfpchk1 t=236)", CoreTrade.LastHitYields(bot))
	function Unit:GetNearbyLaneCreeps() return {} end
	T = T + 1
	bot.hp = 35
	CoreTrade.Desire(bot)
	check("under the roll's HP floor the fight ends", lastOf("trade"):find("kind=fight") and lastOf("trade"):find("why=hp") and lastOf("trade"):find("join=0"))
	check("and its play ends with it", Plays.Of(bot) == nil)
	T = T + Plays.SETTINGS.KillAfter
	Plays.Tick(T)
	check("its end line once the kill window passes", lastOf("play_end"):find("kind=lane_fight") and lastOf("play_end"):find("why=hp"))

	fresh()
	draw = 0.01
	bot.hp, enemy.hp = 50, 90
	CoreTrade.Desire(bot)
	check("well behind the target on HP: a lane fight's own hard zero", lastOf("play"):find("zero=behind") and Plays.Of(bot) == nil)

	-- An ally's play on the enemy: our pos4 ganks it.
	fresh()
	draw = 0.01
	Plays.Define("test_gank", { base = 0.9, timeout = 20, chases = true })
	local sup = MakeUnit({ pid = 4, team = 2, loc = Vector(900, 300), hp = 90, mode = LANING })
	local play = Plays.Roll({ kind = "test_gank", by = sup, target = enemy, at = enemy.loc }, T)
	check("(setup) the ally's play fired", play ~= nil)
	enemy.loc = Vector(1000, 0)
	plays = count("play")
	check("the enemy 1,000 away, outside the core's reach but inside reach + 600: the core joins the play",
		CoreTrade.Desire(bot) == CoreTrade.DESIRE_KILL and Plays.Of(bot) == play and count("play") == plays)
	CoreTrade.Think(bot)
	check("the joiner attacks the play's target", bot.attacking == enemy)
	Plays.End(play, "test", "none", T)
	T = T + 0.5
	CoreTrade.Desire(bot)
	check("the play's end ends the joiner's fight", lastOf("trade"):find("why=play_end") and lastOf("trade"):find("join=1"))

	-- A joiner whose own fight ended (its HP floor) stays in the play: deferred to it, no roll of its own on the target.
	fresh()
	draw = 0.01
	enemy.loc = Vector(400, 0)
	play = Plays.Roll({ kind = "test_gank", by = sup, target = enemy, at = enemy.loc }, T)
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	T = T + 1
	bot.hp = 35
	CoreTrade.Desire(bot)
	check("(setup) the joiner's fight ended on its HP floor", lastOf("trade"):find("why=hp") and lastOf("trade"):find("join=1"))
	bot.hp = 80
	plays = count("play")
	T = T + 1
	check("a joiner still in the play gets no desire and no roll here", CoreTrade.Desire(bot) == 0 and count("play") == plays)
	Plays.End(play, "test", "none", T)

	-- A clear commit wins over joining an ally's play on the same enemy, and laning's last hit yields to it until OnEnd.
	fresh()
	draw = 0.01
	enemy.hp = 35
	play = Plays.Roll({ kind = "test_gank", by = sup, target = enemy, at = enemy.loc }, T)
	check("a 35% target in reach: the commit, not the join", CoreTrade.Desire(bot) == CoreTrade.DESIRE_KILL and Plays.Of(bot) == nil)
	CoreTrade.Think(bot)
	check("a running commit is not cut by laning's last hit", CoreTrade.LastHitYields(bot))
	CoreTrade.OnEnd(bot)
	check("once attack mode lost the bot, laning's last hit is back", not CoreTrade.LastHitYields(bot))
	Plays.End(play, "test", "none", T)

	fresh()
	draw = 0.01
	enemy.loc = Vector(1400, 0)
	play = Plays.Roll({ kind = "test_gank", by = sup, target = enemy, at = enemy.loc }, T)
	CoreTrade.Desire(bot)
	check("a play whose target is beyond reach + 600 is not joined", Plays.Of(bot) == nil)

	fresh()
	draw = 0.01
	bot.hp = 35
	enemy.loc = Vector(400, 0)
	play = Plays.Roll({ kind = "test_gank", by = sup, target = enemy, at = enemy.loc }, T)
	CoreTrade.Desire(bot)
	check("a core under the roll's HP floor does not join (the library's hard zero for it)", Plays.Of(bot) == nil)

	fresh()
	draw = 0.01
	Plays.Define("test_rune", { base = 0.9, timeout = 20, chases = false })
	Plays.Roll({ kind = "test_rune", by = bot, target = enemy, at = enemy.loc }, T)
	check("a core that started another context's play is driven by it: no desire here", CoreTrade.Desire(bot) == 0)

	fresh()
	draw = 0.01
	local Ours = package.loaded["bots/FunLib/custom_loader"].Ours
	Ours.CoreLaneFight = false
	plays = count("play")
	check("switch off: no lane-fight chance, the trade rule", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE and count("play") == plays)
	fresh()
	enemy.hp = 20
	check("(setup) switch off: a 20% target is the trade's kill", CoreTrade.Desire(bot) == CoreTrade.DESIRE_KILL)
	CoreTrade.Think(bot)
	check("switch off: a running kill still gives way to laning's last hit", not CoreTrade.LastHitYields(bot))
	fresh()
	Plays.Roll({ kind = "test_rune", by = bot, target = enemy, at = enemy.loc }, T)
	check("switch off: a core in another context's play keeps the trade rule", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
	Ours.CoreLaneFight = true
	LaneConfig.SetRng(nil)
	CoreTrade.Reset()
	Plays.ResetCache()
end

-- Slice hit-back (D24): a hero hitting us from inside our creeps' aggro is traded back even beside their wave or with us a
-- little behind on HP, the refusals the trade rule alone keeps; tower, numbers, our HP floor and creeps on us still refuse.
do
	check("hit back: a big enemy wave does not refuse it", CoreTrade.Decide(inputs({ enemyCreepsNear = 6 }), false, nil, true).kind == "trade")
	check("hit back: behind on HP does not refuse it", CoreTrade.Decide(inputs({ hp = 0.6, targetHp = 0.9 }), false, nil, true).kind == "trade")
	check("hit back: their tower, their numbers, our HP floor and two creeps on us still refuse it",
		CoreTrade.Decide(inputs({ tower = true }), false, nil, true).respect == "tower"
		and CoreTrade.Decide(inputs({ enemiesNear = 2 }), false, nil, true).respect == "outnumbered"
		and CoreTrade.Decide(inputs({ hp = 0.45, targetHp = 0.4 }), false, nil, true).respect == "low_hp"
		and CoreTrade.Decide(inputs({ hitByCreeps = 2 }), false, nil, true).respect == "creeps")

	local Ours = package.loaded["bots/FunLib/custom_loader"].Ours
	Ours.CoreLaneFight = false
	-- Behind on HP inside their wave: the trade rule alone refuses (`behind`, `wave`).
	local theirs = {}
	for k = 1, 5 do theirs[k] = MakeUnit({ pid = 30 + k, team = 3, loc = Vector(200, 300) }) end
	local ourCreep = MakeUnit({ pid = 40, team = 2, loc = Vector(700, 0) })
	local ourCreeps = { ourCreep }
	function Unit:GetNearbyLaneCreeps(r, enemies)
		local out = {}
		for _, c in ipairs(enemies and theirs or ourCreeps) do if GetUnitToUnitDistance(self, c) <= r then table.insert(out, c) end end
		return out
	end
	local function fresh()
		CoreTrade.Reset()
		bot.loc, enemy.loc = Vector(0, 0), Vector(400, 0)
		bot.hp, enemy.hp, bot.attacking, bot.hitBy = 60, 90, nil, nil
		T = T + 30
	end
	fresh()
	check("(setup) behind on HP in their wave and not hit: no trade", CoreTrade.Desire(bot) == 0)
	fresh()
	bot.hitBy = enemy
	check("hit by a hero standing 300 from our creep: it is traded back", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
	bot.moves, bot.orders = {}, 0
	CoreTrade.Think(bot)
	check("beside their wave the hit back first steps out of it, as a trade does", bot.orders == 0 and #bot.moves == 1)
	bot.loc = Vector(-400, 0)
	T = T + 0.3
	CoreTrade.Desire(bot)
	CoreTrade.Think(bot)
	check("clear of their creeps it attacks the hitter", bot.attacking == enemy and bot.orders == 1)
	bot.loc = Vector(0, 0)
	T = T + 0.5
	check("a running hit back is not ended by the wave or the HP gap", CoreTrade.Desire(bot) == CoreTrade.DESIRE_TRADE)
	enemy.dead = true
	T = T + 0.1
	CoreTrade.Desire(bot)
	check("its end line says it was a hit back", last():find("ev=trade") and last():find("hb=1"), last())
	enemy.dead = false
	fresh()
	bot.hitBy = enemy
	ourCreep.loc = Vector(1000, 0)
	check("hit from outside our creeps' aggro (600 from the nearest): no hit back", CoreTrade.Desire(bot) == 0)
	ourCreep.loc = Vector(700, 0)
	fresh()
	bot.hitBy = enemy
	Ours.HitBack = false
	check("switch off: the trade rule alone, so no trade", CoreTrade.Desire(bot) == 0)
	Ours.HitBack = nil
	Ours.CoreLaneFight = true
	function Unit:GetNearbyLaneCreeps() return {} end
	CoreTrade.Reset()
end

finish()
