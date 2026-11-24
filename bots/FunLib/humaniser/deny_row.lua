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
local Lane = ____dota.Lane
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHits = require(GetScriptDirectory().."/FunLib/humaniser/lane_hits")
local LaneOffers = require(GetScriptDirectory().."/FunLib/humaniser/lane_offers")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- The mode the decider hosts its rows in: the engine steps the deny's task under it.
local HOST = BotMode.Farm
--- The wait for the creep to come due, after its eta: laneFarm's own (`maxWait` eta + 1.5 s, engine/docs/API.md). `judgement`.
____exports.WAIT_SLACK = 1.5
local running = {}
--- Per hero: the creeps already given their choice line, by CreepId, with the line's `go`.
local logged = {}
function ____exports.ResetCache()
    for ____, t in ipairs({running, logged}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end
--- A bot whose position the trip table lets deny, whatever the switches say: the hero the line's reader names.
function ____exports.MayDeny(bot)
    return bot:IsBot() and TripTable.Does(
        "deny",
        LaneConfig.PositionOf(bot)
    )
end
--- OHA's own action holds the hero (pull_job's and rune_job's check: a queued TP, a cast or channel).
local function acting(bot)
    return bot:NumQueuedActions() > 0 or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility()
end
local LANES = {Lane.Top, Lane.Mid, Lane.Bot}
--- The teammate (never the bot itself) whose hit kills the creep first, else undefined.
function ____exports.MateOn(bot, creep)
    local team = bot:GetTeam()
    local row
    for ____, lane in ipairs(LANES) do
        row = LaneHits.Of(team, lane, creep)
        if row ~= nil then
            break
        end
    end
    if row == nil then
        return nil
    end
    local k = LaneHits.KillingHit(row)
    if k == nil or k.by ~= "hero" and k.by ~= "self" then
        return nil
    end
    local a = k.attacker
    if a == bot or a:GetTeam() ~= team then
        return nil
    end
    return {
        pid = a:GetPlayerID(),
        commit = k.commit
    }
end
--- The reachable deny closest to coming due that no teammate's hit takes. When a teammate's takes every reachable one, the
-- nearest-due of those comes back with its `mate` (the row logs it and holds nothing). Undefined when nothing is reachable,
-- or while the engine bundle is not loaded.
function ____exports.Offer(bot)
    local verbs = Tasks.Verbs()
    if verbs == nil then
        return nil
    end
    local free
    local taken
    for ____, t in ipairs(verbs.laneTargets(bot, {within = 1, lastHit = false})) do
        do
            local __continue17
            repeat
                if t.kind ~= "deny" or not LaneOffers.Reachable(t) then
                    __continue17 = true
                    break
                end
                if free ~= nil and t.eta >= free.eta then
                    __continue17 = true
                    break
                end
                local mate = ____exports.MateOn(bot, t.creep)
                if mate == nil then
                    free = t
                elseif taken == nil or t.eta < taken.t.eta then
                    taken = {t = t, mate = mate}
                end
                __continue17 = true
            until true
            if not __continue17 then
                break
            end
        end
    end
    return free ~= nil and ({t = free}) or taken
end
local function choiceLine(bot, slot, go, why, o, src)
    local t = o.t
    local function r2(x)
        return math.floor(x * 100 + 0.5) / 100
    end
    local ____Telemetry_Event_3 = Telemetry.Event
    local ____array_2 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", "deny"},
        {"want", 1},
        {"go", go and 1 or 0},
        {"why", why},
        {"src", src or "own"},
        {
            "lane",
            bot:GetAssignedLane()
        },
        {"slot", slot},
        {
            "walk",
            r2(t.walk)
        },
        {
            "due",
            r2(t.due)
        },
        {
            "dies",
            t.dies == math.huge and -1 or r2(t.dies)
        }
    )
    local ____opt_0 = o.mate
    __TS__SparseArrayPush(
        ____array_2,
        {"mate", ____opt_0 and ____opt_0.pid},
        {
            "mc",
            o.mate ~= nil and r2(o.mate.commit) or nil
        }
    )
    ____Telemetry_Event_3(
        "choice",
        {__TS__SparseArraySpread(____array_2)}
    )
end
--- Once per creep and hero: true the first time (and the first time it goes), so a line goes out only then.
local function firstLine(bot, cid, go)
    local pid = bot:GetPlayerID()
    local seen = logged[pid]
    if seen == nil then
        seen = {}
        logged[pid] = seen
    end
    local was = seen[cid]
    if was == 1 or was == 0 and not go then
        return false
    end
    seen[cid] = go and 1 or 0
    return true
