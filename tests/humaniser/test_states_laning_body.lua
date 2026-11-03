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
		SupportDeny = o.supportDeny == true, SupportDenyDire = o.supportDireOff ~= true, SupportLastHit = o.supportLastHit ~= false, LaneSpot = o.laneSpot }
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
	check("LaneSpot: a support keeps OHA's spot (step 2)", sup ~= nil and sup.x == -250, sup and sup.x)
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
			H, bot = Fresh(DEFAULTS, { pos = o.pos or 5, team = o.team, supportDeny = o.on ~= false, supportDireOff = o.direOff, supportLastHit = o.lastHits })
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

	local Hl, botl = support({ at = Vector(-200, 0) })
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

finish()
