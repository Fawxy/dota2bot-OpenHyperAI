--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneOffers = require(GetScriptDirectory().."/FunLib/humaniser/lane_offers")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
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
--- A pos 4 or 5 assigned to a side lane, whatever the switches say: the hero the line's reader names.
function ____exports.IsSideSupport(bot)
    if not bot:IsBot() then
        return false
    end
    local pos = LaneConfig.PositionOf(bot)
    if pos ~= 4 and pos ~= 5 then
        return false
    end
    local lane = bot:GetAssignedLane()
    return lane == Lane.Top or lane == Lane.Bot
end
--- OHA's own action holds the hero (pull_job's and rune_job's check: a queued TP, a cast or channel).
local function acting(bot)
    return bot:NumQueuedActions() > 0 or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility()
end
--- The reachable deny closest to coming due, else undefined. Undefined too while the engine bundle is not loaded.
function ____exports.Offer(bot)
    local verbs = Tasks.Verbs()
    if verbs == nil then
        return nil
    end
    local best
    for ____, t in ipairs(verbs.laneTargets(bot, {within = 1, lastHit = false})) do
        do
            local __continue12
            repeat
                if t.kind ~= "deny" or not LaneOffers.Reachable(t) then
                    __continue12 = true
                    break
                end
                if best == nil or t.eta < best.eta then
                    best = t
                end
                __continue12 = true
            until true
            if not __continue12 then
                break
            end
        end
    end
    return best
end
local function choiceLine(bot, slot, go, why, t, src)
    local function r2(x)
        return math.floor(x * 100 + 0.5) / 100
    end
    Telemetry.Event(
        "choice",
        {
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
        }
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
    running[bot:GetPlayerID()] = nil
    jobLine(
        bot,
        "end",
        r.success and "ok" or r.reason .. (r.message ~= nil and ":" .. r.message or ""),
        cutBy(bot, r)
    )
end
local function rowOn(bot)
    return Ours.On("SupportDeny") and ____exports.IsSideSupport(bot) and not Drill.Held(bot)
end
--- The shadow (switch off, or the other team under Ours.Team): the same offer, logged once per creep, nothing ordered.
local function shadow(bot)
    if not Telemetry.IsEnabled() or not ____exports.IsSideSupport(bot) or Drill.Held(bot) then
        return
    end
    if not LaneConfig.InLaningPhase() or not bot:IsAlive() then
        return
    end
    local t = ____exports.Offer(bot)
    if t == nil then
        return
    end
    local cid = Telemetry.CreepId(t.creep)
    if firstLine(bot, cid, false) then
        choiceLine(
            bot,
            slotOf(cid),
            false,
            "off",
            t,
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
    local t = ____exports.Offer(bot)
    if t == nil then
        return false
    end
    local cid = Telemetry.CreepId(t.creep)
    local slot = slotOf(cid)
    if acting(bot) then
        if firstLine(bot, cid, false) then
            choiceLine(
                bot,
                slot,
                false,
                "acting",
                t
            )
        end
        return false
    end
    local creep = t.creep
    local ok = Tasks.Start(
        bot,
        {
            name = "deny",
            host = HOST,
            preemptAfter = 1,
            stallAfter = 4,
            onEnd = function(r) return finish(bot, r) end
        },
        function(ctx) return ctx.deny({target = creep, maxWait = t.eta + ____exports.WAIT_SLACK}) end
    )
    if not ok then
        if firstLine(bot, cid, false) then
            choiceLine(
                bot,
                slot,
                false,
                "refused",
                t
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
            t
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
