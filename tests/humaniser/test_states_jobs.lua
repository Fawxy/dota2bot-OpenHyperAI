dofile(HARNESS_DIR .. "/lane_world.lua")
-- Camp jobs as behaviour states (humaniser/states/camp_job.ts, team slices 7-8): OHA plans the job, the SDK's
-- stack/pull verbs execute it in place of camp_jobs' step(), and OHA's bookkeeping (outcome, grade, aborts) stays.
local dota = require("bots/ts_libs/dota/index")
local Lane, FARM, LANING = dota.Lane, dota.BotMode.Farm, dota.BotMode.Laning
local BUNDLE = "bots/FunLib/engine/tasks"

local FRONT = Vector(0, -5000)
local SMALL = Vector(-1600, -6200)
local LARGE = Vector(1500, -6500)

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

-- The stacking tests' world: core pid 1 (pos 1) at the front, support pid 5 at `at`, one enemy far away; plus the
-- state layer (Teams 'all': this world has no human) owning `own`.
local function world(opts)
	opts = opts or {}
	package.loaded[BUNDLE] = nil
	local states = opts.states or { Enable = true, Shadow = true, Teams = "all", Own = opts.own or { stack = { 5 }, pull = { 5 } } }
	local H = LaneFresh(opts.cfg or { Enable = true }, { skill = opts.skill or 1, debug = true, telemetry = { Enable = true },
		transitions = { Caution = false }, states = states })
	T = opts.t or 100
	CURRENT_TEAM = 2
	OBSERVER = 5
	SPAWNERS = {}
	for _, c in ipairs(opts.camps or {}) do table.insert(SPAWNERS, spawner(c[1], c[2])) end
	H.Lane.Camps.ResetCache()
	local core = unit({ pid = 1, pos = 1, loc = opts.coreAt })
	local support = unit({ pid = 5, pos = opts.pos or 5, loc = opts.at or Vector(0, -5600), hp = opts.hp })
	unit({ pid = 10, team = 3, pos = 3, lane = Lane.Top, loc = Vector(6000, 6000) })
	H.Lane.Config.SkillOf(support)
	H.Lane.Config.SkillOf(core)
	H.Lane.LaneState.ForBot(support)
	return H, support, core
end

local function standOf(H, idx)
	local C = H.Lane.Camps
	return H.Lane.Stacking.StandPoint(C.SpawnerByIdx(idx), C.ByIdx(idx))
end

-- One frame as the game plays it: Humaniser.Tick's States and Tasks ticks, farm's GetDesire, then its Think when
-- farm wins. Moves arrive at once; a neutral hit this frame turns on the bot.
local function frame(H, bot, dt)
	local n0 = #ACTIONS
	H.States.Tick(bot)
	H.Tasks.Tick(bot)
	local d = H.Lane.CampJobDesire(bot)
	if d > 0 then
		bot.mode = FARM
		H.Lane.CampJobThink(bot)
	else
		bot.mode = LANING
	end
	for i = #ACTIONS, n0 + 1, -1 do
		local a = ACTIONS[i]
		if a.pid == bot.pid and a.kind == "MoveToLocation" then
			bot.loc = Vector(a.args[1].x, a.args[1].y)
			break
		end
	end
	for i = n0 + 1, #ACTIONS do
		local a = ACTIONS[i]
		if a.pid == bot.pid and a.kind == "AttackUnit" and a.args[1].team == 4 and not bot.noAggro then a.args[1].target = bot end
	end
	T = T + (dt or 0.1)
	return d
end

local function runUntil(H, bot, t, dt)
	while T < t do frame(H, bot, dt) end
end

local function capture(fn)
	local printed, old = {}, print
	print = function(s) table.insert(printed, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err, 0) end
	return printed
end

local function find(lines, needle)
	local found
	for _, l in ipairs(lines) do if l:find(needle, 1, true) then found = l end end
	return found
end

local function neutrals(at, n)
	local list = {}
	for i = 1, n do table.insert(list, MakeNeutral({ x = at.x + i * 10, y = at.y })) end
	return list
end

-- Starts a stack job on camp 1 at minute 1 + :40 (zero jitter), 3 neutrals in the box, `added` more at the next :00.
local function stackGame(H, bot, at, added, o)
	o = o or {}
	T = 100
	bot.loc = o.from or standOf(H, 1)
	SetRandomSequence({ 1.0, 0.25 })
	check("precondition: stack job starts", H.Lane.CampJobs.Start(bot, { kind = "stack", campIdx = 1 }))
	NEUTRALS = {}
	local camp = o.camp or neutrals(at, 3)
	if o.camp then for _, n in ipairs(o.camp) do table.insert(NEUTRALS, n) end end
	runUntil(H, bot, 120)
	neutrals(at, added)
	runUntil(H, bot, 126)
	return H.Lane.CampJobs.Current(bot), camp
