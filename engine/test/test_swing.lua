-- lastHit/deny swing rule (slice lh-chance): `chance` against the default `expected` on the same random creep fights.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("../bots/FunLib/engine/tasks.lua")
local V = tasks.Verbs

-- The world steps at 30 fps and the bot is stepped every EVERY frames: 5 is the 0.167 s think gap of games at timescale 8.
local DT = 1 / 30
local EVERY = 5

local function run(sim, g)
    for _ = 1, 4000 do
        local r = g:next()
        if r.done then return r.value end
        for _ = 1, EVERY do sim:step(DT) end
    end
    error("did not finish", 0)
end

-- One creep fight: our hero (`slow` ranged on a 900 projectile 450-650 away, `fast` ranged on 1200-1600, or `melee`) on an
-- enemy creep of 120-320 HP that 1 to 4 of our lane creeps (a third of them ranged) hit from random phases. Skill 1.
local function trial(seed, kind, rule)
    local rnd = Sim.lcg(seed)
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(seed + 9000), skill = function() return 1 end })
    local bot, d
    if kind == "melee" then
        d = 100
        bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 55 + math.floor(rnd() * 10), attackPoint = 0.4 + rnd() * 0.15 }
    else
        d = 450 + rnd() * 200
        local speed = kind == "slow" and 900 or (1200 + rnd() * 400)
        bot = sim:addBot{ x = 0, y = 0, range = 700, damage = 45 + math.floor(rnd() * 15), attackPoint = 0.3 + rnd() * 0.2,
            projectileSpeed = speed, fireTime = true }
    end
    local creep = sim:addCreep{ x = d, y = 0, hp = 120 + math.floor(rnd() * 200), team = 3, passive = true }
    for i = 1, 1 + math.floor(rnd() * 4) do
        if rnd() < 0.35 then
            sim:addCreep{ x = d + 450, y = 50 * i, team = 2, damage = 21 + math.floor(rnd() * 5), attackPoint = 0.5,
                projectileSpeed = 900, range = 500, autoAttack = true, attackTarget = creep, firstSwingAt = rnd(), passive = true }
        else
            sim:addCreep{ x = d + 60, y = 50 * i, team = 2, damage = 19 + math.floor(rnd() * 5), attackPoint = 0.467,
                autoAttack = true, attackTarget = creep, firstSwingAt = rnd(), passive = true }
        end
    end
    return run(sim, V.lastHit(bot, { target = creep, maxWait = 12, swing = rule }))
end

local function oks(kind, rule, n)
    local ok = 0
    for seed = 1, n do if trial(seed, kind, rule).reason == "ok" then ok = ok + 1 end end
    return ok
end

do
    local n = 120
    for _, kind in ipairs({ "slow", "fast", "melee" }) do
        local e, c = oks(kind, "expected", n), oks(kind, "chance", n)
        if os.getenv("LH_DEBUG") then print(kind, "expected", e, "chance", c) end
        if kind == "fast" then
            T.check(string.format("swing %s: chance takes clearly more (%d vs %d of %d)", kind, c, e, n), c >= e + 6)
        else
            T.check(string.format("swing %s: chance takes no fewer (%d vs %d of %d)", kind, c, e, n), c >= e)
        end
    end
end

-- The chance rule logs its kill chance on the swing (`pk`); the expected rule does not.
do
    local r = trial(3, "slow", "chance")
    T.check("swing: pk on a chance swing (" .. tostring(r.message) .. ")", (r.message or ""):match(" pk=%d") ~= nil)
    local e = trial(3, "slow", nil)
    T.check("swing: no pk under the default rule", (e.message or ""):find(" pk=", 1, true) == nil)
end

-- laneFarm reads `swing` at each attempt's start and passes it to the verb.
do
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(5), skill = function() return 1 end })
    local bot = sim:addBot{ x = 0, y = 0, range = 700, damage = 50, attackPoint = 0.3, projectileSpeed = 900, fireTime = true }
    local creep = sim:addCreep{ x = 550, y = 0, hp = 200, team = 3, passive = true, maxHp = 550 }
    sim:addCreep{ x = 610, y = 50, team = 2, damage = 21, attackPoint = 0.467, autoAttack = true, attackTarget = creep,
        firstSwingAt = 0.2, passive = true }
    local msg
    local asked = 0
    local g = V.laneFarm(bot, function() return { x = 0, y = 0 } end, {
        pick = function(targets) return targets[1] end,
        swing = function() asked = asked + 1; return "chance" end,
        onAttempt = function(_, r) msg = msg or r.message end,
    })
    for _ = 1, 600 do
        if msg ~= nil then break end
        g:next()
        sim:step(1 / 30)
    end
    T.check("laneFarm swing: asked at the attempt (" .. asked .. ")", asked >= 1)
    T.check("laneFarm swing: the attempt ran the chance rule (" .. tostring(msg) .. ")", (msg or ""):match(" pk=%d") ~= nil)
end

print("swing [" .. T.runtime() .. "]")
T.finish()
