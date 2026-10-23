--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
end

local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
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
-- End of Lua Library inline imports
local ____exports = {}
local dist2D, countsMissing
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LaneMain = require(GetScriptDirectory().."/FunLib/humaniser/lane")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Counter = require(GetScriptDirectory().."/FunLib/humaniser/counterplay")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
local Rotation = require(GetScriptDirectory().."/FunLib/humaniser/transitions/rotation")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function countsMissing(s, alone, e)
    local cfg = Settings.Get()
    local after = alone and cfg.AloneMissing or cfg.LaneMissing
    if e.visible or e.timeSinceSeen <= after or e.timeSinceSeen > cfg.MissingMaxAge or not IsHeroAlive(e.pid) then
        return false
    end
    return dist2D(e.location, s.frontLoc) <= cfg.SpareLaneRadius
end
____exports.SOURCE = "transitions:caution"
function ____exports.CautionLevel(i)
    local cfg = Settings.Get()
    local base = i.missing > 0 and 1 or (i.alone and math.min(
        1,
        cfg.AloneLevel + cfg.AloneLevelPerEnemy * math.max(0, i.laneEnemies - 1)
    ) or 0)
    return base * Settings.Lerp(cfg.SkillAmount, i.skill)
end
local states = {}
local episodes = {}
local forced = {}
function ____exports.ResetCache()
    states = {}
    episodes = {}
    forced = {}
end
local function forcedOf(bot)
    local pid = bot:GetPlayerID()
    local f = forced[pid]
    if f == nil then
        f = {level = 0, levelUntil = -math.huge, pointUntil = -math.huge}
        forced[pid] = f
    end
    return f
end
--- Holds the caution level at no less than `level` until `until` (game time); `until` in the past clears it.
function ____exports.ForceLevel(bot, level, ____until)
    local f = forcedOf(bot)
    f.level = level
    f.levelUntil = ____until
end
--- Holds the lane position at `point` (where OHA owns laning) until `until`; an undefined point clears it.
function ____exports.ForceSetup(bot, point, ____until)
    local f = forcedOf(bot)
    f.point = point
    f.pointUntil = ____until
end
function ____exports.IsAlone(bot, s)
    local pid = bot:GetPlayerID()
    local others = {}
    for ____, h in ipairs(s.allies) do
        if h.assigned and h.pid ~= pid then
            others[#others + 1] = h
        end
    end
    if #others == 0 then
        return LanePlan.EnemyLaners(bot, s) >= 2
    end
    if #others > 1 then
        return false
    end
    local p = others[1]
    if not p.alive then
        return true
    end
    local absent = LaneConfig.Settings().Thresholds.CoreAbsentDist
    local apart = dist2D(
        p.unit:GetLocation(),
        bot:GetLocation()
    ) > absent
    if p.distToFront > absent and apart then
        return true
    end
    return apart and Rotation.Active(p.unit) ~= nil or CampJobs.Active(p.unit)
end
function ____exports.Missing(bot, s, alone)
    local n = 0
    for ____, e in ipairs(LaneState.Enemies(bot, s.lane)) do
        if countsMissing(s, alone, e) then
            n = n + 1
        end
    end
    return n
end
local function stateOf(bot)
    local pid = bot:GetPlayerID()
    local st = states[pid]
    if st == nil then
        st = {
            applied = 0,
            reported = 0,
            alone = false,
            target = 0,
            targetAt = -math.huge,
            delay = 0,
            checkAt = -math.huge,
            missing = 0
        }
        states[pid] = st
    end
    return st
end
local function update(bot, now)
    local st = stateOf(bot)
    if now >= st.checkAt then
        st.checkAt = now + Settings.Get().Refresh
        local laning = Phase.LaningTransitions(bot)
        local ____laning_0
        if laning then
            ____laning_0 = LaneState.ForBot(bot)
        else
            ____laning_0 = nil
        end
        local s = ____laning_0
        local target = 0
        st.missing = 0
        st.alone = false
        st.lane = s and s.lane
        if not laning then
            st.applied = 0
        end
        if s ~= nil then
            local alone = ____exports.IsAlone(bot, s)
            st.alone = alone
            st.missing = ____exports.Missing(bot, s, alone)
            if alone or st.missing > 0 then
                target = ____exports.CautionLevel({
                    alone = alone,
                    laneEnemies = LanePlan.EnemyLaners(bot, s),
                    missing = st.missing,
                    skill = LaneConfig.SkillOf(bot)
                })
            end
        end
        if target ~= st.target then
            st.target = target
            st.targetAt = now
            st.delay = Profile.SampleDelay(bot, "notice")
        end
    end
    if st.applied ~= st.target and now - st.targetAt >= st.delay then
        st.applied = st.target
        HDebug.Log(
            "transitions",
            (((("caution pid=" .. tostring(bot:GetPlayerID())) .. " level=") .. string.format("%.2f", st.applied)) .. " missing=") .. tostring(st.missing)
        )
    end
    if st.applied ~= st.reported then
        st.reported = st.applied
        Telemetry.Event(
            "tr_caution",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"level", st.applied},
                {"alone", st.alone},
                {"missing", st.missing},
                {"lane", st.lane}
            }
        )
    end
    return st
end
--- Lane enemies missing for the bot right now (0 when caution is off or the bot is not laning); `maxAge` keeps only those unseen at most that long.
function ____exports.MissingNow(bot, maxAge)
    if not Settings.IsOn("Caution") or not Phase.LaningTransitions(bot) then
        return 0
    end
    local st = update(
        bot,
        DotaTime()
    )
    if st.missing == 0 or maxAge == nil then
        return st.missing
    end
    local s = LaneState.ForBot(bot)
    if s == nil then
        return 0
    end
    local n = 0
    for ____, e in ipairs(LaneState.Enemies(bot, s.lane)) do
        if e.timeSinceSeen <= maxAge and countsMissing(s, st.alone, e) then
            n = n + 1
        end
    end
    return n
