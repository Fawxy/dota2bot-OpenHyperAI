--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ObjectAssign(target, ...)
    local sources = {...}
    for i = 1, #sources do
        local source = sources[i]
        for key in pairs(source) do
            target[key] = source[key]
        end
    end
    return target
end

local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
end

local function __TS__ArraySome(self, callbackfn, thisArg)
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            return true
        end
    end
    return false
end

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

local function __TS__DelegatedYield(iterable)
    if type(iterable) == "string" then
        for index = 0, #iterable - 1 do
            coroutine.yield(__TS__StringAccess(iterable, index))
        end
    elseif iterable.____coroutine ~= nil then
        local co = iterable.____coroutine
        while true do
            local status, value = coroutine.resume(co)
            if not status then
                error(value, 0)
            end
            if coroutine.status(co) == "dead" then
                return value
            else
                coroutine.yield(value)
            end
        end
    elseif iterable[Symbol.iterator] then
        local iterator = iterable[Symbol.iterator](iterable)
        while true do
            local result = iterator:next()
            if result.done then
                return result.value
            else
                coroutine.yield(result.value)
            end
        end
    else
        for ____, value in ipairs(iterable) do
            coroutine.yield(value)
        end
    end
end

local __TS__Unpack = table.unpack or unpack

local __TS__Generator
do
    local function generatorIterator(self)
        return self
    end
    local function generatorNext(self, ...)
        local co = self.____coroutine
        if coroutine.status(co) == "dead" then
            return {done = true}
        end
        local status, value = coroutine.resume(co, ...)
        if not status then
            error(value, 0)
        end
        return {
            value = value,
            done = coroutine.status(co) == "dead"
        }
    end
    function __TS__Generator(fn)
        return function(...)
            local args = {...}
            local argsLength = __TS__CountVarargs(...)
            return {
                ____coroutine = coroutine.create(function() return fn(__TS__Unpack(args, 1, argsLength)) end),
                [Symbol.iterator] = generatorIterator,
                next = generatorNext
            }
        end
    end
