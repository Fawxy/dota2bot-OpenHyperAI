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
	T = 70.5
	check("no job: ward is not capped", near(I.Resolve(support, M.Ward, 0.81), 0.81), I.Resolve(support, M.Ward, 0.81))
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

finish()
