-- Spec scenario 15: with the humaniser off, Lane.Enable off, or every Lane flag off, the lane hooks change nothing
-- and make no engine scans. Every check has a positive control (defaults on) run through the same worlds, so the
-- worlds demonstrably produce activity when a flag is on.
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetMostRecentPing() return self.ping or { time = 0, location = Vector(0, 0), normal_ping = true } end

local BOT_Y = LANE_Y[Lane.Bot]
local SMALL = Vector(-1600, -6200)

local ALL_FLAGS = { "Plan", "Block", "FullPull", "HalfPull", "StackPull", "AggroPull", "Freeze", "Shove", "Stack",
	"Harass", "Mid", "CounterPlay", "Telegraph", "CampBlock" }
local function flags(on, keep)
	local cfg = { Enable = true, OwnLaningThink = "all" }
	for _, f in ipairs(ALL_FLAGS) do cfg[f] = on end
	for _, f in ipairs(keep or {}) do cfg[f] = true end
	return cfg
end

local OFF = {
	{ name = "humaniser disabled", cfg = { Enable = true, OwnLaningThink = "all" }, humaniser = false },
	{ name = "Lane.Enable = false", cfg = { Enable = false, OwnLaningThink = "all" } },
	{ name = "every flag false", cfg = flags(false) },
	{ name = "only Telegraph on", cfg = flags(false, { "Telegraph" }) },
}
local ON = { name = "defaults (control)", cfg = { Enable = true, OwnLaningThink = "all" } }

local function fresh(entry, skill)
	return LaneFresh(entry.cfg, { enable = entry.humaniser ~= false, skill = skill or 0.9, debug = true })
end

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = Vector(o.x or 0, o.y or BOT_Y), hp = o.hp })
	u.lane, u.pos, u.dmg = o.lane or Lane.Bot, o.pos, o.dmg
	return u
end
local function scans() local n = 0 for _, c in pairs(GETUNITLIST_CALLS) do n = n + c end return n end
local function count(fn)
	local printed, old = {}, print
	print = function(...) table.insert(printed, table.concat({ ... }, " ")) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err) end
	return printed
end
local function laneLines(lines)
	local n = 0
	for _, l in ipairs(lines) do if l:find("[H:lane]", 1, true) then n = n + 1 end end
	return n
end

