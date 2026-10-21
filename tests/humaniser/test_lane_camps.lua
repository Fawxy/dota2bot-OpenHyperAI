dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, Team = dota.Lane, dota.Team
local RAD, DIRE = Team.Radiant, Team.Dire

local function spawner(team, type_, x, y)
	return { team = team, type = type_, location = Vector(x, y, 0), min = Vector(x - 150, y - 150, 0), max = Vector(x + 150, y + 150, 0), speed = 0 }
end
local function world(list)
	local H = LaneFresh({ Enable = true })
	SPAWNERS = list
	H.Lane.Camps.ResetCache()
	return H.Lane.Camps, H
end

do
	local C = world({})
	check("radiant team amount is identity", near(C.ToTeamAmount(RAD, 0.3), 0.3))
	check("dire team amount is mirrored", near(C.ToTeamAmount(DIRE, 0.3), 0.7))
	check("abs/team round trip", near(C.ToAbsAmount(DIRE, C.ToTeamAmount(DIRE, 0.3)), 0.3))
end

do
	local C = world({})
	check("radiant safe is bot", C.LaneOfKind(RAD, "safe") == Lane.Bot)
	check("radiant off is top", C.LaneOfKind(RAD, "off") == Lane.Top)
	check("dire safe is top", C.LaneOfKind(DIRE, "safe") == Lane.Top)
	check("dire off is bot", C.LaneOfKind(DIRE, "off") == Lane.Bot)
	check("mid is mid for both", C.LaneOfKind(RAD, "mid") == Lane.Mid and C.LaneOfKind(DIRE, "mid") == Lane.Mid)
end

