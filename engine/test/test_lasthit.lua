-- lastHit v2 and deny: incoming-damage prediction, own hit time, skill-scaled timing error.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("../bots/FunLib/engine/tasks.lua")
local V = tasks.Verbs

-- About 30 frames per second, as in game: the swing decision is only as fine as the frame.
local DT = 1 / 30

local function run(sim, g, maxFrames, dt)
    for _ = 1, maxFrames or 3000 do
        local r = g:next()
        if r.done then return r.value, sim.t end
        sim:step(dt or DT)
    end
    error("generator did not finish", 0)
end

local function world(opts)
    local sim = Sim.new()
    opts = opts or {}
    opts.random = opts.random or Sim.lcg(opts.seed or 7)
    sim:adapter(tasks, opts)
    return sim
end

local function firstSwing(bot)
    for _, a in ipairs(bot.actions) do if a.kind == "attack" then return a end end
end

-- Three allied melee creeps hit the enemy creep at 1.0, 1.2 and 1.4 (80 -> 50 -> 20 -> dead). The swing must
-- start before the 1.2 hit so it lands at 20 hp before the 1.4 hit takes the creep: waiting until hp <= our
-- damage (at 1.2) is too late with a 0.5 s attack point.
local function contested(sim, offset)
    offset = offset or 0
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.5 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 80, team = 3 }
    for i, first in ipairs({ 0.533, 0.733, 0.933 }) do
        sim:addCreep{ x = 120, y = 40 * i, team = 2, damage = 30, attackPoint = 0.467, autoAttack = true,
            attackTarget = creep, firstSwingAt = first + offset }
    end
    return bot, creep
end

do
    local sim = world()
    local bot, creep = contested(sim)
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 5 }))
    T.eq("predict melee: ok", r.reason, "ok")
    T.eq("predict melee: last hit credited", bot.lastHits, 1)
    local swing = firstSwing(bot)
    T.check("predict melee: swung before hp reached our damage", swing and swing.targetHp > 45)
    T.eq("predict melee: one swing", bot:actionsOf("attack"), 1)
end


-- Our own creeps out of the enemy's sight (CanBeSeen is "visible to the enemy team") still count: the same
-- contested creep with the allied attackers hidden from the enemy is led exactly as before.
do
    local sim = world()
    local bot, creep = contested(sim)
    for _, u in ipairs(sim.units) do if u.kind == "creep" and u.team == 2 then u.hidden = true end end
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 5 }))
    T.eq("hidden allies: ok", r.reason, "ok")
    local swing = firstSwing(bot)
    T.check("hidden allies: still led the swing", swing and swing.targetHp > 45)
end


-- A creep that walks into the fog mid-attempt (alive, valid handle, no location) ends the attempt cleanly as
-- lost, and is never offered by laneTargets; it must not raise an error.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.5 }
    local creep = sim:addCreep{ x = 400, y = 0, hp = 300, team = 3, drain = 50, passive = true }
    sim:at(0.3, function() creep.fogged = true end)
    local ok, r = pcall(run, sim, V.lastHit(bot, { target = creep, maxWait = 3 }))
    T.check("fogged target: no error", ok, tostring(r))
    T.eq("fogged target: lost", ok and r.reason, "taken_by_other")
    local s2 = world()
    local b2 = s2:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.5 }
    s2:addCreep{ x = 100, y = 0, hp = 40, team = 3, passive = true, fogged = true }
    local ok2, t2 = pcall(V.laneTargets, b2)
    T.check("fogged creep: laneTargets no error and nothing offered", ok2 and #t2 == 0, tostring(t2))
end


-- Damage spread: with 50 +- 5 the bot swings only at creeps its lowest roll kills (45), not on the average.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 50, variance = 5, attackPoint = 0.3 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 48, team = 3, passive = true }
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 1 }))
    T.eq("variance: no swing on a creep only the average roll kills", r.reason, "timeout")
    local s2 = world()
    local b2 = s2:addBot{ x = 0, y = 0, range = 150, damage = 50, attackPoint = 0.3 }
    local c2 = s2:addCreep{ x = 100, y = 0, hp = 48, team = 3, passive = true }
    T.eq("variance: without a spread the same creep is taken", run(s2, V.lastHit(b2, { target = c2, maxWait = 1 })).reason, "ok")
