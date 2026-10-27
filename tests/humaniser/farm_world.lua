-- Farm-pattern world: a Radiant bot-lane core and support with neutral camps, for core jungle trips between waves.
-- Shared by test_farm_pattern.lua and the core_trip fixture driver. Not a test_ file, so run.js skips it.
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

-- Radiant bot lane: the stub front sits at (0, -5000). Overriding Dire's bot path with a straight line along the lane
-- puts the enemy wave's walk to the front at `travel` seconds (path length / 325), so arrivals are travel + 30k.
FARM_FRONT = Vector(0, -5000)
FARM_SMALL = Vector(0, -6200) -- 1,200 from the front: 4 s each way at 300
FARM_SMALL2 = Vector(900, -6600) -- 985 from SMALL, 1,836 from the front
FARM_LARGE = Vector(1500, -6500) -- 2,121 from the front

function FarmSpawner(type_, at)
	return { team = 2, type = type_, location = Vector(at.x, at.y, 0), min = Vector(at.x - 150, at.y - 150, 0),
		max = Vector(at.x + 150, at.y + 150, 0), speed = 0 }
end

function FarmWorld(o)
	local H = LaneFresh({ Enable = true, PullTiming = { LanePaths = { dire_bot = { { 325 * o.travel, -5000 }, { -7000, -5000 } } } } },
		{ skill = o.skill or 0.9, farm = o.farm, transitions = o.transitions })
	T = o.t
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = {}
	local camp = {}
	for i, c in ipairs(o.camps) do
		table.insert(SPAWNERS, FarmSpawner(c[1], c[2]))
		camp[i] = MakeNeutral({ x = c[2].x, y = c[2].y })
	end
	H.Lane.Camps.ResetCache()
	H.FarmPattern.ResetCache()
	local core = MakeUnit({ pid = 1, team = 2, loc = o.at or FARM_FRONT, level = o.level or 6, mode = BotMode.Laning })
	core.lane, core.pos = Lane.Bot, o.pos or 1
	local support = MakeUnit({ pid = 5, team = 2, loc = Vector(-3000, -5600), level = 4, mode = BotMode.Laning })
	support.lane, support.pos = Lane.Bot, 5
	MakeUnit({ pid = 10, team = 3, loc = Vector(6000, 6000) }).pos = 3
	H.Lane.Config.SkillOf(core)
	H.Lane.Config.SkillOf(support)
	return H, core, support, camp
end

