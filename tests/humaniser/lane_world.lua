-- Shared stub world for lane tests. Not a test_ file, so run.js skips it. Later tasks extend it.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local UnitType, Lane = dota.UnitType, dota.Lane

local MIN_X, SPAN = -7000, 14000
LANE_Y = { [Lane.Top] = 5000, [Lane.Mid] = 0, [Lane.Bot] = -5000 }
local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

-- As in game (console.9055745679), lane amounts are in the calling script's frame: 0 at CURRENT_TEAM's base.
local function absLoc(l, a) return Vector(MIN_X + SPAN * a, LANE_Y[l]) end
local function callerAmount(a) return CURRENT_TEAM == 3 and 1 - a or a end
function GetLocationAlongLane(l, a) return absLoc(l, callerAmount(a)) end
function GetAmountAlongLane(l, v)
	return { amount = callerAmount(clamp01((v.x - MIN_X) / SPAN)), distance = math.abs(v.y - LANE_Y[l]) }
end

-- Team-relative amounts: 0 at the team's ancient, 1 at the enemy's.
LANE_FRONT = { [2] = {}, [3] = {} }
local function absAmount(team, rel) return team == 2 and rel or 1 - rel end
function GetLaneFrontAmount(team, lane, ignoreTowers) return (LANE_FRONT[team] or {})[lane] or 0.5 end
function GetLaneFrontLocation(team, lane, d)
	local a = absAmount(team, GetLaneFrontAmount(team, lane, true))
	local shift = (team == 2 and -d or d) / SPAN
	return absLoc(lane, clamp01(a + shift))
end

TOWERS_W = { [2] = {}, [3] = {} }
function GetTower(team, id) return TOWERS_W[team][id] end

CREEPS = { [2] = {}, [3] = {} }
NEUTRALS = {}
SPAWNERS = {}
LAST_SEEN = {}
ACTIONS = {}
GETUNITLIST_CALLS = {}
OBSERVER = nil
function IsHeroAlive(pid) for t = 2, 3 do for _, u in ipairs(UNITS[t]) do if u.pid == pid then return u.alive end end end return false end

local CreepMeta = {}
CreepMeta.__index = CreepMeta
function CreepMeta:GetAttackTarget() return self.target end
function CreepMeta:GetHealth() return self.hp end
function CreepMeta:GetMaxHealth() return self.maxhp end
function CreepMeta:GetUnitName() return self.name end
-- `removed`: the engine deleted the creep but a list still holds its handle, as after a death in game.
function CreepMeta:IsNull() return self.removed == true end
function CreepMeta:IsAlive()
	if self.removed then error("Invalid object passed to IsAlive.") end
	return self.hp > 0
end
function CreepMeta:CanBeSeen() return true end
function CreepMeta:GetLocation() if self.removed then return nil end return self.loc end
function CreepMeta:GetTeam() return self.team end
function CreepMeta:IsHero() return false end

-- The engine deletes the creep: fresh queries no longer return it, handles already in a list stay behind.
function RemoveCreep(c)
	c.removed = true
	for _, list in pairs(CREEPS) do
		for i = #list, 1, -1 do if list[i] == c then table.remove(list, i) end end
	end
end

function MakeCreep(o)
	local c = setmetatable({
		team = o.team, loc = Vector(o.x, o.y), hp = o.hp or 550, maxhp = o.maxhp or 550,
		name = o.name or (o.team == 2 and "npc_dota_creep_goodguys_melee" or "npc_dota_creep_badguys_melee"), target = o.target,
	}, CreepMeta)
	table.insert(CREEPS[o.team], c)
	return c
end

-- Neutrals live outside CREEPS; GetNearbyNeutralCreeps returns NEUTRALS whatever the radius.
function MakeNeutral(o)
	local c = setmetatable({ team = 4, loc = Vector(o.x, o.y), hp = o.hp or 300, maxhp = o.maxhp or 300,
		name = o.name or "npc_dota_neutral_kobold" }, CreepMeta)
	table.insert(NEUTRALS, c)
	return c
end

-- Valve's RandomVector returns a vector of exactly this length; the direction comes from one RandomFloat draw.
function RandomVector(len)
	local a = RandomFloat(0, 2 * math.pi)
	return Vector(len * math.cos(a), len * math.sin(a), 0)
end

