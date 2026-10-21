dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local FRONT = Vector(0, -5000)
local SMALL = Vector(-1600, -6200) -- the Radiant safe-lane small camp: our pull camp
-- Neither is within 2,500 of the T1, so no pull seed claims them. Derived exits point south (y - 900).
local LARGE = Vector(1500, -6500)
local MEDIUM = Vector(1000, -6500)

local function spawner(type_, at)
	return { team = 2, type = type_, location = Vector(at.x, at.y, 0), min = Vector(at.x - 150, at.y - 150, 0),
		max = Vector(at.x + 150, at.y + 150, 0), speed = 0 }
end

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = o.loc or FRONT, hp = o.hp })
	u.lane, u.pos = o.lane or Lane.Bot, o.pos
	return u
end

local function dist(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end

-- The stack job implementation the scenarios below run against: camp_jobs' own, or stack_task.ts (Tasks.Stack).
local PATHS = { "legacy", "task" }
local PATH = "legacy"
local BUNDLE = "bots/FunLib/sdk/tasks/tasks"

-- Radiant bot lane: core pid 1 (pos 1) at the front, support pid 5 (pos 5) at `at`, one enemy far away.
-- `camps` is a list of { type, location }; spawner idx follows list order.
local function world(skill, opts)
	opts = opts or {}
	assert(PATH == "legacy" or PATH == "task", "unknown stack job path " .. tostring(PATH))
	-- The runner's state lives in the bundle, which FreshHumaniser does not reload.
	package.loaded[BUNDLE] = nil
	local H = LaneFresh(opts.cfg or { Enable = true }, { skill = skill, debug = opts.debug, telemetry = opts.telemetry,
		tasks = { Enable = true, Stack = PATH == "task" } })
	T = opts.t or 100
	CURRENT_TEAM = 2
	OBSERVER = 5
	SPAWNERS = {}
	for _, c in ipairs(opts.camps or {}) do table.insert(SPAWNERS, spawner(c[1], c[2])) end
	H.Lane.Camps.ResetCache()
	local core = unit({ pid = 1, pos = 1, loc = opts.coreAt })
	local support = unit({ pid = 5, pos = opts.pos or 5, loc = opts.at or Vector(0, -5600), hp = opts.hp })
	local enemy = unit({ pid = 10, team = 3, pos = 3, lane = Lane.Top, loc = opts.enemyAt or Vector(6000, 6000) })
	-- Profiles draw their own randoms on first use (the snapshot refresh reads the core's); settle them before any
	-- test queues decision rolls.
	H.Lane.Config.SkillOf(support)
	H.Lane.Config.SkillOf(core)
	H.Lane.LaneState.ForBot(support)
	return H, support, core, enemy
end

local function standOf(H, idx)
	local C = H.Lane.Camps
	return H.Lane.Stacking.StandPoint(C.SpawnerByIdx(idx), C.ByIdx(idx))
end

-- Whether an ally at camp 1's stand point may choose that camp for its next stack once `bot` has stepped out of
-- the box: false only while a reservation holds it.
local function claimable(H, bot)
	local other = unit({ pid = 4, pos = 4, loc = standOf(H, 1) })
	H.Lane.Config.SkillOf(other)
	local at = bot.loc
	bot.loc = Vector(at.x, at.y + 1500)
	local ok = H.Lane.Stacking.ChooseCamp(other, H.Lane.LaneState.ForBot(other), math.floor(T / 60) + 1) ~= nil
	bot.loc = at
	return ok
end

local function eligible(H, bot)
	local s = H.Lane.LaneState.ForBot(bot)
	return H.Lane.Stacking.Eligible(bot, s, H.Lane.LaneState.Enemies(bot, Lane.Bot))
end

-- Every captured line, per path, for the cross-path comparison at the end. The bundle's one support line is left
-- out: it prints wherever the bundle first loads, which is the first task on one path and the first tick on the other.
local LOG = { legacy = {}, task = {} }

-- `own`: a scenario only one path runs, kept out of the comparison.
local function capture(fn, own)
	local printed, old = {}, print
	print = function(s) table.insert(printed, s) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err) end
	for _, l in ipairs(own and {} or printed) do
		if not tostring(l):find("[H:tasks] support", 1, true) then table.insert(LOG[PATH], tostring(l)) end
	end
	return printed
end

local function find(lines, prefix)
	local found
	for _, l in ipairs(lines) do if l:find(prefix, 1, true) then found = l end end
	return found
end

-- Farm's GetDesire, then its Think when it wins the frame, then the humaniser's per-frame task tick.
local function frame(H, bot, t)
	T = t
	local d = H.Lane.CampJobDesire(bot)
	if d > 0 then
		bot.mode = dota.BotMode.Farm
		H.Lane.CampJobThink(bot)
	end
	H.Tasks.Tick(bot)
	return d
end

-- The bot's stack job as the assertions read it, whichever path runs it: nil when none was started; `ended` is
-- "done" once it finished and "aborted" once it was aborted, nil while it runs.
local function current(H, bot)
	if PATH == "task" then
		local job = H.Lane.StackTask.Job(bot)
		if job == nil then return nil end
		local p = job.plan
		return { kind = "stack", campIdx = p.campIdx, forced = p.forced, aggroAt = p.aggroAt, baseAggro = p.baseAggro,
			exitUntil = p.exitUntil, phase = job.label, ended = job.ended }
	end
	local job = H.Lane.CampJobs.Current(bot)
	if job == nil then return nil end
	local ended = job.phase == "done" and "done" or job.phase == "return" and "aborted" or nil
	return { kind = job.kind, campIdx = job.campIdx, forced = job.forced, aggroAt = job.aggroAt, baseAggro = job.baseAggro,
		exitUntil = job.exitUntil, phase = job.phase, ended = ended }
end

local function teleport(bot)
	local m = ActionsOf(bot.pid, "MoveToLocation")
	if m[#m] then bot.loc = Vector(m[#m].args[1].x, m[#m].args[1].y) end
end

-- Neutrals sitting in the camp's box.
local function neutrals(at, n)
	local list = {}
	for i = 1, n do table.insert(list, MakeNeutral({ x = at.x + i * 10, y = at.y })) end
	return list
end

-- Drives a stack job on `idx` started at minute + :40 with a zero jitter (Gauss u1 = 1): 3 neutrals before the aggro,
-- `added` more spawned at the next :00, then settled by :05. Returns the job as `current` reads it at the start, with
-- `ended` read at the end and `ended01` after the :01 frame, the desires at :58 and the next :01,
-- the attacks issued 0.1 s before the aggro, and the camp's original neutrals. `partial` stops after :01.
local function runStack(H, bot, idx, at, minute, added, partial)
	local m0 = minute * 60
	T = m0 + 40
	bot.loc = standOf(H, idx)
	SetRandomSequence({ 1.0, 0.25 })
	check("precondition: stack job starts", H.Lane.CampJobs.Start(bot, { kind = "stack", campIdx = idx }))
	local job = current(H, bot)
	-- Farm thinks in the frame the job starts, as in game; a task left unstepped for 1 s is cancelled.
	frame(H, bot, T)
	NEUTRALS = {}
	local camp = neutrals(at, 3)
	frame(H, bot, job.aggroAt - 0.1)
	local early = #ActionsOf(bot.pid, "AttackUnit")
	frame(H, bot, job.aggroAt)
	camp[1].target = bot
	frame(H, bot, job.aggroAt)
	frame(H, bot, m0 + 56)
	teleport(bot)
	local d58 = frame(H, bot, m0 + 58)
	local d01 = frame(H, bot, m0 + 61)
	job.ended01 = current(H, bot).ended
	if not partial then
		neutrals(at, added)
		frame(H, bot, m0 + 62)
		frame(H, bot, m0 + 65)
	end
	local after = current(H, bot)
	job.ended = after and after.ended
	return job, d58, d01, early, camp
end

do
	local H, support = world(0.5)
	check("pos 5 laning with no enemies is eligible", eligible(H, support) == true)

	local enemy
	H, support, _, enemy = world(0.5)
	enemy.hiddenFrom = { [5] = true }
	LAST_SEEN[10] = { location = Vector(1000, -5600), time_since_seen = 2 }
	T = T + 0.5
	local ok, why = eligible(H, support)
	check("enemy seen 2 s ago at 1,000: not eligible", ok == false and why == "unstable", why)

	H, support = world(0.5, { hp = 45 })
	check("HP 45%: not eligible", eligible(H, support) == false)

	H, support = world(0.5, { pos = 2 })
	ok, why = eligible(H, support)
	check("pos 2: not eligible", ok == false and why == "not-support", why)
end

do
	-- After laning: no accepted order is the condition, not the default.
	local H, support = world(0.5)
	LANING = false
	check("post-laning idle support is eligible", eligible(H, support) == true)
	H.Orders.Post(2, { type = "PUSH", sourceKey = "p", issuerPID = 0, lane = Lane.Bot, location = FRONT, duration = 60,
		maxResponders = 1, onlyPIDs = { 5 }, delayKind = "ping" })
	T = T + 3
	check("precondition: push order accepted", H.Orders.GetFor(support) ~= nil)
	local ok, why = eligible(H, support)
	check("post-laning support with an order does not stack", ok == false and why == "has-order", why)
end

do
	local camps = { { "small", SMALL } }
	local H, support = world(0, { camps = camps, at = Vector(-1600, -5800) })
	SetRandomSequence({ 0.25 })
	check("skill 0, roll 0.25: no stack this minute", H.Lane.Stacking.WantsStack(support, 1) == nil)
	SetRandomSequence({ 0.0 })
	check("second call in the minute: still no", H.Lane.Stacking.WantsStack(support, 1) == nil)
	check("second call in the minute: no new roll", RandomUnread() == 1)
	SetRandomSequence({ 0.0 })
	check("next minute rolls again", H.Lane.Stacking.WantsStack(support, 2) ~= nil and RandomUnread() == 0)

	H, support = world(0, { camps = camps, at = Vector(-1600, -5800) })
	SetRandomSequence({ 0.15 })
	check("skill 0, roll 0.15 (< 0.2): stack", H.Lane.Stacking.WantsStack(support, 1) ~= nil)

	H, support = world(1, { camps = camps, at = Vector(-1600, -5800) })
	SetRandomSequence({ 0.85 })
	local data = H.Lane.Stacking.WantsStack(support, 1)
	check("skill 1, roll 0.85 (< 0.9): stack the pull camp", data ~= nil and data.campIdx == 1)
end

do
	-- pos 1 sits east; the second medium camp is nearer the support but farther from the core.
	local A, B = Vector(2500, -6500), Vector(1000, -7000)
	local camps = { { "small", SMALL }, { "medium", A }, { "medium", B } }
	local H, support = world(0.5, { camps = camps, coreAt = Vector(3000, -5000), at = Vector(500, -6800) })
	local S = H.Lane.Stacking
	check("pull camp chosen over a core's camp", S.ChooseCamp(support, H.Lane.LaneState.ForBot(support), 1).campIdx == 1)

	H, support = world(0.5, { camps = { { "medium", A }, { "medium", B } }, coreAt = Vector(3000, -5000), at = Vector(500, -6800) })
	S = H.Lane.Stacking
	local s = H.Lane.LaneState.ForBot(support)
	check("without a pull camp: the camp nearest our pos 1", S.ChooseCamp(support, s, 1).campIdx == 1)

	T = 110
	check("core's camp out of reach by the aggro: the next one", S.ChooseCamp(support, s, 1).campIdx == 2)

	T = 100
	unit({ pid = 0, bot = false, loc = A })
	check("allied human in the box: camp skipped", S.ChooseCamp(support, s, 1).campIdx == 2)
end

do
	-- An ancient that already holds one stack this minute-chain.
	local ANCIENT = Vector(1500, -6500)
	local function chosenAt(skill)
		local H, support = world(skill, { camps = { { "ancient", ANCIENT } }, coreAt = Vector(-6000, 0), at = Vector(1500, -7200) })
		local S = H.Lane.Stacking
		local before = S.ChooseCamp(support, H.Lane.LaneState.ForBot(support), 1)
		S.NoteStackAttempt(1, 0, 3)
		S.NoteStackOutcome(1, 0, 6)
		check("precondition: ancient stack count 1", S.StackCount(1) == 1)
		return before ~= nil, S.ChooseCamp(support, H.Lane.LaneState.ForBot(support), 1) ~= nil
	end
	local fresh, low = chosenAt(0.7)
	check("unstacked ancient chosen at 0.7", fresh)
	check("ancient multi-stack skipped at 0.7", low == false)
	local _, high = chosenAt(0.71)
	check("ancient multi-stack chosen at 0.71", high)
end

do
	-- The pull camp's stack makes the planner deny with a stack pull.
	local function plan(stacked)
		local H, support = world(1, { camps = { { "small", SMALL } }, enemyAt = Vector(500, -5000) })
		support.loc = Vector(-1600, -5800)
		if stacked then
			H.Lane.Stacking.NoteStackAttempt(1, 1, 3)
			H.Lane.Stacking.NoteStackOutcome(1, 1, 6)
		end
		SetRandomSequence({ 0.0 })
		return H.Lane.LanePlanner.Plan(support, H.Lane.LaneState.ForBot(support)).tech, H, support
	end
	local tech = plan(false)
	check("unstacked pull camp: full pull", tech == "full_pull", tech)
	local H, support
	tech, H, support = plan(true)
	check("stacked pull camp reaches the planner: stack pull", tech == "stack_pull", tech)

	-- Run that stack pull to completion; the stack is consumed.
	T = 130
	H.Lane.LanePlanner.ResetCache()
	check("precondition: stack pull starts", H.Lane.CampJobs.Start(support, { kind = "stack_pull", campIdx = 1 }))
	local job = H.Lane.CampJobs.Current(support)
	local n = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	for _ = 1, 3 do frame(H, support, job.aggroAt - 3) teleport(support) end
	frame(H, support, job.aggroAt)
	n.target = support
	frame(H, support, job.aggroAt + 0.1)
	for i = 1, 4 do frame(H, support, job.aggroAt + 0.1 + i * 0.1) teleport(support) end
	check("precondition: watching the stack pull", job.phase == "watch" and H.Lane.Stacking.IsStacked(1))
	frame(H, support, job.aggroAt + 9)
	check("completed stack pull consumes the stack", job.phase == "done" and H.Lane.Stacking.IsStacked(1) == false)
end

local baseCheck = check
for _, path in ipairs(PATHS) do
	PATH = path
	local function check(name, ...) return baseCheck(#PATHS > 1 and (path .. ": " .. name) or name, ...) end

	do
		-- Support at the medium camp's stand at 1:45: the stack window (from :45 to :54) is open.
		local function lockWorld(cfg)
			local H, support = world(1, { camps = { { "medium", MEDIUM } }, cfg = cfg })
			support.loc = standOf(H, 1)
			return H, support
		end
		local H, support = lockWorld()
		check("window open: stack job starts", near(frame(H, support, 105), 0.7) and current(H, support).kind == "stack")
		check("stack commits the cycle", H.Lane.LanePlanner.Committed(support) == "stack")

		H, support = lockWorld()
		T = 100
		H.Lane.LanePlanner.Commit(support, "full_pull")
		check("full pull in the cycle: no stack job", frame(H, support, 105) == 0 and current(H, support) == nil)

		H, support = lockWorld()
		check("before :45: no stack job", frame(H, support, 104) == 0 and current(H, support) == nil)

		H, support = lockWorld({ Enable = true, Stack = false })
		check("Stack off: no stack job", frame(H, support, 105) == 0 and current(H, support) == nil)
	end

	do
		-- Before the horn DotaTime is negative (-1:15 is :45 of minute -2), and camps first fill at 1:00: nothing to stack.
		for _, t in ipairs({ -75, -15, 45 }) do
			local H, support = world(1, { camps = { { "medium", MEDIUM } }, t = t })
			support.loc = standOf(H, 1)
			check("no stack job at " .. t .. " s, before the first spawn", frame(H, support, t) == 0 and current(H, support) == nil)
		end
	end

	do
		local H, support = world(1, { camps = { { "large", LARGE } }, debug = true })
		local job, d58, d01, early
		local lines = capture(function() job, d58, d01, early = runStack(H, support, 1, LARGE, 1, 3) end)
		local attacks = ActionsOf(5, "AttackUnit")
		check("aggro at :53.5 exactly with a zero jitter", near(job.aggroAt, 113.5) and early == 0, job.aggroAt)
		check("one attack on a neutral, queued", #attacks == 1 and attacks[1].args[2] == true)
		check("desire held at :58 while walking off", near(d58, 0.7) and job.exitUntil == 121)
		check("walks the exit path", dist(ActionsOf(5, "MoveToLocation")[1].args[1], H.Lane.Camps.ByIdx(1).stack.exitPath[1]) <= 20 + 1e-6)
		-- The task ends inside the :01 frame's Think, after GetDesire has already returned the job's desire.
		local d01Want = PATH == "task" and 0.7 or 0
		check("desire at :01: 0 (legacy) or the last frame's 0.7 (task)", near(d01, d01Want) and job.ended01 == "done" and job.ended == "done", d01)

		local line = find(lines, "[H:lane] stack pid")
		local pattern = "^%[H:lane%] stack pid=%d+ camp=%d+ type=%a+ aggro=%d+%.%d planned=%d+%.%d before=%d+ after=[%d%?]+ grade=%S+ stacked=[01]$"
		check("stack line format", line ~= nil and line:match(pattern) ~= nil, line)
		check("stack line values", line ~= nil and line:find("camp=1 type=large aggro=53.5 planned=53.5 before=3 after=6 grade=ok", 1, true), line)
		check("count rose: stacked", H.Lane.Stacking.IsStacked(1) and H.Lane.Hooks.IsStacked(1))
		T = 180
		check("stack expires after the next minute", H.Lane.Stacking.IsStacked(1) == false)
	end

	do
		local H, support = world(1, { camps = { { "large", LARGE } }, debug = true })
		local lines = capture(function() runStack(H, support, 1, LARGE, 1, 0) end)
		local line = find(lines, "[H:lane] stack pid")
		check("timing ok but no new neutrals", line ~= nil and line:find("before=3 after=3 grade=ok", 1, true), line)
		check("count unchanged: not stacked", H.Lane.Stacking.IsStacked(1) == false)
	end

	do
		-- At :02 only the fresh spawn is in the box; the stacked neutrals walk back in by :04.
		local H, support = world(1, { camps = { { "large", LARGE } }, debug = true })
		local camp, earlyLine
		local lines = capture(function()
			local _
			_, _, _, _, camp = runStack(H, support, 1, LARGE, 1, 0, true)
			for _, n in ipairs(camp) do n.loc = Vector(LARGE.x, LARGE.y - 800) end
			neutrals(LARGE, 3)
			frame(H, support, 122)
			frame(H, support, 123)
		end)
		earlyLine = find(lines, "[H:lane] stack pid")
		check("returning neutrals: not settled on the :02 count", earlyLine == nil, earlyLine)
		lines = capture(function()
			for _, n in ipairs(camp) do n.loc = Vector(LARGE.x, LARGE.y) end
			frame(H, support, 124)
		end)
		local line = find(lines, "[H:lane] stack pid")
		check("returned by :04: graded stacked", line ~= nil and line:find("before=3 after=6 grade=ok", 1, true), line)
		check("returned by :04: IsStacked", H.Lane.Stacking.IsStacked(1))

		H, support = world(1, { camps = { { "large", LARGE } }, debug = true })
		lines = capture(function()
			runStack(H, support, 1, LARGE, 1, 0, true)
			frame(H, support, 122)
			frame(H, support, 124.9)
		end)
		check("count never rises: still sampling before :05", find(lines, "[H:lane] stack pid") == nil)
		lines = capture(function() frame(H, support, 125) end)
		line = find(lines, "[H:lane] stack pid")
		check("count never rises: settled at :05 unstacked", line ~= nil and line:find("after=3", 1, true) and not H.Lane.Stacking.IsStacked(1), line)
	end

	do
		-- A hands-off lane: no job, no commit, and the minute's roll is kept.
		local H, support = world(1, { camps = { { "medium", MEDIUM } }, debug = true })
		support.loc = standOf(H, 1)
		H.Orders.Post(2, { type = "LANE_HANDSOFF", sourceKey = "ping", issuerPID = 0, lane = Lane.Bot, duration = 30,
			maxResponders = 1, onlyPIDs = { 5 }, delayKind = "ping" })
		T = 103
		check("precondition: handsoff accepted", H.Orders.GetAcceptedForLane(support, "LANE_HANDSOFF", Lane.Bot) ~= nil)
		SetRandomSequence({ 0.0 })
		local lines = capture(function() check("handsoff: no stack desire", frame(H, support, 105) == 0) end)
		check("handsoff: no job, no commit", current(H, support) == nil and H.Lane.LanePlanner.Committed(support) == nil)
		check("handsoff: no job-start", find(lines, "job-start") == nil)
		check("handsoff: roll not drawn", RandomUnread() == 1)
	end

	do
		-- Out of sight at :02: unknown, assumed stacked because the aggro was in the :53-:56 band.
		local H, support = world(1, { camps = { { "large", LARGE } }, debug = true })
		local lines = capture(function()
			local m0 = 60
			T = m0 + 40
			support.loc = standOf(H, 1)
			SetRandomSequence({ 1.0, 0.25 })
			H.Lane.CampJobs.Start(support, { kind = "stack", campIdx = 1 })
			local job = current(H, support)
			frame(H, support, T)
			local camp = neutrals(LARGE, 3)
			frame(H, support, job.aggroAt)
			camp[1].target = support
			frame(H, support, job.aggroAt)
			frame(H, support, m0 + 61)
			support.loc = Vector(LARGE.x, LARGE.y + 3000)
			frame(H, support, m0 + 62)
			frame(H, support, m0 + 65)
		end)
		local line = find(lines, "[H:lane] stack pid")
		check("unseen outcome logged unknown", line ~= nil and line:find("after=? grade=unknown", 1, true), line)
		check("unseen outcome logged as assumed", find(lines, "[H:lane] stack-assumed") ~= nil)
		check("assumed stacked", H.Lane.Stacking.IsStacked(1))
	end

	do
		local H, support = world(1, { camps = { { "large", LARGE } } })
		unit({ pid = 0, bot = false, lane = Lane.Top, loc = Vector(-5000, 5000) })
		local said = {}
		H.Orders.SetAnnouncer(function(_, key) table.insert(said, key) end)
		runStack(H, support, 1, LARGE, 1, 3)
		check("big camp stack telegraphed", #said == 1 and said[1] == "say_lane_stacked_big", said[1])
		runStack(H, support, 1, LARGE, 2, 3)
		check("second stack 60 s later: no second line", #said == 1)
		runStack(H, support, 1, LARGE, 3, 3)
		check("2 min after the first: telegraphed again", #said == 2)
	end

	do
		local H, support = world(1, { camps = { { "medium", MEDIUM } } })
		unit({ pid = 0, bot = false, lane = Lane.Top, loc = Vector(-5000, 5000) })
		local said = {}
		H.Orders.SetAnnouncer(function(_, key) table.insert(said, key) end)
		runStack(H, support, 1, MEDIUM, 1, 3)
		check("medium camp stack: no telegraph", #said == 0)
	end

	do
		-- grade is timing only; the event's stacked field follows the counts.
		local function stackEvent(added)
			local H, support = world(1, { camps = { { "large", LARGE } }, telemetry = { Enable = true } })
			local lines = {}
			H.Telemetry.SetSink(function(l) table.insert(lines, l) end)
			runStack(H, support, 1, LARGE, 1, added)
			for _, l in ipairs(lines) do if l:find(" ev=lane_stack ", 1, true) then return l end end
		end
		local ev = stackEvent(0)
		check("count unchanged: grade ok but stacked=0", ev ~= nil and ev:find("grade=ok", 1, true) and ev:find(" stacked=0", 1, true), ev)
		ev = stackEvent(3)
		check("count rose: stacked=1", ev ~= nil and ev:find(" stacked=1", 1, true), ev)
	end

	do
		-- Two supports en route to the same camp, neither in the box yet: the first one's job claims it.
		local H, support = world(1, { camps = { { "medium", MEDIUM } }, at = Vector(MEDIUM.x, MEDIUM.y + 1500) })
		local other = unit({ pid = 4, pos = 4, loc = Vector(MEDIUM.x + 100, MEDIUM.y + 1500) })
		H.Lane.Config.SkillOf(other)
		H.Lane.LaneState.ForBot(other)
		T = 105
		check("precondition: first support starts the stack", near(H.Lane.CampJobDesire(support), 0.7) and current(H, support).campIdx == 1)
		local s = H.Lane.LaneState.ForBot(other)
		check("claimed camp skipped by the second support", H.Lane.Stacking.ChooseCamp(other, s, 1) == nil)
		check("second support starts no stack on it", H.Lane.CampJobDesire(other) == 0 and current(H, other) == nil)

		support.hp = 30
		T = 106
		H.Lane.CampJobDesire(support)
		check("precondition: first job aborted", current(H, support).ended == "aborted")
		check("aborted job releases the camp", H.Lane.Stacking.ChooseCamp(other, s, 1) ~= nil)
	end

	do
		-- In the laning phase too, a support whose active mode is retreat (or roam, defend) starts no stack.
		local H, support = world(1, { camps = { { "medium", MEDIUM } } })
		support.loc = standOf(H, 1)
		support.mode = dota.BotMode.Retreat
		local ok, why = eligible(H, support)
		check("retreating support in lane is not eligible", ok == false and why == "busy-mode", why)
		check("retreating support starts no stack", frame(H, support, 105) == 0 and current(H, support) == nil)
		support.mode = dota.BotMode.Laning
		check("control: laning support stacks", near(frame(H, support, 105), 0.7))
	end

	do
		-- Pushed off the stand point while waiting: the bot walks back, still waiting, and aggroes on time.
		local H, support = world(1, { camps = { { "large", LARGE } } })
		local stand = standOf(H, 1)
		support.loc = stand
		SetRandomSequence({ 1.0, 0.25 })
		H.Lane.CampJobs.Start(support, { kind = "stack", campIdx = 1 })
		frame(H, support, 100)
		check("precondition: waiting at the stand", current(H, support).phase == "wait" and #ActionsOf(5, "MoveToLocation") == 0)
		support.loc = Vector(stand.x, stand.y + 400)
		frame(H, support, 101)
		local moves = ActionsOf(5, "MoveToLocation")
		-- The stand point the job walks to carries the 20-unit path noise.
		check("pushed off while waiting: walks back to the stand", #moves == 1 and dist(moves[1].args[1], stand) <= 20 + 1e-6
			and current(H, support).phase == "wait")
		teleport(support)
		neutrals(LARGE, 3)
		frame(H, support, 113.5)
		check("back at the stand: aggroes on time", #ActionsOf(5, "AttackUnit") == 1)
	end

	do
		-- The rotation probe: a stack whose aggro is within JobUpcoming (10 s) while travelling or waiting.
		local H, support = world(1, { camps = { { "large", LARGE } } })
		support.loc = standOf(H, 1)
		SetRandomSequence({ 1.0, 0.25 })
		H.Lane.CampJobs.Start(support, { kind = "stack", campIdx = 1 })
		frame(H, support, 100)
		T = 103.4
		check("aggro 10.1 s away: no rotation planned", H.Lane.Hooks.IsRotationPlanned(support) == false)
		frame(H, support, 103.5)
		check("aggro 10 s away while waiting: rotation planned", H.Lane.Hooks.IsRotationPlanned(support) == true)
		NEUTRALS[1] = nil
		local camp = neutrals(LARGE, 1)
		frame(H, support, 113.5)
		camp[1].target = support
		frame(H, support, 113.5)
		check("walking off after the aggro: no rotation planned", current(H, support).phase == "exit" and H.Lane.Hooks.IsRotationPlanned(support) == false)
	end

	do
		-- Every way a started stack ends early: the job-abort line and the lane_job_abort event carry the legacy
		-- reason, phase and acted flag on both paths.
		local CASES = {
			{ name = "late", reason = "late", phase = "travel", acted = true, setup = function(H, bot)
				bot.loc = Vector(LARGE.x, LARGE.y + 600)
			end, run = function(H, bot, job)
				frame(H, bot, job.aggroAt + 1)
				frame(H, bot, job.aggroAt + 2)
			end },
			{ name = "no-camp", reason = "mistake:no-camp", phase = "aggro", acted = true, setup = function(H)
				NEUTRALS = {}
				H.Lane.Stacking.NoteStackAttempt(1, 0, 3)
				H.Lane.Stacking.NoteStackOutcome(1, 1, 6)
			end, run = function(H, bot, job)
				frame(H, bot, job.aggroAt)
				frame(H, bot, job.aggroAt + 1)
			end },
			{ name = "no-aggro", reason = "mistake:no-aggro", phase = "aggro", acted = true, run = function(H, bot, job)
				frame(H, bot, job.aggroAt)
				frame(H, bot, job.aggroAt + 1.9)
				frame(H, bot, job.aggroAt + 2)
			end },
			{ name = "preempted", reason = "preempted", phase = "wait", acted = true, run = function(H, bot)
				bot.mode = dota.BotMode.Laning
				for _, t in ipairs({ 100.5, 101.6 }) do T = t H.Lane.CampJobDesire(bot) H.Tasks.Tick(bot) end
			end },
			{ name = "mode-end", reason = "mode-end", phase = "wait", acted = true, run = function(H, bot) H.Lane.CampJobOnEnd(bot) end },
			{ name = "mode-end before acting", reason = "mode-end", phase = "travel", acted = false, think = false,
				run = function(H, bot) H.Lane.CampJobOnEnd(bot) end },
			{ name = "run", reason = "run", phase = "wait", acted = true, run = function(H, bot) H.Lane.CampJobAbort(bot, "run") end },
			{ name = "flag-off", reason = "flag-off", phase = "wait", acted = true, run = function(H, bot)
				H.Lane.Config.Settings().Stack = false
				frame(H, bot, 101)
			end },
			{ name = "dead", reason = "dead", phase = "wait", acted = true, run = function(H, bot)
				bot.alive = false
				frame(H, bot, 101)
			end },
			-- Farm stays active but never thinks (a stun): only the time limit after the aggro second ends the job.
			{ name = "timeout", reason = "timeout", phase = "wait", acted = true, run = function(H, bot, job)
				for _, t in ipairs({ job.aggroAt, job.aggroAt + 15 }) do T = t H.Lane.CampJobDesire(bot) H.Tasks.Tick(bot) end
				check("timeout: kept up to aggro + 15 s", current(H, bot).ended == nil)
				frame(H, bot, job.aggroAt + 15.1)
			end },
			{ name = "low-hp", reason = "low-hp", phase = "wait", acted = true, setup = function() LANING = false end,
				run = function(H, bot)
					bot.hp = 10
					frame(H, bot, 101)
				end },
			{ name = "handsoff", reason = "handsoff", phase = "wait", acted = true, run = function(H, bot)
				H.Orders.Post(2, { type = "LANE_HANDSOFF", sourceKey = "ping", issuerPID = 0, lane = Lane.Bot, duration = 30,
					maxResponders = 1, onlyPIDs = { 5 }, delayKind = "ping" })
				frame(H, bot, 103)
			end },
		}
		for _, case in ipairs(CASES) do
			local H, support = world(1, { camps = { { "large", LARGE } }, debug = true, telemetry = { Enable = true } })
			support.loc = standOf(H, 1)
			neutrals(LARGE, 3)
			if case.setup then case.setup(H, support) end
			local events = {}
			H.Telemetry.SetSink(function(l) table.insert(events, l) end)
			local job, reserved
			local lines = capture(function()
				SetRandomSequence({ 1.0, 0.25 })
				H.Lane.CampJobs.Start(support, { kind = "stack", campIdx = 1 })
				job = current(H, support)
				if case.think ~= false then frame(H, support, 100) end
				reserved = not claimable(H, support)
				case.run(H, support, job)
			end)
			for _, e in ipairs(events) do table.insert(LOG[PATH], e) end
			local line = find(lines, "[H:lane] job-abort")
			local want = string.format("[H:lane] job-abort pid=5 kind=stack camp=1 key=%s reason=%s divert=0.00", H.Lane.Camps.ByIdx(1).key or "-", case.reason)
			check(case.name .. ": job-abort line", line == want, line)
			local ev
			for _, e in ipairs(events) do if e:find(" ev=lane_job_abort ", 1, true) then ev = e end end
			local function field(key) return ev and (ev:match(" " .. key .. '="([^"]*)"') or ev:match(" " .. key .. "=(%S+)")) end
			check(case.name .. ": event reason, phase and acted", field("reason") == case.reason and field("phase") == case.phase
				and field("acted") == (case.acted and "1" or "0"), ev)
			check(case.name .. ": ended aborted, desire dropped", current(H, support).ended == "aborted" and H.Lane.CampJobDesire(support) == 0)
			-- The timeout lands after the walk-off's end, where the reservation lapses by itself.
			if case.name ~= "timeout" then check(case.name .. ": reservation released", reserved and claimable(H, support)) end
			-- The timeout lands in the next wave cycle, past the commit's own.
			if case.name ~= "timeout" then
				check(case.name .. ": planner commit " .. (case.acted and "kept" or "released"),
					(H.Lane.LanePlanner.Committed(support) ~= nil) == case.acted, H.Lane.LanePlanner.Committed(support))
			end
			if case.name == "no-camp" then check("no-camp: stack cleared", H.Lane.Stacking.IsStacked(1) == false) end
			if case.name == "late" then check("late: never attacked", #ActionsOf(5, "AttackUnit") == 0) end
		end
	end

	do
		-- With Tasks.Stack off, the task machinery stays silent: no task line, no task claim.
		if PATH == "legacy" then
			local H, support = world(1, { camps = { { "large", LARGE } }, debug = true })
			local lines = capture(function() runStack(H, support, 1, LARGE, 1, 3) end, true)
			local taskLine
			for _, l in ipairs(lines) do
				if l:find("[H:tasks]", 1, true) and not l:find("[H:tasks] support", 1, true) then taskLine = l end
			end
			check("flag off: a full stack logs no task line", taskLine == nil, taskLine)
			check("flag off: the stack ran as the legacy job", H.Lane.CampJobs.Current(support).phase == "done" and H.Lane.StackTask.Job(support) == nil)
		end
	end

	do
		-- Started from farm's GetDesire but never stepped while farm IS the active mode (Think returns early): the
		-- runner cancels it after its 1 s grace, and the abort releases what an unacted legacy abort releases.
		if PATH == "task" then
			local H, support = world(1, { camps = { { "medium", MEDIUM } }, debug = true, telemetry = { Enable = true } })
			support.loc = standOf(H, 1)
			support.mode = dota.BotMode.Farm
			local events = {}
			H.Telemetry.SetSink(function(l) table.insert(events, l) end)
			local FARM, RAW = dota.BotMode.Farm, 0.1
			local function farmDesire(t)
				T = t
				H.Tasks.Tick(support)
				local d = H.Lane.CampJobDesire(support)
				if d > 0 then H.Lane.CampJobRawDesire(support, d) end
				return d
			end
			local lines = capture(function()
				check("precondition: the task starts from GetDesire", near(farmDesire(105), 0.7) and current(H, support).ended == nil)
				farmDesire(105.5)
				check("precondition: within the grace farm holds the floor", H.Intent.Resolve(support, FARM, RAW) >= 0.7)
				check("precondition: camp reserved", not claimable(H, support))
				-- The runner's own claim, posted by Tick alone, holds farm's floor before the task's first Step.
				T = 105.7
				H.Tasks.Tick(support)
				check("precondition: the unstepped task's claim holds farm", near(H.Intent.Resolve(support, FARM, RAW), 0.7)
					and H.Intent.Explain(support, FARM):find("by task:stack", 1, true) ~= nil, H.Intent.Explain(support, FARM))
				farmDesire(106.05)
			end, true)
			check("unstepped: ended after the grace", current(H, support).ended == "aborted")
			T = 106.05 + H.Intent.Get().ClaimTTL
			check("unstepped: farm's floor gone within ClaimTTL", near(H.Intent.Resolve(support, FARM, RAW), RAW), H.Intent.Resolve(support, FARM, RAW))
			check("unstepped: no task claim left", H.Intent.Explain(support, FARM):find("task:", 1, true) == nil, H.Intent.Explain(support, FARM))
			local line = find(lines, "[H:lane] job-abort")
			check("unstepped: logged as preempted", line ~= nil and line:find("reason=preempted", 1, true), line)
			local ev
			for _, e in ipairs(events) do if e:find(" ev=lane_job_abort ", 1, true) then ev = e end end
			check("unstepped: acted=false, phase travel", ev ~= nil and ev:find(" acted=0", 1, true) and ev:find(" phase=travel", 1, true), ev)
			check("unstepped: planner commit released", H.Lane.LanePlanner.Committed(support) == nil)
			check("unstepped: reservation released", claimable(H, support))
			check("unstepped: the same attempt is not started again", farmDesire(106.2) == 0 and current(H, support).ended == "aborted")
		end
	end

	do
		local H, support = world(1, { camps = { { "large", LARGE } }, debug = true, at = Vector(1500, -6000) })
		unit({ pid = 0, bot = false, loc = Vector(1400, -6000) })
		local far = unit({ pid = 2, pos = 3, loc = Vector(5000, 0) })
		T = 70
		local lines = capture(function()
			H.Tick(support)
			T = T + 0.5
			for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = 0, string = "!hstacktest 1", team_only = false }) end
		end)
		local job = current(H, support)
		check("hstacktest starts a forced stack on the nearest bot", job ~= nil and job.kind == "stack" and job.forced == true)
		check("hstacktest targets the next stack second", job ~= nil and job.baseAggro == 113.5, job and job.baseAggro)
		check("hstacktest leaves other bots", current(H, far) == nil)
		check("hstacktest logged", find(lines, "hstacktest pid=5 camp=1 started=true") ~= nil)
	end
end

-- Both paths ran the same scenarios: every captured log line and every abort event must match, in order.
do
	local a, b = LOG.legacy, LOG.task
	local first
	for i = 1, math.max(#a, #b) do
		if a[i] ~= b[i] and first == nil then first = i end
	end
	check("legacy and task paths log identical lines and abort events", first == nil and #a > 0,
		first and string.format("#%d legacy=%s task=%s", first, tostring(a[first]), tostring(b[first])))
	local generic
	for _, l in ipairs(b) do if l:find("interrupted", 1, true) or l:find("cancelled", 1, true) then generic = l end end
	check("task path: no runner-generic reason in any log line", generic == nil and #b > 0, generic)
end

finish()
