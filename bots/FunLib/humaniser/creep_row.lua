--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
end

local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
end

local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end

local function __TS__ClassExtends(target, base)
    target.____super = base
    local staticMetatable = setmetatable({__index = base}, base)
    setmetatable(target, staticMetatable)
    local baseMetatable = getmetatable(base)
    if baseMetatable then
        if type(baseMetatable.__index) == "function" then
            staticMetatable.__index = baseMetatable.__index
        end
        if type(baseMetatable.__newindex) == "function" then
            staticMetatable.__newindex = baseMetatable.__newindex
        end
    end
    setmetatable(target.prototype, base.prototype)
    if type(base.prototype.__index) == "function" then
        target.prototype.__index = base.prototype.__index
    end
    if type(base.prototype.__newindex) == "function" then
        target.prototype.__newindex = base.prototype.__newindex
    end
    if type(base.prototype.__tostring) == "function" then
        target.prototype.__tostring = base.prototype.__tostring
    end
end

local Error, RangeError, ReferenceError, SyntaxError, TypeError, URIError
do
    local function getErrorStack(self, constructor)
        if debug == nil then
            return nil
        end
        local level = 1
        while true do
            local info = debug.getinfo(level, "f")
            level = level + 1
            if not info then
                level = 1
                break
            elseif info.func == constructor then
                break
            end
        end
        if __TS__StringIncludes(_VERSION, "Lua 5.0") then
            return debug.traceback(("[Level " .. tostring(level)) .. "]")
        else
            return debug.traceback(nil, level)
        end
    end
    local function wrapErrorToString(self, getDescription)
        return function(self)
            local description = getDescription(self)
            local caller = debug.getinfo(3, "f")
            local isClassicLua = __TS__StringIncludes(_VERSION, "Lua 5.0") or _VERSION == "Lua 5.1"
            if isClassicLua or caller and caller.func ~= error then
                return description
            else
                return (description .. "\n") .. tostring(self.stack)
            end
        end
    end
    local function initErrorClass(self, Type, name)
        Type.name = name
        return setmetatable(
            Type,
            {__call = function(____, _self, message) return __TS__New(Type, message) end}
        )
    end
    local ____initErrorClass_1 = initErrorClass
    local ____class_0 = __TS__Class()
    ____class_0.name = ""
    function ____class_0.prototype.____constructor(self, message)
        if message == nil then
            message = ""
        end
        self.message = message
        self.name = "Error"
        self.stack = getErrorStack(nil, self.constructor.new)
        local metatable = getmetatable(self)
        if metatable and not metatable.__errorToStringPatched then
            metatable.__errorToStringPatched = true
            metatable.__tostring = wrapErrorToString(nil, metatable.__tostring)
        end
    end
    function ____class_0.prototype.__tostring(self)
        return self.message ~= "" and (self.name .. ": ") .. self.message or self.name
    end
    Error = ____initErrorClass_1(nil, ____class_0, "Error")
    local function createErrorClass(self, name)
        local ____initErrorClass_3 = initErrorClass
        local ____class_2 = __TS__Class()
        ____class_2.name = ____class_2.name
        __TS__ClassExtends(____class_2, Error)
        function ____class_2.prototype.____constructor(self, ...)
            ____class_2.____super.prototype.____constructor(self, ...)
            self.name = name
        end
        return ____initErrorClass_3(nil, ____class_2, name)
    end
    RangeError = createErrorClass(nil, "RangeError")
    ReferenceError = createErrorClass(nil, "ReferenceError")
    SyntaxError = createErrorClass(nil, "SyntaxError")
    TypeError = createErrorClass(nil, "TypeError")
    URIError = createErrorClass(nil, "URIError")
end

local function __TS__ObjectGetOwnPropertyDescriptors(object)
    local metatable = getmetatable(object)
    if not metatable then
        return {}
    end
    return rawget(metatable, "_descriptors") or ({})
end

