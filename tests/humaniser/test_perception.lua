-- Perception (task 03): notice delay through the real aba_global_overrides hooks, and reaction delay through
-- the real jmz_func predicates (extracted from the source, since jmz_func itself is too heavy to load here).
dofile(HARNESS_DIR .. "/dota_stubs.lua")

UNIT_LIST_ALLIES, UNIT_LIST_ENEMIES, UNIT_LIST_ENEMY_HEROES = 1, 7, 8
BOT_MODE_NONE = 0
TEAM_RADIANT, TEAM_DIRE = 2, 3
ABILITY_BEHAVIOR_NO_TARGET, ABILITY_BEHAVIOR_UNIT_TARGET, ABILITY_BEHAVIOR_POINT = 4, 8, 16
local PERCEPTION = "bots/FunLib/humaniser/perception"

-- Units use the engine class so the overrides installed on CDOTA_Bot_Script apply to them.
CDOTA_Bot_Script = {}
local WORLD = {}
local BOT

local function dist(a, b)
	local dx, dy = a.loc.x - b.loc.x, a.loc.y - b.loc.y
	return math.sqrt(dx * dx + dy * dy)
end

local function installRawEngine()
	for k in pairs(CDOTA_Bot_Script) do CDOTA_Bot_Script[k] = nil end
	local C = CDOTA_Bot_Script
	function C:GetPlayerID() return self.pid end
	function C:GetTeam() return self.team end
	function C:IsBot() return self.bot end
	function C:IsHero() return self.hero end
	function C:IsIllusion() return false end
	function C:IsBuilding() return false end
	function C:IsNull() return false end
	function C:IsAlive() return true end
	function C:CanBeSeen() return self.visible end
	function C:GetLocation() return self.loc end
	function C:GetUnitName() return self.name end
	function C:GetDifficulty() return DIFFICULTY_MEDIUM end
	function C:GetLevel() return 1 end
	function C:HasModifier() return false end
	function C:GetModifierByName() return -1 end
	function C:WasRecentlyDamagedByHero(h, t) return self.damagedBy == h and T - self.damagedAt <= t end
	function C:IsChanneling() return self.channeling == true end
	function C:GetIncomingTrackingProjectiles() self.lastRaw = self.projectiles or {} return self.lastRaw end
	function C:GetNearbyHeroes(r, bEnemies)
		local out = {}
		for _, u in ipairs(WORLD) do
			if u ~= self and u.hero and u.visible and (u.team ~= self.team) == bEnemies and dist(self, u) <= r then table.insert(out, u) end
		end
		self.lastRaw = out
		return out
	end
	-- Casting state for the reaction predicates
	function C:IsCastingAbility() return self.casting ~= nil end
	function C:IsUsingAbility() return false end
	function C:IsFacingLocation() return true end
	function C:GetCurrentActiveAbility() return self.casting end
	function C:GetAnimCycle() return self.cycle or 0 end

	LAST_UNIT_LIST = nil
	function GetUnitList(nType)
		local out = {}
		for _, u in ipairs(WORLD) do
			if u.team ~= GetTeam() and u.visible and (u.hero or nType == UNIT_LIST_ENEMIES) then table.insert(out, u) end
		end
		LAST_UNIT_LIST = out
		return out
	end
	function GetUnitToUnitDistance(a, b) return dist(a, b) end
	function GetBot() return BOT end
end

local function U(o)
	local u = setmetatable({
		pid = o.pid, team = o.team or 2, bot = o.bot ~= false, hero = o.hero ~= false, visible = o.visible ~= false,
		loc = o.loc or Vector(0, 0), name = o.name or ("unit" .. tostring(o.pid)), modifiers = {}, difficulty = DIFFICULTY_MEDIUM, level = 1,
	}, { __index = CDOTA_Bot_Script })
	table.insert(WORLD, u)
	if o.pid ~= nil then table.insert(UNITS[u.team], u) end
	return u
end

local function stubRandom() RandomFloat = function(a, b) return a + (b - a) * 0.5 end end
local ORIG_PRINT = print

-- Fresh humaniser instance plus freshly installed overrides bound to it. Returns the perception module.
local function Load(cfg)
	ResetWorld()
	WORLD = {}
	installRawEngine()
	FreshHumaniser(cfg)
	package.loaded["bots/FunLib/aba_global_overrides"] = nil
	require("bots/FunLib/aba_global_overrides")
	-- The overrides also replace RandomFloat (with math.random) and print (silenced); undo both.
	stubRandom()
	print = ORIG_PRINT
	return require(PERCEPTION)
