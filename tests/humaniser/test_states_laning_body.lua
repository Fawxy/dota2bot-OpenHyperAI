dofile(HARNESS_DIR .. "/dota_stubs.lua")
local function no() return false end
local HostSteps = { etiquette = no, ohaLastHit = no, ohaDeny = no, ohaHold = no, ohaLocal = no, ohaPosition = function() return true end }

-- Team slices 3 and 4: the laning state's own spot (lane_spot.ts: creep and tower rings, ranged inset, side
-- shift) and its SDK last hits (laning.ts body + BodyLastHits gating the Lua Think's own).
local BUNDLE = "bots/FunLib/engine/tasks"
local LANING = 1
BOT_MODE_LANING = LANING

-- A lane along the x axis: our front at x = 0, our base towards -x.
function GetLaneFrontLocation(team, lane, delta) return Vector(delta, 0) end
function GetLaneFrontAmount() return 0.5 end

-- Unit API the spot and the verbs need, on top of dota_stubs (whose Unit metatable is local to it).
ResetWorld()
local Unit = getmetatable(MakeUnit({ pid = 99 }))
function Unit:GetNearbyLaneCreeps(r, enemies)
	local out = {}
	for _, c in ipairs(CREEPS or {}) do
		local enemy = c.team ~= self.team
		if c.alive and enemy == enemies and GetUnitToLocationDistance(self, c.loc) <= r then out[#out + 1] = c end
	end
	return out
end
function Unit:GetNearbyHeroes(r, enemies)
	local out = {}
	for t = 2, 3 do
		for _, u in ipairs(UNITS[t]) do
			if u ~= self and u.alive and (u.team ~= self.team) == enemies and GetUnitToLocationDistance(self, u.loc) <= r then out[#out + 1] = u end
		end
	end
	return out
end
function Unit:GetNearbyTowers(r, enemies)
	local out = {}
	for _, tw in ipairs(TOWERS or {}) do
		if (tw.team ~= self.team) == enemies and GetUnitToLocationDistance(self, tw.loc) <= r then out[#out + 1] = tw end
	end
	return out
end
function Unit:GetAttackDamage() return self.damage or 50 end
function Unit:GetAttackPoint() return self.attackPoint or 0.3 end
function Unit:GetAttackTarget() return self.target end
function Unit:GetHealthRegen() return self.regen or 0 end
function Unit:GetDenies() return self.denies or 0 end
function Unit:GetCurrentMovementSpeed() return 300 end
function Unit:GetBoundingRadius() return 24 end
function Unit:WasRecentlyDamagedByAnyHero() return false end
function Unit:WasRecentlyDamagedByHero(e, t) return self.hitBy ~= nil and self.hitBy[e] ~= nil and T - self.hitBy[e] <= t end
function Unit:WasRecentlyDamagedByCreep() return false end
function Unit:WasRecentlyDamagedByTower() return false end
function Unit:Action_AttackUnit(u) self.attacks = self.attacks or {} table.insert(self.attacks, u) end

-- The spot's hero limit is Safe.At, whose read asks which enemy heroes are in sight and which are out of it (none here).
IsHeroAlive = IsHeroAlive or function() return false end
GetHeroLastSeenInfo = GetHeroLastSeenInfo or function() return {} end
GetUnitToUnitDistance = GetUnitToUnitDistance or function(a, b) return math.sqrt((a.loc.x - b.loc.x) ^ 2 + (a.loc.y - b.loc.y) ^ 2) end

local function creep(o)
	local c = setmetatable({ pid = -1, team = o.team or 3, alive = true, loc = o.loc, hp = o.hp or 550, regen = o.regen,
		name = o.name or "npc_dota_creep_badguys_melee", modifiers = {} }, Unit)
	CREEPS[#CREEPS + 1] = c
	return c
end

local function Fresh(states, o)
	ResetWorld()
	T = 10
	CREEPS, TOWERS = {}, {}
	package.loaded[BUNDLE] = nil
	local H = FreshHumaniser({ Enable = true, Lane = { Enable = false }, Transitions = { Enable = false }, Telemetry = { Enable = true }, States = states })
	o = o or {}
	-- Slice 5's Ours.CoreLastHit makes the body own pos1-3's last hits on both teams; the older cases here test the
	-- States settings with it off (OHA's path), and slice 5's cases at the end turn it on.
	package.loaded["bots/FunLib/custom_loader"].Ours = { CoreLastHit = o.coreLastHit == true, CoreLastHitDire = o.direOff ~= true,
		SupportDeny = o.supportDeny == true, SupportDenyDire = o.supportDireOff ~= true, SupportLastHit = o.supportLastHit ~= false, LaneSpot = o.laneSpot,
		LaneSpotTower = o.laneSpotTower }
	local Phase = require("bots/FunLib/humaniser/transitions/phase")
	Phase.LaningHeld = function() return true end
	local LaneConfig = require("bots/FunLib/humaniser/lane_config")
	local positions = {}
	LaneConfig.SetHelpers({ GetPosition = function(u) return positions[u.pid] end })
	MakeUnit({ pid = 0, bot = false, loc = Vector(-4000, -4000) })
	local bot = MakeUnit({ pid = 1, team = o.team, mode = LANING, loc = o.loc or Vector(-300, 0), level = o.level or 3, hp = o.hp })
	bot.range = o.range
	positions[1] = o.pos or 2
	local UT = require("bots/ts_libs/dota/index").UnitType
	GetUnitList = function(t)
		local out = {}
		if t ~= UT.EnemyHeroes then return out end
		for team = 2, 3 do
			for _, u in ipairs(UNITS[team]) do
				if u ~= bot and u.alive and u.team ~= bot.team and u.pid ~= nil and u.pid >= 0 then out[#out + 1] = u end
			end
		end
		return out
	end
	return H, bot, positions
end

local function spotFor(states, o, setup)
	local H, bot = Fresh(states, o)
	if setup then setup(bot) end
	local Laning = require("bots/FunLib/humaniser/states/laning")
	return Laning.Spot(bot), bot, H
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local SDK = { Enable = true, Own = { laning = { 2 } }, Laning = { Spot = "sdk" } }

-- Melee core: behind our creep line, outside every enemy melee creep's 520 ring.
do
	local c
	local s = spotFor(SDK, nil, function() c = creep({ loc = Vector(60, 0) }) end)
	check("melee: spot outside the 520 ring", s ~= nil and dist(s, c.loc) >= 520, s and dist(s, c.loc))
	check("melee: not pushed further than one step past it", s ~= nil and dist(s, c.loc) < 520 + 50 + 1, s and dist(s, c.loc))
	check("melee: on our side of the wave", s ~= nil and s.x < 0, s and s.x)
end

-- The ranged creep's ring is 620.
do
	local c
	local s = spotFor(SDK, nil, function()
		creep({ loc = Vector(60, 0) })
		c = creep({ loc = Vector(200, 0), name = "npc_dota_creep_badguys_ranged" })
	end)
	check("ranged creep: spot outside its 620 ring", s ~= nil and dist(s, c.loc) >= 620, s and dist(s, c.loc))
end

-- Ranged core (range 600): attack range - 50 from the lowest-HP enemy creep, not from the front.
do
	local low
	local s = spotFor(SDK, { range = 600 }, function()
		creep({ loc = Vector(300, 0), hp = 500 })
		low = creep({ loc = Vector(150, 0), hp = 120 })
	end)
	check("ranged core: 550 from the lowest-HP creep", s ~= nil and math.abs(dist(s, low.loc) - 550) < 1, s and dist(s, low.loc))
end

-- Enemy tower: outside its 750 range plus the hold's 80 drift even where the creep rings allow closer, at every level (nothing
-- in lane owns a dive).
do
	local tower = { team = 3, loc = Vector(200, 0) }
	tower.GetLocation = function() return tower.loc end
	local setup = function() creep({ loc = Vector(60, 0) }) TOWERS = { tower } end
	tower.IsAlive = function() return true end
	tower.IsNull = function() return false end
	tower.GetAttackTarget = tower.GetAttackTarget or function() return nil end
	tower.GetAttackRange = tower.GetAttackRange or function() return 700 end
	tower.GetBoundingRadius = tower.GetBoundingRadius or function() return 144 end
	local s3 = spotFor(SDK, { level = 3 }, setup)
	check("tower ring + drift at level 3", s3 ~= nil and dist(s3, tower.loc) >= 830, s3 and dist(s3, tower.loc))
	local s6 = spotFor(SDK, { level = 6 }, setup)
	check("tower ring at level 6 too", s6 ~= nil and dist(s6, tower.loc) >= 830, s6 and dist(s6, tower.loc))
end

-- Side shift: a core moves away from the enemy hero, a support (pos 5) towards its approach line.
do
	local setup = function() creep({ loc = Vector(60, 0) }) MakeUnit({ pid = 7, team = 3, loc = Vector(200, 500) }) end
	local core = spotFor(SDK, { pos = 2 }, setup)
	local sup = spotFor(SDK, { pos = 5 }, setup)
	check("core shifts away from the enemy hero", core ~= nil and core.y < 0, core and core.y)
	check("support shifts towards the enemy hero", sup ~= nil and sup.y > 0, sup and sup.y)
end

-- Slice support-spot: a support (range 600) stands attack range - 50 behind our front, so the front creeps stay in deny reach;
-- a melee core 100 behind it. The enemy creep is far enough ahead that no ring moves either point.
do
	local setup = function() creep({ loc = Vector(800, 0) }) end
	local sup = spotFor(SDK, { pos = 5, range = 600 }, setup)
	local core = spotFor(SDK, { pos = 2 }, setup)
	check("support: 550 behind our front", sup ~= nil and sup.x == -550 and sup.y == 0, sup and sup.x)
	check("melee core: 100 behind our front", core ~= nil and core.x == -100, core and core.x)
end

-- An enemy hero's ready nukes for ev=lane_pos: trained, not passive or hidden, off cooldown, affordable and with damage; the
-- longest cast range among them.
do
	local function ability(o)
		return { IsNull = function() return false end, IsHidden = function() return o.hidden == true end,
			IsPassive = function() return o.passive == true end, GetLevel = function() return o.level or 1 end,
			GetAbilityDamage = function() return o.dmg or 100 end, GetCooldownTimeRemaining = function() return o.cd or 0 end,
			GetManaCost = function() return o.mana or 50 end, GetCastRange = function() return o.range end }
	end
	ResetWorld()
	local e = MakeUnit({ pid = 7, team = 3, loc = Vector(0, 0) })
	e.mana = 120
	e.abilities = { [0] = ability({ range = 700 }), [1] = ability({ range = 900, cd = 4 }), [2] = ability({ range = 1000, passive = true }),
		[3] = ability({ range = 1100, mana = 200 }), [4] = ability({ range = 1200, dmg = 0 }), [5] = ability({ range = 650, level = 0 }) }
	local LaneSpot = require("bots/FunLib/humaniser/states/lane_spot")
	local res = LaneSpot.ReadyNukes(e)
	local n, r = res[1], res[2]
	check("ready nukes: one of six is castable now, range 700", n == 1 and r == 700, tostring(n) .. " " .. tostring(r))
	e.abilities[1] = ability({ range = 900 })
	res = LaneSpot.ReadyNukes(e)
	n, r = res[1], res[2]
	check("ready nukes: the second off cooldown, the longer range", n == 2 and r == 900, tostring(n) .. " " .. tostring(r))
end

-- No enemy wave in sight (between waves, walking out): our own front, 100 behind it, not OHA's spot; the tower ring still holds.
do
	local s, bot, H = spotFor(SDK)
	H.States.SetLaneSpot(bot, function() return Vector(-777, 5) end)
	local Laning = require("bots/FunLib/humaniser/states/laning")
	T = T + 1 -- the spot is cached per frame
	s = Laning.Spot(bot)
	check("no wave: 100 behind our front", s ~= nil and s.x == -100 and s.y == 0, s and s.x)
	check("no wave: anchor reads wave", Laning.SpotInfo(bot) ~= nil and Laning.SpotInfo(bot).anchor == "wave")
	local tower = { team = 3, loc = Vector(300, 0) }
	tower.GetLocation = function() return tower.loc end
	tower.IsAlive = function() return true end
	tower.IsNull = function() return false end
	tower.GetAttackTarget = tower.GetAttackTarget or function() return nil end
	tower.GetAttackRange = tower.GetAttackRange or function() return 700 end
	tower.GetBoundingRadius = tower.GetBoundingRadius or function() return 144 end
	local st = spotFor(SDK, nil, function() TOWERS = { tower } end)
	check("no wave: outside an enemy tower", st ~= nil and dist(st, tower.loc) >= 830, st and dist(st, tower.loc))
end

-- The HP margin (step 0: cores laning took back from retreat at 45-48% HP walked into the enemy wave). A melee creep 600 from
-- the preferred point: at full HP the core stands on it; at 30% HP the ring grows by 240 and moves it back (why=hp); at 20% by 300.
do
	local c
	local setup = function() c = creep({ loc = Vector(500, 0) }) end
	local full, botf = spotFor(SDK, { hp = 100 }, setup)
	local Laning = require("bots/FunLib/humaniser/states/laning")
	check("hp 100%: the preferred point", full ~= nil and full.x == -100 and Laning.SpotInfo(botf).why == "pref", full and full.x)
	local low, botl = spotFor(SDK, { hp = 30 }, setup)
	Laning = require("bots/FunLib/humaniser/states/laning")
	check("hp 30%: outside the ring + 240", low ~= nil and dist(low, c.loc) >= 520 + 240 and dist(low, c.loc) < 520 + 240 + 51, low and dist(low, c.loc))
	check("hp 30%: why=hp", Laning.SpotInfo(botl).why == "hp" and Laning.SpotInfo(botl).margin == 240, Laning.SpotInfo(botl).why)
	local vlow = spotFor(SDK, { hp = 20 }, setup)
	check("hp 20%: outside the ring + 300", vlow ~= nil and dist(vlow, c.loc) >= 820, vlow and dist(vlow, c.loc))
end

-- The hero limit is Safe.At (design 2026-11-19-safe-here-design.md s3): a candidate is refused when the kill line of the heroes that
-- can reach its walk within 3 s (fresh) or 2 s (held) is over HP / 1.25 (held) or 1.25 x 1.15 (fresh), and the refusal's why is the answer's reason.
-- The bot has 100 of 100 HP, so a hero's `estDamage` is its kill line in percent of HP.
local function atFor(bot, p, held)
	-- Behind the bot, away from every hero, the spot reads the place alone.
	return require("bots/FunLib/humaniser/safe_gather").At(bot, p, { from = p, held = held == true })
end
do
	local function run(est, o)
		local e
		local s, bot = spotFor(SDK, o, function(b)
			e = MakeUnit({ pid = 7, team = 3, loc = Vector(600, 0) })
			e.range = 550
			e.estDamage = est
		end)
		return s, bot, e, require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	end
	local s, bot, e, info = run(100)
	check("hero: a kill line of 100% refuses the preferred point, why=kill", s ~= nil and info.why == "kill" and s.x < -100, info and tostring(info.why))
	check("hero: the chosen spot is itself not deadly, and the point one step nearer is", s ~= nil and atFor(bot, s).level ~= "deadly"
		and atFor(bot, Vector(s.x + 50, s.y)).level == "deadly", s and s and s.x)
	local sc, _, _, ic = run(10)
	check("hero control: the same hero at a tenth of the damage (ratio 10) leaves the preferred point", sc ~= nil and ic.why == "pref" and sc.x == -100, ic and tostring(ic.why))
	check("hero: ev=lane_pos carries the answers at the chosen spot and the preferred point", info.sl ~= nil and info.pl == "deadly" and info.pq ~= nil and info.pq < 1.4375, info and tostring(info.pl))
end

-- A place the hero holds is judged at 1.25, a fresh one at 1.25 x 1.15 = 1.44: with a kill line of 77 of 100 HP (ratio 1.3) the
-- preferred point is kept by a bot standing on it and refused to one a step away.
do
	local function run(botX)
		local e
		local s, bot = spotFor(SDK, nil, function(b)
			b.loc = Vector(botX, 0)
			e = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) })
			e.range = 550
			e.estDamage = 77
		end)
		return s, require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	end
	local sHeld, iHeld = run(-100)
	check("held: a bot on the preferred point keeps it at ratio 1.3", sHeld ~= nil and iHeld.why == "pref" and sHeld.x == -100, iHeld and tostring(iHeld.why))
	local sFresh, iFresh = run(-400)
	check("fresh: the same point 300 away is refused at ratio 1.3 (bar 1.44)", sFresh ~= nil and iFresh.why == "kill" and sFresh.x < -100, iFresh and tostring(iFresh.why))
end

-- Heroes are counted by what they can do, not by head: two in reach at full HP with 10 damage each (rtch9's `pressured` read, which the
-- old rule refused) keep the point; with 60 each (kill line 120) it is refused.
do
	local function run(est)
		local s, bot = spotFor(SDK, nil, function(b)
			for k, y in ipairs({ 0, 150 }) do
				local f = MakeUnit({ pid = 6 + k, team = 3, loc = Vector(300, y) })
				f.range = 150
				f.estDamage = est
			end
		end)
		return s, require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	end
	local sLow, iLow = run(10)
	check("two heroes, 10 damage each: the preferred point stays", sLow ~= nil and iLow.why == "pref", iLow and tostring(iLow.why))
	local sHigh, iHigh = run(60)
	check("two heroes, 60 damage each: refused, why=kill", sHigh ~= nil and iHigh.why == "kill", iHigh and tostring(iHigh.why))
end

-- A hero already hitting us is counted over 6 s, not 2 (rtlng1c2: a lone chaser kept hitting her to 45% because a short window of him
-- read safe every second). 10 damage a second against 60 HP: 20 over 2 s (ratio 3), 60 over 6 s (ratio 1).
do
	local function run(o)
		local e3
		local s, b = spotFor(SDK, o, function(b)
			e3 = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) })
			e3.range = 150
			e3.GetEstimatedDamageToTarget = function(_, _, _, dur) return 10 * dur end
			if o.engaged then b.hitBy = { [e3] = T - 0.5 } end
		end)
		return s, require("bots/FunLib/humaniser/states/laning").SpotInfo(b)
	end
	local sEng, iEng = run({ hp = 60, engaged = true })
	check("engaged: a hero hitting us at 60% HP is counted over 6 s and the point is refused", sEng ~= nil and iEng.why == "kill", iEng and tostring(iEng.why))
	local sNot, iNot = run({ hp = 60 })
	check("not engaged: the same hero over 2 s keeps the preferred point", sNot ~= nil and iNot.why == "pref", iNot and tostring(iNot.why))
	local sFull, iFull = run({ hp = 100, engaged = true })
	check("engaged at full HP: 60 of 100 (ratio 1.67) keeps the point: a lone harasser is not pushed back", sFull ~= nil and iFull.why == "pref", iFull and tostring(iFull.why))
