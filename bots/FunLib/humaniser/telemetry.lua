--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Barracks = ____dota.Barracks
local GameState = ____dota.GameState
local Lane = ____dota.Lane
local Rune = ____dota.Rune
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Chat = require(GetScriptDirectory().."/FunLib/humaniser/chat")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
____exports.SCHEMA = 2
local BUILD = (function()
    local ok, info = pcall(
        require,
        GetScriptDirectory() .. "/FunLib/humaniser/build_info"
    )
    local ____temp_0
    if ok and type(info) == "table" and type(info.build) == "string" then
        ____temp_0 = info.build
    else
        ____temp_0 = "unknown"
    end
    return ____temp_0
end)()
____exports.DEFAULTS = {
    Enable = false,
    SnapshotInterval = 1,
    DecisionMaxAge = 1,
    MarkAck = true,
    LuaErrors = true,
    LuaErrorRepeat = 10,
    CreepDeathUntil = 720
}
local function merge(defaults, overrides)
    if overrides == nil or overrides == nil or type(overrides) ~= "table" then
        return defaults
    end
    local result = {}
    for k, v in pairs(defaults) do
        result[k] = v
    end
    for k, v in pairs(overrides) do
        result[k] = v
    end
    return result
end
local cached
function ____exports.Get()
    if cached == nil then
        cached = merge(
            ____exports.DEFAULTS,
            Config.Get().Telemetry
        )
    end
    return cached
end
--- Independent of the humaniser master switch, so an A/B game with the humaniser off still reports.
function ____exports.IsEnabled()
    return ____exports.Get().Enable == true
end
local function formatValue(v)
    if type(v) == "number" then
        if v == math.floor(v) and math.abs(v) < 1000000000 then
            return string.format("%d", v)
        end
        return string.format("%.3f", v)
    end
    if type(v) == "boolean" then
        return v and "1" or "0"
    end
    local s = tostring(v)
    if (string.find(s, "[%s=\"]")) == nil and s ~= "" then
        return s
    end
    return ("\"" .. (string.gsub((string.gsub(s, "\"", "'")), "[\r\n]", " "))) .. "\""
