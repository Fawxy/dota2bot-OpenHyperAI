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
	package.loaded["bots/FunLib/custom_loader"].Ours = { CoreLastHit = o.coreLastHit == true, CoreLastHitDire = o.direOff ~= true }
	local Phase = require("bots/FunLib/humaniser/transitions/phase")
	Phase.IsLaningFor = function() return true end
	local LaneConfig = require("bots/FunLib/humaniser/lane_config")
	local positions = {}
	LaneConfig.SetHelpers({ GetPosition = function(u) return positions[u.pid] end })
	MakeUnit({ pid = 0, bot = false, loc = Vector(-4000, -4000) })
	local bot = MakeUnit({ pid = 1, team = o.team, mode = LANING, loc = o.loc or Vector(-300, 0), level = o.level or 3 })
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

-- Enemy T1 before level 6: outside its 750 range even where the creep rings allow closer; not at level 6.
do
	local tower = { team = 3, loc = Vector(200, 0) }
	tower.GetLocation = function() return tower.loc end
	local setup = function() creep({ loc = Vector(60, 0) }) TOWERS = { tower } end
	tower.IsAlive = function() return true end
	tower.IsNull = function() return false end
	local s3 = spotFor(SDK, { level = 3 }, setup)
	check("tower ring at level 3", s3 ~= nil and dist(s3, tower.loc) >= 750, s3 and dist(s3, tower.loc))
	local s6 = spotFor(SDK, { level = 6 }, setup)
	check("no tower ring at level 6", s6 ~= nil and dist(s6, tower.loc) < 750, s6 and dist(s6, tower.loc))
end

-- Side shift: a core moves away from the enemy hero, a support (pos 5) towards its approach line.
do
	local setup = function() creep({ loc = Vector(60, 0) }) MakeUnit({ pid = 7, team = 3, loc = Vector(200, 500) }) end
	local core = spotFor(SDK, { pos = 2 }, setup)
	local sup = spotFor(SDK, { pos = 5 }, setup)
	check("core shifts away from the enemy hero", core ~= nil and core.y < 0, core and core.y)
	check("support shifts towards the enemy hero", sup ~= nil and sup.y > 0, sup and sup.y)
end

-- No enemy wave in sight: OHA's own spot.
do
	local s, bot, H = spotFor(SDK)
	H.States.SetLaneSpot(bot, function() return Vector(-777, 5) end)
	local Laning = require("bots/FunLib/humaniser/states/laning")
	T = T + 1 -- the spot is cached per frame
	s = Laning.Spot(bot)
	check("no wave: OHA's spot", s ~= nil and s.x == -777, s and s.x)
end


-- The wave dies: the last SDK spot is kept for a few seconds rather than jumping to OHA's spot and back.
do
	local c
	local s1, bot, H = spotFor(SDK, nil, function() c = creep({ loc = Vector(60, 0) }) end)
	H.States.SetLaneSpot(bot, function() return Vector(-1500, 0) end)
	local Laning = require("bots/FunLib/humaniser/states/laning")
	c.alive = false
	T = T + 2
	local s2 = Laning.Spot(bot)
	check("wave gone 2 s: SDK spot kept", s2 ~= nil and s1 ~= nil and s2.x == s1.x, s2 and s2.x)
	T = T + 3
	local s3 = Laning.Spot(bot)
	check("wave gone 5 s: OHA's spot", s3 ~= nil and s3.x == -1500, s3 and s3.x)
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
	local function side(team)
		local H, bot
		silenced(function()
			H, bot = Fresh({ Enable = true, Own = { laning = { 2 } }, Teams = "allies", Laning = { LastHit = {} } }, { team = team, pos = 1, coreLastHit = true, direOff = true })
		end)
		return H.States.MayOwn(bot)
	end
	check("dire off: Radiant pos 1 still owned", side(2) == true)
	check("dire off: Dire pos 1 left to Valve", side(3) == false)
end

finish()
