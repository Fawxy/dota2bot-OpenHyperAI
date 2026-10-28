-- SimpleHost driven as the engine drives mode files: every frame each mode's GetDesire, the highest wins,
-- OnEnd/OnStart on a switch, then the winner's Think.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("dist/tasks_test.lua")
local R, Verbs, Host = tasks.Tasks, tasks.Verbs, tasks.SimpleHost

local LANE, FARM, ROAM = 1, 6, 4
local LANE_BASE, FARM_BASE = 0.4, 0.2
local DT = 0.1
local DEST = { x = 600, y = 0 }

local function res(bot) return (R.Last(bot) or { result = {} }).result end

-- Walks to `dest`, waits, walks back: a Lua-authored body using only the public bundle API.
local function trip(bot, dest, waitSecs)
    local home = bot:GetLocation()
    return Host.body(function(run)
        local r = run(Verbs.walkTo(bot, dest))
        if not r.success then return r end
        r = run(Verbs.wait(bot, waitSecs))
        if not r.success then return r end
        return run(Verbs.walkTo(bot, home))
    end)
end

-- A world with a plain (unwrapped) laning mode and a wrapped farm mode whose own logic is recorded.
-- opts.roam also wraps a roam mode; opts.globalGetBot resolves the bot through a global GetBot instead.
local function world(opts)
    opts = opts or {}
    local sim = Sim.new()
    local w = { sim = sim, laneDesire = LANE_BASE, desires = {}, farmThinks = 0, switches = {} }
    local getBot = function() return w.bot end
    if opts.globalGetBot then
        _G.GetBot = getBot
        _G.DotaTime = function() return sim.t end
        T.eq("install with DotaTime and no now", Host.install({}), true)
        getBot = nil
    else
        Host.install({ now = function() return sim.t end })
    end
    Host.SetEnabled(true)
    w.bot = sim:addBot{ x = 0, y = 0, speed = 300 }
    w.bot.mode = LANE
    local farm = Host.wrapMode(FARM, {
        GetDesire = function() return FARM_BASE end,
        Think = function() w.farmThinks = w.farmThinks + 1 end,
    }, getBot)
    w.modes = {
        { id = LANE, fns = { GetDesire = function() return w.laneDesire end, Think = function() end,
            OnStart = function() end, OnEnd = function() end } },
        { id = FARM, fns = farm },
    }
    if opts.roam then
        w.modes[#w.modes + 1] = { id = ROAM, fns = Host.wrapMode(ROAM, { GetDesire = function() return 0.1 end }, getBot) }
    end
    return w
end

local function frame(w)
    local bot = w.bot
    local best, bestD
    for _, m in ipairs(w.modes) do
        local d = m.fns.GetDesire() or 0
        w.desires[m.id] = d
        if bestD == nil or d > bestD then best, bestD = m, d end
    end
    if best.id ~= bot.mode then
        for _, m in ipairs(w.modes) do
            if m.id == bot.mode then m.fns.OnEnd() end
        end
        bot.mode = best.id
        w.switches[#w.switches + 1] = { t = w.sim.t, to = best.id }
        best.fns.OnStart()
    end
    best.fns.Think()
    w.sim:step(DT)
end

local function frames(w, n)
    for _ = 1, n do frame(w) end
end

-- A started task lifts its host mode above the competitor; it completes and the desire drops back.
do
    local w = world()
    local bot = w.bot
    frame(w)
    T.eq("idle: laning wins", bot.mode, LANE)
    T.eq("idle: farm desire is its base", w.desires[FARM], FARM_BASE)
    T.eq("task accepted", R.task(bot, { name = "trip", host = FARM }, trip(bot, DEST, 0.5)), true)
    frame(w)
    T.eq("claim lifts farm desire to the floor", w.desires[FARM], 0.6)
    T.eq("engine switched to farm", bot.mode, FARM)
    T.check("task stepped in farm's Think", (R.Current(bot) or {}).steps == 1)
    local reached, maxFrames = false, 200
    while R.Current(bot) ~= nil and maxFrames > 0 do
        frame(w)
        if Sim.dist(bot.loc, DEST) <= 150 then reached = true end
        maxFrames = maxFrames - 1
    end
    T.eq("trip finished ok", res(bot).reason, "ok")
    T.check("walked to the destination", reached)
    T.check("came back home", Sim.dist(bot.loc, { x = 0, y = 0 }) <= 150)
    T.eq("farm's own Think skipped while the task ran", w.farmThinks, 0)
    T.eq("claim gone", Host.ClaimOf(bot, FARM), nil)
    frame(w)
    T.eq("farm desire back to base", w.desires[FARM], FARM_BASE)
    T.eq("engine back on laning", bot.mode, LANE)
    T.eq("two switches in all", #w.switches, 2)
end

-- A higher competing desire preempts the task through farm's OnEnd.
do
    local w = world()
    local bot = w.bot
    local ended = {}
    R.task(bot, { name = "long", host = FARM, onEnd = function(r) ended[#ended + 1] = r end },
        trip(bot, { x = 5000, y = 0 }, 1))
    frames(w, 5)
    T.eq("running in farm", bot.mode, FARM)
    w.laneDesire = 0.9
    frame(w)
    local moves = bot:actionsOf("move")
    T.eq("engine switched to laning", bot.mode, LANE)
    T.eq("preempted", res(bot).reason, "preempted")
    T.eq("preempted by farm's OnEnd", res(bot).message, "mode_end")
    T.eq("task onEnd fired once", #ended, 1)
    T.eq("claim gone", Host.ClaimOf(bot, FARM), nil)
    w.laneDesire = LANE_BASE
    frames(w, 5)
    T.eq("farm desire back to base", w.desires[FARM], FARM_BASE)
    T.eq("no orders after preemption", bot:actionsOf("move"), moves)
    T.eq("farm's own Think never ran", w.farmThinks, 0)
end

-- With preemptAfter, farm's OnEnd leaves the decision to the runner: a short spike survives, a long one ends it.
do
    local w = world()
    local bot = w.bot
    R.task(bot, { name = "sticky", host = FARM, preemptAfter = 0.5 }, trip(bot, { x = 5000, y = 0 }, 1))
    frames(w, 3)
    w.laneDesire = 0.9
    frames(w, 3)
    T.eq("spike: laning took over", bot.mode, LANE)
    T.check("spike: task survives farm's OnEnd", R.Current(bot) ~= nil)
    w.laneDesire = LANE_BASE
    frame(w)
    T.eq("spike over: farm wins back", bot.mode, FARM)
    local steps = (R.Current(bot) or {}).steps
    frame(w)
    T.eq("spike over: task resumes", (R.Current(bot) or {}).steps, (steps or 0) + 1)
    w.laneDesire = 0.9
    frames(w, 7)
    T.eq("long spike: preempted by the runner", res(bot).message, "mode=" .. LANE)
end

-- The host mode never wins: the runner's grace still expires the task, ticked from farm's GetDesire.
do
    local w = world()
    local bot = w.bot
    w.laneDesire = 0.9
    R.task(bot, { name = "never", host = FARM }, trip(bot, DEST, 0))
    frame(w)
    T.eq("claim raises farm desire even while losing", w.desires[FARM], 0.6)
    frames(w, 8)
    T.check("pending within the grace", R.Current(bot) ~= nil)
    frames(w, 4)
    T.eq("expired after the grace", R.Current(bot), nil)
    T.eq("expired: reason", res(bot).reason, "preempted")
    T.eq("expired: message", res(bot).message, "never_started")
    T.eq("expired: farm never active", #w.switches, 0)
    T.eq("expired: claim gone", Host.ClaimOf(bot, FARM), nil)
    T.eq("expired: farm desire back to base", w.desires[FARM], FARM_BASE)
    T.eq("expired: body never ran", bot:actionsOf("move"), 0)
end

-- Kill switch: cancels the running task, drops the desire, refuses new tasks until switched back on.
do
    local w = world()
    local bot = w.bot
    R.task(bot, { name = "k", host = FARM }, trip(bot, { x = 5000, y = 0 }, 1))
    frames(w, 3)
    T.eq("running in farm", bot.mode, FARM)
    Host.SetEnabled(false)
    frame(w)
    T.eq("off: cancelled", res(bot).reason, "cancelled")
    T.eq("off: message", res(bot).message, "disabled")
    T.eq("off: farm desire back to base", w.desires[FARM], FARM_BASE)
    T.eq("off: engine back on laning", bot.mode, LANE)
    T.eq("off: new task refused", R.task(bot, { name = "k2", host = FARM }, trip(bot, DEST, 0)), false)
    Host.SetEnabled(true)
    T.eq("on: new task accepted", R.task(bot, { name = "k3", host = FARM }, trip(bot, DEST, 0)), true)
    frame(w)
    T.eq("on: farm wins again", bot.mode, FARM)
end

-- Two wrapped modes, bot via the global GetBot: one Tick per frame, and only the host mode's desire rises.
do
    local w = world({ roam = true, globalGetBot = true })
    local bot = w.bot
    local guardCalls = 0
    R.task(bot, { name = "g", host = FARM, guard = function() guardCalls = guardCalls + 1 end },
        trip(bot, { x = 5000, y = 0 }, 1))
    frames(w, 10)
    T.eq("global GetBot: farm hosts the task", bot.mode, FARM)
    T.eq("one Tick and one Step per frame", guardCalls, 20)
    T.eq("roam desire untouched", w.desires[ROAM], 0.1)
    _G.GetBot, _G.DotaTime = nil, nil
    T.eq("install without a clock refused", Host.install({}), false)
end

-- A Lua body using ctx: labels reach the runner, and run(ctx.must(verb)) ends the task on the verb's failure.
do
    local w = world()
    local bot = w.bot
    bot.blocked = true
    local after = false
    R.task(bot, { name = "lua_must", host = FARM }, Host.body(function(run, ctx)
        ctx.label("out")
        run(ctx.must(ctx.walkTo(DEST)))
        after = true
    end))
    local label
    for _ = 1, 60 do
        local cur = R.Current(bot)
        if cur == nil then break end
        label = cur.label
        frames(w, 1)
    end
    T.eq("lua body: label set through ctx", label, "out")
    T.eq("lua body: must ends with the verb's reason", res(bot).reason, "stuck")
    T.eq("lua body: nothing after the failed must runs", after, false)
end

-- Points a verb builds itself (holdAt's scattered spot) go out as the engine's Vector when the script has one;
-- Dota's move orders take a Vector, not a plain table.
do
    _G.Vector = function(x, y, z) return { x = x, y = y, z = z, native = true } end
    local w = world()
    local bot = w.bot
    local orders = {}
    local move = bot.Action_MoveToLocation
    bot.Action_MoveToLocation = function(self, loc)
        orders[#orders + 1] = loc
        return move(self, loc)
    end
    R.task(bot, { name = "hold", host = FARM }, Host.body(function(run)
        return run(Verbs.holdAt(bot, function() return { x = 800, y = 0 } end))
    end))
    frames(w, 3)
    _G.Vector = nil
    T.check("holdAt ordered a move", #orders > 0)
    T.eq("holdAt's spot is a native Vector", orders[1] and orders[1].native, true)
    R.Cancel(bot, "cancelled")
    Host.install({ now = function() return 0 end })
    T.eq("no Vector global: no vector hook", Host.adapter.vector, nil)
    local made
    Host.install({ now = function() return 0 end, vector = function(x, y, z) made = { x, y, z } return {} end })
    Host.adapter.vector(1, 2, 3)
    T.eq("opts.vector is the hook", made and made[3], 3)
    Host.install({ now = function() return 0 end })
end

-- The shipped example, loaded as Dota would with the public bundle: starts at 0:30, walks out and back.
do
    local sim = Sim.new()
    local bot = sim:addBot{ x = -2000, y = 0, speed = 300 }
    bot.mode = LANE
    bot.GetUnitName = function() return "npc_dota_hero_test" end
    local printed, savedPrint, savedRequire = {}, print, require
    _G.GetBot = function() return bot end
    _G.DotaTime = function() return sim.t end
    _G.GetScriptDirectory = function() return "bots" end
    _G.Vector = function(x, y, z) return { x = x, y = y, z = z } end
    _G.BOT_MODE_FARM = FARM
    _G.require = function(name)
        T.eq("example requires the bundle next to it", name, "bots/tasks")
        return dofile("../bots/FunLib/engine/tasks.lua")
    end
    _G.print = function(s) printed[#printed + 1] = s end
    dofile("examples/generic/mode_farm_generic.lua")
    _G.require = savedRequire
    local w = { sim = sim, bot = bot, desires = {}, switches = {}, modes = {
        { id = LANE, fns = { GetDesire = function() return LANE_BASE end, Think = function() end,
            OnStart = function() end, OnEnd = function() end } },
        { id = FARM, fns = { GetDesire = GetDesire, Think = Think, OnStart = OnStart, OnEnd = OnEnd } },
    } }
    local reached = false
    for _ = 1, 600 do
        frame(w)
        if Sim.dist(bot.loc, { x = 0, y = 0 }) <= 150 then reached = true end
    end
    _G.print = savedPrint
    _G.GetBot, _G.DotaTime, _G.GetScriptDirectory, _G.Vector, _G.BOT_MODE_FARM = nil, nil, nil, nil, nil
    T.eq("example: farm idle before 0:30", w.switches[1] and w.switches[1].t >= 30, true)
    T.check("example: walked to the river", reached)
    T.check("example: came back", Sim.dist(bot.loc, { x = -2000, y = 0 }) <= 150)
    T.eq("example: started, then ended ok",
        table.concat(printed, "|"), "[scout] npc_dota_hero_test started|[scout] npc_dota_hero_test ended ok")
    T.eq("example: back on laning", bot.mode, LANE)
end

print("simple_host [" .. T.runtime() .. "]")
T.finish()
