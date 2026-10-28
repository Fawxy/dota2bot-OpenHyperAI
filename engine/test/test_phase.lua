-- Phase: team-level game phase (laning, transition, midgame, push, defend, late) from a host snapshot, with
-- hysteresis (margin + confirm), minimum dwell, urgent phases, team orders, blended state priors and the
-- States prior hook. Runs the compiled bundle.
local T = dofile("test/helpers.lua")
local tasks = dofile("dist/tasks_test.lua")
local P, S, R = tasks.Phase, tasks.States, tasks.Tasks

local RAD, DIRE = 2, 3
local A

local function newAdapter(t)
    A = { t = t or 0, logs = {}, events = {} }
    tasks.init({
        claim = function() end,
        release = function() end,
        now = function() return A.t end,
        log = function(tag, msg) A.logs[#A.logs + 1] = tag .. ": " .. msg end,
        enabled = function() return true end,
        event = function(name, fields)
            local e = { name = name, t = A.t }
            for _, kv in ipairs(fields) do e[kv[1]] = kv[2] end
            A.events[#A.events + 1] = e
        end,
    })
    P.Reset()
    P.configure({ interval = 0.5, margin = 0.1, confirm = 2, urgentConfirm = 1, minDwell = 20, blend = 4 })
end

local function towers(t1, t2, t3) return { t1 = t1 or 3, t2 = t2 or 3, t3 = t3 or 3 } end

-- A quiet, even game at `time`: all towers up, nobody dead, nothing threatened.
local function snap(time, over)
    local s = {
        time = time,
        towers = { ours = towers(), theirs = towers() },
        netWorth = { ours = 10000, theirs = 10000 },
        alive = { ours = 5, theirs = 5 },
        threat = { heroes = 0, tier = 0 },
        waves = { 0, 0, 0 },
    }
    for k, v in pairs(over or {}) do s[k] = v end
    return s
end

-- Advances game and adapter time together, ticking the team every 0.1 s with `make(time)`.
local function run(team, secs, make)
    local name
    for _ = 1, math.floor(secs / 0.1 + 0.5) do
        name = P.Tick(team, function() return make(A.t) end)
        A.t = A.t + 0.1
    end
    return name
end

local function cur(team) return (P.Current(team) or {}).name end

local function phaseEvents(team)
    local out = {}
    for _, e in ipairs(A.events) do
        if e.name == "phase" and (team == nil or e.team == team) then out[#out + 1] = e end
    end
    return out
end

-- 1. Laning until 10:00 with every T1 up, then transition (replays.md: laning over at first T1 or 10:00).
do
    newAdapter(0)
    run(RAD, 30, function(t) return snap(t) end)
    T.eq("starts in laning", cur(RAD), "laning")
    T.eq("one start event", #phaseEvents(RAD), 1)
    T.eq("start event why", phaseEvents(RAD)[1].why, "start")
    A.t = 595
    run(RAD, 4, function(t) return snap(t) end)
    T.eq("still laning just before 10:00", cur(RAD), "laning")
    run(RAD, 1.5, function(t) return snap(t) end)
    T.eq("not switched before confirm", cur(RAD), "laning")
    run(RAD, 2.5, function(t) return snap(t) end)
    T.eq("transition after 10:00 + confirm", cur(RAD), "transition")
    local ev = phaseEvents(RAD)
    T.eq("change event from", ev[#ev].from, "laning")
    T.eq("change event to", ev[#ev].to, "transition")
end

-- 2. The first T1 falling ends laning early (8:44, the pub p25).
do
    newAdapter(500)
    run(RAD, 30, function(t) return snap(t) end)
    T.eq("laning at 8:20", cur(RAD), "laning")
    local down = function(t) return snap(t, { towers = { ours = towers(), theirs = towers(2) } }) end
    run(RAD, 3, down)
    T.eq("enemy T1 down: transition", cur(RAD), "transition")
end

-- 3. Snapshots are built at most once per interval.
do
    newAdapter(0)
    local calls = 0
    for _ = 1, 50 do
        P.Tick(RAD, function()
            calls = calls + 1
            return snap(A.t)
        end)
        A.t = A.t + 0.05
    end
    T.check("2.5 s at 0.05 s frames builds 5-6 snapshots (got " .. calls .. ")", calls >= 5 and calls <= 6)
end

-- 4. Minimum dwell: an advantage right after midgame starts waits out the dwell; margin keeps a small edge out.
do
    newAdapter(1000)
    local even = function(t) return snap(t, { towers = { ours = towers(0), theirs = towers(0) } }) end
    run(RAD, 5, even)
    T.eq("all T1s down at 16:40: midgame", cur(RAD), "midgame")
    local ahead = function(t) return snap(t, { towers = { ours = towers(0), theirs = towers(0) }, alive = { ours = 5, theirs = 3 } }) end
    run(RAD, 10, ahead)
    T.eq("two enemies dead inside the dwell: still midgame", cur(RAD), "midgame")
    run(RAD, 10, ahead)
    T.eq("after the dwell: push", cur(RAD), "push")

    newAdapter(1000)
    run(RAD, 30, even)
    local slight = function(t) return snap(t, { towers = { ours = towers(0), theirs = towers(0) }, alive = { ours = 5, theirs = 4 } }) end
    run(RAD, 10, slight)
    T.eq("one enemy dead is inside the margin: no push", cur(RAD), "midgame")
end

-- 5. Hysteresis on an urgent phase: threat blips shorter than urgentConfirm don't enter defend, longer ones
--    skip the dwell; leaving needs the threat gone for confirm.
do
    newAdapter(1200)
    local quiet = function(t) return snap(t, { towers = { ours = towers(1), theirs = towers(1) } }) end
    local threat = function(t) return snap(t, { towers = { ours = towers(1), theirs = towers(1) }, threat = { heroes = 3, tier = 2 } }) end
    run(RAD, 5, quiet)
    T.eq("midgame", cur(RAD), "midgame")
    for _ = 1, 5 do
        run(RAD, 0.5, threat)
        run(RAD, 0.5, quiet)
    end
    T.eq("0.5 s threat blips: no defend", cur(RAD), "midgame")
    run(RAD, 1.6, threat)
    T.eq("threat held past urgentConfirm: defend despite dwell", cur(RAD), "defend")
    run(RAD, 1, quiet)
    run(RAD, 0.5, threat)
    T.eq("1 s of quiet does not leave defend", cur(RAD), "defend")
    run(RAD, 3, quiet)
    T.eq("threat gone past confirm: back to midgame", cur(RAD), "midgame")
end

-- 6. A two-hero dive on a T1 during laning is a lane matter (a TP defend), not a team phase.
do
    newAdapter(300)
    run(RAD, 5, function(t) return snap(t, { threat = { heroes = 2, tier = 1 } }) end)
    T.eq("2 heroes on a T1 at 5:00: laning", cur(RAD), "laning")
    run(RAD, 3, function(t) return snap(t, { threat = { heroes = 3, tier = 1 } }) end)
    T.eq("3 heroes on a T1 at 5:00: defend", cur(RAD), "defend")
end

-- 7. Late game: a T3 down on either side, or 35:00.
do
    newAdapter(1500)
    run(RAD, 30, function(t) return snap(t, { towers = { ours = towers(0, 1), theirs = towers(0, 0) } }) end)
    T.eq("T2s down: midgame", cur(RAD), "midgame")
    run(RAD, 3, function(t) return snap(t, { towers = { ours = towers(0, 1), theirs = towers(0, 0, 2) } }) end)
    T.eq("enemy T3 down: late", cur(RAD), "late")
    newAdapter(2100)
    run(RAD, 5, function(t) return snap(t, { towers = { ours = towers(1, 2), theirs = towers(1, 2) } }) end)
    T.eq("35:00 with towers up: late", cur(RAD), "late")
end

-- 8. Teams are independent.
do
    newAdapter(1200)
    local all0 = { ours = towers(0), theirs = towers(0) }
    run(RAD, 5, function(t) return snap(t, { towers = all0 }) end)
    run(DIRE, 5, function(t) return snap(t, { towers = all0, threat = { heroes = 3, tier = 2 } }) end)
    T.eq("radiant midgame", cur(RAD), "midgame")
    T.eq("dire defend", cur(DIRE), "defend")
end

-- 9. Team orders: an order wins at once and holds for its duration; expiry hands back to selection.
do
    newAdapter(1200)
    local q = function(t) return snap(t, { towers = { ours = towers(0), theirs = towers(0) } }) end
    run(RAD, 5, q)
    T.eq("unknown phase order refused", P.Order(RAD, "rosh", 30, "human"), false)
    T.eq("refused order changes nothing", cur(RAD), "midgame")
    T.eq("push order accepted", P.Order(RAD, "push", 10, "human"), true)
    T.eq("ordered phase is current at once", cur(RAD), "push")
    T.eq("current reports the order source", P.Current(RAD).ordered, "human")
    local ev = phaseEvents(RAD)
    T.eq("order event why", ev[#ev].why, "order")
    run(RAD, 8, q)
    T.eq("order holds against selection", cur(RAD), "push")
    run(RAD, 6, q)
    T.eq("after expiry + confirm: midgame again", cur(RAD), "midgame")
    T.eq("no order after expiry", P.Current(RAD).ordered, nil)

    P.Order(RAD, "defend", 60, "human")
    P.ClearOrder(RAD)
    run(RAD, 3, q)
    T.eq("cleared order: back to midgame", cur(RAD), "midgame")
end

-- 10. Priors: phase multipliers on state scores, blended in over `blend` seconds, clamped, n/a passes through.
do
    newAdapter(1000)
    local q = function(t) return snap(t, { towers = { ours = towers(0), theirs = towers(0) } }) end
    T.eq("no phase yet: raw score", P.Apply(RAD, "laning", 0.5), 0.5)
    run(RAD, 0.1, q)
    T.eq("first phase applies in full", cur(RAD), "midgame")
    T.check("midgame: laning damped", P.Apply(RAD, "laning", 0.5) < 0.25)
    T.check("midgame: farm boosted", P.Apply(RAD, "farm", 0.4) > 0.4)
    T.eq("n/a stays n/a", P.Apply(RAD, "farm", nil), nil)
    T.eq("unknown state: raw", P.Apply(RAD, "shop", 0.3), 0.3)
    T.check("clamped to 1", P.Apply(RAD, "farm", 0.95) <= 1)
    P.Order(RAD, "defend", 60, "test")
    local farmMid = P.Bias(RAD, "farm")
    run(RAD, 2, q)
    local farmBlend = P.Bias(RAD, "farm")
    run(RAD, 3, q)
    local farmDefend = P.Bias(RAD, "farm")
    T.check("defend damps farm", farmDefend < 1)
    T.check("half-way through the blend lies between (" .. farmMid .. " > " .. farmBlend .. " > " .. farmDefend .. ")",
        farmBlend < farmMid and farmBlend > farmDefend)
    T.check("defend raises the defend mode desire", P.Desire(RAD, "defend") > 1)
    T.eq("unknown desire key: 1", P.Desire(RAD, "shop"), 1)
end

-- 11. A failing snapshot builder keeps the phase and logs.
do
    newAdapter(100)
    run(RAD, 1, function(t) return snap(t) end)
    A.t = A.t + 1
    P.Tick(RAD, function() error("boom") end)
    T.eq("phase kept on builder error", cur(RAD), "laning")
    local logged = false
    for _, l in ipairs(A.logs) do if l:find("boom") then logged = true end end
    T.check("builder error logged", logged)
end

-- 12. Custom phase specs replace the Dota set for a team.
do
    newAdapter(0)
    P.define(RAD, {
        { name = "calm", score = function() return 0.3 end },
        { name = "storm", score = function(s) return s.storm and 0.9 or nil end, bias = { farm = 0 } },
    })
    run(RAD, 1, function(t) return { time = t } end)
    T.eq("custom: calm", cur(RAD), "calm")
    run(RAD, 30, function(t) return { time = t, storm = true } end)
    T.eq("custom: storm", cur(RAD), "storm")
    T.eq("custom bias zeroes farm", P.Apply(RAD, "farm", 0.8), 0)
end

-- 13. States consume the priors through SetPrior: the same scorers pick laning in laning and farm in midgame.
do
    newAdapter(0)
    S.configure({ interval = 0.25, sticky = 0.1, minDwell = 3, jobBreak = 0.9, cooldown = 5, restart = 1 })
    S.SetOwned(function() return false end)
    local bot = { mode = 4 }
    function bot:GetPlayerID() return 77 end
    function bot:GetTeam() return RAD end
    function bot:IsAlive() return true end
    function bot:GetActiveMode() return self.mode end
    local body = tasks.Testing.counting(1e9, {})
    S.define(bot, {
        { name = "laning", kind = "posture", host = 4, score = function() return 0.5 end, body = body },
        { name = "farm", kind = "posture", host = 6, score = function() return 0.4 end, body = body },
    })
    S.SetPrior(P.Prior())
    local function frames(secs, make)
        for _ = 1, math.floor(secs / 0.1 + 0.5) do
            P.Tick(RAD, function() return make(A.t) end)
            S.Tick(bot)
            R.Tick(bot)
            A.t = A.t + 0.1
        end
    end
    frames(5, function(t) return snap(t) end)
    T.eq("laning phase: laning state", S.Current(bot).name, "laning")
    A.t = 1000
    frames(10, function(t) return snap(t, { towers = { ours = towers(0), theirs = towers(0) } }) end)
    T.eq("midgame phase: farm state", S.Current(bot).name, "farm")
    S.SetPrior(function() error("bad prior") end)
    A.t = 2000
    frames(1, function(t) return snap(t) end)
    local logged = false
    for _, l in ipairs(A.logs) do if l:find("bad prior") then logged = true end end
    T.check("a failing prior is logged, not raised", logged)
    S.SetPrior(nil)
    S.Forget(bot)
end

print("phase [" .. T.runtime() .. "]")
T.finish()
