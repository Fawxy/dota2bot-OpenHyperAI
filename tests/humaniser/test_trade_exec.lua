-- Trade's executor (design 2026-11-19-trade-decision-design.md s5, s10): Desire and Think over a stubbed world: the episode's
-- bookkeeping (open, keep, a level change in place, the ends), the memory of a lost exchange (`lost`: set at a `losing` end, cleared
-- after StayEngaged quiet seconds), what Think carries out of `how`, and the seam readers (Holds, LastHitYields, Joining).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })

local world = { creeps = {}, pair = nil, share = {}, lanes = true }
local RealThreat = require("bots/FunLib/humaniser/threat")
package.loaded["bots/FunLib/humaniser/threat"] = {
	SETTINGS = RealThreat.SETTINGS,
	SeenSpeed = function() return 300 end,
}
-- Safe.At: safe everywhere; the walks (a horizon of 4 s) are counted.
package.loaded["bots/FunLib/humaniser/safe_gather"] = {
	WalkHorizon = 4,
	At = function(_, _, opts)
		if opts ~= nil and opts.horizon == 4 then world.walkAsks = (world.walkAsks or 0) + 1 end
		return { level = "safe", ratio = math.huge, reason = "safe", kill = 0, price = 0 }
	end,
}
package.loaded["bots/FunLib/humaniser/transitions/phase"] = { LaningHeld = function() return world.lanes end }
package.loaded["bots/FunLib/humaniser/states/core_last_hit"] = { Applies = function() return true end }
package.loaded["bots/FunLib/humaniser/states/support_deny"] = { Applies = function() return false end }
package.loaded["bots/FunLib/humaniser/states/laning"] = { DenyDue = function() return false end }
package.loaded["bots/FunLib/humaniser/pair_join"] = {
	SETTINGS = { Window = 3, Keep = 1.5 },
	For = function() return world.pair or {} end,
	After = function() end,
	Reopened = function() end,
}
package.loaded["bots/FunLib/humaniser/spell_ready"] = {
	DamageOn = function(from, on) return world.share[from:GetPlayerID() .. ">" .. on:GetPlayerID()] or 0 end,
	ReadySpells = function() return {} end,
	ReadyDamage = function() return nil end,
}
package.loaded["bots/FunLib/humaniser/creep_aggro"] = { Paid = function() return false end }
package.loaded["bots/FunLib/humaniser/states/trade"] = nil
local Trade = require("bots/FunLib/humaniser/states/trade")

local function hero(pid, team, x, hp)
	local u = MakeUnit({ pid = pid, team = team, loc = Vector(x, 0), hp = hp, maxhp = 100 })
	u.range = 150
	u.lane = 2
	return u
end
local bot = hero(1, 2, 0, 100)
local enemy = hero(6, 3, 200, 100)
local Unit = getmetatable(bot)
function Unit:GetNearbyHeroes(_, enemies)
	if self ~= bot then return {} end
	if enemies then return enemy.visible == false and {} or { enemy } end
	return { self }
end
function Unit:CanBeSeen() return self.visible ~= false end
function Unit:GetNearbyLaneCreeps() return world.creeps end
function Unit:GetNearbyTowers() return {} end
function Unit:GetAttackTarget() return self.attacking end
function Unit:WasRecentlyDamagedByHero(h) return (self.hitBy or {})[h] == true end
function Unit:IsCreep() return false end
function Unit:GetLastAttackTime() return self.lastAttack or 0 end
function Unit:Action_AttackUnit(t) self.orders = self.orders or {} table.insert(self.orders, t) self.attacking = t end
function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end
function IsHeroAlive() return true end
function GetTower() return nil end
function GetUnitList(kind)
	if kind == require("bots/ts_libs/dota/index").UnitType.EnemyHeroes then return { enemy } end
	return { bot }
end
function GetAmountAlongLane() return { amount = 0.5, distance = 100 } end
function GetLocationAlongLane() return Vector(-500, 0) end

