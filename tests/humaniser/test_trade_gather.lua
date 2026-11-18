-- Trade.Gather (design 2026-11-19-trade-decision-design.md s1, the Inputs table): what it reads, from which call, for which candidate;
-- Decide on what it gathered; and the cut line. Threat, PairJoin, Laning, SpellReady and CreepAggro are stubbed: this file tests
-- Gather's own wiring (which read, over which horizon, for whom), not their numbers.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })

local world = { burst = 0.3, reach = {}, missing = 0, reads = {}, walks = {}, deny = false, pair = nil, share = {}, paid = false }
local RealThreat = require("bots/FunLib/humaniser/threat")
local function read(horizon, from, place, opts)
	return { burst = world.burst, reach = world.reach, missing = world.missing, mpids = {} }
end
package.loaded["bots/FunLib/humaniser/threat"] = {
	SETTINGS = RealThreat.SETTINGS,
	SeenSpeed = function() return 300 end,
	Read = function(_, _, place, horizon, opts)
		table.insert(world.reads, { horizon = horizon, engaged = opts and opts.engagedWindow, place = place })
		return read(horizon)
	end,
	Reader = function(_, horizon)
		return function(_, place)
			table.insert(world.walks, { horizon = horizon, place = place })
			return { burst = 0.55, reach = { 1, 2 }, missing = 0.2, mpids = {} }
		end
	end,
}
package.loaded["bots/FunLib/humaniser/states/laning"] = { DenyDue = function() return world.deny end }
package.loaded["bots/FunLib/humaniser/pair_join"] = {
	SETTINGS = { Window = 3 },
	For = function() return world.pair or {} end,
}
package.loaded["bots/FunLib/humaniser/spell_ready"] = {
	DamageOn = function(from, on) return (world.share[from:GetPlayerID() .. ">" .. on:GetPlayerID()] or 0) end,
	ReadySpells = function() return {} end,
}
package.loaded["bots/FunLib/humaniser/creep_aggro"] = { Paid = function() return world.paid end }
package.loaded["bots/FunLib/humaniser/states/trade"] = nil
local Trade = require("bots/FunLib/humaniser/states/trade")

local function hero(pid, team, x, hp, range)
	local u = MakeUnit({ pid = pid, team = team, loc = Vector(x, 0), hp = hp, maxhp = 100 })
	u.range = range or 150
	return u
end
local bot = hero(1, 2, 0, 80, 150)
local enemy = hero(6, 3, 900, 70, 150)
local tower = MakeUnit({ pid = -1, team = 3, loc = Vector(5000, 0), hp = 100 })
local creeps = {}
local Unit = getmetatable(bot)
function Unit:GetNearbyHeroes(_, enemies)
	if self ~= bot then return {} end
	return enemies and { enemy } or { self }
end
function Unit:GetNearbyLaneCreeps() return creeps end
function Unit:GetNearbyTowers(_, enemies) return enemies and { tower } or {} end
function Unit:GetAttackTarget() return self.attacking end
function Unit:WasRecentlyDamagedByHero() return self.hitMe == true end
function Unit:IsCreep() return false end
function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end
function IsHeroAlive() return true end
function GetTower() return nil end

