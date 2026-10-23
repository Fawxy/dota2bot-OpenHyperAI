dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local FRONT = Vector(0, -5000)
local SMALL = Vector(-1600, -6200)
local LARGE = Vector(-1000, -6300)

local function spawner(type_, at)
	return { team = 2, type = type_, location = Vector(at.x, at.y, 0), min = Vector(at.x - 150, at.y - 150, 0),
		max = Vector(at.x + 150, at.y + 150, 0), speed = 0 }
end

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = o.loc or FRONT })
	u.lane, u.pos = o.lane or Lane.Bot, o.pos
	return u
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
local function moves(pid) return ActionsOf(pid, "MoveToLocation") end
local function lastMove(pid) local m = moves(pid) return m[#m] and m[#m].args[1] end
local function teleport(bot) local m = lastMove(bot.pid) if m then bot.loc = Vector(m.x, m.y) end end

-- Radiant bot lane: bot core pid 1, bot support pid 5 (the camp-job owner), one enemy laner elsewhere.
-- Default fronts give laneScore -0.8, so the planner wants a full pull from the small camp (:15/:45).
-- `away` puts the support that far east of its stand point (300 speed, so 300 units = 1 s of travel).
local function jobWorld(skill, opts)
	opts = opts or {}
	local H = LaneFresh(opts.cfg or { Enable = true }, { skill = skill, debug = opts.debug, telemetry = opts.telemetry })
	T = opts.t or 70
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = { spawner("small", SMALL) }
	if opts.large then table.insert(SPAWNERS, spawner("large", LARGE)) end
	H.Lane.Camps.ResetCache()
	local C = H.Lane.Camps
	local data = C.ByIdx(1)
	local stand = C.BoxEdgePoint(C.SpawnerByIdx(1), data.pull.path[1], 150)
	local core = unit({ pid = 1, pos = 1 })
	local support = unit({ pid = 5, pos = 5, loc = Vector(stand.x + (opts.away or 0), stand.y) })
	unit({ pid = 10, team = 3, pos = 3, lane = Lane.Top })
	return H, core, support, data, stand
end

local function frame(H, bot, t)
	T = t
	local d = H.Lane.CampJobDesire(bot)
	local acted = d > 0 and H.Lane.CampJobThink(bot)
	return d, acted
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, s) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err) end
	return printed
end

do
	local J = LaneFresh({ Enable = true }).Lane.CampJobs
	check("next aggro at 12.0 is :15", J.NextAggroTime(12.0, { 15, 45 }, 60) == 15)
	check("next aggro at 16.0 is :45", J.NextAggroTime(16.0, { 15, 45 }, 60) == 45)
	check("next aggro at 50.0 wraps to 1:15", J.NextAggroTime(50.0, { 15, 45 }, 60) == 75)
end

do
	local J = LaneFresh({ Enable = true }).Lane.CampJobs
	check("window opens travel + slack before the aggro", J.WindowOpen(63, 75, 9) == true)
	check("window closed just before", J.WindowOpen(62.9, 75, 9) == false)
	check("window still open just after the aggro", J.WindowOpen(77.0, 75, 9) == true)
	check("window closed past the late margin", J.WindowOpen(77.1, 75, 9) == false)
end

-- A fixed Gaussian draw of +1: u1 = e^-0.5, u2 = 1 (cos 2pi = 1).
local function jitteredAggro(skill)
	local H, _, support = jobWorld(skill)
	H.Lane.Config.SkillOf(support)
	SetRandomSequence({ math.exp(-0.5), 1.0 })
	check("precondition: job starts at skill " .. skill, H.Lane.CampJobs.Start(support, { kind = "full_pull", campIdx = 1 }))
	local base = H.Lane.CampJobs.NextAggroTime(T - 2, { 15, 45 }, 60)
	return H.Lane.CampJobs.Current(support).aggroAt - base
end

do
	local low, high = jitteredAggro(0), jitteredAggro(1)
	check("skill 0 aggro is 1.5 s off the seed", math.abs(low - 1.5) < 1e-3, low)
	check("skill 1 aggro is 0.2 s off the seed", math.abs(high - 0.2) < 1e-3, high)
end

