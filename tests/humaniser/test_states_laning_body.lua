dofile(HARNESS_DIR .. "/dota_stubs.lua")

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
function Unit:WasRecentlyDamagedByCreep() return false end
function Unit:WasRecentlyDamagedByTower() return false end
function Unit:Action_AttackUnit(u) self.attacks = self.attacks or {} table.insert(self.attacks, u) end

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
		SupportDeny = o.supportDeny == true, SupportDenyDire = o.supportDireOff ~= true, SupportLastHit = o.supportLastHit ~= false, LaneSpot = o.laneSpot, SupportHarass = o.supportHarass,
		LaneSpotTower = o.laneSpotTower }
	local Phase = require("bots/FunLib/humaniser/transitions/phase")
	Phase.IsLaningFor = function() return true end
	local LaneConfig = require("bots/FunLib/humaniser/lane_config")
	local positions = {}
	LaneConfig.SetHelpers({ GetPosition = function(u) return positions[u.pid] end })
	MakeUnit({ pid = 0, bot = false, loc = Vector(-4000, -4000) })
	local bot = MakeUnit({ pid = 1, team = o.team, mode = LANING, loc = o.loc or Vector(-300, 0), level = o.level or 3, hp = o.hp })
	bot.range = o.range
	positions[1] = o.pos or 2
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

-- An enemy hero's reach (attack range + both bounding radii + 1.5 s of its 300 movement, at least 800): a ranged enemy (550)
-- 400 from the preferred point moves the spot to 1,048 from it (why=hero), with no creep in the way; at 30% HP the HP margin
-- adds 240; a melee enemy's reach is the 800 floor, not 150 + 48 + 450.
do
	local e
	local setup = function() e = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) }) e.range = 550 end
	local s, bot = spotFor(SDK, nil, setup)
	local Laning = require("bots/FunLib/humaniser/states/laning")
	check("hero reach: outside 550 + 48 + 450", s ~= nil and dist(s, e.loc) >= 1048 and dist(s, e.loc) < 1048 + 51, s and dist(s, e.loc))
	check("hero reach: why=hero", Laning.SpotInfo(bot).why == "hero", Laning.SpotInfo(bot).why)
	local low = spotFor(SDK, { hp = 30 }, setup)
	check("hero reach at 30% HP: + 240", low ~= nil and dist(low, e.loc) >= 1288, low and dist(low, e.loc))
	local m
	local melee, botm = spotFor(SDK, nil, function() m = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) }) end)
	check("melee enemy 400 away: pushed to the 800 floor", melee ~= nil and dist(melee, m.loc) >= 800 and dist(melee, m.loc) < 851
		and require("bots/FunLib/humaniser/states/laning").SpotInfo(botm).why == "hero", melee and dist(melee, m.loc))
	local far, botf = spotFor(SDK, nil, function() MakeUnit({ pid = 7, team = 3, loc = Vector(700, 0) }) end)
	check("melee enemy 800 away: the preferred point (side-shifted) holds", far ~= nil and far.x == -100
		and require("bots/FunLib/humaniser/states/laning").SpotInfo(botf).why == "pref", far and (far.x .. "," .. far.y))
end

-- No candidate within the XP limit clears the hero reach (an enemy ranged hero just behind the preferred point): the fallback is
-- the furthest back that still keeps an enemy tower's ring, not the XP limit inside it (lposchk2: 13 idle seconds in tower range
-- from the old fallback).
do
	local tower = { team = 3, loc = Vector(-1300, 0) }
	tower.GetLocation = function() return tower.loc end
	tower.IsAlive = function() return true end
	tower.IsNull = function() return false end
	local e
	local s, bot = spotFor(SDK, nil, function()
		e = MakeUnit({ pid = 7, team = 3, loc = Vector(-600, 0) }) e.range = 550
		TOWERS = { tower }
	end)
	local info = require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	check("xp fallback: why=xp", info ~= nil and info.why == "xp", info and info.why)
	check("xp fallback: outside the tower ring + drift", s ~= nil and dist(s, tower.loc) >= 830, s and dist(s, tower.loc))
	check("xp fallback: as far back as the tower allows", s ~= nil and dist(s, tower.loc) < 830 + 60, s and dist(s, tower.loc))
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
	-- A support (pos 5, with SupportHarass on our spot) under the same tower keeps the open-lane ring: step 1d checked cores
	-- only (review tower-spot H1).
	local ss = spotFor(SDK, { pos = 5, supportDeny = true, supportHarass = true }, held("ours"))
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

-- A melee enemy hero 400 from the preferred point: in the open lane the 800 floor; with our tower 200 behind the point it would
-- have to stand inside the tower's range to hit the core there, so the point holds (reach 198 + 150).
do
	local e
	local setup = function(x)
		return function() e = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) }) e.range = 150 TOWERS = x and { ownTower(x, 0) } or {} end
	end
	local s, bot = spotFor(SDK, nil, setup(-300))
	local info = require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	check("covered point: the preferred point holds", s ~= nil and s.x == -100 and info.why == "pref", s and (s.x .. "," .. s.y))
	check("covered point: ut=1", info.covered == 1, info.covered)
	local open = spotFor(SDK, nil, setup(nil))
	check("no tower of ours: the 800 floor", open ~= nil and dist(open, e.loc) >= 800, open and dist(open, e.loc))
	-- Our tower 800 behind the point: the enemy could hit the point from outside the tower's range, so the spot backs off only
	-- to where the tower covers it (within 700 - 198 of the tower), not to the 800 floor.
	local edge = spotFor(SDK, nil, setup(-900))
	check("tower further back: the spot backs into its cover", edge ~= nil and dist(edge, Vector(-900, 0)) <= 502
		and dist(edge, e.loc) >= 348 and dist(edge, e.loc) < 800, edge and (edge.x .. "," .. edge.y))
