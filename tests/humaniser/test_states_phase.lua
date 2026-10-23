dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- Slice 12: the team game phase. Shadow (Priors off) logs ev=phase and leaves state scores alone; Priors on
-- multiplies them by the phase bias; PUSH/DEFEND bus orders become phase orders; towers, threat and the clock
-- come from the snapshot OHA builds; Enable = false runs nothing.
local LANING = 1
BOT_MODE_LANING = LANING

local W

-- Coordinates stay map-sized: fengari's integers are 32-bit, so squared distances of far-off points would wrap.
-- Tower ids follow ts_libs/dota's fallbacks (TOWER_* are unset here): 0-2 T1/T2/T3 top, 3-5 mid, 6-8 bot, 9-10 base.
function GetTower(team, id)
	local t = W.towers[team][id]
	if t == nil then return nil end
	return { IsAlive = function() return t.alive end, GetLocation = function() return t.loc end }
end
function IsHeroAlive(pid)
	for team = 2, 3 do for _, u in ipairs(UNITS[team]) do if u.pid == pid then return u.alive end end end
	return false
end
function GetHeroLastSeenInfo(pid)
	for team = 2, 3 do for _, u in ipairs(UNITS[team]) do if u.pid == pid then return { { location = u.loc, time_since_seen = u.seen or 0 } } end end end
	return {}
end
function GetLaneFrontAmount() return 0.5 end

local function towerSet(x0)
	local s = {}
	for id = 0, 10 do s[id] = { alive = true, loc = Vector(x0 + id * 500, 0) } end
	return s
end

local function Fresh(phase, o)
	ResetWorld()
	T = 10
	package.loaded["bots/FunLib/sdk/tasks/tasks"] = nil
	o = o or {}
	local H = FreshHumaniser({ Enable = true, Lane = { Enable = false }, Transitions = { Enable = false }, Telemetry = { Enable = true },
		States = { Enable = true, Own = { laning = {} }, ShadowTeams = "all" }, Phase = phase })
	W = { laning = true, towers = { [2] = towerSet(-7000), [3] = towerSet(2000) } }
	require("bots/FunLib/humaniser/transitions/phase").IsLaningFor = function() return W.laning end
	local CampJobs = require("bots/FunLib/humaniser/camp_jobs")
	CampJobs.Active = function() return false end
	CampJobs.Current = function() return nil end
	require("bots/FunLib/humaniser/transitions/rotation").Active = function() return nil end
	local Farm = require("bots/FunLib/humaniser/farm_pattern")
	Farm.IsActive = function() return true end
	Farm.Current = function() return nil end
	local positions = {}
	require("bots/FunLib/humaniser/lane_config").SetHelpers({ GetPosition = function(u) return positions[u.pid] end })
	MakeUnit({ pid = 0, bot = false, team = 2 })
	local bot = MakeUnit({ pid = 1, team = 2, mode = LANING, loc = Vector(0, 0), level = 6 })
	positions[1] = 2
	for pid = 5, 9 do MakeUnit({ pid = pid, team = 3, loc = Vector(7000, 7000) }) end
	local lines = {}
	require("bots/FunLib/humaniser/telemetry").SetSink(function(l) table.insert(lines, l) end)
	H.States.SetLaneSpot(bot, function() return Vector(1000, 0) end)
	return H, bot, lines
end

local function frames(H, bot, secs)
	for _ = 1, math.floor(secs / 0.05 + 0.5) do
		H.Phase.Tick(bot)
		H.States.Tick(bot)
		H.Tasks.Tick(bot)
		T = T + 0.05
	end
end

local function count(lines, pattern)
	local n = 0
	for _, l in ipairs(lines) do if l:find(pattern) then n = n + 1 end end
	return n
end

local function silenced(fn)
	local p = print
	print = function() end
	local ok, err = pcall(fn)
	print = p
	if not ok then error(err, 0) end
end

local function stateScore(bot)
	local cur = require("bots/FunLib/humaniser/tasks").Loaded().States.Current(bot)
	return cur and cur.score
end

local function allT1Down()
	for team = 2, 3 do for _, id in ipairs({ 0, 3, 6 }) do W.towers[team][id].alive = false end end
end

-- Shadow: the phase is logged per change and state scores are the scorers' own.
do
	local H, bot, lines, early, late
	silenced(function()
		H, bot, lines = Fresh({ Enable = true, Priors = false })
		frames(H, bot, 5)
		early = H.Phase.Describe(2)
		T = 1000
		allT1Down()
		frames(H, bot, 10)
		late = H.Phase.Describe(2)
	end)
	check("shadow: laning at the start", early == "laning shadow", early)
	check("shadow: midgame once lanes are over", late == "midgame shadow", late)
	check("shadow: ev=phase logged per change", count(lines, "ev=phase team=2 from=none to=laning") == 1 and count(lines, "ev=phase team=2 from=laning to=midgame") == 1, table.concat(lines, "\n"))
	check("shadow: laning state score untouched in midgame", near(stateScore(bot) or -1, 0.5), stateScore(bot))
end

-- Priors on: the same laning scorer is damped by the midgame bias once it has blended in.
do
	local H, bot, lines, inLaning
	silenced(function()
		H, bot, lines = Fresh({ Enable = true, Priors = true })
		frames(H, bot, 5)
		inLaning = stateScore(bot)
		T = 1000
		allT1Down()
		frames(H, bot, 10)
	end)
	check("priors: laning phase leaves laning at 0.5", near(inLaning or -1, 0.5), inLaning)
	check("priors: midgame damps laning (0.5 x 0.3)", near(stateScore(bot) or -1, 0.15), stateScore(bot))
end

-- Threat from the snapshot: three enemies seen at our mid T2 make the team defend; a DEFEND order does too.
do
	local H, bot, lines, threatened, ordered
	silenced(function()
		H, bot, lines = Fresh({ Enable = true })
		T = 1000
		allT1Down()
		frames(H, bot, 3)
		for pid = 5, 7 do UNITS[3][pid - 4].loc = W.towers[2][4].loc end
		frames(H, bot, 2)
		threatened = H.Phase.Describe(2)
		for pid = 5, 7 do UNITS[3][pid - 4].loc = Vector(7000, 7000) end
		frames(H, bot, 5)
		require("bots/FunLib/humaniser/orders").Post(2, { type = "DEFEND", sourceKey = "test:defend", issuerPID = 0, duration = 30, maxResponders = 1, location = Vector(0, 0) })
		frames(H, bot, 0.1)
		ordered = H.Phase.Describe(2)
	end)
	check("snapshot: 3 enemies at our T2 -> defend", threatened == "defend shadow", threatened)
	check("orders: DEFEND bus order -> defend phase", ordered ~= nil and ordered:find("^defend %(order:DEFEND:%d+%)") ~= nil, ordered)
end

-- Kill switch.
do
	local H, bot, lines
	silenced(function()
		H, bot, lines = Fresh({ Enable = false })
		frames(H, bot, 5)
	end)
	check("off: no phase, no events", H.Phase.Describe(2) == nil and count(lines, "ev=phase") == 0)
end

finish()
