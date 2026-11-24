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
local Lane = ____dota.Lane
local UnitType = ____dota.UnitType
local LaneHits = require(GetScriptDirectory().."/FunLib/humaniser/lane_hits")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local LANES = {Lane.Top, Lane.Mid, Lane.Bot}
--- A hero's counters, or undefined when the reads fail (an enemy handle may not answer).
local function tally(h)
    local ok, v = pcall(function() return {
        lh = h:GetLastHits(),
        dn = h:GetDenies()
    } end)
    return ok and v or nil
end
local frameAt
local known = {}
--- Per hero handle: last hits and denies at the last frame.
local counts = {}
function ____exports.ResetCache()
    frameAt = nil
    known = {}
    counts = {}
end
local function round(x)
    return math.floor(x * 1000 + 0.5) / 1000
end
--- The heroes whose last hits (`lh`) or denies (`dn`) rose since the last frame: player ids joined by `;`.
local function risen(heroes)
    local lh = {}
    local dn = {}
    for ____, h in ipairs(heroes) do
        do
            local __continue7
            repeat
                local now = tally(h)
                local was = counts[h]
                if now == nil or was == nil then
                    __continue7 = true
                    break
                end
                if now.lh > was.lh then
                    lh[#lh + 1] = h:GetPlayerID()
                end
                if now.dn > was.dn then
                    dn[#dn + 1] = h:GetPlayerID()
                end
                __continue7 = true
            until true
            if not __continue7 then
                break
            end
        end
    end
    return {
        lh = table.concat(lh, ";"),
        dn = table.concat(dn, ";")
    }
end
local function remember(heroes)
    for ____, h in ipairs(heroes) do
        local now = tally(h)
        if now ~= nil then
            counts[h] = now
        end
    end
end
local function teamHeroes()
    local out = {}
    do
        local i = 1
        while i <= 5 do
            local h = GetTeamMember(i)
            if h ~= nil and h ~= nil and not h:IsNull() and not h:IsIllusion() then
                out[#out + 1] = h
            end
            i = i + 1
        end
    end
    return out
end
local function enemyHeroes()
    local out = {}
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        if not h:IsNull() and not h:IsIllusion() and h:CanBeSeen() then
            out[#out + 1] = h
        end
    end
    return out
end
local function frame(bot)
    local now = DotaTime()
    if frameAt == now then
        return
    end
    frameAt = now
    local team = bot:GetTeam()
    local ours = teamHeroes()
    local theirs = enemyHeroes()
    local seen = {}
    for ____, lane in ipairs(LANES) do
        for ____, r in ipairs(LaneHits.Read(team, lane)) do
            seen[r.creep] = true
            local k = LaneHits.KillingHit(r)
            local a = k ~= nil and (k.by == "hero" or k.by == "self") and k.attacker or nil
            known[r.creep] = {
                creep = r.creep,
                lane = lane,
                own = r.own,
                cid = Telemetry.CreepId(r.creep),
                hp = r.hp,
                by = k == nil and "none" or k.by,
                pid = a ~= nil and a:GetPlayerID() or -1,
                t = k == nil and -1 or k.t,
                commit = k == nil and -1 or k.commit,
                at = now
            }
        end
    end
    local left = {}
    for c, p in pairs(known) do
        if seen[c] ~= true then
            left[#left + 1] = p
        end
    end
    if #left > 0 then
        local o = risen(ours)
        local e = risen(theirs)
        for ____, p in ipairs(left) do
            known[p.creep] = nil
            local dead = p.creep:IsNull() or not p.creep:IsAlive()
            local ____Telemetry_Event_3 = Telemetry.Event
            local ____array_2 = __TS__SparseArrayNew(
                {"team", team},
                {"lane", p.lane},
                {"own", p.own and 1 or 0},
                {"cid", p.cid},
                {
                    "hp",
                    math.floor(p.hp)
                },
                {"pby", p.by},
                {"ppid", p.pid},
                {
                    "pt",
                    p.t < 0 and -1 or round(p.t)
                },
                {
                    "pc",
                    p.commit < 0 and -1 or round(p.commit)
                },
                {
                    "age",
                    round(now - p.at)
                }
            )
            local ____temp_0
            if (p.own and o.dn or o.lh) == "" then
                ____temp_0 = nil
            else
                ____temp_0 = p.own and o.dn or o.lh
            end
            __TS__SparseArrayPush(____array_2, {"rose", ____temp_0})
            local ____temp_1
            if (p.own and e.lh or e.dn) == "" then
                ____temp_1 = nil
            else
                ____temp_1 = p.own and e.lh or e.dn
            end
            __TS__SparseArrayPush(____array_2, {"erose", ____temp_1}, {"end", dead and "dead" or "left"})
            ____Telemetry_Event_3(
                "lane_hits_check",
                {__TS__SparseArraySpread(____array_2)}
            )
        end
    end
    remember(ours)
    remember(theirs)
end
function ____exports.Tick(bot)
    if Overrides.Get("LaneReadProbe") ~= true then
        return
    end
    pcall(frame, bot)
end
return ____exports
