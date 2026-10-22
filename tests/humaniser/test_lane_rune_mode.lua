-- mode_rune_generic GetDesire run against a stubbed bot world. Most blocks stub the humaniser; the
-- mid-rune blocks load the real one (Transitions + Intent) so a claim reaches Resolve as in game.
RUNE_BOUNTY_1, RUNE_BOUNTY_2, RUNE_POWERUP_1, RUNE_POWERUP_2 = 1, 2, 3, 4
BOT_MODE_RUNE, BOT_MODE_LANING = 7, 1
dofile(HARNESS_DIR .. "/lane_world.lua")

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

local DEFAULT_RUNE_AT = { [1] = Vector(-4000, 4000), [2] = Vector(4000, -4000), [3] = Vector(-1000, 1000), [4] = Vector(1500, -1500) }
local RUNE_AT = DEFAULT_RUNE_AT
function GetRuneSpawnLocation(r) return RUNE_AT[r] end
RUNE_STATUS = {}
function GetRuneStatus(r) return RUNE_STATUS[r] or RUNE_STATUS_MISSING end
function GetRuneType(r) return RUNE_HASTE end

local function hero(o)
	return setmetatable(o, { __index = {
		GetLocation = function(self) return self.loc end,
		IsBot = function(self) return self.isBot ~= false end,
		IsFacingLocation = function() return true end,
		FindItemSlot = function(self, name) return (name == "item_bottle" and self.bottle) and 0 or -1 end,
		GetLastHits = function() return 0 end,
	} })
end

-- opts.H: a real humaniser (LaneFresh) used for J.Humaniser instead of the stub.
local function load(contest, opts)
	opts = opts or {}
	T = opts.T or 1000
	RUNE_AT = opts.runeAt or DEFAULT_RUNE_AT
	ALLIES, ENEMIES = opts.allies or {}, opts.enemies or {}
	-- Default: 990 from the power rune, inside the 1,200 human-defer range.
	local bot = hero({ loc = opts.loc or Vector(-300, 300), bottle = opts.bottle, pos = opts.pos or 2, pid = 2 })
	bot.GetNearbyHeroes = function(_, _, enemy) return enemy and ENEMIES or ALLIES end
	bot.IsInvulnerable = function() return false end
	bot.DistanceFromFountain = function() return 5000 end
	bot.GetActiveMode = function() return opts.activeMode or 0 end
	bot.GetActiveModeDesire = function() return 0 end
	bot.GetAssignedLane = function() return 2 end
	bot.WasRecentlyDamagedByAnyHero = function() return false end
	bot.GetLevel = function() return 30 end
	bot.GetCurrentActionType = function() return opts.idle and BOT_ACTION_TYPE_IDLE or BOT_ACTION_TYPE_MOVE_TO end
	bot.HasModifier = function() return false end
	bot.GetPlayerID = function() return 2 end
	bot.GetUnitName = function() return "npc_dota_hero_x" end
	bot.GetTeam = function() return 2 end
	bot.IsAlive = function() return true end
	bot.IsHero = function() return true end
	bot.IsIllusion = function() return false end
	-- Stale state from before: the rune and its status as last seen.
	bot.rune = { normal = { location = RUNE_BOUNTY_1, distance = 9999, status = RUNE_STATUS_MISSING }, wisdom = {} }
	function GetBot() return bot end
	local humaniser = opts.H or {
		Lane = { RuneContestDesire = function() return contest end },
		Intent = { Resolve = function(_, _, d) return d end },
		Transitions = {
			MidRunesOn = function() return false end,
			MidRuneFocus = function() return false, false end,
			MidRuneYield = function() end,
			MidRuneSkip = function() end,
			RuneTarget = function() return nil end,
			MidRuneDesire = function() return 0 end,
			RotationYield = function() end,
			HoldsRune = function() return false end,
		},
	}
	local J = setmetatable({
		GetHP = function() return 1 end,
		GetMP = function() return 1 end,
		GetPosition = function(u) return u.pos end,
		IsCore = function() return true end,
		IsEarlyGame = function() return true end,
		IsInLaningPhase = function() return T < 600 end,
		IsValidHero = function(u) return u ~= nil end,
		GetDistanceFromEnemyFountain = function() return 9000 end,
		GetNextPowerRuneSpawnTime = function() if T < 120 then return 120 end return (math.floor(T / 120) + 1) * 120 end,
		Utils = { IsTeamPushingSecondTierOrHighGround = function() return false end, CountEnemyHeroesNear = function() return 0 end },
		Humaniser = humaniser,
	}, { __index = function() return function() return false end end })
	for k, v in pairs(opts.J or {}) do J[k] = v end
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

