-- mode_laning_generic GetDesire and Think run against a stubbed bot world and a stubbed humaniser.
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

local function creep(o)
	return {
		hp = o.hp, loc = o.loc or Vector(0, 0), alive = true,
		GetHealth = function(self) return self.hp end,
		GetMaxHealth = function() return 550 end,
		GetLocation = function(self) return self.loc end,
		IsAlive = function(self) return self.alive end,
	}
end

local function hero(o)
	local h = { pos = o.pos, loc = o.loc or Vector(0, 0), range = o.range or 150, pid = o.pid or 1, actions = {} }
	h.GetLocation = function(self) return self.loc end
	h.GetAttackRange = function(self) return self.range end
	h.GetExtrapolatedLocation = function(self) return self.toward or self.loc end
	h.GetPlayerID = function(self) return self.pid end
	return h
end

-- opts: pos, owned (Lane owns laning), enemyCreeps, allyCreeps, allies (bot heroes nearby), dmg.
local function load(opts)
	DotaTime = function() return opts.t or 120 end
	GameTime = DotaTime
	local bot = hero({ pos = opts.pos, range = opts.range or 150, loc = opts.loc })
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
		Intent = { Resolve = function(_, _, d) return d end },
		States = { MayOwn = function() return false end, SetLaneSpot = function() end, Step = function() return false end, BodyLastHits = function() return false end, SetLaneAssist = function() end },
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
	dofile(HARNESS_DIR .. "/../../bots/mode_laning_generic.lua")
	PickOneAnnouncer, AnnounceMessages = function() end, function() end
	return bot, attempts
end

local function last(bot) return bot.actions[#bot.actions] end

do
	local c = creep({ hp = 40, loc = Vector(100, 0) })
	load({ pos = 3, owned = true, enemyCreeps = { c } })
	check("owned laning: a pos 3 bids 0.9 with a killable creep", near(GetDesire(), 0.9), GetDesire())
	load({ pos = 3, owned = false, enemyCreeps = { c } })
	check("unowned laning: a pos 3 keeps upstream's desire", not near(GetDesire(), 0.9), GetDesire())
	load({ pos = 3, owned = true, enemyCreeps = { creep({ hp = 400 }) } })
	check("owned laning: nothing killable, no 0.9", not near(GetDesire(), 0.9), GetDesire())
end

do
	-- 60 HP against 50 damage: within 1.7x, so a move-to creep; it is in range (100 < 150 * 0.8).
	local enemyCreep = creep({ hp = 60, loc = Vector(100, 0) })
	local allyCreep = creep({ hp = 40, loc = Vector(-100, 0) })
	allyCreep.GetHealth = function() return 40 end
	local bot, attempts = load({ pos = 1, owned = true, enemyCreeps = { enemyCreep }, allyCreeps = { allyCreep } })
	GetDesire()
	Think()
	local a = last(bot)
	check("nearly killable in range: the deny goes through instead of an early swing", a ~= nil and a.name == "AttackUnit" and a.args[1] == allyCreep, a and a.name)
	local attempted = false
	for _, c in ipairs(attempts) do if c == enemyCreep then attempted = true end end
	check("no attempt is counted on the nearly-killable creep", not attempted, #attempts)
	enemyCreep.hp = 45
	GetDesire()
	Think()
	a = last(bot)
	check("killable on the next frame: it is attacked", a ~= nil and a.name == "AttackUnit" and a.args[1] == enemyCreep, a and a.name)
end

do
	local enemyCreep = creep({ hp = 60, loc = Vector(100, 0) })
	local bot = load({ pos = 1, owned = true, enemyCreeps = { enemyCreep } })
	GetDesire()
	Think()
	local a = last(bot)
	check("nearly killable in range, nothing to deny: the bot holds, no attack", a ~= nil and a.name == "MoveToLocation" and #bot.actions == 1, a and a.name)
end

do
	-- A bot support (pos 5) at x=0; a bot core 800 away at x=800 but within its range + 150 of a creep at x=700.
	local c = creep({ hp = 40, loc = Vector(100, 0) })
	local core = hero({ pos = 1, pid = 2, loc = Vector(800, 0), range = 600 })
	local bot = load({ pos = 5, owned = true, enemyCreeps = { c }, allies = { core } })
	GetDesire()
	Think()
	local hit = false
	for _, a in ipairs(bot.actions) do if a.name == "AttackUnit" and a.args[1] == c then hit = true end end
	check("support leaves a creep its core 800 away can reach", not hit)
	core.loc = Vector(1500, 0)
	bot.actions = {}
	GetDesire()
	Think()
	hit = false
	for _, a in ipairs(bot.actions) do if a.name == "AttackUnit" and a.args[1] == c then hit = true end end
	check("support takes a creep its core cannot reach", hit)
end

do
	-- Final review fix: the hold is capped. A creep nobody is hitting never turns killable; after HoldMax the bot swings.
	local enemyCreep = creep({ hp = 60, loc = Vector(100, 0) })
	local bot = load({ pos = 1, owned = true, enemyCreeps = { enemyCreep } })
	GetDesire()
	Think()
	check("hold: the first frame holds", last(bot).name == "MoveToLocation")
	DotaTime = function() return 121.6 end
	GameTime = DotaTime
	GetDesire()
	Think()
	local a = last(bot)
	check("hold: past HoldMax the bot swings at the creep", a.name == "AttackUnit" and a.args[1] == enemyCreep, a.name)
end

do
	-- Final review fix: with the humaniser off, upstream's own owned case (pos 1 with a human pos 5) keeps upstream's
	-- early swing and its 700-radius core check.
	local enemyCreep = creep({ hp = 60, loc = Vector(100, 0) })
	local bot = load({ pos = 1, owned = false, humanPos5 = true, enemyCreeps = { enemyCreep } })
	GetDesire()
	Think()
	local a = last(bot)
	check("humaniser off: upstream's early swing is kept", a ~= nil and a.name == "AttackUnit" and a.args[1] == enemyCreep, a and a.name)
end

do
	-- Final review fix: the last-hit state handed to PreThink is gated like LastHitThink and reads 'kill' only in range.
	local c = creep({ hp = 40, loc = Vector(100, 0) })
	local core = hero({ pos = 1, pid = 2, loc = Vector(200, 0), range = 600 })
	local bot = load({ pos = 5, owned = true, enemyCreeps = { c }, allies = { core } })
	GetDesire()
	Think()
	check("a support's core's creep is no last hit for PreThink", bot.preThinkLastHit == nil, tostring(bot.preThinkLastHit))
	local far = creep({ hp = 40, loc = Vector(700, 0) })
	bot = load({ pos = 1, owned = true, enemyCreeps = { far } })
	GetDesire()
	Think()
	check("a killable creep out of attack range reads as soon, not kill", bot.preThinkLastHit == "soon", tostring(bot.preThinkLastHit))
end

finish()