end

-- Turning: a bot facing away (180 deg) needs about 0.15 s more, so it swings earlier on a draining creep.
do
    local function swingHp(facing)
        local sim = world()
        local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 50, attackPoint = 0.3, facing = facing }
        local creep = sim:addCreep{ x = 100, y = 0, hp = 200, drain = 200, team = 3, passive = true }
        run(sim, V.lastHit(bot, { target = creep, maxWait = 3 }))
        return firstSwing(bot).targetHp
    end
    local facing, away = swingHp(0), swingHp(180)
    T.check("turn: facing away swings earlier (" .. facing .. " vs " .. away .. ")", away > facing + 15)
end


-- Long horizon: a ranged hero 550 away (0.3 s wind-up + 0.57 s flight) on a creep three allied creeps keep
-- hitting for 35 every ~0.33 s. Hits not yet wound up when it decides still land before its projectile, so a
-- prediction from visible wind-ups alone swings late and loses most creeps; extrapolating the attackers' DPS
-- over the horizon takes them.
do
    local ok = 0
    for seed = 1, 10 do
        local sim = world({ seed = seed })
        local bot = sim:addBot{ x = 0, y = 0, range = 600, damage = 50, attackPoint = 0.3, projectileSpeed = 900, fireTime = true }
        local creep = sim:addCreep{ x = 550, y = 0, hp = 300 + 7 * seed, team = 3, passive = true }
        for i = 1, 3 do
            sim:addCreep{ x = 600, y = 40 * i, team = 2, damage = 35, attackPoint = 0.467, autoAttack = true,
                attackTarget = creep, firstSwingAt = 0.11 * seed + 0.33 * i, passive = true }
        end
        local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 8 }))
        if r.reason == "ok" then ok = ok + 1 elseif DEBUG_LH then print(seed, r.reason, r.message) end
    end
    T.check("long horizon: ranged hero takes 8+/10 contested creeps (" .. ok .. ")", ok >= 8)
end

-- An allied projectile already in flight will kill the creep before any swing of ours could land: no swing.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.5 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 20, team = 3, passive = true }
    sim:addCreep{ x = 300, y = 0, team = 2, damage = 25, attackPoint = 0.1, projectileSpeed = 900, range = 500,
        autoAttack = true, attackTarget = creep, firstSwingAt = 0 }
    sim:step(0.12)
    sim:step(DT) -- launched at 0.1: in flight, about 0.2 s from landing
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 3 }))
    T.eq("in-flight projectile kills first: taken_by_other", r.reason, "taken_by_other")
    T.eq("in-flight projectile kills first: no swing", bot:actionsOf("attack"), 0)
end

-- An allied tower winding up on a 40 hp creep (killable by us) will kill it first: no swing.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.5 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 40, team = 3, passive = true }
    sim:addTower{ x = 600, y = 0, team = 2, damage = 100, attackPoint = 0.3, autoAttack = true,
        attackTarget = creep, firstSwingAt = 0 }
    sim:step(0.05)
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 3 }))
    T.eq("tower wind-up kills first: taken_by_other", r.reason, "taken_by_other")
    T.eq("tower wind-up kills first: no swing", bot:actionsOf("attack"), 0)
    -- In-game attribution: a creep lost before any swing says what held the swing back on the last frame.
    T.check("tower wind-up kills first: message says it was waiting on the kill belief", (r.message or ""):find("why=wait", 1, true) ~= nil, tostring(r.message))
end

-- A creep out of range that dies while the bot walks in: the message says `range`, with how far it still had to go.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.5, speed = 100 }
    local creep = sim:addCreep{ x = 900, y = 0, hp = 40, team = 3, passive = true }
    sim:at(0.3, function(w) w:kill(creep) end)
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 3 }))
    T.eq("lost while walking in: taken_by_other", r.reason, "taken_by_other")
    T.check("lost while walking in: why=range with the distance left", (r.message or ""):match("why=range d=%d+") ~= nil, tostring(r.message))
end

-- A tower shot winding up on a 130 hp creep leaves 30: the swing is ordered before the shot lands.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.5 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 130, team = 3, passive = true }
    sim:addTower{ x = 600, y = 0, team = 2, damage = 100, attackPoint = 0.3, autoAttack = true,
        attackTarget = creep, firstSwingAt = 0 }
    sim:step(0.05)
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 3 }))
    T.eq("tower shot counted: ok", r.reason, "ok")
    local swing = firstSwing(bot)
    T.check("tower shot counted: swung before the shot landed", swing and swing.targetHp == 130)