-- Bot T1 (radiant) sits at x = -2800, y = -5000
do
	local C = world({ spawner(RAD, "small", -1600, -5000), spawner(RAD, "small", 1200, -5000) })
	local found = C.PullCampsFor(RAD, Lane.Bot)
	check("exactly one pull camp", #found == 1, #found)
	local job = found[1]
	check("near camp chosen", job and job.campIdx == 1, job and job.campIdx)
	check("seed aggro times", job and job.pull.aggroSec[1] == 15 and job.pull.aggroSec[2] == 45)
	check("seed provenance", job and job.source == "seed" and job.derived == true and job.key == "radiant_safe_small")
	check("meet point on lane", job and near(job.pull.meetPoint.y, LANE_Y[Lane.Bot]))
	check("far camp has no pull", C.ByIdx(2).pull == nil)
end

do
	local C = world({ spawner(RAD, "small", -2800 + 3000, -5000) })
	check("seed rejected when too far", #C.PullCampsFor(RAD, Lane.Bot) == 0)
	check("camp still gets stack data", C.ByIdx(1).stack ~= nil)
end

do
	local C = world({ spawner(RAD, "small", -1600, -5000), spawner(RAD, "large", -2000, -4600) })
	local found = C.PullCampsFor(RAD, Lane.Bot)
	check("small first then large", #found == 2 and found[1].type == "small" and found[2].type == "large")
end

do
	local C = world({ spawner(RAD, "small", -6000, -5000) })
	check("alive T1 too far for camp", #C.PullCampsFor(RAD, Lane.Bot) == 0)
	local w = MakeLaneTowers()
	w[RAD][dota.Tower.Bot1].alive = false
	local t2 = MakeLaneTowers()[RAD][dota.Tower.Bot1]
	t2.loc = Vector(-4900, -5000, 0)
	w[RAD][dota.Tower.Bot2] = t2
	TOWERS_W = w
	C.ResetCache()
	check("dead T1 falls back to T2", #C.PullCampsFor(RAD, Lane.Bot) == 1)
end

do
	local C = world({ spawner(RAD, "small", -1600, -5000) })
	local data = require("bots/FunLib/humaniser/camps_data")
	local meet = Vector(-1234, -5000, 0)
	table.insert(data.CAMP_DATA, { key = "replay_test", team = RAD, type = "small", laneKind = "safe", near = Vector(-1600 + 300, -5000 + 400, 0),
		pullAggroSec = { 10, 40 }, pullPath = { meet }, meetPoint = meet, source = "replay" })
	C.ResetCache()
	local job = C.PullCampsFor(RAD, Lane.Bot)[1]
	table.remove(data.CAMP_DATA)
	check("replay wins over seed", job and job.source == "replay" and job.derived == false and job.key == "replay_test")
	check("replay explicit meet point", job and job.pull.meetPoint.x == -1234 and job.pull.aggroSec[1] == 10)
end

do
	local C = world({})
	local meet = C.DeriveMeetPoint(RAD, Lane.Bot, Vector(-1600, -4400, 0))
	check("meet on lane", near(meet.y, LANE_Y[Lane.Bot]) and math.abs(meet.x + 1600) < 100, meet.x)
	local half = C.DeriveHalfMeetPoint(RAD, Lane.Bot, meet)
	check("radiant half meet 500 further +x", math.abs(half.x - meet.x - 500) < 1 and near(half.y, LANE_Y[Lane.Bot]), half.x - meet.x)
	local dm = C.DeriveMeetPoint(DIRE, Lane.Top, Vector(2000, 4500, 0))
	local dh = C.DeriveHalfMeetPoint(DIRE, Lane.Top, dm)
	check("dire half meet 500 further -x", math.abs(dm.x - dh.x - 500) < 1, dm.x - dh.x)
end

do
	local C = world({ spawner(RAD, "large", -1600, -4000) })
	local s = C.Spawners()[1]
	local exit = C.DeriveStackExit(s, RAD)[1]
	local centre = C.BoxCenter(s)
	check("stack exit away from lane", math.abs(exit.y - LANE_Y[Lane.Bot]) > math.abs(centre.y - LANE_Y[Lane.Bot]), exit.y)
	check("stack exit 900 past the box edge", math.abs(math.sqrt((exit.x - centre.x) ^ 2 + (exit.y - centre.y) ^ 2) - (150 + 900)) < 1)
end

do
	local C = world({ spawner(RAD, "ancient", 3000, 1000), spawner(DIRE, "small", 3000, -1000) })
	check("ancient stack default", C.ByIdx(1).stack.aggroSec == 53.0)
	check("small stack default", C.ByIdx(2).stack.aggroSec == 54.5)
	check("stack exit path present", #C.ByIdx(1).stack.exitPath == 1)
	SPAWNERS = { { team = RAD, type = 3, location = Vector(0, 0, 0), min = Vector(-10, -10, 0), max = Vector(10, 10, 0) } }
	C.ResetCache()
	check("int type normalised", C.Spawners()[1].type == "ancient")
end

do
	local C = world({ spawner(RAD, "small", -1600, -5000), spawner(DIRE, "small", 1600, 5000) })
	check("no mid pull radiant", #C.PullCampsFor(RAD, Lane.Mid) == 0)
	check("no mid pull dire", #C.PullCampsFor(DIRE, Lane.Mid) == 0)
	check("InBox inside", C.InBox(1, Vector(-1600, -5000, 0)))
	check("InBox outside", not C.InBox(1, Vector(-1000, -5000, 0)))
	check("InBox margin", C.InBox(1, Vector(-1400, -5000, 0), 100))
	local s, d = C.NearestSpawner(Vector(1500, 4900, 0))
	check("nearest spawner", s.idx == 2 and d < 200)
end

-- 7.41 map: neutral spawner origins, T1/T2 towers and the goodguys lane path_corner chains, read from the entity
-- lump of game/dota/maps/dota.vpk (default_ents.vents_c, 22/10/2026). Box centres are within ~250 of these origins.
local MAP_SPAWNERS = {
	{ "evil_1", DIRE, "large", -4824, 3915 }, { "evil_11", DIRE, "small", -2880, 7376 }, { "evil_12", DIRE, "medium", 2016, 7896 },
	{ "evil_13", DIRE, "small", 8430, 1263 }, { "evil_14", DIRE, "medium", 336, 7696 }, { "evil_15", DIRE, "medium", -2596, 3850 },
	{ "evil_2", DIRE, "small", -3911, 4829 }, { "evil_20", DIRE, "medium", -4208, 8336 }, { "evil_4", DIRE, "medium", 1224, 4176 },
	{ "evil_5", DIRE, "large", 1064, 2580 }, { "evil_6", DIRE, "medium", -852, 4940 }, { "evil_7", DIRE, "large", 7928, -120 },
	{ "evil_8", DIRE, "ancient", 4352, 48 }, { "evil_9", DIRE, "medium", 3392, -1408 },
	{ "good_1", RAD, "small", 3978, -5027 }, { "good_11", RAD, "medium", -720, -7696 }, { "good_12", RAD, "medium", -2415, -8402 },
	{ "good_13", RAD, "large", -8313, -553 }, { "good_14", RAD, "small", 2768, -8336 }, { "good_15", RAD, "medium", 1922, -3975 },
	{ "good_16", RAD, "small", -8023, -1838 }, { "good_2", RAD, "large", 4649, -3699 }, { "good_20", RAD, "medium", 4416, -8432 },
	{ "good_4", RAD, "medium", 186, -5197 }, { "good_5", RAD, "large", -1454, -3356 }, { "good_7", RAD, "medium", -4013, 992 },
	{ "good_8", RAD, "ancient", -5015, -96 }, { "good_9", RAD, "medium", -1983, -4815 },
}
local MAP_TOWERS = {
	[RAD] = { [dota.Tower.Top1] = { -6336, 1856 }, [dota.Tower.Top2] = { -6501, -872 }, [dota.Tower.Bot1] = { 4860, -6379 }, [dota.Tower.Bot2] = { -360, -6256 } },
	[DIRE] = { [dota.Tower.Top1] = { -5275, 6036 }, [dota.Tower.Top2] = { -128, 6016 }, [dota.Tower.Bot1] = { 6269, -2240 }, [dota.Tower.Bot2] = { 6400, 384 } },
}
local MAP_LANES = {
	[Lane.Top] = { { -6608, -4064 }, { -6584, -4224 }, { -6080, 384 }, { -6656, 1600 }, { -6208, 4224 }, { -6200, 5312 }, { -5792, 5464 },
		{ -5160, 5712 }, { -4488, 5824 }, { -3784, 5928 }, { -2792, 6048 }, { -1856, 6104 }, { 3856, 5784 }, { 5323, 4852 } },
	[Lane.Mid] = { { -5008, -4488 }, { -4856, -4376 }, { -3148, -2694 }, { -976, -824 }, { -360, -256 }, { 176, 120 }, { 912, 624 },
		{ 2584, 1704 }, { 4472, 3944 }, { 5323, 4788 } },
	[Lane.Bot] = { { -3648, -6112 }, { -4024, -6112 }, { 480, -6457 }, { 2048, -6336 }, { 3320, -6184 }, { 4028, -6140 }, { 4672, -6098 },
		{ 5743, -5781 }, { 6028, -5484 }, { 6133, -4708 }, { 6256, -3252 }, { 6336, 3328 }, { 5387, 4788 } },
}

local function mapAlongLane(l, a)
	local pts = MAP_LANES[l]
	local total = 0
	for i = 2, #pts do total = total + math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2) end
	local want = math.max(0, math.min(1, a)) * total
	for i = 2, #pts do
		local seg = math.sqrt((pts[i][1] - pts[i - 1][1]) ^ 2 + (pts[i][2] - pts[i - 1][2]) ^ 2)
		if want <= seg or i == #pts then
			local t = seg > 0 and math.min(1, want / seg) or 0
			return Vector(pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * t, pts[i - 1][2] + (pts[i][2] - pts[i - 1][2]) * t, 0)
		end
		want = want - seg
	end
end

local function mapTower(x, y, alive)
	return { IsAlive = function() return alive ~= false end, GetLocation = function() return Vector(x, y, 0) end }
end

-- extra: synthetic spawners appended after the real ones; deadT1: { team, lane } pairs whose T1 is dead.
local function mapWorld(extra, deadT1, drop)
	local H = LaneFresh({ Enable = true })
	local list, names = {}, {}
	for _, s in ipairs(MAP_SPAWNERS) do
		if s[1] ~= drop then
			table.insert(list, spawner(s[2], s[3], s[4], s[5]))
			names[#list] = s[1]
		end
	end
	for _, s in ipairs(extra or {}) do
		table.insert(list, spawner(s[2], s[3], s[4], s[5]))
		names[#list] = s[1]
	end
	SPAWNERS = list
	local w = { [RAD] = {}, [DIRE] = {} }
	for team, ts in pairs(MAP_TOWERS) do for id, p in pairs(ts) do w[team][id] = mapTower(p[1], p[2]) end end
	for _, d in ipairs(deadT1 or {}) do
		local id = ({ [Lane.Top] = dota.Tower.Top1, [Lane.Bot] = dota.Tower.Bot1 })[d[2]]
		w[d[1]][id] = mapTower(MAP_TOWERS[d[1]][id][1], MAP_TOWERS[d[1]][id][2], false)
	end
	TOWERS_W = w
	H.Lane.Camps.ResetCache()
	return H.Lane.Camps, names
end

local function withMapLanes(fn)
	local old = GetLocationAlongLane
	GetLocationAlongLane = mapAlongLane
	local ok, err = pcall(fn)
	GetLocationAlongLane = old
	if not ok then error(err, 0) end
end

local function campNamesFor(C, names, team, lane)
	local r = {}
	for _, job in ipairs(C.PullCampsFor(team, lane)) do table.insert(r, names[job.campIdx] .. "=" .. tostring(job.key)) end
	return table.concat(r, ",")
end

withMapLanes(function()
	local C, names = mapWorld()
	local radOff = campNamesFor(C, names, RAD, Lane.Top)
	check("7.41 radiant offlane resolves its hard camp", radOff == "good_13=radiant_off_large", radOff)
	local direOff = campNamesFor(C, names, DIRE, Lane.Bot)
	check("7.41 dire offlane resolves its hard camp", direOff == "evil_7=dire_off_large", direOff)
	local radOffJob = C.PullCampsFor(RAD, Lane.Top)[1]
	check("off-lane camp stays seed and unverified", radOffJob and radOffJob.source == "seed" and radOffJob.unverified == true and radOffJob.derived == true)
	check("radiant off meet point near own T2", radOffJob and math.abs(radOffJob.pull.meetPoint.y + 783) < 150, radOffJob and radOffJob.pull.meetPoint.y)
	check("7.41 radiant safe small still resolved", campNamesFor(C, names, RAD, Lane.Bot):find("good_1=radiant_safe_small", 1, true) ~= nil)
	local direSafe = campNamesFor(C, names, DIRE, Lane.Top)
	check("7.41 dire safe camps unchanged", direSafe == "evil_2=dire_safe_small,evil_1=dire_safe_large", direSafe)
	check("7.41 no mid pull camps", #C.PullCampsFor(RAD, Lane.Mid) == 0 and #C.PullCampsFor(DIRE, Lane.Mid) == 0)
end)

withMapLanes(function()
	-- A large camp nearer the Radiant top T1 than good_13 but ~2900 from the lane (inside the jungle) is not pullable into it.
	local C, names = mapWorld({ { "jungle_large", RAD, "large", -3500, 1500 } })
	local radOff = campNamesFor(C, names, RAD, Lane.Top)
	check("jungle camp far from lane skipped for the real off camp", radOff == "good_13=radiant_off_large", radOff)
	C, names = mapWorld({ { "jungle_large", RAD, "large", -3500, 1500 } }, nil, "good_13")
	check("jungle camp far from lane never claimed", campNamesFor(C, names, RAD, Lane.Top) == "")
end)

withMapLanes(function()
	-- Radiant bot T1 down: safe-lane seeds measure from T2 (-360, -6256); good_5 is ~3100 from it but sits off the mid lane.
	local C, names = mapWorld(nil, { { RAD, Lane.Bot } })
	local radSafe = campNamesFor(C, names, RAD, Lane.Bot)
	check("dead safe T1 does not claim the mid-side hard camp", radSafe:find("good_5", 1, true) == nil, radSafe)
	C, names = mapWorld(nil, { { RAD, Lane.Top }, { DIRE, Lane.Bot } })
	check("dead off T1 still resolves via T2", campNamesFor(C, names, RAD, Lane.Top) == "good_13=radiant_off_large"
		and campNamesFor(C, names, DIRE, Lane.Bot) == "evil_7=dire_off_large")
end)

withMapLanes(function()
	-- console.9055745679: stacks of the Radiant top medium (warlock) and the Dire triangle hard camp (grimstroke, witch
	-- doctor) walked off only ~300-400 units. Real 7.41 spawn boxes (trigger bounds from the map's camp models).
	local H = LaneFresh({ Enable = true })
	SPAWNERS = {
		{ team = RAD, type = "medium", location = Vector(-4013, 992, 0), min = Vector(-4368, 535, 0), max = Vector(-3696, 1255, 0) },
		{ team = DIRE, type = "large", location = Vector(1064, 2580, 0), min = Vector(637, 2142, 0), max = Vector(1539, 2931, 0) },
		{ team = RAD, type = "ancient", location = Vector(-5015, -96, 0), min = Vector(-5349, -592, 0), max = Vector(-4245, 385, 0) },
	}
	H.Lane.Camps.ResetCache()
	local radii = H.Lane.Config.Settings().Radii
	for idx, name in ipairs({ "radiant top medium", "dire triangle large", "radiant ancient" }) do
		local job = H.Lane.Camps.ByIdx(idx)
		local s = H.Lane.Camps.SpawnerByIdx(idx)
		local stand = H.Lane.Stacking.StandPoint(s, job)
		local exit = job.stack.exitPath[1]
		local walk = math.sqrt((exit.x - stand.x) ^ 2 + (exit.y - stand.y) ^ 2)
		check(name .. ": stack walk-off covers StackExit past the stand point's box edge", walk >= radii.StackExit - radii.StandOffset - 1, walk)
		check(name .. ": stack exit well clear of the box", not H.Lane.Camps.InBox(idx, exit, 600), exit.x .. "," .. exit.y)
	end
end)

-- lane_world's lane amounts follow the caller like the engine's: as a Dire script, 0 is the Dire base.
local function asDireCaller(fn)
	local H = LaneFresh({ Enable = true })
	CURRENT_TEAM = DIRE
	local ok, err = pcall(fn, H)
	CURRENT_TEAM = RAD
	if not ok then error(err, 0) end
end

asDireCaller(function(H)
	local C = H.Lane.Camps
	check("dire caller: own amounts already in dire frame", near(C.ToTeamAmount(DIRE, 0.3), 0.3) and near(C.ToAbsAmount(DIRE, 0.3), 0.3))
	check("dire caller: radiant amounts mirrored", near(C.ToTeamAmount(RAD, 0.3), 0.7))
	local dm = C.DeriveMeetPoint(DIRE, Lane.Top, Vector(2000, 4500, 0))
	local dh = C.DeriveHalfMeetPoint(DIRE, Lane.Top, dm)
	check("dire caller: dire half meet 500 toward radiant (-x)", math.abs(dm.x - dh.x - 500) < 1, dh.x - dm.x)
	local rm = C.DeriveMeetPoint(RAD, Lane.Bot, Vector(-1600, -4400, 0))
	local rh = C.DeriveHalfMeetPoint(RAD, Lane.Bot, rm)
	check("dire caller: radiant half meet 500 toward dire (+x)", math.abs(rh.x - rm.x - 500) < 1, rh.x - rm.x)
	-- Team-frame tower amounts as lane_state stores them for Dire: own T1 0.3, enemy T1 0.7 (world x 2800 / -2800).
	local hold = H.Lane.LaneTech.HoldPoint(DIRE, Lane.Bot, -1, 0.3, 0.7, 0)
	check("dire caller: hold at eq -1 is at dire's own T1", math.abs(hold.x - 2800) < 1, hold.x)
	local back = H.Lane.LaneTech.HoldPoint(DIRE, Lane.Bot, 0, 0.3, 0.7, 300)
	check("dire caller: hold walk-back goes toward dire's base (+x)", math.abs(back.x - 300) < 1, back.x)
end)

do
	local H = LaneFresh({ Enable = true })
	local back = H.Lane.LaneTech.HoldPoint(RAD, Lane.Bot, 0, 0.3, 0.7, 300)
	check("radiant caller: hold walk-back goes toward radiant's base (-x)", math.abs(back.x + 300) < 1, back.x)
end

-- !hpt / !hcamp through the chat hub
local function chatTest(debug)
	local H = LaneFresh({ Enable = true }, { debug = debug })
	SPAWNERS = { spawner(RAD, "small", -1600, -5000), spawner(RAD, "large", 100, 100) }
	H.Lane.Camps.ResetCache()
	local human = MakeUnit({ pid = 0, team = 2, bot = false, loc = Vector(-1500, -4900, 7) })
	local bot = MakeUnit({ pid = 1, team = 2, bot = true })
	local printed = {}
	local old = print
	print = function(s) table.insert(printed, s) end
	H.Tick(bot)
	for _, text in ipairs({ "!hpt", "!hcamp" }) do
		T = T + 0.5
		for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = 0, string = text, team_only = false }) end
	end
	T = T + 0.5
	for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = 1, string = "!hpt", team_only = false }) end
	print = old
	local lane = {}
	for _, l in ipairs(printed) do if l:find("[H:lane]", 1, true) then table.insert(lane, l) end end
	return lane
end

do
	local off = chatTest(false)
	check("debug off logs nothing", #off == 0, off[1])
	local on = chatTest(true)
	local hpt, hcamp
	for _, l in ipairs(on) do
		if l:find("hpt", 1, true) then hpt = (hpt and "dup" or l) end
		if l:find("hcamp", 1, true) then hcamp = l end
	end
	check("hpt logs a Vector literal once (bot issuer ignored)", hpt == "[H:lane] hpt Vector(-1500, -4900, 7)", hpt)
	check("hcamp logs nearest spawner", hcamp and hcamp:find("idx=1 team=2 type=small", 1, true) and hcamp:find("job=radiant_safe_small source=seed derived=true", 1, true), hcamp)
end

finish()
