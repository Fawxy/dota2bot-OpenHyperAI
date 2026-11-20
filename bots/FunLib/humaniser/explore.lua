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
local blocks
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
____exports.SETTINGS = {Mults = {
    0.85,
    1,
    1.2,
    1.45,
    1.75
}, BandHi = 2, Release = 8}
local rolls = {}
local function r2(v)
    return math.floor(v * 100 + 0.5) / 100
end
local function ____end(pid, why, now)
    local x = rolls[pid]
    if x == nil then
        return
    end
    rolls[pid] = nil
    Telemetry.Event(
        "roll",
        {
            {"kind", "safe"},
            {"ph", "end"},
            {"pid", pid},
            {"mult", x.mult},
            {
                "secs",
                r2(now - x.start)
            },
            {"why", why}
        }
    )
end
--- Whether a held roll has run out. A running retreat keeps it alive: the leave read (`Observe`) is not asked during an episode, so without
-- this a roll ended partway through the walk it caused and the hero drew again on its return (smoke: 13 of 45 ends, the high multipliers
-- re-rolling in 4 s against 24 to 39 s).
local function stale(bot, x, now)
    if RetreatState.Running(bot) then
        x.lastInBand = now
        return false
    end
    return now - x.lastInBand >= ____exports.SETTINGS.Release
end
--- Confirmation arm (`Customize.Ours.SafeBarMult`, a number): every hero of the scoped team carries this multiplier on its kill bar all
-- game, with no draw, so the bar the rolls favour can be read at game level. Undefined when unset or on the other team.
function ____exports.Fixed()
    if Customize.Enable == false then
        return nil
    end
    local ____opt_0 = Customize.Ours
    local v = ____opt_0 and ____opt_0.SafeBarMult
    if type(v) ~= "number" then
        return nil
    end
    local team = Ours.ScopedTeam()
    local ____temp_2
    if team ~= nil and GetTeam() ~= team then
        ____temp_2 = nil
    else
        ____temp_2 = v
    end
    return ____temp_2
end
--- A roll is held for `bot` (a drawn 1.0 included).
function ____exports.Held(bot)
    if ____exports.Fixed() ~= nil then
        return true
    end
    return Ours.On("ExploreRoll") and rolls[bot:GetPlayerID()] ~= nil
end
--- The multiplier on `bot`'s kill bar: its held roll, else 1 (switch off, no roll). A roll not refreshed for `Release` s ends here too, for a hero that stopped being read.
function ____exports.Mult(bot)
    local fixed = ____exports.Fixed()
    if fixed ~= nil then
        return fixed
    end
    if not Ours.On("ExploreRoll") then
        return 1
    end
    local pid = bot:GetPlayerID()
    local x = rolls[pid]
    if x == nil then
        return 1
    end
    local now = DotaTime()
    if stale(bot, x, now) then
        ____end(pid, "out", now)
        return 1
    end
    return x.mult
end
--- The hero's own-place read (`leave`) is in the band: someone reaches it and HP / kill is under `BandHi`.
function ____exports.InBand(a)
    return a.reachers > 0 and a.kill > 0 and a.ratio < ____exports.SETTINGS.BandHi
end
--- Watches the hero's own-place answer. Starts a roll on the first in-band read when none is held, refreshes a held one, ends it after
-- `Release` s out of band. Returns true when a roll started on this read: `a` was made unrolled, so the caller asks again.
function ____exports.Observe(bot, a)
    if not Ours.On("ExploreRoll") or not RetreatState.Owns(bot) then
        return false
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local x = rolls[pid]
    if not ____exports.InBand(a) then
        if x ~= nil and stale(bot, x, now) then
            ____end(pid, "out", now)
        end
        return false
    end
    if x ~= nil then
        x.lastInBand = now
        return false
    end
    local n = #____exports.SETTINGS.Mults
    local u = LaneConfig.Draw() or RandomFloat(0, 1)
    local mult = ____exports.SETTINGS.Mults[math.min(
        n - 1,
        math.floor(u * n)
    ) + 1]
    rolls[pid] = {mult = mult, start = now, lastInBand = now}
    local hpa = bot:GetHealth()
    Telemetry.Event(
        "roll",
        {
            {"kind", "safe"},
            {"ph", "start"},
            {"pid", pid},
            {"mult", mult},
            {
                "ratio",
                r2(a.ratio)
            },
            {
                "kill",
                math.floor(a.kill + 0.5)
            },
            {
                "hp",
                r2(hpa / math.max(
                    1,
                    bot:GetMaxHealth()
                ))
            },
            {
                "hpa",
                math.floor(hpa + 0.5)
            },
            {"pressed", a.pressed},
            {"reach", a.reachers},
            {
                "bar",
                r2(a.bar)
            },
            {"base", a.ratio < a.bar}
        }
    )
    return true
end
--- The hero died: its roll ends.
function ____exports.Died(bot)
    ____end(
        bot:GetPlayerID(),
        "died",
        DotaTime()
    )
end
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(rolls)) do
        __TS__Delete(rolls, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(blocks)) do
        __TS__Delete(blocks, k)
    end
