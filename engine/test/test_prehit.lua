-- hpForecast (a creep's HP from the hits the attacker index sees), and laneFarm carrying out a caller's `prehit` pick.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("../bots/FunLib/engine/tasks.lua")
local V = tasks.Verbs

local DT = 1 / 30

-- Our tower (team 2) 700 from an enemy creep, hitting it every second for 100 with a 750-speed projectile; our melee
-- creep beside the enemy creep hits it for 20 every second. secondsPerAttack is 1 for both, so the sim's wind-up reading
-- ((attackPoint - cycle) * secondsPerAttack) is the real time left.
local function towerScene(o)
    o = o or {}
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(7), attackClock = function() return sim.t end })
    local bot = sim:addBot{ x = -100, y = 0, range = 150, damage = 40, attackPoint = 0.4, speed = 300, team = 2,
        secondsPerAttack = 1.5, cooldown = true }
    local creep = sim:addCreep{ x = 0, y = 0, hp = o.hp or 550, maxHp = 550, team = 3, passive = true,
        name = "npc_dota_creep_badguys_melee" }
    local tower = sim:addTower{ x = -700, y = 0, team = 2, damage = 100, range = 700, attackPoint = 0.3, projectileSpeed = 750,
        autoAttack = true, secondsPerAttack = 1, firstSwingAt = o.towerFirst or 0, attackTarget = creep, passive = true }
    local ally
    if not o.noCreep then
        ally = sim:addCreep{ x = 60, y = 60, team = 2, damage = 20, attackPoint = 0.467, autoAttack = true, secondsPerAttack = 1,
            firstSwingAt = 0.2, attackTarget = creep, passive = true }
    end
    return sim, bot, creep, tower, ally
end

-- The forecast agrees with the HP the sim then shows: read it once the tower's first projectile is in flight and the
-- creep is winding up, and compare its HP at each later step over 2.5 s (until it dies).
do
    local sim, bot, creep = towerScene()
    while sim.t < 0.5 do sim:step(DT) end
    local f = V.hpForecast(bot, creep, 3)
    T.check("forecast: hits known (" .. #f.hits .. ")", #f.hits >= 4)
    T.eq("forecast: nothing unphased with the tower and creep both seen", f.unphased, 0)
    local t0, worst = sim.t, 0
    while sim.t < t0 + 2.5 and creep.alive do
        sim:step(DT)
        -- Within one frame of a hit the step can land on either side of it: compare between hits only.
        local tf = sim.t - t0
        local near = false
        for _, h in ipairs(f.hits) do if math.abs(h.t - tf) < 1.5 * DT then near = true end end
        if not near then worst = math.max(worst, math.abs(V.forecastHp(f, tf) - creep.hp)) end
    end
    T.check("forecast: HP within 1 of the sim's between hits (worst " .. worst .. ")", worst <= 1)
end

-- Kinds, and repeats only for periodic attackers: the tower's hits carry `tower`, the creep's `creep`.
do
    local sim, bot, creep = towerScene()
    while sim.t < 0.5 do sim:step(DT) end
    local f = V.hpForecast(bot, creep, 3)
    local towerHits, creepHits = 0, 0
    for _, h in ipairs(f.hits) do
        if h.by == "tower" then towerHits = towerHits + 1 elseif h.by == "creep" then creepHits = creepHits + 1 end
    end
    T.check("forecast: three tower hits in 3 s (" .. towerHits .. ")", towerHits == 3)
    T.check("forecast: three creep hits in 3 s (" .. creepHits .. ")", creepHits == 3)
    for i = 2, #f.hits do T.check("forecast: hits sorted", f.hits[i - 1].t <= f.hits[i].t) end
end

-- A tower on the creep with no hit in flight or wind-up yet: its phase is unknown, so the forecast says so.
do
    local sim, bot, creep = towerScene({ towerFirst = 0.6, noCreep = true })
    sim:step(DT)
    local f = V.hpForecast(bot, creep, 3)
    T.check("forecast: unphased tower flagged", f.unphasedTower)
    T.eq("forecast: no known hits", #f.hits, 0)
    T.near("forecast: its DPS spread past 0.45 s", V.forecastHp(f, 1.45), f.hp - 100, 1e-6)
end

-- An attacker with no hit in flight or wind-up (unknown phase): the sim's HP stays between the `late` and `early` schedules
-- (its next hit lands no sooner than one wind-up and no later than one cycle, plus flight, from now).
do
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(9) })
    local bot = sim:addBot{ x = -100, y = 0, range = 150, damage = 40, attackPoint = 0.4, team = 2 }
    local creep = sim:addCreep{ x = 0, y = 0, hp = 300, team = 3, passive = true }
    sim:addCreep{ x = 60, y = 0, team = 2, damage = 20, attackPoint = 0.467, autoAttack = true, secondsPerAttack = 1,
        firstSwingAt = 0.5, attackTarget = creep, passive = true }
    sim:step(DT)
    local f = V.hpForecast(bot, creep, 3)
    T.eq("schedules: one unphased attacker listed", #f.unphasedHits, 1)
    local t0, inside, n = sim.t, true, 0
    while sim.t < t0 + 2.9 do
        sim:step(DT)
        local tf = sim.t - t0
        local lo, hi = V.forecastHp(f, tf, "early"), V.forecastHp(f, tf, "late")
        if not (creep.hp >= lo - 1e-6 and creep.hp <= hi + 1e-6) then inside = false end
        n = n + 1
    end
    T.check("schedules: the sim's HP within [early, late] at every step (" .. n .. " steps)", inside)
    -- Exact bounds (review 6ed766b F3): `early` lands at one wind-up (0.467 s), `late` at one cycle (1 s); the real landing
    -- (0.933 s from the forecast) lies between.
    local u = f.unphasedHits[1]
    T.near("schedules: first is one wind-up", u.first, 0.467, 1e-9)
    T.near("schedules: last is one cycle", u.last, 1.0, 1e-9)
    T.eq("schedules: early untouched just before first", V.forecastHp(f, u.first - 0.01, "early"), 300)
    T.eq("schedules: early hit at first", V.forecastHp(f, u.first, "early"), 280)
    T.eq("schedules: late untouched just before last", V.forecastHp(f, u.last - 0.01, "late"), 300)
    T.eq("schedules: late hit at last", V.forecastHp(f, u.last, "late"), 280)
end

-- The bot's own projectile in flight counts (a pre-hit it already fired).
do
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(3) })
    local bot = sim:addBot{ x = 0, y = 0, range = 500, damage = 40, attackPoint = 0.1, projectileSpeed = 900, team = 2 }
    local creep = sim:addCreep{ x = 450, y = 0, hp = 300, team = 3, passive = true }
    bot:Action_AttackUnit(creep, true)
    for _ = 1, 5 do sim:step(DT) end
    local f = V.hpForecast(bot, creep, 2)
    T.check("forecast: own projectile is a `self` hit", #f.hits == 1 and f.hits[1].by == "self")
end

-- attackAndConfirm with aggroConfirms = false: a target already attacking the bot does not confirm an attack that never fires.
do
    local function run(aggro)
        local sim = Sim.new()
        sim:adapter(tasks, { random = Sim.lcg(3) })
        local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 40, attackPoint = 0.3, whiff = true, team = 2 }
        local creep = sim:addCreep{ x = 100, y = 0, hp = 300, team = 3, passive = true }
        creep.attackTarget = bot
        local g = V.attackAndConfirm(bot, function() return creep end, { findFor = 0, confirmFor = 1, aggroConfirms = aggro })
        for _ = 1, 60 do
            local s = g:next()
            if s.done then return s.value end
            sim:step(DT)
        end
    end
    T.eq("aggro confirms by default", run(nil).reason, "ok")
    T.eq("aggroConfirms=false: an attack that never fires is missed", run(false).reason, "missed")
