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

-- While an attempt waits on a creep that is still offered, `pick` is asked with it as `current` every scan and may leave
-- it. Creep a (100 HP, three allies on it from the start, their first hits at 0.9, 1.6 and 1.7) is offered at 0.8 s from
-- killable; creep b (70 HP) gets one fast ally at 0.5 whose 25-damage hits at 0.6, 1.2 and 1.8 make it killable now at 0.6
-- and dead at 1.8. A pick that leaves a creep still 0.5 s from due for one due now takes b (landing at 1.0) and then a
-- (due about 1.3, landing about 1.8). A pick that keeps `current` while it is offered (the old behaviour) takes a at
-- about 1.7 and b dies at 1.8 untaken: it is reported by the body's idle-in-range count, not by any attempt.
do
    local function twoWaves(pick)
        local sim = Sim.new()
        sim:adapter(tasks, { random = Sim.lcg(5) })
        local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 48, attackPoint = 0.4, speed = 310, team = 2 }
        local a = sim:addCreep{ x = 100, y = 0, hp = 100, maxHp = 300, team = 3, passive = true, name = "npc_dota_creep_badguys_melee" }
        local b = sim:addCreep{ x = 100, y = 60, hp = 70, maxHp = 300, team = 3, passive = true, name = "npc_dota_creep_badguys_melee" }
        for _, first in ipairs({ 0.433, 1.133, 1.233 }) do
            sim:addCreep{ x = 0, y = 200, team = 2, damage = 21, attackPoint = 0.467, autoAttack = true, secondsPerAttack = 1,
                firstSwingAt = first, attackTarget = a, passive = true }
        end
        -- Its target is set at 0.5: an attacker already targeting b would count in b's DPS from the start.
        local fast = sim:addCreep{ x = 0, y = 260, team = 2, damage = 25, attackPoint = 0.1, autoAttack = true, secondsPerAttack = 0.6,
            firstSwingAt = 0.5, passive = true }
        sim:at(0.5, function() fast.attackTarget = b end)
        local attempts = {}
        local g = V.laneFarm(bot, function() return { x = 0, y = 0 } end, { pick = pick, retarget = true,
            onAttempt = function(t, r) attempts[#attempts + 1] = { creep = t.creep, reason = r.reason, msg = r.message, at = sim.t } end })
        for _ = 1, math.floor(3 / DT) do g:next() sim:step(DT) end
        return attempts, a, b
    end
    local function switching(targets, current)
        local best = soonest(targets)
        if current == nil then return best end
        local cur
        for _, t in ipairs(targets) do if t.creep == current.creep then cur = t end end
        if best.creep ~= cur.creep and best.eta <= 0.2 and cur.eta >= 0.5 then return best end
        return cur
    end
    local function keeping(targets, current)
        if current == nil then return soonest(targets) end
        for _, t in ipairs(targets) do if t.creep == current.creep then return t end end
        return soonest(targets)
    end
    local sw, a, b = twoWaves(switching)
    T.eq("switch: first attempt on the creep offered first", sw[1] and sw[1].creep, a)
    T.check("switch: left it for the creep due now (sw=1, " .. tostring(sw[1] and sw[1].msg) .. ")",
        sw[1] ~= nil and sw[1].reason == "interrupted" and sw[1].msg:find("sw=1") ~= nil)
    T.eq("switch: took the creep due now", sw[2] and sw[2].creep, b)
    T.eq("switch: and it landed", sw[2] and sw[2].reason, "ok")
    T.eq("switch: back on the first creep", sw[3] and sw[3].creep, a)
    local kp, a2, b2 = twoWaves(keeping)
    T.check("keep: a pick that stays on its creep is never moved off it (" .. tostring(kp[1] and kp[1].reason) .. ")",
        kp[1] ~= nil and kp[1].creep == a2 and kp[1].reason == "ok")
    T.check("keep: and the creep due meanwhile died untaken", not b2.alive and (kp[2] == nil or kp[2].reason ~= "ok"))
end

-- `dropLost`: an attempt waiting in range for a creep that the others will now kill before a swing ordered now lands (no
-- longer offered) is dropped at once (`sw=0`) when `pick` has nothing else; without it the attempt waits until the creep is
-- taken.
local function doomed(dropLost)
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(9), skill = function() return 1 end, attackClock = function() return sim.t end })
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 48, attackPoint = 0.4, speed = 310, team = 2 }
    local a = sim:addCreep{ x = 100, y = 0, hp = 75, maxHp = 300, team = 3, passive = true, name = "npc_dota_creep_badguys_melee" }
    sim:addCreep{ x = 0, y = 200, team = 2, damage = 20, attackPoint = 0.467, autoAttack = true, secondsPerAttack = 1,
        firstSwingAt = 0, attackTarget = a, passive = true }
    for i = 1, 4 do
        sim:addCreep{ x = 0, y = 200 + i * 30, team = 2, damage = 40, attackPoint = 0.467, autoAttack = true, secondsPerAttack = 1,
            firstSwingAt = 0.3, attackTarget = a, passive = true }
    end
    local attempts = {}
    local g = V.laneFarm(bot, function() return { x = 0, y = 0 } end, { pick = soonest, retarget = true, dropLost = dropLost,
        onAttempt = function(t, r) attempts[#attempts + 1] = { creep = t.creep, reason = r.reason, msg = r.message, at = sim.t } end })
    for _ = 1, math.floor(2 / DT) do g:next() sim:step(DT) end
    return attempts, a
end
do
    local on, a = doomed(true)
    T.eq("dropLost: first attempt on the creep", on[1] and on[1].creep, a)
    T.eq("dropLost: dropped as interrupted", on[1] and on[1].reason, "interrupted")
    T.check("dropLost: marked sw=0 (" .. tostring(on[1] and on[1].msg) .. ")", on[1] ~= nil and on[1].msg:find("sw=0") ~= nil)
    T.check("dropLost: dropped before the others' hits land (" .. tostring(on[1] and on[1].at) .. ")", on[1] ~= nil and on[1].at < 0.3 + 0.467)
    local off = doomed(false)
    T.eq("no dropLost: the attempt waits until the creep is taken", off[1] and off[1].reason, "taken_by_other")
end

-- Slice support-lane-hits: a pick that stops answering the creep it waits on while that creep is still offered (a support
-- whose core came for it) releases it with `dropLost` (sw=0, before the swing); without `dropLost` undefined keeps the wait.
local function released(dropLost)
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(9), skill = function() return 1 end, attackClock = function() return sim.t end })
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 48, attackPoint = 0.4, speed = 310, team = 2 }
    -- Not killable yet and nothing else hitting it: offered for the whole run, so only the pick's answer can end the wait.
    local a = sim:addCreep{ x = 100, y = 0, hp = 200, maxHp = 300, team = 3, passive = true, name = "npc_dota_creep_badguys_melee" }
    sim:addCreep{ x = 0, y = 200, team = 2, damage = 30, attackPoint = 0.467, autoAttack = true, secondsPerAttack = 1,
        firstSwingAt = 0, attackTarget = a, passive = true }
    local mine = true
    local pick = function(targets, current)
        if not mine then return nil end
        return soonest(targets)
    end
    local attempts, lastLabel = {}, nil
    local g = V.laneFarm(bot, function() return { x = 0, y = 0 } end, { pick = pick, retarget = true, dropLost = dropLost, within = 5,
        label = function(l) lastLabel = l end,
        onAttempt = function(t, r) attempts[#attempts + 1] = { creep = t.creep, reason = r.reason, msg = r.message, at = sim.t } end })
    for _ = 1, math.floor(0.5 / DT) do g:next() sim:step(DT) end
    mine = false
    for _ = 1, math.floor(0.5 / DT) do g:next() sim:step(DT) end
    return attempts, a, lastLabel
end
do
    local on, a = released(true)
    T.eq("released: the attempt was on the creep", on[1] and on[1].creep, a)
    T.check("released, dropLost: ended sw=0 once the pick stopped answering it (" .. tostring(on[1] and on[1].msg) .. ")",
        on[1] ~= nil and on[1].reason == "interrupted" and on[1].msg:find("sw=0") ~= nil and on[1].at < 0.5 + 0.3)
    local off, _, label = released(false)
    T.check("released, no dropLost: undefined keeps the wait (still in the attempt, none ended)", off[1] == nil and label == "lasthit", label)
end

-- A gap in the steps: the host stops stepping laneFarm for 25 s (the bot in another mode, a job for one) with an attempt open.
-- The next step ends that attempt, by its clock or because the creep is gone; the old attempt is never resumed.
local function gapped(keepAttackers)
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(9), skill = function() return 1 end, attackClock = function() return sim.t end })
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 48, attackPoint = 0.4, speed = 310, team = 2 }
    local a = sim:addCreep{ x = 100, y = 0, hp = 75, maxHp = 300, team = 3, passive = true, name = "npc_dota_creep_badguys_melee" }
    local others = {}
    for i = 1, 5 do
        others[i] = sim:addCreep{ x = 0, y = 200 + i * 30, team = 2, damage = 20, attackPoint = 0.467, autoAttack = true,
            secondsPerAttack = 1, firstSwingAt = 0.3, attackTarget = a, passive = true }
    end
    local attempts = {}
    local g = V.laneFarm(bot, function() return { x = 0, y = 0 } end, { pick = soonest,
        onAttempt = function(t, r) attempts[#attempts + 1] = { creep = t.creep, reason = r.reason, at = sim.t } end })
    -- 0.2 s in: the attempt is open, waiting for the others' first hits (0.3 s + 0.467 s).
    while sim.t < 0.2 do g:next() sim:step(DT) end
    local before = #attempts
    if not keepAttackers then for _, o in ipairs(others) do sim:kill(o) end end
    local gapEnd = sim.t + 25
    while sim.t < gapEnd do sim:step(DT) end
    g:next()
    return attempts, before, gapEnd, a
end
do
    local kept, before, gapEnd = gapped(true)
    T.eq("gap, creep killed meanwhile: no attempt ended before the gap", before, 0)
    T.check("gap, creep killed meanwhile: the first step after it ends the attempt (" .. tostring(kept[1] and kept[1].reason) .. ")",
        kept[1] ~= nil and kept[1].reason ~= "ok" and kept[1].at >= gapEnd)
    local alive, before2, gapEnd2, a = gapped(false)
    T.eq("gap, creep alive: no attempt ended before the gap", before2, 0)
    T.check("gap, creep alive: the attempt was open on the creep", alive[1] ~= nil and alive[1].creep == a)
    T.eq("gap, creep alive: ended by its clock on the first step after it", alive[1] and alive[1].reason, "timeout")
    T.check("gap, creep alive: at that step", alive[1] ~= nil and alive[1].at >= gapEnd2)
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
