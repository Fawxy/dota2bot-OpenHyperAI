--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
end

local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
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

local function __TS__ArrayIndexOf(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    if len == 0 then
        return -1
    end
    if fromIndex >= len then
        return -1
    end
    if fromIndex < 0 then
        fromIndex = len + fromIndex
        if fromIndex < 0 then
            fromIndex = 0
        end
    end
    for i = fromIndex + 1, len do
        if self[i] == searchElement then
            return i - 1
        end
    end
    return -1
end

local function __TS__ArrayFilter(self, callbackfn, thisArg)
    local result = {}
    local len = 0
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            len = len + 1
            result[len] = self[i]
        end
    end
    return result
end

local function __TS__ObjectKeys(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = key
    end
    return result
end

local function __TS__ObjectAssign(target, ...)
    local sources = {...}
    for i = 1, #sources do
        local source = sources[i]
        for key in pairs(source) do
            target[key] = source[key]
        end
    end
    return target
end

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
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

local function __TS__ArraySome(self, callbackfn, thisArg)
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            return true
        end
    end
    return false
end

local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
end
-- End of Lua Library inline imports
local ____exports = {}
local swingOf, ATTACK_ACTIVITIES
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local GameState = ____dota.GameState
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/trainer/settings")
local ____api = require(GetScriptDirectory().."/FunLib/humaniser/trainer/api")
local CreepKind = ____api.CreepKind
local GetTrainerHelpers = ____api.GetTrainerHelpers
local HeroLabel = ____api.HeroLabel
local SetTrainerHelpers = ____api.SetTrainerHelpers
local T = ____api.T
local ____spike = require(GetScriptDirectory().."/FunLib/humaniser/trainer/spike")
local SpikeTick = ____spike.SpikeTick
local ____incoming = require(GetScriptDirectory().."/FunLib/humaniser/trainer/incoming")
local Heroes = ____incoming.Heroes
local NearbyUnits = ____incoming.NearbyUnits
local Towers = ____incoming.Towers
local ____predict = require(GetScriptDirectory().."/FunLib/humaniser/trainer/predict")
local EffectiveDamage = ____predict.EffectiveDamage
local Predict = ____predict.Predict
local Smoother = ____predict.Smoother
local ____judge = require(GetScriptDirectory().."/FunLib/humaniser/trainer/judge")
local Judge = ____judge.Judge
local ____watch = require(GetScriptDirectory().."/FunLib/humaniser/trainer/watch")
local Attribute = ____watch.Attribute
local IsDeathLikely = ____watch.IsDeathLikely
local SelectCreeps = ____watch.SelectCreeps
local ____stats = require(GetScriptDirectory().."/FunLib/humaniser/trainer/stats")
local Stats = ____stats.Stats
local ____draw = require(GetScriptDirectory().."/FunLib/humaniser/trainer/draw")
local Bars = ____draw.Bars
local SummaryText = ____draw.SummaryText
local VerdictLines = ____draw.VerdictLines
function swingOf(u, now)
    if ATTACK_ACTIVITIES[u:GetAnimActivity()] ~= true then
        return {anim = "none"}
    end
    local cycle = u:GetAnimCycle()
    return {
        anim = cycle < u:GetAttackPoint() and "swing" or "followthrough",
        swingStart = now - cycle / u:GetAttackSpeed()
    }
end
local REPLY_INTERVAL = 0.5
local REPLY_CAP = 8
local USAGE = "usage: !trainer on|off|stats|reset|bar on|off|chat off|misses|all|denies on|off"
local MAX_BARS = 2
--- Last frame's bars keep their place unless another window closes this much sooner. A throttled prediction's
-- startClose can trail a fresh one by up to a WatchInterval, which would otherwise swap the bars every frame.
local BAR_STICKINESS = 0.2
local CANDIDATE_RADIUS = 800
local DENY_HP_FRACTION = 0.6
local HERO_FIGHT_SECONDS = 2
local HARASS_SECONDS = 2
ATTACK_ACTIVITIES = {[1503] = true, [1504] = true}
local VERDICT_LINES_KEPT = 3
local CHAT_INTERVAL = 2
local MISS_KINDS = {EARLY = true, LATE = true, MISS = true, MISSED_EASY = true}
--- A last-hit or deny counter that rose this long before a death is still matched to it.
local COUNTER_MATCH_SECONDS = 0.15
local HISTORY_SECONDS = 0.5
local teams = {}
local warned = {}
function ____exports.SetHelpers(h)
    SetTrainerHelpers(h)
end
function ____exports.GetHelpers()
    return GetTrainerHelpers()
end
--- Same rule as commands.ts's lowestBotPID; not imported from there (commands.ts imports this module).
function ____exports.TrainerBotPID(team)
    local best
    for ____, pid in ipairs(GetTeamPlayers(team)) do
        if IsPlayerBot(pid) and (best == nil or pid < best) then
            best = pid
        end
    end
    return best
end
local function stateFor(team)
    local s = teams[team]
    if s == nil then
        local cfg = Settings.Get()
        s = {
            on = false,
            bar = cfg.Bar,
            chat = cfg.Chat,
            denies = cfg.Denies,
            spike = false,
            replies = {},
            lastReplyAt = -math.huge,
            subjects = {},
            checkpointsDone = {},
            wasLaning = nil,
            selfTestStarted = false,
            lastChatAt = -math.huge,
            history = {}
        }
        teams[team] = s
    end
    return s
end
local function newSubject()
    return {
        judge = __TS__New(
            Judge,
            Settings.Get().EasyWindow
        ),
        stats = __TS__New(Stats),
        smoothers = {},
        lastHeroAttackAt = -math.huge,
        verdictLines = {},
        cache = {},
        predictedAt = {},
        barIds = {},
        watchedIds = {},
        bars = {},
        predictions = {},
        tracked = {},
        credits = {}
    }
end
local function subjectState(s, pid)
    local st = s.subjects[pid]
    if st == nil then
        st = newSubject()
        s.subjects[pid] = st
    end
    return st
end
local function queueReply(s, line)
    if #s.replies >= REPLY_CAP then
        return
    end
    local ____s_replies_0 = s.replies
    ____s_replies_0[#____s_replies_0 + 1] = line
end
local function onOff(s)
    return s.on and "on" or "off"
end
local function status(s)
    return (((((("trainer " .. onOff(s)) .. " - bar ") .. (s.bar and "on" or "off")) .. " - chat ") .. s.chat) .. " - denies ") .. (s.denies and "on" or "off")
end
local function parseOnOff(word)
    if word == "on" then
        return true
    end
    if word == "off" then
        return false
    end
    return nil
end
local function switchOn(s)
    s.on = true
    s.subjects = {}
    s.history = {}
    s.wasLaning = nil
    s.checkpointsDone = {}
    local dota = DotaTime()
    for ____, c in ipairs(Settings.Get().Checkpoints) do
        if c <= dota then
            s.checkpointsDone[c] = true
        end
    end
end
local function switchOff(s)
    s.on = false
    for ____, st in pairs(s.subjects) do
        st.verdictLines = {}
        st.summary = nil
        st.bars = {}
        st.predictions = {}
    end
end
local function humanPID(team)
    local best
    for ____, pid in ipairs(GetTeamPlayers(team)) do
        if not IsPlayerBot(pid) and (best == nil or pid < best) then
            best = pid
        end
    end
    return best
end
local function summaryLines(s, st)
    return st.stats:Lines({
        outcomeOnly = Settings.Get().OutcomeOnly,
        denies = s.denies
    })
end
function ____exports.OnCommand(team, _pid, args)
    if not Settings.IsEnabled() then
        return
    end
    local s = stateFor(team)
    local sub = args[1]
    local function reply(line)
        return queueReply(s, line)
    end
    if sub == nil then
        reply(status(s))
    elseif sub == "on" or sub == "off" then
        if sub == "off" then
            switchOff(s)
        elseif not s.on then
            switchOn(s)
        end
        reply(status(s))
    elseif sub == "bar" or sub == "denies" then
        local value = parseOnOff(args[2])
        if value == nil then
            reply(USAGE)
        else
            if sub == "bar" then
                s.bar = value
            else
                s.denies = value
            end
            reply(status(s))
        end
    elseif sub == "chat" then
        local mode = args[2]
        if mode == "off" or mode == "misses" or mode == "all" then
            s.chat = mode
            reply(status(s))
        else
            reply(USAGE)
        end
    elseif sub == "stats" then
        if args[2] == "selftest" then
            local botPid = ____exports.TrainerBotPID(team)
            local ____temp_1
            if botPid == nil then
                ____temp_1 = nil
            else
                ____temp_1 = s.subjects[botPid]
            end
            local st = ____temp_1
            reply((st and st.stats or __TS__New(Stats)):SelfTestLine())
        else
            local pid = humanPID(team)
            local st = pid == nil and newSubject() or subjectState(s, pid)
            local lines = summaryLines(s, st)
            st.summary = {
                lines = lines,
                at = GameTime()
            }
            for ____, line in ipairs(lines) do
                reply(line)
            end
        end
    elseif sub == "reset" then
        for ____, st in pairs(s.subjects) do
            st.stats:Reset()
            st.judge = __TS__New(
                Judge,
                Settings.Get().EasyWindow
            )
        end
        reply("trainer stats reset")
    elseif sub == "spike" and Config.Get().Debug == true then
        s.spike = not s.spike
        HDebug.Log("trainer", "spike", s.spike and "on" or "off")
    else
        reply(USAGE)
    end
end
--- Humans on the team by lowest PID. GetTeamMember answers for the calling bot's team, hence the team check.
local function humans(team)
    local result = {}
    local players = GetTeamPlayers(team)
    do
        local i = 1
        while i <= #players do
            do
                local __continue56
                repeat
                    local member = GetTeamMember(i)
                    if member == nil or member == nil or member:GetTeam() ~= team then
                        __continue56 = true
                        break
                    end
                    if not IsPlayerBot(member:GetPlayerID()) then
                        result[#result + 1] = member
                    end
                    __continue56 = true
                until true
                if not __continue56 then
                    break
                end
            end
            i = i + 1
        end
    end
    table.sort(
        result,
        function(a, b) return a:GetPlayerID() < b:GetPlayerID() end
    )
    return result
end
local function trainerBotUnit(team)
    local pid = ____exports.TrainerBotPID(team)
    local players = GetTeamPlayers(team)
    do
        local i = 1
        while i <= #players do
            local member = GetTeamMember(i)
            if member ~= nil and member ~= nil and member:GetTeam() == team and member:GetPlayerID() == pid then
                return member
            end
            i = i + 1
        end
    end
    return nil
end
local function subjectsFor(team, trainerBot)
    local found = humans(team)
    local subjects = {}
    if #found > 0 then
        subjects[#subjects + 1] = found[1]
    end
    do
        local i = 1
        while i < #found do
            local pid = found[i + 1]:GetPlayerID()
            if warned[team] == nil then
                warned[team] = {}
            end
            if warned[team][pid] ~= true then
                warned[team][pid] = true
                HDebug.Log(
                    "trainer",
                    "[WARN] trainer coaches one player; ignoring pid " .. tostring(pid)
                )
            end
            i = i + 1
        end
    end
    if Settings.Get().SelfTest and trainerBot ~= nil then
        subjects[#subjects + 1] = trainerBot
    end
    return subjects
end
--- The human, then the self-test bot when SelfTest is on.
function ____exports.GetSubjects(team)
    if not Settings.IsEnabled() then
        return {}
    end
    return subjectsFor(
        team,
        trainerBotUnit(team)
    )
end
--- The human's bar predictions for the current frame.
function ____exports.Predictions(team)
    local s = teams[team]
    local pid = humanPID(team)
    if s == nil or pid == nil then
        return {}
    end
    local ____opt_4 = s.subjects[pid]
    return ____opt_4 and ____opt_4.bars or ({})
end
--- One subject's bar and watched predictions for the current frame.
function ____exports.SubjectPredictions(team, pid)
    local ____opt_8 = teams[team]
    local ____opt_6 = ____opt_8 and ____opt_8.subjects[pid]
    return ____opt_6 and ____opt_6.predictions or ({})
end
--- Decided at laning-file load, so it uses only GetTeamPlayers and IsPlayerBot.
function ____exports.IsSelfTestBot(bot)
    return Settings.IsEnabled() and Settings.Get().SelfTest and bot:GetPlayerID() == ____exports.TrainerBotPID(bot:GetTeam())
end
--- The bot's own creep whose start window has reached now; the earliest-closing one wins.
function ____exports.SelfTestTarget(bot)
    local now = GameTime()
    local best
    for ____, p in ipairs(____exports.SubjectPredictions(
        bot:GetTeam(),
        bot:GetPlayerID()
    )) do
        if p.startOpen <= now and now < p.startClose and (best == nil or p.startClose < best.startClose) then
            best = p
        end
    end
    return best and best.creep
end
--- True while the self-test bot's own swing at a creep is before its attack point: any order now would cancel it.
function ____exports.SelfTestHolding(bot)
    if not ____exports.IsSelfTestBot(bot) then
        return false
    end
    local target = bot:GetAttackTarget()
    if target == nil or target == nil or target:IsHero() then
        return false
    end
    return swingOf(
        T(bot),
        GameTime()
    ).anim == "swing"
end
local function creepId(u)
    return tostring(u)
end
local function isLaneCreep(u)
    if u:IsHero() or T(u):IsTower() then
        return false
    end
    local name = u:GetUnitName()
    return (string.find(name, "npc_dota_creep_", 1, true)) ~= nil or (string.find(name, "siege", 1, true)) ~= nil
end
local function candidatesFor(subject, denies)
    local result = {}
    for ____, u in ipairs(NearbyUnits(
        subject:GetLocation(),
        CANDIDATE_RADIUS
    )) do
        do
            local __continue86
            repeat
                if not isLaneCreep(u) or not u:CanBeSeen() then
                    __continue86 = true
                    break
                end
                local ally = u:GetTeam() == subject:GetTeam()
                if ally and not (denies and u:GetHealth() < DENY_HP_FRACTION * u:GetMaxHealth()) then
                    __continue86 = true
                    break
                end
                result[#result + 1] = {
                    id = creepId(u),
                    creep = u,
                    isDeny = ally
                }
                __continue86 = true
            until true
            if not __continue86 then
                break
            end
        end
    end
    return result
end
local function predictOne(st, subject, c, now)
    local smoother = st.smoothers[c.id]
    if smoother == nil then
        smoother = __TS__New(Smoother)
        st.smoothers[c.id] = smoother
    end
    st.predictedAt[c.id] = now
    local p = Predict(
        subject,
        c.creep,
        c.isDeny,
        now,
        smoother
    )
    if p == nil then
        __TS__Delete(st.cache, c.id)
    else
        st.cache[c.id] = p
    end
end
--- At most MAX_BARS + MaxWatched predictions per frame: the attack target and last frame's bars every frame,
-- then the stalest other candidates once their prediction is WatchInterval old, current watched creeps first.
local function refreshPredictions(st, subject, cands, target, now)
    local cfg = Settings.Get()
    local byId = {}
    for ____, c in ipairs(cands) do
        byId[c.id] = c
    end
    local priority = {}
    if target ~= nil and byId[creepId(target)] ~= nil then
        priority[#priority + 1] = creepId(target)
    end
    for ____, id in ipairs(st.barIds) do
        if byId[id] ~= nil and __TS__ArrayIndexOf(priority, id) < 0 then
            priority[#priority + 1] = id
        end
    end
    local done = {}
    do
        local i = 0
        while i < math.min(#priority, MAX_BARS) do
            predictOne(st, subject, byId[priority[i + 1]], now)
            done[priority[i + 1]] = true
            i = i + 1
        end
    end
    local watched = {}
    for ____, id in ipairs(st.watchedIds) do
        watched[id] = true
    end
    local rest = __TS__ArrayFilter(
        cands,
        function(____, c) return not done[c.id] and now - (st.predictedAt[c.id] or -math.huge) >= cfg.WatchInterval end
    )
    table.sort(
        rest,
        function(a, b)
            if watched[a.id] == true ~= (watched[b.id] == true) then
                return watched[a.id] == true
            end
            return (st.predictedAt[a.id] or -math.huge) < (st.predictedAt[b.id] or -math.huge)
        end
    )
    do
        local i = 0
        while i < math.min(#rest, cfg.MaxWatched) do
            predictOne(st, subject, rest[i + 1], now)
            i = i + 1
        end
    end
end
local function prune(st, cands)
    local keep = {}
    for ____, c in ipairs(cands) do
        keep[c.id] = true
    end
    for ____, id in ipairs(__TS__ObjectKeys(st.tracked)) do
        keep[id] = true
    end
    for ____, id in ipairs(__TS__ObjectKeys(st.cache)) do
        if not keep[id] then
            __TS__Delete(st.cache, id)
        end
    end
    for ____, id in ipairs(__TS__ObjectKeys(st.smoothers)) do
        if not keep[id] then
            __TS__Delete(st.smoothers, id)
        end
    end
    for ____, id in ipairs(__TS__ObjectKeys(st.predictedAt)) do
        if not keep[id] then
            __TS__Delete(st.predictedAt, id)
        end
    end
end
--- Ids of the creeps some tower is attacking this frame.
local function towerTargets()
    local targets = {}
    for ____, tower in ipairs(Towers()) do
        local target = tower:GetAttackTarget()
        if target ~= nil and target ~= nil then
            targets[creepId(target)] = true
        end
    end
    return targets
end
local function snapshot(heroes)
    local counters = {lastHits = {}, denies = {}}
    local seen = {}
    for ____, h in ipairs(heroes) do
        do
            local __continue127
            repeat
                local pid = h:GetPlayerID()
                if counters.lastHits[pid] ~= nil then
                    __continue127 = true
                    break
                end
                counters.lastHits[pid] = T(h):GetLastHits()
                counters.denies[pid] = T(h):GetDenies()
                seen[#seen + 1] = {
                    pid = pid,
                    team = h:GetTeam(),
                    name = HeroLabel(h)
                }
                __continue127 = true
            until true
            if not __continue127 then
                break
            end
        end
    end
    return {counters = counters, seen = seen}
end
--- Counters from just before the match window, with rises already matched to other deaths added back.
local function countersBefore(s, st, now, current)
    local snap = s.history[1]
    for ____, h in ipairs(s.history) do
        if h.t <= now - COUNTER_MATCH_SECONDS then
            snap = h
        end
    end
    if snap == nil then
        return current
    end
    local before = {lastHits = {}, denies = {}}
    for pid, v in pairs(snap.counters.lastHits) do
        before.lastHits[pid] = v
    end
    for pid, v in pairs(snap.counters.denies) do
        before.denies[pid] = v
    end
    for ____, c in ipairs(st.credits) do
        if c.t > snap.t then
            before[c.counter][c.pid] = (before[c.counter][c.pid] or 0) + 1
        end
    end
    return before
end
local function attribute(s, st, subject, t, obs, now, current, refs)
    local killer = Attribute(
        obs,
        subject:GetPlayerID(),
        countersBefore(s, st, now, current),
        current,
        refs,
        t.towerTargeting
    )
    local pid
    if killer.kind == "subject" then
        pid = subject:GetPlayerID()
    elseif killer.kind == "ally" or killer.kind == "enemyHero" then
        local ally = killer.kind == "ally"
        for ____, r in ipairs(refs) do
            if r.ally == ally and r.name == killer.name then
                pid = r.pid
            end
        end
    end
    if pid ~= nil then
        local ____st_credits_12 = st.credits
        ____st_credits_12[#____st_credits_12 + 1] = {t = now, counter = t.isDeny and "denies" or "lastHits", pid = pid}
    end
    return killer
end
local function creepObservations(s, st, subject, frame, refs)
    local ____frame_13 = frame
    local now = ____frame_13.now
    local current = ____frame_13.counters
    local result = {}
    for ____, id in ipairs(__TS__ObjectKeys(st.tracked)) do
        do
            local __continue148
            repeat
                local t = st.tracked[id]
                local c = t.creep
                local state
                if c:IsNull() then
                    state = "lost"
                elseif not c:IsAlive() then
                    state = "dead"
                elseif not c:CanBeSeen() then
                    state = "lost"
                else
                    state = "alive"
                end
                if state == "alive" then
                    local p = st.cache[id]
                    t.hp = c:GetHealth()
                    t.maxHp = c:GetMaxHealth()
                    t.dist = GetUnitToUnitDistance(subject, c)
                    t.effDmg = p ~= nil and p.effDmg or EffectiveDamage(subject, c, t.isDeny)
                    t.towerTargeting = frame.towerTargets[id] == true
                    result[#result + 1] = {
                        id = id,
                        kind = t.kind,
                        isDeny = t.isDeny,
                        alive = true,
                        hp = t.hp,
                        dist = t.dist,
                        prediction = p
                    }
                    __continue148 = true
                    break
                end
                __TS__Delete(st.tracked, id)
                if state == "lost" and not IsDeathLikely(t.hp, t.maxHp, t.effDmg, t.dist) then
                    __continue148 = true
                    break
                end
                local obs = {
                    id = id,
                    kind = t.kind,
                    isDeny = t.isDeny,
                    alive = false,
                    hp = 0,
                    dist = t.dist
                }
                obs.killer = attribute(
                    s,
                    st,
                    subject,
                    t,
                    obs,
                    now,
                    current,
                    refs
                )
                result[#result + 1] = obs
                __continue148 = true
            until true
            if not __continue148 then
                break
            end
        end
    end
    while #st.credits > 0 and now - st.credits[1].t > HISTORY_SECONDS do
        table.remove(st.credits, 1)
    end
    return result
end
local function subjectObservation(st, subject, target, now)
    local u = T(subject)
    local alive = subject:IsAlive()
    local inFight = now - st.lastHeroAttackAt <= HERO_FIGHT_SECONDS
    local ____swingOf_result_14 = swingOf(u, now)
    local anim = ____swingOf_result_14.anim
    local swingStart = ____swingOf_result_14.swingStart
    return {
        now = now,
        alive = alive,
        eligible = alive and not u:IsStunned() and not u:IsHexed() and not u:IsChanneling() and not inFight,
        harassed = u:WasRecentlyDamagedByAnyHero(HARASS_SECONDS),
        target = target ~= nil and not target:IsHero() and creepId(target) or nil,
        anim = anim,
        swingStart = swingStart,
        lastHits = u:GetLastHits(),
        denies = u:GetDenies()
    }
end
local function fmt(x)
    return x == nil and "-" or string.format("%.2f", x)
end
local function onVerdict(s, st, subject, v, now)
    Telemetry.Event(
        "trainer",
        {
            {
                "pid",
                subject:GetPlayerID()
            },
            {
                "selftest",
                IsPlayerBot(subject:GetPlayerID())
            },
            {"kind", v.kind},
            {"creep", v.creepKind},
            {"deny", v.isDeny},
            {"offset", v.offset},
            {"window", v.window},
            {"pred", v.predictedLand},
            {"landed", v.landedAt}
        }
    )
    if IsPlayerBot(subject:GetPlayerID()) then
        HDebug.Log(
            "trainer",
            (((("selftest predicted=" .. fmt(v.predictedLand)) .. " actual=") .. fmt(v.landedAt)) .. " verdict=") .. v.kind
        )
        return
    end
    local ____st_verdictLines_15 = st.verdictLines
    ____st_verdictLines_15[#____st_verdictLines_15 + 1] = {text = v.reason, kind = v.kind, at = now}
    while #st.verdictLines > VERDICT_LINES_KEPT do
        table.remove(st.verdictLines, 1)
    end
    local toChat = not Settings.Get().ScreenText or s.chat == "all" or s.chat == "misses" and MISS_KINDS[v.kind] == true
    if toChat and now - s.lastChatAt >= CHAT_INTERVAL then
        s.lastChatAt = now
        queueReply(s, v.reason)
    end
end
local function stepSubject(s, subject, frame)
    local now = frame.now
    local cfg = Settings.Get()
    local st = subjectState(
        s,
        subject:GetPlayerID()
    )
    local rawTarget = subject:GetAttackTarget()
    local ____temp_16
    if rawTarget == nil or rawTarget == nil then
        ____temp_16 = nil
    else
        ____temp_16 = rawTarget
    end
    local target = ____temp_16
    if target ~= nil and target:IsHero() then
        st.lastHeroAttackAt = now
    end
    local cands = candidatesFor(subject, s.denies)
    refreshPredictions(
        st,
        subject,
        cands,
        target,
        now
    )
    local wasBar = {}
    for ____, id in ipairs(st.barIds) do
        wasBar[id] = true
    end
    local ranked = __TS__ArrayMap(
        cands,
        function(____, c)
            local p = st.cache[c.id]
            local prediction = p ~= nil and wasBar[c.id] == true and __TS__ObjectAssign({}, p, {startClose = p.startClose - BAR_STICKINESS}) or p
            return {creep = c.creep, isDeny = c.isDeny, prediction = prediction}
        end
    )
    local selected = SelectCreeps(subject, ranked, MAX_BARS, cfg.MaxWatched)
    local isDeny = {}
    for ____, c in ipairs(cands) do
        isDeny[c.id] = c.isDeny
    end
    st.barIds = __TS__ArrayMap(
        selected.bars,
        function(____, u) return creepId(u) end
    )
    st.watchedIds = __TS__ArrayMap(
        selected.watched,
        function(____, u) return creepId(u) end
    )
    st.bars = __TS__ArrayMap(
        st.barIds,
        function(____, id) return st.cache[id] end
    )
    local ____array_17 = __TS__SparseArrayNew(unpack(st.bars))
    __TS__SparseArrayPush(
        ____array_17,
        unpack(__TS__ArrayMap(
            st.watchedIds,
            function(____, id) return st.cache[id] end
        ))
    )
    st.predictions = {__TS__SparseArraySpread(____array_17)}
    local ____array_18 = __TS__SparseArrayNew(unpack(selected.bars))
    __TS__SparseArrayPush(
        ____array_18,
        unpack(selected.watched)
    )
    for ____, u in ipairs({__TS__SparseArraySpread(____array_18)}) do
        local id = creepId(u)
        if st.tracked[id] == nil then
            st.tracked[id] = {
                creep = u,
                kind = CreepKind(u),
                isDeny = isDeny[id],
                hp = u:GetHealth(),
                maxHp = u:GetMaxHealth(),
                effDmg = 0,
                dist = 0,
                towerTargeting = false
            }
        end
    end
    local team = subject:GetTeam()
    local refs = __TS__ArrayMap(
        frame.heroes,
        function(____, h) return {pid = h.pid, name = h.name, ally = h.team == team} end
    )
    local creeps = creepObservations(
        s,
        st,
        subject,
        frame,
        refs
    )
    prune(st, cands)
    local events = st.judge:Step(
        subjectObservation(st, subject, target, now),
        creeps
    )
    for ____, e in ipairs(events) do
        st.stats:Add(e)
        if e.type == "verdict" then
            onVerdict(
                s,
                st,
                subject,
                e.v,
                now
            )
        end
    end
end
local function checkpoints(s, human, now)
    local post = false
    local dota = DotaTime()
    for ____, c in ipairs(Settings.Get().Checkpoints) do
        if s.checkpointsDone[c] ~= true and dota >= c then
            s.checkpointsDone[c] = true
            post = true
        end
    end
    local helpers = GetTrainerHelpers()
    if helpers ~= nil then
        local laning = helpers.IsInLaningPhase()
        if s.wasLaning == true and not laning then
            post = true
        end
        s.wasLaning = laning
    end
    if not post or human == nil then
        return
    end
    local lines = summaryLines(s, human)
    human.summary = {lines = lines, at = now}
    for ____, line in ipairs(lines) do
        queueReply(s, line)
    end
end
local function run(bot, team, s, now)
    local subjects = subjectsFor(team, bot)
    local ____snapshot_20 = snapshot
    local ____array_19 = __TS__SparseArrayNew(unpack(Heroes()))
    __TS__SparseArrayPush(
        ____array_19,
        unpack(subjects)
    )
    local ____snapshot_20_result_21 = ____snapshot_20({__TS__SparseArraySpread(____array_19)})
    local counters = ____snapshot_20_result_21.counters
    local seen = ____snapshot_20_result_21.seen
    local frame = {
        now = now,
        counters = counters,
        heroes = seen,
        towerTargets = towerTargets()
    }
    for ____, subject in ipairs(subjects) do
        stepSubject(s, subject, frame)
    end
    local ____s_history_22 = s.history
    ____s_history_22[#____s_history_22 + 1] = {t = now, counters = counters}
    while #s.history > 1 and now - s.history[1].t > HISTORY_SECONDS do
        table.remove(s.history, 1)
    end
    local cfg = Settings.Get()
    local pid = humanPID(team)
    local human = pid ~= nil and __TS__ArraySome(
        subjects,
        function(____, u) return u:GetPlayerID() == pid end
    ) and s.subjects[pid] or nil
    checkpoints(s, human, now)
    if cfg.ScreenText and human ~= nil then
        VerdictLines(human.verdictLines, now)
        if human.summary ~= nil then
            SummaryText(human.summary.lines, human.summary.at, now)
        end
    end
    if s.bar and pid ~= nil then
        local unit = __TS__ArrayFind(
            subjects,
            function(____, u) return u:GetPlayerID() == pid end
        )
        if unit ~= nil then
            Bars(
                unit,
                ____exports.Predictions(team),
                now,
                swingOf(
                    T(unit),
                    now
                ).swingStart
            )
        end
    end
end
function ____exports.Tick(bot)
    if not Settings.IsEnabled() then
        return
    end
    local team = bot:GetTeam()
    if bot:GetPlayerID() ~= ____exports.TrainerBotPID(team) then
        return
    end
    local cfg = Settings.Get()
    if teams[team] == nil and not cfg.SelfTest then
        return
    end
    local s = stateFor(team)
    local now = GameTime()
    if cfg.SelfTest and not s.selfTestStarted and GetGameState() == GameState.GameInProgress then
        s.selfTestStarted = true
        switchOn(s)
    end
    if #s.replies > 0 and now - s.lastReplyAt >= REPLY_INTERVAL then
        s.lastReplyAt = now
        bot:ActionImmediate_Chat(
            table.remove(s.replies, 1),
            false
        )
    end
    if s.spike then
        local subject = humans(team)[1]
        if subject ~= nil then
            SpikeTick(bot, subject)
        end
    end
    if s.on then
        run(bot, team, s, now)
    end
end
return ____exports
