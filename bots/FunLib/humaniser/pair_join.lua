--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__ObjectEntries(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = {key, obj[key]}
    end
    return result
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

local function __TS__ObjectKeys(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = key
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local UnitType = ____dota.UnitType
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
____exports.SETTINGS = {
    AllyRange = 1200,
    FoeRange = 1000,
    OursRange = 1200,
    HitRecent = 1,
    Window = 3,
    Every = 0.5,
    Until = 720,
    CutEvery = 2
}
--- The side `from`'s best kill share on `on` over the window: the target and the share.
local function best(from, on, dmg)
    local tgt = -1
    local share = 0
    for ____, o in ipairs(on) do
        local d = 0
        for ____, f in ipairs(from) do
            local ____opt_0 = dmg[f.pid]
            d = d + (____opt_0 and ____opt_0[o.pid] or 0)
        end
        local s = d / math.max(o.hp, 1)
        if tgt == -1 or s > share then
            tgt = o.pid
            share = s
        end
    end
    return tgt, share
end
--- The rule: outnumbered stays out; else join when our best kill share beats theirs.
function ____exports.Decide(rec)
    local tgt, ko = best(rec.ours, rec.theirs, rec.dmg)
    local ____, kt = best(rec.theirs, rec.ours, rec.dmg)
    if #rec.theirs > #rec.ours then
        return {dec = "outnumbered", tgt = tgt, ko = ko, kt = kt}
    end
    return {dec = ko > kt and "join" or "losing", tgt = tgt, ko = ko, kt = kt}
end
local function live(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:GetLocation() ~= nil and not u:IsIllusion()
end
local function dist(a, b)
    local p = a:GetLocation()
    local q = b:GetLocation()
    return math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2)
end
local function member(u, ours)
    local l = u:GetLocation()
    local m = {
        pid = u:GetPlayerID(),
        x = math.floor(l.x + 0.5),
        y = math.floor(l.y + 0.5),
        hp = math.floor(u:GetHealth() + 0.5),
        mhp = math.floor(u:GetMaxHealth() + 0.5)
    }
    if ours then
        m.ret = RetreatState.Running(u) and 1 or 0
    end
    return m
end
--- The situation's record, or undefined when no ally within AllyRange was hit by a hero within HitRecent. The hit ally is the one at the lowest HP share.
function ____exports.Gather(bot)
    local ally
    local allies = {}
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue15
            repeat
                if not live(a) then
                    __continue15 = true
                    break
                end
                allies[#allies + 1] = a
                if a == bot or dist(a, bot) > ____exports.SETTINGS.AllyRange or not a:WasRecentlyDamagedByAnyHero(____exports.SETTINGS.HitRecent) then
                    __continue15 = true
                    break
                end
                if ally == nil or a:GetHealth() / a:GetMaxHealth() < ally:GetHealth() / ally:GetMaxHealth() then
                    ally = a
                end
                __continue15 = true
            until true
            if not __continue15 then
                break
            end
        end
    end
    if ally == nil then
        return nil
    end
    local ours = __TS__ArrayFilter(
        allies,
        function(____, a) return dist(a, ally) <= ____exports.SETTINGS.OursRange end
    )
    local theirs = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        if live(e) and e:CanBeSeen() and dist(e, ally) <= ____exports.SETTINGS.FoeRange then
            theirs[#theirs + 1] = e
        end
    end
    if #theirs == 0 then
        return nil
    end
    local dmg = {}
    local function fill(from, on)
        for ____, f in ipairs(from) do
            local row = {}
            for ____, o in ipairs(on) do
                row[o:GetPlayerID()] = math.floor(f:GetEstimatedDamageToTarget(true, o, ____exports.SETTINGS.Window, DamageType.All) + 0.5)
            end
            dmg[f:GetPlayerID()] = row
        end
    end
    fill(ours, theirs)
    fill(theirs, ours)
    return {
        ally = ally:GetPlayerID(),
        ours = __TS__ArrayMap(
            ours,
            function(____, u) return member(u, true) end
        ),
        theirs = __TS__ArrayMap(
            theirs,
            function(____, u) return member(u, false) end
        ),
        dmg = dmg
    }
end
local states = {}
local function members(ms)
    return table.concat(
        __TS__ArrayMap(
            ms,
            function(____, m) return table.concat(
                {
                    m.pid,
                    m.x,
                    m.y,
                    m.hp,
                    m.mhp,
                    unpack(m.ret ~= nil and ({m.ret}) or ({}))
                },
                ","
            ) end
        ),
        ";"
    )
end
local function dmgOf(rec)
    local out = {}
    for ____, side in ipairs({rec.ours, rec.theirs}) do
        for ____, f in ipairs(side) do
            for ____, ____value in ipairs(__TS__ObjectEntries(rec.dmg[f.pid] or ({}))) do
                local to = ____value[1]
                local d = ____value[2]
                out[#out + 1] = (((tostring(f.pid) .. ",") .. to) .. ",") .. tostring(d)
            end
        end
    end
    return table.concat(out, ";")
end
--- Per frame (index Tick): every Every s in the laning stage, the decision and its cut. Reads only.
function ____exports.Tick(bot)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true or not bot:IsAlive() then
        return
    end
    local now = DotaTime()
    if now > ____exports.SETTINGS.Until then
        return
    end
    local pid = bot:GetPlayerID()
    local ____temp_2 = states[pid] or ({})
    states[pid] = ____temp_2
    local st = ____temp_2
    if st.at ~= nil and now - st.at < ____exports.SETTINGS.Every then
        return
    end
    st.at = now
    local rec = ____exports.Gather(bot)
    if rec == nil then
        st.dec = nil
        return
    end
    local a = ____exports.Decide(rec)
    if a.dec == st.dec and now - (st.cutAt or -math.huge) < ____exports.SETTINGS.CutEvery then
        return
    end
    st.dec = a.dec
    st.cutAt = now
    Telemetry.Event(
        "cut",
        {
            {"pid", pid},
            {"kind", "join"},
            {"al", rec.ally},
            {
                "po",
                members(rec.ours)
            },
            {
                "pt",
                members(rec.theirs)
            },
            {
                "dm",
                dmgOf(rec)
            },
            {"dec", a.dec},
            {"tgt", a.tgt},
            {
                "ko",
                math.floor(a.ko * 1000 + 0.5) / 1000
            },
            {
                "kt",
                math.floor(a.kt * 1000 + 0.5) / 1000
            }
        }
    )
end
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(states)) do
        __TS__Delete(states, k)
    end
end
return ____exports
