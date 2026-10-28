-- Verbs stepped directly (no runner) against the frame simulator.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("../bots/FunLib/engine/tasks.lua")
local V = tasks.Verbs

local DT = 0.1

-- Per frame: step the generator, then advance the sim. Returns the result and the sim time it finished at.
local function run(sim, g, maxFrames)
    for _ = 1, maxFrames or 1000 do
        local r = g:next()
        if r.done then return r.value, sim.t end
        sim:step(DT)
    end
    error("generator did not finish", 0)
end

local function world(opts)
    local sim = Sim.new()
    sim:adapter(tasks, opts)
    return sim
end

-- walkTo ---------------------------------------------------------------------

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
    local r, t = run(sim, V.walkTo(bot, { x = 1000, y = 0 }))
    T.eq("walkTo ok reason", r.reason, "ok")
    T.eq("walkTo ok success", r.success, true)
    T.check("walkTo ok: bot moved to within tolerance", Sim.dist(bot.loc, { x = 1000, y = 0 }) <= 150)
    T.check("walkTo ok: move actions issued", bot:actionsOf("move") >= 1)
    T.near("walkTo ok: move target is loc", bot.actions[1] and bot.actions[1].loc.x, 1000)
    T.check("walkTo ok: took travel time", t >= 2.5)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    local r = run(sim, V.walkTo(bot, { x = 100, y = 0 }))
    T.eq("walkTo already within tolerance -> ok", r.reason, "ok")
    T.eq("walkTo already within tolerance issues no move", bot:actionsOf("move"), 0)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, speed = 50 }
    local r, t = run(sim, V.walkTo(bot, { x = 2000, y = 0 }, { timeout = 2, stuckSecs = 5 }))
    T.eq("walkTo timeout", r.reason, "timeout")
    T.eq("walkTo timeout success=false", r.success, false)
    T.check("walkTo timeout after ~2s", t > 2 and t < 2.5)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, blocked = true }
    local r, t = run(sim, V.walkTo(bot, { x = 1000, y = 0 }))
    T.eq("walkTo stuck (blocked)", r.reason, "stuck")
    T.check("walkTo stuck after ~stuckSecs", t >= 1.5 and t < 2)
end

-- Same blockage window, once as a plain block and once as a stun: only the block counts towards stuck.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, speed = 300, blocked = true }
    sim:at(3, function() bot.blocked = false end)
    local r = run(sim, V.walkTo(bot, { x = 1500, y = 0 }))
    T.eq("walkTo blocked 3s without stun -> stuck", r.reason, "stuck")
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, speed = 300, stunned = true }
    sim:at(3, function() bot.stunned = false end)
    local r, t = run(sim, V.walkTo(bot, { x = 1500, y = 0 }))
    T.eq("walkTo stunned 3s (> stuckSecs) -> not stuck", r.reason, "ok")
    T.check("walkTo stunned: arrived after the stun", t >= 3)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    local r, t = run(sim, V.walkTo(bot, { x = 3000, y = 0 }, { interruptIf = function() return sim.t >= 0.5 end }))
    T.eq("walkTo interrupted", r.reason, "interrupted")
    T.near("walkTo interrupted at 0.5", t, 0.5, 0.05)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    sim:at(0.5, function() bot.alive = false end)
    local r, t = run(sim, V.walkTo(bot, { x = 3000, y = 0 }))
    T.eq("walkTo dead", r.reason, "dead")
    T.near("walkTo dead at 0.5", t, 0.5, 0.05)
end

-- wait -----------------------------------------------------------------------

do
    local sim = world()
    local bot = sim:addBot{}
    local r, t = run(sim, V.wait(bot, 2))
    T.eq("wait ok", r.reason, "ok")
    T.near("wait ok after 2s", t, 2, 0.05)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local r, t = run(sim, V.wait(bot, 5, { interruptIf = function() return sim.t >= 0.95 end }))
    T.eq("wait interrupted", r.reason, "interrupted")
    T.near("wait interrupted at 1s", t, 1, 0.05)
