--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
--- Seconds of forecast: a pre-hit's landing plus one attack cycle (about 1.4-1.7 s early) plus the window after it. `judgement`.
____exports.HORIZON = 3.5
--- Forecast sampling step in seconds (under a frame at 30 fps is not needed: windows are judged against WINDOW_MIN).
____exports.STEP = 0.05
--- The shortest kill window a swing is trusted to land in: about one body step (0.167 s in game) plus a little for the timing
-- the verb still gets wrong. `judgement`.
____exports.WINDOW_MIN = 0.2
--- Own towers within this of the bot are read for their attack target (tower range 700 plus the reach of a short walk).
local TOWER_RADIUS = 1200
function ____exports.WindowFrom(hpAt, horizon, mine, from, extra)
    local runStart
    do
        local t = from
        while t <= horizon + 1e-9 do
            local hp = hpAt(t) - (extra ~= nil and t >= extra.t and extra.d or 0)
            if hp <= 0 then
                return runStart ~= nil and t - runStart >= ____exports.WINDOW_MIN and "window" or "dead"
            end
            if hp <= mine then
                if runStart == nil then
                    runStart = t
                end
                if t - runStart >= ____exports.WINDOW_MIN then
                    return "window"
                end
            else
                runStart = nil
            end
            t = t + ____exports.STEP
        end
    end
    return "open"
end
--- The two questions, on a forecast: `t0` our earliest landing (walk plus own hit time), `period` our attack cycle, `lo`/`hi`
-- our damage after armour at the low and high roll. The kill range is the low roll's (as the last-hit verb's `mine`).
function ____exports.Decide(hpAt, horizon, t0, period, lo, hi)
    local now = ____exports.WindowFrom(hpAt, horizon, lo, t0)
    if now == "window" then
        return "window"
    end
    if now == "open" then
        return "open"
    end
    if hpAt(t0) <= hi then
        return "kills"
    end
    for ____, d in ipairs({lo, hi}) do
        if ____exports.WindowFrom(
            hpAt,
            horizon,
            lo,
            t0 + period,
            {t = t0, d = d}
        ) ~= "window" then
            return "no-after"
        end
    end
    return "go"
end
function ____exports.Applies(bot)
    return Ours.On("PreHit") and CoreLastHit.Applies(bot)
end
local notes = {}
--- The decision's numbers for the ev=prehit of the pre-hit on `creep`, if it was this bot's last one.
function ____exports.NoteOf(pid, creep)
    local n = notes[pid]
    return n ~= nil and n.creep == creep and n or nil
end
--- The verdict on one tower's target and, on `go`, the pre-hit. A function with early returns rather than a loop body with
-- `continue`: TSTL's Lua 5.1 `continue` (a `repeat ... until true` block) put a statement after the loop's `break`, which LuaJIT
-- (Dota) refuses to compile, so the module and everything requiring it failed to load in game (prhchk1, 04/11/2026).
local function consider(bot, me, verbs, target)
    if not target:IsAlive() or target:GetTeam() == bot:GetTeam() or not target:IsCreep() or target:IsHero() then
        return {nil, nil}
    end
    local creep = target
    local speed = math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local walk = math.max(
        0,
        GetUnitToUnitDistance(bot, target) - bot:GetAttackRange()
    ) / speed
    if walk > LanePick.MAX_WALK then
        return {{verdict = "far"}, nil}
    end
    local f = verbs.hpForecast(me, creep, ____exports.HORIZON)
    if f.unphasedTower then
        return {{verdict = "phase", creep = creep}, nil}
    end
    local t0 = walk + verbs.ownHitTime(me, creep)
    local ____this_1
    ____this_1 = me
    local ____opt_0 = ____this_1.GetSecondsPerAttack
    local period = ____opt_0 and ____opt_0(____this_1) or 1.7
    local ____this_3
    ____this_3 = me
    local ____opt_2 = ____this_3.GetBaseDamageVariance
    local variance = ____opt_2 and ____opt_2(____this_3) or 0
    local lo = target:GetActualIncomingDamage(
        bot:GetAttackDamage() - variance,
        DamageType.Physical
    )
    local hi = target:GetActualIncomingDamage(
        bot:GetAttackDamage() + variance,
        DamageType.Physical
    )
    local function hpAt(t)
        return verbs.forecastHp(f, t)
    end
    local verdict = ____exports.Decide(
        hpAt,
        ____exports.HORIZON,
        t0,
        period,
        lo,
        hi
    )
    if verdict == "go" then
        for ____, o in ipairs(verbs.laneTargets(me, {within = t0 + period, deny = false})) do
            if o.creep ~= creep and LanePick.Reachable(o) and o.eta <= t0 + period then
                verdict = "lh"
            end
        end
    end
    local note = {
        verdict = verdict,
        creep = creep,
        hp = f.hp,
        t0 = t0,
        lo = lo
    }
    if verdict ~= "go" then
        return {note, nil}
    end
    local dies = math.huge
    do
        local t = 0
        while t <= ____exports.HORIZON and dies == math.huge do
            if hpAt(t) <= 0 then
                dies = t
            end
            t = t + ____exports.STEP
        end
    end
    return {
        note,
        {
            creep = creep,
            kind = "prehit",
            eta = walk,
            due = 0,
            walk = walk,
            dies = dies,
            ranged = LanePick.IsRanged(creep)
        }
    }
end
function ____exports.Find(bot, verbs)
    if not ____exports.Applies(bot) then
        return nil
    end
    local pid = bot:GetPlayerID()
    local me = bot
    local best
    local note
    for ____, tower in ipairs(bot:GetNearbyTowers(TOWER_RADIUS, false) or ({})) do
        local target = tower:GetAttackTarget()
        if best == nil and target ~= nil and target ~= nil then
            local n, pre = unpack(consider(bot, me, verbs, target))
            if n ~= nil and (note == nil or n.verdict ~= "far") then
                note = n
            end
            best = pre
        end
    end
    if note ~= nil then
        notes[pid] = note
        LanePick.NoteVerdict(
            pid,
            DotaTime(),
            note.verdict
        )
    end
    return best
end
return ____exports
