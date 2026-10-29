-- Stub world for bots/mode_laning_generic.lua GetDesire and Think: a stub bot, creeps, allied heroes and a stub humaniser.
-- Shared by test_laning_mode.lua and the laning_mode fixture driver. Not a test_ file, so run.js skips it.
dofile(HARNESS_DIR .. "/dota_stubs.lua")

BOT_MODE_LANING, BOT_MODE_NONE = 1, 0
BOT_MODE_DESIRE_NONE, BOT_ACTION_DESIRE_NONE = 0, 0
ITEM_SLOT_TYPE_MAIN = 0
DAMAGE_TYPE_PHYSICAL = 1
GAMEMODE_1V1MID, GAMEMODE_MO = 11, 12
function GetGameMode() return 22 end
function GetOpposingTeam() return 3 end
function GetTeam() return 2 end
-- PositionThink adds RandomVector(50) to the front location, so these two support +.
local VecMeta = { __add = function(a, b) return setmetatable({ x = a.x + b.x, y = a.y + b.y }, getmetatable(a)) end }
local function vec(x, y) return setmetatable({ x = x, y = y }, VecMeta) end
function RandomVector() return vec(0, 0) end
function GetLaneFrontAmount() return 0.5 end
function GetLaneFrontLocation() return vec(0, 0) end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
function GetUnitToUnitDistance(a, b) return dist(a:GetLocation(), b:GetLocation()) end

function LaningCreep(o)
	return {
		hp = o.hp, loc = o.loc or Vector(0, 0), alive = true,
		GetHealth = function(self) return self.hp end,
		GetMaxHealth = function() return 550 end,
		GetLocation = function(self) return self.loc end,
		IsAlive = function(self) return self.alive end,
	}
end

function LaningHero(o)
	local h = { pos = o.pos, loc = o.loc or Vector(0, 0), range = o.range or 150, pid = o.pid or 1, actions = {} }
	h.GetLocation = function(self) return self.loc end
	h.GetAttackRange = function(self) return self.range end
	h.GetExtrapolatedLocation = function(self) return self.toward or self.loc end
	h.GetPlayerID = function(self) return self.pid end
	h.GetAttackTarget = function(self) return self.target end
	h.IsAlive = function() return true end
	h.IsIllusion = function() return false end
	return h
end

