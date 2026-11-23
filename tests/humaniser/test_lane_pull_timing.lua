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
	require("bots/FunLib/humaniser/camps").ResetCache()
	local data = require("bots/FunLib/humaniser/camps").ByIdx(1)
	local stand = require("bots/FunLib/humaniser/camps").BoxEdgePoint(require("bots/FunLib/humaniser/camps").SpawnerByIdx(1), data.pull.path[1], 150)
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
local function expected(data, meet)
	local walk, prev = 0, SMALL
	for i, p in ipairs(data.pull.path) do
		local q = (i == #data.pull.path) and meet or p
		walk = walk + dist(prev, q)
		prev = q
	end
	return (meet.x - PATH[1][1]) / 325 - AHEAD - walk / 300 - 1.5
end


do
	local PT = LaneFresh({ Enable = true }) and require("bots/FunLib/humaniser/pull_timing")
	CURRENT_TEAM = 2
	local t = PT.For(2, Lane.Bot, nil, "small", { Vector(4050, -6139) }, { 15, 45 })
	check("missing spawner origin falls back to the seed", t.source == "seed" and t.seconds[1] == 15)
	-- 7.41 good_1 (radiant_safe_small): spawner origin and derived meet from the map data.
	t = PT.For(2, Lane.Bot, Vector(3978, -5027), "small", { Vector(4050, -6139) }, { 15, 45 })
	check("7.41 radiant safe small camp pulls near :17/:47", t.source == "wave" and t.seconds[1] > 16.5 and t.seconds[1] < 18.5
		and within(t.seconds[2] - t.seconds[1], 30, 1e-6), t.seconds[1])
	-- 7.41 evil_2 (dire_safe_small): its in-game meet (GetLocationAlongLane, from bots' watch positions in
	-- console.9055874680) is ~340 off the Dire top creep path; it used to fall back to the :15 seed (every double pull on
	-- it logged timing=seed). Valve's dire_pull window is 21-23.
	CURRENT_TEAM = 3
	t = PT.For(3, Lane.Top, Vector(-3911, 4829), "small", { Vector(-4002, 5490), Vector(-4005, 5520) }, { 15, 45 })
	check("7.41 Dire safe small camp, meet 340 off the path, pulls near :18.7", t.source == "wave" and t.seconds[1] > 18 and t.seconds[1] < 19.5, t.seconds[1])
end

do
	-- WaveAhead by lane kind, one path for every camp: Radiant top and Dire bot are off lanes, Radiant bot and Dire top
	-- safe, mid neither. The same camp geometry on each lane, timed with and without the offsets.
	local function sec(team, lane, ahead)
		local PT = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_top = PATH, radiant_bot = PATH, radiant_mid = PATH,
			dire_top = PATH, dire_bot = PATH }, WaveAhead = ahead } }) and require("bots/FunLib/humaniser/pull_timing")
		CURRENT_TEAM = team
		return PT.For(team, lane, Vector(-1600, -6200), "small", { Vector(-1600, -5000) }, { 15, 45 }).seconds[1]
	end
	local zero, on = { safe = 0, off = 0 }, { safe = 3, off = 1 }
	local function earlier(team, lane) return sec(team, lane, zero) - sec(team, lane, on) end
	check("WaveAhead: safe lanes 3 s earlier, off lanes 1 s, mid unchanged", within(earlier(2, Lane.Bot), 3, 1e-6)
		and within(earlier(3, Lane.Top), 3, 1e-6) and within(earlier(2, Lane.Top), 1, 1e-6) and within(earlier(3, Lane.Bot), 1, 1e-6)
		and within(earlier(2, Lane.Mid), 0, 1e-6), earlier(2, Lane.Bot) .. " " .. earlier(3, Lane.Top) .. " " .. earlier(2, Lane.Top)
		.. " " .. earlier(3, Lane.Bot) .. " " .. earlier(2, Lane.Mid))
end


