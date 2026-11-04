dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

-- Radiant bot lane at y = -5000 (lane_world), small camp south of it. The wave path starts 7,800 west of the camp's
-- meet point, so the :00 wave reaches it at 7800 / 325 = 24 s at creep speed, AHEAD s sooner (the safe lane's WaveAhead).
local SMALL = Vector(-1600, -6200)
local PATH = { { -9400, -5000 }, { 7000, -5000 } }

local AHEAD = 1

local function within(a, b, tol) return math.abs(a - b) <= (tol or 1e-6) end
local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

local function world(opts)
	opts = opts or {}
	local timing = opts.timing or { LanePaths = { radiant_bot = PATH }, NeutralSpeed = { small = 300 }, WaveAhead = { safe = AHEAD, off = 0.5 } }
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
-- waypoints, meet) at 300, minus the 1.5 s lead and the safe lane's WaveAhead.
local function expected(data, meet, half)
	local walk, prev = 0, SMALL
	for i, p in ipairs(data.pull.path) do
		local q = (i == #data.pull.path) and meet or p
		walk = walk + dist(prev, q)
		prev = q
	end
	return (meet.x - PATH[1][1]) / 325 - AHEAD - walk / 300 - 1.5 + (half and 2 or 0)
end

do
	local H, bot, data = world()
	local want = expected(data, data.pull.meetPoint)
	check("precondition: derived second differs from the :15 seed", math.abs(want - 15) > 2, want)
	check("full pull starts", H.Lane.CampJobs.Start(bot, { kind = "full_pull", campIdx = 1 }))
	local job = H.Lane.CampJobs.Current(bot)
	check("full pull planned from the wave", within(job.plannedSec, want, 1e-3), job.plannedSec)
	check("full pull logged as wave-timed", job.timing == "wave")
	check("watch waits for the :60 wave at the meet point", within(job.waveAt, 60 + (data.pull.meetPoint.x - PATH[1][1]) / 325 - AHEAD, 1e-3), job.waveAt)
end

do
	local H, bot, data = world()
	H.Lane.CampJobs.Start(bot, { kind = "half_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(bot)
	local want = expected(data, data.pull.halfMeetPoint, true)
	check("half pull timed to its own meet point, HalfPullLater after", within(job.plannedSec, want, 1e-3), job.plannedSec)
end

do
	-- At 1:10 the plan puts the :60 wave (10 + AHEAD) * 325 along. Two creeps 550 and 750 further on: the wave's body is
	-- 650 (2 s) early, its front creep 750 (2.3 s); the aggro moves by the body (camp 1 hit early on the front creep,
	-- replay pdg3_C).
	local H, bot, data = world()
	local want = expected(data, data.pull.meetPoint)
	local plan = (10 + AHEAD) * 325
	MakeCreep({ team = 2, x = PATH[1][1] + plan + 750, y = -5000 })
	MakeCreep({ team = 2, x = PATH[1][1] + plan + 550, y = -5000 })
	H.Lane.CampJobs.Start(bot, { kind = "full_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(bot)
	check("wave seen ahead of schedule pulls earlier by its body, not its front creep", within(job.plannedSec, want - 2, 1e-3), job.plannedSec)
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
	check("7.41 radiant safe small camp pulls near :17/:47", t.source == "wave" and t.seconds[1] > 16.5 and t.seconds[1] < 18.5
		and within(t.seconds[2] - t.seconds[1], 30, 1e-6), t.seconds[1])
	-- 7.41 evil_2 (dire_safe_small): its in-game meet (GetLocationAlongLane, from bots' watch positions in
	-- console.9055874680) is ~340 off the Dire top creep path; it used to fall back to the :15 seed (every double pull on
	-- it logged timing=seed). Valve's dire_pull window is 21-23.
	CURRENT_TEAM = 3
	t = PT.For(3, Lane.Top, Vector(-3911, 4829), "small", { Vector(-4002, 5490), Vector(-4005, 5520) }, false, { 15, 45 })
	check("7.41 Dire safe small camp, meet 340 off the path, pulls near :18.7", t.source == "wave" and t.seconds[1] > 18 and t.seconds[1] < 19.5, t.seconds[1])
end

do
	-- WaveAhead by lane kind, one path for every camp: Radiant top and Dire bot are off lanes, Radiant bot and Dire top
	-- safe, mid neither. The same camp geometry on each lane, timed with and without the offsets.
	local function sec(team, lane, ahead)
		local PT = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_top = PATH, radiant_bot = PATH, radiant_mid = PATH,
			dire_top = PATH, dire_bot = PATH }, WaveAhead = ahead } }).Lane.PullTiming
		CURRENT_TEAM = team
		return PT.For(team, lane, Vector(-1600, -6200), "small", { Vector(-1600, -5000) }, false, { 15, 45 }).seconds[1]
	end
	local zero, on = { safe = 0, off = 0 }, { safe = 3, off = 1 }
	local function earlier(team, lane) return sec(team, lane, zero) - sec(team, lane, on) end
	check("WaveAhead: safe lanes 3 s earlier, off lanes 1 s, mid unchanged", within(earlier(2, Lane.Bot), 3, 1e-6)
		and within(earlier(3, Lane.Top), 3, 1e-6) and within(earlier(2, Lane.Top), 1, 1e-6) and within(earlier(3, Lane.Bot), 1, 1e-6)
		and within(earlier(2, Lane.Mid), 0, 1e-6), earlier(2, Lane.Bot) .. " " .. earlier(3, Lane.Top) .. " " .. earlier(2, Lane.Top)
		.. " " .. earlier(3, Lane.Bot) .. " " .. earlier(2, Lane.Mid))
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

do
	-- Live re-timing (slice pull-live): the hit follows the wave every LiveEvery s, keeps its last reading once the wave
	-- cannot be read, and WaveAt moves with it.
	local PT = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH, dire_bot = PATH }, WaveAhead = { safe = AHEAD, off = 0 } } }).Lane.PullTiming
	CURRENT_TEAM = 2
	CREEPS[2], CREEPS[3] = {}, {}
	local meet = Vector(-1600, -5000)
	local timing = PT.For(2, Lane.Bot, SMALL, "small", { meet }, false, { 15, 45 })
	local slot = timing.seconds[1] + 60
	local spawnAt = slot + timing.waveAfter - timing.waveTravel
	local function at(s) return PATH[1][1] + (s - spawnAt + AHEAD) * 325 end
	local live = PT.Track(timing, slot)
	T = spawnAt + 5
	local c = MakeCreep({ team = 2, x = at(T), y = -5000 })
	check("on schedule: the hit is the slot", within(PT.Update(live, T), slot, 1e-6), PT.Update(live, T))
	T = T + 2
	c.loc = Vector(at(T) - 325, -5000)
	check("the wave falls 1 s behind after the first read: the hit moves 1 s later", within(PT.Update(live, T), slot + 1, 1e-6), PT.Update(live, T))
	check("the first reading's shift is kept", within(live.first, 0, 1e-6), live.first)
	check("WaveAt moves with the hit", within(PT.WaveAt(live, T), slot + 1 + timing.waveAfter, 1e-6))
	T = T + 0.1
	c.loc = Vector(at(T) - 650, -5000)
	check("no re-read inside LiveEvery", within(PT.Update(live, T), slot + 1, 1e-6), PT.Update(live, T))
	T = T + 1
	CREEPS[2] = {}
	check("the wave out of reach keeps the last reading", within(PT.Update(live, T), slot + 1, 1e-6), PT.Update(live, T))

	-- The other team's wave on the same lane geometry: its creeps are read, ours ignored.
	CREEPS[2], CREEPS[3] = {}, {}
	local theirs = PT.For(3, Lane.Bot, SMALL, "small", { meet }, false, { 15, 45 })
	local tslot = theirs.seconds[1] + 60
	local tspawn = tslot + theirs.waveAfter - theirs.waveTravel
	T = tspawn + 5
	MakeCreep({ team = 3, x = PATH[1][1] + (5 + theirs.ahead) * 325 + 650, y = -5000 })
	MakeCreep({ team = 2, x = PATH[1][1] + (5 + theirs.ahead) * 325 - 650, y = -5000 })
	check("the other team's wave is read from its own creeps", within(PT.Update(PT.Track(theirs, tslot), T), tslot - 2, 1e-6))
	CREEPS[2], CREEPS[3] = {}, {}
end

finish()