function GetUnitList(t)
	GETUNITLIST_CALLS[t] = (GETUNITLIST_CALLS[t] or 0) + 1
	local other = CURRENT_TEAM == 2 and 3 or 2
	if t == UnitType.AlliedCreeps then return CREEPS[CURRENT_TEAM] end
	if t == UnitType.EnemyCreeps then return CREEPS[other] end
	if t == UnitType.EnemyHeroes then
		local r = {}
		for _, u in ipairs(UNITS[other]) do
			if not (u.hiddenFrom and u.hiddenFrom[OBSERVER]) then table.insert(r, u) end
		end
		return r
	end
	if t == UnitType.AlliedHeroes then return UNITS[CURRENT_TEAM] end
	return {}
end
function GetNeutralSpawners() return SPAWNERS end
-- IMPASSABLE(v) true marks a blocked location (e.g. beyond a map edge); nil means everything is passable.
function IsLocationPassable(v) return IMPASSABLE == nil or not IMPASSABLE(v) end
-- FOGGED(v) true marks a location the team cannot see; nil means everything is visible.
function IsLocationVisible(v) return FOGGED == nil or not FOGGED(v) end
function GetHeroLastSeenInfo(pid) return LAST_SEEN[pid] and { LAST_SEEN[pid] } or {} end

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index

local T1_AMOUNT = { [2] = 0.3, [3] = 0.7 }
local T1_ID = { [Lane.Top] = dota.Tower.Top1, [Lane.Mid] = dota.Tower.Mid1, [Lane.Bot] = dota.Tower.Bot1 }
function MakeLaneTowers()
	local w = { [2] = {}, [3] = {} }
	for team = 2, 3 do
		for lane, id in pairs(T1_ID) do
			local t = setmetatable({ pid = -1, team = team, bot = true, alive = true, hp = 1300, modifiers = {},
				loc = absLoc(lane, T1_AMOUNT[team]) }, { __index = UnitMeta })
			t.GetUnitName = function() return "tower_t1" end
			w[team][id] = t
		end
	end
	return w
end
TOWERS_W = MakeLaneTowers()
function UnitMeta:GetAttackTarget() return self.target end
function UnitMeta:GetAttackDamage() return self.dmg or 50 end
function UnitMeta:GetAttackRange() return self.range or 550 end
function UnitMeta:GetExtrapolatedLocation(t) return self.extrap or self.loc end
function UnitMeta:GetMostRecentPing() return { time = 0, location = Vector(0, 0), normal_ping = true } end
function UnitMeta:GetNearbyNeutralCreeps() return NEUTRALS end
function UnitMeta:GetLastAttackTime() return self.lastAttack or -1000 end
function UnitMeta:GetAttackProjectileSpeed() return self.projSpeed or 0 end
function UnitMeta:GetCurrentMovementSpeed() return self.speed or 300 end
-- heroHitAt / towerHitAt: the game time an enemy hero or tower last damaged the unit.
function UnitMeta:WasRecentlyDamagedByAnyHero(t) return self.heroHitAt ~= nil and T - self.heroHitAt <= t end
function UnitMeta:WasRecentlyDamagedByTower(t) return self.towerHitAt ~= nil and T - self.towerHitAt <= t end
function UnitMeta:GetNearbyTowers(r, enemy)
	local team = enemy and (self.team == 2 and 3 or 2) or self.team
	local out = {}
	for _, t in pairs(TOWERS_W[team]) do
		local dx, dy = t.loc.x - self.loc.x, t.loc.y - self.loc.y
		if math.sqrt(dx * dx + dy * dy) <= r then table.insert(out, t) end
	end
	return out
end
function UnitMeta:GetNearbyHeroes(r, enemy)
	local team = enemy and (self.team == 2 and 3 or 2) or self.team
	local out = {}
	for _, u in ipairs(UNITS[team]) do
		local dx, dy = u.loc.x - self.loc.x, u.loc.y - self.loc.y
		if math.sqrt(dx * dx + dy * dy) <= r then table.insert(out, u) end
	end
	return out
end
function GetUnitToUnitDistance(a, b)
	local dx, dy = a:GetLocation().x - b:GetLocation().x, a:GetLocation().y - b:GetLocation().y
	return math.sqrt(dx * dx + dy * dy)
end
function UnitMeta:GetNearbyLaneCreeps(r, enemy)
	local team = enemy and (self.team == 2 and 3 or 2) or self.team
	local out = {}
	for _, c in ipairs(CREEPS[team]) do
		local dx, dy = c.loc.x - self.loc.x, c.loc.y - self.loc.y
		if math.sqrt(dx * dx + dy * dy) <= r then table.insert(out, c) end
	end
	return out
end
-- Items: u.items = { [slot] = { name = ..., ready = bool } }; trees: TREES = { [id] = Vector }.
function UnitMeta:FindItemSlot(name)
	for slot, it in pairs(self.items or {}) do if it.name == name then return slot end end
	return -1