end

-- A ranged hero leads the swing by its projectile travel time against a creep losing 50 hp/s.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 500, damage = 50, attackPoint = 0.3, projectileSpeed = 900 }
    local creep = sim:addCreep{ x = 450, y = 0, hp = 200, drain = 50, team = 3, passive = true }
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 5 }))
    T.eq("ranged lead: ok", r.reason, "ok")
    local swing = firstSwing(bot)
    -- Own hit time 0.3 + (450 - 39) / 900 = 0.76 s, i.e. 38 hp of drain: fire at about 88 hp, not at 50.
    T.check("ranged lead: swung at about 88 hp (got " .. tostring(swing and swing.targetHp) .. ")",
        swing and swing.targetHp > 80 and swing.targetHp <= 90)
end


-- Dota stamps a ranged hero's last-attack time when the projectile leaves, not when it lands: the swing is
-- still in flight then, and must be credited ok when it kills, not called `missed` on the launch frame.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 600, damage = 50, attackPoint = 0.3, projectileSpeed = 900, fireTime = true }
    local creep = sim:addCreep{ x = 550, y = 0, hp = 200, drain = 50, team = 3, passive = true }
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 5 }))
    T.eq("ranged fire time: ok, not missed", r.reason, "ok")
    T.eq("ranged fire time: last hit credited", bot.lastHits, 1)
end

-- A real miss is still a miss: the projectile lands and the creep lives (a whiff), reported once it should
-- have landed.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 600, damage = 50, attackPoint = 0.3, projectileSpeed = 900, fireTime = true, whiff = true }
    local creep = sim:addCreep{ x = 550, y = 0, hp = 200, drain = 50, team = 3, passive = true }
    local r, t = run(sim, V.lastHit(bot, { target = creep, maxWait = 5 }))
    T.eq("ranged whiff: missed", r.reason, "missed")
end

-- Skill: the same contested creep, many trials with the allied hits shifted. Skill 1 lands nearly all; skill
-- 0.2 loses clearly more, and its misses go both ways: early swings that leave the creep alive (missed) and
-- late ones that lose it to the allied creeps (taken_by_other).
local function trials(skill, n, extra)
    local counts = { ok = 0, missed = 0, taken_by_other = 0 }
    for i = 1, n do
        local opts = { skill = function() return skill end, seed = 1000 + i }
        for k, v in pairs(extra or {}) do opts[k] = v end
        local sim = world(opts)
        local bot, creep = contested(sim, (i % 10) * 0.013)
        local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 5 }))
        counts[r.reason] = (counts[r.reason] or 0) + 1
    end
    return counts
end

do
    local n = 120
    local high = trials(1, n)
    local low = trials(0.2, n)
    local mid = trials(0.6, n)
    if os.getenv("LH_DEBUG") then
        for name, c in pairs({ high = high, mid = mid, low = low }) do
            print(name, c.ok, c.missed, c.taken_by_other, c.timeout)
        end
    end
    local function rate(c) return c.ok / n end
    T.check("skill 1: >= 90% landed (got " .. rate(high) .. ")", rate(high) >= 0.9)
    T.check("skill 0.2: clearly worse than skill 1 (" .. rate(low) .. " vs " .. rate(high) .. ")",
        rate(low) <= rate(high) - 0.15)
    T.check("skill 0.6 between (" .. rate(mid) .. ")", rate(mid) >= rate(low) and rate(mid) <= rate(high))
    T.check("skill 0.2: some early misses (" .. low.missed .. ")", low.missed > 0)
    T.check("skill 0.2: some late misses (" .. low.taken_by_other .. ")", low.taken_by_other > 0)
    T.check("skill 0.2: still lands most (" .. rate(low) .. ")", rate(low) >= 0.4)
end

-- The host's error width (pressure included) overrides the skill default.
do
    local n = 60
    local wide = trials(1, n, { lastHitError = function() return 0.6 end })
    T.check("lastHitError widens misses at skill 1 (" .. wide.ok .. "/" .. n .. ")", wide.ok / n <= 0.8)
