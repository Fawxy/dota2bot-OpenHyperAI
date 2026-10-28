-- Feasibility probe: TSTL generators / yield* compiled into the dist bundle, run under the host runtime.
local T = dofile("test/helpers.lua")
local tasks = dofile("dist/tasks_test.lua")

T.check("bundle returns a module table", type(tasks) == "table")
T.eq("Supported()", tasks.Supported(), true)

-- 3-level yield* chain: inner yields 2, middle 1, outer 1; returns ((10 + 5) * 2).
do
    local gen = tasks.Probe.outer()
    local yields, last = 0, nil
    for _ = 1, 20 do
        last = gen:next()
        if last.done then break end
        yields = yields + 1
    end
    T.eq("outer yield count", yields, 4)
    T.eq("outer done", last and last.done, true)
    T.eq("outer return value", last and last.value, 30)

    local again = gen:next()
    T.eq("resume after done stays done", again.done, true)
    T.eq("resume after done has no value", again.value, nil)
end

do
    local gen = tasks.Probe.middle()
    local r
    for _ = 1, 3 do r = gen:next() end
    T.eq("middle not done after 3 yields", r.done, false)
    r = gen:next()
    T.eq("middle done on 4th step", r.done, true)
    T.eq("middle return value", r.value, 15)
end

-- Local state persists across frames.
do
    local gen = tasks.Probe.counter(3)
    local seen = {}
    local r
    repeat
        r = gen:next()
        if not r.done then seen[#seen + 1] = r.value end
    until r.done
    T.eq("counter yields", #seen, 3)
    T.eq("counter step 1", seen[1], 1)
    T.eq("counter step 3", seen[3], 3)
    T.eq("counter return", r.value, 3)
end

-- Two live generators don't share state.
do
    local a, b = tasks.Probe.counter(5), tasks.Probe.counter(5)
    a:next(); a:next(); a:next()
    T.eq("independent generator a", a:next().value, 4)
    T.eq("independent generator b", b:next().value, 1)
end

-- Documented, not asserted: yielding from inside a pcall'd function.
do
    local gen = tasks.Probe.yieldInPcall()
    local ok1, r1 = pcall(function() return gen:next() end)
    local ok2, r2 = true, nil
    if ok1 and not r1.done then ok2, r2 = pcall(function() return gen:next() end) end
    local line
    if not ok1 then
        line = "error " .. tostring(r1)
    elseif not ok2 then
        line = "error " .. tostring(r2)
    else
        local res = r2 or r1
        local inner = res.value or {}
        if inner[1] then
            line = "ok"
        else
            line = "error " .. tostring(inner[2])
        end
    end
    print("PCALL_YIELD [" .. T.runtime() .. "]: " .. line)
end

T.finish()