-- opts: pos, owned (Lane owns laning), ours (Ours.LeaveCoreCreep), enemyCreeps, allyCreeps, allies (bot heroes nearby), dmg.
function LaningLoad(opts)
	DotaTime = function() return opts.t or 120 end
	GameTime = DotaTime
	local bot = LaningHero({ pos = opts.pos, range = opts.range or 150, loc = opts.loc })
	bot.GetUnitName = function() return "npc_dota_hero_x" end
	bot.IsInvulnerable = function() return false end
	bot.IsHero = function() return true end
	bot.IsAlive = function() return true end
	bot.IsIllusion = function() return false end
	bot.GetAttackDamage = function() return opts.dmg or 50 end
	bot.GetNearbyLaneCreeps = function(_, _, enemy) return enemy and (opts.enemyCreeps or {}) or (opts.allyCreeps or {}) end
	bot.GetNearbyHeroes = function(_, _, enemy) return enemy and {} or (opts.allies or {}) end
	bot.GetAssignedLane = function() return 1 end
	bot.GetItemSlotType = function() return -1 end
	bot.FindItemSlot = function() return -1 end
	bot.GetLevel = function() return 2 end
	bot.WasRecentlyDamagedByAnyHero = function() return false end
	bot.GetLastAttackTime = function() return -90 end
	local function record(name) return function(_, ...) table.insert(bot.actions, { name = name, args = { ... } }) end end
	bot.Action_AttackUnit = record("AttackUnit")
	bot.Action_MoveToUnit = record("MoveToUnit")
	bot.Action_MoveToLocation = record("MoveToLocation")
	bot.SetTarget = function() end
	function GetBot() return bot end

	-- The real Etiquette predicate (slice 3), on Ours.LeaveCoreCreep = opts.ours, positions from the world, over the bot
	-- and its allied heroes as the team.
	local team = { bot }
	for _, a in ipairs(opts.allies or {}) do table.insert(team, a) end
	function GetTeamMember(i) return team[i] end
	package.loaded['bots/FunLib/humaniser/lane_config'] = { PositionOf = function(u) return u.pos end }
	package.loaded['bots/FunLib/humaniser/ours'] = { On = function() return opts.ours == true end }
	package.loaded['bots/FunLib/humaniser/etiquette'] = nil
	-- A fixture's negative control runs an older bots/ without the module; the old mode file never reads it then.
	local okEtiquette, Etiquette = pcall(require, 'bots/FunLib/humaniser/etiquette')
	if not okEtiquette then Etiquette = { Applies = function() return false end } end

	local attempts = {}
	local humaniser = {
		AllyLastHit = {
			OwnsLaning = function() return opts.etiquette == true end,
			MayLastHit = function() return true, "free:test" end,
			Settings = function() return {} end,
			CoreCanReach = function(core, c) return dist(core:GetLocation(), c:GetLocation()) <= core:GetAttackRange() + 150 end,
		},
		Lane = {
			OwnsLaning = function() return opts.owned == true end,
			CampJobActive = function() return false end,
			PreThink = function(_, _, _, _, lastHit) bot.preThinkLastHit = lastHit return false end,
			Think = function() return false end,
			MayDeny = function() return true end,
			PickDeny = function() return nil end,
			SupersedesHarass = function() return false end,
			HarassThink = function() return false end,
			AdjustPosition = function(_, loc) return loc end,
		},
		Trainer = { IsSelfTestBot = function() return false end },
		LastHitSkill = {
			NoteLaningOwner = function() end,
			IsActiveFor = function() return false end,
			WillKill = function(_, c, dmg) return c:GetHealth() <= dmg end,
			Choose = function(_, list) return list[1] end,
			NoteAttempt = function(_, c) table.insert(attempts, c) end,
		},
		Etiquette = Etiquette,
		Intent = { Resolve = function(_, _, d) return d end },
		States = { MayOwn = function() return false end, SetLaneSpot = function() end, Step = function() return false end, BodyLastHits = function() return false end, BodyBusy = function() return false end },
	}
	local J = setmetatable({
		GetPosition = function(u) return u.pos end,
		IsPosxHuman = function() return opts.humanPos5 == true end,
		IsInLaningPhase = function() return true end,
		IsValid = function(u) return u ~= nil and (u.IsAlive == nil or u:IsAlive()) end,
		IsValidHero = function(u) return u ~= nil end,
		CanBeAttacked = function() return true end,
		GetAttackProDelayTime = function() return 0 end,
		IsCore = function(u) return u.pos ~= nil and u.pos <= 3 end,
		GetNearbyHeroes = function(u, r, enemy) return u:GetNearbyHeroes(r, enemy) end,
		IsThereNonSelfCoreNearby = function(r)
			for _, a in pairs(opts.allies or {}) do
				if a.pos <= 3 and dist(a:GetLocation(), bot:GetLocation()) <= r then return true end
			end
			return false
		end,
		GetEnemiesAroundAncient = function() return 0 end,
		GetHP = function(u) return u.GetMaxHealth ~= nil and u:GetHealth() / u:GetMaxHealth() or 1 end,
		Utils = {
			NumHumanBotPlayersInTeam = function() return 0, 5 end,
			IsTeamPushingSecondTierOrHighGround = function() return false end,
			GetLastSeenEnemyIdsNearLocation = function() return {} end,
		},
		Humaniser = humaniser,
	}, { __index = function() return function() return false end end })
	package.loaded["bots/FunLib/utils"] = { BuggyHeroesDueToValveTooLazy = {} }
	package.loaded["bots/FunLib/jmz_func"] = J
	package.loaded["bots/FunLib/version"] = {}
	package.loaded["bots/FunLib/localization"] = {}
	Think = nil
	dofile((BOTS_ROOT or (HARNESS_DIR .. "/../..")) .. "/bots/mode_laning_generic.lua")
	PickOneAnnouncer, AnnounceMessages = function() end, function() end
	return bot, attempts
end