end

-- No candidate within the XP limit or the XP range clears a deadly hero's reach and the tower ring (an enemy ranged hero just behind the preferred point): the fallback is
-- the furthest back that still keeps an enemy tower's ring, not the XP limit inside it (lposchk2: 13 idle seconds in tower range
-- from the old fallback).
do
	local tower = { team = 3, loc = Vector(-1300, 0) }
	tower.GetLocation = function() return tower.loc end
	tower.IsAlive = function() return true end
	tower.IsNull = function() return false end
	tower.GetAttackTarget = tower.GetAttackTarget or function() return nil end
	tower.GetAttackRange = tower.GetAttackRange or function() return 700 end
	tower.GetBoundingRadius = tower.GetBoundingRadius or function() return 144 end
	local e
	local s, bot = spotFor(SDK, nil, function()
		e = MakeUnit({ pid = 7, team = 3, loc = Vector(-600, 0) }) e.range = 550 e.estDamage = 100
		TOWERS = { tower }
	end)
	local info = require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	check("xp fallback: why=xp", info ~= nil and info.why == "xp", info and info.why)
	check("xp fallback: outside the tower ring + drift", s ~= nil and dist(s, tower.loc) >= 830, s and dist(s, tower.loc))
	check("xp fallback: as far back as the tower allows", s ~= nil and dist(s, tower.loc) < 830 + 60, s and dist(s, tower.loc))
