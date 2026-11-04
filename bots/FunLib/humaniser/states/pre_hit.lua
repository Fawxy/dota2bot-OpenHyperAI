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
local startWatch, sampleWatch, noteFires, forecastDeath, WATCH_FOR, WATCH_EVERY, WATCH_SAMPLES, WATCH_FIRES, watches
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function startWatch(bot, verbs, tower, creep, f, lo)
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
            local __continue53
            repeat
                if h.t > 1 then
                    __continue53 = true
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
                __continue53 = true
            until true
            if not __continue53 then
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
    local ____creep_8 = creep
    local ____f_9 = f
    local ____DotaTime_result_10 = DotaTime()
    local ____temp_11 = -1
    local ____temp_12 = {}
    local ____temp_13 = {}
    local ____GameTime_result_14 = GameTime()
    local ____temp_15 = {}
    local ____temp_16 = {}
    local ____array_7 = __TS__SparseArrayNew(
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
    local ____math_floor_6 = math.floor
    local ____this_5
    ____this_5 = tower
    local ____opt_4 = ____this_5.GetSecondsPerAttack
    __TS__SparseArrayPush(
        ____array_7,
        {
            "twp",
            ____math_floor_6((____opt_4 and ____opt_4(____this_5) or -1) * 100) / 100
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
    watches[pid] = {
        creep = ____creep_8,
        f = ____f_9,
        t = ____DotaTime_result_10,
        last = ____temp_11,
        hs = ____temp_12,
        fs = ____temp_13,
        g0 = ____GameTime_result_14,
        lat = ____temp_15,
        fire = ____temp_16,
        fields = {__TS__SparseArraySpread(____array_7)}
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
        local ____w_hs_17 = w.hs
        ____w_hs_17[#____w_hs_17 + 1] = (tostring(r) .. ":") .. tostring(math.floor(w.creep:GetHealth()))
        local ____w_fs_18 = w.fs
        ____w_fs_18[#____w_fs_18 + 1] = tostring(math.floor(verbs.forecastHp(w.f, dt)))
        return
    end
    watches[pid] = nil
    local ____Telemetry_Event_20 = Telemetry.Event
    local ____array_19 = __TS__SparseArrayNew(__TS__Spread(w.fields))
    __TS__SparseArrayPush(
        ____array_19,
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
    ____Telemetry_Event_20(
        "prehit_fc",
        {__TS__SparseArraySpread(____array_19)}
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
            local ____w_fire_21 = w.fire
            ____w_fire_21[#____w_fire_21 + 1] = (kind .. ":") .. tostring(math.floor((at - w.g0) * 100) / 100)
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
local function better(a, b)
    if b == nil then
        return true
    end
    if a.margin ~= b.margin then
        return a.margin > b.margin
    end
    if #a.swings ~= #b.swings then
        return #a.swings < #b.swings
    end
    return a.swings[#a.swings] < b.swings[#b.swings]
end
--- The best plan from a swing that can land at `earliest` with `dealt` HP of ours already in the forecast and `pre` pre-hits
-- spent. A swing lands at `earliest` or just after a later tower hit (`AFTER`); landing where a tower hit falls inside the last
-- AFTER before it is not relied on. On the creep's HP there (`hpAt` is the forecast without our hits) it is the kill when inside
-- (0, lo], else a pre-hit of `mean` damage followed by the best plan from one attack cycle later.
local function search(hpAt, horizon, towers, earliest, dealt, pre, period, lo, mean)
    local candidates = {}
    local clear = true
    for ____, t in ipairs(towers) do
        if t > earliest - ____exports.AFTER and t <= earliest then
            clear = false
        end
    end
    if clear then
        candidates[#candidates + 1] = earliest
    end
    for ____, t in ipairs(towers) do
        if t + ____exports.AFTER > earliest then
            candidates[#candidates + 1] = t + ____exports.AFTER
        end
    end
    local best
    for ____, at in ipairs(candidates) do
        do
            local __continue14
            repeat
                if at > horizon then
                    break
                end
                local hp = hpAt(at) - dealt
                if hp <= 0 then
                    __continue14 = true
                    break
                end
                local plan
                if hp <= lo then
                    plan = {
                        swings = {at},
                        hpKill = hp,
                        margin = math.min(hp, lo - hp)
                    }
                elseif pre < ____exports.MAX_PREHITS then
                    local rest = search(
                        hpAt,
                        horizon,
                        towers,
                        at + period,
                        dealt + mean,
                        pre + 1,
                        period,
                        lo,
                        mean
                    )
                    if rest ~= nil then
                        plan = {
                            swings = {
                                at,
                                unpack(rest.swings)
                            },
                            hpKill = rest.hpKill,
                            margin = rest.margin
                        }
                    end
                end
                if plan ~= nil and better(plan, best) then
                    best = plan
                end
                __continue14 = true
            until true
            if not __continue14 then
                break
            end
        end
    end
    return best
end
--- The plan for a creep whose forecast HP without our hits is `hpAt` and whose tower hits land at `towers` (seconds from now,
-- sorted): our first swing can land at `first` (the walk plus our hit time) and every `period` after one, our low-roll damage
-- after armour is `lo` (the kill range's top, as the last-hit verb's `mine`) and our mean damage `mean` (what a pre-hit takes).
-- Undefined when no plan within the horizon ends in a kill.
-- A plan of our swings on one creep: when each lands (seconds from now), the last one the kill.
function ____exports.Plan(hpAt, horizon, towers, first, period, lo, mean)
    return search(
        hpAt,
        horizon,
        towers,
        first,
        0,
        0,
        period,
        lo,
        mean
    )
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
local function consider(bot, me, verbs, tower, target)
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
    local towers = {}
    for ____, h in ipairs(f.hits) do
        if h.by == "tower" then
            towers[#towers + 1] = h.t
        end
    end
    local first = walk + verbs.ownHitTime(me, creep)
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
    local mean = target:GetActualIncomingDamage(
        bot:GetAttackDamage(),
        DamageType.Physical
    )
    local function hpAt(t)
        return verbs.forecastHp(f, t)
    end
    local plan = ____exports.Plan(
        hpAt,
        ____exports.HORIZON,
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
    if verdict == "go" then
        for ____, o in ipairs(verbs.laneTargets(me, {within = first + period, deny = false})) do
            if o.creep ~= creep and LanePick.Reachable(o) and o.eta <= first + period then
                verdict = "lh"
            end
        end
    end
    local note = {
        verdict = verdict,
        creep = creep,
        hp = f.hp,
        t0 = first,
        lo = lo,
        plan = plan
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
        lo
    )
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
--- The pre-hit this core would make now, as a `prehit` LaneTarget, or undefined. Candidates: enemy lane creeps an own tower is
-- attacking, within a MAX_WALK walk. `verbs` is the engine bundle's Verbs (hpForecast, ownHitTime, laneTargets).
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
    sampleWatch(bot, verbs)
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
WATCH_FOR = 2.5
WATCH_EVERY = 0.1
WATCH_SAMPLES = 20
WATCH_FIRES = 30
watches = {}
return ____exports
