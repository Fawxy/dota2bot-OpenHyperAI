--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local GameState = ____dota.GameState
local Team = ____dota.Team
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Chat = require(GetScriptDirectory().."/FunLib/humaniser/chat")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
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
    LuaErrorRepeat = 10
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
function ____exports.Event(ev, fields)
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
            ended = false
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
local function unitFields(unit)
    local loc = unit:GetLocation()
    local stats = unit
    local target = unit:GetAttackTarget()
    return {
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
local function snapHumans(bot, now)
    local team = bot:GetTeam()
    if bot:GetPlayerID() ~= lowestBotPID(team) then
        return
    end
    local players = GetTeamPlayers(team)
    do
        local i = 1
        while i <= #players do
            do
                local __continue88
                repeat
                    if IsPlayerBot(players[i]) then
                        __continue88 = true
                        break
                    end
                    local member = GetTeamMember(i)
                    if member == nil or member == nil then
                        __continue88 = true
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
                    if now - hs.snapAt >= ____exports.Get().SnapshotInterval then
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
                    __continue88 = true
                until true
                if not __continue88 then
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
    if now - s.snapAt >= ____exports.Get().SnapshotInterval then
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