end

-- The XP-only spot: when every candidate within the 1,000 back is deadly, the nearest place beyond it that is not deadly and still within
-- 1,500 of the wave (why=xp). A hero 400 from the preferred point with range 550 reaches about 1,450 over a fresh place's 3 s, which covers every
-- candidate inside the 1,000; one with range 400 (reach about 1,300) leaves a place inside the 1,000, so the same lane has no XP-only spot (control).
do
	local function run(range)
		local e
		local s, bot = spotFor(SDK, nil, function()
			e = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) })
			e.range = range
			e.estDamage = 100
		end)
		return s, bot, require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	end
	local s, bot, info = run(550)
	check("xp-only: every candidate inside 1,000 is deadly, the spot is beyond them, why=xp", s ~= nil and info.why == "xp" and s.x < -1100 and s.x >= -1500, s and (tostring(info.why) .. " " .. s.x))
	check("xp-only: the spot is not deadly and the place a step nearer is", s ~= nil and atFor(bot, s).level ~= "deadly" and atFor(bot, Vector(s.x + 50, s.y)).level == "deadly", s and s.x)
	local sc, _, ic = run(400)
	check("xp-only control: with a place inside 1,000 that passes, the spot is that place, why=kill", sc ~= nil and ic.why == "kill" and sc.x >= -1100, sc and (tostring(ic.why) .. " " .. sc.x))
end

-- A ring cleared sideways when that gives up less ground than going back: a creep just off the axis behind the preferred point.
do
	local c
	local s = spotFor(SDK, nil, function() creep({ loc = Vector(60, 0) }) c = creep({ loc = Vector(-700, -300) }) end)
	check("both rings kept", s ~= nil and dist(s, Vector(60, 0)) >= 520 and dist(s, c.loc) >= 520, s and (s.x .. "," .. s.y))
end

-- Our own tower (Ours.LaneSpotTower). prhchk2: under our tower the creep ring kept melee cores beyond a 1 s walk of the creeps
-- the tower was hitting. Our tower at (-500, 0), range 700.
local function ownTower(x, y, target)
	local tower = { team = 2, loc = Vector(x, y), target = target }
	tower.GetLocation = function() return tower.loc end
	tower.IsAlive = function() return true end
	tower.IsNull = function() return false end
	tower.GetAttackTarget = tower.GetAttackTarget or function() return nil end
	tower.GetAttackRange = tower.GetAttackRange or function() return 700 end
	tower.GetBoundingRadius = tower.GetBoundingRadius or function() return 144 end
	tower.GetAttackRange = function() return 700 end
	tower.GetAttackTarget = function() return tower.target end
	return tower
end

-- A melee creep in our tower's range, attacking one of our creeps: the core may stand 200 from it, not 520.
do
	local Laning = require("bots/FunLib/humaniser/states/laning")
	local c
	local held = function(target)
		return function(bot)
			local ours = creep({ loc = Vector(-20, 0), team = 2 })
			c = creep({ loc = Vector(60, 0) })
			c.target = target == "ours" and ours or target == "bot" and bot or nil
			TOWERS = { ownTower(-500, 0) }
		end
	end
	local s, bot = spotFor(SDK, nil, held("ours"))
	Laning = require("bots/FunLib/humaniser/states/laning")
	local info = Laning.SpotInfo(bot)
	check("held creep: inside the 520 ring, outside 200", s ~= nil and dist(s, c.loc) >= 200 and dist(s, c.loc) < 520, s and dist(s, c.loc))
	check("held creep: ut=1 (closer than the open-lane limits allow)", info ~= nil and info.covered == 1, info and info.covered)
	local sb = spotFor(SDK, nil, held("bot"))
	check("creep attacking us: the 520 ring", sb ~= nil and dist(sb, c.loc) >= 520, sb and dist(sb, c.loc))
	local sn = spotFor(SDK, nil, held(nil))
	check("creep with no target: the 520 ring", sn ~= nil and dist(sn, c.loc) >= 520, sn and dist(sn, c.loc))
	local so = spotFor(SDK, { laneSpotTower = false }, held("ours"))
	check("LaneSpotTower off: the 520 ring under our tower", so ~= nil and dist(so, c.loc) >= 520, so and dist(so, c.loc))
	-- At 20% HP (HP_LOW 25%) the tower's cover is off: the 520 ring plus the full 300 margin (tspchk1 death at 1% HP).
	local sl = spotFor(SDK, { hp = 20 }, held("ours"))
	check("held creep at 20% HP: the 820 ring", sl ~= nil and dist(sl, c.loc) >= 820, sl and dist(sl, c.loc))
	local sm = spotFor(SDK, { hp = 40 }, held("ours"))
	check("held creep at 40% HP: 200 plus the 120 margin", sm ~= nil and dist(sm, c.loc) >= 320 and dist(sm, c.loc) < 520, sm and dist(sm, c.loc))
	-- A support (pos 5, on our spot) under the same tower keeps the open-lane ring: step 1d checked cores
	-- only (review tower-spot H1).
	local ss = spotFor(SDK, { pos = 5, supportDeny = true }, held("ours"))
	check("support under our tower: the 520 ring", ss ~= nil and dist(ss, c.loc) >= 520, ss and dist(ss, c.loc))
	local sf = spotFor(SDK, nil, function(bot) held("ours")(bot) TOWERS = { ownTower(-1500, 0) } end)
	check("creep outside our tower's range: the 520 ring", sf ~= nil and dist(sf, c.loc) >= 520, sf and dist(sf, c.loc))
