-- holdAt: posture verb that keeps the bot near a (moving) point. Runs the compiled bundle on sim.lua.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("dist/tasks_test.lua")
local V = tasks.Verbs

local DT = 0.1

-- Resumes `gen` once per sim step for `secs`; returns the result if it finished, else nil.
local function run(sim, gen, secs)
    for _ = 1, math.floor(secs / DT + 0.5) do
        local s = gen:next()
        if s.done then return s.value end
        sim:step(DT)
    end
    return nil
end

local function moveTargets(bot)
    local out = {}
    for _, a in ipairs(bot.actions) do if a.kind == "move" then out[#out + 1] = a.loc end end
    return out
end

-- Walks to a point out of tolerance, then stands there (hold reported) and never finishes by itself.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0, speed = 300 })
    sim:adapter(tasks)
    local gen = V.holdAt(bot, function() return { x = 900, y = 0 } end, { tolerance = 100, hold = "lane:hold", scatter = 0 })
    local r = run(sim, gen, 10)
    T.eq("static: never ends ok", r, nil)
    T.check("static: arrived within tolerance", Sim.dist(bot.loc, { x = 900, y = 0 }) <= 100)
    T.check("static: hold reported while standing", #sim.holds > 0 and sim.holds[#sim.holds].tag == "lane:hold")
    local before = { x = bot.loc.x, y = bot.loc.y }
    run(sim, gen, 2)
    T.check("static: stays put once there", Sim.dist(bot.loc, before) < 1)
end

-- A moving point is followed: the bot ends up near where the point is now, not where it started.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0, speed = 300 })
    sim:adapter(tasks)
    local p = { x = 500, y = 0 }
    local gen = V.holdAt(bot, function() return p end, { tolerance = 100, scatter = 0 })
    run(sim, gen, 3)
    p = { x = 500, y = 1200 }
    run(sim, gen, 6)
    T.check("moving: followed the point", Sim.dist(bot.loc, p) <= 100)
end

-- Inside tolerance a small drift of the point does not re-target the bot; re-targets come at the repath
-- cadence (here 1 s, no jitter): about one new target per second, not one per frame.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0, speed = 300 })
    sim:adapter(tasks)
    local k = 0
    local gen = V.holdAt(bot, function()
        k = k + 1
        return { x = 10 * math.sin(k), y = 0 }
    end, { tolerance = 100, repath = 1, jitter = 0, scatter = 60 })
    run(sim, gen, 5)
    local distinct, last = 0, nil
    for _, loc in ipairs(moveTargets(bot)) do
        if last == nil or Sim.dist(loc, last) > 1e-6 then
            -- orders to the bot's own location (standing) are not targets
            distinct = distinct + 1
        end
        last = loc
    end
    T.check("cadence: re-orders bounded by repath (got " .. distinct .. " order changes in 5 s)", distinct <= 12)
end

-- Something else ordered the bot away (e.g. a last-hit attack or move from the host): the next resume
-- takes the bot back, so a foreign order never sticks while the posture runs.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0, speed = 300 })
    sim:adapter(tasks)
    local gen = V.holdAt(bot, function() return { x = 0, y = 0 } end, { tolerance = 100, scatter = 0 })
    run(sim, gen, 1)
    bot:Action_MoveToLocation({ x = 2000, y = 0 })
    gen:next()
    sim:step(DT)
    run(sim, gen, 2)
    T.check("foreign order: bot kept near the point", Sim.dist(bot.loc, { x = 0, y = 0 }) <= 100)
end

-- An unknown point (nil) stands the bot still rather than failing.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0, speed = 300 })
    sim:adapter(tasks)
    bot.moveTarget = { x = 1000, y = 0 }
    local gen = V.holdAt(bot, function() return nil end, {})
    T.eq("nil point: keeps running", run(sim, gen, 1), nil)
    T.check("nil point: bot stopped", Sim.dist(bot.loc, { x = 0, y = 0 }) < 40)
end

-- Ends only through its exits: interruptIf, deadline, death.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0 })
    sim:adapter(tasks)
    local stop = false
    local gen = V.holdAt(bot, function() return { x = 0, y = 0 } end, { interruptIf = function() return stop end })
    sim:at(1, function() stop = true end)
    T.eq("interrupt: reason", (run(sim, gen, 3) or {}).reason, "interrupted")

    local gen2 = V.holdAt(bot, function() return { x = 0, y = 0 } end, { deadline = sim.t + 1 })
    T.eq("deadline: reason", (run(sim, gen2, 3) or {}).reason, "timeout")

    local gen3 = V.holdAt(bot, function() return { x = 0, y = 0 } end, {})
    sim:at(sim.t + 0.5, function(s) s:kill(bot) end)
    T.eq("dead: reason", (run(sim, gen3, 3) or {}).reason, "dead")
