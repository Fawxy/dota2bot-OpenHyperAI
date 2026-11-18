--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
local WaveHold = require(GetScriptDirectory().."/FunLib/humaniser/states/wave_hold")
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local LaneAggro = require(GetScriptDirectory().."/FunLib/humaniser/lane_aggro")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local function ranks(n, ...)
    local positions = {...}
    local r = {
        [1] = nil,
        [2] = nil,
        [3] = nil,
        [4] = nil,
        [5] = nil
    }
    for ____, p in ipairs(positions) do
        r[p] = n
    end
    return r
end
local supports = {4, 5}
local cores = {1, 2, 3}
local all = {
    1,
    2,
    3,
    4,
    5
}
--- The engine body's last-hit or deny swing in progress must not be overridden by the rows below (slice 4).
local bodyHit = {
    name = "body_hit",
    rank = ranks(
        10,
        unpack(all)
    ),
    drill = true,
    wants = function(_bot, ctx) return ctx.bodyBusy() end,
    run = function(_bot, ctx) return ctx.stepBody() end
}
--- User rule 02/11/2026: the support's lane hits before anything else (denies, and since slice support-lane-hits the last hits
-- its claims give it). Wants the frame while the body is in an attempt or would start one now; its scan picks the creep.
local supportHit = {
    name = "support_hit",
    rank = ranks(
        20,
        unpack(supports)
    ),
    drill = true,
    wants = function(bot, ctx)
        if not ctx.enabled() or not Laning.OwnsSupportHits(bot) or not ctx.bodyRunning() then
            return false
        end
        local label = ctx.bodyLabel()
        return label == "deny" or label == "lasthit" or Laning.HitOffered(bot)
    end,
    run = function(_bot, ctx) return ctx.stepBody() end
}
--- Slice lane-aggro: with its lane core away a support draws creeps itself (feed, drag); after its lane hits, before the hold,
-- and only while the body runs (so never inside another state's frame).
local supportAggro = {
    name = "support_aggro",
    rank = ranks(
        30,
        unpack(supports)
    ),
    drill = true,
    wants = function(bot, ctx) return ctx.enabled() and Laning.OwnsSupportHits(bot) and ctx.bodyRunning() and (LaneAggro.Owns(bot) or LaneAggro.Pending(bot)) end,
    run = function(bot) return LaneAggro.Step(bot) end
}
--- Slice support-spot: with no lane hit to take, the body holds the support on our lane spot (states/lane_spot, role support)
-- instead of OHA's harass and PositionThink. Harass is not a lane row: it runs in our attack mode (states/trade), which
-- outbids laning while a harass is on.
local supportHold = {
    name = "support_hold",
    rank = ranks(
        40,
        unpack(supports)
    ),
    drill = true,
    wants = function(bot, ctx) return ctx.enabled() and Laning.OwnsSupportHits(bot) and Laning.OwnsSpot(bot) and ctx.bodyRunning() end,
    run = function(_bot, ctx) return ctx.stepBody() end
}
--- A drill's lane-only core with the wave hold (drill entry `laneHold`): the hold and the draw it started; no other lane aggro
-- draw starts (StepOpen steps only an open one).
local drillHold = {
    name = "drill_hold",
    rank = ranks(
        50,
        unpack(cores)
    ),
    drill = true,
    drillOnly = true,
    wants = function(bot, ctx) return ctx.enabled() and Drill.LaneHold(bot) and ctx.bodyLastHits() end,
    run = function(bot)
        WaveHold.Step(bot)
        return LaneAggro.StepOpen(bot)
    end
}
--- A drill's lane-only core with lane aggro (drill entry `laneAggro`): lane aggro's draws, as `aggro` outside drills.
local drillAggro = {
    name = "drill_aggro",
    rank = ranks(
        60,
        unpack(cores)
    ),
    drill = true,
    drillOnly = true,
    wants = function(bot, ctx) return ctx.enabled() and Drill.LaneAggro(bot) and ctx.bodyLastHits() end,
    run = function(bot) return LaneAggro.Step(bot) end
}
--- Slice lane-aggro: a core's draw (lane_aggro feed, drag) while the laning body runs for it, after the body's running swing and
-- before OHA's techniques. A support draws through `support_aggro` instead.
local aggro = {
    name = "aggro",
    rank = ranks(
        70,
        unpack(cores)
    ),
    drill = false,
    wants = function(_bot, ctx) return ctx.enabled() end,
    run = function(bot, ctx)
        if not ctx.bodyLastHits() then
            return CoreLastHit.Applies(bot) and LaneAggro.StepOpen(bot)
        end
        WaveHold.Step(bot)
        return LaneAggro.Step(bot)
    end
}
--- Ours.LeaveCoreCreep: a swing or auto-attack on a creep a core can take is cancelled by the move.
local etiquette = {
    name = "etiquette",
    rank = ranks(
        80,
        unpack(all)
    ),
    drill = false,
    wants = function() return true end,
    run = function(_bot, ctx) return ctx.etiquette() end
}
--- With etiquette on, a last hit near a protected human is only allowed when the human will miss it, so taking it before a deny
-- is intended. Where the body owns last hits (team slice 4) it takes them and the denies itself.
local ohaLastHit = {
    name = "oha_lh",
    rank = ranks(
        90,
        unpack(all)
    ),
    drill = true,
    wants = function(_bot, ctx) return not ctx.bodyLastHits() and not ctx.bodySupportLastHits() end,
    run = function(_bot, ctx) return ctx.ohaLastHit() end
}
local ohaDeny = {
    name = "oha_deny",
    rank = ranks(
        100,
        unpack(all)
    ),
    drill = true,
    wants = function(_bot, ctx) return not ctx.bodyLastHits() and not ctx.bodySupportHits() end,
    run = function(_bot, ctx) return ctx.ohaDeny() end
}
--- Holds still for a creep OHA's last hit chose to wait on; acts only on a frame `oha_lh` set that wait.
local ohaHold = {
    name = "oha_hold",
    rank = ranks(
        110,
        unpack(all)
    ),
    drill = true,
    wants = function(_bot, ctx) return not ctx.bodyLastHits() end,
    run = function(_bot, ctx) return ctx.ohaHold() end
}
--- The optional local override's Think: runs beside the rows and never ends the frame.
local ohaLocal = {
    name = "oha_local",
    rank = ranks(
        120,
        unpack(all)
    ),
    drill = false,
    wants = function() return true end,
    run = function(_bot, ctx)
        ctx.ohaLocal()
        return false
    end
}
--- The body's step for a frame no row above took. A support whose body owns its lane hits but not its harass keeps OHA's
-- positioning: the body's hold would cancel its Valve attacks on heroes (docs/team/research/core-time-diagnosis.md).
local body = {
    name = "body",
    rank = ranks(
        130,
        unpack(all)
    ),
    drill = true,
    wants = function(_bot, ctx) return not ctx.bodySupportHits() end,
    run = function(_bot, ctx) return ctx.stepBody() end
}
--- OHA's PositionThink: the fallback that always acts.
local ohaPos = {
    name = "oha_pos",
    rank = ranks(
        140,
        unpack(all)
    ),
    drill = true,
    wants = function() return true end,
    run = function(_bot, ctx) return ctx.ohaPosition() end
}
____exports.ROWS = {
    bodyHit,
    supportHit,
    supportAggro,
    supportHold,
    drillHold,
    drillAggro,
    aggro,
    etiquette,
    ohaLastHit,
    ohaDeny,
    ohaHold,
    ohaLocal,
    body,
    ohaPos
}
local function build(pos, laneOnly)
    local out = {}
    for ____, r in ipairs(____exports.ROWS) do
        do
            local __continue36
            repeat
                if r.rank[pos] == nil or laneOnly and not r.drill or not laneOnly and r.drillOnly == true then
                    __continue36 = true
                    break
                end
                out[#out + 1] = r
                __continue36 = true
            until true
            if not __continue36 then
                break
            end
        end
    end
    table.sort(
        out,
        function(a, b) return a.rank[pos] < b.rank[pos] end
    )
    return out
end
local ORDERS = {}
for ____, p in ipairs({
    1,
    2,
    3,
    4,
    5
}) do
    ORDERS[tostring(p) .. ":0"] = build(p, false)
    ORDERS[tostring(p) .. ":1"] = build(p, true)
end
--- The rows that run for a position, in order. An undefined or unknown position takes position 1's order.
function ____exports.Order(pos, laneOnly)
    return ORDERS[(tostring(pos) .. ":") .. tostring(laneOnly and 1 or 0)] or ORDERS["1:" .. tostring(laneOnly and 1 or 0)]
end
local CUT_EVERY = 5
local cutState = {}
local skipScratch = {}
local function cutDue(st, row, n, now)
    if st.row ~= row or st.nSkipped ~= n or now < st.at or now - st.at >= CUT_EVERY then
        return true
    end
    do
        local i = 0
        while i < n do
            if st.skipped[i + 1] ~= skipScratch[i + 1] then
                return true
            end
            i = i + 1
        end
    end
    return false
end
local function cut(bot, pos, laneOnly, row, n)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local ____temp_0 = cutState[pid] or ({skipped = {}, nSkipped = 0, at = 0})
    cutState[pid] = ____temp_0
    local st = ____temp_0
    if not cutDue(st, row, n, now) then
        return
    end
    st.row = row
    st.nSkipped = n
    st.at = now
    do
        local i = 0
        while i < n do
            st.skipped[i + 1] = skipScratch[i + 1]
            i = i + 1
        end
    end
    Telemetry.Event(
        "cut",
        {
            {"pid", pid},
            {"kind", "lane"},
            {"pos", pos},
            {"row", row},
            {
                "skip",
                n > 0 and table.concat(skipScratch, ",", 1, n) or nil
            },
            {"lo", laneOnly and 1 or 0}
        }
    )
end
--- Walks the bot's order and returns the name of the row that acted (the fallback row always does).
function ____exports.Walk(bot, ctx)
    local pos = LaneConfig.PositionOf(bot)
    local laneOnly = Overrides.LaneOnly(bot)
    local order = ____exports.Order(pos or 1, laneOnly)
    local n = 0
    local acted = order[#order].name
    for ____, r in ipairs(order) do
        do
            local __continue51
            repeat
                local t0 = Telemetry.DeepT0()
                local wants = r.wants(bot, ctx)
                if t0 ~= nil then
                    Telemetry.DeepAdd(("lane_table.Walk:" .. r.name) .. ".wants", t0)
                end
                if not wants then
                    __continue51 = true
                    break
                end
                local t1 = Telemetry.DeepT0()
                local ran = r.run(bot, ctx)
                if t1 ~= nil then
                    Telemetry.DeepAdd(("lane_table.Walk:" .. r.name) .. ".run", t1)
                end
                if ran then
                    acted = r.name
                    break
                end
                local ____n_1 = n
                n = ____n_1 + 1
                skipScratch[____n_1 + 1] = r.name
                __continue51 = true
            until true
            if not __continue51 then
                break
            end
        end
    end
    if Telemetry.IsEnabled() and Telemetry.Get().Cut == true then
        cut(
            bot,
            pos,
            laneOnly,
            acted,
            n
        )
    end
    return acted
end
return ____exports