end

-- A ranged enemy hero our tower is attacking: reach 550 + 48 + 150, not 550 + 48 + 450.
do
	local e
	local setup = function(tanked)
		return function()
			e = MakeUnit({ pid = 7, team = 3, loc = Vector(300, 0) }) e.range = 550
			TOWERS = { ownTower(-300, 0, tanked and e or nil) }
		end
	end
	local s, bot = spotFor(SDK, nil, setup(true))
	local info = require("bots/FunLib/humaniser/states/laning").SpotInfo(bot)
	check("tanking enemy: outside 748", s ~= nil and dist(s, e.loc) >= 748, s and dist(s, e.loc))
	check("tanking enemy: inside 1,048 (the open-lane reach)", s ~= nil and dist(s, e.loc) < 1048 and info.covered == 1, s and dist(s, e.loc))
	local n = spotFor(SDK, nil, setup(false))
	check("same enemy, tower on something else: 1,048", n ~= nil and dist(n, e.loc) >= 1048, n and dist(n, e.loc))
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
	-- Slice support-spot: a support whose lane hits and harass are ours stands on our spot; SupportHarass off, OHA's.
	local _, bsh, Hsh = spotFor(OHA, { coreLastHit = true, pos = 5, supportDeny = true }, setup)
	Hsh.States.SetLaneSpot(bsh, function() return Vector(-250, 0) end)
	T = T + 1
	local sh = require("bots/FunLib/humaniser/states/laning").Spot(bsh)
	check("LaneSpot: a support with SupportHarass on stands on our spot", sh ~= nil and sh.x ~= -250 and dist(sh, c.loc) >= 520, sh and sh.x)
	local _, bso, Hso = spotFor(OHA, { coreLastHit = true, pos = 5, supportDeny = true, supportHarass = false }, setup)
	Hso.States.SetLaneSpot(bso, function() return Vector(-250, 0) end)
	T = T + 1
	local so = require("bots/FunLib/humaniser/states/laning").Spot(bso)
	check("LaneSpot: SupportHarass off, the support keeps OHA's spot", so ~= nil and so.x == -250, so and so.x)
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
			H, bot = Fresh(DEFAULTS, { pos = o.pos or 5, team = o.team, supportDeny = o.on ~= false, supportDireOff = o.direOff, supportLastHit = o.lastHits, supportHarass = o.harass })
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
		stepped = H.States.SupportStep(bot)
		T = T + 0.05
		for _ = 1, 3 do
			H.States.Tick(bot)
			H.Tasks.Tick(bot)
			H.States.SupportStep(bot)
			T = T + 0.05
		end
	end)
	check("support deny: the support step acts first", stepped == true)
	check("support deny: the body swung at the own creep", bot.attacks ~= nil and bot.attacks[#bot.attacks] == own)

	local He, bote = support({ enemy = true, lastHits = false })
	local offeredEnemy
	silenced(function()
		offeredEnemy = require("bots/FunLib/humaniser/states/laning").HitOffered(bote)
		for _ = 1, 3 do frame(He, bote) end
	end)
	check("support last hits off: a dying enemy creep is not the body's (OHA's last hit)", offeredEnemy == false and bote.attacks == nil and He.States.BodySupportLastHits(bote) == false)

	-- OHA's spot (SupportHarass off): the leash is measured from whichever spot the support holds.
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

-- wave_hold's hold point (lane_spot input `hold`, slice core-in-lane): our wave gone, their melee creep walking in at (-200, 0)
-- and on the core; the hold point (-500, 0) is the preferred point and the creep keeps only the 200 held ring. A melee enemy
-- hero 600 from the point still pushes the spot back to its 800 reach: the hero limit stands.
do
	local L = function() return require("bots/FunLib/humaniser/states/laning") end
	local hold = Vector(-500, 0)
	local c
	local setup = function(hero)
		return function(bot)
			c = creep({ loc = Vector(-200, 0) })
			c.target = bot
			if hero then local e = MakeUnit({ pid = 7, team = 3, loc = Vector(100, 0) }) e.range = 150 end
			L().SetHold(bot, hold)
		end
	end
	local s, bot = spotFor(SDK, nil, setup(false))
	local info = L().SpotInfo(bot)
	check("hold: the spot is the hold point, anchor hold", s ~= nil and dist(s, hold) < 1 and info ~= nil and info.anchor == "hold", info and info.anchor)
	check("hold: inside the creep's 520 ring (it is meant to be on us)", s ~= nil and dist(s, c.loc) < 520, s and dist(s, c.loc))
	local sh = spotFor(SDK, nil, setup(true))
	check("hold under a melee hero 600 from the point: backed to its 800 reach", sh ~= nil and dist(sh, Vector(100, 0)) >= 800, sh and dist(sh, Vector(100, 0)))
	local so = spotFor(SDK, nil, function(bot) c = creep({ loc = Vector(-200, 0) }) c.target = bot end)
	check("no hold: the 520 ring", so ~= nil and dist(so, c.loc) >= 520, so and dist(so, c.loc))
end

finish()
