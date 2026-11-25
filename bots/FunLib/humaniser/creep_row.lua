--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
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
____exports.SETTINGS = {NearWalk = 1, Lead = 0.4, WaitSlack = 1.5}
--- The mode the decider hosts its rows in: the engine steps the attempt's task under it.
local HOST = BotMode.Farm
--- The cell rule: undefined when the creep is in a claimed cell, else why not. In order: `kind` (not their ranged creep),
-- `late` (cannot arrive), `outdmg` (an enemy hero in range of the creep hits harder), `covered` (a walk past NearWalk to a spot
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
--- About to come due: a swing ordered on arrival is due within Lead of it.
function ____exports.Due(walk, due)
    return due <= walk + ____exports.SETTINGS.Lead
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
local function jobLine(bot, phase, why, cut)
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "creep"},
            {"phase", phase},
            {"why", why},
            {"host", HOST},
            {"cut", cut}
        }
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
    running[bot:GetPlayerID()] = nil
    jobLine(
        bot,
        "end",
        r.success and "ok" or r.reason,
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
        ptw = s.path.tower,
        otw = s.otw,
        g2 = s.given.due,
        kb = s.kb
    }
end
--- The read's hook (CreepOffer.SetRow), at each read of a hero: notes why each candidate is not taken and starts an attempt on
-- the claimed creep closest to due. Reasons asked before the facts are read: `busy` (an attempt runs), `kind`, `early` (not
-- yet about to come due), `acting`, `stock` (stock is attacking it), `tried` (this creep's attempt has ended); then Claim's;
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
    local target = bot:GetAttackTarget()
    local busy = acting(bot)
    local best
    for ____, c in ipairs(cands) do
        local why
        if c.t.kind ~= "lasthit" or c.ck ~= "r" then
            why = "kind"
        elseif not ____exports.Due(c.t.walk, c.t.due) then
            why = "early"
        elseif busy then
            why = "acting"
        elseif target == c.creep then
            why = "stock"
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
    running[pid] = {cid = best.cid}
    lastCid[pid] = best.cid
    jobLine(bot, "start", "trigger")
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
    if running[bot:GetPlayerID()] == nil then
        return true
    end
    Tasks.Step(bot, HOST)
    return running[bot:GetPlayerID()] == nil
end
--- The decider's row (registered in index.ts, so the decider imports no row). Soft (plan s3).
____exports.ROW = {name = "creep", applies = rowApplies, step = rowStep, soft = true}
return ____exports