end

do
    local sim = world()
    local bot = sim:addBot{}
    sim:at(0.3, function() bot.alive = false end)
    local r = run(sim, V.wait(bot, 5))
    T.eq("wait dead", r.reason, "dead")
end

-- retreatTo ------------------------------------------------------------------

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    local r = run(sim, V.retreatTo(bot, { safe = { x = -1500, y = 0 } }))
    T.eq("retreatTo ok", r.reason, "ok")
    T.check("retreatTo ok: within its 300 tolerance", Sim.dist(bot.loc, { x = -1500, y = 0 }) <= 300)
    T.check("retreatTo ok: actually moved", bot.loc.x < -1000)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, blocked = true }
    local r, t = run(sim, V.retreatTo(bot, { safe = { x = -1500, y = 0 } }))
    T.eq("retreatTo passes through stuck", r.reason, "stuck")
    T.check("retreatTo uses stuckSecs 3", t >= 3 and t < 3.5)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    local r, t = run(sim, V.retreatTo(bot, { safe = { x = -1500, y = 0 }, interruptIf = function() return sim.t >= 0.95 end }))
    T.eq("retreatTo honours interruptIf", r.reason, "interrupted")
    T.near("retreatTo interrupted at 1 s", t, 1)
end

-- lastHit --------------------------------------------------------------------

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 60, attackPoint = 0.3, speed = 300 }
    local creep = sim:addCreep{ x = 400, y = 0, hp = 300, drain = 100 }
    sim:addCreep{ x = 100, y = 0, hp = 900 } -- higher health; must not be picked
    local r = run(sim, V.lastHit(bot, { maxWait = 5 }))
    T.eq("lastHit ok", r.reason, "ok")
    T.eq("lastHit ok: last hits +1", bot.lastHits, 1)
    T.eq("lastHit ok: creep dead", creep.alive, false)
    T.eq("lastHit ok: exactly one swing", bot:actionsOf("attack"), 1)
    local swing
    for _, a in ipairs(bot.actions) do if a.kind == "attack" then swing = a end end
    T.check("lastHit ok: swung at the lowest-health creep", swing and swing.target == creep)
    -- 100 hp/s of drain over the 0.3 s attack point: due at hp <= 90, one 0.1 s frame of slack.
    T.check("lastHit ok: swing leads the drain (hp " .. tostring(swing and swing.targetHp) .. ")",
        swing and swing.targetHp > 60 and swing.targetHp <= 90)
    T.check("lastHit ok: moved into range first", bot:actionsOf("move") >= 1)
end

do
    local sim = world()
    local bot = sim:addBot{}
    sim:addCreep{ x = 2000, y = 0, hp = 50 } -- outside search radius
    sim:addCreep{ x = 50, y = 0, hp = 50, team = 2 } -- allied
    local r = run(sim, V.lastHit(bot))
    T.eq("lastHit no_target", r.reason, "no_target")
end

do
    local vetoed = 0
    local sim = world({ lastHitFilter = function(_, _) vetoed = vetoed + 1; return false end })
    local bot = sim:addBot{}
    sim:addCreep{ x = 100, y = 0, hp = 40 }
    sim:addCreep{ x = 120, y = 0, hp = 45 }
    local r = run(sim, V.lastHit(bot))
    T.eq("lastHit etiquette", r.reason, "etiquette")
    T.eq("lastHit etiquette: filter consulted per candidate", vetoed, 2)
    T.eq("lastHit etiquette: no swing", bot:actionsOf("attack"), 0)
end

do
    local sim = world()
    local bot = sim:addBot{ damage = 60 }
    local ally = sim:addBot{ x = 200, y = 0 } -- another bot on our team (e.g. a teammate)
    local creep = sim:addCreep{ x = 100, y = 0, hp = 500 }
    sim:killAt(0.5, creep, ally)
    local r = run(sim, V.lastHit(bot))
    T.eq("lastHit taken_by_other (before swing)", r.reason, "taken_by_other")
    T.eq("lastHit taken_by_other: our last hits unchanged", bot.lastHits, 0)
