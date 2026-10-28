-- States: behaviour-state selection (stickiness, dwell, job commitment, cooldown), task start/restart/cancel,
-- shadow mode and telemetry. Runs the compiled bundle.
local T = dofile("test/helpers.lua")
local tasks = dofile("dist/tasks_test.lua")
local S, R = tasks.States, tasks.Tasks

local LANE, FARM, RETREAT = 4, 6, 2
local DT = 0.05

local A -- adapter state of the current scenario

local function newAdapter()
    A = { t = 100, logs = {}, events = {}, claims = {} }
    tasks.init({
        claim = function(bot, c) A.claims[#A.claims + 1] = { id = bot:GetPlayerID(), c = c } end,
        release = function() end,
        now = function() return A.t end,
        log = function(tag, msg) A.logs[#A.logs + 1] = tag .. ": " .. msg end,
        enabled = function() return true end,
        event = function(name, fields)
            local e = { name = name, t = A.t }
            for _, kv in ipairs(fields) do e[kv[1]] = kv[2] end
            A.events[#A.events + 1] = e
        end,
    })
    S.configure({ interval = 0.25, sticky = 0.1, minDwell = 3, jobBreak = 0.9, cooldown = 5, restart = 1 })
    S.SetOwned(function() return false end)
end

local nextId = 1
local function fakeBot()
    local b = { id = nextId, alive = true, mode = LANE }
    nextId = nextId + 1
    function b:GetPlayerID() return self.id end
    function b:IsAlive() return self.alive end
    function b:GetActiveMode() return self.mode end
    return b
end

local Testing = tasks.Testing

-- A posture body that never ends; `log` gets one entry per resume.
local function forever(log) return Testing.counting(1e9, log) end

-- A body that ends on its n-th resume with `result`.
local function finite(n, result) return Testing.counting(n - 1, {}, result) end

-- One frame as a host plays it: the global tick (States.Tick then Tasks.Tick), then the active mode's Think.
local function frame(bot)
    S.Tick(bot)
    R.Tick(bot)
    local stepped = S.Step(bot, bot.mode)
    A.t = A.t + DT
    return stepped
end

local function frames(bot, secs)
    local n = 0
    for _ = 1, math.floor(secs / DT + 0.5) do
        if frame(bot) then n = n + 1 end
    end
    return n
end

local function cur(bot) return (S.Current(bot) or {}).name end

local function eventsOf(name, pid)
    local out = {}
    for _, e in ipairs(A.events) do
        if e.name == name and (pid == nil or e.pid == pid) then out[#out + 1] = e end
    end
    return out
end

local function posture(name, score, extra)
    local s = { name = name, kind = "posture", host = LANE, score = score, body = (extra and extra.body) or finite(1e9) }
    for k, v in pairs(extra or {}) do s[k] = v end
    return s
end

-- Selection picks the highest scorer and reports the change.
do
    newAdapter()
    local bot = fakeBot()
    S.define(bot, { posture("a", function() return 0.5 end), posture("b", function() return 0.3 end) })
    frame(bot)
    T.eq("select: highest score wins", cur(bot), "a")
    local ev = eventsOf("state", bot.id)
    T.eq("select: one change event", #ev, 1)
    T.eq("select: event from none", (ev[1] or {}).from, "none")
    T.eq("select: event to a", (ev[1] or {}).to, "a")
    T.eq("select: shadow not owned", (ev[1] or {}).owned, false)
end

-- Not-applicable scorers (nil) are never chosen; all nil means no state.
do
    newAdapter()
    local bot = fakeBot()
    S.define(bot, { posture("a", function() return nil end) })
    frames(bot, 1)
    T.eq("none: no state when nothing applies", cur(bot), nil)
    T.eq("none: no change events", #eventsOf("state", bot.id), 0)
end

-- Stickiness: the current state keeps a +sticky bonus, so a slightly better rival does not take over.
do
    newAdapter()
    local bot = fakeBot()
    local b = 0.3
    S.define(bot, { posture("a", function() return 0.5 end), posture("b", function() return b end) })
    frame(bot)
    frames(bot, 4) -- past min dwell
    b = 0.55
    frames(bot, 1)
    T.eq("sticky: 0.55 does not beat 0.5 + 0.1", cur(bot), "a")
    b = 0.65
    frames(bot, 1)
    T.eq("sticky: 0.65 beats 0.5 + 0.1", cur(bot), "b")
end

-- Min dwell: a posture is held 3 s before another posture may take over, however high it scores.
do
    newAdapter()
    local bot = fakeBot()
    local b = 0.1
    S.define(bot, { posture("a", function() return 0.5 end), posture("b", function() return b end) })
    frame(bot)
    b = 0.95
    frames(bot, 2.5)
    T.eq("dwell: kept before 3 s", cur(bot), "a")
    frames(bot, 1)
    T.eq("dwell: left after 3 s", cur(bot), "b")
end

-- A posture whose scorer stops applying is left at once, dwell or not.
do
    newAdapter()
    local bot = fakeBot()
    local a = 0.5
    S.define(bot, { posture("a", function() return a end), posture("b", function() return 0.2 end) })
    frame(bot)
    a = nil
    frames(bot, 0.3)
    T.eq("n/a: left without waiting for dwell", cur(bot), "b")
    local ev = eventsOf("state", bot.id)
    T.eq("n/a: why", (ev[#ev] or {}).why, "n/a")
end

-- Selection runs at the interval, not every frame.
do
    newAdapter()
    local bot = fakeBot()
    local a = 0.5
    S.define(bot, { posture("a", function() return a end), posture("b", function() return 0.2 end) })
    frame(bot) -- selects at t=100
    a = nil
    frame(bot) -- t=100.05: no selection yet
    T.eq("interval: no reselection inside the interval", cur(bot), "a")
    frames(bot, 0.25)
    T.eq("interval: reselected at the interval", cur(bot), "b")
end

-- A scorer that errors counts as not applicable and is logged, without breaking the others.
do
    newAdapter()
    local bot = fakeBot()
    S.define(bot, { posture("bad", function() error("boom") end), posture("b", function() return 0.2 end) })
    frame(bot)
    T.eq("score error: other state chosen", cur(bot), "b")
    local logged = false
    for _, l in ipairs(A.logs) do if l:find("boom", 1, true) then logged = true end end
    T.check("score error: logged", logged)
end

-- Owned posture: its body runs as a task on the host, stepped through States.Step; shadow states run nothing.
do
    newAdapter()
    local bot, shadow = fakeBot(), fakeBot()
    local c1, c2 = {}, {}
    S.SetOwned(function(b, name) return b == bot and name == "lane" end)
    S.define(bot, { posture("lane", function() return 0.5 end, { body = forever(c1), floor = 0 }) })
    S.define(shadow, { posture("lane", function() return 0.5 end, { body = forever(c2) }) })
    local stepped = frames(bot, 1)
    frames(shadow, 1)
    T.eq("owned: stepped every frame", stepped, 20)
    T.eq("owned: body resumed", #c1, 20)
    T.eq("owned: task named after the state", (R.Current(bot) or {}).name, "state:lane")
    T.eq("owned: claims the given floor", ((A.claims[1] or {}).c or {}).floor, 0)
    T.eq("shadow: no task", R.Current(shadow), nil)
    T.eq("shadow: body never run", #c2, 0)
    T.eq("shadow: state still chosen", cur(shadow), "lane")
    T.eq("owned: Step on another host does nothing", S.Step(bot, FARM), false)
end

-- Interrupt: the task is preempted after preemptAfter in another mode, the state is kept, and the body is
-- restarted on the first frame the host mode is active again.
do
    newAdapter()
    local bot = fakeBot()
    local c = {}
    S.SetOwned(function() return true end)
    S.define(bot, { posture("lane", function() return 0.5 end, { body = forever(c), preemptAfter = 3 }) })
    frames(bot, 1)
    bot.mode = RETREAT
    frames(bot, 2)
    T.eq("interrupt: short blip keeps the task", (R.Current(bot) or {}).name, "state:lane")
    frames(bot, 2)
    T.eq("interrupt: preempted after 3 s away", R.Current(bot), nil)
    T.eq("interrupt: state kept", cur(bot), "lane")
    local ended = eventsOf("state_task", bot.id)
    T.eq("interrupt: end reported", (ended[1] or {}).reason, "preempted")
    frames(bot, 3)
    T.eq("interrupt: no restart while away", R.Current(bot), nil)
    bot.mode = LANE
    T.eq("interrupt: stepped on the first frame back", frame(bot), true)
    T.eq("interrupt: fresh body (first resume again)", c[#c], 1)
    local starts = eventsOf("state_start", bot.id)
    T.eq("interrupt: restart reported", (starts[#starts] or {}).n, 2)
end

-- A dead bot's task ends; the state is restarted only once it is alive and in its host mode.
do
    newAdapter()
    local bot = fakeBot()
    S.SetOwned(function() return true end)
    S.define(bot, { posture("lane", function() return 0.5 end) })
    frames(bot, 0.5)
    bot.alive = false
    frames(bot, 2)
    T.eq("dead: no task while dead", R.Current(bot), nil)
    bot.alive = true
    frame(bot)
    T.eq("dead: restarted when alive", (R.Current(bot) or {}).name, "state:lane")
end

-- Changing state cancels the old task (reported as cancelled with the new state) and starts the new one.
do
    newAdapter()
    local bot = fakeBot()
    local b = 0.1
    S.SetOwned(function() return true end)
    S.define(bot, { posture("a", function() return 0.5 end), posture("b", function() return b end) })
    frames(bot, 3.5)
    b = 0.9
    frames(bot, 0.3)
    T.eq("change: new task running", (R.Current(bot) or {}).name, "state:b")
    local ended = eventsOf("state_task", bot.id)
    T.eq("change: old task cancelled", (ended[1] or {}).reason, "cancelled")
    T.eq("change: old task's message names the new state", (ended[1] or {}).msg, "state:b")
    T.eq("change: state kept as b (no reselect churn)", cur(bot), "b")
end

-- Jobs: kept while running against any posture below jobBreak; a score at or above it breaks the job.
do
    newAdapter()
    local bot = fakeBot()
    local p = 0.5
    S.SetOwned(function() return true end)
    S.define(bot, {
        { name = "stack", kind = "job", host = FARM, score = function() return 0.8 end, body = finite(1e9) },
        posture("lane", function() return p end),
    })
    bot.mode = FARM
    frames(bot, 4)
    p = 0.85
    frames(bot, 1)
    T.eq("job: kept against 0.85", cur(bot), "stack")
    p = 0.95
    frames(bot, 0.3)
    T.eq("job: broken by 0.95", cur(bot), "lane")
    local ev = eventsOf("state", bot.id)
    T.eq("job: why break", (ev[#ev] or {}).why, "break")
end

-- A job that ends ok is left at once (no waiting for the interval) and may be chosen again by its scorer.
do
    newAdapter()
    local bot = fakeBot()
    S.SetOwned(function() return true end)
    local go = true
    S.define(bot, {
        { name = "pull", kind = "job", host = FARM, score = function() return go and 0.8 or nil end, body = finite(3, { success = true, reason = "ok" }) },
        posture("lane", function() return 0.5 end),
    })
    bot.mode = FARM
    frame(bot)
    go = false
    frame(bot)
    frame(bot) -- third resume returns ok
    frame(bot)
    T.eq("job ok: left on the next frame", cur(bot), "lane")
    local ev = eventsOf("state", bot.id)
    T.eq("job ok: why ended", (ev[#ev] or {}).why, "ended")
end

-- A job that fails is on cooldown: not chosen again for 5 s even if its scorer still says go.
do
    newAdapter()
    local bot = fakeBot()
    S.SetOwned(function() return true end)
    S.define(bot, {
        { name = "pull", kind = "job", host = FARM, score = function() return 0.8 end, body = finite(2, { success = false, reason = "missed" }) },
        posture("lane", function() return 0.5 end),
    })
    bot.mode = FARM
    frames(bot, 0.2)
    T.eq("cooldown: left after failure", cur(bot), "lane")
    frames(bot, 6)
    local picks, failAt = {}, nil
    for _, e in ipairs(A.events) do
        if e.name == "state" and e.pid == bot.id and e.to == "pull" then picks[#picks + 1] = e.t end
        if e.name == "state_task" and e.pid == bot.id and e.state == "pull" and failAt == nil then failAt = e.t end
    end
    T.eq("cooldown: chosen again exactly once in 6 s", #picks, 2)
    T.check("cooldown: re-chosen 5 s after the failure", picks[2] ~= nil and failAt ~= nil
        and picks[2] - failAt >= 5 - 1e-6 and picks[2] - failAt <= 5.3)
end

-- A preempted job is kept and restarted, not ended (an interrupt is not the job's failure).
do
    newAdapter()
    local bot = fakeBot()
    S.SetOwned(function() return true end)
    S.define(bot, {
        { name = "stack", kind = "job", host = FARM, score = function() return 0.8 end, body = finite(1e9) },
        posture("lane", function() return 0.5 end),
    })
    bot.mode = FARM
    frames(bot, 0.5)
    bot.mode = RETREAT
    frames(bot, 1)
    T.eq("job preempt: task gone", R.Current(bot), nil)
    T.eq("job preempt: still the job", cur(bot), "stack")
    bot.mode = FARM
    frame(bot)
    T.eq("job preempt: restarted", (R.Current(bot) or {}).name, "state:stack")
end

-- Ownership read at decision time: becoming owned later starts the task; losing it cancels the task.
do
    newAdapter()
    local bot = fakeBot()
    local own = false
    S.SetOwned(function() return own end)
    S.define(bot, { posture("lane", function() return 0.5 end) })
    frames(bot, 1)
    T.eq("own later: no task while shadow", R.Current(bot), nil)
    own = true
    frames(bot, 0.3)
    T.eq("own later: task started", (R.Current(bot) or {}).name, "state:lane")
    own = false
    frames(bot, 0.3)
    T.eq("disown: task cancelled", R.Current(bot), nil)
    T.eq("disown: state kept", cur(bot), "lane")
end

-- Someone else's task (e.g. a host's own job) is never replaced by a state's start or restart.
do
    newAdapter()
    local bot = fakeBot()
    S.SetOwned(function() return true end)
    R.task(bot, { name = "other", host = LANE }, finite(1e9))
    S.define(bot, { posture("lane", function() return 0.5 end) })
    frames(bot, 0.5)
    T.eq("foreign: other task left running", (R.Current(bot) or {}).name, "other")
    T.eq("foreign: States.Step does not step it", S.Step(bot, LANE), false)
    R.Cancel(bot, "cancelled", "done")
    frame(bot)
    T.eq("foreign: state task starts once it is gone", (R.Current(bot) or {}).name, "state:lane")
end

-- A posture body that keeps erroring is restarted at most once per `restart` seconds.
do
    newAdapter()
    local bot = fakeBot()
    S.SetOwned(function() return true end)
    S.define(bot, { posture("lane", function() return 0.5 end, { body = Testing.throwing(1, "bad body") }) })
    frames(bot, 3)
    local n = #eventsOf("state_start", bot.id)
    T.check("error backoff: 3 or 4 starts in 3 s (got " .. n .. ")", n >= 3 and n <= 4)
end

-- Without an adapter event hook the layer logs its events instead.
do
    newAdapter()
    local logs = {}
    tasks.init({
        claim = function() end, release = function() end, now = function() return A.t end,
        log = function(tag, msg) logs[#logs + 1] = tag .. ": " .. msg end, enabled = function() return true end,
    })
    local bot = fakeBot()
    S.define(bot, { posture("a", function() return 0.5 end) })
    frame(bot)
    local found = false
    for _, l in ipairs(logs) do if l:find("ev=state", 1, true) and l:find("to=a", 1, true) then found = true end end
    T.check("log fallback: state change logged", found)
end

-- A job's guard and onEnd come from its spec: the guard ends it `interrupted` with its message, onEnd sees the end.
do
    newAdapter()
    local bot = fakeBot()
    S.SetOwned(function() return true end)
    local stop, seen = nil, {}
    S.define(bot, {
        { name = "stack", kind = "job", host = FARM, score = function() return 0.8 end, body = finite(1e9),
          guard = function() return stop end, onEnd = function(r, info) seen[#seen + 1] = { r = r, info = info } end },
        posture("lane", function() return 0.5 end),
    })
    bot.mode = FARM
    frames(bot, 0.5)
    T.eq("spec guard: running", (R.Current(bot) or {}).name, "state:stack")
    stop = "flag-off"
    frames(bot, 0.3)
    T.check("spec guard: stack task ended", (R.Current(bot) or {}).name ~= "state:stack")
    T.eq("spec onEnd: called once", #seen, 1)
    T.eq("spec onEnd: interrupted", seen[1] and seen[1].r.reason, "interrupted")
    T.eq("spec onEnd: guard message", seen[1] and seen[1].r.message, "flag-off")
    T.eq("spec guard: job left", cur(bot), "lane")
end

-- A preempted job whose scorer has withdrawn it is left at once (n/a), not kept waiting for a restart.
do
    newAdapter()
    local bot = fakeBot()
    S.SetOwned(function() return true end)
    local plan = true
    S.define(bot, {
        { name = "stack", kind = "job", host = FARM, score = function() if plan then return 0.8 end end, body = finite(1e9) },
        posture("lane", function() return 0.5 end),
    })
    bot.mode = FARM
    frames(bot, 0.5)
    bot.mode = RETREAT
    frames(bot, 1)
    T.eq("job n/a: kept while still scored", cur(bot), "stack")
    plan = false
    frames(bot, 0.3)
    T.eq("job n/a: left once withdrawn", cur(bot), "lane")
    local last = eventsOf("state", bot.id)
    T.eq("job n/a: why", (last[#last] or {}).why, "n/a")
    bot.mode = FARM
    frames(bot, 0.5)
    T.eq("job n/a: lane runs, no stack restart", (R.Current(bot) or {}).name, "state:lane")
end

-- While its task runs, a job withdrawn by its scorer keeps running: the body decides when it is done.
do
    newAdapter()
    local bot = fakeBot()
    S.SetOwned(function() return true end)
    local plan = true
    S.define(bot, {
        { name = "stack", kind = "job", host = FARM, score = function() if plan then return 0.8 end end, body = finite(1e9) },
        posture("lane", function() return 0.5 end),
    })
    bot.mode = FARM
    frames(bot, 0.5)
    plan = false
    frames(bot, 1)
    T.eq("job running n/a: still the job", cur(bot), "stack")
    T.eq("job running n/a: still running", (R.Current(bot) or {}).name, "state:stack")
end

print("states [" .. T.runtime() .. "]")
T.finish()
