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
	-- The creep timer (slice pull-half): the hit puts the neutrals (their walk after it) at the meet point as the aimed creep is
	-- `past` beyond it, from each creep's place at 325 a second; the slot stands until the aimed creep and one behind it are
	-- read; one read per LiveEvery. Three creeps 150 apart, the front one 1,000 short of the meet point.
	local PT = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH, dire_bot = PATH }, WaveAhead = { safe = AHEAD, off = 0 } } }).Lane.PullTiming
	CURRENT_TEAM = 2
	CREEPS[2], CREEPS[3] = {}, {}
	local meet = Vector(-1600, -5000)
	local timing = PT.For(2, Lane.Bot, SMALL, "small", { meet }, false, { 15, 45 })
	local slot = timing.seconds[1] + 60
	local spawnAt = slot + timing.waveAfter - timing.waveTravel
	local m = timing.meetAlong
	-- The time the wave's expected place (LiveRead's model) is 1,000 short of the meet point.
	T = spawnAt - AHEAD + (m - 1000) / 325
	local full = PT.Timer(timing, slot, 0, 100)
	check("no creeps read: the slot", within(PT.Read(full, T), slot, 1e-6) and full.n == 0, PT.Read(full, T))
	MakeCreep({ team = 2, x = PATH[1][1] + m - 1000, y = -5000 })
	full.readAt = nil
	check("one creep read: still the slot", within(PT.Read(full, T), slot, 1e-6) and full.n == 1)
	MakeCreep({ team = 2, x = PATH[1][1] + m - 1150, y = -5000 })
	MakeCreep({ team = 2, x = PATH[1][1] + m - 1300, y = -5000 })
	full.readAt = nil
	local walk = timing.walk
	check("full: the front creep 100 past at the neutrals' arrival", within(PT.Read(full, T), T + 1100 / 325 - walk, 1e-6), PT.Read(full, T))
	check("full: the next creep 50 short, the back one 200 short", full.next == -50 and full.back == -200, tostring(full.next) .. " " .. tostring(full.back))
	check("full: WaveAt is the back creep at the meet point", within(PT.WaveAt(full, T), T + 1300 / 325, 1e-6))
	local at = full.hit
	-- 0.3 s on, the wave 1 s behind where it would have walked: every creep 0.3 * 325 forward less 325.
	for _, c in ipairs(CREEPS[2]) do c.loc = Vector(c.loc.x + 0.3 * 325 - 325, -5000) end
	check("no re-read inside LiveEvery", within(PT.Read(full, T + 0.1), at, 1e-6))
	check("a wave 1 s slower moves the full hit 1 s later", within(PT.Read(full, T + 0.3), at + 1, 1e-6), PT.Read(full, T + 0.3) - at)

	-- The other team's wave on the same lane geometry: its creeps are read, ours ignored.
	CREEPS[2], CREEPS[3] = {}, {}
	local theirs = PT.For(3, Lane.Bot, SMALL, "small", { meet }, false, { 15, 45 })
	local tslot = theirs.seconds[1] + 60
	local tspawn = tslot + theirs.waveAfter - theirs.waveTravel
	T = tspawn + 5
	local e = PATH[1][1] + (5 + theirs.ahead) * 325
	MakeCreep({ team = 3, x = e, y = -5000 })
	MakeCreep({ team = 3, x = e - 150, y = -5000 })
	MakeCreep({ team = 2, x = e + 300, y = -5000 })
	local tt = PT.Timer(theirs, tslot, 0, 0)
	check("the other team's wave is read from its own creeps", within(PT.Read(tt, T), T + (theirs.meetAlong - (e - PATH[1][1])) / 325 - theirs.walk, 1e-6) and tt.n == 2, tt.n)
	CREEPS[2], CREEPS[3] = {}, {}
end