do
	world.share["1>6"] = 20
	local i = Trade.Gather(bot)
	local r = world.reads[1]
	check("the read here is Threat's stay read: 2 s, a hitter over 6 s, burst and heroes from it",
		#world.reads == 1 and r.horizon == 2 and r.engaged == 6 and i.burst == 0.3 and i.n == 0 and i.hp == 0.8)
	local c = i.cands[1]
	check("a candidate carries its distance, the gap past our range and both hulls, and whether we reach it in time",
		c.pid == 6 and c.d == 900 and c.gap == 900 - (150 + 24 + 24) and c.arrives == false and c.thp == 0.7 and c.thpAbs == 70)
	check("a hero at 0.7 HP is no kill candidate: no walk read, no catch read", c.walk == nil and c.catch == nil and #world.walks == 0)
	check("our attack point is the stop at attack range, outside a tower 5,000 away", c.tw == false and i.towerOnMe == false)
	check("Decide on what was gathered: it is out of reach in 1.5 s, so no hit",
		Trade.Decide(i).level == "none" and Trade.Decide(i).reason == "no_reach")
end

do
	enemy.loc = Vector(190, 0)
	enemy.hp = 30
	enemy.range = 100
	world.share["1>6"], world.share["6>1"] = 20, 5
	bot.range = 600
	local i = Trade.Gather(bot)
	local c = i.cands[1]
	check("range 600 over 100: the hit is free, and the damage shares are not asked", c.free == true and c.ko == 0 and c.kt == 0)
	check("a kill candidate (0.3 HP) gets the walk read over GateHorizon to its place",
		c.walk ~= nil and c.walk.burst == 0.55 and c.walk.n == 2 and world.walks[1].horizon == RealThreat.SETTINGS.GateHorizon
			and world.walks[1].place.x == 190)
	check("and a catch read from the hunters: the bot's dps on its HP", c.catch ~= nil and c.catch.ok == true and #c.hunters == 1)
	world.walks = {}
	enemy.hp = 70
	bot.range = 150
	enemy.range = 150
	local f = Trade.Gather(bot).cands[1]
	check("not free: ko and kt are read from the damage estimates over their HP", f.free == false and math.abs(f.ko - 20 / 70) < 1e-9 and math.abs(f.kt - 5 / 80) < 1e-9)
end

do
	bot.hitMe = true
	enemy.loc = Vector(300, 0)
	creeps[1], creeps[2] = hero(20, 3, 100, 100), hero(21, 3, 100, 100)
	creeps[1].attacking = bot
	creeps[1].IsAlive = function() return true end
	creeps[2].IsAlive = function() return true end
	tower.attacking = bot
	world.deny = true
	world.paid = true
	local i = Trade.Gather(bot)
	check("creeps on us count one each and a tower attacking us two; the wave counts every creep within 500",
		i.creepsOnMe == 3 and i.wave == 2 and i.towerOnMe == true)
	check("a hero that hit us is hitting and, in our creeps' aggro, paid; a due deny is read", i.cands[1].hitting == true and i.cands[1].paid == true and i.denyDue == true)
	tower.attacking = nil
	bot.hitMe = false
end

do
	world.pair = { ans = { dec = "outnumbered", tgt = 6, ko = 0.5, kt = 0.2 }, rec = { on = "hit" } }
	local joined = Trade.Gather(bot).pair
	world.pair = { ans = { dec = "join", tgt = 6, ko = 0.5, kt = 0.2 }, rec = { on = "ours" } }
	local ours = Trade.Gather(bot).pair
	check("the pair answer is read as its target and kill shares whatever its label; an `ours` record is no pair answer",
		joined ~= nil and joined.tgt == 6 and joined.dec == "outnumbered" and ours == nil)
	world.pair = nil
end

do
	local i = Trade.Gather(bot, { level = "hit", target = 6, offered = 2, started = 1, landed = true, soFar = 0.02, catchFails = 0 })
	check("a running exchange's target is read alive and kept in the inputs", i.run ~= nil and i.run.alive == true and i.run.level == "hit")
	local seen = Trade.Gather(bot, { level = "kill", target = 6, offered = 2, started = 1, landed = false, soFar = 0, catchFails = 0 })
	check("a running kill's target gets the walk and the catch read even above the kill bar", seen.cands[1].walk ~= nil and seen.cands[1].catch ~= nil)
	enemy.loc = Vector(5000, 5000)
	local savedNear = Unit.GetNearbyHeroes
	function Unit:GetNearbyHeroes(_, enemies) if enemies then return {} end return { self } end
	function GetHeroLastSeenInfo() return { { location = Vector(1000, 0), time_since_seen = 2 } } end
	local gone = Trade.Gather(bot, { level = "kill", target = 6, offered = 2, started = 1, landed = false, soFar = 0, catchFails = 0 })
	check("an unseen kill chases the place it was last seen, moved on by its last seen velocity, and reads the place",
		#gone.cands == 0 and gone.run.chaseAt ~= nil and gone.run.unseen ~= nil and gone.run.catch ~= nil and gone.run.chaseAt.x > 999)
	Unit.GetNearbyHeroes = savedNear
end

finish()