-- Pull window at 1:43 for the bot-lane support, who stands at the small camp's stand point; a human holds the top lane.
local function jobWorld(entry)
	local H = fresh(entry)
	T = 103
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = { { team = 2, type = "small", location = Vector(SMALL.x, SMALL.y, 0), min = Vector(SMALL.x - 150, SMALL.y - 150, 0),
		max = Vector(SMALL.x + 150, SMALL.y + 150, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	local C = H.Lane.Camps
	local data = C.ByIdx(1)
	local stand = data and C.BoxEdgePoint(C.SpawnerByIdx(1), data.pull.path[1], 150) or Vector(SMALL.x, SMALL.y)
	unit({ pid = 0, bot = false, lane = Lane.Top, y = 5000 })
	local core = unit({ pid = 1, pos = 1, x = 0 })
	local support = unit({ pid = 5, pos = 5, x = stand.x, y = stand.y })
	local enemy = unit({ pid = 6, team = 3, pos = 1, x = 300 })
	return H, core, support, enemy
end

-- Hooks that need a pull window, run in one world and then again in a second one just to tick for 10 s.
local function probeJobs(entry)
	local r = {}
	r.lines = count(function()
		local H, core, support, enemy = jobWorld(entry)
		r.active = H.Lane.Config.IsActive()
		r.ownsAlly = H.Lane.OwnsLaning(support)
		r.ownsEnemy = H.Lane.OwnsLaning(enemy)
		r.desire = H.Lane.CampJobDesire(support)
		r.think = H.Lane.CampJobThink(support)
		r.thinkCore = H.Lane.CampJobThink(core)
		r.runeDesire = H.Lane.RuneContestDesire(support)
		r.stacked = H.Lane.PreferStackedCamp(core, { { idx = 1 } })
		r.supersedes = H.Lane.SupersedesHarass(support)
		r.deny = H.Lane.PickDeny(support, {})
		r.jobScans = scans()
		r.jobActions = #ACTIONS

		H = jobWorld(entry)
		ACTIONS, GETUNITLIST_CALLS = {}, {}
		for _, bot in ipairs(UNITS[2]) do
			for t = 103, 113, 0.5 do T = t H.Lane.Tick(bot) end
		end
		r.tickScans, r.tickActions = scans(), #ACTIONS
	end)
	return r
end

-- Laning Think hooks as mode_laning_generic.lua calls them, in four worlds that each produce an action when the flags are on.
local function probeLaning(entry)
	local r = {}
	r.lines = count(function()
		-- 0:05 block
		local H = fresh(entry, 0.8)
		T = 5
		CURRENT_TEAM = 2
		LANE_FRONT[2][Lane.Bot] = 4000 / 14000
		local bot = unit({ pid = 1, pos = 1, x = -2800 })
		MakeCreep({ team = 2, x = -3000, y = BOT_Y })
		MakeCreep({ team = 2, x = -3100, y = BOT_Y })
		MakeCreep({ team = 3, x = 3000, y = BOT_Y })
		r.pre = H.Lane.PreThink(bot, {}, {}, {})
		r.preActions = #ACTIONS

		-- Shove before rotating? no: plan shove on a lone safe-lane bot, no enemy laner, wave at the default front
		H = fresh(entry, 0.8)
		T = 95
		CURRENT_TEAM = 2
		STRONGER = true
		unit({ pid = 0, bot = false, lane = Lane.Top, y = 5000 })
		bot = unit({ pid = 1, pos = 1, x = -200 })
		local creeps = {
			MakeCreep({ team = 3, x = 100, y = BOT_Y, hp = 300 }),
			MakeCreep({ team = 3, x = 2300, y = BOT_Y, hp = 100 }),
			MakeCreep({ team = 3, x = 200, y = BOT_Y, hp = 400 }),
		}
		ACTIONS = {}
		r.think = H.Lane.Think(bot, {}, creeps, {})
		r.thinkActions = #ACTIONS

		-- Freeze posture: our front far up the lane, the wave pushed to us
		H = fresh(entry, 0.8)
		T = 95
		CURRENT_TEAM = 2
		STRONGER = true
		LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.36, 0.64
		bot = unit({ pid = 1, pos = 1, x = -2000 })
		local hero = unit({ pid = 6, team = 3, pos = 3, x = -1700 })
		local enemyCreeps = { MakeCreep({ team = 3, x = -1800, y = BOT_Y }), MakeCreep({ team = 3, x = -1850, y = BOT_Y }) }
		local allies = { MakeCreep({ team = 2, x = -2050, y = BOT_Y }) }
		H.Lane.PreThink(bot, allies, enemyCreeps, { hero })
		H.Lane.Think(bot, allies, enemyCreeps, { hero })
		r.input = Vector(-1960, BOT_Y)
		r.adjusted = H.Lane.AdjustPosition(bot, r.input)

		-- Mid deny control: a deniable ranged creep before a deniable melee one
		H = fresh(entry, 0.9)
		T = 100
		CURRENT_TEAM = 2
		NEXT_RUNE = 240
		local mid = unit({ pid = 2, pos = 2, lane = Lane.Mid, x = 0, y = 0, dmg = 400 })
		unit({ pid = 7, team = 3, pos = 2, lane = Lane.Mid, x = 0, y = 0 })
		local melee = MakeCreep({ team = 2, x = 50, y = 0, hp = 20 })
		local ranged = MakeCreep({ team = 2, x = 60, y = 0, hp = 25, name = "npc_dota_creep_goodguys_ranged" })
		r.ranged, r.denied = ranged, H.Lane.PickDeny(mid, { melee, ranged })
	end)
	return r
end

local function humanTeam(entry)
	local H = fresh(entry)
	T = 100
	CURRENT_TEAM = 2
	unit({ pid = 0, bot = false, lane = Lane.Bot, y = -4000 })
	local bots = {
		unit({ pid = 1, pos = 1 }),
		unit({ pid = 2, pos = 5 }),
		unit({ pid = 3, lane = Lane.Top, pos = 3, y = 5000 }),
		unit({ pid = 4, lane = Lane.Mid, pos = 2, y = 0 }),
	}
	for _, b in ipairs(bots) do H.Tick(b) end
	return H, bots
end
local function say(pid, text)
	T = T + 0.5
	for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = pid, string = text, team_only = true }) end
end
local function orderTypes(H)
	local r = {}
	for _, o in ipairs(H.Orders.GetActive(2)) do table.insert(r, o.type) end
	return table.concat(r, ",")
end

local function probeChatAndPing(entry)
	local r = {}
	r.lines = count(function()
		local H = humanTeam(entry)
		ACTIONS = {}
		say(0, "!freeze bot")
		say(0, "!stack top")
		r.orders = orderTypes(H)
		r.freezeOrder = nil
		for _, o in ipairs(H.Orders.GetActive(2)) do if o.type == "LANE_FREEZE" then r.freezeOrder = o end end
		r.chatActions = #ACTIONS

		H = humanTeam(entry)
		LANING = true
		T = 10
		UNITS[2][1].ping = { time = 10, location = Vector(100, BOT_Y), normal_ping = true }
		H.Pings.Scan(2)
		local o = H.Orders.GetActive(2)[1]
		r.pingType = o and o.type
	end)
	return r
end

local jobs, laning, chat = {}, {}, {}
for i, entry in ipairs(OFF) do
	jobs[i], laning[i], chat[i] = probeJobs(entry), probeLaning(entry), probeChatAndPing(entry)
end
local jobsOn, laningOn, chatOn = probeJobs(ON), probeLaning(ON), probeChatAndPing(ON)

for i, entry in ipairs(OFF) do
	local j, l, c = jobs[i], laning[i], chat[i]
	local n = entry.name .. ": "
	check(n .. "lane system inactive", j.active == false)
	check(n .. "OwnsLaning false for an ally of a human", j.ownsAlly == false)
	check(n .. "OwnsLaning false for an enemy bot under 'all'", j.ownsEnemy == false)
	check(n .. "no camp-job desire or think", j.desire == 0 and j.think == false and j.thinkCore == false, tostring(j.desire))
	check(n .. "no rune contest desire", j.runeDesire == 0)
	check(n .. "no stacked-camp preference", j.stacked == nil)
	check(n .. "04's harass keeps running", j.supersedes == false)
	check(n .. "no deny pick", j.deny == nil and l.denied == nil)
	check(n .. "hooks scan nothing and act on nothing", j.jobScans == 0 and j.jobActions == 0, j.jobScans .. "/" .. j.jobActions)
	check(n .. "10 s of ticks scan nothing and act on nothing", j.tickScans == 0 and j.tickActions == 0, j.tickScans .. "/" .. j.tickActions)
	check(n .. "PreThink and Think return false without acting", l.pre == false and l.preActions == 0 and l.think == false and l.thinkActions == 0)
	check(n .. "AdjustPosition returns the same vector", rawequal(l.adjusted, l.input))
	check(n .. "no [H:lane] output", laneLines(j.lines) + laneLines(l.lines) + laneLines(c.lines) == 0)
	check(n .. "lane commands post no order and no action", c.orders == "" and c.chatActions == 0, c.orders)
	check(n .. "lane-front ping is not a hands-off", c.pingType == nil or c.pingType == "GATHER", c.pingType)
	if entry.humaniser ~= false then
		check(n .. "lane-front ping classifies as GATHER as before", c.pingType == "GATHER", c.pingType)
	end
end

-- Positive controls: the same worlds and calls do something with the flags on.
check("control: lane system active", jobsOn.active == true)
check("control: OwnsLaning for an ally of a human and an enemy bot", jobsOn.ownsAlly == true and jobsOn.ownsEnemy == true)
check("control: camp-job desire 0.7 in the pull window", near(jobsOn.desire, 0.7), jobsOn.desire)
check("control: the job owns the frame", jobsOn.think == true and jobsOn.thinkCore == false)
check("control: hooks scan units", jobsOn.jobScans > 0, jobsOn.jobScans)
check("control: ticking scans units", jobsOn.tickScans > 0, jobsOn.tickScans)
check("control: 04's harass is superseded", jobsOn.supersedes == true)
check("control: [H:lane] output", laneLines(jobsOn.lines) > 0)
check("control: PreThink blocks", laningOn.pre == true and laningOn.preActions == 1)
check("control: Think shoves", laningOn.think == true and laningOn.thinkActions == 1)
check("control: AdjustPosition holds the freeze posture", not rawequal(laningOn.adjusted, laningOn.input) and laningOn.adjusted.x < laningOn.input.x)
check("control: mid deny control picks the ranged creep", laningOn.denied == laningOn.ranged)
check("control: !freeze bot posts LANE_FREEZE", chatOn.freezeOrder ~= nil and chatOn.freezeOrder.lane == Lane.Bot, chatOn.orders)
check("control: lane commands act", chatOn.orders:find("LANE_STACK", 1, true) ~= nil, chatOn.orders)
check("control: lane-front ping posts LANE_HANDSOFF", chatOn.pingType == "LANE_HANDSOFF", chatOn.pingType)

-- The mode files call the facade behind these guards; the laning and farm files cannot be loaded offline, so pin the call sites.
local function source(path)
	local f = io.open(HARNESS_DIR .. "/../../bots/" .. path, "r")
	local text = f:read("*a")
	f:close()
	return text
end
local laningSrc, farmSrc = source("mode_laning_generic.lua"), source("mode_farm_generic.lua")
for _, line in ipairs({
	"if bLaneLaning and Lane.PreThink(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy) then return end",
	"if bLaneLaning and Lane.Think(bot, nAllyCreeps, nEnemyCreeps, nInRangeEnemy) then return end",
	"if not bLaneLaning or Lane.MayDeny(bot, nAllyCreeps) then",
	"denyCreep = (bLaneLaning and Lane.PickDeny(bot, nAllyCreeps)) or GetBestDenyCreep(nAllyCreeps)",
	"if bLaneLaning then target_loc = Lane.AdjustPosition(bot, target_loc) end",
	"if (bHumaniserLaning or bLaneLaning) and Lane.SupersedesHarass(bot) then",
	"local bLaneLaning = Lane.OwnsLaning(bot)",
}) do
	check("laning mode guard: " .. line, laningSrc:find(line, 1, true) ~= nil)
end
check("laning mode: Think() defined only for owned bots", laningSrc:find("bLaneLaning", 1, true) ~= nil and laningSrc:find("bHumaniserLaning or bLaneLaning", 1, true) ~= nil)
for _, call in ipairs({ "J.Humaniser.Lane.CampJobDesire(bot)", "J.Humaniser.Lane.CampJobOnEnd(bot)",
	"if J.Humaniser.Lane.CampJobThink(bot) then return end", "J.Humaniser.Lane.PreferStackedCamp(bot, availableCamp) or preferedCamp" }) do
	check("farm mode hook: " .. call, farmSrc:find(call, 1, true) ~= nil)
end

-- Rune mode: the real mode file with the real facade. Flags off give the same desire as a zero contest and scan nothing.
do
	ResetWorld()
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
	local RUNE_AT = { [1] = Vector(-4000, 4000), [2] = Vector(4000, -4000), [3] = Vector(-1000, 1000), [4] = Vector(1500, -1500) }
	function GetRuneSpawnLocation(r) return RUNE_AT[r] end
	function GetRuneStatus(r) return r == RUNE_POWERUP_1 and RUNE_STATUS_AVAILABLE or RUNE_STATUS_MISSING end
	function GetRuneType() return RUNE_HASTE end

	local function hero(o)
		return setmetatable(o, { __index = {
			GetLocation = function(self) return self.loc end, IsBot = function() return true end,
			IsFacingLocation = function() return true end, FindItemSlot = function() return -1 end,
		} })
	end
	local function runeDesire(laneFacade)
		T = 1000
		local bot = hero({ loc = Vector(-300, 300) })
		bot.GetNearbyHeroes = function() return {} end
		bot.IsInvulnerable = function() return false end
		bot.DistanceFromFountain = function() return 5000 end
		bot.GetActiveMode = function() return 0 end
		bot.GetActiveModeDesire = function() return 0 end
		bot.GetAssignedLane = function() return 2 end
		bot.WasRecentlyDamagedByAnyHero = function() return false end
		bot.GetLevel = function() return 30 end
		bot.GetCurrentActionType = function() return BOT_ACTION_TYPE_MOVE_TO end
		bot.HasModifier = function() return false end
		bot.GetPlayerID = function() return 2 end
		bot.rune = { normal = { location = RUNE_BOUNTY_1, distance = 9999, status = RUNE_STATUS_MISSING }, wisdom = {} }
		function GetBot() return bot end
		local J = setmetatable({
			GetHP = function() return 1 end, GetMP = function() return 1 end, GetPosition = function() return 2 end,
			IsCore = function() return true end, IsEarlyGame = function() return true end,
			IsValidHero = function(u) return u ~= nil end, GetDistanceFromEnemyFountain = function() return 9000 end,
			Utils = { IsTeamPushingSecondTierOrHighGround = function() return false end, CountEnemyHeroesNear = function() return 0 end },
			Humaniser = { Lane = laneFacade },
		}, { __index = function() return function() return false end end })
		package.loaded["bots/FunLib/jmz_func"] = J
		package.loaded["bots/Customize/general"] = { Enable = false }
		dofile(HARNESS_DIR .. "/../../bots/mode_rune_generic.lua")
		return GetDesire()
	end

	local base = runeDesire({ RuneContestDesire = function() return 0 end })
	check("rune mode precondition: a power rune gives a desire", base > 0 and base < 0.6, base)
	for _, entry in ipairs(OFF) do
		local H = fresh(entry)
		T = 1000
		GETUNITLIST_CALLS = {}
		local d = runeDesire(H.Lane)
		check(entry.name .. ": rune desire is the unmodified one", near(d, base) and scans() == 0, d)
	end
	check("rune control: a contest desire changes the mode's desire",
		near(runeDesire({ RuneContestDesire = function() return 0.6 end }), math.max(0.6, base)))
end

finish()
