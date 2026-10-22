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
local LaneFightConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_config")
local memory = {}
local function roll(chance)
    return RandomFloat(0, 1) < chance
end
local function rememberChance(cls, skill)
    if cls == "ult" then
        return LaneFightConfig.Curve("RememberUlt", skill)
    end
    if cls == "key" then
        return LaneFightConfig.Curve("RememberKey", skill)
    end
    return LaneFightConfig.Curve("RememberOther", skill)
end
local function store(observerPid, enemyPid, ability, entry)
    if memory[observerPid] == nil then
        memory[observerPid] = {}
    end
    if memory[observerPid][enemyPid] == nil then
        memory[observerPid][enemyPid] = {}
    end
    memory[observerPid][enemyPid][ability] = entry
end
local function find(observerPid, enemyPid, ability)
    local byEnemy = memory[observerPid]
    if byEnemy == nil then
        return nil
    end
    local byAbility = byEnemy[enemyPid]
    local ____temp_0
    if byAbility == nil then
        ____temp_0 = nil
    else
        ____temp_0 = byAbility[ability]
    end
    return ____temp_0
end
function ____exports.Record(observerPid, enemyPid, ability, cls, cooldown, skill, now)
    if not roll(rememberChance(cls, skill)) then
        return false
    end
    local x = LaneFightConfig.Curve("TimingError", skill)
    local estReadyAt = now + cooldown * (1 + RandomFloat(-x, x))
    store(
        observerPid,
        enemyPid,
        ability,
        {
            seenAt = now,
            estReadyAt = estReadyAt,
            cls = cls,
            shared = false,
            forgetAt = estReadyAt + LaneFightConfig.Curve("ForgetWindow", skill)
        }
    )
    return true
end
function ____exports.Share(fromPid, toPids, enemyPid, ability, skill)
    local entry = find(fromPid, enemyPid, ability)
    if entry == nil then
        return
    end
    local loss = LaneFightConfig.Curve("ShareLoss", skill)
    for ____, pid in ipairs(toPids) do
        do
            local __continue15
            repeat
                if pid == fromPid then
                    __continue15 = true
                    break
                end
                local existing = find(pid, enemyPid, ability)
                if existing ~= nil and existing.seenAt >= entry.seenAt then
                    __continue15 = true
                    break
                end
                if roll(loss) then
                    __continue15 = true
                    break
                end
                store(pid, enemyPid, ability, {
                    seenAt = entry.seenAt,
                    estReadyAt = entry.estReadyAt,
                    cls = entry.cls,
                    shared = true,
                    forgetAt = entry.forgetAt
                })
                __continue15 = true
            until true
            if not __continue15 then
                break
            end
        end
    end
end
function ____exports.ProbablyReady(observerPid, enemyPid, ability, learned, now, skill)
    if not learned then
        return false, 1
    end
    local entry = find(observerPid, enemyPid, ability)
    if entry == nil then
        return true, 0
    end
    if now < entry.estReadyAt then
        return false, 1
    end
    local window = LaneFightConfig.Curve("ForgetWindow", skill)
    local confidence = math.max(0, 1 - (now - entry.estReadyAt) / window)
    return true, confidence
end
function ____exports.KeyThreatsDown(observerPid, enemyPid, keyAbilities, now, skill)
    if #keyAbilities == 0 then
        return 0
    end
    local down = 0
    for ____, ability in ipairs(keyAbilities) do
        local ready = ____exports.ProbablyReady(
            observerPid,
            enemyPid,
            ability,
            true,
            now,
            skill
        )
        if not ready then
            down = down + 1
        end
    end
    return down / #keyAbilities
end
function ____exports.Count(observerPid, now)
    local byEnemy = memory[observerPid]
    if byEnemy == nil then
        return 0
    end
    local n = 0
    for ____, byAbility in pairs(byEnemy) do
        for ____, entry in pairs(byAbility) do
            if now < entry.forgetAt then
                n = n + 1
            end
        end
    end
    return n
end
function ____exports.Reset()
    for k in pairs(memory) do
        __TS__Delete(memory, k)
    end
end
return ____exports