end
____exports.TRADE = {
    Aggs = {
        0.7,
        1,
        1.35,
        1.75,
        2.2
    },
    Block = 45,
    NearHeroes = 1200,
    NearCreeps = 1000,
    SeeHeroes = 1600,
    MaxDt = 1
}
local LEVEL_FIELD = {
    none = "sn",
    hit = "sh",
    hitback = "sb",
    kill = "sk",
    join = "sj"
}
--- `none`'s reason as the field its seconds go to: the first gate that failed, or the end that stopped the exchange.
local NONE_FIELD = {
    unfavoured = "rnf",
    no_reach = "rnr",
    deny = "rdn",
    due = "rdu",
    creeps = "rcr",
    wave = "rwv",
    kill = "rus",
    unknown = "rus",
    tower = "rus",
    aggro = "rag",
    no_target = "rnt"
}
local FIELDS = {
    "sn",
    "sh",
    "sb",
    "sk",
    "sj",
    "rnf",
    "rnr",
    "rdn",
    "rdu",
    "rcr",
    "rwv",
    "rus",
    "rag",
    "rnt",
    "rot",
    "ord"
}
--- Ends the held block: logs its tally.
local function endBlock(pid, b)
    local f = {
        {"kind", "trade"},
        {"ph", "end"},
        {"pid", pid},
        {"agg", b.agg},
        {"blk", b.blk}
    }
    local secs = 0
    for ____, k in ipairs({
        "sn",
        "sh",
        "sb",
        "sk",
        "sj"
    }) do
        secs = secs + (b.tally[k] or 0)
    end
    f[#f + 1] = {
        "secs",
        r2(secs)
    }
    for ____, k in ipairs(FIELDS) do
        f[#f + 1] = {
            k,
            k == "ord" and (b.tally[k] or 0) or r2(b.tally[k] or 0)
        }
    end
    Telemetry.Event("roll", f)
end
--- One frame's answer in the hero's block (`Ours.ExploreTrade` on, a block held): its seconds go to the level and, for `none`, to the reason's field.
function ____exports.Tally(bot, level, why, now)
    local b = blocks[bot:GetPlayerID()]
    if b == nil then
        return
    end
    local dt = b.last == nil and 0 or math.min(
        ____exports.TRADE.MaxDt,
        math.max(0, now - b.last)
    )
    b.last = now
    local lf = LEVEL_FIELD[level] or "sn"
    b.tally[lf] = (b.tally[lf] or 0) + dt
    if level == "none" then
        local nf = NONE_FIELD[why] or "rot"
        b.tally[nf] = (b.tally[nf] or 0) + dt
    end
end
--- The hero was ordered to attack an enemy hero by the exchange.
function ____exports.Order(bot)
    local b = blocks[bot:GetPlayerID()]
    if b ~= nil then
        b.tally.ord = (b.tally.ord or 0) + 1
    end
end
blocks = {}
--- The 45 s block index of `now` for a hero whose first laning frame was `first`.
function ____exports.BlockOf(first, now)
    return math.max(
        0,
        math.floor((now - first) / ____exports.TRADE.Block)
    )
end
--- The draw for a uniform `u` in [0, 1).
function ____exports.AggFor(u)
    local n = #____exports.TRADE.Aggs
    return ____exports.TRADE.Aggs[math.min(
        n - 1,
        math.max(
            0,
            math.floor(u * n)
        )
    ) + 1]
end
local function logTrade(bot, b)
    local ned = -1
    local ne = 0
    for ____, h in ipairs(bot:GetNearbyHeroes(____exports.TRADE.SeeHeroes, true, BotMode.None)) do
        do
            local __continue42
            repeat
                if h:IsNull() or not h:IsAlive() then
                    __continue42 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if ned < 0 or d < ned then
                    ned = d
                end
                if d <= ____exports.TRADE.NearHeroes then
                    ne = ne + 1
                end
                __continue42 = true
            until true
            if not __continue42 then
                break
            end
        end
    end
    local mine = #bot:GetNearbyHeroes(____exports.TRADE.NearHeroes, false, BotMode.None)
    Telemetry.Event(
        "roll",
        {
            {"kind", "trade"},
            {"ph", "start"},
            {
                "pid",
                bot:GetPlayerID()
            },
            {"agg", b.agg},
            {"blk", b.blk},
            {
                "hp",
                r2(bot:GetHealth() / math.max(
                    1,
                    bot:GetMaxHealth()
                ))
            },
            {
                "lvl",
                bot:GetLevel()
            },
            {
                "ned",
                math.floor(ned)
            },
            {"ne", ne},
            {
                "ocr",
                #bot:GetNearbyLaneCreeps(____exports.TRADE.NearCreeps, false)
            },
            {
                "ecr",
                #bot:GetNearbyLaneCreeps(____exports.TRADE.NearCreeps, true)
            },
            {"pn", mine > 1 and 1 or 0}
        }
    )
end
--- The hero's aggression on the in-lane exchange (`Ours.ExploreTrade`): undefined with the switch off, else the draw held for the
-- current 45 s block, redrawn on the first call in the next one. Called from `Trade.Gather`, so only a hero in lane draws.
function ____exports.Agg(bot)
    if not Ours.On("ExploreTrade") then
        return nil
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    if now < 0 then
        return nil
    end
    local held = blocks[pid]
    local first = held ~= nil and held.first or now
    local blk = ____exports.BlockOf(first, now)
    if held ~= nil and held.blk == blk then
        return held.agg
    end
    if held ~= nil then
        endBlock(pid, held)
    end
    local b = {
        agg = ____exports.AggFor(LaneConfig.Draw() or RandomFloat(0, 1)),
        blk = blk,
        first = first,
        tally = {}
    }
    blocks[pid] = b
    logTrade(bot, b)
    return b.agg
end
____exports._test = {rolls = rolls, blocks = blocks}
return ____exports