end

local function count(list) return list == nil and -1 or #list end
local function enemiesOf(u, r) return count(u:GetNearbyHeroes(r or 1600, true, BOT_MODE_NONE)) end
local function skill(s) return { Enable = true, SkillOverride = s } end

-- With RandomFloat at its midpoint and no lapse: notice 0.55 s / react 0.50 s at skill 0, 0.18 s / 0.17 s at skill 1.

-- Part A: hidden until the notice delay passes, and the delay scales with skill
do
	Load(skill(0))
	BOT = U({ pid = 1 })
	local lion = U({ pid = 5, team = 3, loc = Vector(1000, 0), name = "lion" })
	check("unnoticed hero hidden on first sight", enemiesOf(BOT) == 0)
	T = 0.5
	check("still hidden before notice delay", enemiesOf(BOT) == 0)
	check("unit list hides it too", count(GetUnitList(UNIT_LIST_ENEMY_HEROES)) == 0)
	T = 0.56
	check("visible once notice delay passed", enemiesOf(BOT) == 1)
	check("unit list shows it once noticed", count(GetUnitList(UNIT_LIST_ENEMY_HEROES)) == 1)

	Load(skill(1))
	BOT = U({ pid = 1 })
	U({ pid = 5, team = 3, loc = Vector(1000, 0) })
	enemiesOf(BOT)
	T = 0.2
	check("high skill notices sooner", enemiesOf(BOT) == 1)
end

