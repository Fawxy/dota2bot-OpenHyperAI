--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local SustainAct = require(GetScriptDirectory().."/FunLib/humaniser/sustain_act")
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
local all = {
    1,
    2,
    3,
    4,
    5
}
--- Sustain step 3 (D6, `Ours.Sustain`): a heal attempt that walks (a tango's tree, a step out to the safe spot, an ally out of
-- cast range) holds the frame until its use starts, so the rows below do not undo the walk.
local sustain = {
    name = "sustain",
    rank = ranks(
        15,
        unpack(all)
    ),
    drill = true,
    wants = function(bot, ctx) return ctx.enabled() and SustainAct.Walking(bot) end,
    run = function(bot) return SustainAct.Step(bot) end
}
local ohaLastHit = {
    name = "oha_lh",
    host = true,
    scans = true,
    rank = ranks(
        90,
        unpack(all)
    ),
    drill = true,
    wants = function() return true end,
    run = function(_bot, ctx) return ctx.ohaLastHit() end
}
local ohaDeny = {
    name = "oha_deny",
    host = true,
    scans = true,
    rank = ranks(
        100,
        unpack(all)
    ),
    drill = true,
    wants = function() return true end,
    run = function(_bot, ctx) return ctx.ohaDeny() end
}
--- The optional local override's Think: runs beside the rows and never ends the frame.
local ohaLocal = {
    name = "oha_local",
    host = true,
    scans = true,
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
--- OHA's PositionThink: the fallback that always acts.
local ohaPos = {
    name = "oha_pos",
    host = true,
    rank = ranks(
        140,
        unpack(all)
    ),
    drill = true,
    wants = function() return true end,
    run = function(_bot, ctx) return ctx.ohaPosition() end
}
____exports.ROWS = {
    sustain,
    ohaLastHit,
    ohaDeny,
    ohaLocal,
    ohaPos
}
for ____, r in ipairs(____exports.ROWS) do
    local host = r.host == true
    r.wants = Telemetry.Guard(
        ("LaneTable." .. r.name) .. ".wants",
        r.wants,
        function() return host end
    )
    if not host then
        r.run = Telemetry.Guard(
            ("LaneTable." .. r.name) .. ".run",
            r.run,
            function() return false end
        )
    end
end
local function build(pos, laneOnly)
    local out = {}
    for ____, r in ipairs(____exports.ROWS) do
        do
            local __continue21
            repeat
                if r.rank[pos] == nil or laneOnly and not r.drill then
                    __continue21 = true
                    break
                end
                out[#out + 1] = r
                __continue21 = true
            until true
            if not __continue21 then
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
            local __continue36
            repeat
                local t0 = Telemetry.DeepT0()
                local wants = r.wants(bot, ctx)
                if t0 ~= nil then
                    Telemetry.DeepAdd(("lane_table.Walk:" .. r.name) .. ".wants", t0)
                end
                if not wants then
                    __continue36 = true
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
                if r.scans ~= true then
                    local ____n_1 = n
                    n = ____n_1 + 1
                    skipScratch[____n_1 + 1] = r.name
                end
                __continue36 = true
            until true
            if not __continue36 then
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
