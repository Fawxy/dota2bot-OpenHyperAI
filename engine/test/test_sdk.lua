-- v0.2 API (ctx, must/abort, deadline, Flow combinators) driven through the runner against the frame simulator.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("dist/tasks_test.lua")
local R, Testing, Flow = tasks.Tasks, tasks.Testing, tasks.Flow

local HOST = 7
local DT = 0.1
local FAR = { x = 900, y = 0 }

local function world()
    local sim = Sim.new()
    local a = sim:adapter(tasks)
    sim.claims, sim.releases = {}, {}
    a.claim = function(bot, c) sim.claims[#sim.claims + 1] = { id = bot:GetPlayerID(), t = sim.t, c = c } end
    a.release = function(bot, source, mode)
        sim.releases[#sim.releases + 1] = { id = bot:GetPlayerID(), t = sim.t, source = source, mode = mode }
    end
    local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
    bot.mode = HOST
    return sim, bot
end

local function frame(sim, bot)
    if bot.mode == HOST then R.Step(bot, HOST) end
    R.Tick(bot)
    sim:step(DT)
end

local function start(sim, bot, factory, opts)
    opts = opts or {}
    opts.name = opts.name or "t"
    opts.host = HOST
    return R.task(bot, opts, factory)
end

-- Runs until the task ends; returns the result and the sim time it ended at.
local function runToEnd(sim, bot, maxFrames)
    for _ = 1, maxFrames or 600 do
        if R.Current(bot) == nil then return R.Last(bot).result, sim.t end
        frame(sim, bot)
    end
    error("task did not finish", 0)
end

local function errorLogs(sim)
    local n = 0
    for _, l in ipairs(sim.logs) do if l:find(" error: ", 1, true) then n = n + 1 end end
    return n
end

-- ctx: labels follow the body, and a must-chain of two verbs runs both to completion.
do
    local sim, bot = world()
    local labels = {}
    start(sim, bot, Testing.ctxWalkWait(FAR, 1.0))
    local r, t
    for _ = 1, 400 do
        local cur = R.Current(bot)
        if cur == nil then r, t = R.Last(bot).result, sim.t break end
        if cur.label and labels[#labels] ~= cur.label then labels[#labels + 1] = cur.label end
        frame(sim, bot)
    end
    T.eq("ctx chain ok", r and r.reason, "ok")
    T.eq("ctx labels: walk first", labels[1], "walk")
    T.eq("ctx labels: then wait", labels[2], "wait")
    T.check("ctx chain: arrived", Sim.dist(bot.loc, FAR) <= 150)
    -- 750 units at 300/s from tolerance, then the full 1 s wait.
    T.check("ctx chain: waited after arriving", t >= 2.5 + 1.0)
end

-- must: a failed verb ends the task with the verb's result; the rest of the body never runs; not an error.
do
    local sim, bot = world()
    bot.blocked = true
    local ended
    start(sim, bot, Testing.ctxWalkWait(FAR, 1.0), { onEnd = function(res, info) ended = { r = res, info = info } end })
    local labelAtEnd
    for _ = 1, 100 do
        local cur = R.Current(bot)
        if cur == nil then break end
        labelAtEnd = cur.label
        frame(sim, bot)
    end
    local r = R.Last(bot).result
    T.eq("must: verb failure reason propagates", r.reason, "stuck")
    T.eq("must: not success", r.success, false)
    T.eq("must: second verb never reached", labelAtEnd, "walk")
    T.eq("must: onEnd gets the verb's result", ended and ended.r.reason, "stuck")
    T.eq("must: onEnd label", ended and ended.info.label, "walk")
    T.eq("must: not logged as an error", errorLogs(sim), 0)
    T.eq("must: claim released once", #sim.releases, 1)
end

-- must with deadline: arrival is impossible before the deadline, so the task ends timeout at the deadline.
do
    local sim, bot = world()
    start(sim, bot, Testing.ctxWalkWait(FAR, 1.0, 1.0))
    local r, t = runToEnd(sim, bot)
    T.eq("deadline: timeout", r.reason, "timeout")
    T.check("deadline: not before the deadline", t >= 1.0)
    T.check("deadline: within a frame or two of it", t <= 1.0 + 3 * DT)
end

-- deadline that is reachable does not fire.
do
    local sim, bot = world()
    start(sim, bot, Testing.ctxWalkWait(FAR, 0.5, 10))
    local r = runToEnd(sim, bot)
    T.eq("deadline not reached: ok", r.reason, "ok")
end

-- abort from three generators deep: ends with the carried reason and message, nothing after it runs.
do
    local sim, bot = world()
    local after = {}
    start(sim, bot, Testing.nestedAbort(3, "no_target", "camp empty", after))
    local r = runToEnd(sim, bot)
    T.eq("abort: reason", r.reason, "no_target")
    T.eq("abort: message", r.message, "camp empty")
    T.eq("abort: body stops at the abort", #after, 0)
    T.eq("abort: not logged as an error", errorLogs(sim), 0)
end

-- A plain Lua error is still an error, not mistaken for an abort.
do
    local sim, bot = world()
    start(sim, bot, Testing.throwing(2, "boom"))
    local r = runToEnd(sim, bot)
    T.eq("error still error", r.reason, "error")
    T.eq("error message kept", r.message, "boom")
    T.eq("error logged", errorLogs(sim), 1)
end

-- A thrown table that merely looks like an abort is an error.
do
    local sim, bot = world()
    local fake = function() return { next = function() error({ result = { success = true, reason = "ok" } }, 0) end } end
    start(sim, bot, fake)
    local r = runToEnd(sim, bot)
    T.eq("lookalike table is an error", r.reason, "error")
end

-- ctx.elapsed counts from the task's start, not the first step.
do
    local sim, bot = world()
    local seen = {}
    sim:step(5)
    bot.mode = 0
    start(sim, bot, Testing.ctxClock(seen))
    frame(sim, bot); frame(sim, bot)
    bot.mode = HOST
    runToEnd(sim, bot)
    T.check("elapsed includes time before the first step", seen.elapsed ~= nil and seen.elapsed >= 2 * DT)
    T.near("now is the adapter clock", seen.now, 5 + 3 * DT, 1e-6)
end

-- ctx.urgent reaches the claims.
do
    local sim, bot = world()
    local neutral = sim:addCreep{ x = 700, y = 0, hp = 500 }
    local p = { camp = { stand = { x = 600, y = 0 }, pick = function() return neutral end }, aggroAt = 5,
        exitPath = { { x = 0, y = 0 } }, exitUntil = 9, timingError = 0 }
    start(sim, bot, function(ctx) return ctx.stack(p) end)
    frame(sim, bot)
    T.eq("urgent claim posted while travelling", sim.claims[#sim.claims].c.urgent, true)
end

-- Flow.watch: interrupts with the check's message and stops ordering the bot.
do
    local sim, bot = world()
    start(sim, bot, Testing.watchedWalk(FAR, function() if sim.t >= 1.0 then return "enemy seen" end end))
    local r = runToEnd(sim, bot)
    T.eq("watch: interrupted", r.reason, "interrupted")
    T.eq("watch: message carried", r.message, "enemy seen")
    local lastMove = bot.actions[#bot.actions].t
    T.check("watch: no orders after the check fired", lastMove < 1.0)
    T.check("watch: walked until then", bot.loc.x > 200)
end

-- Flow.withTimeout: the inner walk is cut off; a short walk finishes with its own result.
do
    local sim, bot = world()
    start(sim, bot, Testing.timedWalk(FAR, 1.0))
    local r, t = runToEnd(sim, bot)
    T.eq("withTimeout: timeout", r.reason, "timeout")
    T.check("withTimeout: at ~1 s", t >= 1.0 and t <= 1.0 + 3 * DT)

    local sim2, bot2 = world()
    start(sim2, bot2, Testing.timedWalk({ x = 300, y = 0 }, 5.0))
    T.eq("withTimeout: inner result when it finishes first", runToEnd(sim2, bot2).reason, "ok")
end

-- Flow.retry: fresh attempts after failures, stops at the first success.
do
    local sim, bot = world()
    local attempts = {}
    -- The first two targets are too far for a 0.5 s walk; the third is within tolerance already.
    local locs = { FAR, { x = -900, y = 0 }, { x = 0, y = 100 } }
    start(sim, bot, Testing.retryWalks(3, locs, 0.5, attempts))
    local r = runToEnd(sim, bot)
    T.eq("retry: ok on the third attempt", r.reason, "ok")
    T.eq("retry: three attempts", #attempts, 3)
    T.eq("retry: attempt numbers passed", attempts[3], 3)
    local backwards = false
    for _, a in ipairs(bot.actions) do if a.kind == "move" and a.loc.x < 0 then backwards = true end end
    T.check("retry: second attempt really ran its own walk", backwards)
end

-- Flow.retry: shouldRetry can stop early, and the last failure is returned when attempts run out.
do
    local sim, bot = world()
    local attempts = {}
    start(sim, bot, Testing.retryWalks(3, { FAR, FAR, FAR }, 0.5, attempts,
        function(res) return res.reason ~= "timeout" end))
    T.eq("retry: shouldRetry false stops", runToEnd(sim, bot).reason, "timeout")
    T.eq("retry: only one attempt", #attempts, 1)

    local sim2, bot2 = world()
    local attempts2 = {}
    start(sim2, bot2, Testing.retryWalks(2, { FAR, FAR }, 0.5, attempts2))
    T.eq("retry: exhausted returns last failure", runToEnd(sim2, bot2).reason, "timeout")
    T.eq("retry: both attempts used", #attempts2, 2)
end

-- Flow.retry: an attempt that fails without yielding is retried on the next frame, not the same one.
do
    local sim, bot = world()
    local at = {}
    start(sim, bot, Testing.retryInstantFail(3, at))
    T.eq("retry instant: last failure returned", runToEnd(sim, bot).reason, "timeout")
    T.eq("retry instant: three attempts", #at, 3)
    T.check("retry instant: attempts on distinct frames", at[1] < at[2] and at[2] < at[3])
end

-- Flow.race: a watcher wins over the actor and reports its index; the actor stops being stepped.
do
    local sim, bot = world()
    local out = {}
    start(sim, bot, Testing.raceWalkUntil(FAR, function() return sim.t >= 1.0 end, out))
    local r = runToEnd(sim, bot)
    T.eq("race: watcher wins", out.winner, 2)
    T.eq("race: ok", r.reason, "ok")
    T.check("race: actor stopped before arriving", Sim.dist(bot.loc, FAR) > 150)

    local sim2, bot2 = world()
    local out2 = {}
    start(sim2, bot2, Testing.raceWalkUntil({ x = 300, y = 0 }, function() return false end, out2))
    runToEnd(sim2, bot2)
    T.eq("race: actor wins when it finishes first", out2.winner, 1)
end

-- Flow combinators accept any object with next(), so hosts can wrap their own steppers.
do
    local sim = world()
    local n = 0
    local stepper = { next = function() n = n + 1; return { done = n >= 3, value = { success = true, reason = "ok" } } end }
    local g = Flow.watch(stepper, function() return nil end)
    local r
    for _ = 1, 10 do
        local s = g:next()
        if s.done then r = s.value break end
        sim:step(DT)
    end
    T.eq("watch over a plain stepper", r and r.reason, "ok")
    T.eq("stepped exactly until done", n, 3)
end

-- The stack job itself (formerly Testing.stack) is covered in test_jobs.lua.

print("SDK [" .. T.runtime() .. "]")
T.finish()
