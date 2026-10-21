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
	check("stack exit distance", math.abs(math.sqrt((exit.x - centre.x) ^ 2 + (exit.y - centre.y) ^ 2) - 900) < 1)
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
