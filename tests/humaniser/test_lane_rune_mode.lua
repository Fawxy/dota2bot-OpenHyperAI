-- mode_rune_generic GetDesire under a lane rune contest, run against a stubbed bot world (no humaniser load).
dofile(HARNESS_DIR .. "/dota_stubs.lua")

RUNE_BOUNTY_1, RUNE_BOUNTY_2, RUNE_POWERUP_1, RUNE_POWERUP_2 = 1, 2, 3, 4
RUNE_STATUS_UNKNOWN, RUNE_STATUS_AVAILABLE, RUNE_STATUS_MISSING = 0, 1, 2
RUNE_WATER, RUNE_HASTE = 10, 11
BOT_MODE_DESIRE_NONE, BOT_MODE_DESIRE_MODERATE, BOT_MODE_DESIRE_HIGH, BOT_MODE_DESIRE_ABSOLUTE = 0, 0.5, 0.75, 1
BOT_ACTION_TYPE_IDLE, BOT_ACTION_TYPE_MOVE_TO = 0, 1
TEAM_RADIANT, TEAM_DIRE, BOT_MODE_NONE = 2, 3, 0
function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function RemapValClamped(v, a, b, c, d) local t = Clamp((v - a) / (b - a), 0, 1) return c + (d - c) * t end
function GetOpposingTeam() return 3 end
function GetAncient(team) return { GetLocation = function() return Vector(team == 2 and -7000 or 7000, 0) end } end
function GetUnitToLocationDistance(u, loc)
	local l = u:GetLocation()
	return math.sqrt((l.x - loc.x) ^ 2 + (l.y - loc.y) ^ 2)
end

local RUNE_AT = { [1] = Vector(-4000, 4000), [2] = Vector(4000, -4000), [3] = Vector(-1000, 1000), [4] = Vector(1500, -1500) }
function GetRuneSpawnLocation(r) return RUNE_AT[r] end
RUNE_STATUS = {}
function GetRuneStatus(r) return RUNE_STATUS[r] or RUNE_STATUS_MISSING end
function GetRuneType(r) return RUNE_HASTE end

local function hero(o)
	return setmetatable(o, { __index = {
		GetLocation = function(self) return self.loc end,
		IsBot = function(self) return self.isBot ~= false end,
		IsFacingLocation = function() return true end,
		FindItemSlot = function() return -1 end,
	} })
end

local function load(contest, opts)
	opts = opts or {}
	T = 1000
	ALLIES, ENEMIES = opts.allies or {}, opts.enemies or {}
	-- 990 from the power rune: inside the 1,200 human-defer range.
	local bot = hero({ loc = Vector(-300, 300) })
	bot.GetNearbyHeroes = function(_, _, enemy) return enemy and ENEMIES or ALLIES end
	bot.IsInvulnerable = function() return false end
	bot.DistanceFromFountain = function() return 5000 end
	bot.GetActiveMode = function() return 0 end
	bot.GetActiveModeDesire = function() return 0 end
	bot.GetAssignedLane = function() return 2 end
	bot.WasRecentlyDamagedByAnyHero = function() return false end
	bot.GetLevel = function() return 30 end
	bot.GetCurrentActionType = function() return BOT_ACTION_TYPE_MOVE_TO end
	bot.HasModifier = function() return false end
	-- Stale state from before the contest: the rune and its status as last seen.
	bot.rune = { normal = { location = RUNE_BOUNTY_1, distance = 9999, status = RUNE_STATUS_MISSING }, wisdom = {} }
	function GetBot() return bot end
	local J = setmetatable({
		GetHP = function() return 1 end,
		GetMP = function() return 1 end,
		GetPosition = function() return 2 end,
		IsCore = function() return true end,
		IsEarlyGame = function() return true end,
		IsValidHero = function(u) return u ~= nil end,
		GetDistanceFromEnemyFountain = function() return 9000 end,
		Utils = { IsTeamPushingSecondTierOrHighGround = function() return false end, CountEnemyHeroesNear = function() return 0 end },
		Humaniser = { Lane = { RuneContestDesire = function() return contest end }, Intent = { Resolve = function(_, _, d) return d end } },
	}, { __index = function() return function() return false end end })
	package.loaded["bots/FunLib/jmz_func"] = J
	package.loaded["bots/Customize/general"] = { Enable = false }
	dofile(HARNESS_DIR .. "/../../bots/mode_rune_generic.lua")
	return bot
end

do
	RUNE_STATUS = { [RUNE_POWERUP_1] = RUNE_STATUS_AVAILABLE }
	local bot = load(0)
	local base = GetDesire()
	check("no contest: the normal power-rune desire", base > 0 and base < 0.6, base)

	bot = load(0.6)
	local d = GetDesire()
	check("contest: desire at least the contest's", near(d, math.max(0.6, base)), d)
	check("contest: rune location refreshed", bot.rune.normal.location == RUNE_POWERUP_1, bot.rune.normal.location)
	check("contest: rune distance refreshed", near(bot.rune.normal.distance, math.sqrt(2) * 700), bot.rune.normal.distance)
	check("contest: rune status refreshed", bot.rune.normal.status == RUNE_STATUS_AVAILABLE, bot.rune.normal.status)

	load(0.95)
	check("a contest above the normal desire wins", near(GetDesire(), 0.95))

	-- One ally nearby, so the outnumbered exit does not decide this.
	load(0.6, { enemies = { hero({ loc = Vector(-900, 900) }) }, allies = { hero({ loc = Vector(-300, 0) }) } })
	check("enemy about to take the rune: no contest", GetDesire() == 0)

	local human = hero({ loc = Vector(-600, 600), isBot = false })
	load(0.6, { allies = { human } })
	check("human ally near the rune: deferred despite the contest", GetDesire() == 0)
end

finish()