end
--- Hit by a hero just now, low on HP, or under an enemy tower's fire: the moments caution makes a bot readier to run.
function ____exports.Threatened(bot)
    local cfg = Settings.Get()
    local max = bot:GetMaxHealth()
    if max > 0 and bot:GetHealth() / max < cfg.ThreatHP then
        return true
    end
    if bot:WasRecentlyDamagedByAnyHero(cfg.ThreatHitWindow) then
        return true
    end
    return LaneState.EnemyTowerTargeting(bot)
end
function ____exports.Level(bot)
    if not Phase.LaningTransitions(bot) then
        return 0
    end
    local now = DotaTime()
    local applied = Settings.IsOn("Caution") and update(bot, now).applied or 0
    local f = forced[bot:GetPlayerID()]
    return f ~= nil and Settings.IsOn("Teleports") and now < f.levelUntil and math.max(applied, f.level) or applied
end
local function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end
local function towardTower(bot, loc, level)
    local s = LaneState.ForBot(bot)
    if s == nil then
        return loc
    end
    local cfg = Settings.Get()
    local tower = GetLocationAlongLane(
        s.lane,
        clamp01(Camps.ToAbsAmount(s.team, s.ourTowerAmount))
    )
    local d = dist2D(loc, tower)
    if d <= 0 then
        return loc
    end
    local step = math.min(d, cfg.OffsetMin + (cfg.OffsetMax - cfg.OffsetMin) * level)
    return Vector(loc.x + (tower.x - loc.x) / d * step, loc.y + (tower.y - loc.y) / d * step, loc.z)
end
--- Lane position override (plan call 6); returns `loc` itself when caution does not apply.
function ____exports.AdjustPosition(bot, loc)
    local f = forced[bot:GetPlayerID()]
    if f ~= nil and f.point ~= nil and Settings.IsOn("Teleports") and DotaTime() < f.pointUntil and Phase.LaningTransitions(bot) then
        return LaneMain.OwnsLaning(bot) and f.point or loc
    end
    if not Settings.IsOn("Caution") then
        return loc
    end
    local level = ____exports.Level(bot)
    if level <= 0 or not LaneMain.OwnsLaning(bot) then
        return loc
    end
    return towardTower(bot, loc, level)
end
function ____exports.SuppressTrades(bot)
    if ____exports.Level(bot) < Settings.Get().SuppressLevel then
        return false
    end
    local stronger = LaneConfig.Helpers().WeAreStronger
    return stronger == nil or not stronger(
        bot,
        Settings.Get().CautionStrongerRadius
    )
end
local LANE_NAMES = {[Lane.Top] = "top", [Lane.Mid] = "mid", [Lane.Bot] = "bot"}
local function midAlreadyCalled(bot, now)
    local window = Settings.Get().MidMissingSignalWindow
    for ____, sig in ipairs(Counter.Signals(bot)) do
        if sig.kind == "mid_missing" and now - sig.at <= window then
            return true
        end
    end
    return false
end
local function callout(bot, st, now)
    if st.lane == nil then
        return
    end
    local name = LANE_NAMES[st.lane]
    if name == nil then
        return
    end
    local key = (tostring(bot:GetTeam()) .. ":") .. tostring(st.lane)
    local ep = episodes[key]
    if ep == nil then
        ep = {active = false, saidAt = -math.huge}
        episodes[key] = ep
    end
    if st.missing == 0 then
        ep.active = false
        return
    end
    if ep.active or not Difficulty.IsAllyOfHuman(bot) then
        return
    end
    ep.active = true
    local cooldown = Settings.Get().MissingCooldown
    if now - ep.saidAt < cooldown then
        return
    end
    if st.lane == Lane.Mid and midAlreadyCalled(bot, now) then
        return
    end
    ep.saidAt = now
    Orders.Say(bot, "say_ss_" .. name, cooldown)
end
function ____exports.Tick(bot)
    if not Settings.IsOn("Caution") and not Settings.IsOn("Teleports") then
        return
    end
    if not Phase.LaningTransitions(bot) then
        if Settings.IsOn("Caution") then
            update(
                bot,
                DotaTime()
            )
        end
        __TS__Delete(
            forced,
            bot:GetPlayerID()
        )
        Intent.ReleaseSource(bot, ____exports.SOURCE)
        return
    end
    if Settings.IsOn("Caution") then
        local now = DotaTime()
        callout(
            bot,
            update(bot, now),
            now
        )
    end
    local level = ____exports.Level(bot)
    if level <= 0 then
        Intent.ReleaseSource(bot, ____exports.SOURCE)
        return
    end
    local f = forced[bot:GetPlayerID()]
    local tpForced = f ~= nil and Settings.IsOn("Teleports") and DotaTime() < f.levelUntil
    if not tpForced and not ____exports.Threatened(bot) then
        Intent.ReleaseSource(bot, ____exports.SOURCE)
        return
    end
    Intent.Claim(
        bot,
        {
            source = ____exports.SOURCE,
            tier = "TRANSITION",
            mode = BotMode.Retreat,
            scale = 1 + (Settings.Get().RetreatScaleMax - 1) * level
        }
    )
end
function ____exports.RegisterProbes()
    LaneHooks.SetCautionProbe(function(bot) return ____exports.Level(bot) > 0 end)
    LaneHooks.SetPositionProbe(____exports.AdjustPosition)
    LaneHooks.SetTradeProbe(____exports.SuppressTrades)
    LaneHooks.SetMissingProbe(____exports.MissingNow)
end
____exports.RegisterProbes()
return ____exports