-- A favoured hit on a hero in reach.
world.share["1>6"], world.share["6>1"] = 30, 10
local function reset()
	Trade.Reset()
	bot.orders, bot.attacking, bot.hp, enemy.hp, enemy.visible, bot.hitBy = nil, nil, 100, 100, true, nil
	enemy.loc = Vector(200, 0)
end

do
	reset()
	T = 10
	local d = Trade.Desire(bot)
	check("a favoured hero in reach opens a hit: desire 0.6, the exchange is running", d == Trade.DESIRE_HIT and Trade.Running(bot))
	check("Desire took the frame, so Think follows it", Trade.OwnsFrame(bot) == true)
	Trade.Think(bot)
	check("Think primes an aggro-free attack order on the target (no creeps near)", bot.orders ~= nil and bot.orders[1] == enemy and Trade.PrimedAt(1) == 10)
	check("a hit is no arbiter pair group and does not hold the last hit", Trade.Joining(bot) == false and Trade.LastHitYields(bot) == false)
	T = 10.5
	check("the same inputs keep it, with the same episode", Trade.Desire(bot) == Trade.DESIRE_HIT and Trade.EpisodeOf(1).at == 10)
end

do
	-- The exchange turns against us before our first hit lands: the unlanded cap ends it `losing`, and the hero is remembered.
	reset()
	T = 20
	Trade.Desire(bot)
	Trade.Think(bot)
	T = 20.5
	bot.hp = 60
	bot.hitBy = { [enemy] = true }
	local d = Trade.Desire(bot)
	check("40% HP lost with nothing landed ends the hit `losing` (the unlanded cap 0.15): desire 0, no exchange", d == 0 and not Trade.Running(bot))
	bot.hp = 100
	T = 21
	local g = Trade.Gather(bot)
	check("the hero is lost: Decide gives no hit on it, whatever the favour", g.cands[1].lost == true and Trade.Decide(g).level == "none" and Trade.Decide(g).reason == "lost")
	check("and Desire opens nothing on it", Trade.Desire(bot) == 0)
	bot.hitBy = nil
end

do
	-- Cleared once neither has damaged the other for StayEngaged: here "damaged" reads true until the hit memory is dropped.
	reset()
	T = 30
	Trade.Desire(bot)
	T = 30.5
	bot.hp = 60
	Trade.Desire(bot)
	bot.hp = 100
	bot.hitBy = { [enemy] = true }
	T = 31
	local lostWhileHit = Trade.Gather(bot).cands[1].lost
	bot.hitBy = nil
	T = 37
	local lostWhenQuiet = Trade.Gather(bot).cands[1].lost
	check("lost stays while it is still hitting us and clears once it is quiet; the next frame trades again",
		lostWhileHit == true and lostWhenQuiet == false and Trade.Desire(bot) == Trade.DESIRE_HIT)
end

do
	-- The target drops to the kill bar with the catch read ok: the same exchange goes up a level in place.
	reset()
	T = 40
	Trade.Desire(bot)
	local at = Trade.EpisodeOf(1).at
	enemy.hp = 20
	enemy.speed = 300
	bot.atk = 200
	T = 40.5
	local d = Trade.Desire(bot)
	local ep = Trade.EpisodeOf(1)
	check("a hit whose target reaches the kill bar and the catch becomes the kill in place: desire 0.75, the episode kept",
		d == Trade.DESIRE_COMMIT and ep.kind == "kill" and ep.at == at)
	Trade.Think(bot)
	check("a kill commits: it names its target for OHA's casts, and it holds the last hit", bot.target == enemy and Trade.LastHitYields(bot) == true)
	check("a kill is no pair group without the pair's answer", Trade.Joining(bot) == false)
end

