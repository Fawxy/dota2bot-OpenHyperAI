-- laneFarm: a laner holding its spot and breaking off for last hits and denies, on a small creep fight.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("../bots/FunLib/engine/tasks.lua")
local V = tasks.Verbs

local DT = 1 / 30
local SPOT = { x = -560, y = 0 }

-- Our creeps (team 2) and theirs (team 3) at the front around x = 0, each side beating on one creep of the
-- other at a time. The bot (melee, 48 dmg) waits 560 behind the front, outside the enemy creeps' rings.
local function wave(seed, skill, dmg)
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(seed), skill = skill and function() return skill end or nil,
        attackClock = function() return sim.t end })
    -- A level-1 melee hero: 1.7 s between swings, so a missed swing usually costs the creep.
    local bot = sim:addBot{ x = -560, y = 0, range = 150, damage = 48, attackPoint = 0.4, speed = 310, team = 2,
        secondsPerAttack = 1.7, cooldown = true }
    local enemies, allies = {}, {}
    for i = 1, 4 do
        enemies[i] = sim:addCreep{ x = 40, y = (i - 2.5) * 60, hp = 300, maxHp = 300, team = 3, passive = true,
            name = i == 4 and "npc_dota_creep_badguys_ranged" or "npc_dota_creep_badguys_melee" }
        allies[i] = sim:addCreep{ x = -40, y = (i - 2.5) * 60, hp = 300, maxHp = 300, team = 2, passive = true,
            name = "npc_dota_creep_goodguys_melee" }
    end
    -- Three attackers per side focus the lowest-index creep alive, re-targeting as it dies.
    local function focus(list)
        for _, c in ipairs(list) do if c.alive then return c end end
    end
    for i = 1, 3 do
        local a = sim:addCreep{ x = -40, y = 200 + i * 30, team = 2, damage = dmg or 21, attackPoint = 0.467, autoAttack = true,
            secondsPerAttack = 1, firstSwingAt = 0.31 * i, attackTarget = enemies[1], passive = true }
        local e = sim:addCreep{ x = 40, y = 200 + i * 30, team = 3, damage = dmg or 21, attackPoint = 0.467, autoAttack = true,
            secondsPerAttack = 1, firstSwingAt = 0.15 + 0.31 * i, attackTarget = allies[1], passive = true }
        sim:at(0, function()
            local tick
            tick = function(s)
                a.attackTarget = focus(enemies)
                e.attackTarget = focus(allies)
                s:at(s.t + DT, tick)
            end
            tick(sim)
        end)
    end
    return sim, bot
end

-- The caller's choice (bot code in game); here the soonest creep.
local function soonest(targets)
    local best
    for _, t in ipairs(targets) do if best == nil or t.eta < best.eta then best = t end end
    return best
end

