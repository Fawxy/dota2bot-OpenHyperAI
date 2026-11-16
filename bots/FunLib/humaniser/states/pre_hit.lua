--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__SparseArrayNew(...)
    local sparseArray = {...}
    sparseArray.sparseLength = __TS__CountVarargs(...)
    return sparseArray
end

local function __TS__SparseArrayPush(sparseArray, ...)
    local args = {...}
    local argsLen = __TS__CountVarargs(...)
    local listLen = sparseArray.sparseLength
    for i = 1, argsLen do
        sparseArray[listLen + i] = args[i]
    end
    sparseArray.sparseLength = listLen + argsLen
end

local function __TS__SparseArraySpread(sparseArray)
    local _unpack = unpack or table.unpack
    return _unpack(sparseArray, 1, sparseArray.sparseLength)
end

local function __TS__StringAccess(self, index)
    if index >= 0 and index < #self then
        return string.sub(self, index + 1, index + 1)
    end
end

local __TS__Symbol, Symbol
do
    local symbolMetatable = {__tostring = function(self)
        return ("Symbol(" .. (self.description or "")) .. ")"
    end}
    function __TS__Symbol(description)
        return setmetatable({description = description}, symbolMetatable)
    end
    Symbol = {
        asyncDispose = __TS__Symbol("Symbol.asyncDispose"),
        dispose = __TS__Symbol("Symbol.dispose"),
        iterator = __TS__Symbol("Symbol.iterator"),
        hasInstance = __TS__Symbol("Symbol.hasInstance"),
        species = __TS__Symbol("Symbol.species"),
        toStringTag = __TS__Symbol("Symbol.toStringTag")
    }
end

local __TS__Iterator
do
    local function iteratorGeneratorStep(self)
        local co = self.____coroutine
        local status, value = coroutine.resume(co)
        if not status then
            error(value, 0)
        end
        if coroutine.status(co) == "dead" then
            return
        end
        return true, value
    end
    local function iteratorIteratorStep(self)
        local result = self:next()
        if result.done then
            return
        end
        return true, result.value
    end
    local function iteratorStringStep(self, index)
        index = index + 1
        if index > #self then
            return
        end
        return index, string.sub(self, index, index)
    end
    function __TS__Iterator(iterable)
        if type(iterable) == "string" then
            return iteratorStringStep, iterable, 0
        elseif iterable.____coroutine ~= nil then
            return iteratorGeneratorStep, iterable
        elseif iterable[Symbol.iterator] then
            local iterator = iterable[Symbol.iterator](iterable)
            return iteratorIteratorStep, iterator
        else
            return ipairs(iterable)
        end
    end
end

local __TS__Unpack = table.unpack or unpack

local function __TS__Spread(iterable)
    local arr = {}
    if type(iterable) == "string" then
        for i = 0, #iterable - 1 do
            arr[i + 1] = __TS__StringAccess(iterable, i)
        end
    else
        local len = 0
        for ____, item in __TS__Iterator(iterable) do
            len = len + 1
            arr[len] = item
        end
    end
    return __TS__Unpack(arr)
