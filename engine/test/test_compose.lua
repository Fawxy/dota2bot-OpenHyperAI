-- Verbs composed with yield* (Testing.walkThenWait), driven through the runner against the frame simulator.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("dist/tasks_test.lua")
local R, Testing = tasks.Tasks, tasks.Testing

local HOST, OTHER = 7, 3
local DT = 0.1
local DEST = { x = 900, y = 0 }

-- A sim whose adapter records claims and releases (the stock sim adapter discards them).
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

-- One frame as the host plays it: Think (Step) only while the host mode is active and the bot is not
-- stunned, then Tick, then the world advances. Returns whether Step consumed the frame.
local function frame(sim, bot)
    local stepped = false
    if bot.mode == HOST and not bot.stunned then stepped = R.Step(bot, HOST) end
    R.Tick(bot)
    sim:step(DT)
    return stepped
end

local function result(bot) return (R.Last(bot) or { result = {} }).result end

-- Runs frames until the task is no longer current; returns (frames stepped, sim time it finished at).
local function runToEnd(sim, bot, maxFrames)
    local stepped = 0
    for _ = 1, maxFrames or 500 do
        if R.Current(bot) == nil then return stepped, sim.t end
        if frame(sim, bot) then stepped = stepped + 1 end
    end
    return stepped, nil
end

-- Walk, then wait: arrives, waits the full duration, finishes ok; claims every frame, released once.
do
    local sim, bot = world()
    local WAIT = 1.0
    local arrivedAt
    T.eq("task accepted", R.task(bot, { name = "walkwait", host = HOST }, Testing.walkThenWait(bot, DEST, WAIT)), true)
    local stepped, releasedEarly = 0, false
    for _ = 1, 500 do
        if R.Current(bot) == nil then break end
        if frame(sim, bot) then stepped = stepped + 1 end
        if arrivedAt == nil and Sim.dist(bot.loc, DEST) <= 150 then arrivedAt = sim.t end
        if R.Current(bot) ~= nil and #sim.releases > 0 then releasedEarly = true end
    end
    T.eq("not released while running", releasedEarly, false)
    T.eq("finished ok", result(bot).reason, "ok")
    T.eq("finished success", result(bot).success, true)
    T.eq("Last names the task", (R.Last(bot) or {}).name, "walkwait")
    T.check("bot reached the location", Sim.dist(bot.loc, DEST) <= 150)
    T.check("move actions issued", bot:actionsOf("move") > 0)
    T.check("arrived, then waited before finishing",
        arrivedAt ~= nil and #sim.releases == 1 and sim.releases[1].t - arrivedAt >= WAIT - DT)
    T.check("took travel + wait time", stepped >= (900 - 150) / 300 / DT + WAIT / DT)
    T.eq("one claim per stepped frame", #sim.claims, stepped)
    local claimsOk = #sim.claims > 0
    for i, c in ipairs(sim.claims) do
        claimsOk = claimsOk and c.id == bot:GetPlayerID() and c.c.mode == HOST and c.c.source == "task:walkwait"
            and math.abs(c.t - (i - 1) * DT) < 1e-6
    end
    T.check("claims posted every frame with the task's source/mode", claimsOk)
    T.eq("released exactly once", #sim.releases, 1)
    T.eq("release source", sim.releases[1] and sim.releases[1].source, "task:walkwait")
    T.eq("release mode", sim.releases[1] and sim.releases[1].mode, HOST)
    T.check("released after the last claim", sim.releases[1] and sim.releases[1].t >= sim.claims[#sim.claims].t)
end

-- Mode change mid-walk: preempted, released once, and no move orders after cancellation.
do
    local sim, bot = world()
    R.task(bot, { name = "walk", host = HOST }, Testing.walkThenWait(bot, DEST, 1.0))
    sim:at(1.0, function() bot.mode = OTHER end)
    local stepped, finishedAt = runToEnd(sim, bot, 100)
    local movesAtCancel = bot:actionsOf("move")
    local distAtCancel = Sim.dist(bot.loc, DEST)
    for _ = 1, 30 do frame(sim, bot) end
    T.eq("mode change -> preempted", result(bot).reason, "preempted")
    T.eq("preempted success=false", result(bot).success, false)
    T.check("cancelled mid-walk", finishedAt ~= nil and distAtCancel > 150)
    T.check("walked before the mode change", stepped > 0 and movesAtCancel > 0)
    T.eq("no move orders after cancellation", bot:actionsOf("move"), movesAtCancel)
    T.eq("preempted: one claim per stepped frame", #sim.claims, stepped)
    T.eq("preempted: released once", #sim.releases, 1)
end

-- Stun mid-walk: the host skips Think (no Step) but Tick still runs; the task survives and completes.
do
    local sim, bot = world()
    R.task(bot, { name = "stun", host = HOST }, Testing.walkThenWait(bot, DEST, 0.5))
    local STUN_FROM, STUN_TO = 1.0, 2.0
    sim:at(STUN_FROM, function() bot.stunned = true end)
    sim:at(STUN_TO, function() bot.stunned = false end)
    local alive, skipped, stepped = true, 0, 0
    for _ = 1, 500 do
        if R.Current(bot) == nil then break end
        local stunned = bot.stunned
        if frame(sim, bot) then stepped = stepped + 1 elseif stunned then skipped = skipped + 1 end
        if stunned then alive = alive and R.Current(bot) ~= nil end
    end
    T.check("frames skipped while stunned", skipped >= 9)
    T.check("task still current throughout the stun", alive and skipped > 0)
    T.eq("stun: released once", #sim.releases, 1)
    T.eq("stun: completes ok afterwards", result(bot).reason, "ok")
    T.check("stun: reached the location", Sim.dist(bot.loc, DEST) <= 150)
    T.check("stun: finished after the stun ended", sim.releases[1] and sim.releases[1].t > STUN_TO)
    T.eq("stun: claims kept up on stunned frames too", #sim.claims, stepped + skipped)
end

print("compose [" .. T.runtime() .. "]")
T.finish()