end
-- End of Lua Library inline imports
local ____exports = {}
local mateGoing, creepsAttack, lastHits, underTower, kindOf, casts, yieldsTo, r2, enterPhase, factsOf, castPass, refuse, towerGone, yieldNow, onPhase, offerOf, STILL_GOING, CAST_OVER, running, lastCid, pending, WAY
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local DamageType = ____dota.DamageType
local CreepClaim = require(GetScriptDirectory().."/FunLib/humaniser/creep_claim")
local Claims = require(GetScriptDirectory().."/FunLib/humaniser/claims")
local CreepOffer = require(GetScriptDirectory().."/FunLib/humaniser/creep_offer")
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local LaneHits = require(GetScriptDirectory().."/FunLib/humaniser/lane_hits")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local SpellSecure = require(GetScriptDirectory().."/FunLib/humaniser/spell_secure")
--- The cell rule: undefined when the creep is in a claimed cell, else why not. In order: `kind` (neither kind this hero acts on: `KindOf`),
-- `late` (cannot arrive), `outdmg` (an enemy hero in range of the creep hits harder), `race` (a walk-in: an enemy hero
-- with a hit at least ours can be in range of the creep before it comes due), `covered` (a walk past NearWalk to a spot
-- an enemy hero's range covers), `tower` (a last hit inside our tower's range, unless Ours.TowerCreeps is on and the hero is not `out`), `etower`
-- (the stand spot is inside their tower's), `given` (a walk-in: another target comes due where the hero stands before it is back),
-- `mate` (a teammate's hit kills it first). A deny skips `tower` (our tower is no hazard to our own creep) and `given` (a support's
-- other targets are the ranking, a later slice's).
function ____exports.Claim(f)
    if f.k == nil then
        return "kind"
    end
    if f.slk <= 0 then
        return "late"
    end
    if f.ein > 0 and f.ed > f.md then
        return "outdmg"
    end
    if f.walk > 0 and f.erc > 0 then
        return "race"
    end
    if f.walk > ____exports.SETTINGS.NearWalk and f.eh > 0 then
        return "covered"
    end
    if f.otw and f.k == "lh" and (f.out == true or not Ours.On("TowerCreeps")) then
        return "tower"
    end
    if f.ptw then
        return "etower"
    end
    if f.walk > 0 and f.g2 > 0 and f.k == "lh" then
        return "given"
    end
    if f.kb == "mate" then
        return "mate"
    end
    return nil
end
--- Seconds until the hero can order its swing from inside the verb's own range: the walk to the engine's `attackReach` of the creep
-- (lastHit's `why=range` test, which the offer's `walk` also reads) at the hero's current move speed. No wind-up, flight or turn: `due`
-- already counts them between the order and the hit (the engine's `ownHit`), so it is the time to the order.
function ____exports.Need(bot, creep)
    local at = creep:GetLocation()
    local me = bot:GetLocation()
    local dx = at.x - me.x
    local dy = at.y - me.y
    return math.max(
        0,
        math.sqrt(dx * dx + dy * dy) - CreepOffer.Reach(bot, creep)
    ) / math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
end
--- The creep comes due no sooner than the hero can be in the verb's range (`need`, `Need`).
function ____exports.OnTime(need, due)
    return due >= need
end
--- The hero's hit cannot land before the creep dies to the others' hits: its swing is ordered no sooner than the creep comes due, the
-- hero is in range (`need`) and its attack is ready (`cd`, the engine's `cooldownLeft`), and lands `hit - cd` after the order (`hit` the
-- engine's `ownHitTime`, which counts the cooldown left already).
function ____exports.AttackLate(due, need, cd, hit, dies)
    return math.max(due, need, cd) + (hit - cd) > dies
end
function mateGoing(bot, cid, now)
    local pid = bot:GetPlayerID()
    local mine = TripTable.RankOf(
        "creep",
        LaneConfig.PositionOf(bot)
    )
    if mine == nil then
        return false
    end
    do
        local i = 1
        while i <= 5 do
            do
                local __continue18
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m:GetPlayerID() == pid or not m:IsBot() then
                        __continue18 = true
                        break
                    end
                    local cell = TripTable.RankOf(
                        "creep",
                        LaneConfig.PositionOf(m)
                    )
                    if cell == nil or cell >= mine then
                        __continue18 = true
                        break
                    end
                    local a = CreepClaim.AnswerOf(
                        m:GetPlayerID(),
                        cid
                    )
                    if a ~= nil and a.why ~= nil and STILL_GOING[a.why] and now - a.at <= CreepClaim.ANSWER_FRESH then
                        return true
                    end
                    __continue18 = true
                until true
                if not __continue18 then
                    break
                end
            end
            i = i + 1
        end
    end
    return false
end
--- Why the attack cannot take the creep, for the cast; undefined when it can, or when the row held back for a reason the cast shares (the hero
-- acting, another task, retreat, a claim, a teammate's hit). `why` the row's refusal this read. For a creep the row does not attack (`kind`)
-- or not yet about to come due (`early`): the cell rule on it as a last hit (`claim`, Claim's answer), the on-time check, then `late`
-- (`AttackLate`), so the cast waits while the attack may still take it.
function ____exports.AttackCannot(why, claim, onTime, late)
    if CAST_OVER[why] then
        return why
    end
    if why ~= "kind" and why ~= "early" then
        return nil
    end
    if claim ~= nil then
        return CAST_OVER[claim] and claim or nil
    end
    if not onTime then
        return "notime"
    end
    return late and "late" or nil
end
function creepsAttack(bot, creep)
    local row = LaneHits.Of(
        bot:GetTeam(),
        bot:GetAssignedLane(),
        creep
    )
    if row ~= nil then
        for ____, h in ipairs(row.forecast.hits) do
            if h.by == "creep" and h.attacker:GetTeam() == bot:GetTeam() then
                return true
            end
        end
    end
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(LaneHits.READER_RADIUS, false) or ({})) do
        if c:GetAttackTarget() == creep then
            return true
        end
    end
    return false
end
--- The one predicate per kind, asked by Consider, Claim (through the facts) and dueNow alike. A last hit: their ranged creep, or with
-- Ours.TowerCreeps one of any kind inside our tower's range (`otw`), for a hero whose position does `creep` with Ours.LaneCreeps on;
-- a hero whose cell is above the lowest (a support, with Ours.SupportCreeps) takes their ranged creep only, the case its widening was audited on.
-- A deny: any of our creeps, for a hero whose position does `deny` with Ours.CreepDeny on.
function ____exports.KindOf(bot, kind, ck, otw)
    local pos = LaneConfig.PositionOf(bot)
    if kind == "lasthit" and lastHits(pos) and (ck == "r" or otw and underTower(pos)) then
        return "lh"
    end
    if kind == "deny" and TripTable.Does("deny", pos) and Ours.On("CreepDeny") then
        return "dn"
    end
    return nil
end
function lastHits(pos)
    return TripTable.Does("creep", pos) and Ours.On("LaneCreeps") and (not TripTable.Outranked("creep", pos) or Ours.On("SupportCreeps"))
end
function underTower(pos)
    return Ours.On("TowerCreeps") and not TripTable.Outranked("creep", pos)
end
function kindOf(bot, c)
    local needsOtw = c.t.kind == "lasthit" and c.ck ~= "r" and underTower(LaneConfig.PositionOf(bot))
    return ____exports.KindOf(
        bot,
        c.t.kind,
        c.ck,
        needsOtw and c.facts().otw
    )
end
function casts()
    return Ours.On("CreepSpells")
end
--- Whether the creep is free for this hero, as far as the heroes with a lower `creep` cell go; undefined when it is, else why not. A hero
-- with the lowest cell is always free, with no scan. In order: `claimed` (a lower-cell hero holds a claim on it, `Claims.ClaimsOn`),
-- then over the teammates with a lower cell: `human` (not a bot, in this hero's assigned lane: a human publishes no answers, so its
-- creep is never free) and `wait` (it has the creep on offer and has not refused it yet: its answer, `CreepClaim.AnswerOf`, has no
-- `why`). A fresh answer with a `why` is a refusal (`Consider` sets `why` on every refusal, and the next read after an attempt's end
-- gives `tried`, so a stale `why` from before a go is overtaken by the claim, then by `tried`); no answer, or a stale one, is not on offer.
function ____exports.FreeFor(bot, cid, now)
    local pid = bot:GetPlayerID()
    local pos = LaneConfig.PositionOf(bot)
    local mine = TripTable.RankOf("creep", pos)
    if mine == nil or not TripTable.Outranked("creep", pos) then
        return nil
    end
    for ____, c in ipairs(Claims.ClaimsOn(Claims.CreepTarget(cid))) do
        if c.pid ~= pid and c.k == "lh" and c.rank ~= nil and c.rank < mine then
            return "claimed"
        end
    end
    local lane = bot:GetAssignedLane()
    local wait = false
    do
        local i = 1
        while i <= 5 do
            do
                local __continue97
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m:GetPlayerID() == pid then
                        __continue97 = true
                        break
                    end
                    local cell = TripTable.RankOf(
                        "creep",
                        LaneConfig.PositionOf(m)
                    )
                    if cell == nil or cell >= mine then
                        __continue97 = true
                        break
                    end
                    if not m:IsBot() then
                        if m:GetAssignedLane() == lane then
                            return "human"
                        end
                        __continue97 = true
                        break
                    end
                    local a = CreepClaim.AnswerOf(
                        m:GetPlayerID(),
                        cid
                    )
                    if a ~= nil and a.why == nil and now - a.at <= CreepClaim.ANSWER_FRESH then
                        wait = true
                    end
                    __continue97 = true
                until true
                if not __continue97 then
                    break
                end
            end
            i = i + 1
        end
    end
    return wait and "wait" or nil
end
function yieldsTo(pid, cid)
    local on = Claims.ClaimsOn(Claims.CreepTarget(cid))
    local mine = __TS__ArrayFind(
        on,
        function(____, c) return c.pid == pid end
    )
    if mine == nil or mine.k ~= "lh" or mine.phase == "swing" or mine.rank == nil then
        return false
    end
    local r = mine.rank
    return __TS__ArraySome(
        on,
        function(____, c) return c.pid ~= pid and c.k == "lh" and c.rank ~= nil and c.rank < r end
    )
end
function r2(x)
    return math.floor(x * 100 + 0.5) / 100
end
function enterPhase(a, p, t)
    if a.phase ~= nil then
        local ____a_spent_11, ____a_phase_12 = a.spent, a.phase
        ____a_spent_11[____a_phase_12] = ____a_spent_11[____a_phase_12] + (t - a.phaseAt)
    end
    a.phase = p
    a.phaseAt = t
    if p == "swing" and a.so == nil then
        a.so = t - a.t0
    end
end
function factsOf(bot, c)
    local s = c.facts()
    return {
        k = kindOf(bot, c),
        walk = c.t.walk,
        slk = c.arrive.slack,
        eh = s.path.covering,
        md = s.md,
        ed = s.ed,
        ein = s.ein,
        erc = s.erc,
        ptw = s.path.tower,
        otw = s.otw,
        g2 = s.given.due,
        kb = s.kb,
        out = TripTable.Outranked(
            "creep",
            LaneConfig.PositionOf(bot)
        )
    }
end
function castPass(bot, cands, whys, recs, now, gate, shadow)
    local pid = bot:GetPlayerID()
    local verbs = Tasks.Verbs()
    local cd
    local best
    local pick
    for ____, c in ipairs(cands) do
        do
            local __continue168
            repeat
                local why = whys[c.cid]
                if c.t.kind ~= "lasthit" or why == nil then
                    __continue168 = true
                    break
                end
                local as = c.spells()
                if #as == 0 then
                    __continue168 = true
                    break
                end
                local claim
                local onTime = true
                local late = false
                if why == "kind" or why == "early" then
                    claim = ____exports.Claim(__TS__ObjectAssign(
                        {},
                        factsOf(bot, c),
                        {k = "lh"}
                    ))
                    if claim == nil then
                        local need = ____exports.Need(bot, c.creep)
                        onTime = ____exports.OnTime(need, c.t.due)
                        if onTime then
                            if cd == nil then
                                cd = verbs.cooldownLeft(bot)
                            end
                            late = ____exports.AttackLate(
                                c.t.due,
                                need,
                                cd,
                                verbs.ownHitTime(bot, c.t.creep),
                                c.t.dies
                            )
                        end
                    end
                end
                if ____exports.AttackCannot(why, claim, onTime, late) == nil then
                    __continue168 = true
                    break
                end
                local no = gate or (lastCid[pid] == c.cid and "tried" or nil)
                if no ~= nil then
                    c.noteCast(false, no)
                    __continue168 = true
                    break
                end
                if ____exports.FreeFor(bot, c.cid, now) ~= nil or mateGoing(bot, c.cid, now) or #Claims.ClaimsOn(Claims.CreepTarget(c.cid)) > 0 then
                    no = "claimed"
                elseif c.facts().kb == "mate" then
                    no = "mate"
                end
                local p
                if no == nil then
                    local r = SpellSecure.CastPick(as)
                    p = r.pick
                    if p == nil then
                        no = r.why
                    end
                end
                if p == nil then
                    c.noteCast(false, no)
                    __continue168 = true
                    break
                end
                if best == nil or c.t.dies < best.t.dies then
                    if best ~= nil then
                        best.noteCast(false, "other")
                    end
                    best = c
                    pick = p
                else
                    c.noteCast(false, "other")
                end
                __continue168 = true
            until true
            if not __continue168 then
                break
            end
        end
    end
    if best == nil then
        return
    end
    if shadow then
        best.noteCast(false, "off")
        return
    end
    pending[pid] = {
        best = best,
        k = "sp",
        cast = pick,
        need = 0,
        lead = 0,
        now = now,
        seen = recs[best.cid]
    }
    Decider.Offer(bot, ____exports.ROW)
    if pending[pid] == nil then
        return
    end
    pending[pid] = nil
    best.noteCast(
        false,
        Decider.Refusal(bot, ____exports.ROW.name) == "fight" and "fight" or "refused"
    )
end
function refuse(bot, a, why)
    if a.tl == nil then
        a.tl = why
        a.tlt = DotaTime() - a.t0
        a.tlc = a.creep:IsAlive() and creepsAttack(bot, a.creep)
    end
    return not Ours.On("TowerStay")
end
function towerGone(tower)
    return tower:IsNull() or not tower:IsAlive()
end
function yieldNow(pid, cid)
    if not yieldsTo(pid, cid) then
        return false
    end
    local a = running[pid]
    if a ~= nil then
        a.yielded = true
    end
    return true
end
function onPhase(pid, p, t)
    local a = running[pid]
    if a ~= nil then
        enterPhase(a, p, t)
    end
    Claims.Phase(pid, p)
end
function offerOf(bot, pd)
    local ____pd_80 = pd
    local best = ____pd_80.best
    local k = ____pd_80.k
    local rank = TripTable.RankOf(
        k == "dn" and "deny" or "creep",
        LaneConfig.PositionOf(bot)
    )
    local due = pd.now + (k == "sp" and pd.cast.timing.land or best.t.due)
    return {
        tgt = Claims.CreepTarget(best.cid),
        by = k == "sp" and pd.now or pd.now + best.t.due - pd.need,
        way = WAY[k],
        claim = {rank = rank, k = k == "dn" and "dn" or "lh", due = due, phase = k == "sp" and "swing" or nil}
    }
end
____exports.SETTINGS = {
    NearWalk = 1,
    WaitSlack = 1.5,
    EarlyLead = 3,
    Round = 0.4,
    DeciderRound = 0.32,
    Margin = 0.6,
    MaxPreHits = 2,
    LandSlack = 0.1,
    PreHitSlack = 0.5
}
--- The mode the decider hosts its rows in: the engine steps the attempt's task under it.
local HOST = BotMode.Farm
--- About to come due: due within the walk plus `lead` (`Lead`: the longer of one own attack cycle, `GetSecondsPerAttack`, and `EarlyLead`), so the hero is in range and
-- facing with a full cycle to spare whatever its cooldown. Round 0 of oha-creep-ranged went at walk + 0.4 s and lost 48 of
-- 122 uncut attempts with no swing on the creep (re-read 25/11/2026). The creep offer asks laneTargets for creeps due within
-- at least one cycle (`CreepOffer.Within`), so such a creep is offered by then.
function ____exports.Due(walk, due, lead)
    return due <= walk + lead
end
STILL_GOING = {acting = true, row = true, refused = true}
CAST_OVER = {
    late = true,
    outdmg = true,
    race = true,
    covered = true,
    etower = true,
    tower = true,
    notime = true,
    notime_new = true,
    notime_held = true,
    notime_acting = true
}
--- The leftover rule, pure. `hp` the creep's HP, `towerHit` the tower's damage on it after armour, `lo` and `hi` the hero's lowest and highest hit on it
-- after armour, `period` the tower's seconds per attack, `walk` the seconds before the hero's first attack can start, `cycle` the hero's attack cycle.
-- `wait`: the creep is killable by the hero's hit just before the killing shot (leftover within `hi`: from `lo` up the verb swings only on a high roll
-- and the row leaves that to it), so the row carries on as without the rule. `prehit`: one hit now (leftover over `hi`, within `2 * lo`) or two (over
-- `2 * hi`, within `3 * lo`) leave it within one lowest hit, and the hero's attack is ready again before the last hit is needed
-- (`shots >= 1`, `shots * period - walk >= cycle * hits`). `none` otherwise.
function ____exports.Verdict(hp, towerHit, lo, hi, period, walk, cycle)
    if towerHit <= 0 or lo <= 0 then
        return {vd = "wait", shots = 0, leftover = hp, need = 0}
    end
    local shots = math.max(
        0,
        math.floor((hp - 1) / towerHit)
    )
    local leftover = hp - towerHit * shots
    if leftover <= hi then
        return {vd = "wait", shots = shots, leftover = leftover, need = 0}
    end
    local need = leftover <= 2 * lo and 1 or (leftover > 2 * hi and leftover <= 3 * lo and 2 or 0)
    if need == 0 or shots < 1 or shots * period - walk < cycle * need then
        return {vd = "none", shots = shots, leftover = leftover, need = 0}
    end
    return {vd = "prehit", shots = shots, leftover = leftover, need = need}
end
--- Our towers near the hero, read once a read (`Consider`); the tower's target is asked per candidate.
local function ownTowers(bot)
    return bot:GetNearbyTowers(CreepOffer.SETTINGS.TowerRadius, false) or ({})
end
--- A tower of ours that is attacking the creep now.
local function attackerOf(towers, creep)
    for ____, t in ipairs(towers) do
        if t:IsAlive() and t:GetAttackTarget() == creep then
            return t
        end
    end
    return nil
end
--- The verdict on the creep's HP now. `done` the pre-hits already ordered: past `MaxPreHits` the verdict is `none`. A `prehit` becomes `none` with
-- `why=mates` when our creeps attack the creep, else `nowindow` for any `none`.
local function towerRead(bot, creep, tower, done)
    local hit = creep:GetActualIncomingDamage(
        tower:GetAttackDamage(),
        DamageType.Physical
    )
    local dmg = bot:GetAttackDamage()
    local ____this_1
    ____this_1 = bot
    local ____opt_0 = ____this_1.GetBaseDamageVariance
    local spread = ____opt_0 and ____opt_0(____this_1) or 0
    local lo = creep:GetActualIncomingDamage(dmg - spread, DamageType.Physical)
    local hi = creep:GetActualIncomingDamage(dmg + spread, DamageType.Physical)
    local ____exports_Verdict_5 = ____exports.Verdict
    local ____temp_4 = creep:GetHealth()
    local ____this_3
    ____this_3 = tower
    local ____opt_2 = ____this_3.GetSecondsPerAttack
    local v = ____exports_Verdict_5(
        ____temp_4,
        hit,
        lo,
        hi,
        ____opt_2 and ____opt_2(____this_3) or 1,
        ____exports.Need(bot, creep),
        CreepOffer.AttackCycle(bot)
    )
    local r = {tower = tower, hit = hit, v = v}
    if v.vd == "prehit" and done >= ____exports.SETTINGS.MaxPreHits then
        r.v = __TS__ObjectAssign({}, v, {vd = "none", need = 0})
    end
    if r.v.vd == "prehit" and creepsAttack(bot, creep) then
        r.v = __TS__ObjectAssign({}, v, {vd = "none", need = 0})
        r.why = "mates"
    elseif r.v.vd == "none" then
        r.why = "nowindow"
    end
    return r
end
--- The record of each listed creep, new ones made now; records of creeps this read does not list are dropped (the claim read's).
local function touch(pid, cands, now)
    local cids = {}
    for ____, c in ipairs(cands) do
        cids[#cids + 1] = c.cid
    end
    return CreepClaim.Touch(pid, cids, now)
end
--- Why the on-time check refused: at the creep's first read about to come due, after a refusal on time for `held` or `acting`, or neither.
local function noTime(r, first)
    if first then
        return "notime_new"
    end
    return (r.ok == "held" or r.ok == "acting" or r.ok == "row" or r.ok == "fight") and "notime_" .. r.ok or "notime"
end
--- The creep is of a kind this hero acts on and about to come due at this read (the first such read is kept).
local function dueNow(bot, c, r, lead, now)
    if kindOf(bot, c) == nil or not ____exports.Due(c.t.walk, c.t.due, lead) then
        return false
    end
    if r.due0 == nil then
        r.due0 = now
    end
    return true
end
running = {}
lastCid = {}
pending = {}
local reserved = {}
--- A reservation's refusals that wait: the start is not offered while one stands, and it drops only once late.
local WAITS = {acting = true, held = true, fight = true}
--- An attempt the row reserves rather than starts: a right-click with no tower read (the leftover rule's pre-hits start before due), the switch on.
local function reserves(k, tr)
    return k ~= "sp" and tr == nil and Ours.On("CreepReserve")
end
--- The spare (s) left now past the hero's walk to the reserved creep, from the latest read's need and its due (or `at`, its death).
local function slackOf(pd, now, at)
    if at == nil then
        at = pd.best.t.due
    end
    return at - pd.need - (now - pd.now)
end
--- The reservation ends without a start: the claim goes, the creep's try is not spent, and the line says why.
local function drop(bot, pid, rv, why)
    reserved[pid] = nil
    local ____opt_6 = pending[pid]
    if (____opt_6 and ____opt_6.rvAt) ~= nil then
        pending[pid] = nil
    end
    Decider.Unreserve(bot, ____exports.ROW)
    if not Telemetry.IsEnabled() then
        return
    end
    Telemetry.Event(
        "job",
        {
            {"pid", pid},
            {"job", "creep"},
            {"k", rv.pd.k},
            {"phase", "drop"},
            {"why", why},
            {"host", HOST},
            {"cid", rv.cid},
            {
                "rv",
                r2(DotaTime() - rv.at)
            }
        }
    )
end
--- A read with a reservation: the creep is read again as any candidate (`whys`), and the reservation drops when the creep is gone
-- from the read (`gone`), no longer about to come due (`early`), not reachable before it dies (`late`: Consider's on-time test reads
-- the reserved creep's death, not its due), another task runs for
-- the hero (`row`), or our tower now attacks it (`tower`: the leftover rule starts at once, so the next read offers it). Any other
-- refusal is kept for the start round. Else the read's view replaces the reservation's. True while it stands.
local function keep(bot, pid, rv, cands, whys, reads, recs, lead, now)
    local c = __TS__ArrayFind(
        cands,
        function(____, x) return x.cid == rv.cid end
    )
    local why = c == nil and "gone" or whys[c.cid]
    local out
    if c == nil then
        out = "gone"
    elseif why == "early" or why == "kind" then
        out = "early"
    elseif why ~= nil and string.sub(why, 1, 6) == "notime" then
        out = "late"
    elseif why == "row" then
        out = "row"
    elseif reads[c.cid] ~= nil then
        out = "tower"
    end
    if out ~= nil then
        drop(bot, pid, rv, out)
        return false
    end
    rv.why = why
    rv.pd = __TS__ObjectAssign(
        {},
        rv.pd,
        {
            best = c,
            need = ____exports.Need(bot, c.creep),
            lead = lead,
            now = now,
            seen = recs[c.cid]
        }
    )
    if why == nil then
        c.note(false, "reserved")
    end
    return true
end
--- The decider's round with a reservation: the start is offered (as `pending`, which `rowBegin` takes) once one more round would
-- leave less than `Margin`, unless a waiting refusal stands; past its due it is still offered until the hero's walk would end after
-- the creep dies (rig ladder-support dire, 27/11/2026: 9 of 14 `late` drops with no other mode were started by the same hero within 2 s, most
-- already in range, a start refused at its round having let the due pass). Late, gone, or a claim's refusal kept from the last read: dropped.
-- The creep's handle is read only through `IsNull` and `IsAlive`: the read that listed it may be a round old.
local function startDue(bot, pid, rv)
    Decider.Refusal(bot, ____exports.ROW.name)
    local now = DotaTime()
    local creep = rv.pd.best.creep
    local ____opt_8 = creep.IsNull
    local ____temp_10 = ____opt_8 and ____opt_8(creep)
    if ____temp_10 == nil then
        ____temp_10 = false
    end
    if ____temp_10 or not creep:IsAlive() then
        drop(bot, pid, rv, "gone")
        return nil
    end
    if slackOf(rv.pd, now, rv.pd.best.t.dies) < 0 then
        drop(bot, pid, rv, "late")
        return nil
    end
    if slackOf(rv.pd, now) > ____exports.SETTINGS.DeciderRound + ____exports.SETTINGS.Margin then
        return nil
    end
    if rv.why ~= nil then
        if WAITS[rv.why] ~= true then
            drop(bot, pid, rv, rv.why)
        end
        return nil
    end
    local pd = __TS__ObjectAssign({}, rv.pd, {rvAt = rv.at})
    pending[pid] = pd
    return offerOf(bot, pd)
end
function ____exports.ResetCache()
    for ____, t in ipairs({running, lastCid, pending, reserved}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
    CreepClaim.ResetCache()
    Claims.ResetCache()
end
function ____exports.On(bot)
    local pos = LaneConfig.PositionOf(bot)
    local lh = lastHits(pos)
    local dn = TripTable.Does("deny", pos) and Ours.On("CreepDeny")
    return (lh or dn or casts()) and bot:IsBot() and not Drill.Held(bot)
end
--- OHA's own action holds the hero (the deny and pull rows' check: a queued order, a cast or channel).
local function acting(bot)
    return bot:NumQueuedActions() > 0 or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility()
end
--- A teammate's hit kills the creep first in the lane read (the attempt drops before its swing then).
local function mateTakes(bot, creep)
    local row = LaneHits.Of(
        bot:GetTeam(),
        bot:GetAssignedLane(),
        creep
    )
    if row == nil then
        return false
    end
    local k = LaneHits.KillingHit(row)
    if k == nil or k.by ~= "hero" and k.by ~= "self" then
        return false
    end
    local a = k.attacker
    return a ~= bot and a:GetTeam() == bot:GetTeam()
end
--- The start line: the creep (`cid`, as on the read's line and `creep_death`), the walk and due at go, the hero's attack range (`rng`)
-- and the engine's reach on the creep (`rch`), and
-- what the reads saw: `gn` the need at go and `sp` the spare (due less need), `hw` and `hm` the last refusal while about to come
-- due and the hero's mode then (absent when it went at the first such read), `hs` seconds from that first read to the go, `sa` 1
-- when the hero's attack target was the creep, `nw` 1 when this read was the first to list the creep, `k` `lh` or `dn`, `ld` the lead in force (s: one attack
-- cycle, or `EarlyLead`), `oc` the other heroes already holding a claim on the creep (Claims.ClaimsOn, before the decider takes this one); with Ours.TowerCreeps and a tower attacking the
-- creep `lf` the creep's HP just before the killing tower shot, `tT` the tower's damage on it, `ts` the shots before that one and `vd` the verdict (`Verdict`).
-- A reserved start (Ours.CreepReserve) carries `rv`, the seconds from the reservation to the start; its walk, need and `sa` are the latest
-- read's, its due that read's less the time since.
local function startLine(bot, cid, aid, t, g)
    local ____Telemetry_Event_27 = Telemetry.Event
    local ____array_26 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"aid", aid},
        {"job", "creep"},
        {"k", g.k},
        {"phase", "start"},
        {"why", "trigger"},
        {"host", HOST},
        {"cid", cid},
        {
            "gw",
            r2(t.walk)
        },
        {
            "gd",
            r2(t.due)
        },
        {
            "rng",
            math.floor(bot:GetAttackRange())
        },
        {
            "rch",
            math.floor(g.reach)
        },
        {
            "gn",
            r2(g.need)
        },
        {
            "sp",
            r2(t.due - g.need)
        },
        {"hw", g.seen.why},
        {"hm", g.seen.mode},
        {
            "hs",
            r2(g.now - (g.seen.due0 or g.now))
        },
        {"sa", g.sa and 1 or 0},
        {"nw", g.seen.first == g.now and 1 or 0},
        {
            "ld",
            r2(g.lead)
        },
        {"oc", g.oc}
    )
    local ____temp_13
    if g.tr == nil then
        ____temp_13 = nil
    else
        ____temp_13 = r2(g.tr.v.leftover)
    end
    __TS__SparseArrayPush(____array_26, {"lf", ____temp_13})
    local ____temp_14
    if g.tr == nil then
        ____temp_14 = nil
    else
        ____temp_14 = r2(g.tr.hit)
    end
    __TS__SparseArrayPush(____array_26, {"tT", ____temp_14})
    local ____opt_15 = g.tr
    __TS__SparseArrayPush(____array_26, {"ts", ____opt_15 and ____opt_15.v.shots})
    local ____opt_17 = g.tr
    __TS__SparseArrayPush(____array_26, {"vd", ____opt_17 and ____opt_17.v.vd})
    local ____opt_19 = g.cast
    __TS__SparseArrayPush(____array_26, {"ab", ____opt_19 and ____opt_19.spell.name})
    local ____temp_21
    if g.cast == nil then
        ____temp_21 = nil
    else
        ____temp_21 = r2(g.cast.timing.land)
    end
    __TS__SparseArrayPush(____array_26, {"al", ____temp_21})
    local ____opt_22 = g.cast
    __TS__SparseArrayPush(____array_26, {"az", ____opt_22 and ____opt_22.also})
    local ____temp_24
    if g.cast == nil then
        ____temp_24 = nil
    else
        ____temp_24 = math.floor(g.cast.over + 0.5)
    end
    __TS__SparseArrayPush(____array_26, {"am", ____temp_24})
    local ____temp_25
    if g.rv == nil then
        ____temp_25 = nil
    else
        ____temp_25 = r2(g.rv)
    end
    __TS__SparseArrayPush(____array_26, {"rv", ____temp_25})
    ____Telemetry_Event_27(
        "job",
        {__TS__SparseArraySpread(____array_26)}
    )
end
--- The end line: `pw`, `pq`, `ps` the seconds in each phase of the verb (walk, wait, swing), `so` the seconds from the go to the swing order (-1 none), `tk` how many times another
-- mode had the hero (a gap between steps over `Round`) and `tks` the seconds it did, `wt` the seconds from the go to the row's first step (-1 never), `tin` the seconds to first in the verb's range (-1 never), `sw` 1 when the verb ordered its swing (its message
-- is the post-swing one, which carries `end=`; absent on a cut, whose message is the runner's; 0 with `why=ok` when the hero's count
-- rose from a swing ordered before the verb's, message `hit=other`), `cl` 1 when the hero's claim on the creep was held and is released, `yd` 1 when the end was a yield (`why=interrupted`), `ph` the pre-hits ordered (an attempt the leftover rule covers; absent otherwise), `hp0`/`hp1` the hero's HP at the
-- start and end, `msg` the verb's message (what the swing was based on, or what held it).
local function endLine(bot, a, r, cut, claimed)
    local msg = r.message
    local sw
    if r.success then
        sw = msg ~= nil and (string.find(msg, "hit=other", 1, true)) == 1 and 0 or 1
    elseif r.reason ~= "preempted" and msg ~= nil then
        sw = (string.find(msg, " end=", 1, true)) ~= nil and 1 or 0
    end
    local ____Telemetry_Event_59 = Telemetry.Event
    local ____array_58 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"aid", a and a.aid},
        {"job", "creep"},
        {"k", a and a.k},
        {"phase", "end"},
        {"why", r.success and "ok" or r.reason},
        {"host", HOST},
        {"cut", cut},
        {"cl", claimed and 1 or 0},
        {"yd", (a and a.yielded) == true and 1 or nil},
        {"cid", a and a.cid}
    )
    local ____temp_38
    if (a and a.tower) == nil then
        ____temp_38 = nil
    else
        ____temp_38 = a.ph
    end
    __TS__SparseArrayPush(____array_58, {"ph", ____temp_38}, {"tl", a and a.tl})
    local ____temp_43
    if (a and a.tlt) == nil then
        ____temp_43 = nil
    else
        ____temp_43 = r2(a.tlt)
    end
    __TS__SparseArrayPush(____array_58, {"tlt", ____temp_43})
    local ____temp_46
    if (a and a.tlc) == nil then
        ____temp_46 = nil
    else
        ____temp_46 = a.tlc and 1 or 0
    end
    __TS__SparseArrayPush(____array_58, {"tlc", ____temp_46})
    local ____temp_47
    if a == nil then
        ____temp_47 = nil
    else
        ____temp_47 = a.so ~= nil and r2(a.so) or -1
    end
    __TS__SparseArrayPush(____array_58, {"so", ____temp_47}, {"tk", a and a.tk})
    local ____temp_50
    if a == nil then
        ____temp_50 = nil
    else
        ____temp_50 = r2(a.tks)
    end
    __TS__SparseArrayPush(____array_58, {"tks", ____temp_50})
    local ____temp_51
    if a == nil then
        ____temp_51 = nil
    else
        ____temp_51 = r2(a.spent.walk)
    end
    __TS__SparseArrayPush(____array_58, {"pw", ____temp_51})
    local ____temp_52
    if a == nil then
        ____temp_52 = nil
    else
        ____temp_52 = r2(a.spent.wait)
    end
    __TS__SparseArrayPush(____array_58, {"pq", ____temp_52})
    local ____temp_53
    if a == nil then
        ____temp_53 = nil
    else
        ____temp_53 = r2(a.spent.swing)
    end
    __TS__SparseArrayPush(____array_58, {"ps", ____temp_53})
    local ____temp_54
    if a == nil then
        ____temp_54 = nil
    else
        ____temp_54 = a.wt ~= nil and r2(a.wt) or -1
    end
    __TS__SparseArrayPush(____array_58, {"wt", ____temp_54})
    local ____temp_55
    if a == nil then
        ____temp_55 = nil
    else
        ____temp_55 = a.tin ~= nil and r2(a.tin) or -1
    end
    __TS__SparseArrayPush(
        ____array_58,
        {"tin", ____temp_55},
        {"sw", sw},
        {"hp0", a and a.hp0},
        {
            "hp1",
            math.floor(bot:GetHealth())
        },
        {"msg", msg}
    )
    ____Telemetry_Event_59(
        "job",
        {__TS__SparseArraySpread(____array_58)}
    )
end
--- As the pull's: an attempt the engine ends because the host lost the hero names what took it.
local function cutBy(bot, r)
    if r.success or r.reason ~= "preempted" then
        return nil
    end
    if Decider.LetGo(bot) or bot:GetActiveMode() == BotMode.Retreat then
        return "retreat"
    end
    return HDebug.ModeName(bot:GetActiveMode())
end
local function finish(bot, r)
    local pid = bot:GetPlayerID()
    local a = running[pid]
    running[pid] = nil
    local claimed = Claims.HeldBy(pid) ~= nil
    local now = DotaTime()
    if a ~= nil then
        if a.phase ~= nil then
            local ____a_spent_60, ____a_phase_61 = a.spent, a.phase
            ____a_spent_60[____a_phase_61] = ____a_spent_60[____a_phase_61] + (now - a.phaseAt)
        end
        if a.lastStep ~= nil and now - a.lastStep > ____exports.SETTINGS.Round then
            a.tk = a.tk + 1
            a.tks = a.tks + (now - a.lastStep)
        end
    end
    endLine(
        bot,
        a,
        r,
        cutBy(bot, r),
        claimed
    )
end
--- The lead (s) the row goes on: a creep due within the walk plus this is about to come due (`Due`). One own attack cycle, or `EarlyLead` when
-- that is longer.
function ____exports.Lead(bot)
    return math.max(
        CreepOffer.AttackCycle(bot),
        ____exports.SETTINGS.EarlyLead
    )
end
--- What the read asks laneTargets to offer (`within`) for a hero the row acts on: the lead, so a creep is listed by the time the row may go. 0: the read's own.
function ____exports.OfferLead(bot)
    return ____exports.On(bot) and ____exports.SETTINGS.EarlyLead or 0
end
--- The read's hook (CreepOffer.SetRow), at each read of a hero: notes why each candidate is not taken and starts an attempt on
-- the claimed creep closest to due. Reasons asked before the facts are read: `busy` (an attempt runs), `kind`, `early` (not
-- yet about to come due), `acting`, `row` (another task runs for the hero: a pull or stack), `held` (stock's retreat holds the hero: a later read may still go),
-- `tried` (this creep's attempt has ended); then Claim's;
-- `notime_new`, `notime_held`, `notime_acting`, `notime` (the hero cannot be in the verb's range before the creep comes due: at the
-- creep's first read about to come due, after a refusal on time for `held` or `acting`, or neither; asked after `early`).
-- The chosen creep is then offered to the decider (`Decider.Offer`), which begins the row at once unless a row above holds the
-- hero; `refused` when the task runner said no or the decider did not begin it. The last of these reasons given while the creep was about to come due is kept per hero
-- and creep (`Seen`), with the hero's mode when it was `held`, and goes out on the start line (`hw`, `hm`).
function ____exports.Consider(bot, cands)
    if not ____exports.On(bot) then
        return
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local lead = ____exports.Lead(bot)
    local recs = touch(pid, cands, now)
    if #cands == 0 then
        local rv = reserved[pid]
        if rv ~= nil then
            drop(bot, pid, rv, "gone")
        end
        return
    end
    if running[pid] ~= nil then
        for ____, c in ipairs(cands) do
            local r = recs[c.cid]
            if dueNow(
                bot,
                c,
                r,
                lead,
                now
            ) then
                r.why = "busy"
                r.mode = nil
            end
            c.note(false, "busy")
        end
        return
    end
    if Tasks.Jobs() == nil then
        return
    end
    local busy = acting(bot)
    local other = Tasks.Running(bot) ~= nil
    local mode = bot:GetActiveMode()
    local held = Decider.LetGo(bot) or mode == BotMode.Retreat
    local best
    local tower = underTower(LaneConfig.PositionOf(bot))
    local towers
    local reads = {}
    local whys = {}
    for ____, c in ipairs(cands) do
        local why
        local r = recs[c.cid]
        local first = r.due0 == nil
        local k = kindOf(bot, c)
        local tr
        local notarget = false
        if k == "lh" and tower then
            if towers == nil then
                towers = ownTowers(bot)
            end
            local tw = attackerOf(towers, c.creep)
            local ____temp_62
            if tw == nil then
                ____temp_62 = nil
            else
                ____temp_62 = towerRead(bot, c.creep, tw, 0)
            end
            tr = ____temp_62
            reads[c.cid] = tr
            notarget = tr == nil and c.ck ~= "r"
        end
        local pre = (tr and tr.v.vd) == "prehit"
        if pre and r.due0 == nil then
            r.due0 = now
        end
        if k == nil then
            why = "kind"
        elseif notarget then
            why = "notarget"
        elseif (tr and tr.why) ~= nil then
            why = tr.why
        elseif not pre and not dueNow(
            bot,
            c,
            r,
            lead,
            now
        ) then
            why = "early"
        else
            local ____temp_71 = not pre
            if ____temp_71 then
                local ____exports_OnTime_70 = ____exports.OnTime
                local ____exports_Need_result_69 = ____exports.Need(bot, c.creep)
                local ____opt_67 = reserved[pid]
                ____temp_71 = not ____exports_OnTime_70(____exports_Need_result_69, (____opt_67 and ____opt_67.cid) == c.cid and c.t.dies or c.t.due)
            end
            if ____temp_71 then
                why = noTime(r, first)
            elseif busy then
                why = "acting"
            elseif other then
                why = "row"
            elseif held then
                why = "held"
            elseif lastCid[pid] == c.cid then
                why = "tried"
            else
                local ____temp_72
                if k == "lh" then
                    ____temp_72 = ____exports.FreeFor(bot, c.cid, now)
                else
                    ____temp_72 = nil
                end
                why = ____temp_72
                if why == nil then
                    why = ____exports.Claim(factsOf(bot, c))
                end
            end
        end
        if why ~= nil and why ~= "kind" and why ~= "early" then
            r.why = why
            if string.sub(why, 1, 6) ~= "notime" then
                r.ok = why
            end
            r.mode = why == "held" and HDebug.ModeName(mode) or nil
        end
        whys[c.cid] = why
        if why ~= nil then
            c.note(false, why)
        elseif best == nil or c.t.eta < best.t.eta then
            best = c
        end
    end
    local rv = reserved[pid]
    if rv ~= nil and keep(
        bot,
        pid,
        rv,
        cands,
        whys,
        reads,
        recs,
        lead,
        now
    ) then
        for ____, c in ipairs(cands) do
            do
                local __continue154
                repeat
                    if c.cid == rv.cid or whys[c.cid] ~= nil or kindOf(bot, c) == nil then
                        __continue154 = true
                        break
                    end
                    c.note(false, "busy")
                    recs[c.cid].why = "busy"
                    __continue154 = true
                until true
                if not __continue154 then
                    break
                end
            end
        end
        return
    end
    if best == nil then
        castPass(
            bot,
            cands,
            whys,
            recs,
            now,
            busy and "acting" or (other and "row" or (held and "held" or nil)),
            not casts()
        )
        return
    end
    for ____, c in ipairs(cands) do
        do
            local __continue158
            repeat
                if c == best or kindOf(bot, c) == nil then
                    __continue158 = true
                    break
                end
                c.note(false, "other")
                recs[c.cid].why = "other"
                recs[c.cid].ok = "other"
                __continue158 = true
            until true
            if not __continue158 then
                break
            end
        end
    end
    local pd = {
        best = best,
        k = kindOf(bot, best),
        need = ____exports.Need(bot, best.creep),
        lead = lead,
        now = now,
        seen = recs[best.cid],
        tr = reads[best.cid]
    }
    if reserves(pd.k, pd.tr) and slackOf(pd, now) > ____exports.SETTINGS.DeciderRound + ____exports.SETTINGS.Margin then
        if Decider.Reserve(
            bot,
            ____exports.ROW,
            offerOf(bot, pd)
        ) then
            reserved[pid] = {cid = best.cid, pd = pd, at = now}
            best.note(false, "reserved")
            if Telemetry.IsEnabled() then
                Telemetry.Event(
                    "job",
                    {
                        {"pid", pid},
                        {"job", "creep"},
                        {"k", pd.k},
                        {"phase", "reserve"},
                        {"host", HOST},
                        {"cid", best.cid},
                        {
                            "gd",
                            r2(best.t.due)
                        },
                        {
                            "gn",
                            r2(pd.need)
                        }
                    }
                )
            end
            return
        end
    else
        pending[pid] = pd
        Decider.Offer(bot, ____exports.ROW)
        if pending[pid] == nil then
            return
        end
        pending[pid] = nil
    end
    if Decider.Refusal(bot, ____exports.ROW.name) == "fight" then
        best.note(false, "fight")
        local r = recs[best.cid]
        r.why = "fight"
        r.ok = "fight"
        r.mode = HDebug.ModeName(mode)
        return
    end
    best.note(false, "refused")
    recs[best.cid].why = "refused"
end
--- The leftover rule's refusal of a running attempt before its swing is ordered: the verdict is `none` now, or the tower left the creep. Noted
-- once (`refuse`); it ends the attempt only with `Ours.TowerStay` off.
local function towerLost(bot, pid)
    local a = running[pid]
    if a == nil or a.tower == nil or a.so ~= nil or a.tl ~= nil then
        return false
    end
    if towerGone(a.tower) or a.tower:GetAttackTarget() ~= a.creep then
        return refuse(bot, a, "tgt")
    end
    local tr = towerRead(bot, a.creep, a.tower, a.ph)
    if tr.v.vd ~= "none" then
        return false
    end
    return refuse(bot, a, tr.why or "none")
end
--- The pre-hit's interrupt: the tower left the creep (or fell); notes the refusal and always cuts the pre-hit.
local function towerLeft(bot, a, creep)
    if a.tower == nil or not towerGone(a.tower) and a.tower:GetAttackTarget() == creep then
        return false
    end
    refuse(bot, a, "tgt")
    return true
end
--- The attempt of a creep a tower is attacking: while the verdict is `prehit`, one plain attack (not a last hit: the engine's `attackAndConfirm`, which
-- walks in itself), its order cancelled once it has fired or failed (an attack order outlives its one attack: engine/src/lane.ts, the pre-hit), and a
-- wait until the hit has landed so the verdict is asked on the creep's HP; then `lastHit` on the same creep. The hold and the claim are the attempt's.
local towerAttempt = __TS__Generator(function(ctx, bot, pid, creep, opts)
    while true do
        local a = running[pid]
        if a == nil or a.tower == nil or not creep:IsAlive() then
            break
        end
        if towerGone(a.tower) or a.tower:GetAttackTarget() ~= creep then
            if refuse(bot, a, "tgt") then
                return ctx.fail("interrupted", "nowindow")
            end
            break
        end
        local tr = towerRead(bot, creep, a.tower, a.ph)
        if tr.v.vd == "none" then
            if refuse(bot, a, tr.why or "none") then
                return ctx.fail("interrupted", tr.why)
            end
            break
        end
        if tr.v.vd == "wait" then
            break
        end
        local walk = ____exports.Need(bot, creep)
        local hitIn = Tasks.Verbs().ownHitTime(bot, creep)
        local landAt = ctx.now() + walk + hitIn + ____exports.SETTINGS.LandSlack
        a.ph = a.ph + 1
        local r = __TS__DelegatedYield(ctx.attackAndConfirm(
            function() return creep:IsAlive() and creep or nil end,
            {
                findFor = 0,
                confirmFor = walk + hitIn + ____exports.SETTINGS.PreHitSlack,
                aggroConfirms = false,
                hold = "creep_prehit",
                interruptIf = function() return mateTakes(bot, creep) or towerLeft(bot, a, creep) end
            }
        ))
        bot:Action_MoveToLocation(bot:GetLocation())
        if not r.success and not (a.tl == "tgt" and Ours.On("TowerStay")) then
            return r
        end
        if not r.success then
            break
        end
        while ctx.now() < landAt and creep:IsAlive() do
            coroutine.yield()
        end
    end
    return __TS__DelegatedYield(ctx.lastHit(opts))
end)
--- The row's `begin`: starts the attempt on the creep Consider chose, at the read's moment.
local function rowBegin(bot)
    local pid = bot:GetPlayerID()
    local pd = pending[pid]
    pending[pid] = nil
    if pd == nil then
        return false
    end
    local best = pd.best
    local k = pd.k
    local need = pd.need
    local lead = pd.lead
    local now = pd.now
    local tr = pd.tr
    local cast = pd.cast
    local ____temp_73
    if pd.rvAt ~= nil then
        ____temp_73 = reserved[pid]
    else
        ____temp_73 = nil
    end
    local rv = ____temp_73
    local t = best.t
    local creep = t.creep
    local age = DotaTime() - now
    local ____temp_74
    if cast == nil then
        ____temp_74 = nil
    else
        ____temp_74 = bot:GetAbilityByName(cast.spell.name)
    end
    local ability = ____temp_74
    if k == "sp" and (ability == nil or ability == nil) then
        best.noteCast(false, "refused")
        return false
    end
    local ok = Tasks.Start(
        bot,
        {
            name = "creep",
            host = HOST,
            preemptAfter = 1,
            stallAfter = 4,
            onEnd = function(r) return finish(bot, r) end
        },
        function(ctx)
            if k == "sp" then
                return ctx.cast(ability, {target = creep, timeout = cast.timing.land + 1})
            end
            local opts = {
                target = creep,
                maxWait = math.max(0, t.eta - age) + ____exports.SETTINGS.WaitSlack,
                interruptIf = function() return mateTakes(bot, creep) or yieldNow(pid, best.cid) or towerLost(bot, pid) end,
                onPhase = function(p, at) return onPhase(pid, p, at) end
            }
            if k == "dn" then
                return ctx.deny(opts)
            end
            if tr == nil then
                return ctx.lastHit(opts)
            end
            return towerAttempt(
                ctx,
                bot,
                pid,
                creep,
                opts
            )
        end
    )
    if not ok then
        if k == "sp" then
            best.noteCast(false, "refused")
        else
            best.note(false, "refused")
            pd.seen.why = "refused"
        end
        if rv ~= nil then
            drop(bot, pid, rv, "refused")
        end
        return false
    end
    if rv ~= nil then
        reserved[pid] = nil
    end
    local aid = Telemetry.NextAid(pid)
    if k == "sp" then
        best.noteCast(true, nil, aid)
    else
        best.note(true, nil, aid)
    end
    local t0 = DotaTime()
    local a = {
        cid = best.cid,
        creep = best.creep,
        t0 = t0,
        hp0 = math.floor(bot:GetHealth()),
        aid = aid,
        phaseAt = t0,
        spent = {walk = 0, wait = 0, swing = 0},
        tk = 0,
        tks = 0,
        k = k,
        tower = tr and tr.tower,
        ph = 0
    }
    running[pid] = a
    lastCid[pid] = best.cid
    local oc = 0
    for ____, c in ipairs(Claims.ClaimsOn(Claims.CreepTarget(best.cid))) do
        if c.pid ~= pid then
            oc = oc + 1
        end
    end
    local sa = bot:GetAttackTarget()
    local ____startLine_79 = startLine
    local ____array_78 = __TS__SparseArrayNew(bot, best.cid, aid, {walk = t.walk, due = t.due - age})
    local ____temp_77
    if pd.rvAt == nil then
        ____temp_77 = nil
    else
        ____temp_77 = t0 - pd.rvAt
    end
    __TS__SparseArrayPush(
        ____array_78,
        {
            rv = ____temp_77,
            need = need,
            reach = CreepOffer.Reach(bot, best.creep),
            seen = pd.seen,
            now = now,
            sa = sa ~= nil and sa ~= nil and sa == creep,
            lead = lead,
            k = k,
            oc = oc,
            tr = tr,
            cast = cast
        }
    )
    ____startLine_79(__TS__SparseArraySpread(____array_78))
    return true
end
--- The row's `wants`: an offer while an attempt runs (the latch), and while Consider offers its chosen creep to the decider. The
-- row decides at the read (Consider); with a reservation (Ours.CreepReserve) the decider's round offers its start (`startDue`).
local function rowWants(bot, _reads)
    if not ____exports.On(bot) then
        return nil
    end
    Tasks.Tick(bot)
    local pid = bot:GetPlayerID()
    local a = running[pid]
    if a ~= nil then
        return {tgt = "creep:" .. tostring(a.cid)}
    end
    local rv = reserved[pid]
    if rv ~= nil then
        pending[pid] = nil
        return startDue(bot, pid, rv)
    end
    local pd = pending[pid]
    if pd == nil then
        return nil
    end
    return offerOf(bot, pd)
end
WAY = {lh = "attack", dn = "deny", sp = "spell"}
--- The row's verb: one frame of the attempt; true once it has ended.
local function rowStep(bot)
    local pid = bot:GetPlayerID()
    local first = running[pid]
    if first == nil then
        return true
    end
    local now = DotaTime()
    if first.wt == nil then
        first.wt = now - first.t0
    end
    if first.lastStep ~= nil and now - first.lastStep > ____exports.SETTINGS.Round then
        first.tk = first.tk + 1
        first.tks = first.tks + (now - first.lastStep)
    end
    first.lastStep = now
    Tasks.Step(bot, HOST)
    local a = running[pid]
    if a == nil then
        return true
    end
    if a.tin == nil then
        local at = a.creep:GetLocation()
        local me = bot:GetLocation()
        if at ~= nil and at ~= nil then
            local dx = at.x - me.x
            local dy = at.y - me.y
            if math.sqrt(dx * dx + dy * dy) <= CreepOffer.Reach(bot, a.creep) then
                a.tin = DotaTime() - a.t0
            end
        end
    end
    return false
end
--- The decider's row (registered in index.ts, so the decider imports no row). Hard (plan s3).
____exports.ROW = {name = "creep", wants = rowWants, begin = rowBegin, step = rowStep}
return ____exports
