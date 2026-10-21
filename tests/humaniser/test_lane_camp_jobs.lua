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
	local H = LaneFresh(opts.cfg or { Enable = true }, { skill = skill, debug = opts.debug })
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
	frame(H, support, job.aggroAt + 0.1)
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

do
	local H, _, support = jobWorld(1, { large = true })
	local small = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local job = runToWatch(H, support, small, 76.5)
	check("two camps at 1.0 make a double pull", job.kind == "double_pull" and job.secondCampIdx == 2)
	MakeCreep({ team = 2, x = job.meet.x, y = job.meet.y, target = small })
	local large = MakeNeutral({ x = LARGE.x, y = LARGE.y })
	frame(H, support, 77)
	check("first camp engaged: heads to the second camp", job.stage == 2 and job.activeCamp == 2 and job.phase == "travel")
	teleport(support)
	frame(H, support, job.aggroAt)
	local a = ActionsOf(5, "AttackUnit")
	check("aggroes the second camp", #a == 2 and a[2].args[1] == large)
	check("second lead ends at the first meet point", dist(job.path[#job.path], job.meet) <= 20 + 1e-6)
end

do
	-- Off-lane large seeds are unverified; the start line says so.
	local H = LaneFresh({ Enable = true }, { skill = 1, debug = true })
	T = 70
	CURRENT_TEAM = 2
	SPAWNERS = { spawner("large", Vector(-1600, 6200)) }
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

finish()
