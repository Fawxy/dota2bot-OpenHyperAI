dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

-- Radiant bot lane at y = -5000 (lane_world), small camp south of it. The wave path starts 7,800 west of the camp's
-- meet point, so the :00 wave reaches it at 7800 / 325 = 24 s.
local SMALL = Vector(-1600, -6200)
local PATH = { { -9400, -5000 }, { 7000, -5000 } }

local function within(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function world(opts)
	opts = opts or {}
	local timing = opts.timing or { LanePaths = { radiant_bot = PATH }, NeutralSpeed = { small = 300 } }
	local H = LaneFresh({ Enable = true, PullTiming = timing, Timing = opts.timingCfg }, { skill = 1 })
	T = opts.t or 70
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = { { team = 2, type = "small", location = SMALL, min = Vector(SMALL.x - 150, SMALL.y - 150, 0),
		max = Vector(SMALL.x + 150, SMALL.y + 150, 0), speed = 0 } }
	H.Lane.Camps.ResetCache()
	local data = H.Lane.Camps.ByIdx(1)
	local stand = H.Lane.Camps.BoxEdgePoint(H.Lane.Camps.SpawnerByIdx(1), data.pull.path[1], 150)
	local u = MakeUnit({ pid = 5, team = 2, bot = true, loc = stand })
	u.lane, u.pos = Lane.Bot, 5
	-- As in test_lane_camp_jobs: the core this support owns the camp job for, and one enemy laner elsewhere.
	local core = MakeUnit({ pid = 1, team = 2, loc = Vector(0, -5000) })
	core.lane, core.pos = Lane.Bot, 1
	local enemy = MakeUnit({ pid = 10, team = 3, loc = Vector(0, -5000) })
	enemy.lane, enemy.pos = Lane.Top, 3
	return H, u, data
end

-- The formula restated from the world's own geometry: wave travel along PATH minus the neutrals' walk (origin, lead
-- waypoints, meet) at 300, minus the 1.5 s lead.
local function expected(data, meet, half)
	local walk, prev = 0, SMALL
	for i, p in ipairs(data.pull.path) do
		local q = (i == #data.pull.path) and meet or p
		walk = walk + dist(prev, q)
		prev = q
	end
	return (meet.x - PATH[1][1]) / 325 - walk / 300 - 1.5 + (half and 2 or 0)
end

do
	local H, bot, data = world()
	local want = expected(data, data.pull.meetPoint)
	check("precondition: derived second differs from the :15 seed", math.abs(want - 15) > 2, want)
	check("full pull starts", H.Lane.CampJobs.Start(bot, { kind = "full_pull", campIdx = 1 }))
	local job = H.Lane.CampJobs.Current(bot)
	check("full pull planned from the wave", within(job.plannedSec, want, 1e-3), job.plannedSec)
	check("full pull logged as wave-timed", job.timing == "wave")
	check("watch waits for the :60 wave at the meet point", within(job.waveAt, 60 + (data.pull.meetPoint.x - PATH[1][1]) / 325, 1e-3), job.waveAt)
end

do
	local H, bot, data = world()
	H.Lane.CampJobs.Start(bot, { kind = "half_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(bot)
	local want = expected(data, data.pull.halfMeetPoint, true)
	check("half pull timed to its own meet point, HalfPullLater after", within(job.plannedSec, want, 1e-3), job.plannedSec)
end

do
	-- At 1:10 the :60 wave has walked 3,250; a lead creep 650 further on is 2 s early, so the aggro moves 2 s earlier.
	local H, bot, data = world()
	local want = expected(data, data.pull.meetPoint)
	MakeCreep({ team = 2, x = PATH[1][1] + 3250 + 650, y = -5000 })
	MakeCreep({ team = 2, x = PATH[1][1] + 3250 + 650 - 100, y = -5000 })
	H.Lane.CampJobs.Start(bot, { kind = "full_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(bot)
	check("wave seen ahead of schedule pulls earlier", within(job.plannedSec, want - 2, 1e-3), job.plannedSec)
	check("live-shifted pull logged as live", job.timing == "live")
	check("the slot stays the unshifted aggro", within(job.slot - job.baseAggro, 2, 1e-3))
end

do
	-- The previous wave far up the lane is not the pulled wave.
	local H, bot, data = world()
	MakeCreep({ team = 2, x = 3000, y = -5000 })
	H.Lane.CampJobs.Start(bot, { kind = "full_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(bot)
	check("an old wave elsewhere on the lane does not shift the pull", within(job.plannedSec, expected(data, data.pull.meetPoint), 1e-3) and job.timing == "wave")
end

do
	-- No lane path override: the stub lane is ~1,100 off the real 7.41 Radiant bot path, so the meet point is not on it.
	local H, bot = world({ timing = {} })
	H.Lane.CampJobs.Start(bot, { kind = "full_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(bot)
	check("meet point off the lane path falls back to the seed", job.plannedSec == 15 and job.timing == "seed", job.plannedSec)
	check("seed pull has no wave arrival", job.waveAt == nil)

	H, bot = world({ timing = { FromWave = false, LanePaths = { radiant_bot = PATH } } })
	H.Lane.CampJobs.Start(bot, { kind = "full_pull", campIdx = 1 })
	check("FromWave off keeps the seed", H.Lane.CampJobs.Current(bot).plannedSec == 15)
end

do
	local PT = LaneFresh({ Enable = true }).Lane.PullTiming
	CURRENT_TEAM = 2
	local t = PT.For(2, Lane.Bot, nil, "small", { Vector(4050, -6139) }, false, { 15, 45 })
	check("missing spawner origin falls back to the seed", t.source == "seed" and t.seconds[1] == 15)
	-- 7.41 good_1 (radiant_safe_small): spawner origin and derived meet from the map data.
	t = PT.For(2, Lane.Bot, Vector(3978, -5027), "small", { Vector(4050, -6139) }, false, { 15, 45 })
	check("7.41 radiant safe small camp pulls near :20/:50", t.source == "wave" and t.seconds[1] > 19.5 and t.seconds[1] < 21.5
		and within(t.seconds[2] - t.seconds[1], 30, 1e-6), t.seconds[1])
end

do
	-- Watch outlasts WatchSec (1 s here) until WatchAfterWave (3 s) past the wave's arrival.
	local H, bot = world({ timingCfg = { WatchSec = 1 } })
	H.Lane.CampJobs.Start(bot, { kind = "full_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(bot)
	job.phase, job.watchFrom, job.acted = "watch", job.aggroAt + 3, true
	bot.loc = job.path[#job.path]
	local function runTo(t)
		while T < t do
			T = math.min(t, T + 0.25)
			if H.Lane.CampJobDesire(bot) > 0 then H.Lane.CampJobThink(bot) end
		end
	end
	T = job.watchFrom
	runTo(job.watchFrom + 1.5)
	check("watch holds past WatchSec while the wave is still coming", job.phase == "watch", job.phase)
	runTo(job.waveAt + 2.9)
	check("watch still holding just before WatchAfterWave", job.phase == "watch", job.phase)
	runTo(job.waveAt + 3.1)
	check("watch ends WatchAfterWave after the wave arrives", job.phase == "done", job.phase)
end

finish()
