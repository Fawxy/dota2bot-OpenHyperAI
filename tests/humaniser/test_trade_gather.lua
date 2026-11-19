-- Trade.Gather (design 2026-11-19-trade-decision-design.md s1, the Inputs table): what it reads, from which call, for which candidate;
-- Decide on what it gathered; and the cut line. SafeGather, Threat, PairJoin, Laning, SpellReady and CreepAggro are stubbed: this file tests
-- Gather's own wiring (which question, over which horizon, for whom), not their numbers.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })

local world = { ats = {}, here = { level = "safe", ratio = 2.5, reason = "safe", kill = 0, price = 0 }, walk = { level = "safe", ratio = 3, reason = "safe", kill = 0, price = 0 },
	deny = false, pair = nil, share = {}, paid = false }
local RealThreat = require("bots/FunLib/humaniser/threat")
-- Safe.At is asked for a place with the options the consumer passes; the answer is the world's `here` for the hero's own place and `walk` elsewhere.
package.loaded["bots/FunLib/humaniser/safe_gather"] = {
	WalkHorizon = 4,
	At = function(bot, place, opts)
		table.insert(world.ats, { place = place, opts = opts })
		local here = bot:GetLocation()
		return (place.x == here.x and place.y == here.y) and world.here or world.walk
	end,
}
package.loaded["bots/FunLib/humaniser/states/laning"] = { DenyDue = function() return world.deny end }
package.loaded["bots/FunLib/humaniser/pair_join"] = {
	SETTINGS = { Window = 3, Keep = 1.5 },
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
	local a, b = world.ats[1], world.ats[2]
	check("here is asked twice, held and over the stay horizon (the default): without a hold for a hit, with one for the rest; the hit's answer is named `trade`",
		#world.ats == 2 and a.place.x == 0 and a.opts.held == true and a.opts.hold == false and a.opts.who == "trade" and a.opts.horizon == nil
			and b.opts.held == true and b.opts.hold == true and b.opts.who == nil and i.hp == 0.8 and i.n == 1
			and i.safe.hit.level == "safe" and i.safe.hold.ratio == 2.5)
	local c = i.cands[1]
	check("a candidate carries its distance, the gap past our range and both hulls, ",
		c.pid == 6 and c.d == 900 and c.gap == 900 - (150 + 24 + 24) and c.thp == 0.7 and c.thpAbs == 70)
	check("a hero at 0.7 HP is no kill candidate: no walk read, no catch read", c.walk == nil and c.catch == nil and #world.ats == 2)
	check("our attack point is the stop at attack range, outside a tower 5,000 away", c.tw == false and i.towerOnMe == false)
	check("Decide on what was gathered: it is out of reach in 0.5 s, so no hit",
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
	local w = world.ats[#world.ats]
	check("a kill candidate (0.3 HP) gets Safe.At along the walk to its place: 4 s, away, not held, with a hold; the answer is read as level, ratio and reason",
		c.walk ~= nil and c.walk.level == "safe" and c.walk.ratio == 3 and c.walk.reason == "safe"
			and w.place.x == 190 and w.opts.horizon == 4 and w.opts.away == true and w.opts.held == false and w.opts.hold == true and w.opts.who == "trade_walk")
	check("and a catch read from the hunters: the bot's dps on its HP", c.catch ~= nil and c.catch.ok == true and #c.hunters == 1)
	world.ats = {}
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
	world.pair = { ans = { dec = "losing", tgt = 6, ko = 0.5, kt = 0.2 }, rec = {} }
	local joined = Trade.Gather(bot).pair
	check("the pair answer is read as its target and kill shares whatever its label",
		joined ~= nil and joined.tgt == 6 and joined.ko == 0.5 and joined.kt == 0.2 and joined.dec == "losing")
	world.pair = nil
end

-- A running play near us we may join: the joiner's hard zero is Safe.At's answer for its walk to the target (4 s, away, hold, named `play`):
-- deadly zeroes it with the answer's reason, and two down at 0.3 HP (the old outnumbered and HP zeros) does not.
do
	local Plays = require("bots/FunLib/humaniser/plays/plays")
	local near, inputs, of = Plays.Near, Plays.InputsOf, Plays.Of
	local other = hero(9, 2, 100, 100)
	Plays.Of = function() return nil end
	Plays.Near = function() return { { id = 5, kind = "lane_fight", by = other, target = enemy, tgt = 6, at = enemy.loc, joiners = {} } } end
	Plays.InputsOf = function(c) return { kind = c.kind, ourLevel = 5, theirLevel = 5, ours = 1, theirs = 3, hp = 0.3, mana = 1, rune = false, tower = 5000, skill = 1 } end
	enemy.loc, enemy.hp = Vector(300, 0), 70
	world.ats = {}
	world.walk = { level = "deadly", ratio = 0.5, reason = "kill", kill = 900, price = 0 }
	local dead = Trade.Gather(bot).play
	local asked
	for _, a in ipairs(world.ats) do if a.opts.who == "play" then asked = a end end
	world.walk = { level = "safe", ratio = 3, reason = "safe", kill = 0, price = 0 }
	local ok = Trade.Gather(bot).play
	check("a joiner's walk to the play's target is asked as `play` (4 s, away, not held, hold); deadly zeroes it with the reason",
		asked ~= nil and asked.opts.horizon == 4 and asked.opts.away == true and asked.opts.held == false and asked.opts.hold == true
			and asked.place.x == 300 and dead ~= nil and dead.zero == "kill")
	check("a safe walk with two down at 0.3 HP is no zero for the joiner", ok ~= nil and ok.zero == nil, ok and ok.zero)
	Plays.Near, Plays.InputsOf, Plays.Of = near, inputs, of
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