end


-- Idle steps: once at the point, the bot shuffles in steps of 50-150 about once a second, never more than
-- `scatter` from the point, instead of freezing on one spot.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0, speed = 300 })
    sim:adapter(tasks, { random = Sim.lcg(3) })
    local P = { x = 600, y = 0 }
    local gen = V.holdAt(bot, function() return P end, { tolerance = 30, scatter = 150, step = { 50, 150 }, repath = 1, jitter = 0.8 })
    run(sim, gen, 4)
    local n0 = #bot.actions
    local orders, steps, worst = {}, {}, 0
    local last
    for _ = 1, 100 do -- 10 s
        local before = { x = bot.loc.x, y = bot.loc.y }
        gen:next()
        local a = bot.actions[#bot.actions]
        if a.kind == "move" and Sim.dist(a.loc, before) > 1 and (last == nil or Sim.dist(a.loc, last) > 1e-6) then
            orders[#orders + 1] = a.loc
            steps[#steps + 1] = Sim.dist(a.loc, before)
            last = a.loc
        end
        worst = math.max(worst, Sim.dist(bot.loc, P))
        sim:step(DT)
    end
    T.check("idle: 6-16 new spots in 10 s (got " .. #orders .. ")", #orders >= 6 and #orders <= 16)
    local okLen = true
    for _, d in ipairs(steps) do if d < 45 or d > 155 then okLen = false end end
    T.check("idle: each new spot a 50-150 step from the bot", okLen)
    T.check("idle: stays within scatter of the point (worst " .. math.floor(worst) .. ")", worst <= 150 + 30)
    T.check("idle: issued orders", #bot.actions > n0)
end

-- `follow`: a point that wobbles by 40 every frame does not re-target the bot when follow is 100.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0, speed = 300 })
    sim:adapter(tasks)
    local k = 0
    local gen = V.holdAt(bot, function()
        k = k + 1
        return { x = (k % 2) * 40, y = 0 }
    end, { tolerance = 30, follow = 100, repath = 2, jitter = 0, scatter = 0 })
    run(sim, gen, 5)
    local distinct, last = 0, nil
    for _, a in ipairs(bot.actions) do
        if a.kind == "move" and (last == nil or Sim.dist(a.loc, last) > 1e-6) and Sim.dist(a.loc, { x = 0, y = 0 }) > 1 then distinct = distinct + 1 end
        if a.kind == "move" then last = a.loc end
    end
    T.check("follow: wobble below follow keeps the spot (" .. distinct .. " re-targets in 5 s)", distinct <= 3)
end

-- Bound on ctx like every verb.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0, speed = 300 })
    sim:adapter(tasks)
    local body = tasks.Testing.ctxHold({ x = 600, y = 0 })
    tasks.Tasks.task(bot, { name = "hold", host = 0 }, body)
    for _ = 1, 40 do
        tasks.Tasks.Step(bot, 0)
        sim:step(DT)
    end
    T.check("ctx.holdAt: bot moved to the point", Sim.dist(bot.loc, { x = 600, y = 0 }) <= 100)
    T.eq("ctx.holdAt: task still running", (tasks.Tasks.Current(bot) or {}).name, "hold")
end

-- Spots the verb builds (scattered points) are made by the adapter's vector hook, so hosts whose move order
-- needs a native vector type (Dota's Vector) get one.
do
    local sim = Sim.new()
    local bot = sim:addBot({ x = 0, y = 0, speed = 300 })
    local a = sim:adapter(nil)
    a.vector = function(x, y, z) return { x = x, y = y, z = z, native = true } end
    tasks.init(a)
    local gen = V.holdAt(bot, function() return { x = 800, y = 0 } end, { scatter = 50 })
    run(sim, gen, 0.5)
    local first
    for _, ac in ipairs(bot.actions) do if ac.kind == "move" then first = ac break end end
    T.check("vector hook: walk spot built by the adapter", first ~= nil and first.native == true)
end

print("holdAt [" .. T.runtime() .. "]")
T.finish()