-- Mid power-rune worlds (task 12, 3b). The mid stands at the origin; the other spots are far away.
local function midWorld(bounty1, power1)
	return { [1] = bounty1, [2] = Vector(6000, -6000), [3] = power1, [4] = Vector(-6000, -6000) }
end
local NEAR_BOUNTY = midWorld(Vector(0, 900), Vector(1400, 0))
local FAR_POWER = midWorld(Vector(-6000, 6000), Vector(1800, 0))

local function realHumaniser(transitions)
	local H = LaneFresh({ Enable = true }, { transitions = transitions or { Enable = true } })
	H.Lane.SetHelpers({ GetPosition = function(u) return u.pos end, IsInLaningPhase = function() return T < 600 end })
	return H
end

-- One frame as in game: the humaniser Tick (ItemUsageThink) and then the mode's GetDesire.
local function frame(H, bot)
	H.Transitions.Tick(bot)
	return GetDesire()
end

do
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 357, loc = Vector(0, 0), runeAt = NEAR_BOUNTY })
	local d = frame(H, bot)
	check("mid picks the power rune over a nearer bounty at 6:00", bot.rune.normal.location == RUNE_POWERUP_1, bot.rune.normal.location)
	check("mid picks the power rune over a nearer bounty at 6:00: desire above 0", d > 0, d)
end

do
	RUNE_STATUS = { [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 357, loc = Vector(0, 0), runeAt = FAR_POWER })
	local d = frame(H, bot)
	check("bottle-less mid wants the rune over laning", d >= 0.6, d)
end

do
	-- 15 s before the spawn: the unspawned power rune still reads MISSING at second 45.
	RUNE_STATUS = { [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 345, loc = Vector(0, 0), runeAt = FAR_POWER })
	local d = frame(H, bot)
	check("15 s before the spawn the mid targets the power spot", bot.rune.normal.location == RUNE_POWERUP_1, bot.rune.normal.location)
	check("15 s before the spawn the mid wants the rune", d >= 0.6, d)
end

do
	-- Waiting at the spot for the spawn, the bot has nothing queued.
	RUNE_STATUS = { [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 355, loc = Vector(1700, 0), runeAt = FAR_POWER, idle = true })
	local d = frame(H, bot)
	check("idle mid waiting at the spot keeps the rune", d >= 0.6 and bot.rune.normal.location == RUNE_POWERUP_1, d)
end

do
	-- Upstream drops all rune desire within 80 of RUNE_POWERUP_2 between 2:00 and 6:00.
	RUNE_STATUS = { [RUNE_POWERUP_2] = RUNE_STATUS_MISSING }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 355, loc = Vector(-5950, -6000), runeAt = FAR_POWER })
	local d = frame(H, bot)
	check("mid waiting on the second power spot before 6:00 keeps the rune", d >= 0.6 and bot.rune.normal.location == RUNE_POWERUP_2, d)
end

