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

local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__ArraySplice(self, ...)
    local args = {...}
    local len = #self
    local actualArgumentCount = __TS__CountVarargs(...)
    local start = args[1]
    local deleteCount = args[2]
    if start < 0 then
        start = len + start
        if start < 0 then
            start = 0
        end
    elseif start > len then
        start = len
    end
    local itemCount = actualArgumentCount - 2
    if itemCount < 0 then
        itemCount = 0
    end
    local actualDeleteCount
    if actualArgumentCount == 0 then
        actualDeleteCount = 0
    elseif actualArgumentCount == 1 then
        actualDeleteCount = len - start
    else
        actualDeleteCount = deleteCount or 0
        if actualDeleteCount < 0 then
            actualDeleteCount = 0
        end
        if actualDeleteCount > len - start then
            actualDeleteCount = len - start
        end
    end
    local out = {}
    for k = 1, actualDeleteCount do
        local from = start + k
        if self[from] ~= nil then
            out[k] = self[from]
        end
    end
    if itemCount < actualDeleteCount then
        for k = start + 1, len - actualDeleteCount do
            local from = k + actualDeleteCount
            local to = k + itemCount
            if self[from] then
                self[to] = self[from]
            else
                self[to] = nil
            end
        end
        for k = len - actualDeleteCount + itemCount + 1, len do
            self[k] = nil
        end
    elseif itemCount > actualDeleteCount then
        for k = len - actualDeleteCount, start + 1, -1 do
            local from = k + actualDeleteCount
            local to = k + itemCount
            if self[from] then
                self[to] = self[from]
            else
                self[to] = nil
            end
        end
    end
    local j = start + 1
    for i = 3, actualArgumentCount do
        self[j] = args[i]
        j = j + 1
    end
    for k = #self, len - actualDeleteCount + itemCount + 1, -1 do
        self[k] = nil
    end
    return out
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local GameState = ____dota.GameState
local DEDUPE_WINDOW = 0.25
local LOG_LIMIT = 50
local subscribers = {}
local subscriberOrder = {}
local DEFERRED_LIMIT = 100
local deferred = {}
function ____exports.Defer(tag, line)
    if #deferred < DEFERRED_LIMIT then
        deferred[#deferred + 1] = {tag, line}
    end
end
function ____exports.FlushDeferred(log)
    while #deferred > 0 do
        local entry = table.remove(deferred, 1)
        log(entry[1], entry[2])
    end
end
local recent = {}
local installed = false
local installedInProgress = false
local function isDuplicate(msg)
    for ____, prev in ipairs(recent) do
        if prev.pid == msg.pid and prev.text == msg.text and msg.time - prev.time < DEDUPE_WINDOW then
            return true
        end
    end
    return false
end
local function onChat(event)
    if event == nil or event.string == nil then
        ____exports.Defer("chat", "recv nil_or_no_string")
        return
    end
    ____exports.Defer(
        "chat",
        (((("recv pid=" .. tostring(event.player_id)) .. " team_only=") .. tostring(event.team_only)) .. " text=") .. tostring(event.string)
    )
    local msg = {
        pid = event.player_id,
        text = event.string,
        teamOnly = event.team_only == true,
        time = GameTime()
    }
    if isDuplicate(msg) then
        ____exports.Defer(
            "chat",
            (("dup pid=" .. tostring(msg.pid)) .. " text=") .. msg.text
        )
        return
    end
    recent[#recent + 1] = msg
    if #recent > LOG_LIMIT then
        table.remove(recent, 1)
    end
    for ____, name in ipairs(subscriberOrder) do
        local handler = subscribers[name]
        local ok, err = pcall(handler, msg)
        if not ok then
            print((("[Humaniser] chat subscriber '" .. name) .. "' failed: ") .. tostring(err))
            ____exports.Defer(
                "chat",
                (("subscriber_failed name=" .. name) .. " err=") .. tostring(err)
            )
        end
    end
end
--- Installs the shared callback for this script context: on first call, and once more when the game reaches in-progress.
-- Safe to call every frame. hero_selection.lua's UpdateLaneAssignments re-installs its own chat callback every frame
-- until the horn; in-game, a hub installed only during pre-game never received a message, consistent with only the
-- latest install being kept. If the engine instead keeps every callback, the duplicate delivery is dropped by isDuplicate.
function ____exports.EnsureInstalled(_bot)
    if not installed then
        installed = true
        installedInProgress = GetGameState() == GameState.GameInProgress
        InstallChatCallback(onChat)
        ____exports.Defer(
            "chat",
            (("installed gt=" .. tostring(GameTime())) .. " state=") .. tostring(GetGameState())
        )
    end
    if not installedInProgress and GetGameState() == GameState.GameInProgress then
        installedInProgress = true
        InstallChatCallback(onChat)
        ____exports.Defer(
            "chat",
            (("reinstalled gt=" .. tostring(GameTime())) .. " state=") .. tostring(GetGameState())
        )
    end
end
--- Registers (or replaces) a named handler. Names keep re-subscription idempotent.
function ____exports.Subscribe(name, handler)
    if subscribers[name] == nil then
        subscriberOrder[#subscriberOrder + 1] = name
    end
    subscribers[name] = handler
end
function ____exports.Unsubscribe(name)
    if subscribers[name] == nil then
        return
    end
    __TS__Delete(subscribers, name)
    local index = __TS__ArrayIndexOf(subscriberOrder, name)
    if index >= 0 then
        __TS__ArraySplice(subscriberOrder, index, 1)
    end
end
function ____exports.IsCommand(text)
    return string.sub(text, 1, 1) == "!"
end
return ____exports