local function farm(sim, bot, secs, opts)
    local attempts = {}
    opts = opts or {}
    if opts.pick == nil and not opts.noPick then opts.pick = soonest end
    opts.onAttempt = function(t, r, contested) attempts[#attempts + 1] = { kind = t.kind, ok = r.success, reason = r.reason } end
    local g = V.laneFarm(bot, function() return SPOT end, opts)
    for _ = 1, math.floor(secs / DT) do
        local s = g:next()
        if s.done then return s.value, attempts end
        sim:step(DT)
    end
    return nil, attempts
end

-- Skill 1: takes most enemy creeps, denies some of ours, and is back on its spot afterwards.
do
    local sim, bot = wave(11)
    local r, attempts = farm(sim, bot, 40)
    T.eq("lane: posture never ends by itself", r, nil)
    T.check("lane: 3+ of 4 last hits at skill 1 (got " .. bot.lastHits .. ")", bot.lastHits >= 3)
    T.check("lane: a deny or two (got " .. bot.denies .. ")", bot.denies >= 1)
    T.check("lane: back near the spot (" .. math.floor(Sim.dist(bot.loc, SPOT)) .. ")", Sim.dist(bot.loc, SPOT) <= 150)
    local oks = 0
    for _, a in ipairs(attempts) do if a.ok then oks = oks + 1 end end
    T.eq("lane: every credited hit was reported", oks, bot.lastHits + bot.denies)
end

-- The host switches last hits off: the bot only holds.
do
    local sim, bot = wave(11)
    local _, attempts = farm(sim, bot, 40, { lastHits = function() return false end })
    T.eq("lane off: no attempts", #attempts, 0)
    T.eq("lane off: no last hits", bot.lastHits, 0)
    T.check("lane off: stayed at the spot", Sim.dist(bot.loc, SPOT) <= 150)
end

-- No `pick`: the engine makes no choice of its own, so the bot only holds although creeps are due.
do
    local sim, bot = wave(11)
    local _, attempts = farm(sim, bot, 40, { noPick = true })
    T.eq("no pick: no attempts", #attempts, 0)
    T.eq("no pick: no last hits", bot.lastHits, 0)
end

-- Skill scales the result where the kill window is about one creep hit (35-damage hits, 48-damage hero):
-- skill 1 takes nearly every creep, skill 0.2 clearly fewer (early swings `missed`, late ones lost).
do
    local hi, lo = 0, 0
    for seed = 1, 12 do
        local s1, b1 = wave(seed, 1, 35)
        farm(s1, b1, 40)
        hi = hi + b1.lastHits
        local s2, b2 = wave(seed, 0.2, 35)
        farm(s2, b2, 40)
        lo = lo + b2.lastHits
    end
    T.check("lane skill: 1.0 takes 90%+ of 48 creeps (" .. hi .. ")", hi >= 43)
    T.check("lane skill: 0.2 takes clearly fewer (" .. lo .. " vs " .. hi .. ")", lo <= 0.85 * hi)
end


-- Between the leash (900) and `far` (1200) from the spot, a killable creep beside the bot is not picked (the
-- attempt would be dropped at once and picked again within the same resume, forever): the bot walks back.
do
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(5) })
    local bot = sim:addBot{ x = 400, y = 0, range = 150, damage = 48, attackPoint = 0.4, speed = 310, team = 2 }
    sim:addCreep{ x = 450, y = 0, hp = 40, team = 3, passive = true, name = "npc_dota_creep_badguys_melee" }
    local n = 0
    local g = V.laneFarm(bot, function() return SPOT end, { pick = soonest, onAttempt = function()
        n = n + 1
        if n > 50 then error("laneFarm spun on one creep", 0) end
    end })
    for _ = 1, 15 do g:next() sim:step(DT) end
    T.eq("leash: no attempt beyond the leash", n, 0)
    T.check("leash: walking back to the spot", bot.loc.x < 400)
end

-- `retarget`: an attempt whose creep loses its attackers (no longer offered) is dropped for the creep `pick` chooses
-- next; without it the attempt waits out its maxWait while that creep becomes due elsewhere.
local function stall(retarget)
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(7), skill = function() return 1 end, attackClock = function() return sim.t end })
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 48, attackPoint = 0.4, speed = 310, team = 2 }
    local a = sim:addCreep{ x = 100, y = 0, hp = 81, maxHp = 300, team = 3, passive = true, name = "npc_dota_creep_badguys_melee" }
    local b = sim:addCreep{ x = 100, y = 60, hp = 200, maxHp = 300, team = 3, passive = true, name = "npc_dota_creep_badguys_melee" }
    local first = sim:addCreep{ x = 0, y = 200, team = 2, damage = 21, attackPoint = 0.467, autoAttack = true, secondsPerAttack = 1,
        firstSwingAt = 0, attackTarget = a, passive = true }
    for i = 1, 3 do
        sim:addCreep{ x = 0, y = 200 + i * 30, team = 2, damage = 21, attackPoint = 0.467, autoAttack = true, secondsPerAttack = 1,
            firstSwingAt = 0.2 * i, attackTarget = b, passive = true }
    end
    sim:at(0.6, function() first.attackTarget = b end)
    local attempts = {}
    local g = V.laneFarm(bot, function() return { x = 0, y = 0 } end, { pick = soonest, retarget = retarget,
        onAttempt = function(t, r) attempts[#attempts + 1] = { creep = t.creep, reason = r.reason, msg = r.message } end })
    for _ = 1, math.floor(4 / DT) do g:next() sim:step(DT) end
    return attempts, a, b, bot
end
do
    local attempts, a, b, bot = stall(true)
    T.eq("retarget: first attempt on the stalled creep", attempts[1] and attempts[1].creep, a)
    T.eq("retarget: dropped as interrupted", attempts[1] and attempts[1].reason, "interrupted")
    T.check("retarget: marked sw=1 (" .. tostring(attempts[1] and attempts[1].msg) .. ")", attempts[1] ~= nil and attempts[1].msg:find("sw=1") ~= nil)
    T.eq("retarget: next attempt on the creep now due", attempts[2] and attempts[2].creep, b)
    T.eq("retarget: and it lands", attempts[2] and attempts[2].reason, "ok")
    local off = stall(false)
    T.eq("no retarget: the stalled attempt waits out its maxWait", off[1] and off[1].reason, "timeout")
end

-- Death ends it; interruptIf ends it.
do
    local sim, bot = wave(3)
    sim:at(2, function(s) s:kill(bot) end)
    local r = farm(sim, bot, 5)
    T.eq("lane: dead", r and r.reason, "dead")
    local sim2, bot2 = wave(3)
    local stop = false
    sim2:at(1, function() stop = true end)
    local r2 = farm(sim2, bot2, 5, { interruptIf = function() return stop end })
    T.eq("lane: interrupted", r2 and r2.reason, "interrupted")
end

print("laneFarm [" .. T.runtime() .. "]")
T.finish()
