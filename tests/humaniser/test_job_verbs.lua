-- Job verbs (humaniser/job_verbs: stack, pull, runeRun, clearCamp, gank) driven through the engine's runner against
-- the engine's frame simulator. Moved from the engine's test_jobs.lua in slice 0b, unchanged but for the calls.
local T = dofile(BOTS_ROOT .. "/engine/test/helpers.lua")
local Sim = dofile(BOTS_ROOT .. "/engine/test/sim.lua")
local tasks = dofile(BOTS_ROOT .. "/bots/FunLib/engine/tasks.lua")
local Jobs = require("bots/FunLib/humaniser/job_verbs")
local R = tasks.Tasks
local V = Jobs
-- job.stack(ctx, plan) and friends before slice 0b: the job with this task's label and urgent as its hooks.
local job = {}
for _, name in ipairs({ "stack", "pull", "runeRun", "clearCamp", "gank" }) do
    job[name] = function(ctx, plan) return Jobs[name](ctx.bot, plan, { label = ctx.label, urgent = ctx.urgent }) end
end

local HOST = 7
local DT = 0.1

local function world(adapterOpts, botOpts)
    local sim = Sim.new()
    local a = sim:adapter(nil, adapterOpts)
    sim.claims = {}
    a.claim = function(_, c) sim.claims[#sim.claims + 1] = { t = sim.t, c = c } end
    tasks.init(a)
    Jobs.Bind(tasks, a)
    local o = { x = 0, y = 0, speed = 300 }
    for k, v in pairs(botOpts or {}) do o[k] = v end
    local bot = sim:addBot(o)
    bot.mode = HOST
    return sim, bot
end

local function frame(sim, bot)
    if bot.mode == HOST then R.Step(bot, HOST) end
    R.Tick(bot)
    sim:step(DT)
end

local function start(bot, factory)
    return R.task(bot, { name = "job", host = HOST }, factory)
end

-- Runs until the task ends; records label changes and, per unit in `watch`, the time it first targeted the bot.
local function run(sim, bot, watch, maxFrames)
    local labels, hitAt = {}, {}
    for _ = 1, maxFrames or 1000 do
        local cur = R.Current(bot)
        if cur == nil then return R.Last(bot).result, sim.t, labels, hitAt end
        if cur.label and labels[#labels] ~= cur.label then labels[#labels + 1] = cur.label end
        frame(sim, bot)
        for i, u in ipairs(watch or {}) do
            if hitAt[i] == nil and u.attackTarget == bot then hitAt[i] = sim.t end
        end
    end
    error("task did not finish", 0)
end

local function holdsOf(sim)
    local h = {}
    for _, x in ipairs(sim.holds) do h[x.tag] = true end
    return h
end

local function box(cx, cy, half)
    return { min = { x = cx - half, y = cy - half }, max = { x = cx + half, y = cy + half } }
end

local function mean(xs)
    local s = 0
    for _, x in ipairs(xs) do s = s + x end
    return s / #xs
end

local function sd(xs)
    local m, s = mean(xs), 0
    for _, x in ipairs(xs) do s = s + (x - m) ^ 2 end
    return math.sqrt(s / #xs)
end

-- ---------------------------------------------------------------------------------------------------- stack

local function stackPlan(over)
    local p = {
        camp = { stand = { x = 600, y = 0 }, box = box(750, 0, 100) },
        aggroAt = 5, exitPath = { { x = 200, y = 0 }, { x = 0, y = 0 } }, exitUntil = 9,
        timingError = 0, aggroLead = 0,
    }
    for k, v in pairs(over or {}) do p[k] = v end
    -- "auto": leave the option unset so the verb's default (estimated lead, skill-drawn error) applies.
    for k, v in pairs(p) do if v == "auto" then p[k] = nil end end
    return p
end

do
    -- The stack shape: travel, wait at the stand point, confirmed hit, walk off, hold out of the box until exitUntil.
    local sim, bot = world()
    local n = sim:addNeutral{ x = 700, y = 0, hp = 500 }
    local p = stackPlan()
    start(bot, function(ctx) return job.stack(ctx, p) end)
    local r, t, labels = run(sim, bot)
    T.eq("stack: ok", r.reason, "ok")
    T.eq("stack: phases", table.concat(labels, ","), "travel,wait,aggro,exit")
    local firstAttack
    for _, a in ipairs(bot.actions) do if a.kind == "attack" then firstAttack = firstAttack or a.t end end
    T.check("stack: no attack order before the aggro second (lead 0)", firstAttack ~= nil and firstAttack >= p.aggroAt - 1e-9)
    T.eq("stack: neutral aggroed onto the bot", n.attackTarget, bot)
    T.check("stack: walked off along the path", Sim.dist(bot.loc, { x = 0, y = 0 }) <= 100)
    T.check("stack: held until exitUntil", t >= p.exitUntil)
    local h = holdsOf(sim)
    T.check("stack: wait and exit holds posted", h.job_wait and h.stack_exit)
    local urgentEarly = false
    for _, c in ipairs(sim.claims) do if c.c.urgent and c.t < p.aggroAt then urgentEarly = true end end
    T.check("stack: urgent while travelling", urgentEarly)
    T.eq("stack: urgency dropped after the aggro", sim.claims[#sim.claims].c.urgent, false)
end

do
    -- Auto lead: the order goes the wind-up early, so the hit lands on the aggro second, not one wind-up late.
    local sim, bot = world(nil, { attackPoint = 0.5 })
    local n = sim:addNeutral{ x = 700, y = 0, hp = 500 }
    start(bot, function(ctx) return job.stack(ctx, stackPlan{ aggroLead = "auto" }) end)
    local r, _, _, hit = run(sim, bot, { n })
    T.eq("stack lead: ok", r.reason, "ok")
    T.check("stack lead: hit lands at the aggro second", hit[1] ~= nil and math.abs(hit[1] - 5) <= DT + 1e-9)
end

do
    -- A ranged bot leads by the projectile flight too.
    local sim, bot = world(nil, { attackPoint = 0.3, range = 600, projectileSpeed = 900 })
    local n = sim:addNeutral{ x = 1100, y = 0, hp = 500 }
    start(bot, function(ctx) return job.stack(ctx, stackPlan{ aggroLead = "auto", camp = { stand = { x = 600, y = 0 }, box = box(1150, 0, 100) } }) end)
    local r, _, _, hit = run(sim, bot, { n })
    T.eq("stack ranged lead: ok", r.reason, "ok")
    T.check("stack ranged lead: lands within a frame of the aggro second", hit[1] ~= nil and math.abs(hit[1] - 5) <= 2 * DT + 1e-9)
end

do
    -- Idle neutrals stand just outside the spawn box: inside the default 300 margin they are still the camp.
    local sim, bot = world()
    local n = sim:addNeutral{ x = 700, y = 0, hp = 500 }
    start(bot, function(ctx) return job.stack(ctx, stackPlan{ camp = { stand = { x = 600, y = 0 }, box = box(1000, 0, 100) } }) end)
    local r = run(sim, bot)
    T.eq("stack margin: neutral 200 outside the box is the camp", r.reason, "ok")
    T.eq("stack margin: it was hit", n.attackTarget, bot)
end

do
    -- Outside the margin it is not the camp (a neighbouring camp's creep): no-camp, and it is left alone.
    local sim, bot = world()
    local n = sim:addNeutral{ x = 700, y = 0, hp = 500 }
    start(bot, function(ctx) return job.stack(ctx, stackPlan{ camp = { stand = { x = 600, y = 0 }, box = box(1000, 0, 100), margin = 100 } }) end)
    local r = run(sim, bot)
    T.eq("stack outside margin: no_target", r.reason, "no_target")
    T.eq("stack outside margin: message", r.message, "mistake:no-camp")
    T.check("stack outside margin: not attacked", n.attackTarget == nil)
end

do
    -- Blocked on the way: not at the stand point by aggroAt + startLate (and nothing in sight) -> timeout "late".
    local sim, bot = world()
    sim:addNeutral{ x = 1500, y = 0, hp = 500 }
    sim:at(0.5, function() bot.blocked = true end)
    start(bot, function(ctx) return job.stack(ctx, stackPlan{ camp = { stand = { x = 600, y = 0 }, box = box(1500, 0, 100) } }) end)
    local r, t = run(sim, bot)
    T.eq("stack late: timeout", r.reason, "timeout")
    T.eq("stack late: message", r.message, "late")
    T.check("stack late: gives up at aggroAt + startLate", t >= 7 - 1e-9 and t <= 7 + 3 * DT)
end

do
    -- Camp farmed: nothing in the box within noCampAfter -> no-camp after searching towards the origin.
    local sim, bot = world()
    start(bot, function(ctx) return job.stack(ctx, stackPlan{ camp = { stand = { x = 600, y = 0 }, box = box(750, 0, 100), origin = { x = 750, y = 0 } } }) end)
    local r, t = run(sim, bot)
    T.eq("stack no camp: no_target", r.reason, "no_target")
    T.eq("stack no camp: message", r.message, "mistake:no-camp")
    T.check("stack no camp: searched until aggroAt + noCampAfter", t >= 6 - 1e-9)
    T.check("stack no camp: walked in towards the origin", bot.loc.x > 650)
end

do
    -- Pushed off the stand point while waiting: walks back and still aggroes on time.
    local sim, bot = world()
    local n = sim:addNeutral{ x = 700, y = 0, hp = 500 }
    sim:at(3.5, function() bot.loc.x = 300 end)
    start(bot, function(ctx) return job.stack(ctx, stackPlan()) end)
    local r, _, _, hit = run(sim, bot, { n })
    T.eq("stack pushed: ok", r.reason, "ok")
    T.check("stack pushed: hit by aggroAt + attack point", hit[1] ~= nil and hit[1] <= 5 + 0.3 + DT)
end

do
    -- The bot whiffs: no landed hit within confirmFor -> missed with the no-aggro message.
    local sim, bot = world()
    bot.whiff = true
    sim:addNeutral{ x = 700, y = 0, hp = 500, passive = true }
    start(bot, function(ctx) return job.stack(ctx, stackPlan()) end)
    local r = run(sim, bot)
    T.eq("stack whiff: missed", r.reason, "missed")
    T.eq("stack whiff: message", r.message, "mistake:no-aggro")
end

do
    -- onAggro reports the planned second, the drawn error and when the order went out.
    local sim, bot = world()
    local n = sim:addNeutral{ x = 700, y = 0, hp = 500 }
    local info
    start(bot, function(ctx) return job.stack(ctx, stackPlan{ timingError = 0.7, onAggro = function(i) info = i end }) end)
    run(sim, bot)
    T.check("onAggro called", info ~= nil)
    T.eq("onAggro planned", info and info.planned, 5)
    T.near("onAggro error", info and info.error, 0.7, 1e-9)
    T.check("onAggro ordered at planned + error (lead 0)", info and math.abs(info.orderedAt - 5.7) <= DT + 1e-9)
    T.check("onAggro target is the neutral hit", info ~= nil and info.target == n)
end

do
    -- Skill: the aggro error is drawn from the adapter's skill. Low skill lands far more spread out than high skill,
    -- both centred on the planned second.
    local function landings(skill, seed)
        local out = {}
        local rnd = Sim.lcg(seed)
        for _ = 1, 40 do
            local sim, bot = world({ skill = function() return skill end, random = rnd })
            local n = sim:addNeutral{ x = 700, y = 0, hp = 500 }
            start(bot, function(ctx) return job.stack(ctx, stackPlan{ aggroAt = 8, exitUntil = 14, timingError = "auto", aggroLead = 0 }) end)
            local _, _, _, hit = run(sim, bot, { n })
            if hit[1] then out[#out + 1] = hit[1] - 0.3 end
        end
        return out
    end
    local hi, lo = landings(1, 11), landings(0.2, 11)
    T.check("stack skill: every high-skill attempt landed", #hi == 40)
    T.check("stack skill: low skill spreads wider (sd)", sd(lo) > 3 * sd(hi))
    T.check("stack skill: high skill within 0.5 s", math.abs(mean(hi) - 8) <= 0.5 and sd(hi) <= 0.35)
    T.check("stack skill: low skill centred on the second", math.abs(mean(lo) - 8) <= 0.6)
end

-- ----------------------------------------------------------------------------------------------------- pull

local function pullPlan(over)
    local p = {
        camp = { stand = { x = 600, y = 0 }, box = box(750, 0, 100) },
        aggroAt = 5, lead = { { x = 400, y = 300 }, { x = 200, y = 600 } }, watchSec = 2,
        timingError = 0, aggroLead = 0,
    }
    for k, v in pairs(over or {}) do p[k] = v end
    return p
end

do
    local sim, bot = world()
    local n = sim:addNeutral{ x = 700, y = 0, hp = 500 }
    start(bot, function(ctx) return job.pull(ctx, pullPlan{ watchUntil = 9, watchSec = 0.5 }) end)
    local r, t, labels, hit = run(sim, bot, { n })
    T.eq("pull: ok", r.reason, "ok")
    T.eq("pull: phases", table.concat(labels, ","), "travel,wait,aggro,lead,watch")
    T.check("pull: hit at the aggro second", hit[1] ~= nil and hit[1] >= 5 and hit[1] <= 5.3 + DT)
    T.check("pull: led to the meet point", Sim.dist(bot.loc, { x = 200, y = 600 }) <= 100)
    T.check("pull: watched until the wave (watchUntil)", t >= 9 - 1e-9 and t <= 9 + 2 * DT)
    T.check("pull: watch hold posted", holdsOf(sim).job_watch)
end

do
    -- Lead blocked: the camp is chasing a bot that cannot reach the meet point -> fails with message "lead".
    local sim, bot = world()
    sim:addNeutral{ x = 700, y = 0, hp = 500 }
    sim:at(6, function() bot.blocked = true end)
    start(bot, function(ctx) return job.pull(ctx, pullPlan()) end)
    local r = run(sim, bot)
    T.check("pull lead blocked: fails", not r.success)
    T.eq("pull lead blocked: message", r.message, "lead")
end

-- Double pull geometry: the bot starts between the hard camp (north) and the small camp, each outside the other's margin.
local HARD = { camp = { stand = { x = 600, y = 800 }, box = box(750, 800, 100) }, aggroAt = 3 }

do
    -- Hard camp hit first at its own second, then the small camp at the graded second, then the lead.
    local sim, bot = world(nil, { x = 600, y = 500 })
    local hard = sim:addNeutral{ x = 700, y = 800, hp = 900 }
    local small = sim:addNeutral{ x = 700, y = 0, hp = 500 }
    local ordered = {}
    start(bot, function(ctx) return job.pull(ctx, pullPlan{ aggroAt = 7, first = HARD }) end)
    local r, _, labels, hit = run(sim, bot, { hard, small })
    for _, a in ipairs(bot.actions) do if a.kind == "attack" then ordered[#ordered + 1] = a.target end end
    T.eq("double: ok", r.reason, "ok")
    T.eq("double: phases", table.concat(labels, ","), "travel,wait,aggro,travel,wait,aggro,lead,watch")
    T.check("double: hard camp first", ordered[1] == hard)
    T.check("double: then the small camp", ordered[#ordered] == small)
    T.check("double: hard hit at its second", hit[1] ~= nil and hit[1] >= 3 and hit[1] <= 3.3 + DT)
    T.check("double: small hit at the graded second", hit[2] ~= nil and hit[2] >= 7 and hit[2] <= 7.3 + DT)
end

do
    -- Hard camp gone: no-camp, and the small camp is never touched.
    local sim, bot = world(nil, { x = 600, y = 500 })
    local small = sim:addNeutral{ x = 700, y = 0, hp = 500 }
    start(bot, function(ctx) return job.pull(ctx, pullPlan{ aggroAt = 7, first = HARD }) end)
    local r = run(sim, bot)
    T.eq("double no hard camp: no_target", r.reason, "no_target")
    T.check("double no hard camp: small camp untouched", small.attackTarget == nil)
end

-- ------------------------------------------------------------------------------------------------------ rune

local RUNE = 3

local function runeWorld(adapterOpts, status)
    local sim, bot = world(adapterOpts)
    sim:addRune(RUNE, { x = 900, y = 0, status = status or Sim.RUNE_STATUS_MISSING })
    sim:installRuneGlobals()
    return sim, bot
end

do
    -- Arrives early, waits beside the spot, picks the rune up only once it has spawned.
    local sim, bot = runeWorld()
    sim:at(8, function() sim.runes[RUNE].status = Sim.RUNE_STATUS_AVAILABLE end)
    local arrivedAt
    start(bot, function(ctx) return job.runeRun(ctx, { at = { x = 850, y = 0 }, spawnAt = 8, rune = RUNE }) end)
    local r, _, labels
    for _ = 1, 400 do
        if R.Current(bot) == nil then break end
        frame(sim, bot)
        if arrivedAt == nil and Sim.dist(bot.loc, { x = 850, y = 0 }) <= 150 then arrivedAt = sim.t end
    end
    r = R.Last(bot).result
    local firstPick
    for _, a in ipairs(bot.actions) do if a.kind == "rune" then firstPick = firstPick or a.t end end
    T.eq("rune: ok", r.reason, "ok")
    T.eq("rune: taken by the bot", sim.runes[RUNE].takenBy, bot)
    T.check("rune: arrived before the spawn", arrivedAt ~= nil and arrivedAt < 8)
    T.check("rune: no pick-up order before the spawn", firstPick ~= nil and firstPick >= 8)
    T.check("rune: wait hold posted", holdsOf(sim).rune_wait)
    sim:removeRuneGlobals()
end

do
    -- runeLeaveAt: leaving then arrives `early` s before the spawn at skill 1, and with less margin at low skill.
    local function margins(skill)
        local out = {}
        local rnd = Sim.lcg(5)
        for i = 1, 30 do
            local sim, bot = world({ skill = function() return skill end, random = rnd })
            local plan = { at = { x = 1500, y = 0 }, spawnAt = 100 + i, early = 4 }
            local leave = V.runeLeaveAt(bot, plan)
            T.check("runeLeaveAt stable per spawn", V.runeLeaveAt(bot, plan) == leave)
            out[#out + 1] = plan.spawnAt - (leave + 1500 / 300)
        end
        return out
    end
    local hi, lo = margins(1), margins(0.2)
    T.check("rune early: skill 1 arrives ~4 s early", math.abs(mean(hi) - 4) <= 0.3)
    T.check("rune early: low skill cuts it finer", mean(lo) < mean(hi) - 1.5)
    T.check("rune early: low skill is sometimes late", (function()
        for _, m in ipairs(lo) do if m < 0 then return true end end
        return false
    end)())
end

do
    -- Blocked on the way: not there by spawnAt + lateBy -> timeout "late".
    local sim, bot = runeWorld()
    sim:at(1, function() bot.blocked = true end)
    start(bot, function(ctx) return job.runeRun(ctx, { at = { x = 850, y = 0 }, spawnAt = 5, rune = RUNE, lateBy = 2 }) end)
    local r, t = run(sim, bot)
    T.eq("rune late: timeout", r.reason, "timeout")
    T.eq("rune late: message", r.message, "late")
    T.check("rune late: at spawnAt + lateBy", t >= 7 - 1e-9 and t <= 7 + 3 * DT)
    sim:removeRuneGlobals()
end

do
    -- Never spawns (taken before we saw it / wrong spot): gives up with no_target after the grace window.
    local sim, bot = runeWorld()
    start(bot, function(ctx) return job.runeRun(ctx, { at = { x = 850, y = 0 }, spawnAt = 5, rune = RUNE }) end)
    local r, t = run(sim, bot)
    T.eq("rune never: no_target", r.reason, "no_target")
    T.check("rune never: retried through the grace window", t >= 5 + 2 - 1e-9 and t <= 5 + 2 + 3 * DT)
    sim:removeRuneGlobals()
end

do
    -- Shrine: stand within radius for `channel` s from the activation; pushed out, the count restarts.
    local sim, bot = world()
    sim:at(6, function() bot.loc.x = 300 end)
    start(bot, function(ctx) return job.runeRun(ctx, { at = { x = 900, y = 0 }, spawnAt = 5, channel = 3, radius = 300 }) end)
    local r, t, labels = run(sim, bot)
    T.eq("shrine: ok", r.reason, "ok")
    T.eq("shrine: phases", table.concat(labels, ","), "travel,wait,channel")
    -- Pushed out at 6, back in range (600 -> 600 at 300/s) about 7.0, then 3 s.
    T.check("shrine: count restarted after the push", t >= 9.9)
end

do
    -- Shrine with host confirmation that never comes: missed.
    local sim, bot = world()
    start(bot, function(ctx)
        return job.runeRun(ctx, { at = { x = 900, y = 0 }, spawnAt = 5, channel = 3, confirmed = function() return false end })
    end)
    local r = run(sim, bot)
    T.eq("shrine unconfirmed: missed", r.reason, "missed")
end

-- clearCamp: walk to the camp, kill its neutrals (lowest HP first, kept while alive), end ok "cleared".
do
    -- The sim's attack orders do not walk the bot in, so it starts in range of the camp.
    local sim, bot = world(nil, { x = 500, damage = 50, autoAttack = true, secondsPerAttack = 0.5, range = 150 })
    local a = sim:addNeutral{ x = 600, y = 0, hp = 120 }
    local b = sim:addNeutral{ x = 640, y = 0, hp = 60 }
    local far = sim:addNeutral{ x = 2000, y = 0, hp = 100 }
    local engagedAt
    start(bot, function(ctx) return job.clearCamp(ctx, { at = { x = 620, y = 0 }, onEngage = function(t) engagedAt = t end }) end)
    local r, t, labels = run(sim, bot)
    T.eq("clear: ok", r.reason, "ok")
    T.eq("clear: cleared", r.message, "cleared")
    T.check("clear: both camp neutrals dead", not a.alive and not b.alive)
    T.check("clear: a neutral outside the camp radius left alone", far.alive)
    T.eq("clear: farming once in range", labels[#labels], "farm")
    T.check("clear: engagement reported once in range", engagedAt ~= nil)
    local firstTarget = nil
    for _, x in ipairs(bot.actions) do if x.kind == "attack" then firstTarget = x.target break end end
    T.check("clear: lowest HP neutral first", firstTarget == b)
    T.check("clear: one order per target, not one per frame (" .. bot:actionsOf("attack") .. ")", bot:actionsOf("attack") <= 4)
end

do
    -- Nothing at the camp: arrives, looks for emptyAfter, ends ok "empty".
    local sim, bot = world()
    start(bot, function(ctx) return job.clearCamp(ctx, { at = { x = 600, y = 0 } }) end)
    local r, t = run(sim, bot)
    T.eq("clear empty: ok", r.reason, "ok")
    T.eq("clear empty: empty", r.message, "empty")
    T.check("clear empty: after arriving (300 from 600 at 300/s) and looking", t >= 1.4 and t <= 2.2)
end

do
    -- Past the deadline mid-fight: timeout "late", the camp left unfinished.
    local sim, bot = world(nil, { damage = 10, autoAttack = true })
    local n = sim:addNeutral{ x = 300, y = 0, hp = 1000, passive = true }
    start(bot, function(ctx) return job.clearCamp(ctx, { at = { x = 300, y = 0 }, deadline = 4 }) end)
    local r, t = run(sim, bot)
    T.eq("clear late: timeout", r.reason, "timeout")
    T.eq("clear late: message", r.message, "late")
    T.check("clear late: at the deadline", t >= 4 and t <= 4.2)
    T.check("clear late: neutral still alive", n.alive)
end

do
    -- Skill: after a kill the next attack order waits one reaction delay from the profile.
    local function nextOrderGap(react)
        local sim, bot = world({ profile = function() return { react = react, jitter = 0 } end }, { damage = 100, autoAttack = true, secondsPerAttack = 0.5 })
        local a = sim:addNeutral{ x = 100, y = 0, hp = 100 }
        local b = sim:addNeutral{ x = 120, y = 0, hp = 300 }
        local diedAt
        start(bot, function(ctx) return job.clearCamp(ctx, { at = { x = 110, y = 0 } }) end)
        for _ = 1, 200 do
            if R.Current(bot) == nil then break end
            frame(sim, bot)
            if diedAt == nil and not a.alive then diedAt = sim.t end
        end
        for _, x in ipairs(bot.actions) do
            if x.kind == "attack" and x.target == b then return x.t - diedAt end
        end
    end
    local quick, slow = nextOrderGap(0), nextOrderGap(0.4)
    T.check("clear react 0: next target within a frame (" .. tostring(quick) .. ")", quick ~= nil and quick <= DT + 1e-6)
    T.check("clear react 0.4: next order >= 0.4 s after the kill (" .. tostring(slow) .. ")", slow ~= nil and slow >= 0.4 - 1e-6 and slow <= 0.4 + 2 * DT)
end

-- gank: walk the approach path, telegraph once ETA <= lead, chase into range, attack; ok "kill" when the target dies.
do
    local sim, bot = world(nil, { damage = 100, autoAttack = true, secondsPerAttack = 0.5, range = 150, speed = 300 })
    local target = sim:addHero{ team = 3, x = 1500, y = 0, hp = 300 }
    local telegraphedAt, eta, engagedAt
    start(bot, function(ctx)
        return job.gank(ctx, {
            target = function() return target end,
            path = { { x = 600, y = 300 } },
            engageRange = 200,
            telegraph = { lead = 3, fn = function(e) telegraphedAt, eta = sim.t, e end },
            onEngage = function(t) engagedAt = t end,
        })
    end)
    local r, t, labels = run(sim, bot)
    T.eq("gank: ok", r.reason, "ok")
    T.eq("gank: kill", r.message, "kill")
    T.check("gank: target dead", not target.alive)
    T.eq("gank: phases", table.concat(labels, ","), "travel,engage")
    -- Path 671 then 1,005 to the target: 5.6 s at 300; the telegraph fires once ETA is 3 s.
    T.check("gank: telegraphed about 3 s out (" .. tostring(eta) .. ")", eta ~= nil and eta <= 3 + 1e-6 and eta >= 2.6)
    T.check("gank: telegraph before engaging", telegraphedAt ~= nil and engagedAt ~= nil and telegraphedAt < engagedAt)
    T.check("gank: went via the approach point", (function()
        for _, a in ipairs(bot.actions) do if a.kind == "move" and a.loc.y == 300 then return true end end
        return false end)())
end

do
    -- The target slips into fog for longer than the grace: fail "escaped".
    local sim, bot = world(nil, { speed = 300 })
    local target = sim:addHero{ team = 3, x = 900, y = 0, hp = 300 }
    sim:at(1, function() target.hidden = true end)
    start(bot, function(ctx) return job.gank(ctx, { target = function() return target end, path = {} }) end)
    local r, t = run(sim, bot)
    T.eq("gank lost: interrupted", r.reason, "interrupted")
    T.eq("gank lost: escaped", r.message, "escaped")
    T.check("gank lost: after the 2 s fog grace", t >= 3 - 1e-6 and t <= 3.3)
end

do
    -- Engaged but the fight drags on: fail timeout "no-kill" after engageFor.
    local sim, bot = world(nil, { damage = 1, autoAttack = true, range = 150 })
    local target = sim:addHero{ team = 3, x = 100, y = 0, hp = 5000 }
    start(bot, function(ctx) return job.gank(ctx, { target = function() return target end, path = {}, engageFor = 4 }) end)
    local r, t = run(sim, bot)
    T.eq("gank long: timeout", r.reason, "timeout")
    T.eq("gank long: message", r.message, "no-kill")
    T.check("gank long: about engageFor after engaging", t >= 4 and t <= 4.4)
end

do
    -- Not engaged by the deadline (target out of reach): fail timeout "late".
    local sim, bot = world(nil, { speed = 300 })
    local target = sim:addHero{ team = 3, x = 6000, y = 0, hp = 300 }
    start(bot, function(ctx) return job.gank(ctx, { target = function() return target end, path = {}, deadline = 5 }) end)
    local r, t = run(sim, bot)
    T.eq("gank far: late", r.message, "late")
    T.check("gank far: at the deadline", t >= 5 and t <= 5.2)
end

do
    -- The host's commit check ends it (e.g. the target reached its tower): interrupted with the host's message.
    local sim, bot = world(nil, { speed = 300 })
    local target = sim:addHero{ team = 3, x = 3000, y = 0, hp = 300 }
    start(bot, function(ctx)
        return job.gank(ctx, { target = function() return target end, path = {}, commit = function() if sim.t >= 2 then return "tower" end end })
    end)
    local r, t = run(sim, bot)
    T.eq("gank commit: interrupted", r.reason, "interrupted")
    T.eq("gank commit: host message", r.message, "tower")
end

do
    -- Skill: the first attack waits one reaction delay after reaching engage range.
    local function firstAttackGap(react)
        local sim, bot = world({ profile = function() return { react = react, jitter = 0 } end }, { damage = 1000, autoAttack = true, range = 150 })
        local target = sim:addHero{ team = 3, x = 100, y = 0, hp = 100 }
        local engagedAt
        start(bot, function(ctx) return job.gank(ctx, { target = function() return target end, path = {}, onEngage = function(t) engagedAt = t end }) end)
        run(sim, bot)
        for _, a in ipairs(bot.actions) do if a.kind == "attack" then return a.t - engagedAt end end
    end
    local quick, slow = firstAttackGap(0), firstAttackGap(0.5)
    T.check("gank react 0: attacks at once (" .. tostring(quick) .. ")", quick ~= nil and quick <= 1e-6)
    T.check("gank react 0.5: first attack 0.5 s later (" .. tostring(slow) .. ")", slow ~= nil and slow >= 0.5 - 1e-6 and slow <= 0.5 + 2 * DT)
end

do
    -- A neutral fought in the camp that chases out past the radius still holds the camp open until it dies.
    local sim, bot = world(nil, { x = 500, damage = 40, autoAttack = true, secondsPerAttack = 0.5, range = 2000 })
    local n = sim:addNeutral{ x = 600, y = 0, hp = 200 }
    sim:at(0.3, function() n.loc.x = 1500 end)
    start(bot, function(ctx) return job.clearCamp(ctx, { at = { x = 600, y = 0 }, radius = 300 }) end)
    local r = run(sim, bot)
    T.eq("clear chase: cleared", r.message, "cleared")
    T.check("clear chase: only once the chasing neutral is dead", not n.alive)
end

do
    -- Vision: the camp is out of sight from the stand point (trees, night). With `camp.approach` the bot walks in to it
    -- `approachLead` s before the aggro and hits on time ; without it, mistake:no-camp.
    local function attempt(withApproach)
        local sim, bot = world()
        local n = sim:addNeutral{ x = 1300, y = 0, hp = 500 }
        local camp = { stand = { x = 600, y = 0 }, box = box(1300, 0, 100), origin = { x = 1300, y = 0 } }
        if withApproach then camp.approach = { x = 1150, y = 0 } end
        start(bot, function(ctx) return job.stack(ctx, stackPlan{ camp = camp, aggroAt = 6, exitUntil = 10 }) end)
        for _ = 1, 400 do
            n.hidden = math.abs(bot.loc.x - n.loc.x) > 400
            if R.Current(bot) == nil then break end
            frame(sim, bot)
        end
        return R.Last(bot).result, n
    end
    local without = attempt(false)
    -- Without it the camp is only found after the aggro second, too late (here: no-aggro).
    T.check("no approach: fails from a blind stand (" .. tostring(without.message) .. ")", not without.success)
    local with, n = attempt(true)
    T.eq("approach: ok", with.reason, "ok")
    T.check("approach: the camp was hit", n.attackTarget ~= nil)
end

print("jobs [" .. T.runtime() .. "]")
T.finish()
FINISHED = true