do
	-- A half pull's clearance search (phchk1: on camp 1 the second creep aimed 500 past the meet point turned the whole
	-- wave, the neutrals walking towards the front creeps). A camp 900 ahead along the lane and 700 off it: at the
	-- HalfClear aim the front creeps pass within 500 of the neutrals' walk. The search's hit keeps the front two outside
	-- 500 and brings the third inside it, checked here by walking both at 0.01 s, the neutrals stopping at the fight.
	-- The search runs without the live step-in (HalfStepIn false).
	local PT = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH }, NeutralSpeed = { small = 300 }, WaveAhead = { safe = AHEAD, off = 0 }, HalfStepIn = false } }).Lane.PullTiming
	CURRENT_TEAM = 2
	CREEPS[2], CREEPS[3] = {}, {}
	local meet = Vector(-1600, -5000)
	local origin = Vector(-700, -5700)
	local timing = PT.For(2, Lane.Bot, origin, "small", { meet }, true, { 15, 45 })
	local slot = timing.seconds[1] + 60
	local m = timing.meetAlong
	T = slot + timing.waveAfter - timing.waveTravel - AHEAD + (m - 1000) / 325
	local alongs = { m - 1000, m - 1100, m - 1200, m - 1300 }
	for _, a in ipairs(alongs) do MakeCreep({ team = 2, x = PATH[1][1] + a, y = -5000 }) end
	-- The search's model walked at 0.01 s: the neutrals leave the origin 1 s after the hit (HalfNeutralDelay) at 300 for
	-- the stand point `back` short of the meet point, stopping at the fight (a creep from the third back within 500); the
	-- puller (when `speed` is given) starts 400 down the path (HalfHeroStart) and stands there. Returns the nearest the
	-- front two and the third come to the neutrals and to the puller.
	local function walk(h, back, speed)
		local len = dist(origin, meet)
		local f0 = math.max(0, len - (back or 0)) / len
		local stand = Vector(origin.x + (meet.x - origin.x) * f0, origin.y + (meet.y - origin.y) * f0)
		local sl = dist(origin, stand)
		local function at(d) local f = math.min(1, math.max(0, d) / sl) return Vector(origin.x + (stand.x - origin.x) * f, origin.y + (stand.y - origin.y) * f) end
		local nf, nt, hf, ht, stop = math.huge, math.huge, math.huge, math.huge, nil
		for s = 0, len / 300 + 3, 0.01 do
			local n = stop or at((s - 1) * 300)
			local p = speed and at(400 + s * speed)
			local fight = false
			for k, a in ipairs(alongs) do
				local c = Vector(PATH[1][1] + a + 325 * (h + s - T), -5000)
				local d = dist(n, c)
				if k <= 2 then nf = math.min(nf, d) elseif k == 3 then nt = math.min(nt, d) end
				if p then
					local e = dist(p, c)
					if k <= 2 then hf = math.min(hf, e) elseif k == 3 then ht = math.min(ht, e) end
				end
				if k >= 3 and d <= 500 then fight = true end
			end
			if fight and stop == nil then stop = n end
		end
		return nf, nt, hf, ht
	end
	local aim = T + (m + 500 - alongs[2]) / 325 - timing.walk
	local aimClear = walk(aim, 0)
	check("precondition: at the HalfClear aim a front creep comes within 500", aimClear < 500, aimClear)
	local half = PT.Timer(timing, slot, 1, 500, 2)
	local hit = PT.Read(half, T)
	local clear, turn = walk(hit, half.standBack)
	check("half: the search's hit keeps the front two out (" .. math.floor(clear) .. ") and turns the third (" .. math.floor(turn) .. ")",
		clear > 500 and turn <= 500 and half.margin > 0, half.margin)
	-- The search walks a 0.2 s grid, so its fight stop and nearest approaches sit within about 0.2 * 325 / 4 of the fine walk's.
	check("half: hf and hu are the walk's nearest approaches", math.abs(half.clear - clear) <= 20 and math.abs(half.turn - turn) <= 20,
		tostring(half.clear) .. " " .. tostring(half.turn) .. " vs " .. math.floor(clear) .. " " .. math.floor(turn))
	-- A camp off the side of the lane, as camp 1 (phchk2 A_on_4: 1100 off it). The puller reaches the lane ahead of the
	-- neutrals, and a creep within 450 (HalfHeroAggro) of it turns as one within 500 of the neutrals does (the replays: all
	-- four turned with the neutrals 1000 off): a search on the neutrals alone walks a front creep past the puller.
	origin = Vector(-1450, -3900)
	timing = PT.For(2, Lane.Bot, origin, "small", { meet }, true, { 15, 45 })
	local side = PT.Timer(timing, slot, 1, 500, 2)
	local sh = PT.Read(side, T)
	local _, _, heroClear = walk(sh, side.standBack, 330)
	check("precondition: the neutrals-only hit walks a front creep within 450 of the puller", side.margin > 0 and heroClear < 450, heroClear)
	-- Counting the puller only while the neutrals are in reach of it to turn the third (phhar2: the unhit puller turned
	-- nothing), no hit time splits this wave: the search says so (hm <= 0), where the neutrals-only search claimed one.
	local withHero = PT.Timer(timing, slot, 1, 500, 2, 330)
	PT.Read(withHero, T)
	check("half with the puller: no clean split from the side camp (hm <= 0)", withHero.margin ~= nil and withHero.margin <= 0, withHero.margin)
	-- The live step-in from the side camp: the puller holds off the lane while the front two are near the meet point and
	-- steps in to it once they are past (front creeps more than 450 + 50 from where it stands, now and 0.5 s on).
	local stand = Vector(meet.x + (origin.x - meet.x) * 300 / dist(origin, meet), meet.y + (origin.y - meet.y) * 300 / dist(origin, meet))
	local function waveAt(front)
		CREEPS[2] = {}
		for k = 0, 3 do MakeCreep({ team = 2, x = meet.x + front - 100 * k, y = -5000 }) end
		local c = PT.Timer(timing, slot, 1, 500, 2, 330)
		-- The wave's read window follows its expected place, which walks with the clock.
		return PT.StepIn(c, origin, stand, meet, T + (front + 1000) / 325, false, stand)
	end
	local function frontsOut(p, front, gap)
		for k = 0, 1 do
			for _, ahead in ipairs({ 0, 162.5 }) do
				if dist(p, Vector(meet.x + front - 100 * k + ahead, -5000)) <= gap then return false end
			end
		end
		return true
	end
	local near = waveAt(100)
	check("step-in: front two at the meet point, the puller stands where neither comes within 500 now or in 0.5 s",
		frontsOut(near, 100, 500) and dist(near, meet) > dist(stand, meet) - 1, tostring(near.x) .. "," .. tostring(near.y))
	local past = waveAt(700)
	check("step-in: the second creep 600 past, the puller steps on to the meet point", dist(past, meet) < 1, tostring(past.x) .. "," .. tostring(past.y))
	local mid = waveAt(400)
	check("step-in: in between, as far in as keeps the front two out", frontsOut(mid, 400, 500) and dist(mid, meet) < dist(near, meet)
		and dist(mid, meet) > 0, dist(mid, meet))
	-- With the camp's neutrals known (offsets from the puller) it is their places, moved with the puller, that stay 550
	-- (HalfAcquire + buffer) from the front two, not the puller's: neutrals 300 behind it let it stand 300 nearer the wave;
	-- one 300 ahead of it (lane side) holds it back.
	local ul = dist(origin, meet)
	local toCamp = Vector((origin.x - meet.x) / ul * 300, (origin.y - meet.y) / ul * 300)
	local function waveAtWith(front, offs, ranged)
		CREEPS[2] = {}
		for k = 0, 3 do MakeCreep({ team = 2, x = meet.x + front - 100 * k, y = -5000 }) end
		local c = PT.Timer(timing, slot, 1, 500, 2, 330)
		return PT.StepIn(c, origin, stand, meet, T + (front + 1000) / 325, false, stand, offs, ranged)
	end
	local behind = waveAtWith(100, { toCamp })
	check("step-in on the neutrals: 300 behind the puller, it stands nearer the wave than on its own and they stay 550 out",
		dist(behind, meet) < dist(near, meet) - 100 and frontsOut(Vector(behind.x + toCamp.x, behind.y + toCamp.y), 100, 550), dist(behind, meet))
	local ahead = waveAtWith(100, { Vector(-toCamp.x, -toCamp.y) })
	check("step-in on the neutrals: 300 ahead of the puller, it holds at the back point", dist(ahead, meet) >= dist(near, meet) - 1, dist(ahead, meet))
	local over = waveAtWith(700, { toCamp }, true)
	check("step-in on the neutrals: the wave past, ranged neutrals, the line runs on across the lane (HalfStepOver 400)",
		dist(over, meet) > 300 and dist(over, origin) > dist(meet, origin), dist(over, meet))
	-- Melee neutrals close on the puller (phhar9 camp 1: the crossing walked them on to the lane, whole wave 2 of 2).
	local melee = waveAtWith(700, { toCamp })
	check("step-in on the neutrals: the wave past, melee neutrals, the line ends at the meet point", dist(melee, meet) <= 1
		and dist(melee, origin) <= dist(meet, origin) + 1, dist(melee, meet))
	CREEPS[2] = {}
	for _, a in ipairs(alongs) do MakeCreep({ team = 2, x = PATH[1][1] + a, y = -5000 }) end
	-- With the step-in (the default) the hit is the HalfClear aim brought forward by HalfNeutralDelay + HalfStepEarly
	-- (1.5 s), so the neutrals wait off the lane rather than arrive late; no search runs. The lead ends at least 550 off
	-- the lane (HalfHoldOff), where the passing wave cannot reach the puller or the neutrals.
	local T0 = T
	local SP = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH }, NeutralSpeed = { small = 300 }, WaveAhead = { safe = AHEAD, off = 0 } } }).Lane.PullTiming
	T, CURRENT_TEAM = T0, 2
	CREEPS[2] = {}
	for _, a in ipairs(alongs) do MakeCreep({ team = 2, x = PATH[1][1] + a, y = -5000 }) end
	local st = SP.For(2, Lane.Bot, origin, "small", { meet }, true, { 15, 45 })
	local early = SP.Timer(st, slot, 1, 500, 2, 330)
	local eh = SP.Read(early, T)
	local aim2 = T + (st.meetAlong + 500 - alongs[2]) / 325 - st.walk
	check("step-in aim: 1.5 s before the HalfClear aim, no search", math.abs(eh - (aim2 - 1.5)) < 1e-6 and early.margin == nil, eh - aim2)
	local hold = SP.StepBackPoint(origin, meet, PATH)
	check("step-in hold: 550 off the lane, on the way back to the camp", math.abs(hold.y - (-5000)) >= 550 and dist(hold, origin) < dist(meet, origin),
		tostring(hold.x) .. "," .. tostring(hold.y))
	-- The harness pin (HalfStand): with the wave past (the live step-in would walk on to the meet point) the puller still
	-- stands at the nearest point of its line that is the slot's offset off the lane; the offsets go round by slot.
	local HP = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH }, NeutralSpeed = { small = 300 }, WaveAhead = { safe = AHEAD, off = 0 }, HalfStand = { 450, 350 } } }).Lane.PullTiming
	T, CURRENT_TEAM = T0, 2
	CREEPS[2] = {}
	for k = 0, 3 do MakeCreep({ team = 2, x = meet.x + 700 - 100 * k, y = -5000 }) end
	local ht = HP.For(2, Lane.Bot, origin, "small", { meet }, true, { 15, 45 })
	local function pinnedOff(s)
		-- The wave's read window follows the slot, so the clock moves with it.
		local pinned = HP.StepIn(HP.Timer(ht, s, 1, 500, 2, 330), origin, stand, meet, T + (s - slot) + 1700 / 325, false, stand)
		return math.abs(pinned.y - (-5000))
	end
	local off = pinnedOff(slot)
	check("harness pin: the second creep 600 past, the puller holds 450-500 off the lane", off >= 450 and off < 500, off)
	local off2 = pinnedOff(slot + 30)
	check("harness pin: the next slot takes the next offset (350-400)", off2 >= 350 and off2 < 400, off2)
	local full = PT.Timer(timing, slot, 0, 100)
	PT.Read(full, T)
	check("full: no search (hf unset)", full.clear == nil and full.hit ~= nil)
	CREEPS[2], CREEPS[3] = {}, {}
