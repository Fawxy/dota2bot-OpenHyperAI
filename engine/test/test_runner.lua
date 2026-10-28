-- Task runner: per-frame stepping, claims, cancellation rules. Runs the compiled bundle.
local T = dofile("test/helpers.lua")
local tasks = dofile("dist/tasks_test.lua")
local R, Testing = tasks.Tasks, tasks.Testing

local HOST, OTHER = 7, 3
local DT = 0.05

local cur -- adapter state of the current scenario; frame() advances its clock

local function fakeAdapter()
    local A = { claims = {}, releases = {}, logs = {}, t = 100, on = true }
    cur = A
    A.adapter = {
        claim = function(bot, c) A.claims[#A.claims + 1] = { id = bot:GetPlayerID(), c = c } end,
        release = function(bot, source, mode)
            A.releases[#A.releases + 1] = { id = bot:GetPlayerID(), source = source, mode = mode }
        end,
        now = function() return A.t end,
        log = function(tag, msg) A.logs[#A.logs + 1] = tag .. ": " .. msg end,
        enabled = function() return A.on end,
    }
    tasks.init(A.adapter)
    return A
end

local function fakeBot(id)
    local b = { id = id, alive = true, mode = HOST }
    function b:GetPlayerID() return self.id end
    function b:IsAlive() return self.alive end
    function b:GetActiveMode() return self.mode end
    return b
end

-- Last result, nil-safe so a broken runner reports FAILs instead of aborting the file.
local function res(bot) return (R.Last(bot) or { result = {} }).result end

-- One frame as the host plays it: Think (only when the host mode is active and not stunned), then Tick,
-- then the clock advances by DT.
local function frame(bot, opts)
    local stepped = false
    if not (opts and opts.skipStep) and bot.mode == HOST then stepped = R.Step(bot, HOST) end
    R.Tick(bot)
    cur.t = cur.t + DT
    return stepped
end

-- Runs frames until `secs` of clock have passed.
local function frames(bot, secs, opts)
    local n = 0
    for _ = 1, math.floor(secs / DT + 0.5) do
        if frame(bot, opts) then n = n + 1 end
    end
    return n
end

-- onEnd recorder: each call keeps the result and info plus the runner state seen from inside the hook.
local function recorder(A, bot)
    local calls = {}
    local fn = function(result, info)
        calls[#calls + 1] = { result = result, info = info, releases = #A.releases, current = R.Current(bot) }
    end
    return calls, fn
end

local function onlyCall(name, calls, reason, message, steps)
    T.eq(name .. ": onEnd called once", #calls, 1)
    local c = calls[1] or { result = {}, info = {} }
    T.eq(name .. ": onEnd reason", c.result.reason, reason)
    T.eq(name .. ": onEnd message", c.result.message, message)
    T.eq(name .. ": onEnd success", c.result.success, reason == "ok")
    if steps then T.eq(name .. ": onEnd steps", c.info.steps, steps) end
    T.eq(name .. ": onEnd after release", (c.releases or 0) >= 1, true)
    T.eq(name .. ": onEnd after state cleared", c.current, nil)
end

local function logged(A, needle)
    for _, l in ipairs(A.logs) do
        if l:find(needle, 1, true) then return true end
    end
    return false
end

-- 7a. No adapter: must run before any init().
do
    local bot = fakeBot(70)
    T.eq("no adapter: task() refused", R.task(bot, { name = "x", host = HOST }, Testing.counting(1, {})), false)
    T.eq("no adapter: nothing running", R.Current(bot), nil)
end

-- 1 + 2. One resume per Step; claim each Step with defaults; single release; Last holds the body's Result.
do
    local A = fakeAdapter()
    local bot, log = fakeBot(1), {}
    local ret = { success = false, reason = "no_target", message = "nobody" }
    T.eq("task() accepted", R.task(bot, { name = "walk", host = HOST }, Testing.counting(3, log, ret)), true)
    R.Tick(bot)
    T.eq("no resume before first Step", #log, 0)
    T.eq("Tick claims before first Step", #A.claims, 1)
    for i = 1, 3 do
        T.eq("Step " .. i .. " consumed frame", frame(bot), true)
        T.eq("log after Step " .. i, #log, i)
        T.check("still running after Step " .. i, R.Current(bot) ~= nil)
    end
    T.eq("Describe while running", R.Describe(bot), "walk step=3")
    T.eq("Step 4 consumed frame", frame(bot), true)
    T.eq("log after Step 4", #log, 4)
    T.eq("finished after 4 Steps", R.Current(bot), nil)
    T.eq("claims: one per frame, Step and Tick share it", #A.claims, 4)
    local c = (A.claims[4] or { c = {} }).c
    T.eq("claim source", c.source, "task:walk")
    T.eq("claim mode", c.mode, HOST)
    T.eq("claim default tier", c.tier, "LANE_PLAN")
    T.eq("claim default floor", c.floor, 0.6)
    T.eq("released exactly once", #A.releases, 1)
    T.eq("release source", (A.releases[1] or {}).source, "task:walk")
    T.eq("release mode", (A.releases[1] or {}).mode, HOST)
    local last = R.Last(bot)
    T.eq("Last name", last and last.name, "walk")
    T.eq("Last reason is body's", last and last.result.reason, "no_target")
    T.eq("Last message is body's", last and last.result.message, "nobody")
    T.eq("Describe after finish", R.Describe(bot), "- last=walk no_target")
    T.eq("Step after finish", R.Step(bot, HOST), false)
    T.eq("no release after finish", #A.releases, 1)

    -- Explicit tier/floor are forwarded; a body returning nothing is ok.
    R.task(bot, { name = "fight", host = HOST, tier = "COMBAT", floor = 0.9 }, Testing.counting(0, {}))
    frame(bot)
    T.eq("claim explicit tier", (A.claims[5] or {c = {}}).c.tier, "COMBAT")
    T.eq("claim explicit floor", (A.claims[5] or {c = {}}).c.floor, 0.9)
    T.eq("nil return counts as ok", res(bot).reason, "ok")
    T.eq("nil return counts as success", res(bot).success, true)
    T.eq("Describe ok", R.Describe(bot), "- last=fight ok")
    T.eq("Describe nothing ever", R.Describe(fakeBot(99)), "-")
end

-- 3. Mode switch after stepping: preempted, released, never resumed again.
do
    local A = fakeAdapter()
    local bot, log = fakeBot(3), {}
    R.task(bot, { name = "farm", host = HOST }, Testing.counting(5, log))
    frame(bot)
    frame(bot)
    bot.mode = OTHER
    frame(bot)
    T.eq("preempted: not running", R.Current(bot), nil)
    T.eq("preempted reason", res(bot).reason, "preempted")
    T.eq("preempted message", res(bot).message, "mode=" .. OTHER)
    T.eq("preempted: released", #A.releases, 1)
    bot.mode = HOST
    T.eq("Step after preempt returns false", R.Step(bot, HOST), false)
    T.eq("body not resumed after preempt", #log, 2)
    T.eq("no claim after preempt", #A.claims, 2)
end

-- 4. Stunned frames (no Step, host mode still active) do not cancel; resumes where it left off.
do
    local A = fakeAdapter()
    local bot, log = fakeBot(4), {}
    R.task(bot, { name = "stun", host = HOST }, Testing.counting(3, log))
    frame(bot)
    for _ = 1, 10 do
        A.t = A.t + 0.1
        frame(bot, { skipStep = true })
    end
    T.check("stunned: still running", R.Current(bot) ~= nil)
    T.eq("stunned: no release", #A.releases, 0)
    T.eq("stunned: claim kept up every frame", #A.claims, 11)
    T.eq("stunned: steps unchanged", R.Current(bot) and R.Current(bot).steps, 1)
    frame(bot)
    T.eq("resumes at next slice", log[#log], 2)
    T.eq("resumed exactly once", #log, 2)
end

-- 5. Death; never-started grace.
do
    local A = fakeAdapter()
    local bot = fakeBot(5)
    R.task(bot, { name = "die", host = HOST }, Testing.counting(3, {}))
    frame(bot)
    bot.alive = false
    R.Tick(bot)
    T.eq("dead: not running", R.Current(bot), nil)
    T.eq("dead reason", res(bot).reason, "dead")
    T.eq("dead: released", #A.releases, 1)

    local bot2 = fakeBot(51)
    bot2.mode = OTHER
    R.task(bot2, { name = "wait", host = HOST }, Testing.counting(3, {}))
    A.t = A.t + 0.9
    R.Tick(bot2)
    T.check("never stepped: kept within grace", R.Current(bot2) ~= nil)
    A.t = A.t + 0.2
    R.Tick(bot2)
    T.eq("never stepped: cancelled after grace", R.Current(bot2), nil)
    T.eq("never_started reason", res(bot2).reason, "preempted")
    T.eq("never_started message", res(bot2).message, "never_started")
end

-- 6. Body throws: Step does not raise, error recorded, released, logged.
do
    local A = fakeAdapter()
    local bot = fakeBot(6)
    R.task(bot, { name = "boom", host = HOST }, Testing.throwing(2, "kaboom"))
    T.eq("throwing: first Step ok", R.Step(bot, HOST), true)
    local ok, consumed = pcall(R.Step, bot, HOST)
    T.eq("throwing: Step did not raise", ok, true)
    T.eq("throwing: Step consumed frame", consumed, true)
    T.eq("throwing: not running", R.Current(bot), nil)
    T.eq("error reason", res(bot).reason, "error")
    T.check("error message carried", tostring(res(bot).message):find("kaboom", 1, true) ~= nil)
    T.eq("error: released", #A.releases, 1)
    local logged = false
    for _, l in ipairs(A.logs) do
        if l:find("kaboom", 1, true) then logged = true end
    end
    T.check("error logged", logged)
end

-- 7. Disabled / unsupported: refused, nothing claimed; disabling mid-task cancels.
do
    local A = fakeAdapter()
    local bot = fakeBot(7)
    A.on = false
    T.eq("disabled: task() refused", R.task(bot, { name = "x", host = HOST }, Testing.counting(1, {})), false)
    frame(bot)
    T.eq("disabled: no claim", #A.claims, 0)
    T.check("disabled: logged", #A.logs > 0)
    A.on = true

    local saved = coroutine
    coroutine = nil
    local accepted = R.task(bot, { name = "x", host = HOST }, Testing.counting(1, {}))
    coroutine = saved
    T.eq("unsupported: task() refused", accepted, false)
    frame(bot)
    T.eq("unsupported: no claim", #A.claims, 0)

    R.task(bot, { name = "kill", host = HOST }, Testing.counting(3, {}))
    frame(bot)
    A.on = false
    T.eq("disabled mid-task: Step refused", R.Step(bot, HOST), false)
    R.Tick(bot)
    T.eq("disabled mid-task: cancelled", R.Current(bot), nil)
    T.eq("disabled reason", res(bot).message, "disabled")
    T.eq("disabled mid-task: released", #A.releases, 1)
end

-- 8. Two bots run independent tasks.
do
    local A = fakeAdapter()
    local b1, b2, l1, l2 = fakeBot(81), fakeBot(82), {}, {}
    R.task(b1, { name = "a", host = HOST }, Testing.counting(1, l1))
    R.task(b2, { name = "b", host = HOST }, Testing.counting(3, l2))
    frame(b1); frame(b2)
    frame(b1)
    T.eq("bot1 finished", R.Current(b1), nil)
    T.eq("bot2 still running", R.Current(b2) and R.Current(b2).name, "b")
    T.eq("bot2 resumed once", #l2, 1)
    b2.mode = OTHER
    R.Tick(b2)
    T.eq("bot1 last unaffected by bot2 preempt", res(b1).reason, "ok")
    T.eq("bot2 preempted", res(b2).reason, "preempted")
    T.eq("claims tagged per bot", (A.claims[3] or {}).id, 81)
end

-- 9. Replacing a running task.
do
    local A = fakeAdapter()
    local bot, oldLog, newLog = fakeBot(9), {}, {}
    R.task(bot, { name = "old", host = HOST }, Testing.counting(5, oldLog))
    frame(bot)
    R.task(bot, { name = "new", host = HOST }, Testing.counting(2, newLog))
    T.eq("replace: old released", #A.releases, 1)
    T.eq("replace: release source", (A.releases[1] or {}).source, "task:old")
    T.eq("replace: last is old", (R.Last(bot) or {}).name, "old")
    T.eq("replace: reason", res(bot).reason, "cancelled")
    T.eq("replace: message", res(bot).message, "replaced")
    frame(bot)
    T.eq("replace: new runs", #newLog, 1)
    T.eq("replace: old not resumed", #oldLog, 1)
end

-- 10. Tick claim while the host is active but never steps: claims during the grace, then never_started.
do
    local A = fakeAdapter()
    local bot, log = fakeBot(10), {}
    R.task(bot, { name = "idle", host = HOST }, Testing.counting(3, log))
    frames(bot, 0.9, { skipStep = true })
    T.check("unstepped, host active: still pending within grace", R.Current(bot) ~= nil)
    T.eq("unstepped: one claim per frame during grace", #A.claims, 18)
    T.eq("unstepped: claim mode", (A.claims[1] or { c = {} }).c.mode, HOST)
    frames(bot, 0.2, { skipStep = true })
    T.eq("unstepped: cancelled after grace", R.Current(bot), nil)
    T.eq("unstepped: reason", res(bot).reason, "preempted")
    T.eq("unstepped: message", res(bot).message, "never_started")
    T.eq("unstepped: released", #A.releases, 1)
    local claimsAtCancel = #A.claims
    frames(bot, 1.0, { skipStep = true })
    T.eq("unstepped: no claim after cancel", #A.claims, claimsAtCancel)
    T.eq("unstepped: body never resumed", #log, 0)
end

-- 11. Running task whose host stays active but is not stepped: cancelled stalled, claims stop.
do
    local A = fakeAdapter()
    local bot, log = fakeBot(11), {}
    R.task(bot, { name = "held", host = HOST }, Testing.counting(100, log))
    frame(bot)
    frames(bot, 1.9, { skipStep = true })
    T.check("stall: still running before stallAfter", R.Current(bot) ~= nil)
    T.eq("stall: claims kept up while not stepped", #A.claims, 39)
    frames(bot, 0.2, { skipStep = true })
    T.eq("stall: cancelled", R.Current(bot), nil)
    T.eq("stall: reason", res(bot).reason, "preempted")
    T.eq("stall: message", res(bot).message, "stalled")
    T.eq("stall: released", #A.releases, 1)
    local claimsAtCancel = #A.claims
    frames(bot, 1.0)
    T.eq("stall: no claim after cancel", #A.claims, claimsAtCancel)
    T.eq("stall: no resume after cancel", #log, 1)

    -- stallAfter is configurable.
    local bot2 = fakeBot(111)
    R.task(bot2, { name = "short", host = HOST, stallAfter = 0.5 }, Testing.counting(100, {}))
    frame(bot2)
    frames(bot2, 0.4, { skipStep = true })
    T.check("stallAfter=0.5: running at 0.4 s", R.Current(bot2) ~= nil)
    frames(bot2, 0.2, { skipStep = true })
    T.eq("stallAfter=0.5: stalled after 0.5 s", res(bot2).message, "stalled")
end

-- 12. preemptAfter: mode flickers shorter than N survive (the clock resets on return); a longer one cancels.
do
    local A = fakeAdapter()
    local bot, log = fakeBot(12), {}
    R.task(bot, { name = "sticky", host = HOST, preemptAfter = 0.5 }, Testing.counting(100, log))
    frames(bot, 0.2)
    bot.mode = OTHER
    frames(bot, 0.3)
    T.check("flicker 0.3 s: still running", R.Current(bot) ~= nil)
    T.eq("flicker: claims kept up while away", #A.claims, 10)
    bot.mode = HOST
    frames(bot, 0.1)
    T.eq("flicker: keeps stepping after return", #log, 6)
    bot.mode = OTHER
    frames(bot, 0.3)
    T.check("second flicker: away clock was reset", R.Current(bot) ~= nil)
    bot.mode = HOST
    frame(bot)
    bot.mode = OTHER
    frames(bot, 0.45)
    T.check("away 0.45 s: still running", R.Current(bot) ~= nil)
    frames(bot, 0.15)
    T.eq("away > 0.5 s: cancelled", R.Current(bot), nil)
    T.eq("preemptAfter: reason", res(bot).reason, "preempted")
    T.eq("preemptAfter: message", res(bot).message, "mode=" .. OTHER)
    T.eq("preemptAfter: released", #A.releases, 1)
end

-- 13. guard: checked in Tick (before the mode check) and in Step (before resuming); message passed verbatim.
do
    local A = fakeAdapter()
    local bot, log, why = fakeBot(13), {}, nil
    local calls, onEnd = recorder(A, bot)
    local guard = function() return why end
    R.task(bot, { name = "g1", host = HOST, guard = guard, onEnd = onEnd }, Testing.counting(10, log))
    frames(bot, 0.1)
    T.eq("guard nil: body stepping", #log, 2)
    why = "too dangerous: 3"
    T.eq("guard in Step: frame not consumed", R.Step(bot, HOST), false)
    T.eq("guard in Step: body not resumed", #log, 2)
    T.eq("guard in Step: reason", res(bot).reason, "interrupted")
    T.eq("guard in Step: message verbatim", res(bot).message, "too dangerous: 3")
    T.eq("guard in Step: released", #A.releases, 1)
    onlyCall("guard in Step", calls, "interrupted", "too dangerous: 3", 2)

    why = nil
    local calls2, onEnd2 = recorder(A, bot)
    R.task(bot, { name = "g2", host = HOST, guard = guard, onEnd = onEnd2 }, Testing.counting(10, log))
    frame(bot)
    local claims = #A.claims
    why = "left zone"
    bot.mode = OTHER
    R.Tick(bot)
    T.eq("guard in Tick: wins over mode check", res(bot).reason, "interrupted")
    T.eq("guard in Tick: message verbatim", res(bot).message, "left zone")
    T.eq("guard in Tick: no claim posted", #A.claims, claims)
    onlyCall("guard in Tick", calls2, "interrupted", "left zone", 1)
end

-- 14. onEnd: once per task with the exact result, after release and with the runner state cleared.
do
    local A = fakeAdapter()
    local bot = fakeBot(14)
    local function start(name, body, extra)
        local calls, onEnd = recorder(A, bot)
        local opts = { name = name, host = HOST, onEnd = onEnd }
        for k, v in pairs(extra or {}) do opts[k] = v end
        R.task(bot, opts, body)
        return calls
    end

    local calls = start("ok", Testing.counting(1, {}))
    frames(bot, 0.5)
    onlyCall("ok", calls, "ok", nil, 2)

    calls = start("ret", Testing.counting(0, {}, { success = false, reason = "no_target", message = "none" }))
    frames(bot, 0.5)
    onlyCall("body return", calls, "no_target", "none", 1)

    calls = start("cancel", Testing.counting(5, {}))
    frame(bot)
    R.Cancel(bot, "cancelled", "by caller")
    R.Cancel(bot, "cancelled", "again")
    frames(bot, 0.2)
    onlyCall("Cancel", calls, "cancelled", "by caller", 1)

    calls = start("pre", Testing.counting(5, {}))
    frame(bot)
    bot.mode = OTHER
    frames(bot, 0.2)
    bot.mode = HOST
    onlyCall("preempt", calls, "preempted", "mode=" .. OTHER, 1)

    calls = start("dead", Testing.counting(5, {}))
    frame(bot)
    bot.alive = false
    R.Tick(bot)
    bot.alive = true
    onlyCall("dead", calls, "dead", nil, 1)

    calls = start("err", Testing.throwing(2, "kaboom"))
    frames(bot, 0.2)
    T.eq("error: onEnd called once", #calls, 1)
    T.eq("error: onEnd reason", (calls[1] or { result = {} }).result.reason, "error")
    T.check("error: onEnd message", tostring((calls[1] or { result = {} }).result.message):find("kaboom", 1, true) ~= nil)

    calls = start("off", Testing.counting(5, {}))
    frame(bot)
    A.on = false
    frames(bot, 0.2)
    A.on = true
    onlyCall("disabled", calls, "cancelled", "disabled", 1)

    calls = start("old", Testing.counting(5, {}))
    frame(bot)
    local newCalls = start("new", Testing.counting(5, {}))
    onlyCall("replaced", calls, "cancelled", "replaced", 1)
    T.eq("replaced: new task's onEnd not called", #newCalls, 0)
    R.Cancel(bot, "cancelled")

    calls = start("never", Testing.counting(5, {}))
    frames(bot, 1.2, { skipStep = true })
    onlyCall("never_started", calls, "preempted", "never_started", 0)

    calls = start("stall", Testing.counting(50, {}))
    frame(bot)
    frames(bot, 2.2, { skipStep = true })
    onlyCall("stalled", calls, "preempted", "stalled", 1)
end

-- 15. An erroring onEnd is logged and leaves the runner usable.
do
    local A = fakeAdapter()
    local bot, log = fakeBot(15), {}
    R.task(bot, { name = "bad", host = HOST, onEnd = function() error("cleanup failed", 0) end }, Testing.counting(0, {}))
    local ok = pcall(frame, bot)
    T.eq("erroring onEnd: Step/Tick did not raise", ok, true)
    T.eq("erroring onEnd: task still recorded as ok", res(bot).reason, "ok")
    T.check("erroring onEnd: logged", logged(A, "cleanup failed"))
    T.eq("erroring onEnd: released", #A.releases, 1)
    T.eq("after erroring onEnd: new task accepted", R.task(bot, { name = "next", host = HOST }, Testing.counting(2, log)), true)
    frames(bot, 0.15)
    T.eq("after erroring onEnd: new task ran to completion", #log, 3)
    T.eq("after erroring onEnd: new task ok", (R.Last(bot) or {}).name, "next")
end

-- 16. Urgent and Label, set from inside the body.
do
    local A = fakeAdapter()
    local bot = fakeBot(16)
    local calls, onEnd = recorder(A, bot)
    local body = Testing.calling({
        function() R.Label(bot, "approach") end,
        function() R.Urgent(bot, true); R.Label(bot, "hold") end,
        function() end,
        function() R.Urgent(bot, false) end,
        function() end,
    })
    R.task(bot, { name = "job", host = HOST, onEnd = onEnd }, body)
    frame(bot)
    T.eq("Label: Current shows it", (R.Current(bot) or {}).label, "approach")
    T.eq("Label: Describe shows it", R.Describe(bot), "job:approach step=1")
    T.check("Urgent: not urgent before it is set", not (A.claims[1] or { c = {} }).c.urgent)
    T.eq("frame 1: one claim", #A.claims, 1)
    frame(bot)
    T.eq("Label: replaced", R.Describe(bot), "job:hold step=2")
    T.eq("Urgent set mid-frame: re-claimed in the same frame", #A.claims, 3)
    T.check("Urgent: Step's claim was before the body set it", not (A.claims[2] or { c = {} }).c.urgent)
    T.eq("Urgent: Tick's claim carries it", (A.claims[3] or { c = {} }).c.urgent, true)
    frame(bot)
    T.eq("Urgent: later claims carry it", (A.claims[4] or { c = {} }).c.urgent, true)
    T.eq("Urgent: still one claim per frame", #A.claims, 4)
    frame(bot)
    T.eq("Urgent cleared: next claim not urgent", (A.claims[#A.claims] or { c = {} }).c.urgent, false)
    R.Cancel(bot, "cancelled", "stop")
    onlyCall("labelled", calls, "cancelled", "stop", 4)
    T.eq("onEnd gets the label current at the end", ((calls[1] or {}).info or {}).label, "hold")
    T.eq("Describe without label", (function()
        R.task(bot, { name = "plain", host = HOST }, Testing.counting(3, {}))
        return R.Describe(bot)
    end)(), "plain step=0")
end

-- 17. Re-entrancy: a task ended (or replaced) from inside its own resume or onEnd still ends exactly once, and
-- a task started from there is not lost.
do
    local A = fakeAdapter()
    local bot = fakeBot(17)
    local body = tasks.SimpleHost.body

    -- The body cancels its own task, then returns in the same resume.
    local calls, onEnd = recorder(A, bot)
    R.task(bot, { name = "self", host = HOST, onEnd = onEnd }, body(function()
        R.Cancel(bot, "cancelled", "self")
        return { success = true, reason = "ok" }
    end))
    frame(bot)
    onlyCall("self-cancel", calls, "cancelled", "self", 0)
    T.eq("self-cancel: Last keeps the cancel", res(bot).reason, "cancelled")
    T.eq("self-cancel: released once", #A.releases, 1)

    -- The body starts its successor, then returns in the same resume.
    local oldCalls, oldEnd = recorder(A, bot)
    local nextLog = {}
    R.task(bot, { name = "first", host = HOST, onEnd = oldEnd }, body(function()
        R.task(bot, { name = "second", host = HOST }, Testing.counting(2, nextLog))
        return { success = true, reason = "ok" }
    end))
    frame(bot)
    onlyCall("handover", oldCalls, "cancelled", "replaced", 0)
    T.eq("handover: successor still running", (R.Current(bot) or {}).name, "second")
    frames(bot, 0.5)
    T.eq("handover: successor ran to completion", #nextLog, 3)
    T.eq("handover: successor ended ok", (R.Last(bot) or {}).name, "second")

    -- A replaced task's onEnd starts another task: the replacement still wins and the interloper ends once.
    local sideCalls, sideEnd = recorder(A, bot)
    R.task(bot, { name = "a", host = HOST, onEnd = function()
        R.task(bot, { name = "side", host = HOST, onEnd = sideEnd }, Testing.counting(5, {}))
    end }, Testing.counting(5, {}))
    frame(bot)
    R.task(bot, { name = "b", host = HOST }, Testing.counting(5, {}))
    T.eq("onEnd restart: replacement is current", (R.Current(bot) or {}).name, "b")
    onlyCall("onEnd restart: interloper", sideCalls, "cancelled", "replaced", 0)
    R.Cancel(bot, "cancelled")

    -- Two levels deep: the interloper's own onEnd starts a third task, which must end too.
    local deepCalls, deepEnd = recorder(A, bot)
    R.task(bot, { name = "c", host = HOST, onEnd = function()
        R.task(bot, { name = "side2", host = HOST, onEnd = function()
            R.task(bot, { name = "deep", host = HOST, onEnd = deepEnd }, Testing.counting(5, {}))
        end }, Testing.counting(5, {}))
    end }, Testing.counting(5, {}))
    frame(bot)
    R.task(bot, { name = "d", host = HOST }, Testing.counting(5, {}))
    T.eq("nested restart: replacement is current", (R.Current(bot) or {}).name, "d")
    onlyCall("nested restart: deepest interloper", deepCalls, "cancelled", "replaced", 0)
    R.Cancel(bot, "cancelled")

    -- An onEnd that always restarts its task cannot block a replacement forever: the replacement is refused.
    local function stubborn()
        R.task(bot, { name = "stubborn", host = HOST, onEnd = stubborn }, Testing.counting(5, {}))
    end
    stubborn()
    T.eq("endless restart: replacement refused", R.task(bot, { name = "e", host = HOST }, Testing.counting(5, {})), false)
    T.check("endless restart: refusal logged", logged(A, "onEnd restarts endlessly"))
end

T.finish()