end

-- Target choice: of two killable creeps, prefer the ranged one at high skill.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 60, attackPoint = 0.3 }
    sim:addCreep{ x = 100, y = 0, hp = 40, team = 3, name = "npc_dota_creep_badguys_melee" }
    local ranged = sim:addCreep{ x = 110, y = 20, hp = 50, team = 3, name = "npc_dota_creep_badguys_ranged" }
    local r = run(sim, V.lastHit(bot, { maxWait = 2 }))
    T.eq("ranged priority: ok", r.reason, "ok")
    local swing = firstSwing(bot)
    T.check("ranged priority: took the ranged creep", swing and swing.target == ranged)
end


-- laneTargets: the creeps a laner could go for next. Creeps lose hp to `drain` (hp/s); the bot (50 dmg, 0.3 s
-- wind-up, melee) lands 0.3 s after an order, so a creep at hp h is due when h - 0.3 * drain <= 50.
local function laneWorld(opts)
    local sim = world(opts)
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 50, attackPoint = 0.3, team = 2 }
    return sim, bot
end
local MELEE, RANGED = "npc_dota_creep_badguys_melee", "npc_dota_creep_badguys_ranged"
local ALLY_MELEE = "npc_dota_creep_goodguys_melee"
local function offered(list, creep)
    for _, t in ipairs(list) do if t.creep == creep then return t end end
end