end

-- laneFarm: `pick` is asked with nothing offered, and a `prehit` it returns is one attack on the creep, after which the
-- verb scans again; the attempt reports kind prehit, ok once the attack fired.
do
    local sim, bot, creep = towerScene({ hp = 2000 })
    local emptyAsks, preDone = 0, false
    local attempts = {}
    local g = V.laneFarm(bot, function() return { x = -100, y = 0 } end, {
        pick = function(targets)
            if #targets == 0 then emptyAsks = emptyAsks + 1 end
            if preDone then return nil end
            return { creep = creep, kind = "prehit", eta = 0, due = 0, walk = 0, dies = 99, ranged = false }
        end,
        onAttempt = function(t, r) attempts[#attempts + 1] = { kind = t.kind, reason = r.reason }; preDone = true end,
    })
    local hp0 = creep.hp
    for _ = 1, 90 do g:next() sim:step(DT) end
    T.check("prehit: pick asked with nothing offered (" .. emptyAsks .. ")", emptyAsks >= 1)
    T.eq("prehit: one attempt", #attempts, 1)
    T.eq("prehit: kind", attempts[1] and attempts[1].kind, "prehit")
    T.eq("prehit: confirmed by the attack firing", attempts[1] and attempts[1].reason, "ok")
    T.eq("prehit: one attack order", bot:actionsOf("attack"), 1)
    T.check("prehit: the bot's hit landed", hp0 - creep.hp >= 40)
end

-- The pre-hit's attack order is cancelled after the attempt. As in Dota, the sim's `keepAttacking` bot swings at its target
-- again every attack cycle until another order comes; the last-hit wait that follows the pre-hit (pick answers a `lasthit` on
-- the same creep, never due at 2000 HP) gives no order of its own, so without the cancel the bot hits a second time at 1.5 s
-- (prhchk5, 04/11/2026). Only the bot damages the creep here (the tower stands by).
do
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(7), attackClock = function() return sim.t end })
    local bot = sim:addBot{ x = -100, y = 0, range = 150, damage = 40, attackPoint = 0.4, speed = 300, team = 2,
        secondsPerAttack = 1.5, cooldown = true, keepAttacking = true }
    local creep = sim:addCreep{ x = 0, y = 0, hp = 2000, maxHp = 2000, team = 3, passive = true, name = "npc_dota_creep_badguys_melee" }
    sim:addTower{ x = -700, y = 0, team = 2, damage = 100, range = 700, attackPoint = 0.3, projectileSpeed = 750,
        secondsPerAttack = 1, attackTarget = creep, passive = true }
    local preDone = false
    local g = V.laneFarm(bot, function() return { x = -100, y = 0 } end, {
        retarget = true,
        pick = function()
            if preDone then return { creep = creep, kind = "lasthit", eta = 0, due = 0, walk = 0, dies = 99, ranged = false } end
            return { creep = creep, kind = "prehit", eta = 0, due = 0, walk = 0, dies = 99, ranged = false }
        end,
        onAttempt = function(t) if t.kind == "prehit" then preDone = true end end,
    })
    for _ = 1, 100 do g:next() sim:step(DT) end
    T.eq("prehit cancel: one attack order", bot:actionsOf("attack"), 1)
    T.eq("prehit cancel: exactly one hit of the bot's in 3.3 s (the standing order did not swing again)", 2000 - creep.hp, 40)