do
	local H, _, support, data = jobWorld(1)
	local s = H.Lane.CampJobs.AggroSecondsFor("half_pull", data)
	check("half pull uses the half seconds", #s == 2 and s[1] == 17 and s[2] == 47)
	check("full pull uses the pull seconds", H.Lane.CampJobs.AggroSecondsFor("full_pull", data)[1] == 15)
	H.Lane.CampJobs.Start(support, { kind = "half_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(support)
	local half, full = data.pull.halfMeetPoint, data.pull.meetPoint
	check("half pull planned on :17", job.plannedSec == 17, job.plannedSec)
	check("half pull meets at the half meet point", dist(job.meet, half) < 1e-6 and dist(half, full) > 400)
end

do
	local J = LaneFresh({ Enable = true }).Lane.CampJobs
	local neutral = MakeNeutral({ x = 0, y = 0 })
	local enemyCreep = MakeCreep({ team = 3, x = 0, y = 0 })
	local list = {}
	for i = 1, 4 do table.insert(list, MakeCreep({ team = 2, x = 0, y = 0, target = neutral })) end
	table.insert(list, MakeCreep({ team = 2, x = 0, y = 0, target = enemyCreep }))
	check("4 of 5 on neutrals diverts 0.8", near(J.MeasureDivert(list, 5), 0.8))
	check("full at exactly 0.8 is weak", J.Grade("full_pull", 0.8) == "mistake:weak-pull")
	check("full at 0.85 is ok", J.Grade("full_pull", 0.85) == "ok")
	check("full with nothing diverted", J.Grade("full_pull", 0) == "mistake:no-divert")
	check("half at 0.45 is ok", J.Grade("half_pull", 0.45) == "ok")
	check("half at 0.7 pulled the whole wave", J.Grade("half_pull", 0.7) == "mistake:half->full")
	check("half at 0.2 is weak", J.Grade("half_pull", 0.2) == "mistake:weak-pull")
end

do
	-- Pull at 1:45 from the stand point: the start window is 1:42 to 1:47.
	local H, core, support = jobWorld(0.9, { t = 103 })
	check("owner desire inside the window", near(H.Lane.CampJobDesire(support), 0.7))
	check("owner has a full pull", H.Lane.CampJobs.Current(support).kind == "full_pull")
	check("non-owner has no desire", H.Lane.CampJobDesire(core) == 0 and H.Lane.CampJobs.Current(core) == nil)

	H, core, support = jobWorld(0.9, { t = 92 })
	check("no desire 10 s before the window", H.Lane.CampJobDesire(support) == 0 and H.Lane.CampJobs.Current(support) == nil)

	H, core, support = jobWorld(0.9, { t = 103, cfg = { Enable = true, FullPull = false } })
	check("no desire with FullPull off", H.Lane.CampJobDesire(support) == 0 and H.Lane.CampJobs.Current(support) == nil)

	-- A live lane-fight commit (lane_fight's probe) blocks the start, the scheduled pull with gate=lanefight.
	H, core, support = jobWorld(0.9, { t = 103, telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	H.Lane.Hooks.SetFightProbe(function(b) return b == support end)
	local gated = 0
	check("no camp job while committed to a lane kill", H.Lane.CampJobDesire(support) == 0 and H.Lane.CampJobs.Current(support) == nil)
	for _, l in ipairs(lines) do if l:find("ev=lane_plan ", 1, true) and l:find("gate=lanefight", 1, true) then gated = gated + 1 end end
	check("... logged as lane_plan gate=lanefight", gated == 1, table.concat(lines, "\n"))
	check("a non-forced Start is refused too", not H.Lane.CampJobs.Start(support, { kind = "full_pull", campIdx = 1 }))
	check("a forced Start (a human's order) is not", H.Lane.CampJobs.Start(support, { kind = "full_pull", campIdx = 1, forced = true }))
end

-- Runs a scheduled full pull from 1:12.5 (the window opens at 1:12 from the stand) through aggro and lead to the meet point; returns the job.
local function runToWatch(H, support, neutral, leadAt)
	frame(H, support, 72.5)
	local job = H.Lane.CampJobs.Current(support)
	frame(H, support, job.aggroAt)
	neutral.target = support
	frame(H, support, leadAt)
	teleport(support)
	frame(H, support, leadAt + 0.1)
	teleport(support)
	frame(H, support, leadAt + 0.2)
	return job
end

do
	local H, _, support = jobWorld(1)
	local neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	frame(H, support, 72.5)
	local job = H.Lane.CampJobs.Current(support)
	frame(H, support, job.aggroAt)
	neutral.target = support
	local d = frame(H, support, 80)
	check("precondition: leading at 1:20", job.phase == "lead")
	check("desire held while leading outside the window", near(d, 0.7) and not H.Lane.CampJobs.WindowOpen(80, job.aggroAt, 0))
	teleport(support)
	frame(H, support, 80.1)
	teleport(support)
	frame(H, support, 80.2)
	d = frame(H, support, 84)
	check("desire held while watching", near(d, 0.7) and job.phase == "watch")
	frame(H, support, 88.3)
	check("job done after the watch", job.phase == "done")
	check("no desire once done", H.Lane.CampJobDesire(support) == 0)

	H, _, support = jobWorld(1)
	neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	job = runToWatch(H, support, neutral, 80)
	frame(H, support, 84)
	check("precondition: watching", job.phase == "watch")
	T = 90.1
	check("hard stop 15 s after the aggro", job.aggroAt + 15 < 90.1 and H.Lane.CampJobDesire(support) == 0)
	check("hard stop ends the job early", job.phase == "return")
end

do
	local H, _, support = jobWorld(1, { away = 900 })
	frame(H, support, 70)
	check("precondition: travelling", H.Lane.CampJobs.Current(support).phase == "travel")
	H.Orders.Post(2, { type = "LANE_HANDSOFF", sourceKey = "ping", issuerPID = 0, lane = Lane.Bot, duration = 30,
		maxResponders = 1, onlyPIDs = { 5 }, delayKind = "ping" })
	T = 72
	check("precondition: handsoff accepted", H.Orders.GetAcceptedForLane(support, "LANE_HANDSOFF", Lane.Bot) ~= nil)
	local before = #ACTIONS
	check("handsoff drops the desire", H.Lane.CampJobDesire(support) == 0)
	check("handsoff stops the job", H.Lane.CampJobThink(support) == false and #ACTIONS == before)
end

do
	local H, core, support = jobWorld(1)
	local neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local job = runToWatch(H, support, neutral, 76.5)
	frame(H, support, 85)
	check("precondition: pull done at cycle second 25", job.phase == "done")
	core.hp = 30
	T = 86
	local c = H.Lane.LanePlanner.Plan(support, H.Lane.LaneState.ForBot(support))
	check("no second technique in the cycle", c.tech == "none" and c.reason == "one per cycle (full_pull)", c.tech .. " " .. c.reason)
	check("no second job in the cycle", H.Lane.CampJobDesire(support) == 0)
end

do
	local H, _, support = jobWorld(1, { t = 60 })
	H.Lane.CampJobs.Start(support, { kind = "full_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(support)
	T = job.aggroAt - 12
	H.Lane.CampJobThink(support)
	check("rotation not planned 12 s before the pull", H.Lane.Hooks.IsRotationPlanned(support) == false)
	T = job.aggroAt - 8
	H.Lane.CampJobThink(support)
	check("precondition: waiting at the camp", job.phase == "wait")
	check("rotation planned 8 s before the pull", H.Lane.Hooks.IsRotationPlanned(support) == true)
end

do
	local H, _, support, data, stand = jobWorld(1, { away = 900 })
	local neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local d, acted = frame(H, support, 70)
	check("travel issues a move to the stand point", acted and #moves(5) == 1 and dist(lastMove(5), stand) <= 20 + 1e-6)
	teleport(support)
	local job = H.Lane.CampJobs.Current(support)
	frame(H, support, job.aggroAt - 0.5)
	local before = #ACTIONS
	frame(H, support, job.aggroAt)
	local a = ACTIONS[#ACTIONS]
	check("one attack at the aggro time", #ACTIONS == before + 1 and a.kind == "AttackUnit" and a.args[1] == neutral and a.args[2] == true)
	support.loc = Vector(SMALL.x, SMALL.y)
	before = #ACTIONS
	frame(H, support, job.aggroAt + 0.05)
	check("holds the attack order until the hit is confirmed", #ACTIONS == before and job.phase == "aggro")
	-- Read between frames: the attack's own time is the aggro, not the frame that sees it (a melee hit: no flight).
	support.lastAttack = job.aggroAt + 0.07
	frame(H, support, job.aggroAt + 0.1)
	check("records the aggro at the attack time", near(job.actualAggro, job.aggroAt + 0.07), job.actualAggro)
	check("leads out along the first path waypoint", dist(lastMove(5), data.pull.path[1]) <= 20 + 1e-6)
	teleport(support)
	frame(H, support, job.aggroAt + 0.2)
	check("final waypoint is the meet point within noise", #job.path == 2 and dist(lastMove(5), job.meet) <= 20 + 1e-6)
end

do
	local H, core, support = jobWorld(1, { away = 900 })
	frame(H, support, 70)
	check("precondition: travelling", H.Lane.CampJobs.Active(support))
	core.hp = 30
	T = 70.6
	check("partner endangered drops the desire", H.Lane.CampJobDesire(support) == 0)
	check("partner endangered aborts the job", H.Lane.CampJobs.Current(support).phase == "return")
end

do
	local H, _, support = jobWorld(1, { debug = true })
	local neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local job
	local lines = capture(function()
		job = runToWatch(H, support, neutral, 76.5)
		for _ = 1, 4 do MakeCreep({ team = 2, x = job.meet.x, y = job.meet.y, target = neutral }) end
		frame(H, support, 77)
		frame(H, support, 85)
	end)
	local line
	for _, l in ipairs(lines) do if l:find("[H:lane] job pid", 1, true) then line = l end end
	check("job line printed", line ~= nil)
	local pattern = "^%[H:lane%] job pid=%d+ kind=%w+ camp=%d+ key=[%w_%-]+ aggro=%-?%d+%.%d planned=%-?%d+%.%d divert=%d%.%d%d grade=%S+$"
	check("job line format", line ~= nil and line:match(pattern) ~= nil, line)
	check("whole wave diverted grades ok", line ~= nil and line:find("kind=full camp=1 key=radiant_safe_small", 1, true)
		and line:find("planned=15.0 divert=1.00 grade=ok", 1, true), line)
end

local function traceEvent(lines)
	for _, l in ipairs(lines) do
		if l:find("ev=lane_pull_trace ", 1, true) then
			local f = {}
			for k, v in l:gmatch("(%w+)=(%S+)") do f[k] = tonumber(v) or v end
			return f
		end
	end
end

do
	-- The camp reaches the meet a second before the wave; two creeps hit it, then the other two: never all four at
	-- once, so the peak is half the wave while all four were diverted.
	local H, _, support = jobWorld(1, { telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	local neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local job = runToWatch(H, support, neutral, 76.5)
	neutral.loc = Vector(job.meet.x, job.meet.y)
	frame(H, support, 77)
	local creeps = {}
	for i = 1, 4 do creeps[i] = MakeCreep({ team = 2, x = job.meet.x, y = job.meet.y, target = i <= 2 and neutral or nil }) end
	frame(H, support, 78)
	for i = 1, 4 do creeps[i].target = i > 2 and neutral or nil end
	frame(H, support, 79)
	frame(H, support, 85)
	check("precondition: pull graded", job.phase == "done")
	local e = traceEvent(lines)
	check("pull trace logged once the pull is graded", e ~= nil and e.kind == "full" and e["end"] == "mistake:weak-pull", table.concat(lines, "\n"))
	check("every creep that hit the camp counts, not only at once", e.ever == 4 and e.waveMax == 4 and near(e.peak, 0.5), e and (e.ever .. " " .. e.peak))
	check("camp and wave arrivals are timed from the hit", near(e.nIn, 77 - job.actualAggro) and near(e.wave, 78 - job.actualAggro) and e.nAtWave == 1,
		e and (e.nIn .. " " .. e.wave))

	local core
	H, core, support = jobWorld(1, { away = 900, telemetry = { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	frame(H, support, 70)
	core.hp = 30
	T = 70.6
	H.Lane.CampJobDesire(support)
	check("precondition: aborted on the walk", H.Lane.CampJobs.Current(support).phase == "return")
	check("no trace for a pull that was never hit", traceEvent(lines) == nil)
end

do
	-- Our creep already at the meet point: the planner's pull is not started, logged as lane_plan gate=lane-at-meet.
	local H, _, support, data = jobWorld(0.9, { t = 103, telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	MakeCreep({ team = 2, x = data.pull.meetPoint.x, y = data.pull.meetPoint.y + 300 })
	frame(H, support, 103)
	local gated = false
	for _, l in ipairs(lines) do if l:find("ev=lane_plan ", 1, true) and l:find("gate=lane-at-meet", 1, true) then gated = true end end
	check("no pull with our creeps at the meet point", gated and H.Lane.CampJobs.Current(support) == nil, table.concat(lines, "\n"))

	-- They walk in while the support waits at the camp: the job ends before the hit instead of drawing the camp.
	local neutral
	H, _, support, data = jobWorld(1, { telemetry = { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	frame(H, support, 72.5)
	local job = H.Lane.CampJobs.Current(support)
	check("precondition: pull started", job ~= nil)
	frame(H, support, job.aggroAt - 1)
	MakeCreep({ team = 2, x = job.meet.x, y = job.meet.y })
	local before = #ActionsOf(5, "AttackUnit")
	frame(H, support, job.aggroAt)
	local aborted = false
	for _, l in ipairs(lines) do if l:find("ev=lane_job_abort ", 1, true) and l:find("reason=lane-at-meet", 1, true) then aborted = true end end
	check("creeps reaching the meet before the hit abort the pull", aborted and job.phase == "return" and #ActionsOf(5, "AttackUnit") == before)

	H, _, support = jobWorld(1, { cfg = { Enable = true, PullLaneGate = false } })
	neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	frame(H, support, 72.5)
	job = H.Lane.CampJobs.Current(support)
	frame(H, support, job.aggroAt - 1)
	MakeCreep({ team = 2, x = job.meet.x, y = job.meet.y })
	before = #ActionsOf(5, "AttackUnit")
	frame(H, support, job.aggroAt)
	check("with PullLaneGate off the camp is still hit", #ActionsOf(5, "AttackUnit") == before + 1 and job.phase == "aggro")
end

-- A creep path along the stub bot lane (y = -5000), so the small camp's pull is wave-timed: the :00 wave reaches its
-- meet (-1600, -5000) after 7,800 / 325 = 24 s.
local WAVE_CFG = { Enable = true, PullTiming = { LanePaths = { radiant_bot = { { -9400, -5000 }, { 7000, -5000 } } } } }

do
	-- Double pull, hard camp first: the large camp is hit from its side facing the small camp, then the small camp on its
	-- own wave-timed second (about 24 - (300 + 900) / 290 - 1.5 = 18.36), and both are led to the small camp's meet.
	local H, _, support = jobWorld(1, { large = true, cfg = WAVE_CFG })
	local small = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local large = MakeNeutral({ x = LARGE.x, y = LARGE.y })
	frame(H, support, 72.5)
	local job = H.Lane.CampJobs.Current(support)
	check("two camps at 1.0 make a double pull", job ~= nil and job.kind == "double_pull" and job.secondCampIdx == 2, job and job.kind)
	check("the small camp keeps its wave-timed second", job.timing == "wave" and math.abs(job.plannedSec - 18.36) < 0.05, job.plannedSec)
	-- About 391 of walk between the stands at 300, plus DoublePullHitGap.
	check("the hard camp is hit first, its walk to the small camp ahead of the small camp's hit",
		job.activeCamp == 2 and job.chain ~= nil and math.abs(job.chain.aggroAt - job.aggroAt - 2.30) < 0.05, job.chain and job.chain.aggroAt - job.aggroAt)
	teleport(support)
	frame(H, support, job.aggroAt)
	local a = ActionsOf(5, "AttackUnit")
	check("aggroes the hard camp", #a == 1 and a[1].args[1] == large)
	large.target = support
	frame(H, support, job.aggroAt + 0.1)
	check("hard camp on the bot: walks to the small camp", job.activeCamp == 1 and job.phase == "travel" and job.chain == nil and job.actualAggro == nil, job.phase)
	teleport(support)
	frame(H, support, job.aggroAt)
	a = ActionsOf(5, "AttackUnit")
	check("then aggroes the small camp", #a == 2 and a[2].args[1] == small)
	frame(H, support, job.aggroAt + 0.1)
	check("the hard camp chasing the bot does not confirm the small camp's aggro", job.phase == "aggro", job.phase)
	support.lastAttack = T
	frame(H, support, T + 0.1)
	check("the small camp's hit is the graded aggro; both are led to its meet", job.phase == "lead" and job.actualAggro ~= nil
		and dist(job.path[#job.path], job.meet) <= 20 + 1e-6)
end

do
	-- Off-lane large seeds are unverified; the start line says so. The camp is Dire's: the job uses Radiant's data on it.
	local H = LaneFresh({ Enable = true }, { skill = 1, debug = true })
	T = 70
	CURRENT_TEAM = 2
	SPAWNERS = { spawner("large", Vector(-1600, 6200)) }
	SPAWNERS[1].team = 3
	H.Lane.Camps.ResetCache()
	local bot = unit({ pid = 5, pos = 4, lane = Lane.Top, loc = Vector(-1600, 5900) })
	local lines = capture(function() H.Lane.CampJobs.Start(bot, { kind = "full_pull", campIdx = 1 }) end)
	check("job start notes unverified data", lines[1] ~= nil and lines[1]:find("key=radiant_off_large data=unverified", 1, true), lines[1])
end

do
	local H, _, support = jobWorld(1)
	unit({ pid = 0, bot = false, lane = Lane.Top, loc = Vector(5000, 5000) })
	local said = {}
	H.Orders.SetAnnouncer(function(_, key) table.insert(said, key) end)
	H.Lane.CampJobs.Start(support, { kind = "half_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(support)
	T = job.aggroAt - 6
	H.Lane.CampJobThink(support)
	check("no telegraph 6 s before the pull", #said == 0)
	T = job.aggroAt - 5
	H.Lane.CampJobThink(support)
	T = job.aggroAt - 4
	H.Lane.CampJobThink(support)
	check("half pull telegraphed once 5 s before", #said == 1 and said[1] == "say_lane_half_pull", said[1])
end

do
	-- No hit lands and no neutral turns on the bot: the job gives up as a logged mistake.
	local H, _, support = jobWorld(1, { debug = true })
	MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local job
	local lines = capture(function()
		frame(H, support, 72.5)
		job = H.Lane.CampJobs.Current(support)
		frame(H, support, job.aggroAt)
		frame(H, support, job.aggroAt + 1.9)
		check("precondition: still waiting on the hit", job.phase == "aggro")
		frame(H, support, job.aggroAt + 2.0)
	end)
	check("unconfirmed aggro times out", job.phase == "return" and job.actualAggro == nil)
	local abortLine, jobLine
	for _, l in ipairs(lines) do
		if l:find("[H:lane] job-abort", 1, true) then abortLine = l end
		if l:find("[H:lane] job pid", 1, true) then jobLine = l end
	end
	check("timeout logged as an abort", abortLine ~= nil and abortLine:find("reason=mistake:no-aggro", 1, true), abortLine)
	check("timeout is not a graded job line", jobLine == nil, jobLine)
end

do
	-- A safety abort after the aggro is not graded: it would count against the camp's timing.
	local H, core, support = jobWorld(1, { debug = true })
	local neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local lines = capture(function()
		runToWatch(H, support, neutral, 76.5)
		core.hp = 30
		frame(H, support, 77.5)
	end)
	local abortLine, jobLine
	for _, l in ipairs(lines) do
		if l:find("[H:lane] job-abort", 1, true) then abortLine = l end
		if l:find("[H:lane] job pid", 1, true) then jobLine = l end
	end
	check("partner abort logged on the abort line", abortLine ~= nil and abortLine:find("reason=partner-low-hp", 1, true), abortLine)
	check("partner abort is not a graded job line", jobLine == nil, jobLine)
end

do
	local H, _, support = jobWorld(1)
	check("no camp job: laning last hits are not held back", H.Lane.CampJobActive(support) == false)
	frame(H, support, 72.5)
	check("running camp job holds back laning last hits", H.Lane.CampJobActive(support) == true)
	H, _, support = jobWorld(1, { cfg = { Enable = false } })
	check("lane off: never holds back last hits", H.Lane.CampJobActive(support) == false and next(GETUNITLIST_CALLS) == nil)
end

local function pullChat(debug, text)
	local H, _, support = jobWorld(1, { debug = debug })
	local human = unit({ pid = 0, bot = false, loc = Vector(-1500, -6000) })
	local far = unit({ pid = 2, pos = 3, loc = Vector(5000, 0) })
	H.Tick(support)
	T = T + 0.5
	capture(function()
		for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = 0, string = text, team_only = false }) end
	end)
	return H, support, far
end

do
	local H, support = pullChat(false, "!hpulltest 1")
	check("hpulltest ignored with debug off", H.Lane.CampJobs.Current(support) == nil)
	local far
	H, support, far = pullChat(true, "!hpulltest 1")
	local job = H.Lane.CampJobs.Current(support)
	check("hpulltest forces a full pull on the nearest bot", job ~= nil and job.forced == true and job.kind == "full_pull")
	check("hpulltest leaves the other bots", H.Lane.CampJobs.Current(far) == nil)
	H, support = pullChat(true, "!hpulltest 1 half")
	job = H.Lane.CampJobs.Current(support)
	check("hpulltest half", job ~= nil and job.kind == "half_pull")
end

do
	local H, _, support = jobWorld(1, { t = 103, away = 600, cfg = { Enable = false } })
	check("lane off: no camp-job desire", H.Lane.CampJobDesire(support) == 0)
	check("lane off: camp-job think is inert", H.Lane.CampJobThink(support) == false and #ACTIONS == 0)
	check("lane off: no unit scans", next(GETUNITLIST_CALLS) == nil)
	H, _, support = jobWorld(1, { t = 103, away = 600 })
	check("defaults inside the window: desire", near(H.Lane.CampJobDesire(support), 0.7))
	check("defaults inside the window: one move", H.Lane.CampJobThink(support) == true and #moves(5) == 1 and #ACTIONS == 1)
end

local function lineWith(lines, text)
	local found
	for _, l in ipairs(lines) do if l:find(text, 1, true) then found = l end end
	return found
end

local function markStacked(H)
	H.Lane.Stacking.NoteStackAttempt(1, 1, 3)
	H.Lane.Stacking.NoteStackOutcome(1, 1, 6)
	check("precondition: camp marked stacked", H.Lane.Stacking.IsStacked(1))
end

do
	-- Farm's GetDesire registers the job whether or not farm wins; here another mode wins every frame.
	local H, _, support = jobWorld(1, { debug = true, away = 900 })
	markStacked(H)
	local job
	local lines = capture(function()
		T = 72.5
		check("precondition: the desire registers a job", near(H.Lane.CampJobDesire(support), 0.7))
		job = H.Lane.CampJobs.Current(support)
		check("precondition: registering commits the cycle", H.Lane.LanePlanner.Committed(support) ~= nil)
		T = 73.0
		check("out-bid for 0.5 s: job kept", near(H.Lane.CampJobDesire(support), 0.7))
		T = 73.6
		check("out-bid for over 1 s: desire dropped", H.Lane.CampJobDesire(support) == 0)
		check("pre-empted job no longer holds back last hits", H.Lane.CampJobActive(support) == false)
		check("pre-empted before acting: the cycle's technique is free", H.Lane.LanePlanner.Committed(support) == nil)
		-- Farm wins later inside the same start window: the lost attempt is not run late.
		for t = job.aggroAt, job.aggroAt + 1.5, 0.5 do frame(H, support, t) end
	end)
	local abortLine = lineWith(lines, "[H:lane] job-abort")
	check("pre-emption logged on the abort line", abortLine ~= nil and abortLine:find("reason=preempted", 1, true), abortLine)
	check("the same aggro is not registered again", #ActionsOf(5) == 0 and select(2, string.gsub(table.concat(lines, "\n"), "job%-start", "")) == 1)
	check("no no-camp verdict for a camp never reached", lineWith(lines, "no-camp") == nil)
	check("pre-emption leaves the stack mark", H.Lane.Stacking.IsStacked(1))
end

do
	-- Control: a job farm has run keeps the cycle when it is later out-bid; a stun inside farm mode is no pre-emption.
	local H, _, support = jobWorld(1, { away = 900 })
	frame(H, support, 72.5)
	T = 73.0
	H.Lane.CampJobDesire(support)
	T = 73.6
	check("out-bid after acting: desire dropped", H.Lane.CampJobDesire(support) == 0)
	check("out-bid after acting: the cycle stays used", H.Lane.LanePlanner.Committed(support) ~= nil)

	H, _, support = jobWorld(1, { away = 900 })
	frame(H, support, 72.5)
	support.mode = dota.BotMode.Farm
	local d
	for t = 73, 74.5, 0.5 do T = t d = H.Lane.CampJobDesire(support) end
	check("farm active but not thinking (stunned): job kept", near(d, 0.7) and H.Lane.CampJobs.Current(support).phase == "travel")
end

do
	-- Still walking well past the aggro second, with no neutral anywhere: the box was never seen.
	-- 10 s away, so the job starts as the window opens at 1:02 and the bot then never moves.
	local H, _, support = jobWorld(1, { debug = true, away = 3000 })
	markStacked(H)
	local job
	local lines = capture(function()
		frame(H, support, 63)
		job = H.Lane.CampJobs.Current(support)
		for t = job.aggroAt, job.aggroAt + 1.5, 0.5 do frame(H, support, t) end
		check("precondition: still walking after the aggro second", job.phase == "travel")
		frame(H, support, job.aggroAt + 2.0)
	end)
	local abortLine = lineWith(lines, "[H:lane] job-abort")
	check("late arrival aborts as late", job.phase == "return" and abortLine ~= nil and abortLine:find("reason=late", 1, true), abortLine)
	check("late arrival is not a no-camp verdict", lineWith(lines, "no-camp") == nil)
	check("late arrival leaves the stack mark", H.Lane.Stacking.IsStacked(1))

	-- Control: at the stand with the box empty (after walking in to the spawner origin), the stack really is gone.
	H, _, support = jobWorld(1, { debug = true })
	markStacked(H)
	lines = capture(function()
		frame(H, support, 72.5)
		job = H.Lane.CampJobs.Current(support)
		teleport(support)
		frame(H, support, job.aggroAt)
		frame(H, support, job.aggroAt + 1.0)
	end)
	abortLine = lineWith(lines, "[H:lane] job-abort")
	check("at the stand, empty box: no-camp", abortLine ~= nil and abortLine:find("reason=mistake:no-camp", 1, true), abortLine)
	check("at the stand, empty box: stack cleared", H.Lane.Stacking.IsStacked(1) == false)
end

do
	local H, _, support = jobWorld(0.9, { t = 103 })
	support.hp = 30
	check("low-HP owner starts no job", H.Lane.CampJobDesire(support) == 0 and H.Lane.CampJobs.Current(support) == nil)

	H, _, support = jobWorld(1, { debug = true })
	capture(function() frame(H, support, 72.5) end)
	local job = H.Lane.CampJobs.Current(support)
	support.hp = 30
	local d
	local lines = capture(function()
		T = 72.8
		d = H.Lane.CampJobDesire(support)
	end)
	local abortLine = lineWith(lines, "[H:lane] job-abort")
	check("low HP mid-job: desire dropped and job aborted", d == 0 and job.phase == "return")
	check("low HP abort reason", abortLine ~= nil and abortLine:find("reason=low-hp", 1, true), abortLine)
end

do
	-- mode_farm_generic starting a run: Think no longer runs the job, so it ends at once.
	local H, _, support = jobWorld(1, { debug = true })
	capture(function() frame(H, support, 72.5) end)
	local job = H.Lane.CampJobs.Current(support)
	local lines = capture(function() H.Lane.CampJobAbort(support, "run") end)
	local abortLine = lineWith(lines, "[H:lane] job-abort")
	check("run start aborts the job", job.phase == "return" and abortLine ~= nil and abortLine:find("reason=run", 1, true), abortLine)
	check("aborted job no longer owns farm's frame", H.Lane.CampJobThink(support) == false)
	local src = io.open(HARNESS_DIR .. "/../../bots/mode_farm_generic.lua", "r"):read("a")
	local runStart = src:find("runMode = true;", 1, true)
	local abortAt = src:find('J.Humaniser.Lane.CampJobAbort(bot, "run")', 1, true)
	check("farm aborts the job where the run starts", runStart ~= nil and abortAt ~= nil and abortAt > runStart and abortAt - runStart < 200)
	check("farm skips the job's Think during a run", src:find("if not runMode and J.Humaniser.Lane.CampJobThink(bot) then return end", 1, true) ~= nil)
end

-- Intent arbitration (task 09): the job's desire reaches farm as a CAMP_JOB floor claim over a raw 0.
do
	local H, _, support = jobWorld(1, { away = 900 })
	local I = H.Intent
	local FARM, LANING, RETREAT = dota.BotMode.Farm, dota.BotMode.Laning, dota.BotMode.Retreat
	T = 70
	local d = H.Lane.CampJobDesire(support)
	check("precondition: a job registers", near(d, 0.7), d)
	local raw = H.Lane.CampJobRawDesire(support, d)
	check("intent on: farm's raw desire is 0", raw == 0, raw)
	check("intent on: the claim carries the job's desire", near(I.Resolve(support, FARM, raw), 0.7), I.Resolve(support, FARM, raw))
	check("overlay names the job claim", I.Explain(support, FARM):find("by lane:full_pull", 1, true) ~= nil, I.Explain(support, FARM))
	T = 70.1
	check("the floor lasts only its frame", near(I.Resolve(support, FARM, 0), 0), I.Resolve(support, FARM, 0))

	-- Survival outranks the job: a low-HP bot whose retreat wants out gets farm capped below retreat.
	T = 70.2
	d = H.Lane.CampJobDesire(support)
	support.hp = 20
	raw = H.Lane.CampJobRawDesire(support, d)
	I.Resolve(support, RETREAT, 0.7)
	check("low HP: retreat beats the job's floor", near(I.Resolve(support, FARM, raw), 0.65), I.Resolve(support, FARM, raw))
	support.hp = 100

	-- The active laning mode's dwell bonus must not push the pull late.
	support.mode = LANING
	I.Tick(support)
	T = 70.5
	-- Back at full HP: retreat's own scoring in this round lifts the survival cap of the last one.
	I.Resolve(support, RETREAT, 0.3)
	d = H.Lane.CampJobDesire(support)
	raw = H.Lane.CampJobRawDesire(support, d)
	check("no laning dwell bonus against a job", near(I.Resolve(support, LANING, 0.66), 0.66), I.Resolve(support, LANING, 0.66))
	check("job's farm beats laning", I.Resolve(support, FARM, raw) > I.Resolve(support, LANING, 0.66))
end
-- The dwell-bonus suspension covers only the approach to the pull; the floor lasts the whole job.
do
	local H, _, support = jobWorld(1, { away = 900 })
	local I = H.Intent
	local FARM, LANING = dota.BotMode.Farm, dota.BotMode.Laning
	T = 70
	support.mode = LANING
	I.Tick(support)
	T = 70.5
	check("precondition: laning has a dwell bonus", I.Resolve(support, LANING, 0.66) > 0.66, I.Resolve(support, LANING, 0.66))
	for _, phase in ipairs({ "travel", "wait", "aggro", "lead", "watch" }) do
		T = T + 0.3
		local d = H.Lane.CampJobDesire(support)
		H.Lane.CampJobs.Current(support).phase = phase
		local raw = H.Lane.CampJobRawDesire(support, d)
		local bonus = I.Resolve(support, LANING, 0.66) > 0.66
		local expectBonus = phase == "lead" or phase == "watch"
		check(phase .. ": dwell bonus is " .. (expectBonus and "kept" or "suspended"), bonus == expectBonus, I.Resolve(support, LANING, 0.66))
		check(phase .. ": the job's floor applies", near(I.Resolve(support, FARM, raw), d), I.Resolve(support, FARM, raw))
	end
end
do
	local H, _, support = jobWorld(1, { away = 900 })
	H.Config.Get().Intent.Enable = false
	T = 70
	local d = H.Lane.CampJobDesire(support)
	check("intent off: farm returns the job's own desire", near(H.Lane.CampJobRawDesire(support, d), 0.7), tostring(d) .. " " .. tostring(H.Lane.CampJobRawDesire(support, d)))
end

-- Waiting at the stand point is a deliberate hold: intent's stuck detector leaves the bot alone.
do
	local H, _, support = jobWorld(1, { t = 60 })
	local FARM = dota.BotMode.Farm
	H.Lane.CampJobs.Start(support, { kind = "full_pull", campIdx = 1 })
	local job = H.Lane.CampJobs.Current(support)
	support.mode, support.desire = FARM, 0.5
	for t = job.aggroAt - 8, job.aggroAt - 5, 0.1 do
		T = t
		H.Lane.CampJobThink(support)
		H.Intent.Resolve(support, FARM, 0.5)
		H.Intent.Tick(support)
	end
	check("precondition: still waiting", job.phase == "wait")
	check("job wait held", H.Intent.HeldBy(support) == "lane:job_wait", H.Intent.HeldBy(support))
	check("job wait is not a stuck mode", H.Intent.SummaryLine(support):find("stuck=-", 1, true) ~= nil, H.Intent.SummaryLine(support))
end

-- DotaTime is negative before the horn, and camps first fill at 1:00: no pull may be planned for an empty box.
do
	for _, t in ipairs({ -17, 43 }) do
		local H, _, support = jobWorld(0.9, { t = t })
		check("no pull desire at " .. t .. " s, before the first spawn", H.Lane.CampJobDesire(support) == 0 and H.Lane.CampJobs.Current(support) == nil)
	end
	local H, _, support = jobWorld(0.9, { t = 73 })
	check("first pull at 1:15 is planned", near(H.Lane.CampJobDesire(support), 0.7) and H.Lane.CampJobs.Current(support).plannedSec == 15)
end

local function hev(lines, name)
	local r = {}
	for _, l in ipairs(lines) do if l:find(" ev=" .. name .. " ", 1, true) then table.insert(r, l) end end
	return r
end
local function field(line, key) return line and line:match(" " .. key .. '="([^"]*)"') or line and line:match(" " .. key .. "=(%S+)") end

do
	-- A double that cannot fit is not planned: a plain full pull, and lane_plan says why.
	local function unfit(opts, speed)
		local H, _, support = jobWorld(1, opts)
		support.speed = speed
		local lines = {}
		H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
		for t = 70, 76, 0.5 do T = t H.Lane.CampJobDesire(support) end
		local job = H.Lane.CampJobs.Current(support)
		local why
		for _, l in ipairs(hev(lines, "lane_plan")) do if field(l, "gate") == "double-unfit" then why = field(l, "why") end end
		return job, why
	end
	-- No creep path to time the small camp from, so the hard camp cannot be placed against the wave.
	local job, why = unfit({ large = true, telemetry = { Enable = true } }, 300)
	check("seed-timed small camp: full pull, not double", job ~= nil and job.kind == "full_pull" and job.secondCampIdx == nil, job and job.kind)
	check("seed-timed small camp: lane_plan why=no-wave", why == "no-wave", why)
	-- 391 between the stands at 50 is 7.8 s, past DoublePullMaxGap (the hard camp would give up the chase).
	job, why = unfit({ large = true, telemetry = { Enable = true }, cfg = WAVE_CFG }, 50)
	check("stands too far apart: full pull, why=far", job ~= nil and job.kind == "full_pull" and why == "far", why)
end

do
	-- lane_plan: one event per wave cycle with the planner's verdict, however often farm asks.
	local H, _, support = jobWorld(1, { away = 900, telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	H.Lane.LanePlanner.Commit(support, "aggro_pull")
	for t = 70, 76, 0.5 do T = t H.Lane.CampJobDesire(support) end
	local plans = hev(lines, "lane_plan")
	check("one lane_plan in the cycle", #plans == 1, #plans)
	check("lane_plan names the planner's choice and reason",
		field(plans[1], "gate") == "planner" and field(plans[1], "tech") == "none" and field(plans[1], "reason") == "one per cycle (aggro_pull)", plans[1])
	check("lane_plan carries the score inputs", tonumber(field(plans[1], "score")) ~= nil and tonumber(field(plans[1], "front")) ~= nil
		and field(plans[1], "owner") == "ok" and field(plans[1], "partner") == "1", plans[1])
	for t = 100, 103, 0.5 do T = t H.Lane.CampJobDesire(support) end
	plans = hev(lines, "lane_plan")
	check("next cycle: a second lane_plan, now a pull", #plans == 2 and field(plans[2], "tech") == "full_pull", plans[2])
	check("lane_plan carries the meet amount", tonumber(field(plans[1], "meet")) ~= nil and tonumber(field(plans[2], "meet")) ~= nil, plans[1])
	local starts = hev(lines, "lane_job_start")
	check("job start event", #starts == 1 and field(starts[1], "kind") == "full" and field(starts[1], "aggroAt") ~= nil, starts[1])
end

do
	-- Too far from the camp: the window is shut by distance alone, and the event says so.
	local H, _, support = jobWorld(1, { away = 4500, telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	for t = 63, 70, 0.5 do T = t H.Lane.CampJobDesire(support) end
	local plans = hev(lines, "lane_plan")
	check("far camp: no job", H.Lane.CampJobs.Current(support) == nil)
	check("far camp: gate=far with the travel time", #plans == 1 and field(plans[1], "gate") == "far" and near(tonumber(field(plans[1], "travel")), 15), plans[1])
end

do
	-- The gates are re-checked every frame: far at the window's opening, back in reach later in the same cycle.
	local H, _, support, _, stand = jobWorld(1, { away = 4500, telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	frame(H, support, 63)
	check("precondition: far at 1:03", H.Lane.CampJobs.Current(support) == nil)
	support.loc = Vector(stand.x + 900, stand.y)
	frame(H, support, 70)
	local plans = hev(lines, "lane_plan")
	check("back in reach: the job starts in the same cycle", H.Lane.CampJobs.Current(support) ~= nil)
	check("far, then planner: both logged in one cycle", #plans == 2 and field(plans[1], "gate") == "far" and field(plans[2], "gate") == "planner",
		#plans .. " " .. tostring(plans[2]))
end

do
	-- 11 s away at 1:12 is inside MaxTravel, but arrives at 1:23, past the :15 pull's late tolerance (1:17).
	local H, _, support = jobWorld(1, { away = 3300, telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	local d = frame(H, support, 72)
	local plans = hev(lines, "lane_plan")
	check("cannot arrive by the late tolerance: no job", d == 0 and H.Lane.CampJobs.Current(support) == nil)
	check("cannot arrive: gate=late", #plans == 1 and field(plans[1], "gate") == "late", plans[1])

	-- Control: the same distance when the window opens (1:01, arriving 1:12) starts the pull.
	H, _, support = jobWorld(1, { away = 3300 })
	check("11 s away at 1:01: job starts", near(frame(H, support, 61), 0.7) and H.Lane.CampJobs.Current(support).kind ~= nil)
end

do
	-- Every abort reaches telemetry with its reason and the phase it ended in.
	local H, _, support = jobWorld(1, { away = 900, telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	frame(H, support, 70)
	H.Orders.Post(2, { type = "LANE_HANDSOFF", sourceKey = "ping", issuerPID = 0, lane = Lane.Bot, duration = 30,
		maxResponders = 1, onlyPIDs = { 5 }, delayKind = "ping" })
	T = 72
	H.Lane.CampJobDesire(support)
	local aborts = hev(lines, "lane_job_abort")
	check("abort event with reason and phase", #aborts == 1 and field(aborts[1], "reason") == "handsoff" and field(aborts[1], "phase") == "travel"
		and field(aborts[1], "acted") == "1", aborts[1])
end

-- Commitment (console.9055828679: 12 of 38 jobs ended partner-unsafe 0.3-8 s in): once a job runs, the enemy laners
-- standing in their usual lane spots near the core no longer end it; a dive on the core does, after a reaction delay.
local function enemyAt(pid, x, y) return unit({ pid = pid, team = 3, pos = pid == 11 and 5 or 1, loc = Vector(x, y) }) end
-- jobWorld's enemy stands on the front; these tests place their own.
local function clearEnemies() for _, u in ipairs(UNITS[3]) do u.loc = Vector(6000, 6000) end end

do
	local H, core, support = jobWorld(1, { away = 900, telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	frame(H, support, 70)
	check("precondition: travelling", H.Lane.CampJobs.Current(support).phase == "travel")
	clearEnemies()
	enemyAt(11, FRONT.x + 900, FRONT.y)
	enemyAt(12, FRONT.x + 1000, FRONT.y + 300)
	T = 70.6
	check("precondition: the start gate now says unsafe",
		H.Lane.LaneRoles.PartnerSafe(support, H.Lane.LaneState.ForBot(support), H.Lane.LaneState.Enemies(support, Lane.Bot)) == false)
	local d = frame(H, support, 70.6)
	for t = 71, 73, 0.5 do d = frame(H, support, t) end
	check("laners standing near the core: the pull goes on", near(d, 0.7) and H.Lane.CampJobs.Active(support), d)
	local holds = hev(lines, "lane_job_hold")
	check("one hold event, with the partner reading", #holds == 1 and field(holds[1], "pnear") == "2" and field(holds[1], "pclose") == "0"
		and field(holds[1], "phase") == "travel", holds[1])
	check("no abort", #hev(lines, "lane_job_abort") == 0)
end

do
	local H, core, support = jobWorld(1, { away = 900, telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	frame(H, support, 70)
	clearEnemies()
	enemyAt(11, FRONT.x + 400, FRONT.y)
	frame(H, support, 70.5)
	core.hp = 92
	frame(H, support, 71)
	core.hp = 80
	frame(H, support, 71.5)
	check("dive noticed: not yet turned back", H.Lane.CampJobs.Active(support))
	core.hp = 74
	frame(H, support, 72)
	check("dive held past the reaction delay: the support turns back", not H.Lane.CampJobs.Active(support))
	local aborts = hev(lines, "lane_job_abort")
	check("dive abort carries the reading", #aborts == 1 and field(aborts[1], "reason") == "partner-dived" and field(aborts[1], "pclose") == "1"
		and near(tonumber(field(aborts[1], "php")), 0.74) and near(tonumber(field(aborts[1], "ploss")), 0.26), aborts[1])
end

do
	-- One enemy trading near the core without landing damage is no dive.
	local H, core, support = jobWorld(1, { away = 900 })
	frame(H, support, 70)
	clearEnemies()
	enemyAt(11, FRONT.x + 400, FRONT.y)
	for t = 70.5, 73, 0.5 do frame(H, support, t) end
	check("enemy beside an unhurt core: the pull goes on", H.Lane.CampJobs.Active(support))
end

-- The job's floor sits on farm only, and claims order within one mode: other errands are capped while it runs.
do
	local H, _, support = jobWorld(1, { away = 900 })
	local I, M = H.Intent, dota.BotMode
	T = 70
	local raw = H.Lane.CampJobRawDesire(support, H.Lane.CampJobDesire(support))
	local farm = I.Resolve(support, M.Farm, raw)
	check("ward waits for the job", I.Resolve(support, M.Ward, 0.81) < farm, I.Resolve(support, M.Ward, 0.81))
	check("a last-hit team_roam visit waits for the job", I.Resolve(support, M.TeamRoam, 0.72) < farm, I.Resolve(support, M.TeamRoam, 0.72))
	check("retreat is left alone", near(I.Resolve(support, M.Retreat, 0.8), 0.8), I.Resolve(support, M.Retreat, 0.8))
	check("defend is left alone", near(I.Resolve(support, M.DefendTowerBot, 0.8), 0.8))
	H.Lane.CampJobs.Abort(support, "test")
	check("job over: ward is not capped", near(I.Resolve(support, M.Ward, 0.81), 0.81), I.Resolve(support, M.Ward, 0.81))
end

-- console.9055921786: 8 of 25 aborts were mode-end in lead or watch at 49-80% HP. Retreat's laning-phase creep-damage
-- branch (0.79-0.90) counts the neutrals chasing the bot, which is what a pull is. Retreat is held below the job while
-- only neutrals threaten, released for good by low HP, a hero's damage or attack, or a tower.
local function leadingWorld()
	local H, core, support = jobWorld(1, { telemetry = { Enable = true } })
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	local neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	frame(H, support, 72.5)
	local job = H.Lane.CampJobs.Current(support)
	frame(H, support, job.aggroAt)
	neutral.target = support
	frame(H, support, 80)
	check("precondition: leading the camp", job.phase == "lead")
	return H, support, job, lines
end
-- One farm GetDesire (which posts the claims), then retreat's and farm's resolved desires.
local function retreatAgainstJob(H, support, retreatRaw)
	T = T + 0.05
	local raw = H.Lane.CampJobRawDesire(support, H.Lane.CampJobDesire(support))
	return H.Intent.Resolve(support, dota.BotMode.Retreat, retreatRaw), H.Intent.Resolve(support, dota.BotMode.Farm, raw)
end

do
	local H, support, job, lines = leadingWorld()
	support.hp = 70
	local retreat, farm = retreatAgainstJob(H, support, 0.82)
	check("neutrals hitting at 70% in lead: retreat held below the job", retreat < farm and near(farm, 0.7), retreat .. " " .. farm)
	support.hp = 55
	retreat, farm = retreatAgainstJob(H, support, 0.88)
	check("still only neutrals at 55%: the job keeps going", retreat < farm, retreat .. " " .. farm)
	local holds = hev(lines, "lane_job_hold")
	check("one hold-on line", #holds == 1 and field(holds[1], "hold") == "retreat" and field(holds[1], "state") == "on"
		and field(holds[1], "phase") == "lead", holds[1])

	support.hp = 45
	retreat = retreatAgainstJob(H, support, 0.89)
	check("below JobHoldMinHP the hold releases", near(retreat, 0.89), retreat)
	holds = hev(lines, "lane_job_hold")
	check("release logged with its reason", #holds == 2 and field(holds[2], "state") == "off" and field(holds[2], "reason") == "hp", holds[2])
	support.hp = 70
	retreat = retreatAgainstJob(H, support, 0.82)
	check("a released hold stays released for the job", near(retreat, 0.82), retreat)
	check("no further hold lines", #hev(lines, "lane_job_hold") == 2)
end

do
	local H, support, job, lines = leadingWorld()
	support.hp = 70
	local retreat, farm = retreatAgainstJob(H, support, 0.82)
	check("precondition: held before the hero's hit", retreat < farm)
	support.heroHitAt = T
	retreat = retreatAgainstJob(H, support, 0.82)
	check("an enemy hero's hit at 70% releases the hold", near(retreat, 0.82), retreat)
	check("hero hit named", field(hev(lines, "lane_job_hold")[2], "reason") == "hero-hit")

	H, support, job, lines = leadingWorld()
	support.hp = 90
	retreat, farm = retreatAgainstJob(H, support, 0.82)
	check("precondition: held before the hero attacks", retreat < farm)
	UNITS[3][1].target = support
	retreat = retreatAgainstJob(H, support, 0.82)
	check("a visible enemy hero attacking us releases the hold", near(retreat, 0.82), retreat)
	check("hero attack named", field(hev(lines, "lane_job_hold")[2], "reason") == "hero-attack")

	H, support, job, lines = leadingWorld()
	support.hp = 90
	retreat, farm = retreatAgainstJob(H, support, 0.9)
	check("precondition: held before the tower shot", retreat < farm)
	support.towerHitAt = T
	retreat = retreatAgainstJob(H, support, 0.9)
	check("tower damage releases the hold", near(retreat, 0.9), retreat)
end

do
	local H, support, job = leadingWorld()
	support.hp = 70
	local held, jobFarm = retreatAgainstJob(H, support, 0.82)
	check("precondition: held without the order", held < jobFarm)
	H.Intent.Claim(support, { source = "orders:RETREAT", tier = "HUMAN_ORDER", mode = dota.BotMode.Retreat, floor = 0.95 })
	local retreat, farm = retreatAgainstJob(H, support, 0.82)
	check("an order to retreat beats the hold", retreat > farm, retreat .. " " .. farm)
end

do
	-- Watch and the aggro phase once the hit is out hold too; walking there, waiting, or before the hit do not.
	for _, case in ipairs({ { "watch", true }, { "aggro-hit", true }, { "aggro", false }, { "wait", false }, { "travel", false } }) do
		local H, support, job = leadingWorld()
		support.hp = 70
		job.phase = case[1] == "aggro-hit" and "aggro" or case[1]
		if case[1] == "aggro" then job.aggroOrderedAt = nil end
		local retreat, farm = retreatAgainstJob(H, support, 0.82)
		check(case[1] .. ": retreat " .. (case[2] and "held" or "free"), (retreat < farm) == case[2] and (case[2] or near(retreat, 0.82)),
			retreat .. " " .. farm)
	end
	local H, support, job = leadingWorld()
	support.hp = 70
	job.kind = "stack"
	local retreat = retreatAgainstJob(H, support, 0.82)
	check("a stack's walk-off is not held", near(retreat, 0.82), retreat)
	check("no job: no hold", not LaneFresh({ Enable = true }).Lane.CampJobHoldsRetreat(unit({ pid = 6, pos = 4 })))
end

do
	-- A double pull walks to the small camp with the hard camp chasing it: that walk and the small camp's hit are held too.
	local H, _, support = jobWorld(1, { large = true, cfg = WAVE_CFG })
	MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local large = MakeNeutral({ x = LARGE.x, y = LARGE.y })
	support.hp = 70
	frame(H, support, 72.5)
	local job = H.Lane.CampJobs.Current(support)
	-- Farm's Think follows each desire query here, as in game, so the job is not pre-empted.
	local retreat, farm = retreatAgainstJob(H, support, 0.82)
	H.Lane.CampJobThink(support)
	check("double, before the hard camp's hit: retreat free", near(retreat, 0.82) and job.chain ~= nil, retreat)
	teleport(support)
	frame(H, support, job.aggroAt)
	large.target = support
	frame(H, support, job.aggroAt + 0.1)
	check("precondition: walking to the small camp with the hard camp on the bot", job.phase == "travel" and job.chain == nil, job.phase)
	retreat, farm = retreatAgainstJob(H, support, 0.82)
	H.Lane.CampJobThink(support)
	check("double, hard camp chasing on the walk: retreat held", retreat < farm, retreat .. " " .. farm)
	check("double, hard camp chasing on the walk: farm's run gate held", H.Lane.CampJobHoldsRetreat(support))
	teleport(support)
	frame(H, support, job.aggroAt - 1)
	check("precondition: waiting at the small camp", job.phase == "wait", job.phase)
	retreat, farm = retreatAgainstJob(H, support, 0.82)
	H.Lane.CampJobThink(support)
	check("double, waiting for the small camp's hit: retreat held", retreat < farm, retreat .. " " .. farm)
end

do
	-- Farm's own ShouldRun ("don't trade into creeps under 70%") ended a pull in watch at 68% (ogre 1:27).
	local src = io.open(HARNESS_DIR .. "/../../bots/mode_farm_generic.lua", "r"):read("a")
	local branch = src:find("and bot:WasRecentlyDamagedByCreep(1)", 1, true)
	local gate = src:find("and not J.Humaniser.Lane.CampJobHoldsRetreat(bot) then", 1, true)
	check("farm's creep-damage run yields to a held pull", branch ~= nil and gate ~= nil and gate > branch and gate - branch < 200)
	local H, support = leadingWorld()
	support.hp = 68
	check("the run gate is held for neutrals at 68%", H.Lane.CampJobHoldsRetreat(support))
end

do
	-- WD cast Cask on the camp it was pulling (console.9055970181 1:48): upstream's farm branches fire inside a job.
	local src = io.open(HARNESS_DIR .. "/../../bots/ability_item_usage_generic.lua", "r"):read("a")
	for _, f in ipairs({ { "ItemUsageThink", "ItemUsageComplement()" }, { "AbilityUsageThink", "BotBuild.SkillsComplement()" } }) do
		local at = src:find("function " .. f[1] .. "()", 1, true)
		local gate = at and src:find("if J.Humaniser.Lane.CampJobHoldsCasts(bot) then return end", at, true)
		local call = at and src:find(f[2], at, true)
		check(f[1] .. " returns on a held camp job before casting", gate ~= nil and call ~= nil and gate < call)
	end
	local H, support, job = leadingWorld()
	clearEnemies()
	check("leading the camp: casts held", H.Lane.CampJobHoldsCasts(support))
	enemyAt(11, support.loc.x + 1000, support.loc.y)
	check("an enemy hero at 1000: casts free", not H.Lane.CampJobHoldsCasts(support))
	clearEnemies()
	enemyAt(11, support.loc.x + 1500, support.loc.y)
	check("an enemy hero at 1500: still held", H.Lane.CampJobHoldsCasts(support))
	H.Lane.CampJobs.Abort(support, "test")
	check("job over: casts free", not H.Lane.CampJobHoldsCasts(support))
end

do
	-- On the walk in, only once the camp is in sight (its neutrals would be the farm branches' targets).
	local H, _, support = jobWorld(1, { away = 900 })
	frame(H, support, 70)
	check("precondition: travelling", H.Lane.CampJobs.Current(support).phase == "travel")
	clearEnemies()
	check("travelling, camp not in sight: casts free", not H.Lane.CampJobHoldsCasts(support))
	MakeNeutral({ x = SMALL.x, y = SMALL.y })
	check("travelling, camp in sight: casts held", H.Lane.CampJobHoldsCasts(support))
end

-- console.9055994510: Valve's attack mode (0.95, not resolvable) cut 9 of 34 jobs, 6 of them with no enemy within 1,400.
-- A round as the engine scores it: retreat before farm, so farm's GetDesire reads this round's retreat.
local function round(H, support, retreatRaw)
	T = T + 0.3
	local retreat = H.Intent.Resolve(support, dota.BotMode.Retreat, retreatRaw)
	local farm = H.Intent.Resolve(support, dota.BotMode.Farm, H.Lane.CampJobRawDesire(support, H.Lane.CampJobDesire(support)))
	return retreat, farm
end
local ATTACK = 0.95

do
	local H, support = leadingWorld()
	clearEnemies()
	support.hp, support.mode = 80, dota.BotMode.Farm
	local _, farm = round(H, support, 0.3)
	check("leading, nothing near: the job outbids attack mode", farm > ATTACK, farm)
	enemyAt(11, support.loc.x + 1000, support.loc.y)
	_, farm = round(H, support, 0.3)
	check("an enemy hero at 1000: back to the job's desire, attack mode may take over", near(farm, 0.7), farm)
	clearEnemies()
	enemyAt(11, support.loc.x + 1500, support.loc.y)
	_, farm = round(H, support, 0.3)
	check("an enemy hero at 1500: still committed", farm > ATTACK, farm)

	-- The hold keeps neutral-driven retreat under the job; once it releases, the commitment must not stand in for it.
	clearEnemies()
	support.hp = 70
	local retreat
	retreat, farm = round(H, support, 0.85)
	check("neutrals only at 70%: held retreat, committed farm", retreat < 0.7 and farm > ATTACK, retreat .. " " .. farm)
	support.hp = 45
	round(H, support, 0.89)
	retreat, farm = round(H, support, 0.89)
	check("hold released at 45%: retreat wins and farm is not committed", retreat > farm and near(farm, 0.7), retreat .. " " .. farm)
end

do
	-- Travelling there is no retreat hold, so a retreat that wants out keeps the job at its own desire.
	local H, _, support = jobWorld(1, { away = 900 })
	frame(H, support, 70)
	check("precondition: travelling", H.Lane.CampJobs.Current(support).phase == "travel")
	clearEnemies()
	support.mode = dota.BotMode.Farm
	local _, farm = round(H, support, 0.2)
	check("travelling, retreat quiet: committed", farm > ATTACK, farm)
	local retreat
	retreat, farm = round(H, support, 0.8)
	check("travelling, retreat at 0.8: retreat wins", retreat > farm, retreat .. " " .. farm)
	H.Config.Get().Intent.Enable = false
	check("intent off: no commitment", near(H.Lane.CampJobRawDesire(support, H.Lane.CampJobDesire(support)), 0.7))
end

-- Start gate (console.9055994510: 4 of 8 retreat-ended jobs started at 51-59%, one with retreat already at 0.86).
do
	local function startAt(hp, retreatRaw, fight)
		local H, _, support = jobWorld(1, { away = 900, telemetry = { Enable = true } })
		local lines = {}
		H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
		support.hp = hp
		if fight then
			clearEnemies()
			local enemy = enemyAt(11, support.loc.x + fight.dist, support.loc.y)
			if fight.hit then support.heroHitAt = 70 end
			if fight.attacking then support.target = enemy end
		end
		T = 70
		if retreatRaw then H.Intent.Resolve(support, dota.BotMode.Retreat, retreatRaw) end
		local gate
		for _, l in ipairs(hev(lines, "lane_plan")) do gate = field(l, "gate") end
		local d = H.Lane.CampJobDesire(support)
		for _, l in ipairs(hev(lines, "lane_plan")) do gate = field(l, "gate") end
		return d, gate
	end
	local d, gate = startAt(70)
	check("70% HP: the pull starts", near(d, 0.7), d)
	d, gate = startAt(60)
	check("60% HP: no pull, logged as low-hp", d == 0 and gate == "low-hp", tostring(d) .. " " .. tostring(gate))
	d, gate = startAt(90, 0.75)
	check("retreat already at 0.75: no pull", d == 0 and gate == "retreat", tostring(d) .. " " .. tostring(gate))
	d = startAt(90, 0.5)
	check("retreat at 0.5: the pull starts", near(d, 0.7), d)
	-- console.9057032878, shadow_demon 2:08: started with beastmaster 335 away, walked to the camp under its hits.
	d, gate = startAt(90, nil, { dist = 500, hit = true })
	check("hit by an enemy hero 500 away: no pull, logged as fight", d == 0 and gate == "fight", tostring(d) .. " " .. tostring(gate))
	d, gate = startAt(90, nil, { dist = 500, attacking = true })
	check("attacking an enemy hero 500 away: no pull", d == 0 and gate == "fight", tostring(d) .. " " .. tostring(gate))
	d = startAt(90, nil, { dist = 500 })
	check("an enemy laner 500 away, no trade: the pull starts", near(d, 0.7), d)
	d = startAt(90, nil, { dist = 1000, hit = true })
	check("hit, but the hero is 1,000 away: the pull starts", near(d, 0.7), d)
end

-- Tango and clarity on the way to a pull, while there is time to spare.
local function supplyWorld(o)
	local H, _, support = jobWorld(1, { away = o.away or 900, telemetry = o.telemetry and { Enable = true } or nil })
	if o.telemetry then
		support.lines = {}
		H.Telemetry.SetSink(function(l) table.insert(support.lines, l) end)
	end
	-- jobWorld's enemy stands on the front, 1,190 from this support: inside JobEnemyHero.
	UNITS[3][1].loc = Vector(FRONT.x + 1000, FRONT.y)
	support.GetMaxHealth = function() return 600 end
	support.hp = o.hp or 450
	support.maxMana, support.mana = 300, o.mana or 300
	support.items = o.items or { [0] = { name = "item_tango" } }
	TREES = { [7] = Vector(support.loc.x + 150, support.loc.y) }
	return H, support
end
local function used(pid, kind) return #ActionsOf(pid, kind) end

do
	local H, support = supplyWorld({})
	frame(H, support, 70)
	local job = H.Lane.CampJobs.Current(support)
	check("precondition: time to spare", job.aggroAt - 70 - 3 > 1.5, job.aggroAt)
	local trees = ActionsOf(support.pid, "UseAbilityOnTree")
	check("150 HP down on the way to a pull: eats the nearby tree", #trees == 1 and trees[1].args[2] == 7, #trees)
	check("and no move that frame", used(support.pid, "MoveToLocation") == 0)
	frame(H, support, 70.5)
	check("the tango is left to land", used(support.pid, "MoveToLocation") == 0)
	support.modifiers["modifier_tango_heal"] = 1
	frame(H, support, 70.6)
	check("healing: the walk resumes", used(support.pid, "MoveToLocation") == 1)
	support.modifiers["modifier_tango_heal"] = nil
	for t = 71, 72, 0.5 do frame(H, support, t) end
	check("one tango per pull", used(support.pid, "UseAbilityOnTree") == 1)
end

do
	-- lane_job_supply says what was used and whether its modifier showed, and why a needed item was not.
	local H, support = supplyWorld({ telemetry = true })
	local lines = support.lines
	frame(H, support, 70)
	support.modifiers["modifier_tango_heal"] = 1
	frame(H, support, 70.2)
	local ev = hev(lines, "lane_job_supply")
	check("tango used then taken", #ev == 2 and field(ev[1], "state") == "use" and field(ev[2], "state") == "taken"
		and field(ev[1], "item") == "tango" and near(tonumber(field(ev[1], "hp")), 0.75), table.concat(ev, " | "))

	H, support = supplyWorld({ telemetry = true })
	frame(H, support, 70)
	for t = 70.2, 72, 0.2 do frame(H, support, t) end
	ev = hev(support.lines, "lane_job_supply")
	check("no heal within SupplyWait: logged as missed", #ev == 2 and field(ev[2], "state") == "missed", table.concat(ev, " | "))

	H, support = supplyWorld({ telemetry = true, items = {} })
	for t = 70, 71, 0.2 do frame(H, support, t) end
	ev = hev(support.lines, "lane_job_supply")
	check("no tango in the inventory: one skip, no-item", #ev == 1 and field(ev[1], "state") == "skip" and field(ev[1], "reason") == "no-item", table.concat(ev, " | "))

	H, support = supplyWorld({ telemetry = true, hp = 600, away = 600 })
	frame(H, support, 70)
	support.hp = 450
	enemyAt(11, support.loc.x + 900, support.loc.y)
	frame(H, support, 70.2)
	ev = hev(support.lines, "lane_job_supply")
	check("hit on the way with an enemy near: skip, enemy", H.Lane.CampJobs.Active(support) and #ev == 1 and field(ev[1], "reason") == "enemy", table.concat(ev, " | "))
end

do
	local H, support = supplyWorld({ hp = 550 })
	frame(H, support, 70)
	check("50 HP down: no tango", used(support.pid, "UseAbilityOnTree") == 0 and used(support.pid, "MoveToLocation") == 1)

	H, support = supplyWorld({ items = { [0] = { name = "item_tango", ready = false } } })
	frame(H, support, 70)
	check("tango not castable: walks on", used(support.pid, "UseAbilityOnTree") == 0 and used(support.pid, "MoveToLocation") == 1)

	-- The job starts first: an enemy this close at the start leaves the partner unsafe and nothing would start.
	H, support = supplyWorld({ hp = 600, away = 600 })
	frame(H, support, 70)
	support.hp = 450
	enemyAt(11, support.loc.x + 900, support.loc.y)
	frame(H, support, 70.2)
	check("an enemy hero near: no tango", H.Lane.CampJobs.Active(support) and used(support.pid, "UseAbilityOnTree") == 0)

	H, support = supplyWorld({})
	frame(H, support, 70)
	ACTIONS = {}
	local job = H.Lane.CampJobs.Current(support)
	job.tangoUsed = nil
	frame(H, support, job.aggroAt - 1.2)
	check("too close to the hit: no tango", used(support.pid, "UseAbilityOnTree") == 0)
end

do
	local H, support = supplyWorld({ hp = 600, mana = 100, items = { [0] = { name = "item_clarity" } } })
	frame(H, support, 70)
	local uses = ActionsOf(support.pid, "UseAbilityOnEntity")
	check("200 mana down: drinks the clarity on itself", #uses == 1 and uses[1].args[2] == support, #uses)
	support.modifiers["modifier_clarity_potion"] = 1
	frame(H, support, 70.1)
	check("regenerating: the walk resumes", used(support.pid, "MoveToLocation") == 1)

	H, support = supplyWorld({ hp = 600, mana = 200, items = { [0] = { name = "item_clarity" } } })
	frame(H, support, 70)
	check("100 mana down: no clarity", used(support.pid, "UseAbilityOnEntity") == 0)
end

-- The core's side: while its support is out on a camp, it backs off sooner.
do
	-- The support starts at the front, so only its job (not its position) says it is away.
	local H, core, support = jobWorld(1, { telemetry = { Enable = true } })
	support.loc = FRONT
	local lines = {}
	H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
	local I, RETREAT = H.Intent, dota.BotMode.Retreat
	T = 69
	H.Lane.Tick(core)
	check("no job: the core's retreat is unchanged", near(I.Resolve(core, RETREAT, 0.4), 0.4), I.Resolve(core, RETREAT, 0.4))
	frame(H, support, 70)
	check("precondition: the support's pull runs", H.Lane.CampJobs.Active(support))
	H.Lane.Tick(core)
	check("support on a pull: the core's retreat is raised", near(I.Resolve(core, RETREAT, 0.4), 0.5), I.Resolve(core, RETREAT, 0.4))
	check("the support's own retreat is not", near(I.Resolve(support, RETREAT, 0.4), 0.4))
	H.Lane.CampJobs.Abort(support, "test")
	T = 70.5
	H.Lane.Tick(core)
	check("job over: the core's caution ends", near(I.Resolve(core, RETREAT, 0.4), 0.4) and not H.Lane.CampJobs.Covering(core))
	local covers = hev(lines, "lane_cover")
	check("cover start and end logged", #covers == 2 and field(covers[1], "state") == "start" and field(covers[1], "via") == "job"
		and field(covers[1], "partner") == "5" and field(covers[2], "state") == "end", table.concat(covers, " | "))
end

do
	-- Modules not shared: the core's instance holds no job, so it reads its support's position at the camp instead.
	local H, core, support = jobWorld(1)
	support.loc = Vector(SMALL.x + 200, SMALL.y)
	T = 70
	H.Lane.Tick(core)
	check("support seen at the pull camp: the core covers", H.Lane.CampJobs.Covering(core))
	support.loc = Vector(FRONT.x - 300, FRONT.y)
	T = 70.6
	H.Lane.Tick(core)
	check("support back at the front: cover ends", not H.Lane.CampJobs.Covering(core))
end

do
	-- A human core is told by a ping on the camp; a bot core needs none.
	local sent = {}
	local H, core, support = jobWorld(1, { away = 900 })
	-- The stub Unit class is local to dota_stubs.lua; every unit shares it as its metatable index.
	local Unit = getmetatable(support).__index
	local old = Unit.ActionImmediate_Ping
	Unit.ActionImmediate_Ping = function(self, x, y) table.insert(sent, { pid = self.pid, x = x, y = y }) end
	core.bot = false
	frame(H, support, 70)
	frame(H, support, 70.2)
	local job = H.Lane.CampJobs.Current(support)
	check("human core: one ping on the stand point", #sent == 1 and sent[1].pid == 5 and dist(sent[1], job.stand) < 1e-6, #sent)
	sent = {}
	H, core, support = jobWorld(1, { away = 900 })
	frame(H, support, 70)
	check("bot core: no ping", #sent == 0, #sent)
	Unit.ActionImmediate_Ping = old
end

do
	-- A mode-end abort says which mode took over and how old the job's retreat hold was when it did.
	-- farm's OnEnd runs while farm is still the active mode (console.9057032878: all mode-end aborts read to=farm).
	local H, support, job, lines = leadingWorld()
	support.hp = 70
	retreatAgainstJob(H, support, 0.82)
	T = T + 0.25
	H.Intent.Resolve(support, dota.BotMode.Retreat, 0.82)
	support.mode = dota.BotMode.Farm
	H.Lane.CampJobOnEnd(support)
	check("the job ends at once", H.Lane.CampJobs.Active(support) == false)
	check("but its line waits for the mode that took over", #hev(lines, "lane_job_abort") == 0)
	H.Lane.Tick(support)
	check("still farm on the next tick: still waiting", #hev(lines, "lane_job_abort") == 0)
	T = T + 0.1
	support.mode = dota.BotMode.Retreat
	H.Lane.Tick(support)
	local a = hev(lines, "lane_job_abort")[1]
	check("mode-end names the winner", a ~= nil and field(a, "reason") == "mode-end" and field(a, "to") == "retreat", a)
	check("the hold was on but last posted 0.25 s before farm ended", field(a, "hold") == "on" and near(tonumber(field(a, "holdAge")), 0.25), a)
	check("retreat's resolve was 0.1 s before the line", near(tonumber(field(a, "toAge")), 0.1) and near(tonumber(field(a, "logLag")), 0.1), a)
end

do
	-- Farm ended and came straight back: after a second the line goes out naming farm.
	local H, support, job, lines = leadingWorld()
	support.mode = dota.BotMode.Farm
	H.Lane.CampJobOnEnd(support)
	T = T + 1.1
	H.Lane.Tick(support)
	local a = hev(lines, "lane_job_abort")[1]
	check("farm again a second later: logged with to=farm", a ~= nil and field(a, "to") == "farm", a)
end

do
	-- console.9055963380: retreat is scored a round (~0.31 s) after farm posted the hold. It must still be held then.
	local H, support = leadingWorld()
	support.hp = 70
	T = T + 0.05
	local farm = H.Intent.Resolve(support, dota.BotMode.Farm, H.Lane.CampJobRawDesire(support, H.Lane.CampJobDesire(support)))
	T = T + 0.31
	local retreat = H.Intent.Resolve(support, dota.BotMode.Retreat, 0.82)
	check("retreat scored a round after farm is still held", retreat < farm, retreat .. " " .. farm)
	check("so is a team_roam visit scored in that round", H.Intent.Resolve(support, dota.BotMode.TeamRoam, 0.72) < farm)
end

do
	-- The longer lifetime must not outlast the job: its claims go the moment it ends or its hold drops.
	local H, support = leadingWorld()
	support.hp = 70
	retreatAgainstJob(H, support, 0.82)
	support.heroHitAt = T
	T = T + 0.05
	H.Lane.CampJobRawDesire(support, H.Lane.CampJobDesire(support))
	check("a dropped hold frees retreat in the same round", near(H.Intent.Resolve(support, dota.BotMode.Retreat, 0.82), 0.82))

	H, support = leadingWorld()
	support.hp = 70
	retreatAgainstJob(H, support, 0.82)
	support.mode = dota.BotMode.Retreat
	H.Lane.CampJobOnEnd(support)
	check("an ended job leaves retreat alone at once", near(H.Intent.Resolve(support, dota.BotMode.Retreat, 0.82), 0.82))
	check("and its errand caps", near(H.Intent.Resolve(support, dota.BotMode.Ward, 0.81), 0.81))
end

-- Clash pull --------------------------------------------------------------------------------------------------------

do
	local J = LaneFresh({ Enable = true }).Lane.CampJobs
	local p = J.ClashPoint(Vector(0, 0), Vector(1000, 0), 400)
	check("clash point stands off toward the camp", near(p.x, 400) and near(p.y, 0))
	local q = J.ClashPoint(Vector(0, 0), Vector(300, 0), 400)
	check("a camp nearer than the stand-off is the point", near(q.x, 300))
	check("no prediction under 1 s of history", J.ClearPrediction({ { t = 10, hp = 900 }, { t = 10.8, hp = 700 } }, 10.8, 1.5) == nil)
	check("clear time from the drop rate", near(J.ClearPrediction({ { t = 10, hp = 900 }, { t = 11, hp = 600 } }, 11, 1.5) or -1, 2))
	check("only samples in the window count", near(J.ClearPrediction({ { t = 5, hp = 5000 }, { t = 10, hp = 900 }, { t = 11, hp = 600 } }, 11, 1.5) or -1, 2))
	check("no prediction while the HP rises", J.ClearPrediction({ { t = 10, hp = 600 }, { t = 11, hp = 900 } }, 11, 1.5) == nil)
	check("no prediction while the HP is flat", J.ClearPrediction({ { t = 10, hp = 600 }, { t = 11, hp = 600 } }, 11, 1.5) == nil)
end

finish()