end

do
	-- Slice pull-aggro (Ours.PullOnHero): with the puller's side set (timer.hero) the hit second is the aimed creep's entry
	-- into its own acquisition range of where the puller is hit, less one neutral attack (arrive), the walk to the stand at
	-- the puller's speed, a half's step from it and the lock. The lane runs along y = -5000; the camp straight below the meet.
	local PT = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH }, NeutralSpeed = { small = 300 }, WaveAhead = { safe = AHEAD, off = 0 } } }).Lane.PullTiming
	CURRENT_TEAM = 2
	CREEPS[2], CREEPS[3] = {}, {}
	local meet = Vector(-1600, -5000)
	local origin = Vector(-1600, -6200)
	local from = Vector(-1600, -6000)
	local timing = PT.For(2, Lane.Bot, origin, "small", { meet }, false, { 15, 45 })
	local slot = timing.seconds[1] + 60
	local m = timing.meetAlong
	T = slot + timing.waveAfter - timing.waveTravel - AHEAD + (m - 1000) / 325
	local wave = {}
	for k = 0, 3 do wave[k + 1] = MakeCreep({ team = 2, x = PATH[1][1] + m - 1000 - 150 * k, y = -5000 }) end
	local full = PT.Timer(timing, slot, 0, 100)
	full.hero = { from = from, route = { meet }, speed = 300, lock = 0.4, arrive = 1 }
	local want = T + 500 / 325 - 1 - 1000 / 300 - 0.4
	check("on hero, full: the front creep within 500 of the meet point, less arrive, walk and lock", within(PT.Read(full, T), want, 1e-6), PT.Read(full, T) - want)
	check("on hero, full: ent logged and the neutrals' walk not used", within(full.ent, T + 500 / 325, 1e-6) and full.clear == nil, full.ent)
	wave[1].acq = 600
	full.readAt = nil
	check("on hero, full: a front creep with 600 acquisition enters 100 sooner", within(PT.Read(full, T), want - 100 / 325, 1e-6), PT.Read(full, T) - want)
	wave[1].acq = nil
	-- Half: the stand is beyond every creep's range plus the margin (325 x 0.2 + 24 + 16 = 105) from the lane, on the way back
	-- to the camp in 50 steps: the back creep's 600 puts it 750 off; the third creep (500) is hit 395 off the lane.
	wave[4].acq = 600
	local ht = PT.For(2, Lane.Bot, origin, "small", { meet }, true, { 15, 45 })
	local half = PT.Timer(ht, slot, 1, 500, 2, 300)
	half.hero = { from = from, route = { meet }, speed = 300, lock = 0, arrive = 1 }
	local hit = PT.Read(half, T)
	check("on hero, half: the stand 750 off the lane", half.stand ~= nil and within(half.stand.y, -5750, 1e-6) and within(half.stand.x, -1600, 1e-6),
		half.stand and (half.stand.x .. "," .. half.stand.y))
	local inside = math.sqrt(500 * 500 - 395 * 395)
	local hwant = T + (1300 - inside) / 325 - 1 - 355 / 300 - 250 / 300
	check("on hero, half: the third creep within 500 of the step point 395 off, less arrive, step and walk", within(hit, hwant, 1e-6), hit - hwant)
	-- The step-in, the wave walking in with its expected place at the meet point (T2): gaps of 600 so the front two stay out
	-- of their range plus the margin of the step point; the third creep 200 short of the meet point.
	local T2 = T + 1000 / 325
	CREEPS[2] = {}
	for k = 0, 3 do MakeCreep({ team = 2, x = meet.x + 1000 - 600 * k, y = -5000 }) end
	local here = half.stand
	local function stepAt(c, landIn) return PT.StepInOnHero(c, half.stand, here, T2, landIn, 300, false) end
	local c1 = PT.Timer(ht, slot, 1, 500, 2, 300)
	local hold = stepAt(c1, 2)
	check("step-in on hero: a landing 2 s off (beyond the step's 1.6 s walk) holds at the stand", dist(hold, half.stand) < 1 and c1.stepTo == nil, dist(hold, half.stand))
	check("step-in on hero: no landing known holds too", dist(stepAt(c1, nil), half.stand) < 1)
	local go = stepAt(c1, 0.3)
	local back = Vector(meet.x - 200 + 325 * 0.3, -5000)
	check("step-in on hero: a landing due within the step goes to 395 from where the third creep will be", within(dist(go, back), 395, 1e-3) and c1.stepTo ~= nil,
		dist(go, back))
	check("step-in on hero: once stepped it keeps to that point", dist(stepAt(c1, 2), go) < 1)
	CREEPS[2] = {}
	for k = 0, 3 do MakeCreep({ team = 2, x = meet.x - 100 * k, y = -5000 }) end
	local c2 = PT.Timer(ht, slot, 1, 500, 2, 300)
	local held = stepAt(c2, 0.3)
	check("step-in on hero: creeps 100 apart, the second would turn too: holds and counts it", dist(held, half.stand) < 1 and c2.stepHeld == 1, c2.stepHeld)
	CREEPS[2], CREEPS[3] = {}, {}
end

finish()