local function __TS__Delete(target, key)
    local descriptors = __TS__ObjectGetOwnPropertyDescriptors(target)
    local descriptor = descriptors[key]
    if descriptor then
        if not descriptor.configurable then
            error(
                __TS__New(
                    TypeError,
                    ((("Cannot delete property " .. tostring(key)) .. " of ") .. tostring(target)) .. "."
                ),
                0
            )
        end
        descriptors[key] = nil
        return true
    end
    target[key] = nil
    return true
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
-- End of Lua Library inline imports
local ____exports = {}
local enterPhase, onPhase, running
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
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
function enterPhase(a, p, t)
    if a.phase ~= nil then
        local ____a_spent_0, ____a_phase_1 = a.spent, a.phase
        ____a_spent_0[____a_phase_1] = ____a_spent_0[____a_phase_1] + (t - a.phaseAt)
    end
    a.phase = p
    a.phaseAt = t
    if p == "swing" and a.so == nil then
        a.so = t - a.t0
    end
end
function onPhase(pid, p, t)
    local a = running[pid]
    if a ~= nil then
        enterPhase(a, p, t)
    end
end
____exports.SETTINGS = {NearWalk = 1, WaitSlack = 1.5, EarlyLead = 3, Round = 0.4}
--- The mode the decider hosts its rows in: the engine steps the attempt's task under it.
local HOST = BotMode.Farm
--- The cell rule: undefined when the creep is in a claimed cell, else why not. In order: `kind` (neither kind this hero acts on: `KindOf`),
-- `late` (cannot arrive), `outdmg` (an enemy hero in range of the creep hits harder), `race` (a walk-in: an enemy hero
-- with a hit at least ours can be in range of the creep before it comes due), `covered` (a walk past NearWalk to a spot
-- an enemy hero's range covers), `tower` (inside our tower's range: the under-tower hit is a later widening, s6), `etower`
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
    if f.otw and f.k == "lh" then
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
--- About to come due: due within the walk plus `lead` (`Lead`: the longer of one own attack cycle, `GetSecondsPerAttack`, and `EarlyLead`), so the hero is in range and
-- facing with a full cycle to spare whatever its cooldown. Round 0 of oha-creep-ranged went at walk + 0.4 s and lost 48 of
-- 122 uncut attempts with no swing on the creep (re-read 25/11/2026). The creep offer asks laneTargets for creeps due within
-- at least one cycle (`CreepOffer.Within`), so such a creep is offered by then.
function ____exports.Due(walk, due, lead)
    return due <= walk + lead
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
local seen = {}
--- The record of each listed creep, new ones made now; records of creeps this read does not list are dropped.
local function touch(pid, cands, now)
    local m = seen[pid]
    if m == nil then
        m = {}
        seen[pid] = m
    end
    for ____, c in ipairs(cands) do
        local r = m[c.cid]
        if r == nil then
            m[c.cid] = {at = now, first = now}
        else
            r.at = now
        end
    end
    for cid, r in pairs(m) do
        if r.at ~= now then
            __TS__Delete(m, cid)
        end
    end
    return m
end
--- Why the on-time check refused: at the creep's first read about to come due, after a refusal on time for `held` or `acting`, or neither.
local function noTime(r, first)
    if first then
        return "notime_new"
    end
    return (r.ok == "held" or r.ok == "acting" or r.ok == "row") and "notime_" .. r.ok or "notime"
end
--- The one predicate per kind, asked by Consider, Claim (through the facts) and dueNow alike. A last hit: their ranged creep, for a hero whose
-- position does `creep` with Ours.LaneCreeps on. A deny: any of our creeps, for a hero whose position does `deny` with Ours.CreepDeny on.
function ____exports.KindOf(bot, kind, ck)
    local pos = LaneConfig.PositionOf(bot)
    if kind == "lasthit" and ck == "r" and TripTable.Does("creep", pos) and Ours.On("LaneCreeps") then
        return "lh"
    end
    if kind == "deny" and TripTable.Does("deny", pos) and Ours.On("CreepDeny") then
        return "dn"
    end
    return nil
end
--- The creep is of a kind this hero acts on and about to come due at this read (the first such read is kept).
local function dueNow(bot, c, r, lead, now)
    if ____exports.KindOf(bot, c.t.kind, c.ck) == nil or not ____exports.Due(c.t.walk, c.t.due, lead) then
        return false
    end
    if r.due0 == nil then
        r.due0 = now
    end
    return true
