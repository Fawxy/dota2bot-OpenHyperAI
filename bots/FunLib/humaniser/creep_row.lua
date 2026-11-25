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
-- End of Lua Library inline imports
local ____exports = {}
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
____exports.SETTINGS = {NearWalk = 1, WaitSlack = 1.5}
--- The mode the decider hosts its rows in: the engine steps the attempt's task under it.
local HOST = BotMode.Farm
--- The cell rule: undefined when the creep is in a claimed cell, else why not. In order: `kind` (not their ranged creep),
-- `late` (cannot arrive), `outdmg` (an enemy hero in range of the creep hits harder), `race` (a walk-in: an enemy hero
-- with a hit at least ours can be in range of the creep before it comes due), `covered` (a walk past NearWalk to a spot
-- an enemy hero's range covers), `tower` (inside our tower's range: the under-tower hit is a later widening, s6), `etower`
-- (the stand spot is inside their tower's), `given` (a walk-in: another target comes due where the hero stands before it is back),
-- `mate` (a teammate's hit kills it first).
function ____exports.Claim(f)
    if f.kind ~= "lasthit" or f.ck ~= "r" then
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
    if f.otw then
        return "tower"
    end
    if f.ptw then
        return "etower"
    end
    if f.walk > 0 and f.g2 > 0 then
        return "given"
    end
    if f.kb == "mate" then
        return "mate"
    end
    return nil
end
--- About to come due: due within the walk plus `lead`, one own attack cycle (`GetSecondsPerAttack`), so the hero is in range and
-- facing with a full cycle to spare whatever its cooldown. Round 0 of oha-creep-ranged went at walk + 0.4 s and lost 48 of
-- 122 uncut attempts with no swing on the creep (re-read 25/11/2026). The creep offer asks laneTargets for creeps due within
-- at least one cycle (`CreepOffer.Within`), so such a creep is offered by then.
function ____exports.Due(walk, due, lead)
    return due <= walk + lead
end
local running = {}
--- pid -> the creep of the hero's last attempt: one attempt a creep.
local lastCid = {}
function ____exports.ResetCache()
    for ____, t in ipairs({running, lastCid}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end
function ____exports.On(bot)
    return Ours.On("LaneCreeps") and CreepOffer.MayOffer(bot) and not Drill.Held(bot)
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
--- The start line: the creep (`cid`, as on the read's line and `creep_death`), the walk and due at go, the hero's attack range.
local function startLine(bot, cid, t)
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "creep"},
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
            }
        }
    )
end
--- The end line: `tin` the seconds to first in the verb's range (-1 never), `sw` 1 when the verb ordered its swing (its message
-- is the post-swing one, which carries `end=`; absent on a cut, whose message is the runner's), `hp0`/`hp1` the hero's HP at the
-- start and end, `msg` the verb's message (what the swing was based on, or what held it).
local function endLine(bot, a, r, cut)
    local msg = r.message
    local sw
    if r.success then
        sw = 1
    elseif r.reason ~= "preempted" and msg ~= nil then
        sw = (string.find(msg, " end=", 1, true)) ~= nil and 1 or 0
    end
    local ____Telemetry_Event_6 = Telemetry.Event
    local ____array_5 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"job", "creep"},
        {"phase", "end"},
        {"why", r.success and "ok" or r.reason},
        {"host", HOST},
        {"cut", cut},
        {"cid", a and a.cid}
    )
    local ____temp_2
    if a == nil then
        ____temp_2 = nil
    else
        ____temp_2 = a.tin ~= nil and r2(a.tin) or -1
    end
    __TS__SparseArrayPush(
        ____array_5,
        {"tin", ____temp_2},
        {"sw", sw},
        {"hp0", a and a.hp0},
        {
            "hp1",
            math.floor(bot:GetHealth())
        },
        {"msg", msg}
    )
    ____Telemetry_Event_6(
        "job",
        {__TS__SparseArraySpread(____array_5)}
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
    endLine(
        bot,
        a,
        r,
        cutBy(bot, r)
    )
end
local function factsOf(c)
    local s = c.facts()
    return {
        kind = c.t.kind,
        ck = c.ck,
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
--- The read's hook (CreepOffer.SetRow), at each read of a hero: notes why each candidate is not taken and starts an attempt on
-- the claimed creep closest to due. Reasons asked before the facts are read: `busy` (an attempt runs), `kind`, `early` (not
-- yet about to come due), `acting`, `tried` (this creep's attempt has ended); then Claim's;
-- `refused` (the task runner said no).
function ____exports.Consider(bot, cands)
    if not ____exports.On(bot) then
        return
    end
    local pid = bot:GetPlayerID()
    if running[pid] ~= nil then
        for ____, c in ipairs(cands) do
            c.note(false, "busy")
        end
        return
    end
    if Tasks.Jobs() == nil then
        return
    end
    local busy = acting(bot)
    local lead = CreepOffer.AttackCycle(bot)
    local best
    for ____, c in ipairs(cands) do
        local why
        if c.t.kind ~= "lasthit" or c.ck ~= "r" then
            why = "kind"
        elseif not ____exports.Due(c.t.walk, c.t.due, lead) then
            why = "early"
        elseif busy then
            why = "acting"
        elseif lastCid[pid] == c.cid then
            why = "tried"
        else
            why = ____exports.Claim(factsOf(c))
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
        if c ~= best and c.t.kind == "lasthit" and c.ck == "r" then
            c.note(false, "other")
        end
    end
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
        function(ctx) return ctx.lastHit({
            target = creep,
            maxWait = t.eta + ____exports.SETTINGS.WaitSlack,
            interruptIf = function() return mateTakes(bot, creep) end
        }) end
    )
    if not ok then
        best.note(false, "refused")
        return
    end
    best.note(true)
    running[pid] = {
        cid = best.cid,
        creep = best.creep,
        t0 = DotaTime(),
        hp0 = math.floor(bot:GetHealth())
    }
    lastCid[pid] = best.cid
    startLine(bot, best.cid, t)
end
--- The row's `applies`: true while an attempt runs (the latch). The attempt starts at the read (Consider), never here.
local function rowApplies(bot)
    if not ____exports.On(bot) then
        return false
    end
    Tasks.Tick(bot)
    return running[bot:GetPlayerID()] ~= nil
end
--- The row's verb: one frame of the attempt; true once it has ended.
local function rowStep(bot)
    local pid = bot:GetPlayerID()
    if running[pid] == nil then
        return true
    end
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
            if math.sqrt(dx * dx + dy * dy) <= bot:GetAttackRange() then
                a.tin = DotaTime() - a.t0
            end
        end
    end
    return false
end
--- The decider's row (registered in index.ts, so the decider imports no row). Soft (plan s3).
____exports.ROW = {name = "creep", applies = rowApplies, step = rowStep, soft = true}
return ____exports