end
function UnitMeta:GetItemInSlot(slot)
	local it = (self.items or {})[slot]
	if it == nil then return nil end
	return { GetName = function() return it.name end, IsFullyCastable = function() return it.ready ~= false end, name = it.name }
end
function UnitMeta:GetMana() return self.mana or 100 end
function UnitMeta:GetMaxMana() return self.maxMana or 100 end
function UnitMeta:GetNearbyTrees(r)
	local ids = {}
	for id, loc in pairs(TREES or {}) do if GetUnitToLocationDistance(self, loc) <= r then table.insert(ids, id) end end
	table.sort(ids, function(a, b) return GetUnitToLocationDistance(self, TREES[a]) < GetUnitToLocationDistance(self, TREES[b]) end)
	return ids
end
function GetTreeLocation(id) return TREES[id] end
for _, kind in ipairs({ "MoveToLocation", "AttackUnit", "MovePath", "ClearActions", "UseAbilityOnLocation", "UseAbilityOnTree", "UseAbilityOnEntity" }) do
	UnitMeta["Action_" .. kind] = function(self, ...)
		table.insert(ACTIONS, { pid = self.pid, kind = kind, args = { ... } })
	end
end
function ActionsOf(pid, kind)
	local r = {}
	for _, a in ipairs(ACTIONS) do if a.pid == pid and (kind == nil or a.kind == kind) then table.insert(r, a) end end
	return r
end

local queue, qi = nil, 1
function SetRandomSequence(list)
	queue, qi = list, 1
	function RandomFloat(a, b)
		local f
		if queue and qi <= #queue then f = queue[qi]; qi = qi + 1 else f = RANDOM_FRACTION or 0.5 end
		return a + (b - a) * f
	end
end
-- Queued values not yet drawn, for tests asserting that a call consumed no roll.
function RandomUnread() return queue and math.max(0, #queue - qi + 1) or 0 end
local function clearRandom()
	queue, qi = nil, 1
	function RandomFloat(a, b) return a + (b - a) * (RANDOM_FRACTION or 0.5) end
end

LANING, STRONGER, NEXT_RUNE = nil, nil, nil

function LaneFresh(laneCfg, extra)
	extra = extra or {}
	ResetWorld()
	CREEPS, NEUTRALS, SPAWNERS, LAST_SEEN, ACTIONS = { [2] = {}, [3] = {} }, {}, {}, {}, {}
	LANE_FRONT, TOWERS_W, GETUNITLIST_CALLS = { [2] = {}, [3] = {} }, MakeLaneTowers(), {}
	LANING, STRONGER, NEXT_RUNE, OBSERVER = nil, nil, nil, nil
	IMPASSABLE, TREES = nil, nil
	clearRandom()
	local H = FreshHumaniser({ Enable = extra.enable ~= false, Debug = extra.debug, SkillOverride = extra.skill, Lane = laneCfg,
		Telemetry = extra.telemetry })
	H.Lane.SetHelpers({
		GetPosition = function(u) return u.pos end,
		IsInLaningPhase = function() return LANING ~= false end,
		WillKillTarget = function(t, dmg) return t.hp <= dmg end,
		GetAttackProDelayTime = function() return 0.3 end,
		WeAreStronger = function() return STRONGER == true end,
		NextPowerRuneTime = function() return NEXT_RUNE or 1e9 end,
		IsValidHero = function(u) return u ~= nil and u.alive end,
		IsSuspiciousIllusion = function(u) return u.illusion == true end,
		IsValidBuilding = function(u) return u ~= nil and u.alive end,
		GetHP = function(u) return u:GetHealth() / u:GetMaxHealth() end,
	})
	H.Lane.Config.ResetSettings()
	H.Lane.Hooks.ResetHooks()
	H.Lane.Camps.ResetCache()
	H.Lane.LaneState.ResetCache()
	H.Lane.LaneRoles.ResetCache()
	H.Lane.LanePlan.ResetCache()
	H.Lane.LanePlanner.ResetCache()
	H.Lane.LaneTech.ResetCache()
	H.Lane.CampJobs.ResetCache()
	H.Lane.Stacking.ResetCache()
	H.Lane.Harass.ResetCache()
	H.Lane.Counter.ResetCache()
	-- ResetHooks dropped the probes registered at module load.
	H.Lane.CampJobs.RegisterProbes()
	H.Lane.Stacking.RegisterProbes()
	H.Lane.LaneMid.RegisterProbes()
	H.Lane.Counter.RegisterProbes()
	return H
end