end
running = {}
--- pid -> the creep of the hero's last attempt: one attempt a creep.
local lastCid = {}
local pending = {}
function ____exports.ResetCache()
    for ____, t in ipairs({running, lastCid, seen, pending}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end
function ____exports.On(bot)
    local pos = LaneConfig.PositionOf(bot)
    local lh = TripTable.Does("creep", pos) and Ours.On("LaneCreeps")
    local dn = TripTable.Does("deny", pos) and Ours.On("CreepDeny")
    return (lh or dn) and CreepOffer.MayOffer(bot) and not Drill.Held(bot)
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
local function r2(x)
    return math.floor(x * 100 + 0.5) / 100
end
--- The start line: the creep (`cid`, as on the read's line and `creep_death`), the walk and due at go, the hero's attack range (`rng`)
-- and the engine's reach on the creep (`rch`), and
-- what the reads saw: `gn` the need at go and `sp` the spare (due less need), `hw` and `hm` the last refusal while about to come
-- due and the hero's mode then (absent when it went at the first such read), `hs` seconds from that first read to the go, `sa` 1
-- when the hero's attack target was the creep, `nw` 1 when this read was the first to list the creep, `k` `lh` or `dn`, `ld` the lead in force (s: one attack
-- cycle, or `EarlyLead`).
local function startLine(bot, cid, aid, t, g)
    Telemetry.Event(
        "job",
        {
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
            }
        }
    )