do
	-- The pair answers for the target: a join, in the arbiter's pair group.
	reset()
	T = 50
	world.pair = { ans = { dec = "join", tgt = 6, ko = 0.6, kt = 0.2 }, rec = { on = "hit" } }
	enemy.loc = Vector(600, 0)
	check("the pair's answer opens a join on its target: desire 0.75 and the arbiter's pair group", Trade.Desire(bot) == Trade.DESIRE_COMMIT and Trade.Joining(bot) == true)
	check("Holds is join while the pair answers", Trade.Holds(bot) == "join")
	world.pair = nil
	T = 50.5
	check("the pair keeps its answer for Keep seconds after the situation lapses", Trade.Desire(bot) == Trade.DESIRE_COMMIT)
	T = 52.5
	local d = Trade.Desire(bot)
	check("then the join ends pair_end: the hero is out of reach for a hit, so nothing opens", d == 0 and not Trade.Running(bot))
	world.pair = nil
	enemy.loc = Vector(200, 0)
end

do
	-- Holds: a hit back holds retreat while the hero hits us and the exchange favours us; a hero that is not hitting us holds nothing.
	reset()
	T = 60
	bot.hitBy = { [enemy] = true }
	check("a hitter that passes the bars holds retreat as a hit back", Trade.Holds(bot) == "hitback")
	bot.hitBy = nil
	check("a plain hit holds nothing", Trade.Holds(bot) == nil)
	world.lanes = false
	bot.hitBy = { [enemy] = true }
	check("outside the laning body's hold, nothing holds", Trade.Holds(bot) == nil and Trade.Desire(bot) == nil)
	world.lanes = true
	bot.hitBy = nil
end

do
	-- The unseen chase: a kill whose target left sight walks to its predicted place.
	reset()
	T = 70
	enemy.hp = 20
	bot.atk = 200
	Trade.Desire(bot)
	Trade.Think(bot)
	check("setup: a started kill", Trade.EpisodeOf(1).kind == "kill")
	enemy.visible = false
	function GetHeroLastSeenInfo() return { { location = Vector(500, 0), time_since_seen = 1 } } end
	T = 71
	bot.moves = nil
	local d = Trade.Desire(bot)
	Trade.Think(bot)
	check("the chase goes on past the loss of sight and moves to the predicted place", d == Trade.DESIRE_COMMIT and bot.moves ~= nil and bot.moves[#bot.moves].x >= 499)
	function GetHeroLastSeenInfo() return {} end
end

do
	-- The lane-fight chance reads the walk's threat at most once per target per 15 s, however many frames ask.
	reset()
	world.share["1>6"], world.share["6>1"] = 10, 30 -- unfavoured: no hit opens, so the chance is asked every frame
	local Plays = require("bots/FunLib/humaniser/plays/plays")
	local roll = Plays.Roll
	Plays.Roll = function() return nil end
	world.walkAsks = 0
	T = 100
	Trade.Desire(bot)
	T = 100.5
	Trade.Desire(bot)
	T = 110
	Trade.Desire(bot)
	local early = world.walkAsks
	T = 116
	Trade.Desire(bot)
	check("the walk read for a chance is taken once per target per 15 s (frames at 100, 100.5, 110: one read; 116: a second)",
		early == 1 and world.walkAsks == 2, tostring(early) .. "/" .. tostring(world.walkAsks))
	Plays.Roll = roll
	world.share["1>6"], world.share["6>1"] = 30, 10
end

do
	-- A lane-fight play that fires but is not answered with a join on it ends at once, not at its timeout.
	reset()
	local Plays = require("bots/FunLib/humaniser/plays/plays")
	local roll, finish_ = Plays.Roll, Plays.End
	local ended = {}
	Plays.Roll = function(c)
		return { id = 90, kind = "lane_fight", by = c.by, target = c.target, tgt = c.target:GetPlayerID(), at = c.at, started = T, joiners = {} }
	end
	Plays.End = function(p, why) table.insert(ended, { p.id, why }) end
	T = 200
	Trade.Desire(bot)
	check("a fired play whose answer is a hit, not a join on it, is ended `refused` at once",
		#ended == 1 and ended[1][1] == 90 and ended[1][2] == "refused")
	Plays.Roll, Plays.End = roll, finish_
end

finish()