-- Each due creep is offered with its eta and kind; the ranged flag follows the unit name. No choice is made.
do
    local sim, bot = laneWorld()
    local m = sim:addCreep{ x = 100, y = 0, hp = 100, drain = 100, team = 3, name = MELEE }   -- due in 0.2 s
    local r = sim:addCreep{ x = 100, y = 30, hp = 120, drain = 100, team = 3, name = RANGED } -- due in 0.4 s
    local list = V.laneTargets(bot)
    local tm, tr = offered(list, m), offered(list, r)
    T.eq("targets: both creeps offered", #list, 2)
    T.check("targets: melee eta about 0.2 s, not ranged", tm ~= nil and math.abs(tm.eta - 0.2) < 0.02 and not tm.ranged, tm and tm.eta)
    T.check("targets: ranged eta about 0.4 s, ranged", tr ~= nil and math.abs(tr.eta - 0.4) < 0.02 and tr.ranged and tr.kind == "lasthit", tr and tr.eta)
    -- The facts behind eta (slice 5): due 0.2 s, no walk, and dead to the drain at 100 hp / 100 hp/s = 1 s from now.
    T.check("targets: melee due, walk and dies", tm ~= nil and math.abs(tm.due - 0.2) < 0.02 and tm.walk == 0 and math.abs(tm.dies - 1.0) < 0.02,
        tm and string.format("%s %s %s", tm.due, tm.walk, tm.dies))
end

-- Denies: an allied creep below half its max hp is offered as a deny; `lastHit = false` / `deny = false` drop a side.
do
    local sim, bot = laneWorld()
    local a = sim:addCreep{ x = 80, y = -40, hp = 60, maxHp = 550, drain = 100, team = 2, name = ALLY_MELEE }
    local e = sim:addCreep{ x = 100, y = 0, hp = 100, drain = 100, team = 3, name = MELEE }
    local list = V.laneTargets(bot)
    T.check("targets: deny offered with its kind", offered(list, a) ~= nil and offered(list, a).kind == "deny")
    T.check("targets: last hit offered beside it", offered(list, e) ~= nil and offered(list, e).kind == "lasthit")
    local d = V.laneTargets(bot, { lastHit = false })
    T.check("targets: lastHit = false leaves only the deny", #d == 1 and d[1].creep == a)
    local l = V.laneTargets(bot, { deny = false })
    T.check("targets: deny = false leaves only the last hit", #l == 1 and l[1].creep == e)
end

-- Etiquette: a last hit the host forbids is not offered; the deny is.
do
    local sim, bot = laneWorld({ lastHitFilter = function() return false end })
    sim:addCreep{ x = 100, y = 0, hp = 60, drain = 100, team = 3, name = MELEE }
    sim:addCreep{ x = 80, y = -40, hp = 70, maxHp = 550, drain = 100, team = 2, name = ALLY_MELEE }
    local list = V.laneTargets(bot)
    T.check("targets: filtered last hit skipped, deny offered", #list == 1 and list[1].kind == "deny")
end

-- Not due within the window: a creep nobody hits (only our hit could ever kill it) and a far-off one.
do
    local sim, bot = laneWorld()
    sim:addCreep{ x = 100, y = 0, hp = 300, team = 3, name = MELEE }                    -- no damage incoming
    sim:addCreep{ x = 100, y = 0, hp = 250, drain = 100, team = 3, name = MELEE }       -- due in 2.3 s
    T.eq("targets: nothing due within 1 s", #V.laneTargets(bot), 0)
    local far = sim:addCreep{ x = 520, y = 0, hp = 40, team = 3, name = MELEE, passive = true }
    sim:step(DT) -- creep queries are cached per frame
    -- killable now but 370 out of range: the walk (about 1.2 s at 300) is the eta, and the bot sets off now
    local t = offered(V.laneTargets(bot), far)
    T.check("targets: far creep's eta is its walk", t ~= nil and math.abs(t.eta - 370 / 300) < 0.05, t and t.eta)
    T.check("targets: far creep due now, its walk apart, and no one on it (dies never)", t ~= nil and t.due == 0 and math.abs(t.walk - 370 / 300) < 0.05 and t.dies == math.huge,
        t and string.format("%s %s %s", t.due, t.walk, t.dies))
end

-- Melee standing outside the 520 ring: a creep 600 away due in 1.5 s is worth setting off for (1.5 s walk),
-- one due in 3 s is not yet; beyond the search radius (800 for melee) nothing is offered.
do
    local sim, bot = laneWorld()
    local c = sim:addCreep{ x = 600, y = 0, hp = 200, drain = 100, team = 3, name = MELEE }
    local list = V.laneTargets(bot)
    T.check("targets: sets off for a creep due as it arrives", #list == 1 and list[1].creep == c, list[1] and list[1].eta)
    c.hp = 350 -- due in 3 s
    sim:step(DT)
    T.eq("targets: too early to set off", #V.laneTargets(bot), 0)
    local sim2, bot2 = laneWorld()
    sim2:addCreep{ x = 900, y = 0, hp = 40, team = 3, name = MELEE, passive = true }
    T.eq("targets: beyond the search radius", #V.laneTargets(bot2), 0)
end

-- deny ------------------------------------------------------------------------

-- Enemy creeps beat on our creep (300 hp, 50 per hit). With 160 damage the bot could kill it at 160 hp but
-- may only deny below 50% (150).
local function denyWorld(opts)
    local sim = world(opts)
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 160, attackPoint = 0.3 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 300, team = 2, passive = true }
    sim:addCreep{ x = 200, y = 0, team = 3, damage = 50, attackPoint = 0.4, autoAttack = true,
        attackTarget = creep, firstSwingAt = 0.1, secondsPerAttack = 0.5 }
    return sim, bot, creep
end

do
    local sim, bot, creep = denyWorld()
    local r = run(sim, V.deny(bot, { maxWait = 5 }))
    T.eq("deny ok", r.reason, "ok")
    T.eq("deny ok: denies +1", bot.denies, 1)
    T.eq("deny ok: no last hit credited", bot.lastHits, 0)
    T.eq("deny ok: creep dead", creep.alive, false)
    local swing = firstSwing(bot)
    T.check("deny: never swung above 50% hp", swing and swing.targetHp < 150)
end

do
    local sim = world()
    local bot = sim:addBot{}
    sim:addCreep{ x = 100, y = 0, hp = 50, team = 3 } -- enemy creep: not deniable
    local r = run(sim, V.deny(bot))
    T.eq("deny no_target without allied creeps", r.reason, "no_target")
end

do
    local sim, bot, creep = denyWorld()
    local enemy = sim:addHero{ x = 250, y = 0, team = 3 }
    enemy.attackTarget = creep
    sim:killAt(0.5, creep, enemy)
    local r = run(sim, V.deny(bot, { target = creep }))
    T.eq("deny lost to the enemy: taken_by_other", r.reason, "taken_by_other")
    T.eq("deny lost: no deny credited", bot.denies, 0)
end

do
    local sim = world()
    local bot = sim:addBot{ damage = 40 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 300, team = 2 }
    local r, t = run(sim, V.deny(bot, { target = creep, maxWait = 1 }))
    T.eq("deny timeout above 50%", r.reason, "timeout")
    T.check("deny timeout after maxWait", t >= 1 and t < 1.2)
    T.eq("deny timeout: never swung", bot:actionsOf("attack"), 0)
end

-- A swing due only because of an enemy hero's wind-up names it: 80 HP, their 40 lands at 1.0 (wind-up from 0.5), ours
-- (45, 0.6 s) is due at 0.5 with their hit counted and never without it. ec is their wind-up left at our order (0.5),
-- oc our attack point (0.6): we commit after them.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.6 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 80, team = 3, passive = true }
    local enemy = sim:addHero{ x = 250, y = 0, team = 3, damage = 40, attackPoint = 0.5, secondsPerAttack = 1,
        autoAttack = true, firstSwingAt = 0.5 }
    enemy.attackTarget = creep
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 3 }))
    local msg = r.message or ""
    T.check("enemy wind-up relied on: ew=1 er=1 (" .. msg .. ")", string.find(msg, "ew=1 er=1", 1, true) ~= nil)
    local ec = tonumber(string.match(msg, "ec=([%d.]+)"))
    local oc = tonumber(string.match(msg, "oc=([%d.]+)"))
    T.check("enemy wind-up: ec is their wind-up left (" .. tostring(ec) .. ")", ec ~= nil and math.abs(ec - 0.5) <= 0.05)
    T.check("enemy wind-up: oc is our attack point (" .. tostring(oc) .. ")", oc ~= nil and math.abs(oc - 0.6) <= 0.05)
    local hf = tonumber(string.match(msg, "hf=(%d+)"))
    local hwf = tonumber(string.match(msg, "hwf=(%d+)"))
    T.check("hero watch: frames with the enemy hero on the creep (" .. msg .. ")", hf ~= nil and hf > 0)
    T.check("hero watch: its wind-up frames read, no more than its frames", hwf ~= nil and hwf > 0 and hwf <= hf)
    T.check("hero watch: raw activity is the attack's", string.find(msg, "ha=1503", 1, true) ~= nil)
end

-- An enemy hero aimed at the creep but not in an attack animation (the reading a broken wind-up reader gives in game):
-- frames counted, no wind-up frames, so hf > 0 with hwf = 0 tells the reader apart from heroes that never attack.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.6 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 300, team = 3, passive = true }
    local enemy = sim:addHero{ x = 250, y = 0, team = 3, damage = 40, attackPoint = 0.5, secondsPerAttack = 1 }
    enemy.attackTarget = creep
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 0.5 }))
    local msg = r.message or ""
    T.eq("hero watch idle: timeout", r.reason, "timeout")
    T.check("hero watch idle: frames counted (" .. msg .. ")", (tonumber(string.match(msg, "hf=(%d+)")) or 0) > 0)
    T.check("hero watch idle: no wind-up frames", string.find(msg, "hwf=0", 1, true) ~= nil)
