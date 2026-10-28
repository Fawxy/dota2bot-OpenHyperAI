-- lastHit v2 and deny: incoming-damage prediction, own hit time, skill-scaled timing error.
local T = dofile("test/helpers.lua")
local Sim = dofile("test/sim.lua")
local tasks = dofile("../bots/FunLib/engine/tasks.lua")
local V = tasks.Verbs

-- About 30 frames per second, as in game: the swing decision is only as fine as the frame.
local DT = 1 / 30

local function run(sim, g, maxFrames)
    for _ = 1, maxFrames or 3000 do
        local r = g:next()
        if r.done then return r.value, sim.t end
        sim:step(DT)
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
-- lost, and is never offered by nextLastHit; it must not raise an error.
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
    local ok2, t2 = pcall(V.nextLastHit, b2)
    T.check("fogged creep: nextLastHit no error and nothing offered", ok2 and t2 == nil, tostring(t2))
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


-- nextLastHit: which creep a laner goes for next. Creeps lose hp to `drain` (hp/s); the bot (50 dmg, 0.3 s
-- wind-up, melee) lands 0.3 s after an order, so a creep at hp h is due when h - 0.3 * drain <= 50.
local function laneWorld(opts)
    local sim = world(opts)
    local bot = sim:addBot{ x = 0, y = 0, range = 150, damage = 50, attackPoint = 0.3, team = 2 }
    return sim, bot
end
local MELEE, RANGED = "npc_dota_creep_badguys_melee", "npc_dota_creep_badguys_ranged"
local ALLY_MELEE = "npc_dota_creep_goodguys_melee"

-- The ranged creep wins over a melee creep due a little sooner (gold and XP).
do
    local sim, bot = laneWorld()
    sim:addCreep{ x = 100, y = 0, hp = 100, drain = 100, team = 3, name = MELEE }   -- due in 0.2 s
    local r = sim:addCreep{ x = 100, y = 30, hp = 120, drain = 100, team = 3, name = RANGED } -- due in 0.4 s
    local t = V.nextLastHit(bot)
    T.check("next: ranged preferred over a melee due 0.2 s sooner", t ~= nil and t.creep == r and t.kind == "lasthit")
    T.check("next: eta of the ranged creep about 0.4 s", t ~= nil and math.abs(t.eta - 0.4) < 0.02, t and t.eta)
end

-- ...but not over a melee creep due now when the ranged one is a second away: the bias is bounded.
do
    local sim, bot = laneWorld()
    local m = sim:addCreep{ x = 100, y = 0, hp = 60, drain = 100, team = 3, name = MELEE }   -- due now
    sim:addCreep{ x = 100, y = 30, hp = 180, drain = 100, team = 3, name = RANGED }          -- due in 1.0 s
    local t = V.nextLastHit(bot, { within = 1.5 })
    T.check("next: melee due now beats a ranged creep due in 1 s", t ~= nil and t.creep == m, t and t.eta)
end

-- A core never gives up its own last hit to deny: an allied creep due now loses to an enemy creep due in 0.2 s.
do
    local sim, bot = laneWorld()
    sim:addCreep{ x = 80, y = -40, hp = 60, maxHp = 550, drain = 100, team = 2, name = ALLY_MELEE }
    local e = sim:addCreep{ x = 100, y = 0, hp = 100, drain = 100, team = 3, name = MELEE }
    local t = V.nextLastHit(bot)
    T.check("next: last hit beats a deny due slightly sooner", t ~= nil and t.creep == e and t.kind == "lasthit")
    local d = V.nextLastHit(bot, { lastHit = false })
    T.check("next: the deny is offered when last hits are off", d ~= nil and d.kind == "deny")
end

-- Etiquette: a last hit the host forbids is not offered; the deny is.
do
    local sim, bot = laneWorld({ lastHitFilter = function() return false end })
    sim:addCreep{ x = 100, y = 0, hp = 60, drain = 100, team = 3, name = MELEE }
    sim:addCreep{ x = 80, y = -40, hp = 70, maxHp = 550, drain = 100, team = 2, name = ALLY_MELEE }
    local t = V.nextLastHit(bot)
    T.check("next: filtered last hit skipped, deny offered", t ~= nil and t.kind == "deny")
end

-- Not due within the window: a creep nobody hits (only our hit could ever kill it) and a far-off one.
do
    local sim, bot = laneWorld()
    sim:addCreep{ x = 100, y = 0, hp = 300, team = 3, name = MELEE }                    -- no damage incoming
    sim:addCreep{ x = 100, y = 0, hp = 250, drain = 100, team = 3, name = MELEE }       -- due in 2.3 s
    T.eq("next: nothing due within 1 s", V.nextLastHit(bot), nil)
    local far = sim:addCreep{ x = 520, y = 0, hp = 40, team = 3, name = MELEE, passive = true }
    sim:step(DT) -- creep queries are cached per frame
    -- killable now but 370 out of range: the walk (about 1.2 s at 300) is the eta, and the bot sets off now
    local t = V.nextLastHit(bot)
    T.check("next: far creep's eta is its walk", t ~= nil and t.creep == far and math.abs(t.eta - 370 / 300) < 0.05, t and t.eta)
end

-- Melee standing outside the 520 ring: a creep 600 away due in 1.5 s is worth setting off for (1.5 s walk),
-- one due in 3 s is not yet; beyond the search radius (800 for melee) nothing is offered.
do
    local sim, bot = laneWorld()
    local c = sim:addCreep{ x = 600, y = 0, hp = 200, drain = 100, team = 3, name = MELEE }
    local t = V.nextLastHit(bot)
    T.check("next: sets off for a creep due as it arrives", t ~= nil and t.creep == c, t and t.eta)
    c.hp = 350 -- due in 3 s
    sim:step(DT)
    T.eq("next: too early to set off", V.nextLastHit(bot), nil)
    local sim2, bot2 = laneWorld()
    sim2:addCreep{ x = 900, y = 0, hp = 40, team = 3, name = MELEE, passive = true }
    T.eq("next: beyond the search radius", V.nextLastHit(bot2), nil)
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

print("lasthit [" .. T.runtime() .. "]")
T.finish()