end

-- lane_aggro's fed creep (lane_spot input `fed`, slice lane-aggro). lagchk3: in 15 of 30 fed creeps lost the bot made no deny
-- attempt; lagrec1 2:32-2:38 a melee core held 550-640 from it. Our ranged creep at (0, 0), an enemy melee creep at (60, 0)
-- hitting it; a melee core (reach 150 + 48).
do
	local fed, e
	local setup = function(hp, target)
		return function(bot)
			fed = creep({ loc = Vector(0, 0), team = 2, hp = hp, name = "npc_dota_creep_goodguys_ranged" })
			fed.maxhp = 300
			e = creep({ loc = Vector(60, 0) })
			e.target = target == "bot" and bot or fed
			require("bots/FunLib/humaniser/states/laning").SetFed(bot, fed)
		end
	end
	local s, bot = spotFor(SDK, nil, setup(150))
	local info = require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	check("fed creep at 50%: the spot is in deny reach of it", s ~= nil and dist(s, fed.loc) <= 198, s and dist(s, fed.loc))
	check("fed creep at 50%: behind it, anchor fed", s ~= nil and s.x < 0 and info ~= nil and info.anchor == "fed", info and info.anchor)
	local sh = spotFor(SDK, nil, setup(270))
	check("fed creep at 90%: the usual 520 ring", sh ~= nil and dist(sh, e.loc) >= 520, sh and dist(sh, e.loc))
	local sb = spotFor(SDK, nil, setup(150, "bot"))
	check("fed creep, enemy creep on us: its 520 ring stands", sb ~= nil and dist(sb, e.loc) >= 520, sb and dist(sb, e.loc))
end

-- wave_hold's hold point overrides lane_aggro's fed creep (decided 06/11/2026, hschk3: other anchors took holding cores off
-- their point): with both set, the spot anchors on the hold point.
do
	local s, bot = spotFor(SDK, nil, function(bot)
		local fed = creep({ loc = Vector(0, 0), team = 2, hp = 150, name = "npc_dota_creep_goodguys_ranged" })
		fed.maxhp = 300
		local L = require("bots/FunLib/humaniser/states/laning")
		L.SetFed(bot, fed)
		L.SetHold(bot, Vector(-500, 0))
	end)
	local info = require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	check("hold and fed both set: the hold point anchors the spot", info ~= nil and info.anchor == "hold" and s ~= nil and dist(s, Vector(-500, 0)) < 1, info and info.anchor)
end

-- Our own tower no longer relaxes the hero limit: the same read answers there. A melee enemy 400 from the preferred point with a kill line
-- of 100% refuses it with our tower 200 behind the point and with none, and the spot is the same. Control: a harmless hero (10%) does not.
do
	local function run(est, tower)
		local e
		local s, bot = spotFor(SDK, nil, function()
			e = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) }) e.range = 150 e.estDamage = est
			TOWERS = tower and { ownTower(-300, 0) } or {}
		end)
		return s, require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	end
	local sTow, iTow = run(100, true)
	local sOpen, iOpen = run(100, false)
	check("under our tower: a deadly hero still refuses the point", sTow ~= nil and iTow.why == "kill" and sTow.x < -100, sTow and tostring(iTow.why))
	check("under our tower: the spot is the open lane's", sTow ~= nil and sOpen ~= nil and sTow.x == sOpen.x, sTow and sOpen and (sTow.x .. " " .. sOpen.x))
	local sCalm, iCalm = run(10, true)
	check("under our tower, a harmless hero: the preferred point holds", sCalm ~= nil and iCalm.why == "pref" and sCalm.x == -100, iCalm and tostring(iCalm.why))
end

-- Ours.LaneSpot: a core under CoreLastHit stands on our spot although States.Laning.Spot is 'oha'; off, OHA's spot.
do
	local c
	local setup = function() c = creep({ loc = Vector(60, 0) }) end
	local OHA = { Enable = true, Own = { laning = { 2 } } }
	-- OHA's spot here is 310 from the creep, inside its ring.
	local _, bon, Hon = spotFor(OHA, { coreLastHit = true }, setup)
	Hon.States.SetLaneSpot(bon, function() return Vector(-250, 0) end)
	T = T + 1
	local on = require("bots/FunLib/humaniser/states/laning").Spot(bon)
	check("LaneSpot on: our spot for a core, not OHA's", on ~= nil and dist(on, c.loc) >= 520, on and on.x)
	local _, boff, Hoff = spotFor(OHA, { coreLastHit = true, laneSpot = false }, setup)
	Hoff.States.SetLaneSpot(boff, function() return Vector(-250, 0) end)
	T = T + 1
	local off = require("bots/FunLib/humaniser/states/laning").Spot(boff)
	check("LaneSpot off: OHA's spot", off ~= nil and off.x == -250, off and off.x)
	local _, bsup, Hsup = spotFor(OHA, { coreLastHit = true, pos = 5 }, setup)
	Hsup.States.SetLaneSpot(bsup, function() return Vector(-250, 0) end)
	T = T + 1
	local sup = require("bots/FunLib/humaniser/states/laning").Spot(bsup)
	check("LaneSpot: a support whose lane hits are OHA's keeps OHA's spot", sup ~= nil and sup.x == -250, sup and sup.x)
	-- Slice support-spot: a support whose lane hits and harass are ours (Laning.OwnsSpot: Ours.LaneSpot and OwnsSupportHits) stands on our spot; with LaneSpot off, or without the support hits, OHA's.
	local _, bsh, Hsh = spotFor(OHA, { coreLastHit = true, pos = 5, supportDeny = true }, setup)
	Hsh.States.SetLaneSpot(bsh, function() return Vector(-250, 0) end)
	T = T + 1
	local sh = require("bots/FunLib/humaniser/states/laning").Spot(bsh)
	check("LaneSpot: a support that owns its lane hits (OwnsSpot) stands on our spot; the off controls follow", sh ~= nil and sh.x ~= -250 and dist(sh, c.loc) >= 520, sh and sh.x)
	local _, bso, Hso = spotFor(OHA, { coreLastHit = true, pos = 5, supportDeny = true, laneSpot = false }, setup)
	Hso.States.SetLaneSpot(bso, function() return Vector(-250, 0) end)
	T = T + 1
	local so = require("bots/FunLib/humaniser/states/laning").Spot(bso)
	check("LaneSpot: LaneSpot off, the support keeps OHA's spot", so ~= nil and so.x == -250, so and so.x)
end

-- Spot = 'oha' (the default) ignores the wave: slice 1's behaviour.
do
	local s, bot, H = spotFor({ Enable = true, Own = { laning = { 2 } } }, nil, function() creep({ loc = Vector(60, 0) }) end)
	H.States.SetLaneSpot(bot, function() return Vector(-250, 0) end)
	T = T + 1
	s = require("bots/FunLib/humaniser/states/laning").Spot(bot)
	check("Spot=oha: OHA's spot even with a wave", s ~= nil and s.x == -250, s and s.x)
end

-- Slice 4: one frame as OHA plays it (Humaniser.Tick's States and Tasks ticks, then the laning Think's step).
local function frame(H, bot)
	H.States.Tick(bot)
	H.Tasks.Tick(bot)
	if bot.mode == LANING then H.States.Step(bot, LANING) end
	T = T + 0.05
end

local function silenced(fn)
	local p = print
	print = function() end
	local ok, err = pcall(fn)
	print = p
	if not ok then error(err, 0) end
end