end
-- End of Lua Library inline imports
local ____exports = {}
local better, landings, killFrom, search, decide, notePick, startWatch, sampleWatch, noteFires, forecastDeath, picks, PICK_GAP, WATCH_FOR, WATCH_EVERY, WATCH_SAMPLES, WATCH_FIRES, watches
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
function better(a, b)
    if b == nil then
        return true
    end
    if math.abs(a.odds - b.odds) > 1e-9 then
        return a.odds > b.odds
    end
    if a.margin ~= b.margin then
        return a.margin > b.margin
    end
    if #a.swings ~= #b.swings then
        return #a.swings < #b.swings
    end
    return a.swings[#a.swings] < b.swings[#b.swings]
end
function landings(towers, earliest)
    local out = {}
    local clear = true
    for ____, t in ipairs(towers) do
        if t > earliest - ____exports.AFTER and t <= earliest then
            clear = false
        end
    end
    if clear then
        out[#out + 1] = earliest
    end
    for ____, t in ipairs(towers) do
        if t + ____exports.AFTER > earliest then
            out[#out + 1] = t + ____exports.AFTER
        end
    end
    return out
end
function killFrom(hpAt, horizon, towers, earliest, dealt, lo, err)
    local odds = 0
    local best
    for ____, at in ipairs(landings(towers, earliest)) do
        do
            local __continue23
            repeat
                if at > horizon then
                    break
                end
                local hp = hpAt(at) - dealt
                local p = err(at, hp) - err(at, hp - lo)
                if p <= 0 then
                    __continue23 = true
                    break
                end
                odds = odds + p
                local here = {
                    swings = {at},
                    hpKill = hp,
                    margin = math.min(hp, lo - hp),
                    odds = p
                }
                if better(here, best) then
                    best = here
                end
                __continue23 = true
            until true
            if not __continue23 then
                break
            end
        end
    end
    if best == nil then
        return nil
    end
    best.odds = math.min(1, odds)
    return best
end
function search(hpAt, horizon, towers, earliest, dealt, pre, period, lo, mean, err)
    local best = killFrom(
        hpAt,
        horizon,
        towers,
        earliest,
        dealt,
        lo,
        err
    )
    if pre >= ____exports.MAX_PREHITS then
        return best
    end
    for ____, at in ipairs(landings(towers, earliest)) do
        if at > horizon then
            break
        end
        local hp = hpAt(at) - dealt
        if hp > lo then
            local rest = search(
                hpAt,
                horizon,
                towers,
                at + period,
                dealt + mean,
                pre + 1,
                period,
                lo,
                mean,
                err
            )
            if rest ~= nil then
                local plan = {
                    swings = {
                        at,
                        unpack(rest.swings)
                    },
                    hpKill = rest.hpKill,
                    margin = rest.margin,
                    odds = rest.odds
                }
                if better(plan, best) then
                    best = plan
                end
            end
        end
    end
    return best
end
--- The plan for a creep whose forecast HP without our hits is `hpAt` and whose tower hits land at `towers` (seconds from now,
-- sorted): our first swing can land at `first` (the walk plus our hit time) and every `period` after one, our low-roll damage
-- after armour is `lo` (the kill range's top, as the last-hit verb's `mine`) and our mean damage `mean` (what a pre-hit takes);
-- `err` the forecast's error (default the fitted one). Undefined when no plan within the horizon has a chance of a kill.
-- A plan of our swings on one creep: when each lands (seconds from now), the last one the kill.
function ____exports.Plan(hpAt, horizon, towers, first, period, lo, mean, err)
    if err == nil then
        err = ____exports.FittedError
    end
    return search(
        hpAt,
        horizon,
        towers,
        first,
        0,
        0,
        period,
        lo,
        mean,
        err
    )
end
function decide(bot, me, verbs, tower, target, walk, f, hpAt, towers, horizon, next, freeUntil)
    if freeUntil == nil then
        freeUntil = math.huge
    end
    local creep = target
    local first = walk + verbs.ownHitTime(me, creep)
    local ____this_5
    ____this_5 = me
    local ____opt_4 = ____this_5.GetSecondsPerAttack
    local read = ____opt_4 and ____opt_4(____this_5)
    local period = read ~= nil and read > 0 and read or WorldFacts.Fallback("attack_period", 1.7)
    local ____this_7
    ____this_7 = me
    local ____opt_6 = ____this_7.GetBaseDamageVariance
    local variance = ____opt_6 and ____opt_6(____this_7) or 0
    local lo = target:GetActualIncomingDamage(
        bot:GetAttackDamage() - variance,
        DamageType.Physical
    )
    local mean = target:GetActualIncomingDamage(
        bot:GetAttackDamage(),
        DamageType.Physical
    )
    local plan = ____exports.Plan(
        hpAt,
        horizon,
        towers,
        first,
        period,
        lo,
        mean
    )
    local verdict
    if plan == nil then
        verdict = "none"
    elseif plan.swings[1] > first + 0.000001 then
        verdict = "wait"
    elseif #plan.swings == 1 then
        verdict = "kills"
    else
        verdict = "go"
    end
    if verdict == "go" and first + period > freeUntil then
        verdict = "lh"
    end
    if verdict == "go" then
        for ____, o in ipairs(verbs.laneTargets(me, {within = first + period, deny = false})) do
            if o.creep ~= creep and LanePick.Reachable(o) and o.eta <= first + period then
                verdict = "lh"
            end
        end
    end
    local ____verdict_9 = verdict
    local ____creep_10 = creep
    local ____f_hp_11 = f.hp
    local ____lo_12 = lo
    local ____plan_13 = plan
    local ____next_8
    if next then
        ____next_8 = true
    else
        ____next_8 = nil
    end
    local note = {
        verdict = ____verdict_9,
        creep = ____creep_10,
        hp = ____f_hp_11,
        t0 = first,
        lo = ____lo_12,
        plan = ____plan_13,
        next = ____next_8
    }
    if verdict ~= "go" then
        return {note, nil}
    end
    startWatch(
        bot,
        verbs,
        tower,
        target,
        f,
        lo,
        next
    )
    local dies = math.huge
    do
        local t = 0
        while t <= horizon and dies == math.huge do
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
function notePick(tower, current, next, creeps)
    local prev = picks[tower]
    if current == nil then
        return
    end
    if prev ~= nil and prev.target ~= current and DotaTime() - prev.at <= PICK_GAP then
        local reach = WorldFacts.TowerReach(tower, 788)
        local d = GetUnitToUnitDistance(tower, current)
        local rank = 1
        local n = 0
        local dn = math.huge
        local natk = 0
        for ____, c in ipairs(creeps) do
            do
                local __continue100
                repeat
                    if c:IsNull() or not c:IsAlive() then
                        __continue100 = true
                        break
                    end
                    local dc = GetUnitToUnitDistance(tower, c)
                    if dc > reach + (c:GetBoundingRadius() or 0) then
                        __continue100 = true
                        break
                    end
                    n = n + 1
                    if c ~= current and dc < d then
                        rank = rank + 1
                    end
                    if dc < dn then
                        dn = dc
                    end
                    if c:GetAttackTarget() == tower then
                        natk = natk + 1
                    end
                    __continue100 = true
                until true
                if not __continue100 then
                    break
                end
            end
        end
        local ct = current:GetAttackTarget()
        Telemetry.Event(
            "tower_pick",
            {
                {"ok", prev.predicted == current},
                {"rank", rank},
                {"n", n},
                {
                    "d",
                    math.floor(d)
                },
                {
                    "dn",
                    dn == math.huge and -1 or math.floor(dn)
                },
                {"atk", ct == tower},
                {
                    "atkh",
                    ct ~= nil and ct ~= nil and not ct:IsNull() and ct:IsHero()
                },
                {"natk", natk},
                {
                    "rg",
                    LanePick.IsRanged(current)
                },
                {
                    "prev",
                    not prev.target:IsNull() and prev.target:IsAlive()
                }
            }
        )
    end
    picks[tower] = {
        target = current,
        predicted = next,
        at = DotaTime()
    }
end
function startWatch(bot, verbs, tower, creep, f, lo, next)
    local pid = bot:GetPlayerID()
    if watches[pid] ~= nil then
        return
    end
    local kt = 0
    local kc = 0
    local kh = 0
    local ks = 0
    local td = -1
    for ____, h in ipairs(f.hits) do
        do
            local __continue109
            repeat
                if h.t > 1 then
                    __continue109 = true
                    break
                end
                if h.by == "tower" then
                    kt = kt + 1
                    td = h.damage
                elseif h.by == "creep" then
                    kc = kc + 1
                elseif h.by == "hero" then
                    kh = kh + 1
                else
                    ks = ks + 1
                end
                __continue109 = true
            until true
            if not __continue109 then
                break
            end
        end
    end
    local ac = 0
    local ah = 0
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(1600, false) or ({})) do
        if c:GetAttackTarget() == creep then
            ac = ac + 1
        end
    end
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, false, 0) or ({})) do
        if h ~= bot and h:GetAttackTarget() == creep then
            ah = ah + 1
        end
    end
    local tw = creep:GetActualIncomingDamage(
        tower:GetAttackDamage(),
        DamageType.Physical
    )
    local ____creep_24 = creep
    local ____f_25 = f
    local ____DotaTime_result_26 = DotaTime()
    local ____temp_27 = -1
    local ____temp_28 = {}
    local ____temp_29 = {}
    local ____GameTime_result_30 = GameTime()
    local ____temp_31 = {}
    local ____temp_32 = {}
    local ____array_23 = __TS__SparseArrayNew(
        {"pid", pid},
        {
            "hp",
            math.floor(f.hp)
        },
        {
            "lo",
            math.floor(lo)
        },
        {
            "tw",
            math.floor(tw)
        },
        {
            "td",
            math.floor(td)
        }
    )
    local ____math_floor_21 = math.floor
    local ____this_20
    ____this_20 = tower
    local ____opt_19 = ____this_20.GetSecondsPerAttack
    __TS__SparseArrayPush(
        ____array_23,
        {
            "twp",
            ____math_floor_21((____opt_19 and ____opt_19(____this_20) or -1) * 100) / 100
        },
        {"kt", kt},
        {"kc", kc},
        {"kh", kh},
        {"ks", ks},
        {"nu", #f.unphasedHits},
        {
            "ud",
            math.floor(f.unphased)
        },
        {"ac", ac},
        {"ah", ah}
    )
    local ____next_22
    if next then
        ____next_22 = true
    else
        ____next_22 = nil
    end
    __TS__SparseArrayPush(____array_23, {"nx", ____next_22})
    watches[pid] = {
        creep = ____creep_24,
        f = ____f_25,
        t = ____DotaTime_result_26,
        last = ____temp_27,
        hs = ____temp_28,
        fs = ____temp_29,
        g0 = ____GameTime_result_30,
        lat = ____temp_31,
        fire = ____temp_32,
        fields = {__TS__SparseArraySpread(____array_23)}
    }
    sampleWatch(bot, verbs)
end
function sampleWatch(bot, verbs)
    local pid = bot:GetPlayerID()
    local w = watches[pid]
    if w == nil then
        return
    end
    local dt = DotaTime() - w.t
    local alive = not w.creep:IsNull() and w.creep:IsAlive()
    if alive and dt < WATCH_FOR and #w.hs < WATCH_SAMPLES then
        noteFires(bot, w)
        if dt - w.last < WATCH_EVERY then
            return
        end
        w.last = dt
        local r = math.floor(dt * 100) / 100
        local ____w_hs_33 = w.hs
        ____w_hs_33[#____w_hs_33 + 1] = (tostring(r) .. ":") .. tostring(math.floor(w.creep:GetHealth()))
        local ____w_fs_34 = w.fs
        ____w_fs_34[#____w_fs_34 + 1] = tostring(math.floor(verbs.forecastHp(w.f, dt)))
        return
    end
    watches[pid] = nil
    local ____Telemetry_Event_36 = Telemetry.Event
    local ____array_35 = __TS__SparseArrayNew(__TS__Spread(w.fields))
    __TS__SparseArrayPush(
        ____array_35,
        {
            "end",
            math.floor(dt * 100) / 100
        },
        {"dead", not alive},
        {
            "fdies",
            forecastDeath(verbs, w.f)
        },
        {
            "hs",
            table.concat(w.hs, ",")
        },
        {
            "fs",
            table.concat(w.fs, ",")
        },
        {
            "fire",
            table.concat(w.fire, ",")
        }
    )
    ____Telemetry_Event_36(
        "prehit_fc",
        {__TS__SparseArraySpread(____array_35)}
    )
end
function noteFires(bot, w)
    local function note(u, kind)
        if u:GetAttackTarget() ~= w.creep then
            return
        end
        local at = u:GetLastAttackTime()
        local before = w.lat[u]
        w.lat[u] = at
        if at > w.g0 and (before == nil or at > before) and #w.fire < WATCH_FIRES then
            local ____w_fire_37 = w.fire
            ____w_fire_37[#____w_fire_37 + 1] = (kind .. ":") .. tostring(math.floor((at - w.g0) * 100) / 100)
        end
    end
    note(bot, "S")
    for ____, u in ipairs(bot:GetNearbyTowers(1600, false) or ({})) do
        note(u, "T")
    end
    for ____, u in ipairs(bot:GetNearbyTowers(1600, true) or ({})) do
        note(u, "X")
    end
    for ____, u in ipairs(bot:GetNearbyLaneCreeps(1600, false) or ({})) do
        note(u, "C")
    end
    for ____, u in ipairs(bot:GetNearbyLaneCreeps(1600, true) or ({})) do
        note(u, "E")
    end
    for ____, u in ipairs(bot:GetNearbyHeroes(1600, false, 0) or ({})) do
        if u ~= bot then
            note(u, "H")
        end
    end
    for ____, u in ipairs(bot:GetNearbyHeroes(1600, true, 0) or ({})) do
        note(u, "D")
    end
end
function forecastDeath(verbs, f)
    do
        local t = 0
        while t <= ____exports.HORIZON do
            if verbs.forecastHp(f, t) <= 0 then
                return math.floor(t * 100) / 100
            end
            t = t + ____exports.STEP
        end
    end
    return -1
end
--- Seconds of forecast: two pre-hits and the kill (about 0.7 s to the first landing, then two attack cycles of 1.4-1.7 s). `judgement`.
____exports.HORIZON = 4.5
--- Forecast sampling step in seconds, for the forecast's own death time.
____exports.STEP = 0.05
--- Seconds after a tower's hit lands that our own may land and count as after it: the verb relies on a hit one server tick
-- before its own, plus a frame of slack for the timing it still gets wrong. `judgement`.
____exports.AFTER = 0.1
--- The most pre-hits one plan spends before its kill: a third would reach past the horizon at early attack speeds. `judgement`.
____exports.MAX_PREHITS = 2
--- Own towers within this of the bot are read for their attack target (tower range 700 plus the reach of a short walk).
local TOWER_RADIUS = 1200
--- Forecast for the tower's predicted next target (slice prehit-next): its tower hits start only once the current target
-- dies, about 1-2 s out, and a creep takes four or more tower hits, so the plan needs longer than HORIZON. `judgement`.
____exports.NEXT_HORIZON = 6
--- Seconds from the current target's death to the tower's attack on the next leaving (acquiring and its wind-up). `judgement`.
____exports.NEXT_TURN = 0.1
--- Tower attack projectile speed when the read fails (Dota towers: 750).
local TOWER_PROJECTILE = 750
--- The forecast's error on a creep our tower is hitting: real HP below the forecast's, our own hits removed, at a time ahead
-- (`ev=prehit_fc`, 353 probes from h2hhighstand1 and rig tower-prehit on1, 17/11/2026; `fitted`). It is 0 in about 40% of
-- samples and 20-120 HP in most of the rest: our creeps join that the forecast, which counts current attackers, cannot see;
-- the negative tail is a forecast tower hit landing late. One row per half second ahead (the last for 2 s and beyond): the
-- error at the probabilities `ERROR_P`.
____exports.ERROR_P = {
    0.02,
    0.1,
    0.2,
    0.3,
    0.4,
    0.5,
    0.6,
    0.7,
    0.8,
    0.9,
    0.98
}
____exports.ERROR = {
    {
        -80,
        -12,
        -1,
        0,
        0,
        0,
        2,
        7,
        17,
        64,
        107
    },
    {
        -75,
        -41,
        -1,
        1,
        4,
        9,
        25,
        49,
        72,
        90,
        133
    },
    {
        -78,
        -3,
        1,
        4,
        7,
        18,
        28,
        41,
        65,
        87,
        133
    },
    {
        -72,
        -3,
        2,
        5,
        10,
        21,
        34,
        50,
        64,
        92,
        173
    },
    {
        -72,
        -1,
        3,
        6,
        11,
        26,
        40,
        61,
        84,
        110,
        176
    }
}
--- HP beyond the table's end points over which the chance runs out to 0 and to 1. `judgement`.
local ERROR_TAIL = 20
____exports.FittedError = function(t, x)
    local row = ____exports.ERROR[math.min(
        #____exports.ERROR - 1,
        math.max(
            0,
            math.floor(t / 0.5)
        )
    ) + 1]
    local n = #row
    if x < row[1] - ERROR_TAIL then
        return 0
    end
    if x < row[1] then
        return ____exports.ERROR_P[1] * (x - (row[1] - ERROR_TAIL)) / ERROR_TAIL
    end
    if x >= row[n] + ERROR_TAIL then
        return 1
    end
    if x >= row[n] then
        return ____exports.ERROR_P[n] + (1 - ____exports.ERROR_P[n]) * (x - row[n]) / ERROR_TAIL
    end
    local i = 0
    while i + 1 < n and row[i + 1 + 1] <= x do
        i = i + 1
    end
    local span = row[i + 1 + 1] - row[i + 1]
    return ____exports.ERROR_P[i + 1] + (____exports.ERROR_P[i + 1 + 1] - ____exports.ERROR_P[i + 1]) * (x - row[i + 1]) / span
end
--- No error: the forecast is the creep's HP (the planner before odds). A kill on exactly lo counts, on exactly 0 does not.
____exports.NoError = function(_t, x) return x > 0 and 1 or 0 end
function ____exports.Applies(bot)
    return Ours.On("PreHit") and CoreLastHit.Applies(bot)
end
--- The tower's next target once `current` dies, as read now: the enemy lane creep in its reach nearest the tower, other than
-- `current` (the hypothesis ev=tower_pick grades; the published rule could not be read, 17/11/2026). `creeps` the enemy lane
-- creeps near; `reach` the tower's attack range plus its radius.
function ____exports.NextTarget(tower, current, creeps, reach)
    local best
    local bestD = math.huge
    for ____, c in ipairs(creeps) do
        do
            local __continue40
            repeat
                if c == current or c:IsNull() or not c:IsAlive() then
                    __continue40 = true
                    break
                end
                local d = GetUnitToUnitDistance(tower, c)
                if d <= reach + (c:GetBoundingRadius() or 0) and d < bestD then
                    best = c
                    bestD = d
                end
                __continue40 = true
            until true
            if not __continue40 then
                break
            end
        end
    end
    return best
end
--- When the tower's hits land on its next target (seconds from now, up to `horizon`): its current target dies at `dies`; its
-- last hit on it landed at `last` (undefined if none before the death) after `travelCur` s of flight; the next is `travelNext`
-- away in flight. The tower fires on the next once its attack is ready (`period` after the last fired) and not before the
-- death plus NEXT_TURN, then every `period`.
function ____exports.NextTowerHits(dies, last, travelCur, travelNext, period, horizon)
    local fire = dies + ____exports.NEXT_TURN
    if last ~= nil then
        fire = math.max(fire, last - travelCur + period)
    end
    local out = {}
    do
        local t = fire + travelNext
        while t <= horizon do
            out[#out + 1] = t
            t = t + period
        end
    end
    return out
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
local function consider(bot, me, verbs, tower, target)
    if target:IsNull() or not target:IsAlive() or target:GetTeam() == bot:GetTeam() or not target:IsCreep() or target:IsHero() then
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
    local towers = {}
    for ____, h in ipairs(f.hits) do
        if h.by == "tower" then
            towers[#towers + 1] = h.t
        end
    end
    local function hpAt(t)
        return verbs.forecastHp(f, t)
    end
    return decide(
        bot,
        me,
        verbs,
        tower,
        target,
        walk,
        f,
        hpAt,
        towers,
        ____exports.HORIZON,
        false
    )
end
--- The verdict on the tower's predicted next target (`NextTarget`) while it is still on `current`: the current one's forecast
-- gives its death and the tower's last hit on it, `NextTowerHits` the tower's hits on the next from then, added to the next
-- creep's own forecast (its current attackers, no tower).
local function considerNext(bot, me, verbs, tower, current, next, freeUntil)
    if current:IsNull() or not current:IsAlive() or next:IsNull() or not next:IsAlive() then
        return {nil, nil}
    end
    local speed = math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local walk = math.max(
        0,
        GetUnitToUnitDistance(bot, next) - bot:GetAttackRange()
    ) / speed
    if walk > LanePick.MAX_WALK then
        return {{verdict = "far", next = true}, nil}
    end
    local cur = current
    local fc = verbs.hpForecast(me, cur, ____exports.NEXT_HORIZON)
    if fc.unphasedTower then
        return {{verdict = "phase", next = true}, nil}
    end
    local dies
    do
        local t = 0
        while t <= ____exports.NEXT_HORIZON and dies == nil do
            if verbs.forecastHp(fc, t) <= 0 then
                dies = t
            end
            t = t + ____exports.STEP
        end
    end
    if dies == nil then
        return {{verdict = "none", next = true}, nil}
    end
    local last
    for ____, h in ipairs(fc.hits) do
        if h.by == "tower" and h.t <= dies + ____exports.STEP then
            last = last == nil and h.t or math.max(last, h.t)
        end
    end
    local tu = tower
    local ____opt_0 = tu.GetSecondsPerAttack
    local read = ____opt_0 and ____opt_0(tu)
    local tperiod = read ~= nil and read > 0 and read or 1
    local ____opt_2 = tu.GetAttackProjectileSpeed
    local ps = ____opt_2 and ____opt_2(tu)
    local pspeed = ps ~= nil and ps > 0 and ps or TOWER_PROJECTILE
    local towers = ____exports.NextTowerHits(
        dies,
        last,
        GetUnitToUnitDistance(tower, current) / pspeed,
        GetUnitToUnitDistance(tower, next) / pspeed,
        tperiod,
        ____exports.NEXT_HORIZON
    )
    local creep = next
    local f = verbs.hpForecast(me, creep, ____exports.NEXT_HORIZON)
    for ____, h in ipairs(f.hits) do
        if h.by == "tower" then
            return {nil, nil}
        end
    end
    local tw = next:GetActualIncomingDamage(
        tower:GetAttackDamage(),
        DamageType.Physical
    )
    local function hpAt(t)
        local n = 0
        for ____, h in ipairs(towers) do
            if h <= t then
                n = n + 1
            end
        end
        return verbs.forecastHp(f, t) - tw * n
    end
    return decide(
        bot,
        me,
        verbs,
        tower,
        next,
        walk,
        f,
        hpAt,
        towers,
        ____exports.NEXT_HORIZON,
        true,
        freeUntil
    )
end
--- The pre-hit this core would make now, as a `prehit` LaneTarget, or undefined. Candidates: enemy lane creeps an own tower is
-- attacking, within a MAX_WALK walk, then each tower's predicted next target. `verbs` is the engine bundle's Verbs
-- (hpForecast, forecastHp, ownHitTime, laneTargets).
function ____exports.Find(bot, verbs)
    if not ____exports.Applies(bot) then
        return nil
    end
    local pid = bot:GetPlayerID()
    local me = bot
    local best
    local note
    local towersNear = bot:GetNearbyTowers(TOWER_RADIUS, false) or ({})
    for ____, tower in ipairs(towersNear) do
        local target = tower:GetAttackTarget()
        if best == nil and target ~= nil and target ~= nil then
            local n, pre = unpack(consider(
                bot,
                me,
                verbs,
                tower,
                target
            ))
            if n ~= nil and (note == nil or n.verdict ~= "far") then
                note = n
            end
            best = pre
        end
    end
    local creeps = bot:GetNearbyLaneCreeps(1600, true) or ({})
    local v = note and note.verdict
    local free = best == nil and v ~= "go" and v ~= "kills" and v ~= "lh"
    local freeUntil = v == "wait" and (note and note.plan) ~= nil and note.plan.swings[1] or math.huge
    for ____, tower in ipairs(towersNear) do
        local target = tower:GetAttackTarget()
        local current = target ~= nil and target ~= nil and not target:IsNull() and target:IsAlive() and target:IsCreep() and target:GetTeam() ~= bot:GetTeam() and target or nil
        local ____temp_18
        if current ~= nil then
            ____temp_18 = ____exports.NextTarget(
                tower,
                current,
                creeps,
                WorldFacts.TowerReach(tower, 788)
            )
        else
            ____temp_18 = nil
        end
        local next = ____temp_18
        notePick(tower, current, next, creeps)
        if free and best == nil and current ~= nil and next ~= nil then
            local n, pre = unpack(considerNext(
                bot,
                me,
                verbs,
                tower,
                current,
                next,
                freeUntil
            ))
            if n ~= nil and (note == nil or n.verdict ~= "far") then
                note = n
            end
            best = pre
        end
    end
    sampleWatch(bot, verbs)
    if note ~= nil then
        notes[pid] = note
        LanePick.NoteVerdict(
            pid,
            DotaTime(),
            note.next == true and "n" .. note.verdict or note.verdict
        )
    end
    return best
end
picks = {}
PICK_GAP = 1
WATCH_FOR = 2.5
WATCH_EVERY = 0.1
WATCH_SAMPLES = 20
WATCH_FIRES = 30
watches = {}
return ____exports