-- Part A: UNIT_LIST_ENEMIES hides only unnoticed heroes; creeps pass
do
	Load(skill(0))
	BOT = U({ pid = 1 })
	U({ pid = 5, team = 3, loc = Vector(1000, 0) })
	local creep = U({ team = 3, hero = false, loc = Vector(900, 0) })
	local list = GetUnitList(UNIT_LIST_ENEMIES)
	check("creep kept, hero hidden", #list == 1 and list[1] == creep, #list)
end

-- Part A: object permanence within 2 s, a fresh delay after longer absence
do
	Load(skill(0))
	BOT = U({ pid = 1 })
	local e = U({ pid = 5, team = 3, loc = Vector(1000, 0) })
	enemiesOf(BOT)
	T = 0.6
	check("noticed", enemiesOf(BOT) == 1)
	e.visible = false
	for t = 0.7, 1.5, 0.1 do T = t enemiesOf(BOT) end
	T = 2.0
	e.visible = true
	check("re-acquired instantly after a short juke", enemiesOf(BOT) == 1)
	e.visible = false
	T = 2.5 enemiesOf(BOT)
	T = 5.0
	e.visible = true
	check("long absence needs a new notice", enemiesOf(BOT) == 0)
	T = 5.56
	check("new notice completes", enemiesOf(BOT) == 1)
end

-- Part A: a hero kept in vision but outside the radius of recent queries keeps permanence
do
	Load(skill(0))
	BOT = U({ pid = 1 })
	U({ pid = 5, team = 3, loc = Vector(1000, 0) })
	enemiesOf(BOT)
	T = 0.6 enemiesOf(BOT)
	for t = 0.7, 3.5, 0.1 do T = t enemiesOf(BOT, 500) end
	T = 3.6
	check("continuous vision is not a new sighting", enemiesOf(BOT) == 1)
end

-- Part A: immediate-notice exceptions
do
	Load(skill(0))
	BOT = U({ pid = 1 })
	U({ pid = 5, team = 3, loc = Vector(250, 0) })
	check("within 300 units noticed at once", enemiesOf(BOT) == 1)

	Load(skill(0))
	BOT = U({ pid = 1 })
	local e = U({ pid = 5, team = 3, loc = Vector(1000, 0) })
	BOT.damagedBy, BOT.damagedAt = e, 0
	check("recent damage noticed at once", enemiesOf(BOT) == 1)
end

-- Part A: a teammate noticing over 1 s ago calls it out (shared modules), and degrades when modules are not shared
do
	local P = Load(skill(0))
	local a = U({ pid = 1 })
	local b = U({ pid = 2, loc = Vector(0, 100) })
	U({ pid = 5, team = 3, loc = Vector(1000, 0) })
	BOT = a enemiesOf(a)
	T = 0.6 enemiesOf(a)
	T = 1.2
	BOT = b
	check("callout needs teammate to have noticed over 1 s ago", enemiesOf(b) == 0)
	T = 1.61
	BOT = a enemiesOf(a)
	BOT = b
	check("teammate callout", enemiesOf(b) == 1)

	-- A separate module instance (non-shared modules) has no teammate state: plain notice delay, no error.
	local other = FreshHumaniser(skill(0)) and require(PERCEPTION)
	stubRandom()
	b:GetNearbyHeroes(1600, true)
	check("non-shared instance falls back to own delay", #other.FilterNearbyEnemies(b, b.lastRaw) == 0)
	check("separate instances", other ~= P)
end

-- Part A: enemy callers and ally queries pass through
do
	Load(skill(0))
	BOT = U({ pid = 1 })
	local e = U({ pid = 5, team = 3, loc = Vector(1000, 0) })
	U({ pid = 3, loc = Vector(2400, 0) })
	-- The far teammate would be hidden (a new, distant sighting) if this list were filtered.
	check("enemy caller's enemy list (our heroes) not filtered", enemiesOf(e) == 2)
	local ally = U({ pid = 2, loc = Vector(900, 0) })
	check("ally lists not filtered", count(BOT:GetNearbyHeroes(1600, false, BOT_MODE_NONE)) == 1)
	check("allied caller filtered by the observer's knowledge", enemiesOf(ally) == 0)
end

-- Kill switch: overrides return the engine's own result untouched
for _, cfg in ipairs({ { Enable = false }, { Enable = true, Perception = { Enable = false } } }) do
	local P = Load(cfg)
	BOT = U({ pid = 1 })
	local e = U({ pid = 5, team = 3, loc = Vector(1000, 0) })
	local list = BOT:GetNearbyHeroes(1600, true, BOT_MODE_NONE)
	check("disabled: GetNearbyHeroes is the raw table", rawequal(list, BOT.lastRaw) and #list == 1)
	local ul = GetUnitList(UNIT_LIST_ENEMY_HEROES)
	check("disabled: GetUnitList is the raw table", rawequal(ul, LAST_UNIT_LIST) and #ul == 1)
	e.channeling = true
	check("disabled: enemy channel seen at once", e:IsChanneling() == true)
	BOT.projectiles = { { is_attack = true, caster = e, location = Vector(10, 0) } }
	check("disabled: projectiles are the raw table", rawequal(P.GetIncomingTrackingProjectiles(BOT), BOT.lastRaw))
	check("disabled: casts known at once", P.IsCastKnown(e, "lion_voodoo") == true)
end

-- Part B: the real jmz_func, loaded with stubbed requires (its dependencies are too heavy for the harness)
-- and the fresh perception instance as its HPerception upvalue.
local function loadPredicates(P)
	local proxy
	proxy = setmetatable({}, { __index = function() return proxy end, __call = function() return proxy end })
	local env = setmetatable({
		require = function(path) if path == PERCEPTION then return P end return proxy end,
	}, { __index = _G })
	return assert(loadfile(HARNESS_DIR .. "/../../bots/FunLib/jmz_func.lua", "t", env))()
end

local function ability(name, behavior, castPoint)
	return {
		GetName = function() return name end,
		GetBehavior = function() return behavior end,
		GetCastPoint = function() return castPoint or 0.3 end,
	}
end

-- Bot caster: no reaction until the react delay has passed; a later cast is a new event
do
	local J = loadPredicates(Load(skill(0)))
	BOT = U({ pid = 1 })
	local e = U({ pid = 5, team = 3, loc = Vector(200, 0) })
	e.casting = ability("lion_voodoo", ABILITY_BEHAVIOR_UNIT_TARGET)
	check("cast not reacted to on first sight", J.IsWillBeCastUnitTargetSpell(BOT, 800) == false)
	T = 0.45
	check("cast not reacted to before react delay", J.IsWillBeCastUnitTargetSpell(BOT, 800) == false)
	T = 0.51
	check("cast reacted to after react delay", J.IsWillBeCastUnitTargetSpell(BOT, 800) == true)
	e.casting = nil
	T = 2.0
	e.casting = ability("lion_voodoo", ABILITY_BEHAVIOR_UNIT_TARGET)
	check("next cast is a new event", J.IsWillBeCastUnitTargetSpell(BOT, 800) == false)
	e.casting = ability("lion_impale", ABILITY_BEHAVIOR_POINT)
	T = 2.3
	check("point cast not yet known", J.IsWillBeCastPointSpell(BOT, 800) == false)
	T = 2.55 J.IsWillBeCastPointSpell(BOT, 800)
	T = 2.81
	check("point cast known after react delay", J.IsWillBeCastPointSpell(BOT, 800) == true)
end

-- Human caster with a long cast point: low skill fires as soon as it knows, high skill holds for the window
do
	local function run(s)
		local J = loadPredicates(Load(skill(s)))
		BOT = U({ pid = 1 })
		local e = U({ pid = 5, team = 3, loc = Vector(200, 0), bot = false })
		e.casting = ability("lion_voodoo", ABILITY_BEHAVIOR_UNIT_TARGET, 2.0)
		-- Polled every 0.05 s through a 2 s cast point; results at 0 s, 0.45 s and 1.9 s.
		local results = {}
		for i = 0, 38 do
			T, e.cycle = i * 0.05, i * 0.025
			local r = J.IsWillBeCastUnitTargetSpell(BOT, 800)
			if i == 0 or i == 9 or i == 38 then table.insert(results, r) end
		end
		return results
	end
	local low, high = run(0.3), run(1)
	check("low skill: not before known", low[1] == false)
	check("low skill: fires early once known", low[2] == true)
	check("high skill: known early but waits", high[2] == false)
	check("high skill: fires in the optimal window", high[3] == true)
end

-- Kill switch on the predicates: original behaviour, including the frame-perfect human branch
do
	local J = loadPredicates(Load({ Enable = true, Perception = { Enable = false } }))
	BOT = U({ pid = 1 })
	local e = U({ pid = 5, team = 3, loc = Vector(200, 0), bot = false })
	e.casting = ability("lion_voodoo", ABILITY_BEHAVIOR_UNIT_TARGET, 2.0)
	e.cycle = 0.225
	check("disabled: human early cast ignored as before", J.IsWillBeCastUnitTargetSpell(BOT, 800) == false)
	e.cycle = 0.95
	check("disabled: human cast in window fires at once", J.IsWillBeCastUnitTargetSpell(BOT, 800) == true)
end

-- Tracking projectiles: enemy ones delayed, allied ones pass, a vanished identity starts over
do
	local P = Load(skill(0))
	local J = loadPredicates(P)
	BOT = U({ pid = 1 })
	local e = U({ pid = 5, team = 3, loc = Vector(600, 0) })
	local ally = U({ pid = 2, loc = Vector(500, 0) })
	local attack = { is_attack = true, caster = e, location = Vector(50, 0) }
	BOT.projectiles = { { is_attack = true, caster = ally, location = Vector(50, 0) } }
	check("allied projectile passes at once", J.IsAttackProjectileIncoming(BOT, 300) == true)
	BOT.projectiles = { attack }
	T = 0.1
	check("enemy attack not yet known", J.IsAttackProjectileIncoming(BOT, 300) == false)
	T = 0.61
	check("enemy attack known after react delay", J.IsAttackProjectileIncoming(BOT, 300) == true)
	T = 0.7
	BOT.projectiles = {}
	J.IsAttackProjectileIncoming(BOT, 300)
	T = 0.8
	BOT.projectiles = { attack }
	check("identity dropped when it vanished", J.IsAttackProjectileIncoming(BOT, 300) == false)
	check("same-frame call is cached", rawequal(P.GetIncomingTrackingProjectiles(BOT), P.GetIncomingTrackingProjectiles(BOT)))
end

-- Channels (IsChanneling override): enemy channels delayed, a tracked cast is not delayed twice, allies pass
do
	local P = Load(skill(0))
	BOT = U({ pid = 1 })
	local e = U({ pid = 5, team = 3, loc = Vector(200, 0) })
	local e2 = U({ pid = 6, team = 3, loc = Vector(200, 50) })
	local ally = U({ pid = 2, loc = Vector(100, 0) })
	ally.channeling = true
	check("allied channel seen at once", ally:IsChanneling() == true)
	e.channeling = true
	check("enemy channel not yet known", e:IsChanneling() == false)
	T = 0.51
	check("enemy channel known after react delay", e:IsChanneling() == true)
	for t = 0.51, 1.02, 0.17 do T = t P.IsCastKnown(e2, "crystal_maiden_freezing_field") end
	T = 1.03
	e2.channeling = true
	check("channel after a known cast is not delayed again", e2:IsChanneling() == true)
end

finish()