-- Step 4: with MidRunes off (or the transitions kill switch off) every world above scores as upstream did.
for _, cfg in ipairs({ { Enable = true, MidRunes = false }, { Enable = false } }) do
	local tag = cfg.Enable and "MidRunes flag off keeps upstream" or "transitions off keeps upstream"
	local H = realHumaniser(cfg)
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local bot = load(0, { H = H, T = 357, loc = Vector(0, 0), runeAt = NEAR_BOUNTY })
	local d = frame(H, bot)
	check(tag .. ": the nearer bounty is still the target", bot.rune.normal.location == RUNE_BOUNTY_1 and d == 0, d)
	RUNE_STATUS = { [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	H = realHumaniser(cfg)
	bot = load(0, { H = H, T = 357, loc = Vector(0, 0), runeAt = FAR_POWER })
	d = frame(H, bot)
	check(tag .. ": bottle-less desire unlifted", near(d, 0.25), d)
	H = realHumaniser(cfg)
	bot = load(0, { H = H, T = 345, loc = Vector(0, 0), runeAt = FAR_POWER })
	d = frame(H, bot)
	check(tag .. ": unspawned power rune skipped before :52", bot.rune.normal.location == -1 and d == 0, d)
	H = realHumaniser(cfg)
	bot = load(0, { H = H, T = 355, loc = Vector(1700, 0), runeAt = FAR_POWER, idle = true })
	check(tag .. ": idle gate kept", frame(H, bot) == 0)
	RUNE_STATUS = { [RUNE_POWERUP_2] = RUNE_STATUS_MISSING }
	H = realHumaniser(cfg)
	bot = load(0, { H = H, T = 355, loc = Vector(-5950, -6000), runeAt = FAR_POWER })
	check(tag .. ": power-2 spot gate kept", frame(H, bot) == 0)
end

do
	-- The floor never overrides the mode's own safety gates.
	RUNE_STATUS = { [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 355, loc = Vector(0, 0), runeAt = FAR_POWER, enemies = { hero({ loc = Vector(300, 0) }) } })
	check("outnumbered mid: no floor", frame(H, bot) == 0)
	H = realHumaniser()
	bot = load(0, { H = H, T = 355, loc = Vector(900, 0), runeAt = FAR_POWER, allies = { hero({ loc = Vector(1500, 0), isBot = false }) } })
	check("human ally at the rune: no floor", frame(H, bot) == 0)
end

do
	RUNE_STATUS = { [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 357, loc = Vector(-2000, 0), runeAt = FAR_POWER })
	check("mid beyond 3,500 of the spot: no floor", frame(H, bot) < 0.6)
	H = realHumaniser()
	bot = load(0, { H = H, T = 357, loc = Vector(0, 0), runeAt = FAR_POWER, pos = 1 })
	check("pos 1: no floor", frame(H, bot) < 0.6)
	H = realHumaniser()
	bot = load(0, { H = H, T = 330, loc = Vector(0, 0), runeAt = FAR_POWER })
	check("30 s before the spawn: no floor yet", frame(H, bot) < 0.6)
end

do
	-- After the spawn: unseen (UNKNOWN) keeps pulling, until the bot sees the spot empty or taken.
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_UNKNOWN }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 362, loc = Vector(0, 0), runeAt = NEAR_BOUNTY })
	local d = frame(H, bot)
	check("after the spawn, unseen: mid still heads for the power rune", d >= 0.6 and bot.rune.normal.location == RUNE_POWERUP_1, d)
	-- Both spots now known empty (the far one defaults to MISSING).
	RUNE_STATUS[RUNE_POWERUP_1] = RUNE_STATUS_MISSING
	T = 365
	d = frame(H, bot)
	check("both spots seen empty: no floor", d < 0.6, d)
	RUNE_STATUS[RUNE_POWERUP_1] = RUNE_STATUS_UNKNOWN
	T = 370
	d = frame(H, bot)
	check("seen taken, then out of sight: no floor again", d < 0.6 and bot.rune.normal.location == RUNE_BOUNTY_1, d)
end

do
	local lines = {}
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local H = LaneFresh({ Enable = true }, { transitions = { Enable = true, MidRunes = false }, telemetry = { Enable = true } })
	H.Lane.SetHelpers({ GetPosition = function(u) return u.pos end, IsInLaningPhase = function() return T < 600 end })
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	local bot = load(0, { H = H, T = 357, loc = Vector(0, 0), runeAt = NEAR_BOUNTY })
	frame(H, bot)
	T = 358
	frame(H, bot)
	local skips = {}
	for _, l in ipairs(lines) do if l:find("ev=rune_skip", 1, true) then table.insert(skips, l) end end
	check("rune_skip: once per spawn", #skips == 1, #skips)
	local l = skips[1] or ""
	check("rune_skip: names the target, gate and raw desire", l:find("pid=2", 1, true) and l:find("target=1", 1, true)
		and l:find("gate=bounty", 1, true) and l:find("raw=0", 1, true) and l:find("spawn=360", 1, true), l)
	local before = #lines
	T = 400
	frame(H, bot)
	local later = 0
	for i = before + 1, #lines do if lines[i]:find("ev=rune_skip", 1, true) then later = later + 1 end end
	check("rune_skip: none away from a spawn", later == 0, later)
end

-- Only one of the two power spots gets the rune: the spawn is judged as a whole.
local BOTH_POWER = { [1] = Vector(0, 900), [2] = Vector(6000, -6000), [3] = Vector(1400, 0), [4] = Vector(-2500, 0) }

do
	-- The mid waits at its nearer spot; the rune appears on the other side of the river.
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_MISSING, [RUNE_POWERUP_2] = RUNE_STATUS_AVAILABLE }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 361, loc = Vector(0, 0), runeAt = BOTH_POWER })
	local d = frame(H, bot)
	check("rune at the other spot: mid goes there", d >= 0.6 and bot.rune.normal.location == RUNE_POWERUP_2, d)
end

do
	-- Seen available at one spot, then taken: done, even with the other spot unseen.
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_AVAILABLE, [RUNE_POWERUP_2] = RUNE_STATUS_UNKNOWN }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 361, loc = Vector(0, 0), runeAt = BOTH_POWER })
	frame(H, bot)
	RUNE_STATUS[RUNE_POWERUP_1] = RUNE_STATUS_MISSING
	T = 362
	local d = frame(H, bot)
	check("seen available then taken: no floor", d < 0.6, d)
