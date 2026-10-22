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
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Rune = ____dota.Rune
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
local Runes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/runes")
____exports.SOURCE = "transitions:mid_rune"
local states = {}
function ____exports.ResetCache()
    for k in pairs(states) do
        __TS__Delete(states, k)
    end
end
local function stateFor(bot)
    local pid = bot:GetPlayerID()
    local s = states[pid]
    if s == nil then
        s = {
            checkAt = -math.huge,
            claim = false,
            focus = false,
            preSpawn = false,
            spawn = -1,
            seenAvailable = {},
            seenEmpty = {},
            taken = false,
            done = false,
            skipSpawn = -1
        }
        states[pid] = s
    end
    return s
end
function ____exports.IsMid(bot)
    return LaneConfig.PositionOf(bot) == 2
end
function ____exports.IsOn(bot)
    return Settings.IsOn("MidRunes") and ____exports.IsMid(bot)
end
local POWER_SPOTS = {Rune.Power1, Rune.Power2}
local function distanceTo(loc, rune)
    local spot = GetRuneSpawnLocation(rune)
    return math.sqrt((spot.x - loc.x) ^ 2 + (spot.y - loc.y) ^ 2)
end
--- The nearest power spot passing `ok`, or undefined.
local function nearestPower(loc, ok)
    local best
    local bestD = math.huge
    for ____, rune in ipairs(POWER_SPOTS) do
        local d = distanceTo(loc, rune)
        if ok(rune) and d < bestD then
            bestD = d
            best = rune
        end
    end
    return best, bestD
end
--- The latest power spawn strictly before `now`, or undefined before the first.
local function lastSpawn(now)
    local last = Runes.NextSpawn("power", now) - Runes.RUNE_RULES.power.every
    return last >= Runes.RUNE_RULES.power.first and last < now and last or nil
end
local function refresh(bot, s, now)
    local cfg = Settings.Get()
    s.checkAt = now + cfg.Refresh
    local loc = bot:GetLocation()
    local due = Runes.NextSpawn("power", now) - now
    s.preSpawn = due <= cfg.MidRuneFocus
    s.target = nil
    local pending = false
    local last = lastSpawn(now)
    if last ~= nil then
        if s.spawn ~= last then
            s.spawn = last
            s.seenAvailable = {}
            s.seenEmpty = {}
            s.taken = false
        end
        local available
        for ____, rune in ipairs(POWER_SPOTS) do
            local status = GetRuneStatus(rune)
            if status == RUNE_STATUS_AVAILABLE then
                s.seenAvailable[rune] = true
                s.seenEmpty[rune] = false
                available = rune
            elseif status == RUNE_STATUS_MISSING then
                if s.seenAvailable[rune] == true then
                    s.taken = true
                elseif now - last >= cfg.MidRuneSpawnGrace then
                    s.seenEmpty[rune] = true
                end
            end
        end
        s.done = s.taken or s.seenEmpty[Rune.Power1] == true and s.seenEmpty[Rune.Power2] == true
        if not s.done then
            if available ~= nil then
                s.target = available
            elseif now - last <= cfg.MidRuneCheckWindow then
                s.target = (nearestPower(
                    loc,
                    function(r) return s.seenEmpty[r] ~= true end
                ))
            end
            pending = s.target ~= nil
        end
    end
    local inReach = (s.target ~= nil and distanceTo(loc, s.target) or select(
        2,
        nearestPower(
            loc,
            function() return true end
        )
    )) <= cfg.MidRuneRadius
    s.focus = s.preSpawn or pending and inReach
    s.claim = inReach and (due <= cfg.MidRuneLead or pending)
    if not pending then
        s.target = nil
    end
end
local function current(bot)
    local s = stateFor(bot)
    local now = DotaTime()
    if now >= s.checkAt then
        refresh(bot, s, now)
    end
    return s
end
--- For the rune mode: whether only power spots count (a power rune is due within MidRuneFocus or is up),
-- whether it is due rather than up, so a MISSING (not yet spawned) power spot still counts, and after a
-- spawn the one spot to head for (where it was seen, else the nearer spot not yet seen empty).
function ____exports.Focus(bot)
    if not ____exports.IsOn(bot) then
        return false, false, nil
    end
    local s = current(bot)
    local ____s_focus_1 = s.focus
    local ____temp_2 = s.focus and s.preSpawn
    local ____temp_0
    if s.focus and not s.preSpawn then
        ____temp_0 = s.target
    else
        ____temp_0 = nil
    end
    return ____s_focus_1, ____temp_2, ____temp_0
end
function ____exports.Tick(bot)
    if not ____exports.IsOn(bot) then
        return
    end
    local s = current(bot)
    if s.claim then
        Intent.Claim(
            bot,
            {
                source = ____exports.SOURCE,
                tier = "TRANSITION",
                mode = BotMode.Rune,
                floor = Settings.Get().MidRuneFloor
            }
        )
    end
end
--- The rune mode refused this frame (a safety gate, no power target): the floor must not apply.
function ____exports.Yield(bot)
    Intent.Release(bot, ____exports.SOURCE, BotMode.Rune)
end
--- rune_skip telemetry: a mid with little rune desire around a power spawn, at most once per spawn.
function ____exports.NoteSkip(bot, raw, desire, target, status, gate)
    if not Telemetry.IsEnabled() or not ____exports.IsMid(bot) then
        return
    end
    local cfg = Settings.Get()
    if type(desire) ~= "number" or desire >= cfg.MidRuneSkipDesire then
        return
    end
    local now = DotaTime()
    local next = Runes.NextSpawn("power", now)
    local last = lastSpawn(now)
    local spawn
    if next - now <= cfg.MidRuneSkipWindow then
        spawn = next
    elseif last ~= nil and now - last <= cfg.MidRuneSkipWindow then
        spawn = last
    end
    if spawn == nil then
        return
    end
    local s = stateFor(bot)
    if s.skipSpawn == spawn then
        return
    end
    s.skipSpawn = spawn
    Telemetry.Event(
        "rune_skip",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"spawn", spawn},
            {"target", target},
            {"status", status},
            {"raw", raw},
            {"desire", desire},
            {
                "laning",
                Intent.Competing(bot)
            },
            {"gate", gate}
        }
    )
end
return ____exports