do
	-- The creep timer: the hit puts the neutrals (their walk after it) at the meet point as the front creep is `past`
	-- beyond it, from each creep's place at 325 a second; the slot stands until the front creep and one behind it are
	-- read; one read per LiveEvery. Three creeps 150 apart, the front one 1,000 short of the meet point.
	local PT = LaneFresh({ Enable = true, PullTiming = { LanePaths = { radiant_bot = PATH, dire_bot = PATH }, WaveAhead = { safe = AHEAD, off = 0 } } }) and require("bots/FunLib/humaniser/pull_timing")
	CURRENT_TEAM = 2
	CREEPS[2], CREEPS[3] = {}, {}
	local meet = Vector(-1600, -5000)
	local timing = PT.For(2, Lane.Bot, SMALL, "small", { meet }, { 15, 45 })
	local slot = timing.seconds[1] + 60
	local spawnAt = slot + timing.waveAfter - timing.waveTravel
	local m = timing.meetAlong
	-- The time the wave's expected place (LiveRead's model) is 1,000 short of the meet point.
	T = spawnAt - AHEAD + (m - 1000) / 325
	local full = PT.Timer(timing, slot, 100)
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
	check("full: WaveAt is the back creep at the meet point", within(PT.WaveAt(full), T + 1300 / 325, 1e-6))
	local at = full.hit
	-- 0.3 s on, the wave 1 s behind where it would have walked: every creep 0.3 * 325 forward less 325.
	for _, c in ipairs(CREEPS[2]) do c.loc = Vector(c.loc.x + 0.3 * 325 - 325, -5000) end
	check("no re-read inside LiveEvery", within(PT.Read(full, T + 0.1), at, 1e-6))
	check("a wave 1 s slower moves the full hit 1 s later", within(PT.Read(full, T + 0.3), at + 1, 1e-6), PT.Read(full, T + 0.3) - at)

	-- The neutrals' speed is read again at every read (user 08/11/2026): a camp re-fed with faster neutrals shortens the walk,
	-- so the hit goes out later (the neutrals arrive sooner) by exactly the walk's change.
	local WF = require("bots/FunLib/humaniser/world_facts")
	local tm = PT.For(2, Lane.Bot, SMALL, "small", { meet }, { 15, 45 }, 7)
	local ct = PT.Timer(tm, slot, 100)
	T = spawnAt - AHEAD + (m - 1000) / 325
	local u = { IsNull = function() return false end, GetBaseMovementSpeed = function() return 400 end, IsAlive = function() return true end }
	CREEPS[2], CREEPS[3] = {}, {}
	MakeCreep({ team = 2, x = PATH[1][1] + m - 1000, y = -5000 })
	MakeCreep({ team = 2, x = PATH[1][1] + m - 1150, y = -5000 })
	local before = PT.Read(ct, T)
	WF.FeedNeutral("small", { u }, 7)
	ct.readAt = nil
	local after = PT.Read(ct, T)
	check("a faster pack read at the order shortens the walk and moves the hit later", within(after - before, tm.walkLen / 290 - tm.walkLen / 400, 1e-6) and tm.neutralSpeed == 400, tostring(after - before) .. " " .. tostring(tm.neutralSpeed))

	-- The other team's wave on the same lane geometry: its creeps are read, ours ignored.
	CREEPS[2], CREEPS[3] = {}, {}
	local theirs = PT.For(3, Lane.Bot, SMALL, "small", { meet }, { 15, 45 })
	local tslot = theirs.seconds[1] + 60
	local tspawn = tslot + theirs.waveAfter - theirs.waveTravel
	T = tspawn + 5
	local e = PATH[1][1] + (5 + theirs.ahead) * 325
	MakeCreep({ team = 3, x = e, y = -5000 })
	MakeCreep({ team = 3, x = e - 150, y = -5000 })
	MakeCreep({ team = 2, x = e + 300, y = -5000 })
	local tt = PT.Timer(theirs, tslot, 0)
	check("the other team's wave is read from its own creeps", within(PT.Read(tt, T), T + (theirs.meetAlong - (e - PATH[1][1])) / 325 - theirs.walk, 1e-6) and tt.n == 2, tt.n)
	CREEPS[2], CREEPS[3] = {}, {}
end

finish()