end

do
    local sim = world()
    local bot = sim:addBot{ damage = 60, attackPoint = 0.4 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 50 }
    sim:killAt(0.2, creep, nil) -- killed mid-swing by someone who isn't an enemy hero
    local r = run(sim, V.lastHit(bot))
    T.eq("lastHit taken_by_other (during swing)", r.reason, "taken_by_other")
    T.eq("lastHit taken_by_other (during swing): swing was issued", bot:actionsOf("attack"), 1)
end

do
    local sim = world()
    local bot = sim:addBot{ damage = 60, attackPoint = 0.4 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 50 }
    local enemy = sim:addHero{ x = 300, y = 0, team = 3 }
    enemy.attackTarget = creep
    sim:killAt(0.2, creep, enemy)
    local r = run(sim, V.lastHit(bot))
    T.eq("lastHit denied", r.reason, "denied")
    T.eq("lastHit denied: our last hits unchanged", bot.lastHits, 0)
end

do
    local sim = world()
    local bot = sim:addBot{ damage = 60, attackPoint = 0.3 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 50 }
    sim:at(0.1, function() creep.hp = 400 end) -- healed before the hit lands
    local r = run(sim, V.lastHit(bot))
    T.eq("lastHit missed", r.reason, "missed")
    T.eq("lastHit missed: creep survived", creep.alive, true)
    T.eq("lastHit missed: one swing", bot:actionsOf("attack"), 1)
end

do
    local sim = world()
    local bot = sim:addBot{ damage = 50 }
    sim:addCreep{ x = 100, y = 0, hp = 500 }
    local r, t = run(sim, V.lastHit(bot, { maxWait = 1.5 }))
    T.eq("lastHit timeout", r.reason, "timeout")
    T.check("lastHit timeout after maxWait", t > 1.5 and t < 2)
    T.eq("lastHit timeout: never swung", bot:actionsOf("attack"), 0)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local creep = sim:addCreep{ x = 100, y = 0, hp = 500 }
    sim:at(0.3, function() bot.alive = false end)
    local r = run(sim, V.lastHit(bot, { target = creep }))
    T.eq("lastHit dead", r.reason, "dead")
end

do
    local sim = world()
    local bot = sim:addBot{}
    local stripped = setmetatable({}, { __index = function(_, k)
        if k == "GetAttackDamage" then return nil end
        local v = bot[k]
        if type(v) == "function" then return function(_, ...) return v(bot, ...) end end
        return v
    end })
    local r = run(sim, V.lastHit(stripped))
    T.eq("lastHit unsupported without GetAttackDamage", r.reason, "unsupported")
end

-- Per-frame creep cache: two lastHit verbs for one bot in one frame share one set of creep queries.
do
    local sim = world()
    local bot = sim:addBot{ damage = 10 }
    local other = sim:addBot{ damage = 10 }
    sim:addCreep{ x = 100, y = 0, hp = 500 }
    local g1, g2 = V.lastHit(bot), V.lastHit(bot)
    g1:next()
    local once = sim:count("GetNearbyLaneCreeps", bot)
    T.check("creep cache: first verb queries", once >= 1)
    g2:next()
    T.eq("creep cache: second verb in the frame adds no query", sim:count("GetNearbyLaneCreeps", bot), once)
    V.lastHit(other):next()
    T.eq("creep cache: keyed per bot", sim:count("GetNearbyLaneCreeps", other), once)
    sim:step(DT)
    V.lastHit(bot):next()
    T.eq("creep cache: refreshed next frame", sim:count("GetNearbyLaneCreeps", bot), 2 * once)
end

