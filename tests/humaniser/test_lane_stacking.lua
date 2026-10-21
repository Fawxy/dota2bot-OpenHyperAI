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

-- Radiant bot lane: core pid 1 (pos 1) at the front, support pid 5 (pos 5) at `at`, one enemy far away.
-- `camps` is a list of { type, location }; spawner idx follows list order.
local function world(skill, opts)
	opts = opts or {}
	local H = LaneFresh(opts.cfg or { Enable = true }, { skill = skill, debug = opts.debug, telemetry = opts.telemetry })
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

local function eligible(H, bot)
	local s = H.Lane.LaneState.ForBot(bot)
	return H.Lane.Stacking.Eligible(bot, s, H.Lane.LaneState.Enemies(bot, Lane.Bot))
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, s) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err) end
	return printed
end

local function find(lines, prefix)
	local found
	for _, l in ipairs(lines) do if l:find(prefix, 1, true) then found = l end end
	return found
end

local function frame(H, bot, t)
	T = t
	local d = H.Lane.CampJobDesire(bot)
	if d > 0 then H.Lane.CampJobThink(bot) end
	return d
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
-- `added` more spawned at the next :00, then settled by :05. Returns the job, the desires at :58 and the next :01,
-- the attacks issued before the order's lead, and the camp's original neutrals. `partial` stops after :01.
local function runStack(H, bot, idx, at, minute, added, partial)
	local m0 = minute * 60
	T = m0 + 40
	bot.loc = standOf(H, idx)
	SetRandomSequence({ 1.0, 0.25 })
	check("precondition: stack job starts", H.Lane.CampJobs.Start(bot, { kind = "stack", campIdx = idx }))
	local job = H.Lane.CampJobs.Current(bot)
	NEUTRALS = {}
	local camp = neutrals(at, 3)
	-- The injected J.GetAttackProDelayTime reads 0.3 s, so the order goes out at aggroAt - 0.3.
	frame(H, bot, job.aggroAt - 0.4)
	local early = #ActionsOf(bot.pid, "AttackUnit")
	frame(H, bot, job.aggroAt - 0.3)
	camp[1].target = bot
	frame(H, bot, job.aggroAt)
	frame(H, bot, m0 + 56)
	teleport(bot)
	local d58 = frame(H, bot, m0 + 58)
	local d01 = frame(H, bot, m0 + 61)
	if not partial then
		neutrals(at, added)
		frame(H, bot, m0 + 62)
		frame(H, bot, m0 + 65)
	end
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
	-- Support at the medium camp's stand at 1:45: the stack window (from :45 to :54) is open.
	local function lockWorld(cfg)
		local H, support = world(1, { camps = { { "medium", MEDIUM } }, cfg = cfg })
		support.loc = standOf(H, 1)
		return H, support
	end
	local H, support = lockWorld()
	check("window open: stack job starts", near(frame(H, support, 105), 0.7) and H.Lane.CampJobs.Current(support).kind == "stack")
	check("stack commits the cycle", H.Lane.LanePlanner.Committed(support) == "stack")

	H, support = lockWorld()
	T = 100
	H.Lane.LanePlanner.Commit(support, "full_pull")
	check("full pull in the cycle: no stack job", frame(H, support, 105) == 0 and H.Lane.CampJobs.Current(support) == nil)

	H, support = lockWorld()
	check("before :45: no stack job", frame(H, support, 104) == 0 and H.Lane.CampJobs.Current(support) == nil)

	H, support = lockWorld({ Enable = true, Stack = false })
	check("Stack off: no stack job", frame(H, support, 105) == 0 and H.Lane.CampJobs.Current(support) == nil)
end