end

-- Owned stack: the SDK body runs the job; OHA's outcome line and stack bookkeeping are unchanged.
do
	local H, support = world({ camps = { { "large", LARGE } } })
	local job
	local lines = capture(function() job = stackGame(H, support, LARGE, 3) end)
	local attacks = ActionsOf(5, "AttackUnit")
	check("stack: job executed by the SDK body", job.sdk == true and (job.sdkFrames or 0) > 50, job.sdkFrames)
	check("stack: step() ran only until the state started (<= 3 frames)", (job.legacyFrames or 0) <= 3, job.legacyFrames)
	check("stack: one attack on the camp", #attacks == 1)
	-- The order goes out its lead (0.4 s without GetAttackPoint) before the planned 53.5.
	local line = find(lines, "[H:lane] stack pid")
	check("stack: outcome logged as before", line ~= nil and line:find("camp=1 type=large", 1, true) and line:find("before=3 after=6", 1, true)
		and line:find("stacked=1", 1, true), line)
	local aggro = line and tonumber(line:match("aggro=([%d%.]+)"))
	check("stack: aggro within 0.5 s of the planned :53.5", aggro ~= nil and math.abs(aggro - 53.5) <= 0.5, aggro)
	check("stack: counted as stacked", H.Lane.Stacking.IsStacked(1))
	check("stack: job done after the walk-off", job.phase == "done")
	local exitPath = H.Lane.Camps.ByIdx(1).stack.exitPath
	local walked = false
	for _, m in ipairs(ActionsOf(5, "MoveToLocation")) do if dist(m.args[1], exitPath[#exitPath]) <= 60 then walked = true end end
	check("stack: walked the exit path", walked)
	check("stack: state task ended ok", find(lines, "ev=state_task") ~= nil and find(lines, "state=stack result=ok") ~= nil, find(lines, "ev=state_task"))
	check("stack: job_exec event", find(lines, "ev=job_exec") ~= nil and find(lines, "ev=job_exec"):find("result=ok", 1, true) ~= nil, find(lines, "ev=job_exec"))
	check("stack: back to no state job, farm desire 0", frame(H, support) == 0)
end

-- Not owned (pos 4 when only pos 5 is listed): step() runs the job as before; the state is shadowed.
do
	local H, support = world({ camps = { { "large", LARGE } }, pos = 4 })
	local job
	local lines = capture(function() job = stackGame(H, support, LARGE, 3) end)
	check("unowned: step() runs it", job.sdk ~= true and (job.sdkFrames or 0) == 0)
	check("unowned: still stacked", find(lines, "[H:lane] stack pid") ~= nil and find(lines, "[H:lane] stack pid"):find("stacked=1", 1, true) ~= nil)
	check("unowned: shadow state chosen", find(lines, "to=stack") ~= nil and find(lines, "owned=0") ~= nil)
	check("unowned: no state task", find(lines, "ev=state_start") == nil)
end

-- Kill switch: States.Enable = false leaves every job on step().
do
	local H, support = world({ camps = { { "large", LARGE } }, states = { Enable = false, Own = { stack = { 5 } } } })
	local job
	local lines = capture(function() job = stackGame(H, support, LARGE, 3) end)
	check("off: step() runs it", job.sdk ~= true)
	check("off: no state events", find(lines, "ev=state ") == nil)
end

-- Idle neutrals stand just outside the spawn box: the SDK's box margin still finds them (step()'s strict box did not).
do
	local H, support = world({ camps = { { "large", LARGE } } })
	local outside = { MakeNeutral({ x = LARGE.x + 230, y = LARGE.y }) }
	local job
	local lines = capture(function() job = stackGame(H, support, LARGE, 2, { camp = outside }) end)
	if DEBUG_JOBS then for _, l in ipairs(lines) do if not l:find("lane_eq", 1, true) then print(l) end end end
	check("margin: aggro landed on a neutral 80 outside the box", #ActionsOf(5, "AttackUnit") == 1, #ActionsOf(5, "AttackUnit"))
	check("margin: no mistake:no-camp", find(lines, "reason=mistake:no-camp") == nil)
	check("margin: stack attempt counted", find(lines, "[H:lane] stack pid") ~= nil)
end

-- Same world on step(): the strict box misses that neutral (the known mistake:no-camp).
do
	local H, support = world({ camps = { { "large", LARGE } }, states = { Enable = false } })
	local outside = { MakeNeutral({ x = LARGE.x + 230, y = LARGE.y }) }
	local lines = capture(function() stackGame(H, support, LARGE, 2, { camp = outside }) end)
	check("margin legacy: no-camp", find(lines, "reason=mistake:no-camp") ~= nil)
end

-- Empty camp at the stand point: OHA's abort and the camp's stack cleared, as step() does.
do
	local H, support = world({ camps = { { "large", LARGE } } })
	local job
	local lines = capture(function() job = stackGame(H, support, LARGE, 0, { camp = {} }) end)
	check("no camp: aborted mistake:no-camp", job.phase == "return" and find(lines, "reason=mistake:no-camp") ~= nil, job.phase)
	check("no camp: state left after the failure", (H.States.Describe(support) or ""):sub(1, 5) ~= "stack", H.States.Describe(support))
end

-- The aggro never confirms (whiff): mistake:no-aggro.
do
	local H, support = world({ camps = { { "large", LARGE } } })
	support.noAggro = true
	local lines = capture(function() stackGame(H, support, LARGE, 0) end)
	check("whiff: mistake:no-aggro", find(lines, "reason=mistake:no-aggro") ~= nil)
end

-- OHA's continue checks still end an SDK-run job: low HP mid-travel aborts it and the body stops.
do
	local H, support = world({ camps = { { "large", LARGE } } })
	local lines = capture(function()
		T = 100
		support.loc = Vector(0, -5600)
		SetRandomSequence({ 1.0, 0.25 })
		H.Lane.CampJobs.Start(support, { kind = "stack", campIdx = 1 })
		NEUTRALS = {}
		neutrals(LARGE, 3)
		runUntil(H, support, 105)
		support.hp = 10
		runUntil(H, support, 108)
	end)
	local job = H.Lane.CampJobs.Current(support)
	check("unsafe: OHA aborted the job", job.phase == "return" and find(lines, "ev=lane_job_abort") ~= nil)
	check("unsafe: no attack issued", #ActionsOf(5, "AttackUnit") == 0)
	check("unsafe: state task ended by its guard", find(lines, "msg=job-ended") ~= nil, find(lines, "ev=state_task"))
end

-- Farm loses (retreat wins): OHA's mode-end abort ends the job, the state leaves without restarting the body.
do
	local H, support = world({ camps = { { "large", LARGE } } })
	local lines = capture(function()
		T = 100
		support.loc = Vector(0, -5600)
		SetRandomSequence({ 1.0, 0.25 })
		H.Lane.CampJobs.Start(support, { kind = "stack", campIdx = 1 })
		NEUTRALS = {}
		neutrals(LARGE, 3)
		runUntil(H, support, 104)
		H.Lane.CampJobOnEnd(support)
		for _ = 1, 30 do
			H.States.Tick(support)
			H.Tasks.Tick(support)
			support.mode = dota.BotMode.Retreat
			T = T + 0.1
		end
	end)
	check("mode end: job aborted", H.Lane.CampJobs.Current(support).phase == "return")
	check("mode end: state left", (H.States.Describe(support) or ""):sub(1, 5) ~= "stack", H.States.Describe(support))
	local starts = 0
	for _, l in ipairs(lines) do if l:find("ev=state_start", 1, true) and l:find("state=stack", 1, true) then starts = starts + 1 end end
	check("mode end: body started once", starts == 1, starts)
end

-- The state starts only after step() ran the job past its wait (held up behind another job state): the body hands
-- the job back instead of replaying travel and aggro over it.
do
	local H, support = world({ camps = { { "large", LARGE } } })
	local job
	local lines = capture(function()
		T = 100
		support.loc = standOf(H, 1)
		SetRandomSequence({ 1.0, 0.25 })
		H.Lane.CampJobs.Start(support, { kind = "stack", campIdx = 1 })
		job = H.Lane.CampJobs.Current(support)
		NEUTRALS = {}
		neutrals(LARGE, 3)
		job.phase, job.actualAggro = "exit", job.aggroAt
		runUntil(H, support, 105)
	end)
	check("late start: handed back to step()", job.sdk == false)
	check("late start: no aggro replayed", #ActionsOf(5, "AttackUnit") == 0)
	check("late start: state task ended legacy-resume", find(lines, "msg=legacy-resume") ~= nil)
end

-- Pulls: the safe-lane small camp (the stacking world above has no pull camp). Default fronts make the planner want a
-- full pull at :15/:45; the support waits at its stand point.
local LARGE_PULL = Vector(-1000, -6300)
local WAVE_CFG = { Enable = true, PullTiming = { LanePaths = { radiant_bot = { { -9400, -5000 }, { 7000, -5000 } } } } }

local function pullWorld(opts)
	opts = opts or {}
	package.loaded[BUNDLE] = nil
	local states = opts.states or { Enable = true, Shadow = true, Teams = "all", Own = { stack = { 5 }, pull = { 5 } } }
	local H = LaneFresh(opts.cfg or { Enable = true }, { skill = 1, debug = true, telemetry = { Enable = true }, states = states })
	T = 70
	CURRENT_TEAM = 2
	OBSERVER = 1
	SPAWNERS = { spawner("small", SMALL) }
	if opts.large then table.insert(SPAWNERS, spawner("large", LARGE_PULL)) end
	H.Lane.Camps.ResetCache()
	local C = H.Lane.Camps
	local data = C.ByIdx(1)
	local stand = C.BoxEdgePoint(C.SpawnerByIdx(1), data.pull.path[1], 150)
	unit({ pid = 1, pos = 1 })
	local support = unit({ pid = 5, pos = 5, loc = Vector(stand.x, stand.y) })
	unit({ pid = 10, team = 3, pos = 3, lane = Lane.Top })
	return H, support, data
end

do
	local H, support = pullWorld()
	local neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local job, waved
	local lines = capture(function()
		runUntil(H, support, 72.5)
		job = H.Lane.CampJobs.Current(support)
		while job.phase ~= "watch" and T < 90 do frame(H, support) end
		for _ = 1, 4 do MakeCreep({ team = 2, x = job.meet.x, y = job.meet.y, target = neutral }) end
		waved = T
		runUntil(H, support, 95)
	end)
	check("pull: full pull planned", job ~= nil and job.kind == "full_pull")
	check("pull: run by the SDK body", job.sdk == true and (job.sdkFrames or 0) > 50 and (job.legacyFrames or 0) <= 3, job.sdkFrames)
	local attacks = ActionsOf(5, "AttackUnit")
	check("pull: one attack on the camp", #attacks == 1 and attacks[1].args[1] == neutral)
	check("pull: aggro recorded within 0.5 s of the planned :15", job.actualAggro ~= nil and math.abs(job.actualAggro - job.aggroAt) <= 0.5, job.actualAggro)
	check("pull: reached the meet point", dist(support.loc, job.meet) <= 120, dist(support.loc, job.meet))
	local line = find(lines, "[H:lane] job pid")
	check("pull: graded job line as step() logs it", line ~= nil and line:find("kind=full camp=1", 1, true) and line:find("divert=1.00 grade=ok", 1, true), line)
	check("pull: job done", job.phase == "done")
	check("pull: state task ok", find(lines, "state=pull result=ok") ~= nil, find(lines, "state=pull"))
end

do
	-- Double pull: the hard camp's hit lands first, then the small camp's on its own second; only the small hit is graded.
	local H, support = pullWorld({ large = true, cfg = WAVE_CFG })
	local small = MakeNeutral({ x = SMALL.x, y = SMALL.y })
	local large = MakeNeutral({ x = LARGE_PULL.x, y = LARGE_PULL.y })
	local job
	local lines = capture(function()
		runUntil(H, support, 72.5)
		job = H.Lane.CampJobs.Current(support)
		local hardAt = job and job.aggroAt
		while job ~= nil and job.phase ~= "watch" and job.phase ~= "return" and T < 100 do frame(H, support) end
		job.hardAt = hardAt
	end)
	check("double: planned", job ~= nil and job.kind == "double_pull", job and job.kind)
	local attacks = ActionsOf(5, "AttackUnit")
	check("double: hard camp hit first, then the small camp", #attacks == 2 and attacks[1].args[1] == large and attacks[2].args[1] == small, #attacks)
	check("double: graded camp's aggro is the small one", job.actualAggro ~= nil and job.actualAggro > job.hardAt + 0.5, job.actualAggro)
	check("double: led to watch", job.phase == "watch", job.phase)
	check("double: SDK body ran it", job.sdk == true and (job.legacyFrames or 0) <= 3)
end

do
	-- Pull owned for pos 4 only: pos 5's pull stays on step().
	local H, support = pullWorld({ states = { Enable = true, Shadow = true, Teams = "all", Own = { pull = { 4 } } } })
	MakeNeutral({ x = SMALL.x, y = SMALL.y })
	capture(function() runUntil(H, support, 80) end)
	local job = H.Lane.CampJobs.Current(support)
	check("pull unowned: step() runs it", job ~= nil and job.sdk ~= true and (job.sdkFrames or 0) == 0)
	check("pull unowned: still attacks on its second", #ActionsOf(5, "AttackUnit") == 1)
end

finish()