-- walkTo / walkPath: stuckSecs = math.huge disables stuck detection --------------

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, blocked = true }
    local r, t = run(sim, V.walkTo(bot, { x = 1000, y = 0 }, { timeout = 3, stuckSecs = math.huge }))
    T.eq("walkTo stuckSecs=huge: blocked bot times out instead of stuck", r.reason, "timeout")
    T.check("walkTo stuckSecs=huge: kept ordering moves past the default stuck window", t > 3 and bot:actionsOf("move") >= 30)
end

-- walkPath -------------------------------------------------------------------

local function moveTargets(bot)
    local out = {}
    for _, a in ipairs(bot.actions) do
        if a.kind == "move" then
            local last = out[#out]
            if not last or last.x ~= a.loc.x or last.y ~= a.loc.y then out[#out + 1] = a.loc end
        end
    end
    return out
end

-- Three legs, each longer than stuckSecs' worth of the previous leg's best distance: also proves the stuck
-- baseline restarts per waypoint (otherwise the second leg's larger distance would read as no progress).
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
    local path = { { x = 600, y = 0 }, { x = 600, y = 900 }, { x = 0, y = 900 } }
    local r = run(sim, V.walkPath(bot, path, { stuckSecs = 0.5 }))
    T.eq("walkPath ok", r.reason, "ok")
    local mt = moveTargets(bot)
    T.eq("walkPath: three distinct move targets", #mt, 3)
    local inOrder = #mt == 3
    for i = 1, 3 do inOrder = inOrder and mt[i] and mt[i].x == path[i].x and mt[i].y == path[i].y end
    T.check("walkPath: moved to the waypoints in order", inOrder)
    T.check("walkPath: ended at the last waypoint", Sim.dist(bot.loc, path[3]) <= 150)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    local g = V.walkPath(bot, { { x = 50, y = 0 }, { x = 100, y = 0 }, { x = 1000, y = 0 } })
    T.eq("walkPath skips reached leading waypoints: still running", g:next().done, false)
    T.near("walkPath skips several reached waypoints in one frame", bot.actions[1] and bot.actions[1].loc.x, 1000)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
    local path = { { x = 600, y = 0 }, { x = 650, y = 0 }, { x = 700, y = 0 }, { x = 700, y = 900 } }
    sim:at(0.25, function() bot.loc.x, bot.loc.y = 680, 0 end) -- knocked within reach of waypoints 1-3
    local r = run(sim, V.walkPath(bot, path))
    T.eq("walkPath after displacement ok", r.reason, "ok")
    local mt = moveTargets(bot)
    T.check("walkPath: skipped three pending waypoints in one frame after displacement",
        #mt == 2 and mt[1].x == 600 and mt[2].x == 700 and mt[2].y == 900)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    local r = V.walkPath(bot, { { x = 50, y = 0 }, { x = 0, y = 60 } }):next()
    T.eq("walkPath already at the end: done on first resume", r.done, true)
    T.eq("walkPath already at the end: ok", r.value and r.value.reason, "ok")
    T.eq("walkPath already at the end: no move", bot:actionsOf("move"), 0)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, speed = 50 }
    local r, t = run(sim, V.walkPath(bot, { { x = 100, y = 0 }, { x = 3000, y = 0 } }, { timeout = 2, stuckSecs = 5 }))
    T.eq("walkPath timeout", r.reason, "timeout")
    T.check("walkPath timeout counts from the verb's start, not the waypoint", t > 2 and t < 2.3)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
    sim:at(1.0, function() bot.blocked = true end)
    local r, t = run(sim, V.walkPath(bot, { { x = 300, y = 0 }, { x = 3000, y = 0 } }))
    T.eq("walkPath stuck", r.reason, "stuck")
    -- Last progress is seen on the 0.9 frame (the block applies before the 1.0 movement step).
    T.near("walkPath stuck stuckSecs after the last progress", t, 2.4)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, blocked = true }
    local r, t = run(sim, V.walkPath(bot, { { x = 1000, y = 0 }, { x = 2000, y = 0 } }, { timeout = 3, stuckSecs = math.huge }))
    T.eq("walkPath stuckSecs=huge: blocked bot times out instead of stuck", r.reason, "timeout")
    T.check("walkPath stuckSecs=huge: kept walking until the timeout", t > 3 and bot:actionsOf("move") >= 30)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    local r, t = run(sim, V.walkPath(bot, { { x = 3000, y = 0 } }, { interruptIf = function() return sim.t >= 0.5 end }))
    T.eq("walkPath interrupted", r.reason, "interrupted")
    T.near("walkPath interrupted at 0.5", t, 0.5, 0.05)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    sim:at(0.5, function() bot.alive = false end)
    local r, t = run(sim, V.walkPath(bot, { { x = 3000, y = 0 } }))
    T.eq("walkPath dead", r.reason, "dead")
    T.near("walkPath dead at 0.5", t, 0.5, 0.05)
end

-- waitUntil ------------------------------------------------------------------

do
    local sim = world()
    local bot = sim:addBot{}
    sim.t = 5
    local r = V.waitUntil(bot, 3, { hold = "h" }):next()
    T.eq("waitUntil past t: done on first resume", r.done, true)
    T.eq("waitUntil past t: ok", r.value and r.value.reason, "ok")
    T.eq("waitUntil past t: no hold", #sim.holds, 0)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local frames = 0
    local g = V.waitUntil(bot, 0.55, { hold = "stand" })
    local r, t = run(sim, setmetatable({}, { __index = { next = function() frames = frames + 1; return g:next() end } }))
    T.eq("waitUntil future t: ok", r.reason, "ok")
    T.near("waitUntil finishes at the first frame with now >= t", t, 0.6)
    T.eq("waitUntil: resumed once per frame up to t", frames, 7)
    T.eq("waitUntil: hold called each waiting frame", #sim.holds, 6)
    local tagged = #sim.holds == 6
    for i, h in ipairs(sim.holds) do
        tagged = tagged and h.tag == "stand" and h.id == bot.id and math.abs(h.t - (i - 1) * DT) < 1e-6
    end
    T.check("waitUntil: hold carries the tag on frames 0..0.5", tagged)
end

do
    local sim = world()
    local bot = sim:addBot{}
    sim:at(0.3, function() bot.alive = false end)
    local r, t = run(sim, V.waitUntil(bot, 5))
    T.eq("waitUntil dead", r.reason, "dead")
    T.near("waitUntil dead at 0.3", t, 0.3, 0.05)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local r, t = run(sim, V.waitUntil(bot, 5, { interruptIf = function() return sim.t >= 0.25 end }))
    T.eq("waitUntil interrupted", r.reason, "interrupted")
    T.near("waitUntil interrupted at 0.3", t, 0.3, 0.05)
end

-- attackAndConfirm -----------------------------------------------------------

local function attacks(bot)
    local out = {}
    for _, a in ipairs(bot.actions) do if a.kind == "attack" then out[#out + 1] = a end end
    return out
end

-- First of `units` that is alive and visible.
local function picker(units)
    return function()
        for _, u in ipairs(units) do
            if u.alive and not u.hidden then return u end
        end
        return nil
    end
end

do
    local sim = world()
    local bot = sim:addBot{ attackPoint = 0.3 }
    local creep = sim:addCreep{ x = 100, y = 0, passive = true }
    local g = V.attackAndConfirm(bot, picker({ creep }), { findFor = 1, confirmFor = 2 })
    local first = g:next()
    local a = attacks(bot)
    T.eq("attackAndConfirm: not finished on the order frame", first.done, false)
    T.check("attackAndConfirm: attack issued on the first resume, queued, at the picked target",
        #a == 1 and a[1].t == 0 and a[1].once == true and a[1].target == creep)
    sim:step(DT)
    local r, t = run(sim, g)
    T.eq("attackAndConfirm ok via the attack landing", r.reason, "ok")
    T.near("attackAndConfirm ok on the frame the hit landed", t, 0.3)
    T.eq("attackAndConfirm ok: single order", #attacks(bot), 1)
end

do
    local sim = world()
    local bot = sim:addBot{ whiff = true }
    local creep = sim:addCreep{ x = 100, y = 0, passive = true }
    local r, t = run(sim, V.attackAndConfirm(bot, picker({ creep }), {
        findFor = 1, confirmFor = 2, confirmed = function() return sim.t >= 0.45 end,
    }))
    T.eq("attackAndConfirm ok via confirmed() alone", r.reason, "ok")
    T.near("attackAndConfirm confirmed() at 0.5", t, 0.5)
end

do
    local sim = world()
    local bot = sim:addBot{ whiff = true }
    local creep = sim:addCreep{ x = 100, y = 0 }
    sim:at(0.4, function() creep.attackTarget = bot end)
    local r, t = run(sim, V.attackAndConfirm(bot, picker({ creep }), { findFor = 1, confirmFor = 2 }))
    T.eq("attackAndConfirm ok via the target attacking the bot", r.reason, "ok")
    T.near("attackAndConfirm target-aggro confirm at 0.4", t, 0.4)
end

do
    local sim = world()
    local bot = sim:addBot{ whiff = true }
    local creep = sim:addCreep{ x = 100, y = 0, passive = true }
    local r, t = run(sim, V.attackAndConfirm(bot, picker({ creep }), {
        findFor = 1, confirmFor = 2, interruptIf = function() return sim.t >= 0.45 end,
    }))
    T.eq("attackAndConfirm honours interruptIf", r.reason, "interrupted")
    T.near("attackAndConfirm interrupted at 0.5", t, 0.5)
end

do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0 }
    local r, t = run(sim, V.attackAndConfirm(bot, function() return nil end, {
        findFor = 0.95, confirmFor = 2, searchAt = { x = 800, y = 0 },
    }))
    T.eq("attackAndConfirm no_target", r.reason, "no_target")
    T.near("attackAndConfirm no_target at findFor", t, 1.0)
    T.eq("attackAndConfirm no_target: moved towards searchAt every frame", bot:actionsOf("move"), 10)
    T.near("attackAndConfirm no_target: move target is searchAt", bot.actions[1] and bot.actions[1].loc.x, 800)
    T.check("attackAndConfirm no_target: actually moved", bot.loc.x > 200)
    T.eq("attackAndConfirm no_target: no attack", bot:actionsOf("attack"), 0)
end

do
    local sim = world()
    local bot = sim:addBot{ whiff = true }
    local creep = sim:addCreep{ x = 100, y = 0, passive = true }
    local r, t = run(sim, V.attackAndConfirm(bot, picker({ creep }), { findFor = 1, confirmFor = 0.95, hold = "aggro" }))
    T.eq("attackAndConfirm missed", r.reason, "missed")
    T.near("attackAndConfirm missed at confirmFor", t, 1.0)
    T.eq("attackAndConfirm missed: one order", bot:actionsOf("attack"), 1)
    T.eq("attackAndConfirm: hold on each frame waiting for the hit", #sim.holds, 9)
    T.eq("attackAndConfirm: hold tag", sim.holds[1] and sim.holds[1].tag, "aggro")
    T.near("attackAndConfirm: no hold on the order frame", sim.holds[1] and sim.holds[1].t, 0.1)
end

do
    local sim = world()
    local bot = sim:addBot{ whiff = true }
    local c1 = sim:addCreep{ x = 100, y = 0, passive = true }
    local c2 = sim:addCreep{ x = 120, y = 0, passive = true }
    sim:killAt(0.45, c1, nil)
    local r, t = run(sim, V.attackAndConfirm(bot, picker({ c1, c2 }), { findFor = 1, confirmFor = 0.95 }))
    local a = attacks(bot)
    T.eq("attackAndConfirm retarget: two orders", #a, 2)
    T.check("attackAndConfirm retarget: second order on the new target the frame after the drop",
        a[2] and a[2].target == c2 and a[2].once == true and math.abs(a[2].t - 0.6) < 1e-6)
    T.eq("attackAndConfirm retarget: still missed (attacks never land)", r.reason, "missed")
    T.near("attackAndConfirm retarget: confirm clock restarted at the new order", t, 1.6, 0.05)
end

do
    local sim = world()
    local bot = sim:addBot{ attackPoint = 0.3 }
    local c1 = sim:addCreep{ x = 100, y = 0, passive = true }
    local c2 = sim:addCreep{ x = 120, y = 0, passive = true }
    sim:at(0.05, function() c1.hidden = true end)
    local r, t = run(sim, V.attackAndConfirm(bot, picker({ c1, c2 }), { findFor = 1, confirmFor = 2 }))
    local a = attacks(bot)
    T.check("attackAndConfirm invisible target dropped and c2 ordered",
        #a == 2 and a[1].target == c1 and a[2].target == c2 and math.abs(a[2].t - 0.2) < 1e-6)
    T.eq("attackAndConfirm invisible: ok once the hit on c2 landed", r.reason, "ok")
    T.near("attackAndConfirm invisible: confirmed at c2's hit", t, 0.5)
    T.eq("attackAndConfirm invisible: hidden target never hit", c1.hp, 1000)
end

do
    local sim = world()
    local bot = sim:addBot{ whiff = true }
    local creep = sim:addCreep{ x = 100, y = 0, passive = true }
    sim:at(0.15, function() bot.alive = false end)
    local r, t = run(sim, V.attackAndConfirm(bot, picker({ creep }), { findFor = 1, confirmFor = 2 }))
    T.eq("attackAndConfirm dead", r.reason, "dead")
    T.near("attackAndConfirm dead at 0.2", t, 0.2)
end

do
    local sim = world()
    local bot = sim:addBot{}
    local creep = sim:addCreep{ x = 100, y = 0 }
    local stripped = setmetatable({}, { __index = function(_, k)
        if k == "GetLastAttackTime" then return nil end
        local v = bot[k]
        if type(v) == "function" then return function(_, ...) return v(bot, ...) end end
        return v
    end })
    local r = run(sim, V.attackAndConfirm(stripped, picker({ creep }), { findFor = 1, confirmFor = 1 }))
    T.eq("attackAndConfirm unsupported without GetLastAttackTime", r.reason, "unsupported")
    T.eq("attackAndConfirm unsupported: no order", bot:actionsOf("attack"), 0)
end

-- Composition: walkTo -> waitUntil -> attackAndConfirm adds no frame between verbs ----------

do
    local bundle = dofile("dist/tasks_test.lua")
    for _, case in ipairs({
        { name = "arrives after t", t = 1.0, arrive = 2.5, attackAt = 2.5 },
        { name = "arrives before t", t = 3.05, arrive = 2.5, attackAt = 3.1 },
    }) do
        local sim = Sim.new()
        sim:adapter(bundle)
        local bot = sim:addBot{ x = 0, y = 0, speed = 300 }
        local creep = sim:addCreep{ x = 950, y = 0, passive = true }
        local g = bundle.Testing.walkWaitAttack(bot, { x = 900, y = 0 }, case.t, picker({ creep }), 2)()
        local arrivedAt
        for _ = 1, 100 do
            if arrivedAt == nil and Sim.dist(bot.loc, { x = 900, y = 0 }) <= 150 then arrivedAt = sim.t end
            if g:next().done then break end
            sim:step(DT)
        end
        local a = attacks(bot)
        T.near("compose (" .. case.name .. "): arrival frame", arrivedAt, case.arrive)
        T.check("compose (" .. case.name .. "): attack issued at " .. case.attackAt,
            #a == 1 and math.abs(a[1].t - case.attackAt) < 1e-6)
    end
end

T.finish()