do
	-- Before the horn DotaTime is negative (-1:15 is :45 of minute -2), and camps first fill at 1:00: nothing to stack.
	for _, t in ipairs({ -75, -15, 45 }) do
		local H, support = world(1, { camps = { { "medium", MEDIUM } }, t = t })
		support.loc = standOf(H, 1)
		check("no stack job at " .. t .. " s, before the first spawn", frame(H, support, t) == 0 and H.Lane.CampJobs.Current(support) == nil)
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
	check("no desire at :01", d01 == 0 and job.phase == "done")

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
	check("handsoff: no job, no commit", H.Lane.CampJobs.Current(support) == nil and H.Lane.LanePlanner.Committed(support) == nil)
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
		local job = H.Lane.CampJobs.Current(support)
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
	check("precondition: first support starts the stack", near(H.Lane.CampJobDesire(support), 0.7) and H.Lane.CampJobs.Current(support).campIdx == 1)
	local s = H.Lane.LaneState.ForBot(other)
	check("claimed camp skipped by the second support", H.Lane.Stacking.ChooseCamp(other, s, 1) == nil)
	check("second support starts no stack on it", H.Lane.CampJobDesire(other) == 0 and H.Lane.CampJobs.Current(other) == nil)

	support.hp = 30
	T = 106
	H.Lane.CampJobDesire(support)
	check("precondition: first job aborted", H.Lane.CampJobs.Current(support).phase == "return")
	check("aborted job releases the camp", H.Lane.Stacking.ChooseCamp(other, s, 1) ~= nil)
end