end
--- The end line: `pw`, `pq`, `ps` the seconds in each phase of the verb (walk, wait, swing), `so` the seconds from the go to the swing order (-1 none), `tk` how many times another
-- mode had the hero (a gap between steps over `Round`) and `tks` the seconds it did, `wt` the seconds from the go to the row's first step (-1 never), `tin` the seconds to first in the verb's range (-1 never), `sw` 1 when the verb ordered its swing (its message
-- is the post-swing one, which carries `end=`; absent on a cut, whose message is the runner's; 0 with `why=ok` when the hero's count
-- rose from a swing ordered before the verb's, message `hit=other`), `hp0`/`hp1` the hero's HP at the
-- start and end, `msg` the verb's message (what the swing was based on, or what held it).
local function endLine(bot, a, r, cut)
    local msg = r.message
    local sw
    if r.success then
        sw = msg ~= nil and (string.find(msg, "hit=other", 1, true)) == 1 and 0 or 1
    elseif r.reason ~= "preempted" and msg ~= nil then
        sw = (string.find(msg, " end=", 1, true)) ~= nil and 1 or 0
    end
    local ____Telemetry_Event_20 = Telemetry.Event
    local ____array_19 = __TS__SparseArrayNew(
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
        {"cid", a and a.cid}
    )
    local ____temp_8
    if a == nil then
        ____temp_8 = nil
    else
        ____temp_8 = a.so ~= nil and r2(a.so) or -1
    end
    __TS__SparseArrayPush(____array_19, {"so", ____temp_8}, {"tk", a and a.tk})
    local ____temp_11
    if a == nil then
        ____temp_11 = nil
    else
        ____temp_11 = r2(a.tks)
    end
    __TS__SparseArrayPush(____array_19, {"tks", ____temp_11})
    local ____temp_12
    if a == nil then
        ____temp_12 = nil
    else
        ____temp_12 = r2(a.spent.walk)
    end
    __TS__SparseArrayPush(____array_19, {"pw", ____temp_12})
    local ____temp_13
    if a == nil then
        ____temp_13 = nil
    else
        ____temp_13 = r2(a.spent.wait)
    end
    __TS__SparseArrayPush(____array_19, {"pq", ____temp_13})
    local ____temp_14
    if a == nil then
        ____temp_14 = nil
    else
        ____temp_14 = r2(a.spent.swing)
    end
    __TS__SparseArrayPush(____array_19, {"ps", ____temp_14})
    local ____temp_15
    if a == nil then
        ____temp_15 = nil
    else
        ____temp_15 = a.wt ~= nil and r2(a.wt) or -1
    end
    __TS__SparseArrayPush(____array_19, {"wt", ____temp_15})
    local ____temp_16
    if a == nil then
        ____temp_16 = nil
    else
        ____temp_16 = a.tin ~= nil and r2(a.tin) or -1
    end
    __TS__SparseArrayPush(
        ____array_19,
        {"tin", ____temp_16},
        {"sw", sw},
        {"hp0", a and a.hp0},
        {
            "hp1",
            math.floor(bot:GetHealth())
        },
        {"msg", msg}
    )
    ____Telemetry_Event_20(
        "job",
        {__TS__SparseArraySpread(____array_19)}
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
    local now = DotaTime()
    if a ~= nil then
        if a.phase ~= nil then
            local ____a_spent_21, ____a_phase_22 = a.spent, a.phase
            ____a_spent_21[____a_phase_22] = ____a_spent_21[____a_phase_22] + (now - a.phaseAt)
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
        cutBy(bot, r)
    )
end
local function factsOf(bot, c)
    local s = c.facts()
    return {
        k = ____exports.KindOf(bot, c.t.kind, c.ck),
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
        kb = s.kb
    }
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
    for ____, c in ipairs(cands) do
        local why
        local r = recs[c.cid]
        local first = r.due0 == nil
        if ____exports.KindOf(bot, c.t.kind, c.ck) == nil then
            why = "kind"
        elseif not dueNow(
            bot,
            c,
            r,
            lead,
            now
        ) then
            why = "early"
        elseif not ____exports.OnTime(
            ____exports.Need(bot, c.creep),
            c.t.due
        ) then
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
            why = ____exports.Claim(factsOf(bot, c))
        end
        if why ~= nil and why ~= "kind" and why ~= "early" then
            r.why = why
            if string.sub(why, 1, 6) ~= "notime" then
                r.ok = why
            end
            r.mode = why == "held" and HDebug.ModeName(mode) or nil
        end
        if why ~= nil then
            c.note(false, why)
        elseif best == nil or c.t.eta < best.t.eta then
            best = c
        end
    end
    if best == nil then
        return
    end
    for ____, c in ipairs(cands) do
        do
            local __continue81
            repeat
                if c == best or ____exports.KindOf(bot, c.t.kind, c.ck) == nil then
                    __continue81 = true
                    break
                end
                c.note(false, "other")
                recs[c.cid].why = "other"
                recs[c.cid].ok = "other"
                __continue81 = true
            until true
            if not __continue81 then
                break
            end
        end
    end
    pending[pid] = {
        best = best,
        k = ____exports.KindOf(bot, best.t.kind, best.ck),
        need = ____exports.Need(bot, best.creep),
        lead = lead,
        now = now,
        seen = recs[best.cid]
    }
    Decider.Offer(bot, ____exports.ROW)
    if pending[pid] == nil then
        return
    end
    pending[pid] = nil
    best.note(false, "refused")
    recs[best.cid].why = "refused"
end
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
    local t = best.t
    local creep = t.creep
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
            local opts = {
                target = creep,
                maxWait = t.eta + ____exports.SETTINGS.WaitSlack,
                interruptIf = function() return mateTakes(bot, creep) end,
                onPhase = function(p, at) return onPhase(pid, p, at) end
            }
            if k == "dn" then
                return ctx.deny(opts)
            end
            return ctx.lastHit(opts)
        end
    )
    if not ok then
        best.note(false, "refused")
        pd.seen.why = "refused"
        return false
    end
    local aid = Telemetry.NextAid(pid)
    best.note(true, nil, aid)
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
        k = k
    }
    running[pid] = a
    lastCid[pid] = best.cid
    local sa = bot:GetAttackTarget()
    startLine(
        bot,
        best.cid,
        aid,
        t,
        {
            need = need,
            reach = CreepOffer.Reach(bot, best.creep),
            seen = pd.seen,
            now = now,
            sa = sa ~= nil and sa ~= nil and sa == creep,
            lead = lead,
            k = k
        }
    )
    return true
end
--- The row's `wants`: an offer while an attempt runs (the latch), and while Consider offers its chosen creep to the decider. The
-- row decides at the read (Consider), never at the decider's round.
local function rowWants(bot)
    if not ____exports.On(bot) then
        return nil
    end
    Tasks.Tick(bot)
    local pid = bot:GetPlayerID()
    local a = running[pid]
    if a ~= nil then
        return {tgt = "creep:" .. tostring(a.cid)}
    end
    local pd = pending[pid]
    if pd == nil then
        return nil
    end
    return {
        tgt = "creep:" .. tostring(pd.best.cid),
        by = pd.now + pd.best.t.due - pd.need
    }
end
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