end

-- Due without the enemy hero's hit (44 HP, ours 45): ew names their wind-up, er=0. Under a lapse the belief's horizon
-- shrinks below their landing: ew/er read the hits the belief counted, so a wind-up it skipped is not named relied on
-- (sdk review 2026-11-04-sdk-slice-lasthit-refine-logs-5f24047 F2).
for _, lapse in ipairs({ 0, 1 }) do
    local sim = world({ profile = function() return { lapse = lapse } end })
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.6 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 44, team = 3, passive = true }
    local enemy = sim:addHero{ x = 250, y = 0, team = 3, damage = 40, attackPoint = 0.5, secondsPerAttack = 1,
        autoAttack = true, firstSwingAt = 0 }
    enemy.attackTarget = creep
    for _ = 1, 3 do sim:step(DT) end
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 3 }))
    local msg = r.message or ""
    T.check("enemy wind-up not needed (lapse " .. lapse .. "): er=0 or not counted (" .. msg .. ")",
        string.find(msg, "er=1", 1, true) == nil)
    if lapse == 0 then T.check("enemy wind-up not needed: ew=1 er=0 (" .. msg .. ")", string.find(msg, "ew=1 er=0", 1, true) ~= nil) end
end

-- Skill: reaction samples stay within reactBase * (1 +- jitter / 2).
do
    world({ profile = function() return { react = 0.4, jitter = 0.5 } end })
    local lo, hi = math.huge, -math.huge
    for _ = 1, 200 do
        local d = tasks.Skill.react({ GetPlayerID = function() return 1 end })
        lo, hi = math.min(lo, d), math.max(hi, d)
    end
    T.check("react within 0.3..0.5 (" .. lo .. ".." .. hi .. ")", lo >= 0.3 - 1e-9 and hi <= 0.5 + 1e-9)
    T.check("react varies", hi - lo > 0.1)