do
	-- A camp both teams have a job on (the enemy off lane's pull camp): only an ally's stack claim blocks it.
	local H, support = world(1, { camps = { { "medium", MEDIUM } }, at = Vector(MEDIUM.x, MEDIUM.y + 1500) })
	local S = H.Lane.Stacking
	local s = H.Lane.LaneState.ForBot(support)
	T = 105
	S.Reserve(1, 4, T + 30)
	unit({ pid = 4, pos = 4, loc = Vector(0, 0) })
	check("precondition: an ally's claim blocks", S.ChooseCamp(support, s, 1) == nil)
	S.Reserve(1, 10, T + 30)
	S.Release(1, 4)
	check("enemy's claim on the same camp does not block", S.ChooseCamp(support, s, 1) ~= nil)
	S.Reserve(1, 4, T + 30)
	S.Release(1, 10)
	check("enemy's release keeps the ally's claim", S.ChooseCamp(support, s, 1) == nil)
end

do
	-- In the laning phase too, a support whose active mode is retreat (or roam, defend) starts no stack.
	local H, support = world(1, { camps = { { "medium", MEDIUM } } })
	support.loc = standOf(H, 1)
	support.mode = dota.BotMode.Retreat
	local ok, why = eligible(H, support)
	check("retreating support in lane is not eligible", ok == false and why == "busy-mode", why)
	check("retreating support starts no stack", frame(H, support, 105) == 0 and H.Lane.CampJobs.Current(support) == nil)
	support.mode = dota.BotMode.Laning
	check("control: laning support stacks", near(frame(H, support, 105), 0.7))
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
	local job = H.Lane.CampJobs.Current(support)
	check("hstacktest starts a forced stack on the nearest bot", job ~= nil and job.kind == "stack" and job.forced == true)
	check("hstacktest targets the next stack second", job ~= nil and job.baseAggro == 113.5, job and job.baseAggro)
	check("hstacktest leaves other bots", H.Lane.CampJobs.Current(far) == nil)
	check("hstacktest logged", find(lines, "hstacktest pid=5 camp=1 started=true") ~= nil)
end

do
	-- A stack under way is committed like a pull: the enemy laners standing by the core do not end it.
	local H, support, core = world(1, { camps = { { "medium", MEDIUM } } })
	support.loc = standOf(H, 1)
	T = 100
	check("precondition: stack job starts", H.Lane.CampJobs.Start(support, { kind = "stack", campIdx = 1 }))
	frame(H, support, 100)
	unit({ pid = 11, team = 3, pos = 5, loc = Vector(FRONT.x - 600, FRONT.y + 300) })
	unit({ pid = 12, team = 3, pos = 1, loc = Vector(FRONT.x + 700, FRONT.y) })
	T = 100.6
	local s = H.Lane.LaneState.ForBot(support)
	local enemies = H.Lane.LaneState.Enemies(support, Lane.Bot)
	check("precondition: a new stack would not start", H.Lane.Stacking.Eligible(support, s, enemies) == false)
	check("laners by the core: the stack goes on", near(frame(H, support, 100.6), 0.7) and H.Lane.CampJobs.Active(support))
	core.hp = 30
	T = 101.2
	check("core low: the stack is dropped", frame(H, support, 101.2) == 0 and not H.Lane.CampJobs.Active(support))
end

local function stackJob(H, bot, idx)
	T = 100
	SetRandomSequence({ 1.0, 0.25 })
	check("precondition: stack job starts", H.Lane.CampJobs.Start(bot, { kind = "stack", campIdx = idx }))
	return H.Lane.CampJobs.Current(bot)
end

do
	-- console.9055828679: skywrath reached camp 17's stand 1-2 s after its aggro second and only then attacked
	-- (aggro 54.7 / 55.1 for 53.5), though the camp was in range on the way. Now the camp is attacked from where it is
	-- first seen, the order going out the attack's lead (the injected J.GetAttackProDelayTime: 0.3 s) early.
	local H, support = world(1, { camps = { { "large", LARGE } } })
	local job = stackJob(H, support, 1)
	local stand = standOf(H, 1)
	support.loc = Vector(stand.x + 500, stand.y)
	local troll = MakeNeutral({ x = LARGE.x, y = LARGE.y })
	frame(H, support, job.aggroAt - 0.4)
	check("en route: no attack before the lead", #ActionsOf(5, "AttackUnit") == 0 and job.phase == "travel")
	frame(H, support, job.aggroAt - 0.3)
	local a = ActionsOf(5, "AttackUnit")
	check("en route: attacks the lead before the planned second", #a == 1 and a[1].args[1] == troll and job.phase == "aggro")
	-- Ranged: released at aggroAt - 0.2 from 500 away at 1,000/s, so the hit lands at aggroAt + 0.3.
	support.range, support.projSpeed = 600, 1000
	support.loc = Vector(LARGE.x + 500, LARGE.y)
	support.lastAttack = job.aggroAt - 0.2
	frame(H, support, job.aggroAt - 0.1)
	check("ranged aggro logged when the projectile lands", job.actualAggro ~= nil and math.abs(job.actualAggro - (job.aggroAt + 0.3)) < 1e-6, job.actualAggro)
end

do
	-- console.9055828679: warlock stood at evil_2's stand points, behind the trees along the box edge, saw no neutral and
	-- aborted `mistake:no-camp` four times. An unseen camp is walked in on before the aggro.
	local H, support = world(1, { camps = { { "large", LARGE } } })
	local job = stackJob(H, support, 1)
	support.loc = standOf(H, 1)
	local troll = MakeNeutral({ x = LARGE.x, y = LARGE.y })
	troll.CanBeSeen = function() return false end
	local radii = H.Lane.Config.Settings().Radii
	frame(H, support, job.aggroAt - 3.5)
	check("unseen camp: waits at the stand until StandApproachLead", job.phase == "wait")
	frame(H, support, job.aggroAt - 3)
	local m = ActionsOf(5, "MoveToLocation")
	local to = m[#m] and m[#m].args[1]
	check("unseen camp: walks in toward the spawner origin", to ~= nil and dist(to, LARGE) <= radii.StandApproach + 1e-6, to and dist(to, LARGE))
	teleport(support)
	troll.CanBeSeen = function() return true end
	frame(H, support, job.aggroAt - 0.3)
	check("unseen camp: attacks once it is in sight", #ActionsOf(5, "AttackUnit") == 1)
end

finish()