end
--- The exact line Event() prints, without printing it. Field order is the caller's.
function ____exports.FormatLine(ev, fields)
    local parts = {
        "[HEV]",
        "t=" .. formatValue(DotaTime()),
        "ev=" .. ev
    }
    for ____, ____value in ipairs(fields) do
        local k = ____value[1]
        local v = ____value[2]
        if v ~= nil and v ~= nil then
            parts[#parts + 1] = (k .. "=") .. formatValue(v)
        end
    end
    return table.concat(parts, " ")
end
local sink
--- Tests capture lines here instead of printing them.
function ____exports.SetSink(fn)
    sink = fn
end
--- For names built at run time (farm_pattern trips, the engine adapter); listed as untyped in tools/hlog/EVENTS.md.
function ____exports.EventUntyped(ev, fields)
    if not ____exports.IsEnabled() then
        return
    end
    local line = ____exports.FormatLine(ev, fields)
    if sink ~= nil then
        sink(line)
        return
    end
    local rawPrint = Utils.RawPrint;
    (rawPrint or print)(line)
end
--- Typed event: the name and every key must be declared in events.ts. The printed line is exactly what EventUntyped prints.
function ____exports.Event(ev, fields)
    ____exports.EventUntyped(ev, fields)
end
--- Whether index.ts should install Guard() around the humaniser entry points.
function ____exports.GuardsEnabled()
    return ____exports.IsEnabled() and ____exports.Get().LuaErrors == true
end
local MAX_ERROR_KEYS = 64
local errorStats = {}
local errorKeys = 0
local function shortTrace()
    if type(debug) ~= "table" or type(debug.traceback) ~= "function" then
        return nil
    end
    local frames = {}
    for line in string.gmatch(
        debug.traceback("", 1),
        "[^\n]+"
    ) do
        local loc = string.match(line, "([%w_]+%.lua:%d+)")
        if loc ~= nil and (string.find(loc, "^telemetry%.lua")) == nil then
            local fname = string.match(line, "function '([^']+)'")
            frames[#frames + 1] = fname ~= nil and ((loc .. "(") .. fname) .. ")" or loc
            if #frames >= 6 then
                break
            end
        end
    end
    return #frames > 0 and table.concat(frames, " < ") or nil
end
local function describeError(err)
    if type(err) == "string" then
        return err
    end
    local ok, s = pcall(tostring, err)
    return ok and type(s) == "string" and s or ("<" .. type(err)) .. ">"
end
local function currentPID()
    return GetBot():GetPlayerID()
end
local function reportError(where, err, tb)
    local msg = describeError(err)
    if #msg > 200 then
        msg = string.sub(msg, 1, 200)
    end
    local key = (where .. "|") .. msg
    if errorStats[key] == nil and errorKeys >= MAX_ERROR_KEYS then
        key = where .. "|*"
    end
    local now = GameTime()
    local stat = errorStats[key]
    if stat == nil then
        errorKeys = errorKeys + 1
        stat = {n = 0, at = -math.huge}
        errorStats[key] = stat
    end
    stat.n = stat.n + 1
    if now - stat.at < ____exports.Get().LuaErrorRepeat then
        return
    end
    stat.at = now
    local okPid, pid = pcall(currentPID)
    local ____exports_Event_2 = ____exports.Event
    local ____okPid_1
    if okPid then
        ____okPid_1 = pid
    else
        ____okPid_1 = nil
    end
    ____exports_Event_2("lua_error", {
        {"pid", ____okPid_1},
        {"where", where},
        {"n", stat.n},
        {"msg", msg},
        {"tb", tb}
    })
end
--- fn under xpcall. An error is reported (rate-limited per where+msg) and swallowed: the caller gets
-- fallback(...args), which should be what the hook returns with its feature off. Reporting happens after
-- xpcall returns, so a stack overflow (handler cannot run: "error in error handling") is still reported.
-- Up to six arguments, no allocation per call; multiple return values pass through.
function ____exports.Guard(where, fn, fallback)
    local a1
    local a2
    local a3
    local a4
    local a5
    local a6
    local tb
    local function thunk()
        return fn(
            a1,
            a2,
            a3,
            a4,
            a5,
            a6
        )
    end
    local function handler(err)
        local ok, t = pcall(shortTrace)
        local ____ok_3
        if ok then
            ____ok_3 = t
        else
            ____ok_3 = nil
        end
        tb = ____ok_3
        return err
    end
    local function fail(b1, b2, b3, b4, b5, b6, err)
        local trace = tb
        tb = nil
        pcall(reportError, where, err, trace)
        if fallback ~= nil then
            return fallback(
                b1,
                b2,
                b3,
                b4,
                b5,
                b6
            )
        end
        return nil
    end
    local function finish(b1, b2, b3, b4, b5, b6, ok, ...)
        if ok then
            return ...
        end
        return fail(
            b1,
            b2,
            b3,
            b4,
            b5,
            b6,
            ...
        )
    end
    return function(b1, b2, b3, b4, b5, b6)
        a1 = b1
        a2 = b2
        a3 = b3
        a4 = b4
        a5 = b5
        a6 = b6
        tb = nil
        return finish(
            b1,
            b2,
            b3,
            b4,
            b5,
            b6,
            xpcall(thunk, handler)
        )
    end
end
--- An OHA entry point (mode GetDesire/Think/OnStart/OnEnd, item and ability thinks) under pcall, for H.1. An error is
-- reported as ev=lua_error where=oha.<where> (rate-limited like Guard) and raised again unchanged, so OHA behaves as
-- before. pcall, not xpcall: with no handler a stack overflow keeps its own message ("<file>:<line>: stack overflow")
-- instead of Dota's "error in error handling". Returns fn unchanged when it is nil or guards are off.
function ____exports.Entry(where, fn)
    if fn == nil or not ____exports.GuardsEnabled() then
        return fn
    end
    local name = "oha." .. where
    local function fail(err)
        pcall(reportError, name, err, nil)
        return error(err, 0)
    end
    local function finish(ok, ...)
        if ok then
            return ...
        end
        return fail(...)
    end
    return function(...) return finish(pcall(fn, ...)) end
end
--- Replaces each named export of a module table with a Guard()ed one. Lua callers resolve exports at call time.
function ____exports.GuardModule(name, mod, fallbacks)
    for k, fallback in pairs(fallbacks) do
        if type(mod[k]) == "function" then
            mod[k] = ____exports.Guard((name .. ".") .. k, mod[k], fallback)
        end
    end
end
local function weakKeys()
    return setmetatable({}, {__mode = "k"})
end
local states = {}
local function stateFor(pid)
    local s = states[pid]
    if s == nil then
        s = {
            modeSince = 0,
            snapAt = -math.huge,
            lastHits = -1,
            denies = -1,
            decisions = weakKeys(),
            markCursor = {},
            ended = false,
            smoked = false,
            aegis = false
        }
        states[pid] = s
    end
    return s
end
local function heroName(unit)
    return (string.gsub(
        unit:GetUnitName(),
        "npc_dota_hero_",
        ""
    ))
end
--- Called from AllyLastHit.MayLastHit for every enemy creep it judges.
function ____exports.NoteLastHitDecision(bot, creep, allowed, reason)
    if not ____exports.IsEnabled() then
        return
    end
    local decisions = stateFor(bot:GetPlayerID()).decisions
    local d = decisions[creep]
    if d == nil then
        decisions[creep] = {
            allowed = allowed,
            reason = reason,
            at = DotaTime()
        }
    else
        d.allowed = allowed
        d.reason = reason
        d.at = DotaTime()
    end
end
local marksByTeam = {}
local markCount = {}
local subscribedTeams = {}
--- Chat hub subscriber for one team. Exported for tests.
function ____exports.HandleChat(team, msg)
    if not ____exports.IsEnabled() or IsPlayerBot(msg.pid) then
        return
    end
    local ____, ____, rest = string.find(
        string.lower(msg.text),
        "^%s*!mark(.*)$"
    )
    if rest == nil or rest ~= "" and (string.find(rest, "^%s")) == nil then
        return
    end
    local ____, ____, note = string.find(msg.text, "^%s*!%a+%s*(.-)%s*$")
    local n = (markCount[team] or 0) + 1
    markCount[team] = n
    if marksByTeam[team] == nil then
        marksByTeam[team] = {}
    end
    local ____marksByTeam_team_4 = marksByTeam[team]
    ____marksByTeam_team_4[#____marksByTeam_team_4 + 1] = {
        by = msg.pid,
        text = note,
        t = DotaTime(),
        n = n
    }
end
local function lowestBotPID(team)
    local best
    for ____, pid in ipairs(GetTeamPlayers(team)) do
        if IsPlayerBot(pid) and (best == nil or pid < best) then
            best = pid
        end
    end
    return best
end
local function pct(v, max)
    return max > 0 and math.floor(100 * v / max + 0.5) or 0
end
local LANES = {{Lane.Top, "top"}, {Lane.Mid, "mid"}, {Lane.Bot, "bot"}}
local function absAlong(lane, loc)
    local r = GetAmountAlongLane(lane, loc)
    return {
        amount = Camps.ToTeamAmount(Team.Radiant, r.amount),
        distance = r.distance
    }
end
--- ln (nearest lane), s (absolute amount along it) and ld (distance from it) for one hero.
local function laneFields(loc)
    local best
    local name = ""
    for ____, ____value in ipairs(LANES) do
        local lane = ____value[1]
        local n = ____value[2]
        local r = absAlong(lane, loc)
        if best == nil or r.distance < best.distance then
            best = r
            name = n
        end
    end
    return {
        {"ln", name},
        {"s", best.amount},
        {
            "ld",
            math.floor(best.distance)
        }
    }
end
--- One ev=front per team: the team's wave front per lane, absolute amount and map position.
local function trackFront(team)
    local fields = {{"team", team}}
    for ____, ____value in ipairs(LANES) do
        local lane = ____value[1]
        local n = ____value[2]
        local loc = GetLaneFrontLocation(team, lane, 0)
        fields[#fields + 1] = {
            n,
            absAlong(lane, loc).amount
        }
        fields[#fields + 1] = {
            n .. "x",
            math.floor(loc.x)
        }
        fields[#fields + 1] = {
            n .. "y",
            math.floor(loc.y)
        }
    end
    ____exports.Event("front", fields)
end
local guardedLaneFields = ____exports.Guard(
    "Telemetry.Lane",
    laneFields,
    function() return {} end
)
local guardedFront = ____exports.Guard("Telemetry.Front", trackFront)
local function unitFields(unit)
    local loc = unit:GetLocation()
    local stats = unit
    local target = unit:GetAttackTarget()
    local fields = {
        {
            "x",
            math.floor(loc.x)
        },
        {
            "y",
            math.floor(loc.y)
        },
        {
            "alive",
            unit:IsAlive()
        },
        {
            "hp",
            pct(
                unit:GetHealth(),
                unit:GetMaxHealth()
            )
        },
        {
            "mp",
            pct(
                unit:GetMana(),
                unit:GetMaxMana()
            )
        },
        {
            "lvl",
            unit:GetLevel()
        },
        {
            "lh",
            stats:GetLastHits()
        },
        {
            "dn",
            stats:GetDenies()
        },
        {
            "kills",
            GetHeroKills ~= nil and GetHeroKills(unit:GetPlayerID()) or nil
        },
        {
            "deaths",
            GetHeroDeaths ~= nil and GetHeroDeaths(unit:GetPlayerID()) or nil
        },
        {
            "tgt",
            target ~= nil and target ~= nil and target:GetUnitName() or nil
        }
    }
    for ____, f in ipairs(guardedLaneFields(loc)) do
        fields[#fields + 1] = f
    end
    return fields
end
local function botFields(bot, ctx)
    local fields = unitFields(bot)
    fields[#fields + 1] = {
        "mode",
        HDebug.ModeName(bot:GetActiveMode())
    }
    fields[#fields + 1] = {
        "d",
        bot:GetActiveModeDesire()
    }
    fields[#fields + 1] = {
        "act",
        bot:GetCurrentActionType()
    }
    fields[#fields + 1] = {
        "gold",
        bot:GetGold()
    }
    if ctx ~= nil then
        fields[#fields + 1] = {"by", ctx.by}
        fields[#fields + 1] = {"order", ctx.order}
    end
    return fields
end
local function maybeProfile(bot, s)
    if not Config.IsEnabled() then
        local offKey = "off|" .. tostring(LaneConfig.PositionOf(bot))
        if s.profileKey == offKey then
            return
        end
        s.profileKey = offKey
        ____exports.Event(
            "bot",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {
                    "hero",
                    heroName(bot)
                },
                {
                    "team",
                    bot:GetTeam()
                },
                {"schema", ____exports.SCHEMA},
                {"humaniser", false},
                {
                    "skill",
                    Difficulty.GetSkill(bot)
                },
                {
                    "ally",
                    Difficulty.IsAllyOfHuman(bot)
                },
                {"build", BUILD},
                {
                    "pos",
                    LaneConfig.PositionOf(bot)
                },
                {
                    "ours",
                    Ours.Describe()
                }
            }
        )
        return
    end
    local p = Profile.Get(bot)
    local cfg = Config.Get().Profile
    local key = string.format(
        "%.3f|%.3f|%.3f|%s",
        p.skill,
        p.noticeBase,
        p.reactBase,
        tostring(LaneConfig.PositionOf(bot))
    )
    if key == s.profileKey then
        return
    end
    s.profileKey = key
    ____exports.Event(
        "bot",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {
                "hero",
                heroName(bot)
            },
            {
                "team",
                bot:GetTeam()
            },
            {"schema", ____exports.SCHEMA},
            {"skill", p.skill},
            {
                "ally",
                Difficulty.IsAllyOfHuman(bot)
            },
            {"notice", p.noticeBase},
            {"react", p.reactBase},
            {"ping", p.pingBase},
            {"chat", p.chatBase},
            {"jitter", p.jitter},
            {"lapse", p.lapseChance},
            {"lapseMax", cfg.LapseMaxExtra},
            {"minReact", cfg.MinReact},
            {"deference", p.deference},
            {"build", BUILD},
            {
                "pos",
                LaneConfig.PositionOf(bot)
            },
            {
                "ours",
                Ours.Describe()
            }
        }
    )
end
local function trackCounters(unit, s, human, now)
    local stats = unit
    local lh = stats:GetLastHits()
    local dn = stats:GetDenies()
    if s.lastHits >= 0 and lh > s.lastHits then
        local current = unit:GetAttackTarget() or nil
        local creep = s.prevTarget or current
        local ____temp_7
        if s.prevTarget ~= nil then
            ____temp_7 = s.prevTargetName
        else
            ____temp_7 = current and current:GetUnitName()
        end
        local creepName = ____temp_7
        local d = creep ~= nil and s.decisions[creep] or nil
        local fresh = d ~= nil and now - d.at <= ____exports.Get().DecisionMaxAge
        ____exports.Event(
            "lasthit",
            {
                {
                    "pid",
                    unit:GetPlayerID()
                },
                {"human", human},
                {"n", lh - s.lastHits},
                {"creep", creepName},
                {"dec", fresh and d.reason or nil},
                {"decAge", fresh and now - d.at or nil}
            }
        )
    end
    if s.denies >= 0 and dn > s.denies then
        ____exports.Event(
            "deny",
            {
                {
                    "pid",
                    unit:GetPlayerID()
                },
                {"human", human},
                {"n", dn - s.denies}
            }
        )
    end
    s.lastHits = lh
    s.denies = dn
    local target = unit:GetAttackTarget()
    s.prevTarget = target ~= nil and target ~= nil and target or nil
    local ____s_10 = s
    local ____opt_8 = s.prevTarget
    ____s_10.prevTargetName = ____opt_8 and ____opt_8:GetUnitName()
end
local function trackMode(bot, s, now, provider)
    local mode = bot:GetActiveMode()
    if mode == s.mode then
        return
    end
    local from = s.mode
    s.mode = mode
    local dwell = now - s.modeSince
    s.modeSince = now
    if from == nil then
        return
    end
    local ctx = provider ~= nil and provider(bot) or nil
    ____exports.Event(
        "mode",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {
                "from",
                HDebug.ModeName(from)
            },
            {
                "to",
                HDebug.ModeName(mode)
            },
            {
                "d",
                bot:GetActiveModeDesire()
            },
            {"dwell", dwell},
            {"by", ctx and ctx.by}
        }
    )
end
local function reportMarks(bot, s, provider)
    local team = bot:GetTeam()
    local marks = marksByTeam[team]
    if marks == nil then
        return
    end
    local pid = bot:GetPlayerID()
    local seen = s.markCursor[team] or 0
    do
        local i = seen
        while i < #marks do
            local m = marks[i + 1]
            if pid == lowestBotPID(team) then
                ____exports.Event("mark", {
                    {"n", m.n},
                    {"by", m.by},
                    {"team", team},
                    {"text", m.text},
                    {"at", m.t}
                })
                if ____exports.Get().MarkAck then
                    bot:ActionImmediate_Chat(
                        ("mark " .. tostring(m.n)) .. " saved",
                        false
                    )
                end
            end
            local ctx = provider ~= nil and provider(bot) or nil
            local fields = {
                {"n", m.n},
                {"pid", pid},
                {
                    "hero",
                    heroName(bot)
                }
            }
            for ____, f in ipairs(botFields(bot, ctx)) do
                fields[#fields + 1] = f
            end
            fields[#fields + 1] = {"competing", ctx and ctx.competing}
            ____exports.Event("mark_state", fields)
            i = i + 1
        end
    end
    s.markCursor[team] = #marks
end
local function ancientDown(team)
    local ancient = GetAncient(team)
    return ancient == nil or ancient == nil or not ancient:IsAlive() or ancient:GetHealth() <= 0
end
local RUNES = {
    Rune.Power1,
    Rune.Power2,
    Rune.Bounty1,
    Rune.Bounty2,
    Rune.Bounty3,
    Rune.Bounty4
}
local TOWER_TIERS = {
    {Tower.Top1, 1},
    {Tower.Mid1, 1},
    {Tower.Bot1, 1},
    {Tower.Top2, 2},
    {Tower.Mid2, 2},
    {Tower.Bot2, 2},
    {Tower.Top3, 3},
    {Tower.Mid3, 3},
    {Tower.Bot3, 3},
    {Tower.Base1, 4},
    {Tower.Base2, 4}
}
local BARRACKS = {
    Barracks.TopMelee,
    Barracks.TopRanged,
    Barracks.MidMelee,
    Barracks.MidRanged,
    Barracks.BotMelee,
    Barracks.BotRanged
}
--- RUNE_RULES power.first (transitions/runes): power spots hold water runes before it.
local POWER_FROM = 360
--- judgement: the own hero nearest a rune when it vanishes took it if within pickup range plus a frame of movement.
local RUNE_TAKER_R = 400
--- judgement: ward cast range 500 plus movement since the cast.
local WARD_OWNER_R = 800
--- Rune status is stale across 0:00 (b23 gate logs: every spot "taken" at t = 0.2), so tracking starts after this.
local RUNES_FROM = 1
--- A teleport's landing spot is read this long after its modifier ends.
local TP_SETTLE = 0.1
local worlds = {}
local teamJobAt = {}
local function firstThisFrame(job, team, now)
    local key = job .. tostring(team)
    if teamJobAt[key] == now then
        return false
    end
    teamJobAt[key] = now
    return true
end
local function teamHeroes(team)
    local heroes = {}
    local n = #GetTeamPlayers(team)
    do
        local i = 1
        while i <= n do
            local m = GetTeamMember(i)
            if m ~= nil and m ~= nil and m:IsAlive() then
                heroes[#heroes + 1] = m
            end
            i = i + 1
        end
    end
    return heroes
end
local function nearest(units, loc)
    local best
    local bestD = math.huge
    for ____, u in ipairs(units) do
        local d = GetUnitToLocationDistance(u, loc)
        if d < bestD then
            best = u
            bestD = d
        end
    end
    return best, bestD
end
local function trackRunes(team, w, now)
    if now < RUNES_FROM then
        return
    end
    for ____, r in ipairs(RUNES) do
        do
            local __continue115
            repeat
                local seen = w.runes[r]
                if GetRuneStatus(r) == RUNE_STATUS_AVAILABLE then
                    if seen == nil or not seen.up then
                        w.runes[r] = {
                            up = true,
                            loc = GetRuneSpawnLocation(r)
                        }
                    end
                    __continue115 = true
                    break
                end
                if seen == nil or not seen.up then
                    __continue115 = true
                    break
                end
                seen.up = false
                local taker, d = nearest(
                    teamHeroes(team),
                    seen.loc
                )
                if taker == nil or d > RUNE_TAKER_R then
                    __continue115 = true
                    break
                end
                local ____, enemyD = nearest(
                    GetUnitList(UnitType.EnemyHeroes),
                    seen.loc
                )
                if enemyD < d then
                    __continue115 = true
                    break
                end
                local power = r == Rune.Power1 or r == Rune.Power2
                ____exports.Event(
                    "rune_pickup",
                    {
                        {
                            "pid",
                            taker:GetPlayerID()
                        },
                        {"team", team},
                        {"rune", r},
                        {"kind", power and (now < POWER_FROM and "water" or "power") or "bounty"},
                        {
                            "x",
                            math.floor(seen.loc.x)
                        },
                        {
                            "y",
                            math.floor(seen.loc.y)
                        }
                    }
                )
                __continue115 = true
            until true
            if not __continue115 then
                break
            end
        end
    end
end
local function trackWards(team, w)
    for ____, ward in ipairs(GetUnitList(UnitType.AlliedWards)) do
        do
            local __continue123
            repeat
                if w.wards[ward] == true then
                    __continue123 = true
                    break
                end
                w.wards[ward] = true
                local name = ward:GetUnitName()
                local kind = (string.find(name, "observer")) ~= nil and "obs" or ((string.find(name, "sentry")) ~= nil and "sentry" or nil)
                if kind == nil then
                    __continue123 = true
                    break
                end
                local loc = ward:GetLocation()
                local owner, d = nearest(
                    teamHeroes(team),
                    loc
                )
                ____exports.Event(
                    "ward_place",
                    {
                        {
                            "pid",
                            owner ~= nil and d <= WARD_OWNER_R and owner:GetPlayerID() or nil
                        },
                        {"team", team},
                        {"kind", kind},
                        {
                            "x",
                            math.floor(loc.x)
                        },
                        {
                            "y",
                            math.floor(loc.y)
                        }
                    }
                )
                __continue123 = true
            until true
            if not __continue123 then
                break
            end
        end
    end
end
local function trackBuilding(team, w, kind, id, u, tier)
    local key = kind .. tostring(id)
    local alive = u ~= nil and u ~= nil and u:IsAlive()
    local known = w.buildings[key]
    w.buildings[key] = alive
    if known == true and not alive then
        ____exports.Event("building_fall", {{"team", team}, {"kind", kind}, {"id", id}, {"tier", tier}})
    end
end
local function trackWorld(bot, now)
    local team = bot:GetTeam()
    if not firstThisFrame("world", team, now) then
        return
    end
    local w = worlds[team]
    if w == nil then
        w = {
            runes = {},
            wards = weakKeys(),
            buildings = {},
            slowAt = -math.huge
        }
        worlds[team] = w
    end
    trackRunes(team, w, now)
    if now - w.slowAt < ____exports.Get().SnapshotInterval then
        return
    end
    w.slowAt = now
    trackWards(team, w)
    for ____, ____value in ipairs(TOWER_TIERS) do
        local id = ____value[1]
        local tier = ____value[2]
        trackBuilding(
            team,
            w,
            "tower",
            id,
            GetTower(team, id),
            tier
        )
    end
    for ____, id in ipairs(BARRACKS) do
        trackBuilding(
            team,
            w,
            "rax",
            id,
            GetBarracks(team, id)
        )
    end
    local killedAt = GetRoshanKillTime()
    if w.roshanAt ~= nil and killedAt > w.roshanAt then
        ____exports.Event("roshan_kill", {{"team", team}, {"at", killedAt}})
    end
    w.roshanAt = killedAt
    guardedFront(team)
end
--- Smoke, teleport and aegis edges for one hero (bot or human).
local function trackHero(unit, s, now, slow)
    local smoked = unit:HasModifier("modifier_smoke_of_deceit")
    if smoked and not s.smoked then
        local loc = unit:GetLocation()
        ____exports.Event(
            "smoke_use",
            {
                {
                    "pid",
                    unit:GetPlayerID()
                },
                {
                    "team",
                    unit:GetTeam()
                },
                {
                    "x",
                    math.floor(loc.x)
                },
                {
                    "y",
                    math.floor(loc.y)
                }
            }
        )
    end
    s.smoked = smoked
    local teleporting = unit:HasModifier("modifier_teleporting")
    if teleporting then
        if s.tpFrom == nil then
            local loc = unit:GetLocation()
            s.tpFrom = {loc.x, loc.y, now}
        end
        s.tpEndAt = nil
    elseif s.tpFrom ~= nil then
        if s.tpEndAt == nil then
            s.tpEndAt = now
        elseif now - s.tpEndAt >= TP_SETTLE then
            local fx, fy, at = unpack(s.tpFrom)
            local loc = unit:GetLocation()
            ____exports.Event(
                "tp",
                {
                    {
                        "pid",
                        unit:GetPlayerID()
                    },
                    {
                        "team",
                        unit:GetTeam()
                    },
                    {
                        "fx",
                        math.floor(fx)
                    },
                    {
                        "fy",
                        math.floor(fy)
                    },
                    {
                        "x",
                        math.floor(loc.x)
                    },
                    {
                        "y",
                        math.floor(loc.y)
                    },
                    {"dur", s.tpEndAt - at},
                    {
                        "dist",
                        math.floor(math.sqrt((loc.x - fx) ^ 2 + (loc.y - fy) ^ 2))
                    }
                }
            )
            s.tpFrom = nil
            s.tpEndAt = nil
        end
    end
    if not slow then
        return
    end
    local aegis = unit:FindItemSlot("item_aegis") >= 0
    if aegis and not s.aegis then
        ____exports.Event(
            "aegis",
            {
                {
                    "pid",
                    unit:GetPlayerID()
                },
                {
                    "team",
                    unit:GetTeam()
                }
            }
        )
    end
    s.aegis = aegis
end
local creepTracks = {}
--- A creep that vanishes above this health share left vision; it did not die.
local DEATH_MAX_HP = 0.5
--- Deaths are logged only this close to an own hero (vision), and cores are described only this close to the death.
local DEATH_NEAR = 1500
--- A hero whose last hits (or an enemy whose denies) rose takes the nearest death within this distance.
local KILLER_NEAR = 1200
local function creepKind(name)
    local lane = (string.find(name, "creep_goodguys", 1, true)) ~= nil or (string.find(name, "creep_badguys", 1, true)) ~= nil
    if (string.find(name, "siege", 1, true)) ~= nil then
        return "siege"
    end
    if not lane then
        return nil
    end
    return (string.find(name, "ranged", 1, true)) ~= nil and "ranged" or "melee"
end
local function deathDistance(u, d)
    local loc = u:GetLocation()
    return math.sqrt((loc.x - d.seen.x) ^ 2 + (loc.y - d.seen.y) ^ 2)
end
--- Gives each counter rise the nearest unclaimed death.
local function claimDeaths(deaths, unit, n, by)
    do
        local k = 0
        while k < n do
            local best
            local bestD = KILLER_NEAR
            for ____, d in ipairs(deaths) do
                local dist = deathDistance(unit, d)
                if d.by == nil and dist <= bestD then
                    best = d
                    bestD = dist
                end
            end
            if best == nil then
                return
            end
            best.by = by
            k = k + 1
        end
    end
end
local function rise(counts, pid, value)
    local prev = counts[pid]
    counts[pid] = value
    return prev ~= nil and value > prev and value - prev or 0
end
local function trackCreepDeaths(bot, now)
    if now < 0 or now > ____exports.Get().CreepDeathUntil then
        return
    end
    local team = bot:GetTeam()
    if not firstThisFrame("creeps", team, now) then
        return
    end
    local c = creepTracks[team]
    if c == nil then
        c = {
            creeps = {},
            dead = {},
            lastHits = {},
            denies = {},
            target = {},
            attackAt = {},
            attackOn = {},
            attackMode = {}
        }
        creepTracks[team] = c
    end
    local heroes = teamHeroes(team)
    local gameNow = GameTime()
    local alive = {}
    local live = {}
    for ____, u in ipairs(GetUnitList(UnitType.EnemyCreeps) or ({})) do
        do
            local __continue162
            repeat
                if u == nil or u == nil or not u:IsAlive() then
                    __continue162 = true
                    break
                end
                alive[#alive + 1] = u
                live[u] = true
                local back = c.dead[u]
                if back ~= nil then
                    c.dead[u] = nil
                    ____exports.Event("creep_revive", {{"team", team}, {"kind", back.kind}, {"hp", back.hp}})
                end
                __continue162 = true
            until true
            if not __continue162 then
                break
            end
        end
    end
    local deaths = {}
    for creep, seen in pairs(c.creeps) do
        do
            local __continue166
            repeat
                if live[creep] == true then
                    __continue166 = true
                    break
                end
                c.creeps[creep] = nil
                if seen.hp > DEATH_MAX_HP then
                    __continue166 = true
                    break
                end
                local d = {creep = creep, seen = seen}
                for ____, h in ipairs(heroes) do
                    if deathDistance(h, d) <= DEATH_NEAR then
                        deaths[#deaths + 1] = d
                        break
                    end
                end
                __continue166 = true
            until true
            if not __continue166 then
                break
            end
        end
    end
    for ____, h in ipairs(heroes) do
        local n = rise(
            c.lastHits,
            h:GetPlayerID(),
            h:GetLastHits()
        )
        if n > 0 then
            claimDeaths(
                deaths,
                h,
                n,
                tostring(h:GetPlayerID())
            )
        end
    end
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue175
            repeat
                if e == nil or e == nil or not e:IsAlive() or e:IsIllusion() then
                    __continue175 = true
                    break
                end
                local ok, dn = pcall(function() return e:GetDenies() end)
                local n = ok and type(dn) == "number" and rise(
                    c.denies,
                    e:GetPlayerID(),
                    dn
                ) or 0
                if n > 0 then
                    claimDeaths(deaths, e, n, "deny")
                end
                __continue175 = true
            until true
            if not __continue175 then
                break
            end
        end
    end
    local cores = {}
    for ____, h in ipairs(heroes) do
        local pos = LaneConfig.PositionOf(h)
        if pos ~= nil and pos >= 1 and pos <= 3 then
            cores[#cores + 1] = {h, pos}
        end
    end
    for ____, d in ipairs(deaths) do
        local fields = {
            {"team", team},
            {"kind", d.seen.kind},
            {
                "x",
                math.floor(d.seen.x)
            },
            {
                "y",
                math.floor(d.seen.y)
            },
            {"hp", d.seen.hp},
            {"by", d.by or "none"}
        }
        local ____temp_15
        if d.by ~= nil then
            ____temp_15 = tonumber(d.by)
        else
            ____temp_15 = nil
        end
        local killer = ____temp_15
        if killer ~= nil and c.attackOn[killer] == d.creep then
            local mode = c.attackMode[killer]
            if mode ~= nil then
                fields[#fields + 1] = {
                    "bm",
                    HDebug.ModeName(mode)
                }
            end
            fields[#fields + 1] = {"bs", gameNow - c.attackAt[killer]}
        end
        for ____, ____value in ipairs(cores) do
            local core = ____value[1]
            local pos = ____value[2]
            do
                local __continue186
                repeat
                    local dist = deathDistance(core, d)
                    if dist > DEATH_NEAR then
                        __continue186 = true
                        break
                    end
                    local pid = core:GetPlayerID()
                    fields[#fields + 1] = {
                        ("p" .. tostring(pos)) .. "d",
                        math.floor(dist)
                    }
                    fields[#fields + 1] = {
                        ("p" .. tostring(pos)) .. "r",
                        core:GetAttackRange()
                    }
                    fields[#fields + 1] = {
                        ("p" .. tostring(pos)) .. "t",
                        c.target[pid] == d.creep
                    }
                    if c.attackOn[pid] == d.creep then
                        fields[#fields + 1] = {
                            ("p" .. tostring(pos)) .. "a",
                            gameNow - c.attackAt[pid]
                        }
                    end
                    __continue186 = true
                until true
                if not __continue186 then
                    break
                end
            end
        end
        ____exports.Event("creep_death", fields)
        c.dead[d.creep] = d.seen
    end
    for ____, ____value in ipairs(cores) do
        local core = ____value[1]
        c.target[core:GetPlayerID()] = core:GetAttackTarget() or nil
    end
    for ____, h in ipairs(heroes) do
        local pid = h:GetPlayerID()
        local at = h:GetLastAttackTime()
        if c.attackAt[pid] == nil or at > c.attackAt[pid] then
            c.attackAt[pid] = at
            c.attackOn[pid] = h:GetAttackTarget() or nil
            c.attackMode[pid] = stateFor(pid).mode
        end
    end
    for ____, u in ipairs(alive) do
        do
            local __continue196
            repeat
                local kind = creepKind(u:GetUnitName())
                if kind == nil then
                    __continue196 = true
                    break
                end
                local loc = u:GetLocation()
                c.creeps[u] = {
                    kind = kind,
                    x = loc.x,
                    y = loc.y,
                    hp = u:GetHealth() / math.max(
                        1,
                        u:GetMaxHealth()
                    )
                }
                __continue196 = true
            until true
            if not __continue196 then
                break
            end
        end
    end
end
local guardedWorld = ____exports.Guard("Telemetry.World", trackWorld)
local guardedCreeps = ____exports.Guard("Telemetry.Creeps", trackCreepDeaths)
local guardedHero = ____exports.Guard("Telemetry.Hero", trackHero)
local function snapHumans(bot, now)
    local team = bot:GetTeam()
    if not firstThisFrame("humans", team, now) then
        return
    end
    local players = GetTeamPlayers(team)
    do
        local i = 1
        while i <= #players do
            do
                local __continue201
                repeat
                    if IsPlayerBot(players[i]) then
                        __continue201 = true
                        break
                    end
                    local member = GetTeamMember(i)
                    if member == nil or member == nil then
                        __continue201 = true
                        break
                    end
                    local hs = stateFor(member:GetPlayerID())
                    if hs.snapAt < 0 then
                        hs.snapAt = now
                        ____exports.Event(
                            "player",
                            {
                                {
                                    "pid",
                                    member:GetPlayerID()
                                },
                                {
                                    "hero",
                                    heroName(member)
                                },
                                {"team", team},
                                {"human", true}
                            }
                        )
                    end
                    trackCounters(member, hs, true, now)
                    local slow = now - hs.snapAt >= ____exports.Get().SnapshotInterval
                    guardedHero(member, hs, now, slow)
                    if slow then
                        hs.snapAt = now
                        local fields = {
                            {
                                "pid",
                                member:GetPlayerID()
                            },
                            {"human", true}
                        }
                        for ____, f in ipairs(unitFields(member)) do
                            fields[#fields + 1] = f
                        end
                        ____exports.Event("snap", fields)
                    end
                    __continue201 = true
                until true
                if not __continue201 then
                    break
                end
            end
            i = i + 1
        end
    end
end
--- Runs every frame per bot from Humaniser.Tick, whether or not the humaniser is enabled.
function ____exports.Tick(bot, provider)
    if not ____exports.IsEnabled() then
        return
    end
    local state = GetGameState()
    if state ~= GameState.GameInProgress and state ~= GameState.PreGame and state ~= GameState.PostGame then
        return
    end
    local team = bot:GetTeam()
    if subscribedTeams[team] ~= true then
        subscribedTeams[team] = true
        Chat.Subscribe(
            "telemetry:" .. tostring(team),
            function(msg) return ____exports.HandleChat(team, msg) end
        )
    end
    local s = stateFor(bot:GetPlayerID())
    local now = DotaTime()
    if s.ended then
        return
    end
    maybeProfile(bot, s)
    trackMode(bot, s, now, provider)
    trackCounters(bot, s, false, now)
    reportMarks(bot, s, provider)
    local slow = now - s.snapAt >= ____exports.Get().SnapshotInterval
    guardedHero(bot, s, now, slow)
    guardedWorld(bot, now)
    guardedCreeps(bot, now)
    if slow then
        s.snapAt = now
        local fields = {{
            "pid",
            bot:GetPlayerID()
        }}
        for ____, f in ipairs(botFields(
            bot,
            provider ~= nil and provider(bot) or nil
        )) do
            fields[#fields + 1] = f
        end
        ____exports.Event("snap", fields)
    end
    snapHumans(bot, now)
    if state == GameState.PostGame or ancientDown(Team.Radiant) or ancientDown(Team.Dire) then
        s.ended = true
        ____exports.Event(
            "game_end",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {
                    "radiantAncient",
                    not ancientDown(Team.Radiant)
                },
                {
                    "direAncient",
                    not ancientDown(Team.Dire)
                }
            }
        )
    end
end
return ____exports