end

-- Calibration fields on a swing's message: `fa` when the attack fired (the sim lands a melee hit at the attack point),
-- `lhp` the creep's HP on the first frame at or past the predicted landing (0: our hit took it), `fg` the frame gap seen.
do
    local sim = world()
    local bot, creep = contested(sim)
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 5 }))
    T.eq("calibration: ok", r.reason, "ok")
    local fa = tonumber(string.match(r.message or "", "fa=([%d%.%-]+)"))
    local lhp = tonumber(string.match(r.message or "", "lhp=([%d%-]+)"))
    local fg = tonumber(string.match(r.message or "", "fg=([%d%.]+)"))
    T.check("calibration: fa is the attack point (" .. tostring(fa) .. ")", fa ~= nil and math.abs(fa - 0.5) <= 0.04)
    T.eq("calibration: lhp 0, our hit took the creep", lhp, 0)
    T.check("calibration: fg is the sim's frame (" .. tostring(fg) .. ")", fg ~= nil and math.abs(fg - DT) <= 0.005)
end

-- The relied horizon ends one server tick before our hit, not one think gap. Stepped every 1/6 s (the body's in-game
-- rate, llhscn1), a verb that dropped every allied hit landing in the last 0.2 s before its own waited one frame too
-- long and lost the creep to the next hit. Allied hits of 40 land at 0.467, 0.747 and 1.05 on a 120 HP creep; ours
-- takes 0.6 s, so the swing is due at 0.333 (two hits inside its horizon) and lands at 0.933, before the third.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.6 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 120, team = 3, passive = true }
    for i, first in ipairs({ 0, 0.28, 0.583 }) do
        sim:addCreep{ x = 120, y = 40 * i, team = 2, damage = 40, attackPoint = 0.467, autoAttack = true,
            attackTarget = creep, firstSwingAt = first, passive = true }
    end
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 3 }), nil, 1 / 6)
    T.eq("think gap: ok at six frames a second", r.reason, "ok")
    local swing = firstSwing(bot)
    T.check("think gap: swung at the frame two hits were inside the horizon (t=" .. tostring(swing and swing.t) .. ")",
        swing ~= nil and swing.t < 0.4)
end

-- Damage the attacker index cannot see (a unit whose attack target reads nil, as a fogged enemy's does) still lands.
-- The creep's own HP history is the floor: hits of 30 every 0.3 s on a 200 HP creep read as at least 80 a second
-- (100 less one hit over the window), so the swing (0.5 s to land) goes at 50 HP and lands after the hit that
-- leaves 20; waiting for hp <= 44 would swing at 20 and land after the hit that kills it.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 44, attackPoint = 0.5 }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 200, team = 3, passive = true }
    local unseen = sim:addCreep{ x = 120, y = 40, team = 2, damage = 30, attackPoint = 0.3, secondsPerAttack = 0.3,
        autoAttack = true, attackTarget = creep, passive = true }
    unseen.GetAttackTarget = function() return nil end
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 5 }))
    T.eq("observed rate: ok", r.reason, "ok")
    local swing = firstSwing(bot)
    T.check("observed rate: swung above our damage (hp=" .. tostring(swing and swing.targetHp) .. ")", swing ~= nil and swing.targetHp > 44)
    local obs = tonumber(string.match(r.message or "", "obs=(%d+)"))
    T.check("observed rate: obs on the message (" .. tostring(obs) .. ")", obs ~= nil and obs >= 60 and obs <= 100)
    T.check("observed rate: the index saw nothing (idps=0)", string.find(r.message or "", "idps=0", 1, true) ~= nil)
    T.check("no enemy hero wind-up: no ew fields", string.find(r.message or "", "ew=", 1, true) == nil)
    T.check("no enemy hero: hf=0 hwf=0", string.find(r.message or "", " hf=0 hwf=0", 1, true) ~= nil)