end

-- The sim's standing order itself: without the cancel a keepAttacking bot hits again one attack cycle later.
do
    local sim = Sim.new()
    sim:adapter(tasks, { random = Sim.lcg(7), attackClock = function() return sim.t end })
    local bot = sim:addBot{ x = -100, y = 0, range = 150, damage = 40, attackPoint = 0.4, team = 2, secondsPerAttack = 1.5,
        cooldown = true, keepAttacking = true }
    local creep = sim:addCreep{ x = 0, y = 0, hp = 2000, team = 3, passive = true }
    bot:Action_AttackUnit(creep, true)
    for _ = 1, 100 do sim:step(DT) end
    T.eq("sim keepAttacking: two hits from one order in 3.3 s", 2000 - creep.hp, 80)
end

-- The forecast and the belief read an attacker's phase from the same place: a tower projectile landing past a short horizon
-- still phases the tower for both (review 2026-11-05-sdk-slice-prehit F2: the forecast called it unphased, the belief not).
do
    local sim, bot, creep = towerScene({ noCreep = true })
    while sim.t < 0.5 do sim:step(DT) end
    local f = V.hpForecast(bot, creep, 0.5)
    T.check("short horizon: the tower is phased by its projectile beyond it", not f.unphasedTower and f.unphased == 0)
    T.eq("short horizon: no hit inside 0.5 s", #f.hits, 0)
    T.eq("short horizon: the belief agrees (nothing between swings)", V.incomingDps(bot, creep).between, 0)
end

-- A tower whose projectile is in flight has a known phase: the last-hit belief counts that hit and its repeat one cycle
-- later within the horizon, and no longer spreads the tower's rate past 0.45 s on top of them (a ranged core under its own
-- tower read 30-45 HP heavy and swung early, slice pre-hit 05/11/2026).
do
    local sim, bot, creep = towerScene({ noCreep = true })
    while sim.t < 0.5 do sim:step(DT) end
    local d = V.incomingDps(bot, creep)
    T.near("phased tower: its rate stays in dps", d.dps, 100, 1e-6)
    T.eq("phased tower: nothing between swings while its projectile flies", d.between, 0)
    -- The projectile lands at 0.3 + 700/750 = 1.23 s from its swing, the next one a cycle later: both inside 2.5 s from now.
    T.eq("phased tower: the hit in flight and its repeat within the horizon", V.incomingDamage(bot, creep, 2.5), 200)
    T.eq("phased tower: only the hit in flight within a shorter horizon", V.incomingDamage(bot, creep, 1.0), 100)
end

-- retarget: a `prehit` on the creep a last-hit attempt waits for replaces that attempt (sw=1), although the creep is the same.
do
    local sim, bot, creep = towerScene({ hp = 2000 })
    local attempts = {}
    local g = V.laneFarm(bot, function() return { x = -100, y = 0 } end, {
        retarget = true,
        within = 30,
        pick = function(targets, current)
            if #attempts > 0 then return nil end
            if current ~= nil then
                return { creep = creep, kind = "prehit", eta = 0, due = 0, walk = 0, dies = 99, ranged = false }
            end
            return targets[1]
        end,
        onAttempt = function(t, r) attempts[#attempts + 1] = { kind = t.kind, reason = r.reason, msg = r.message } end,
    })
    for _ = 1, 60 do g:next() sim:step(DT) end
    T.check("retarget prehit: the last-hit wait ended for it", attempts[1] ~= nil and attempts[1].kind == "lasthit"
        and attempts[1].reason == "interrupted" and string.find(attempts[1].msg or "", "sw=1", 1, true) ~= nil)
    T.eq("retarget prehit: then the prehit", attempts[2] and attempts[2].kind, "prehit")
end

print("prehit [" .. T.runtime() .. "]")
T.finish()