end
--- Slot of a creep's line: the second it was first offered, to 0.1 s.
local slots = {}
local function slotOf(cid)
    local s = slots[cid]
    if s == nil then
        s = math.floor(DotaTime() * 10) / 10
        slots[cid] = s
    end
    return s
end
local function jobLine(bot, phase, why, cut)
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "deny"},
            {"phase", phase},
            {"why", why},
            {"host", HOST},
            {"cut", cut}
        }
    )
end
--- As the pull's: a deny the engine ends because the host lost the hero names what took it.
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
    local ____opt_4 = running[pid]
    local mate = ____opt_4 and ____opt_4.mate
    running[pid] = nil
    local why = r.success and "ok" or (r.reason == "interrupted" and mate ~= nil and "mate" or r.reason .. (r.message ~= nil and ":" .. r.message or ""))
    jobLine(
        bot,
        "end",
        why,
        cutBy(bot, r)
    )
end
local function rowOn(bot)
    return Ours.On("Deny") and ____exports.MayDeny(bot) and not Drill.Held(bot)
end
--- The shadow (switch off, or the other team under Ours.Team): the same offer, logged once per creep, nothing ordered.
local function shadow(bot)
    if not Telemetry.IsEnabled() or not ____exports.MayDeny(bot) or Drill.Held(bot) then
        return
    end
    if not LaneConfig.InLaningPhase() or not bot:IsAlive() then
        return
    end
    local o = ____exports.Offer(bot)
    if o == nil then
        return
    end
    local cid = Telemetry.CreepId(o.t.creep)
    if firstLine(bot, cid, false) then
        choiceLine(
            bot,
            slotOf(cid),
            false,
            "off",
            o,
            "shadow"
        )
    end
end
--- The row's `applies`, asked every scoring round: true while an attempt runs (the latch) or as one starts.
local function rowApplies(bot)
    if not rowOn(bot) then
        shadow(bot)
        return false
    end
    local pid = bot:GetPlayerID()
    Tasks.Tick(bot)
    if running[pid] ~= nil then
        return true
    end
    if not LaneConfig.InLaningPhase() or not bot:IsAlive() then
        return false
    end
    local o = ____exports.Offer(bot)
    if o == nil then
        return false
    end
    local t = o.t
    local cid = Telemetry.CreepId(t.creep)
    local slot = slotOf(cid)
    if o.mate ~= nil then
        if firstLine(bot, cid, false) then
            choiceLine(
                bot,
                slot,
                false,
                "mate",
                o
            )
        end
        return false
    end
    if acting(bot) then
        if firstLine(bot, cid, false) then
            choiceLine(
                bot,
                slot,
                false,
                "acting",
                o
            )
        end
        return false
    end
    local creep = t.creep
    local function mateTakes()
        local m = ____exports.MateOn(bot, creep)
        local a = running[pid]
        if m ~= nil and a ~= nil then
            a.mate = m.pid
        end
        return m ~= nil
    end
    local ok = Tasks.Start(
        bot,
        {
            name = "deny",
            host = HOST,
            preemptAfter = 1,
            stallAfter = 4,
            onEnd = function(r) return finish(bot, r) end
        },
        function(ctx) return ctx.deny({target = creep, maxWait = t.eta + ____exports.WAIT_SLACK, interruptIf = mateTakes}) end
    )
    if not ok then
        if firstLine(bot, cid, false) then
            choiceLine(
                bot,
                slot,
                false,
                "refused",
                o
            )
        end
        return false
    end
    if firstLine(bot, cid, true) then
        choiceLine(
            bot,
            slot,
            true,
            nil,
            o
        )
    end
    running[pid] = {cid = cid, slot = slot}
    jobLine(bot, "start", "trigger")
    return true
end
--- The row's verb: one frame of the deny; true once it has ended.
local function rowStep(bot)
    if running[bot:GetPlayerID()] == nil then
        return true
    end
    Tasks.Step(bot, HOST)
    return running[bot:GetPlayerID()] == nil
end
--- The decider's row (registered in index.ts, so the decider imports no row). Soft (plan s3): Valve's attack, item, evasive
-- and defend-ally outbid it when they want the hero; on the hard hold the supports lost about a quarter of their seconds in
-- attack mode (batch sdeny1).
____exports.ROW = {name = "deny", applies = rowApplies, step = rowStep, soft = true}
return ____exports