end

-- A creep killed during our wind-up cancels the attack. Seen on the next frame, at the predicted landing time, it is
-- a late swing (`taken_by_other`, the attack never fired), not `missed`.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 45, attackPoint = 0.5, whiff = true }
    local creep = sim:addCreep{ x = 100, y = 0, hp = 40, team = 3, passive = true }
    local unseen = sim:addCreep{ x = 120, y = 40, team = 2, damage = 50, attackPoint = 0.45, autoAttack = true,
        attackTarget = creep, passive = true }
    unseen.GetAttackTarget = function() return nil end
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 2 }), nil, 0.25)
    T.eq("killed in our wind-up: taken_by_other", r.reason, "taken_by_other")
    T.check("killed in our wind-up: attack never fired (" .. tostring(r.message) .. ")", string.find(r.message or "", "fa=-1", 1, true) ~= nil)
end

-- A creep still alive on the frame of our predicted landing and killed by someone else just after is a miss (our hit did
-- not take it), whether or not the host has GetLastAttackTime to show the attack fired; killed before the landing it is
-- taken_by_other. The whiffing ranged bot's hit never lands, so the creep's fate is the others' alone.
for _, withMethod in ipairs({ true, false }) do
    local function fate(killAfter)
        local sim = world()
        local bot = sim:addBot{ x = 0, y = 0, range = 600, damage = 50, attackPoint = 0.3, projectileSpeed = 900, fireTime = true, whiff = true }
        if not withMethod then bot.GetLastAttackTime = nil end
        local creep = sim:addCreep{ x = 550, y = 0, hp = 200, drain = 50, team = 3, passive = true }
        local g = V.lastHit(bot, { target = creep, maxWait = 5 })
        local swingT
        for _ = 1, 3000 do
            local s = g:next()
            if s.done then return s.value end
            if swingT == nil and firstSwing(bot) ~= nil then swingT = sim.t end
            if swingT ~= nil and creep.alive and sim.t >= swingT + 0.87 + killAfter then creep.alive = false; creep.hp = 0 end
            sim:step(DT)
        end
        error("generator did not finish", 0)
    end
    local tag = withMethod and "with GetLastAttackTime" or "without GetLastAttackTime"
    local r = fate(0.1)
    T.eq("alive at landing (" .. tag .. "): missed", r.reason, "missed")
    local lhp = tonumber(string.match(r.message or "", "lhp=(%-?%d+)"))
    T.check("alive at landing (" .. tag .. "): lhp > 0 (" .. tostring(lhp) .. ")", lhp ~= nil and lhp > 0)
    T.eq("killed before landing (" .. tag .. "): taken_by_other", fate(-0.2).reason, "taken_by_other")
end

-- An attacker already winding up is credited with that hit once, not also as a rate over the long horizon. A ranged
-- hero (0.3 s wind-up + 0.59 s flight, 55 damage) on a 120 HP creep; allied creep A (40 a second) lands at 0.6, B
-- lands at 1.3. Counting A's hit and its rate too read 46 at the landing and swung at once, landing at 1.0 on 80 HP
-- (missed, llhscn2); crediting the hit alone reads 63 and waits for it, then the two rates read 46 and the swing
-- lands at about 1.5, after B's hit.
do
    local sim = world()
    local bot = sim:addBot{ x = 0, y = 0, range = 600, damage = 55, attackPoint = 0.3, projectileSpeed = 900, fireTime = true }
    local creep = sim:addCreep{ x = 550, y = 0, hp = 120, team = 3, passive = true }
    for i, first in ipairs({ 0.133, 0.833 }) do
        sim:addCreep{ x = 600, y = 40 * i, team = 2, damage = 40, attackPoint = 0.467, autoAttack = true,
            attackTarget = creep, firstSwingAt = first, passive = true }
    end
    local r = run(sim, V.lastHit(bot, { target = creep, maxWait = 3 }))
    T.eq("wind-up once: ok", r.reason, "ok")
    local swing = firstSwing(bot)
    T.check("wind-up once: waited for the seen hit (t=" .. tostring(swing and swing.t) .. ")", swing ~= nil and swing.t >= 0.55)
end

print("lasthit [" .. T.runtime() .. "]")
T.finish()