end

do
	-- At the spawn instant the engine can still read MISSING at both spots; the rune shows a frame later.
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_MISSING, [RUNE_POWERUP_2] = RUNE_STATUS_MISSING }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 360.1, loc = Vector(0, 0), runeAt = BOTH_POWER })
	frame(H, bot)
	RUNE_STATUS[RUNE_POWERUP_1] = RUNE_STATUS_AVAILABLE
	T = 360.7
	local d = frame(H, bot)
	check("one MISSING read at the spawn instant, then AVAILABLE: the spawn is still pending", d >= 0.6 and bot.rune.normal.location == RUNE_POWERUP_1, d)
	local focus = H.Transitions.MidRuneFocus(bot)
	check("... and the mid keeps its focus", focus == true)

	-- Both spots read MISSING after the first second (a stale read), then the rune shows: AVAILABLE clears the empty mark.
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_MISSING, [RUNE_POWERUP_2] = RUNE_STATUS_MISSING }
	H = realHumaniser()
	bot = load(0, { H = H, T = 361.5, loc = Vector(0, 0), runeAt = BOTH_POWER })
	check("precondition: both spots seen empty, no floor", frame(H, bot) < 0.6)
	RUNE_STATUS[RUNE_POWERUP_1] = RUNE_STATUS_AVAILABLE
	T = 362.1
	d = frame(H, bot)
	check("seen empty, then AVAILABLE: the mid heads for it", d >= 0.6 and bot.rune.normal.location == RUNE_POWERUP_1, d)
end

do
	-- Nearer spot seen empty, the other unseen: the mid checks the other spot inside the check window.
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_MISSING, [RUNE_POWERUP_2] = RUNE_STATUS_UNKNOWN }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 362, loc = Vector(0, 0), runeAt = BOTH_POWER })
	local d = frame(H, bot)
	check("nearer spot empty, other unseen: mid checks the other", d >= 0.6 and bot.rune.normal.location == RUNE_POWERUP_2, d)
end

do
	-- A minute after the spawn an unseen spot is stale: no pull.
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_2] = RUNE_STATUS_UNKNOWN }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 420, loc = Vector(0, 0), runeAt = BOTH_POWER })
	local d = frame(H, bot)
	check("unseen spots a minute after the spawn: no floor", d < 0.6, d)
end

-- Support rotations (task 12, Task 4). The decision is tested in test_transitions_rotation.lua; here
-- Rotation.Active is stubbed so the rune mode sees a pos 4 rotating to the top power spot (y > 0).
local ROT_WORLD = { [1] = Vector(0, 900), [2] = Vector(6000, -6000), [3] = Vector(1800, 500), [4] = Vector(-6000, -6000) }
local function rotatingHumaniser(transitions)
	local H = realHumaniser(transitions)
	H.Transitions.Rotation.Active = function()
		return { spawn = 360, go = true, side = "top", spot = ROT_WORLD[3], leaveAt = 340, reason = "ok" }
	end
	return H
end

do
	RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local H = realHumaniser()
	local bot = load(0, { H = H, T = 355, loc = Vector(0, 0), runeAt = ROT_WORLD, pos = 4 })
	local d = frame(H, bot)
	check("support not rotating: no rotation floor (control)", d < 0.7 and bot.rune.normal.location ~= RUNE_POWERUP_1, d)

	H = rotatingHumaniser()
	bot = load(0, { H = H, T = 355, loc = Vector(0, 0), runeAt = ROT_WORLD, pos = 4 })
	d = frame(H, bot)
	check("rotating support heads for its power spot over a nearer bounty", bot.rune.normal.location == RUNE_POWERUP_1, bot.rune.normal.location)
	check("rotating support: the rotation floor lifts the rune mode", d >= 0.7, d)

	H = rotatingHumaniser()
	bot = load(0, { H = H, T = 355, loc = Vector(1750, 500), runeAt = ROT_WORLD, pos = 4, idle = true })
	d = frame(H, bot)
	check("rotating support waiting idle at the spot keeps the floor", d >= 0.7, d)
	check("rotating support waiting at the spot holds", H.Intent.HeldBy(bot) == "transitions:rotate", H.Intent.HeldBy(bot))

	H = rotatingHumaniser()
	bot = load(0, { H = H, T = 355, loc = Vector(0, 0), runeAt = ROT_WORLD, pos = 4, enemies = { hero({ loc = Vector(300, 0) }) } })
	check("outnumbered rotating support: no floor", frame(H, bot) == 0)
	H = rotatingHumaniser()
	bot = load(0, { H = H, T = 355, loc = Vector(900, 0), runeAt = ROT_WORLD, pos = 4, allies = { hero({ loc = Vector(1500, 500), isBot = false }) } })
	check("human ally at the rune: no rotation floor", frame(H, bot) == 0)
