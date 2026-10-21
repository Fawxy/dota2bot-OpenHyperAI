-- Shared stub world for lane tests. Not a test_ file, so run.js skips it. Later tasks extend it.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local UnitType, Lane = dota.UnitType, dota.Lane

local MIN_X, SPAN = -7000, 14000
LANE_Y = { [Lane.Top] = 5000, [Lane.Mid] = 0, [Lane.Bot] = -5000 }
local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

function GetLocationAlongLane(l, a) return Vector(MIN_X + SPAN * a, LANE_Y[l]) end
function GetAmountAlongLane(l, v)
	return { amount = clamp01((v.x - MIN_X) / SPAN), distance = math.abs(v.y - LANE_Y[l]) }
end

-- Team-relative amounts: 0 at the team's ancient, 1 at the enemy's.
LANE_FRONT = { [2] = {}, [3] = {} }
local function absAmount(team, rel) return team == 2 and rel or 1 - rel end
function GetLaneFrontAmount(team, lane, ignoreTowers) return (LANE_FRONT[team] or {})[lane] or 0.5 end
function GetLaneFrontLocation(team, lane, d)
	local a = absAmount(team, GetLaneFrontAmount(team, lane, true))
	local shift = (team == 2 and -d or d) / SPAN
	return GetLocationAlongLane(lane, clamp01(a + shift))
end

TOWERS_W = { [2] = {}, [3] = {} }
function GetTower(team, id) return TOWERS_W[team][id] end

CREEPS = { [2] = {}, [3] = {} }
NEUTRALS = {}
SPAWNERS = {}
LAST_SEEN = {}
ACTIONS = {}
GETUNITLIST_CALLS = {}

local CreepMeta = {}
CreepMeta.__index = CreepMeta
function CreepMeta:GetAttackTarget() return self.target end
function CreepMeta:GetHealth() return self.hp end
function CreepMeta:GetMaxHealth() return self.maxhp end
function CreepMeta:GetUnitName() return self.name end
function CreepMeta:IsAlive() return self.hp > 0 end
function CreepMeta:CanBeSeen() return true end
function CreepMeta:GetLocation() return self.loc end
function CreepMeta:GetTeam() return self.team end

function MakeCreep(o)
	local c = setmetatable({
		team = o.team, loc = Vector(o.x, o.y), hp = o.hp or 550, maxhp = o.maxhp or 550,
		name = o.name or "npc_dota_creep_lane", target = o.target,
	}, CreepMeta)
	table.insert(CREEPS[o.team], c)
	return c
end

function GetUnitList(t)
	GETUNITLIST_CALLS[t] = (GETUNITLIST_CALLS[t] or 0) + 1
	local other = CURRENT_TEAM == 2 and 3 or 2
	if t == UnitType.AlliedCreeps then return CREEPS[CURRENT_TEAM] end
	if t == UnitType.EnemyCreeps then return CREEPS[other] end
	if t == UnitType.EnemyHeroes then return UNITS[other] end
	if t == UnitType.AlliedHeroes then return UNITS[CURRENT_TEAM] end
	return {}
end
function GetNeutralSpawners() return SPAWNERS end
function GetHeroLastSeenInfo(pid) return LAST_SEEN[pid] and { LAST_SEEN[pid] } or {} end

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function GetNearbyNeutralsStub() return NEUTRALS end
function UnitMeta:GetNearbyNeutralCreeps() return NEUTRALS end
for _, kind in ipairs({ "MoveToLocation", "AttackUnit", "MovePath", "ClearActions", "UseAbilityOnLocation" }) do
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
local function clearRandom()
	queue, qi = nil, 1
	function RandomFloat(a, b) return a + (b - a) * (RANDOM_FRACTION or 0.5) end
end

LANING, STRONGER, NEXT_RUNE = nil, nil, nil

function LaneFresh(laneCfg, extra)
	extra = extra or {}
	ResetWorld()
	CREEPS, NEUTRALS, SPAWNERS, LAST_SEEN, ACTIONS = { [2] = {}, [3] = {} }, {}, {}, {}, {}
	LANE_FRONT, TOWERS_W, GETUNITLIST_CALLS = { [2] = {}, [3] = {} }, { [2] = {}, [3] = {} }, {}
	LANING, STRONGER, NEXT_RUNE = nil, nil, nil
	clearRandom()
	local H = FreshHumaniser({ Enable = extra.enable ~= false, SkillOverride = extra.skill, Lane = laneCfg })
	H.Lane.SetHelpers({
		GetPosition = function(u) return u.pos end,
		IsInLaningPhase = function() return LANING ~= false end,
		WillKillTarget = function(t, dmg) return t.hp <= dmg end,
		GetAttackProDelayTime = function() return 0.3 end,
		WeAreStronger = function() return STRONGER == true end,
		NextPowerRuneTime = function() return NEXT_RUNE or 120 end,
	})
	H.Lane.Config.ResetSettings()
	H.Lane.Hooks.ResetHooks()
	return H
end