-- The body takes a dying enemy creep itself, reports the attempt, and owns the bot's last hits meanwhile.
do
	local H, bot, c, events
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = { 2 } } })
		events = {}
		require("bots/FunLib/humaniser/telemetry").SetSink(function(line) events[#events + 1] = line end)
		H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
		for _ = 1, 4 do frame(H, bot) end
		-- 60 hp losing 100/s: with a 0.3 s wind-up and 50 damage it is due now.
		c = creep({ loc = Vector(-200, 0), hp = 60, regen = -100 })
		for _ = 1, 3 do frame(H, bot) end
	end)
	check("body: owns last hits while running", H.States.BodyLastHits(bot) == true)
	check("body: attacked the dying creep", bot.attacks ~= nil and bot.attacks[#bot.attacks] == c)
	check("body: busy while the swing is in flight (OHA's steps stand back)", H.States.BodyBusy(bot) == true)
	silenced(function()
		c.alive, c.hp = false, 0
		bot.lastHits = 1
		for _ = 1, 3 do frame(H, bot) end
	end)
	local lh
	for _, l in ipairs(events) do if l:find("ev=lh ", 1, true) then lh = l end end
	if lh == nil then for _, l in ipairs(events) do print("  " .. l) end end
	check("body: ev=lh reported ok", lh ~= nil and lh:find("result=ok", 1, true) ~= nil and lh:find("kind=lasthit", 1, true) ~= nil, lh)
	-- The creep is dead at the end, so its place comes from the last scan that offered it, with that reading's age.
	local ca = lh and tonumber(lh:match(" ca=([%d.]+)"))
	check("body: ev=lh places the dead creep from its last scan", lh ~= nil and lh:find(" cx=-200 ", 1, true) ~= nil
		and lh:find(" cy=0 ", 1, true) ~= nil and ca ~= nil and ca > 0, lh)
	require("bots/FunLib/humaniser/telemetry").SetSink(nil)
end

-- ev=cut kind=pick: the body's pick logs its inputs and answer when the answer changes, not on every scan of the same attempt.
do
	local H, bot, c, c2, events
	local function picks()
		local out = {}
		for _, l in ipairs(events) do if l:find("ev=cut ", 1, true) and l:find("kind=pick", 1, true) then out[#out + 1] = l end end
		return out
	end
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = { 2 } } })
		events = {}
		require("bots/FunLib/humaniser/telemetry").SetSink(function(line) events[#events + 1] = line end)
		H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
		for _ = 1, 4 do frame(H, bot) end
		c = creep({ loc = Vector(-200, 0), hp = 60, regen = -100 })
		for _ = 1, 3 do frame(H, bot) end
	end)
	local first = picks()
	check("pick cut: the first pick logs one line with the offered creep and the answer", #first == 1
		and first[1]:find(" pid=1 ", 1, true) ~= nil and first[1]:find(" pos=2 ", 1, true) ~= nil
		and first[1]:find(" ord=lasthit,pre_hit,deny,idle_swing ", 1, true) ~= nil and first[1]:find(" tg=1,lasthit,", 1, true) ~= nil
		and first[1]:find(",0,1 ", 1, true) ~= nil and first[1]:find(" ans=1 ak=lasthit", 1, true) ~= nil, first[1])
	silenced(function() for _ = 1, 10 do frame(H, bot) end end)
	check("pick cut: the same answer on later scans inside 5 s logs no second line", #picks() == 1, #picks())
	silenced(function()
		c.alive, c.hp = false, 0
		bot.lastHits = 1
		for _ = 1, 3 do frame(H, bot) end
		c2 = creep({ loc = Vector(-180, 0), hp = 60, regen = -100 })
		for _ = 1, 3 do frame(H, bot) end
	end)
	local all = picks()
	check("pick cut: a different creep chosen logs again", #all == 2 and all[2] ~= first[1], #all)
	require("bots/FunLib/humaniser/telemetry").SetSink(nil)
end

-- Ours.PickSafe: a creep whose hit place the safe read calls deadly is not this hero's to take. The read is stubbed on the module
-- table (laning.lua indexes it at each call); `levelAt(place)` answers per place so one world can have a deadly and a safe creep.
-- The last hit is 200 away (a 50 walk into the 150 reach, stand point (-250, 0)), the deny is in range (place = the bot's own).
do
	local function scenario(o)
		local H, bot, lh, deny, events, SG
		local calls = {}
		silenced(function()
			H, bot = Fresh({ Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = { 2 } } })
			package.loaded["bots/FunLib/custom_loader"].Ours.PickSafe = o.switch ~= false
			SG = require("bots/FunLib/humaniser/safe_gather")
			SG.At = function(b, place, opts)
				calls[#calls + 1] = { place = place, held = opts and opts.held, horizon = opts and opts.horizon, who = opts and opts.who }
				if o.throws then error("boom") end
				return { level = o.levelAt(place) }
			end
			events = {}
			require("bots/FunLib/humaniser/telemetry").SetSink(function(line) events[#events + 1] = line end)
			H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
			for _ = 1, 4 do frame(H, bot) end
			-- Alive for 0.8 s: longer than the 0.17 s walk and the swing's slack, so the reach rule offers it.
			lh = creep({ loc = Vector(-100, 0), hp = 90, regen = -100 })
			if o.deny then deny = creep({ loc = Vector(-400, 0), hp = 60, regen = -100, team = bot.team }) end
			for _ = 1, 3 do frame(H, bot) end
		end)
		local picks = {}
		for _, l in ipairs(events) do if l:find("ev=cut ", 1, true) and l:find("kind=pick", 1, true) then picks[#picks + 1] = l end end
		require("bots/FunLib/humaniser/telemetry").SetSink(nil)
		return { bot = bot, lh = lh, deny = deny, calls = calls, picks = picks, events = events }
	end
	-- The first pick the body made: the kind it chose (the creeps are offered lasthit first, deny second).
	local function chose(r, kind) return r.picks[1] ~= nil and r.picks[1]:find(" ak=" .. kind, 1, true) ~= nil end
	local atBot = function(p) return p.x == -300 and p.y == 0 end

	local deadlyAtStand = function(p) return p.x > -280 and "deadly" or "safe" end
	local costlyAtStand = function(p) return p.x > -280 and "costly" or "safe" end

	local dead = scenario({ levelAt = deadlyAtStand, deny = true })
	check("pick safe: a last hit whose stand point is deadly is not taken, the deny in a safe place is", chose(dead, "deny"), dead.picks[1])
	local sd = dead.picks[1] and dead.picks[1]:match(" sd=(%d+)")
	check("pick safe: the cut line counts the dropped creep and shows it as not mine", sd == "1"
		and dead.picks[1]:find("tg=1,lasthit,[^;]*,0;2,deny", 1) ~= nil, dead.picks[1])

	local costly = scenario({ levelAt = costlyAtStand, deny = true })
	check("pick safe: control, costly does not drop the last hit", chose(costly, "lasthit"), costly.picks[1])
	check("pick safe: no sd on a line when nothing was dropped", costly.picks[1] ~= nil and costly.picks[1]:find(" sd=", 1, true) == nil, costly.picks[1])

	local askedOut, askedIn
	for _, c in ipairs(dead.calls) do
		if c.held == true and c.horizon == 2 and math.abs(c.place.x + 250) < 1 and c.place.y == 0 then askedOut = true end
		if c.held == true and atBot(c.place) then askedIn = true end
	end
	check("pick safe: out of range asks at the point attack range from the creep, not at the bot, by the leave bar (held) 2 s ahead", askedOut == true, #dead.calls)
	check("pick safe: in range asks held=true at the bot's own place", askedIn == true, #dead.calls)
	local anyWho = false
	for _, c in ipairs(dead.calls) do if c.who ~= nil then anyWho = true end end
	check("pick safe: the pick asks without a who (no extra safe lines of its own)", not anyWho)

	local off = scenario({ levelAt = deadlyAtStand, switch = false })
	check("pick safe off: the read is never asked and the creep is taken", #off.calls == 0 and chose(off, "lasthit"), #off.calls)

	local boom = scenario({ throws = true })
	check("pick safe: a read that throws still lets the creep be picked", #boom.calls > 0 and chose(boom, "lasthit"), #boom.calls)
	local failed = false
	for _, l in ipairs(boom.events) do if l:find("PickSafe", 1, true) then failed = true end end
	check("pick safe: the fault is reported", failed)
end

-- A creep that reads alive with no location when the attempt ends (prhfc2 game C, log 2026-11-04T02-49-08-prhfc2_C_on_3.log
-- t=155.533: ev=state_task reason=error, `at` nil in placeOf): the attempt is still reported, placed from its last scan.
do
	local H, bot, c, events
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = { 2 } } })
		events = {}
		require("bots/FunLib/humaniser/telemetry").SetSink(function(line) events[#events + 1] = line end)
		H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
		for _ = 1, 4 do frame(H, bot) end
		c = creep({ loc = Vector(-200, 0), hp = 60, regen = -100 })
		for _ = 1, 3 do frame(H, bot) end
		c.loc, c.removed = nil, true
		for i = #CREEPS, 1, -1 do if CREEPS[i] == c then table.remove(CREEPS, i) end end
		for _ = 1, 3 do frame(H, bot) end
	end)
	local lh, err
	for _, l in ipairs(events) do
		if l:find("ev=lh ", 1, true) then lh = l end
		if l:find("reason=error", 1, true) then err = l end
	end
	check("body: no task error on a creep alive with no location", err == nil, err)
	check("body: that attempt placed from its last scan", lh ~= nil and lh:find(" cx=-200 ", 1, true) ~= nil, lh)
	require("bots/FunLib/humaniser/telemetry").SetSink(nil)
end

-- A creep the game has removed by the time the attempt ends: its handle raises on IsAlive (log
-- 2026-11-04T04-59-58-prhchk5_A_on_1.log pid 1 t=215.833 and t=511.667: "laning.lua:308: Invalid object passed to IsAlive.",
-- ev=state_task reason=error, the laning task failed). The attempt is still reported, placed from its last scan.
do
	local H, bot, c, events
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = { 2 } } })
		events = {}
		require("bots/FunLib/humaniser/telemetry").SetSink(function(line) events[#events + 1] = line end)
		H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
		for _ = 1, 4 do frame(H, bot) end
		c = creep({ loc = Vector(-200, 0), hp = 60, regen = -100 })
		for _ = 1, 3 do frame(H, bot) end
		c.loc, c.removed = nil, true
		c.IsAlive = function(self)
			if self.removed then error("Invalid object passed to IsAlive.") end
			return self.alive
		end
		for i = #CREEPS, 1, -1 do if CREEPS[i] == c then table.remove(CREEPS, i) end end
		for _ = 1, 3 do frame(H, bot) end
	end)
	local lh, err
	for _, l in ipairs(events) do
		if l:find("ev=lh ", 1, true) then lh = l end
		if l:find("reason=error", 1, true) then err = l end
	end
	check("body: no task error on a removed creep", err == nil, err)
	check("body: the removed creep's attempt placed from its last scan", lh ~= nil and lh:find(" cx=-200 ", 1, true) ~= nil, lh)
	require("bots/FunLib/humaniser/telemetry").SetSink(nil)
end

-- Not listed in Laning.LastHit: the Lua Think keeps its own last hits and the body never attacks.
do
	local H, bot
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = { 2 } }, Laning = { LastHit = { 1 } } })
		H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
		creep({ loc = Vector(-200, 0), hp = 60, regen = -100 })
		for _ = 1, 6 do frame(H, bot) end
	end)
	check("unlisted: BodyLastHits false", H.States.BodyLastHits(bot) == false)
	check("unlisted: never busy", H.States.BodyBusy(bot) == false)
	check("unlisted: body never attacked", bot.attacks == nil)
end

-- Listed but the state is not owned (pos 2 not in Own): OHA keeps its last hits.
do
	local H, bot
	silenced(function()
		H, bot = Fresh({ Enable = true, Own = { laning = {} }, Laning = { LastHit = { 2 } } })
		for _ = 1, 4 do frame(H, bot) end
	end)
	check("not owned: BodyLastHits false", H.States.BodyLastHits(bot) == false)
end


-- Core farm etiquette (adapter lastHitFilter): a support leaves a dying creep to an allied core that can reach it,
-- takes it when no core can, and a mid (pos 2) never defers.
if GetUnitToUnitDistance == nil then
	function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end
end
function Unit:GetExtrapolatedLocation() return self.loc end
do
	local function offered(pos, coreLoc)
		local H, bot, positions = Fresh({ Enable = true, Own = { laning = { 1, 2, 3, 4, 5 } } }, { pos = pos })
		local core = MakeUnit({ pid = 2, loc = coreLoc })
		positions[2] = 1
		creep({ loc = Vector(-200, 0), hp = 60, regen = -100 })
		local t
		silenced(function() t = H.Tasks.Verbs().laneTargets(bot)[1] end)
		return t
	end
	local beside = Vector(-170, 30)
	local t5 = offered(5, beside)
	check("etiquette: pos 5 leaves the creep to the core beside it", t5 == nil, t5 and t5.kind)
	local t5far = offered(5, Vector(-3000, 0))
	check("etiquette: pos 5 takes it with no core near", t5far ~= nil and t5far.kind == "lasthit")
	local t2 = offered(2, beside)
	check("etiquette: pos 2 never defers", t2 ~= nil and t2.kind == "lasthit")
end

-- Slice 5, Ours.CoreLastHit: a core on the team without a human (Valve's C++ laning in OFF) gets the Lua Think and the
-- body takes its last hits, with Own and Laning.LastHit at their defaults; supports are untouched; off is OHA's path.
do
	local DEFAULTS = { Enable = true, Own = { laning = { 2 } }, Teams = "allies", Laning = { LastHit = {} } }
	local function dire(pos, on, direOff)
		local H, bot, c
		silenced(function()
			H, bot = Fresh(DEFAULTS, { team = 3, pos = pos, coreLastHit = on, direOff = direOff })
			H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
			for _ = 1, 4 do frame(H, bot) end
			-- Radiant's creep: the enemy's for this Dire bot.
			c = creep({ loc = Vector(-200, 0), hp = 60, regen = -100, team = 2, name = "npc_dota_creep_goodguys_melee" })
			for _ = 1, 3 do frame(H, bot) end
		end)
		return H, bot, c
	end
	for _, pos in ipairs({ 1, 2, 3 }) do
		local H, bot, c = dire(pos, true)
		check("core lh on: Dire pos " .. pos .. " may own (Lua Think)", H.States.MayOwn(bot) == true)
		check("core lh on: Dire pos " .. pos .. " body owns its last hits", H.States.BodyLastHits(bot) == true)
		check("core lh on: Dire pos " .. pos .. " body swung at the dying creep", bot.attacks ~= nil and bot.attacks[#bot.attacks] == c)
	end
	local H4, bot4 = dire(4, true)
	check("core lh on: a support is not taken over", H4.States.BodyLastHits(bot4) == false and bot4.attacks == nil)
	local Hoff, botoff = dire(1, false)
	check("core lh off: Dire pos 1 stays on Valve's laning (no Lua Think)", Hoff.States.MayOwn(botoff) == false)
	check("core lh off: the body never attacks", Hoff.States.BodyLastHits(botoff) == false and botoff.attacks == nil)
end

do -- CoreLastHitDire = false: Radiant keeps the body, Dire stays on Valve's laning
	local function side(team, pos)
		local H, bot
		silenced(function()
			H, bot = Fresh({ Enable = true, Own = { laning = { 2 } }, Teams = "allies", Laning = { LastHit = {} } }, { team = team, pos = pos, coreLastHit = true, direOff = true })
		end)
		return H.States.MayOwn(bot)
	 end
	for _, pos in ipairs({ 1, 2, 3 }) do
		check("dire off: Radiant pos " .. pos .. " still owned", side(2, pos) == true)
		check("dire off: Dire pos " .. pos .. " left to Valve", side(3, pos) == false)
	end
	check("dire off: a Dire pos 4 stays untouched", side(3, 4) == false)
end

-- Slice l1-support-deny, Ours.SupportDeny: a support's body takes a dying own creep (the deny), and the support's lane step
-- steps the body ahead of OHA's own laning steps while a lane hit is offered. Its last hits: see the support-lane-hits block.
do
	local DEFAULTS = { Enable = true, Own = { laning = { 2 } }, Teams = "allies", Laning = { LastHit = {} } }
	local function support(o)
		local H, bot, c
		silenced(function()
			H, bot = Fresh(DEFAULTS, { pos = o.pos or 5, team = o.team, supportDeny = o.on ~= false, supportDireOff = o.direOff, supportLastHit = o.lastHits, laneSpot = o.harass })
			H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
			for _ = 1, 4 do frame(H, bot) end
			local team = o.enemy and 3 or (o.team or 2)
			c = creep({ loc = o.at or Vector(-200, 0), hp = 45, regen = -40, team = team })
		end)
		return H, bot, c
	end
	local H, bot, own = support({})
	local Laning = require("bots/FunLib/humaniser/states/laning")
	check("support deny: may own (Lua Think)", H.States.MayOwn(bot) == true)
	check("support deny: the body owns the support's lane hits, not a core's last hits", H.States.BodySupportHits(bot) == true and H.States.BodyLastHits(bot) == false)
	local offered
	silenced(function() offered = Laning.HitOffered(bot) end)
	check("support deny: the dying own creep is offered", offered == true)
	local stepped
	silenced(function()
		H.States.Tick(bot)
		H.Tasks.Tick(bot)
		stepped = H.States.LaneStep(bot, HostSteps) == "support_hit"
		T = T + 0.05
		for _ = 1, 3 do
			H.States.Tick(bot)
			H.Tasks.Tick(bot)
			H.States.LaneStep(bot, HostSteps)
			T = T + 0.05
		end
	end)
	check("support deny: the support_hit row acts first", stepped == true)
	check("support deny: the body swung at the own creep", bot.attacks ~= nil and bot.attacks[#bot.attacks] == own)

	local He, bote = support({ enemy = true, lastHits = false })
	local offeredEnemy
	silenced(function()
		offeredEnemy = require("bots/FunLib/humaniser/states/laning").HitOffered(bote)
		for _ = 1, 3 do frame(He, bote) end
	end)
	check("support last hits off: a dying enemy creep is not the body's (OHA's last hit)", offeredEnemy == false and bote.attacks == nil and He.States.BodySupportLastHits(bote) == false)

	-- OHA's spot (LaneSpot off): the leash is measured from whichever spot the support holds.
	local Hl, botl = support({ at = Vector(-200, 0), harass = false })
	silenced(function() Hl.States.SetLaneSpot(botl, function() return Vector(-1500, 0) end) end)
	local past
	silenced(function() past = require("bots/FunLib/humaniser/states/laning").HitOffered(botl) end)
	check("support deny: nothing offered beyond the leash from the spot", past == false)

	local Hc, botc = support({ pos = 1 })
	check("support deny: a core's lane hits are not the support body's", require("bots/FunLib/humaniser/states/laning").OwnsSupportHits(botc) == false)
	local Hoff, botoff = support({ on = false })
	check("support deny off: OHA's path (no body denies)", Hoff.States.BodySupportHits(botoff) == false and botoff.attacks == nil)
	local Hd, botd = support({ team = 3, direOff = true })
	check("support deny, Dire off: a Dire support stays OHA's", Hd.States.MayOwn(botd) == false)
end


-- Slice support-lane-hits, Ours.SupportLastHit: the support's body takes the last hits no allied core will take (states/lane_claims):
-- a creep with no core near (free), not one its idle core is beside, and the second creep due while its core's body is in an
-- attempt on another (busy) when the core cannot swing again before the others kill it.
do
	local DEFAULTS = { Enable = true, Own = { laning = { 2 } }, Teams = "allies", Laning = { LastHit = {} } }
	local Pick = require("bots/FunLib/humaniser/states/lane_pick")
	local function world(o)
		local H, bot, positions, x, y, core
		silenced(function()
			H, bot, positions = Fresh(DEFAULTS, { pos = 5, supportDeny = true })
			H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
			for _ = 1, 4 do frame(H, bot) end
			x = creep({ loc = Vector(-200, 0), hp = 45, regen = -40 })
			if o.core then
				core = MakeUnit({ pid = 2, mode = LANING, loc = o.coreAt or Vector(-150, 50), level = 3 })
				positions[2] = 1
			end
			if o.busy then
				y = creep({ loc = Vector(-100, 80), hp = 70, regen = -40 })
				Pick = require("bots/FunLib/humaniser/states/lane_pick")
				Pick.NotePick(2, T, { { creep = y, kind = "lasthit", eta = 0.3, due = 0.3, walk = 0, dies = 5, ranged = false } },
					{ creep = y, kind = "lasthit", eta = 0.3, due = 0.3, walk = 0, dies = 5, ranged = false })
				Pick.NotePhase(2, "lasthit")
			end
		end)
		local Laning = require("bots/FunLib/humaniser/states/laning")
		local offered
		silenced(function()
			offered = Laning.HitOffered(bot)
			for _ = 1, 3 do frame(H, bot) end
		end)
		local Claims = require("bots/FunLib/humaniser/states/lane_claims")
		return offered, bot, x, Claims
	end
	local offered, bot, x = world({})
	check("support last hit: a dying enemy creep with no core near is the body's", offered == true and bot.attacks ~= nil and bot.attacks[#bot.attacks] == x)
	offered, bot = world({ core = true })
	check("support last hit: not a creep its idle core is beside (Etiquette.CanTake)", offered == false and bot.attacks == nil)
	offered, bot, x = world({ core = true, busy = true })
	check("support last hit: the second creep, its core's body in an attempt on another, is the body's", offered == true and bot.attacks ~= nil and bot.attacks[#bot.attacks] == x)
	offered, bot = world({ core = true, coreAt = Vector(-4000, 3000) })
	check("support last hit: a core out of reach leaves the creep to the support", offered == true)
end

-- Ours.CoreDenyYield (user 06/11/2026, bug-hunt mark 11): a core leaves a deny its lane support's body is in an attempt on and
-- goes for the next one; a last hit on that creep's kind and other denies stay its; a support not in an attempt is not yielded to.
do
	local Claims = require("bots/FunLib/humaniser/states/lane_claims")
	local Pick
	local function lt(c, kind, eta) return { creep = c, kind = kind, eta = eta, due = eta, walk = 0, dies = 5, ranged = false } end
	local function world(o)
		local H, core, positions, sup, d1, d2, e1
		silenced(function()
			H, core, positions = Fresh({ Enable = true, Own = { laning = { 2 } }, Teams = "allies", Laning = { LastHit = {} } },
				{ pos = 1, coreLastHit = true })
			package.loaded["bots/FunLib/custom_loader"].Ours.CoreDenyYield = o.off ~= true
			sup = MakeUnit({ pid = 2, mode = LANING, loc = Vector(-250, 40), level = 3 })
			positions[2] = 5
			d1 = creep({ loc = Vector(-200, 0), hp = 45, regen = -40, team = 2 })
			d2 = creep({ loc = Vector(-180, 60), hp = 45, regen = -40, team = 2 })
			e1 = creep({ loc = Vector(-150, -40), hp = 45, regen = -40 })
			Pick = require("bots/FunLib/humaniser/states/lane_pick")
			Claims = require("bots/FunLib/humaniser/states/lane_claims")
			Pick.NotePick(2, T, { lt(d1, "deny", 0.2) }, lt(d1, "deny", 0.2))
			Pick.NotePhase(2, o.phase or "deny")
		end)
		return core, d1, d2, e1
	end
	local H4
	local core, d1, d2, e1 = world({})
	local mine = Claims.CoreMine(core)
	check("deny yield: the deny its support is attempting is not the core's", mine ~= nil and mine(lt(d1, "deny", 0.2)) == false)
	check("deny yield: the support's pid is named", Claims.DenyYield(core, lt(d1, "deny", 0.2)) == 2)
	check("deny yield: another deny stays the core's", mine ~= nil and mine(lt(d2, "deny", 0.3)) == true)
	check("deny yield: a last hit stays the core's", mine ~= nil and mine(lt(e1, "lasthit", 0.5)) == true)
	local pick = Pick.Choose({ lt(d1, "deny", 0.1), lt(d2, "deny", 0.4) }, nil, mine)
	check("deny yield: the core picks the other deny", pick ~= nil and pick.creep == d2, pick and pick.kind)
	local stay = Pick.Choose({ lt(d1, "deny", 0.1), lt(e1, "lasthit", 2.0) }, lt(d1, "deny", 0.1), mine)
	check("deny yield: a wait on it is dropped for the next last hit", stay ~= nil and stay.creep == e1)
	local column = Claims.Mine(core, 1, 1)
	check("claims column: `unattempted` on a core's denies leaves the support's deny, takes the rest",
		column ~= nil and column(lt(d1, "deny", 0.2)) == false and column(lt(d2, "deny", 0.3)) == true and column(lt(e1, "lasthit", 0.5)) == true)
	core, d1 = world({ off = true })
	check("claims column, Ours.CoreDenyYield off: a core takes every creep", Claims.Mine(core, 1, 1) == nil)
	core, d1 = world({ phase = "hold" })
	mine = Claims.CoreMine(core)
	check("deny yield: a support holding (no attempt) is not yielded to", mine(lt(d1, "deny", 0.2)) == true and Claims.DenyYield(core, lt(d1, "deny", 0.2)) == nil)
	core, d1 = world({ off = true })
	check("deny yield off: the core takes every creep", Claims.CoreMine(core) == nil and Claims.DenyYield(core, lt(d1, "deny", 0.2)) == nil)

	-- A pos 4-5 taking a core's mine (listed in Laning.LastHit) never yields (review 2026-11-06-deny-yield-0ee970a F4).
	silenced(function()
		local positions
		H4, core, positions = Fresh({ Enable = true, Own = { laning = { 2 } }, Teams = "allies", Laning = { LastHit = {} } },
			{ pos = 4, coreLastHit = true })
		package.loaded["bots/FunLib/custom_loader"].Ours.CoreDenyYield = true
		MakeUnit({ pid = 2, mode = LANING, loc = Vector(-250, 40), level = 3 })
		positions[2] = 5
		d1 = creep({ loc = Vector(-200, 0), hp = 45, regen = -40, team = 2 })
		Pick = require("bots/FunLib/humaniser/states/lane_pick")
		Claims = require("bots/FunLib/humaniser/states/lane_claims")
		Pick.NotePick(2, T, { lt(d1, "deny", 0.2) }, lt(d1, "deny", 0.2))
		Pick.NotePhase(2, "deny")
	end)
	check("deny yield: a pos 4 on a core's mine does not yield", Claims.DenyYield(core, lt(d1, "deny", 0.2)) == nil)

	-- Through the core's body: it swings at the other deny, and that attempt's ev=lh says yd=2; ev=snap's lf counts yc=1. With
	-- the attempt ending more than 6 s after the yield, yd is dropped (review 2026-11-06-deny-yield-0ee970a F2).
	local function bodyRun(gap)
		local H, events, body
		silenced(function()
			local positions
			H, body, positions = Fresh({ Enable = true, Own = { laning = { 2 } }, Teams = "allies", Laning = { LastHit = {} } }, { pos = 1, coreLastHit = true })
			package.loaded["bots/FunLib/custom_loader"].Ours.CoreDenyYield = true
			events = {}
			require("bots/FunLib/humaniser/telemetry").SetSink(function(line) events[#events + 1] = line end)
			H.States.SetLaneSpot(body, function() return Vector(-300, 0) end)
			MakeUnit({ pid = 2, mode = LANING, loc = Vector(-250, 40), level = 3 })
			positions[2] = 5
			for _ = 1, 4 do frame(H, body) end
			d1 = creep({ loc = Vector(-200, 0), hp = 30, regen = -60, team = 2 })
			d2 = creep({ loc = Vector(-220, 30), hp = 45, regen = -40, team = 2 })
			Pick = require("bots/FunLib/humaniser/states/lane_pick")
			Pick.NotePick(2, T, { lt(d1, "deny", 0.1) }, lt(d1, "deny", 0.1))
			Pick.NotePhase(2, "deny")
			for _ = 1, 3 do frame(H, body) end
		end)
		local swung = body.attacks ~= nil and body.attacks[#body.attacks] == d2
		silenced(function()
			T = T + gap
			d2.alive, d2.hp = false, 0
			body.denies = 1
			for _ = 1, 3 do frame(H, body) end
		end)
		local lh
		for _, l in ipairs(events) do if l:find("ev=lh ", 1, true) and l:find(" pid=1 ", 1, true) then lh = l end end
		require("bots/FunLib/humaniser/telemetry").SetSink(nil)
		return swung, lh
	end
	local swung, lh = bodyRun(0)
	check("deny yield body: the core swung at the other deny, not the support's", swung)
	check("deny yield body: the attempt's ev=lh names the support (yd=2)", lh ~= nil and lh:find(" yd=2", 1, true) ~= nil, lh)
	check("deny yield body: lf counts the yield", (require("bots/FunLib/humaniser/states/lane_pick").Describe(1, T) or ""):find(" yc=1", 1, true) ~= nil,
		require("bots/FunLib/humaniser/states/lane_pick").Describe(1, T))
	swung, lh = bodyRun(10)
	check("deny yield body: an attempt ending 10 s after the yield carries no yd", lh ~= nil and lh:find(" yd=", 1, true) == nil, lh)
end

-- The claim columns of the pick table (states/pick_table) as the picker's `mine` reads them (LaneClaims.Mine, laning ClaimPos).
do
	local Claims
	local function lt(c, kind, eta) return { creep = c, kind = kind, eta = eta, due = eta, walk = 0, dies = 5, ranged = false } end

	-- `unclaimed` on last hits (pos 5): not a creep an allied core is beside, the one no core is near; every deny.
	local function support(o)
		local bot, x, d
		silenced(function()
			local positions
			local H
			H, bot, positions = Fresh({ Enable = true, Own = { laning = { 2 } }, Teams = "allies", Laning = { LastHit = o.listed and { 5 } or {} } },
				{ pos = 5, supportDeny = true, supportLastHit = o.lastHits ~= false })
			H.States.SetLaneSpot(bot, function() return Vector(-300, 0) end)
			for _ = 1, 4 do frame(H, bot) end
			Claims = require("bots/FunLib/humaniser/states/lane_claims")
			x = creep({ loc = Vector(-200, 0), hp = 45, regen = -40 })
			d = creep({ loc = Vector(-190, 20), hp = 45, regen = -40, team = 2 })
			if o.core then
				MakeUnit({ pid = 2, mode = LANING, loc = Vector(-150, 50), level = 3 })
				positions[2] = 1
			end
		end)
		return bot, x, d
	end
	local Laning = function() return require("bots/FunLib/humaniser/states/laning") end
	local bot, x, d = support({})
	local mine = Claims.Mine(bot, Laning().ClaimPos(bot), 1)
	check("claims column: a pos 5 takes a last hit no core is near", mine(lt(x, "lasthit", 0.3)) == true)
	check("claims column: a pos 5 takes every deny", mine(lt(d, "deny", 0.3)) == true)
	bot, x, d = support({ core = true })
	mine = Claims.Mine(bot, Laning().ClaimPos(bot), 1)
	check("claims column: a pos 5 leaves a last hit an idle core is beside", mine(lt(x, "lasthit", 0.3)) == false)
	check("claims column: ...and still takes a deny", mine(lt(d, "deny", 0.3)) == true)
	bot, x, d = support({ lastHits = false })
	mine = Claims.Mine(bot, Laning().ClaimPos(bot), 1)
	check("claims column, Ours.SupportLastHit off: no last hit, denies stay", mine(lt(x, "lasthit", 0.3)) == false and mine(lt(d, "deny", 0.3)) == true)

	-- A pos 5 listed in Laning.LastHit reads position 1's column: all last hits, and no yield of denies to another support.
	bot, x, d = support({ core = true, listed = true })
	check("claims column: a listed pos 5 reads position 1's column", Laning().ClaimPos(bot) == 1)
	mine = Claims.Mine(bot, Laning().ClaimPos(bot), 1)
	check("claims column: a listed pos 5 takes the last hit a core is beside", mine(lt(x, "lasthit", 0.3)) == true)
end

-- wave_hold's hold point (lane_spot input `hold`, slice core-in-lane): our wave gone, their melee creep walking in at (-200, 0)
-- and on the core; the hold point (-500, 0) is the preferred point and the creep keeps only the 200 held ring. A melee enemy
-- hero 600 from the point with a kill line of 100% still pushes the spot back: the hero limit stands.
do
	local L = function() return require("bots/FunLib/humaniser/states/laning") end
	local hold = Vector(-500, 0)
	local c
	local setup = function(hero)
		return function(bot)
			c = creep({ loc = Vector(-200, 0) })
			c.target = bot
			if hero then local e = MakeUnit({ pid = 7, team = 3, loc = Vector(100, 0) }) e.range = 150 e.estDamage = 100 end
			L().SetHold(bot, hold)
		end
	end
	local s, bot = spotFor(SDK, nil, setup(false))
	local info = L().SpotInfo(bot)
	check("hold: the spot is the hold point, anchor hold", s ~= nil and dist(s, hold) < 1 and info ~= nil and info.anchor == "hold", info and info.anchor)
	check("hold: inside the creep's 520 ring (it is meant to be on us)", s ~= nil and dist(s, c.loc) < 520, s and dist(s, c.loc))
	local sh, bshh = spotFor(SDK, nil, setup(true))
	check("hold under a deadly melee hero 600 from the point: backed off the hold point, why=kill", sh ~= nil and dist(sh, hold) > 1 and sh.x < hold.x and L().SpotInfo(bshh).why == "kill", sh and sh.x)
	local so = spotFor(SDK, nil, function(bot) c = creep({ loc = Vector(-200, 0) }) c.target = bot end)
	check("no hold: the 520 ring", so ~= nil and dist(so, c.loc) >= 520, so and dist(so, c.loc))
end

finish()