end

do
	-- The rotating support positions and contests, but a spawned rune with our core beside the spot is the core's:
	-- the forced target yields to the normal pick, whose closest-ally and core gates then apply.
	local function J()
		return {
			IsCore = function(u) return (u.pos or 1) <= 3 end,
			IsThereCoreNearby = function(r)
				for _, m in ipairs(UNITS[2]) do
					if m.pos <= 3 and GetUnitToLocationDistance(GetBot(), m.loc) <= r then return true end
				end
				return false
			end,
		}
	end
	local function run(midLoc, status, t, supLoc)
		RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = status }
		local H = rotatingHumaniser()
		local mid = MakeUnit({ pid = 3, team = 2, bot = true, loc = midLoc })
		mid.pos = 2
		local bot = load(0, { H = H, T = t or 361, loc = supLoc or Vector(1750, 500), runeAt = ROT_WORLD, pos = 4, J = J() })
		local d = frame(H, bot)
		return bot.rune.normal.location, d
	end
	local loc, d = run(Vector(1800, -400), RUNE_STATUS_AVAILABLE)
	check("rune up, our mid 900 from the spot: the rotating support does not take it", loc ~= RUNE_POWERUP_1, loc)
	check("... and the rotation floor does not lift its rune mode", d < 0.7, d)
	check("contrast: rune up, no core near the spot: the support keeps its forced target",
		run(Vector(-6000, 0), RUNE_STATUS_AVAILABLE) == RUNE_POWERUP_1)
	check("contrast: before the spawn, mid near: the support still heads for the spot",
		run(Vector(1800, -400), RUNE_STATUS_MISSING, 355) == RUNE_POWERUP_1)
	check("mid 1100 from the spot on the far side, 1350 from the support: still the mid's rune",
		run(Vector(2900, 500), RUNE_STATUS_AVAILABLE, nil, Vector(1550, 500)) ~= RUNE_POWERUP_1)
end

do
	-- The mid's contest desire (MidRunes off, so the 3b floor does not mask it).
	RUNE_STATUS = { [RUNE_POWERUP_1] = RUNE_STATUS_MISSING }
	local H = realHumaniser({ Enable = true, MidRunes = false })
	local bot = load(0, { H = H, T = 357, loc = Vector(0, 0), runeAt = FAR_POWER })
	check("mid alone: the bottle-less desire (control)", near(frame(H, bot), 0.25))
	H = realHumaniser({ Enable = true, MidRunes = false })
	H.Transitions.Rotation.MidRuneDesire = function() return 0.55 end
	bot = load(0, { H = H, T = 357, loc = Vector(0, 0), runeAt = FAR_POWER })
	check("mid with a rotating support near contests the rune", near(frame(H, bot), 0.55))
end


do
	-- A rotating support on its spawned rune (top spot, 1800,500): what Think does with it.
	local function think(midLoc, t)
		RUNE_STATUS = { [RUNE_BOUNTY_1] = RUNE_STATUS_UNKNOWN, [RUNE_POWERUP_1] = RUNE_STATUS_AVAILABLE }
		local H = rotatingHumaniser()
		local mid = MakeUnit({ pid = 3, team = 2, bot = true, loc = midLoc })
		mid.pos = 2
		local bot = load(0, { H = H, T = t, loc = Vector(1800, 520), runeAt = ROT_WORLD, pos = 4 })
		local did = {}
		bot.Action_PickUpRune = function() table.insert(did, "pickup") end
		bot.Action_ClearActions = function() table.insert(did, "stand") end
		bot.Action_MoveToLocation = function() table.insert(did, "move") end
		bot.Action_AttackUnit = function() table.insert(did, "attack") end
		bot.GetAttackRange = function() return 150 end
		bot.GetNearbyCreeps = function() return {} end
		local d = frame(H, bot)
		Think()
		return did[1], d
	end
	local act, d = think(Vector(-600, 0), 361)
	check("our mid 2,450 from the rune: the support stands on it without picking it up", act == "stand", act)
	check("... and stays in the rune mode", d >= 0.7, d)
	check("our mid not coming 4 s after the spawn: the support picks it up", think(Vector(-6000, 0), 364) == "pickup", think(Vector(-6000, 0), 364))
end

finish()
