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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
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

local function __TS__ArrayIncludes(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    local k = fromIndex
    if fromIndex < 0 then
        k = len + fromIndex
    end
    if k < 0 then
        k = 0
    end
    for i = k + 1, len do
        if self[i] == searchElement then
            return true
        end
    end
    return false
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

local function __TS__ArraySome(self, callbackfn, thisArg)
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            return true
        end
    end
    return false
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

local __TS__StringSplit
do
    local sub = string.sub
    local find = string.find
    function __TS__StringSplit(source, separator, limit)
        if limit == nil then
            limit = 4294967295
        end
        if limit == 0 then
            return {}
        end
        local result = {}
        local resultIndex = 1
        if separator == nil or separator == "" then
            for i = 1, #source do
                result[resultIndex] = sub(source, i, i)
                resultIndex = resultIndex + 1
            end
        else
            local currentPos = 1
            while resultIndex <= limit do
                local startPos, endPos = find(source, separator, currentPos, true)
                if not startPos then
                    break
                end
                result[resultIndex] = sub(source, currentPos, startPos - 1)
                resultIndex = resultIndex + 1
                currentPos = endPos + 1
            end
            if resultIndex <= limit then
                result[resultIndex] = sub(source, currentPos)
            end
        end
        return result
    end
end

local function __TS__ArraySlice(self, first, last)
    local len = #self
    first = first or 0
    if first < 0 then
        first = len + first
        if first < 0 then
            first = 0
        end
    else
        if first > len then
            first = len
        end
    end
    last = last or len
    if last < 0 then
        last = len + last
        if last < 0 then
            last = 0
        end
    else
        if last > len then
            last = len
        end
    end
    local out = {}
    first = first + 1
    last = last + 1
    local n = 1
    while first < last do
        out[n] = self[first]
        first = first + 1
        n = n + 1
    end
    return out
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

local function __TS__ArraySort(self, compareFn)
    if compareFn ~= nil then
        table.sort(
            self,
            function(a, b) return compareFn(nil, a, b) < 0 end
        )
    else
        table.sort(self)
    end
    return self
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
-- End of Lua Library inline imports
local ____exports = {}
local overrides, swapped, listed, spotPoint, noteSpot, behindOwnT1, endLinger, lingerPoint, nearbyHero, startLinger, lingerTick, chase, sentryAttack, keyOf, rigOf, rigState, rigActor, rigCastHeld, releasedModes, rigIdle, rawSpot, passableNear, nearestTower, rigPoint, logSpot, heroOf, lastPoint, attackTarget, hpShare, holdsItem, standAt, waitInFountain, atFountain, burstStep, lastHitPlace, swingStep, answerStep, rigStep, rigHold, pastReach, pairFacts, controlRep, Customize, brokeOff, FOUNTAIN, STATUE_BEHIND, STATUE_SWAY, statueSide, lastSpot, SPOT_OFFSET, CHASER_WAIT_BEHIND, LINGER_HP, LINGER_SECS, LINGER_DIST, LINGER_STANDOFF_SLACK, TOWER_REACH_FALLBACK, LINGER_TOWER_MARGIN, lingering, lingered, rig, rigSpots, RIG_IDLE_DESIRE, TOWER_IDS, RIG_SNAP_STEP, RIG_SNAP_RINGS, rigUnits, RIG_PLACED, RIG_APPROACH, RIG_SHOP_REACH, RIG_BUY_SECS, RIG_FULL_HP, RIG_AT, RIG_FROM_SLACK, WAIT_RADIUS, WAIT_STEP, WAIT_AT, waitSlots, RIG_CHANNEL_SECS, RIG_REORDER_SECS, LH_INSIDE, LH_BACK_MIN, SWING_REACH, SWING_HITS, SWING_SECS, ANSWER_HIT, ANSWER_KEEP, ANSWER_LEASH
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local DamageType = ____dota.DamageType
local GameState = ____dota.GameState
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
local Sight = require(GetScriptDirectory().."/FunLib/humaniser/sight")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
function overrides()
    return Customize.Overrides
end
--- The active drill's name, or undefined (no drill, or a name the table does not hold).
function ____exports.Name()
    local ____opt_2 = overrides()
    local n = ____opt_2 and ____opt_2.Drill
    return type(n) == "string" and ____exports.TABLE[n] ~= nil and n or nil
end
--- The active drill's entry, or undefined.
function ____exports.Active()
    local n = ____exports.Name()
    local ____temp_4
    if n == nil then
        ____temp_4 = nil
    else
        ____temp_4 = ____exports.TABLE[n]
    end
    return ____temp_4
end
function swapped()
    local ____opt_5 = ____exports.Active()
    return (____opt_5 and ____opt_5.sided) == true and Ours.ScopedTeam() == Team.Dire
end
function listed(s, team, pos)
    if s == nil or pos == nil then
        return false
    end
    local radiant = team == Team.Radiant ~= swapped()
    local ____radiant_7
    if radiant then
        ____radiant_7 = s.r
    else
        ____radiant_7 = s.d
    end
    local list = ____radiant_7
    return list ~= nil and __TS__ArrayIndexOf(list, pos) >= 0
end
--- The bot's role in the active drill: `play` when no drill is on. A hero whose position is not known yet plays.
function ____exports.RoleOf(bot)
    local d = ____exports.Active()
    if d == nil then
        return "play"
    end
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil then
        return "play"
    end
    if listed(
        d.cast,
        bot:GetTeam(),
        pos
    ) then
        return "cast"
    end
    if rigActor(d, bot) then
        return "actor"
    end
    if listed(
        d.statue,
        bot:GetTeam(),
        pos
    ) then
        return "statue"
    end
    if listed(
        d.sentry,
        bot:GetTeam(),
        pos
    ) then
        return "sentry"
    end
    if listed(
        d.chaser,
        bot:GetTeam(),
        pos
    ) then
        return "chaser"
    end
    if listed(
        d.laneOnly,
        bot:GetTeam(),
        pos
    ) then
        return "laneonly"
    end
    if listed(
        d.inLane,
        bot:GetTeam(),
        pos
    ) then
        return "inlane"
    end
    return d.others
end
--- A statue's spot for the current rep (`lane` before the first rep or without a spot list).
function ____exports.SpotOf(bot)
    local d = ____exports.Active()
    local pos = LaneConfig.PositionOf(bot)
    local ____temp_41
    if pos ~= nil then
        local ____temp_40
        if bot:GetTeam() == Team.Radiant then
            local ____opt_32 = d and d.spots
            ____temp_40 = ____opt_32 and ____opt_32.r
        else
            local ____opt_36 = d and d.spots
            ____temp_40 = ____opt_36 and ____opt_36.d
        end
        ____temp_41 = ____temp_40 and ____temp_40[pos]
    else
        ____temp_41 = nil
    end
    local list = ____temp_41
    local rep = ____exports.RepAt(DotaTime())
    if list == nil or #list == 0 or rep == 0 then
        return "lane"
    end
    return list[(rep - 1) % #list + 1]
end
function spotPoint(bot, spot)
    if spot == "bench" then
        local x, y, z = unpack(FOUNTAIN[bot:GetTeam()])
        return Vector(x, y, z)
    end
    local side, kind, seen = string.match(spot, "^pull:([rd]):(%a+)(:?%a*)$")
    if side == nil or kind ~= "safe" and kind ~= "off" or seen ~= "" and seen ~= ":seen" then
        return nil
    end
    local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
    local team = side == "r" and Team.Radiant or Team.Dire
    local camp = Camps.PullCampsFor(
        team,
        Camps.LaneOfKind(team, kind)
    )[1]
    local ____temp_42
    if camp ~= nil then
        ____temp_42 = Camps.SpawnerByIdx(camp.campIdx)
    else
        ____temp_42 = nil
    end
    local s = ____temp_42
    if s == nil then
        return nil
    end
    local c = Camps.BoxCenter(s)
    local lane = GetLaneFrontLocation(
        team,
        Camps.LaneOfKind(team, kind),
        0
    )
    return Camps.BoxEdgePoint(
        s,
        seen == ":seen" and lane or Vector(2 * c.x - lane.x, 2 * c.y - lane.y, c.z),
        SPOT_OFFSET
    )
end
function noteSpot(bot, spot, at)
    local pid = bot:GetPlayerID()
    local key = (tostring(____exports.RepAt(DotaTime())) .. ":") .. spot
    if lastSpot[pid] == key then
        return
    end
    lastSpot[pid] = key
    Telemetry.Event(
        "drill",
        {
            {"ph", "spot"},
            {
                "name",
                ____exports.Name()
            },
            {"pid", pid},
            {
                "team",
                bot:GetTeam()
            },
            {
                "rep",
                ____exports.RepAt(DotaTime())
            },
            {"spot", spot},
            {
                "x",
                at ~= nil and math.floor(at.x) or nil
            },
            {
                "y",
                at ~= nil and math.floor(at.y) or nil
            }
        }
    )
end
function behindOwnT1(bot)
    local ids = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
    local tw = GetTower(
        bot:GetTeam(),
        ids[bot:GetAssignedLane()]
    )
    if tw == nil or tw == nil or not tw:IsAlive() then
        return nil
    end
    local a = tw:GetLocation()
    local fx, fy = unpack(FOUNTAIN[bot:GetTeam()])
    local len = math.max(
        1,
        math.sqrt((fx - a.x) ^ 2 + (fy - a.y) ^ 2)
    )
    return Vector(a.x + (fx - a.x) * CHASER_WAIT_BEHIND / len, a.y + (fy - a.y) * CHASER_WAIT_BEHIND / len, a.z)
end
function endLinger(bot, res, dnow)
    local pid = bot:GetPlayerID()
    local st = lingering[pid]
    if st == nil then
        return
    end
    __TS__Delete(lingering, pid)
    Telemetry.Event(
        "drill",
        {
            {"ph", "linger_end"},
            {
                "name",
                ____exports.Name()
            },
            {"pid", pid},
            {"tpid", st.tpid},
            {"rep", st.rep},
            {"res", res},
            {
                "secs",
                math.floor((DotaTime() - (st.t0 or st.tgo)) * 10 + 0.5) / 10
            },
            {
                "dmin",
                st.dmin ~= nil and math.floor(st.dmin) or nil
            },
            {
                "dmax",
                math.floor(st.dmax)
            },
            {
                "dend",
                dnow ~= nil and math.floor(dnow) or (st.dlast ~= nil and math.floor(st.dlast) or nil)
            },
            {
                "uns",
                math.floor(st.uns * 10 + 0.5) / 10
            },
            {"clamp", st.clamp}
        }
    )
end
function lingerPoint(bot, target, spot)
    local a = target:GetLocation()
    local len = math.max(
        1,
        math.sqrt((spot.x - a.x) ^ 2 + (spot.y - a.y) ^ 2)
    )
    local p = Vector(a.x + (spot.x - a.x) * LINGER_DIST / len, a.y + (spot.y - a.y) * LINGER_DIST / len, spot.z)
    local ids = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
    local tw = GetTower(
        target:GetTeam(),
        ids[bot:GetAssignedLane()]
    )
    if tw == nil or tw == nil or not tw:IsAlive() then
        return {p, 0}
    end
    local tl = tw:GetLocation()
    local reach = WorldFacts.TowerReach(tw, TOWER_REACH_FALLBACK) + LINGER_TOWER_MARGIN
    local td = math.max(
        1,
        math.sqrt((p.x - tl.x) ^ 2 + (p.y - tl.y) ^ 2)
    )
    if td >= reach then
        return {p, 0}
    end
    p = Vector(tl.x + (p.x - tl.x) * reach / td, tl.y + (p.y - tl.y) * reach / td, p.z)
    return {p, 1}
end
function nearbyHero(bot, pid)
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, BotMode.None) or ({})) do
        if h:IsAlive() and h:GetPlayerID() == pid then
            return h
        end
    end
    return nil
end
function startLinger(bot, target)
    local pid = bot:GetPlayerID()
    local rep = ____exports.RepAt(DotaTime())
    if target:GetLocation() == nil then
        return false
    end
    local share = target:GetHealth() / math.max(
        1,
        target:GetMaxHealth()
    )
    if lingered[pid] == rep or share > LINGER_HP or share < 0 then
        return false
    end
    local d = GetUnitToUnitDistance(bot, target)
    lingered[pid] = rep
    lingering[pid] = {
        rep = rep,
        tgo = DotaTime(),
        tpid = target:GetPlayerID(),
        dmax = d,
        dlast = d,
        clamp = 0,
        uns = 0,
        tlast = DotaTime()
    }
    local d0 = ____exports.Active()
    Telemetry.Event(
        "drill",
        {
            {"ph", "linger_go"},
            {
                "name",
                ____exports.Name()
            },
            {"pid", pid},
            {
                "tpid",
                target:GetPlayerID()
            },
            {"rep", rep},
            {
                "thp",
                math.floor(share * 100 + 0.5) / 100
            },
            {
                "d",
                math.floor(d)
            },
            {"rend", d0 ~= nil and d0.rep.from + rep * d0.rep.every or nil}
        }
    )
    return true
end
function lingerTick(bot, spot)
    local pid = bot:GetPlayerID()
    local st = lingering[pid]
    if st == nil then
        return false
    end
    local now = DotaTime()
    local dt = now - st.tlast
    st.tlast = now
    local target = nearbyHero(bot, st.tpid)
    local seen = target ~= nil and target:GetLocation() ~= nil
    if not seen then
        if not IsHeroAlive(st.tpid) then
            endLinger(bot, "died")
            return false
        end
        st.uns = st.uns + dt
    else
        local dd = GetUnitToUnitDistance(bot, target)
        st.dlast = dd
        st.dmax = math.max(st.dmax, dd)
        if st.t0 == nil and dd >= LINGER_DIST - LINGER_STANDOFF_SLACK then
            st.t0 = now
            local share = target:GetHealth() / math.max(
                1,
                target:GetMaxHealth()
            )
            Telemetry.Event(
                "drill",
                {
                    {"ph", "linger"},
                    {
                        "name",
                        ____exports.Name()
                    },
                    {"pid", pid},
                    {"tpid", st.tpid},
                    {"rep", st.rep},
                    {
                        "thp",
                        share >= 0 and share <= 1 and math.floor(share * 100 + 0.5) / 100 or nil
                    },
                    {
                        "d",
                        math.floor(dd)
                    }
                }
            )
        end
        if st.t0 ~= nil then
            st.dmin = st.dmin ~= nil and math.min(st.dmin, dd) or dd
            if dd <= bot:GetAttackRange() + 100 then
                endLinger(bot, "contact", dd)
                return false
            end
        end
    end
    if st.t0 == nil and now - st.tgo >= LINGER_SECS then
        endLinger(bot, "no_standoff", st.dlast)
        return false
    end
    if st.t0 ~= nil and now - st.t0 >= LINGER_SECS then
        endLinger(bot, "timeout", st.dlast)
        return false
    end
    if seen then
        local p, clamp = unpack(lingerPoint(bot, target, spot))
        if clamp == 1 then
            st.clamp = 1
        end
        st.pt = p
    end
    if st.pt ~= nil and GetUnitToLocationDistance(bot, st.pt) > 50 then
        bot:Action_MoveToLocation(st.pt)
    end
    return true
end
function chase(bot)
    local spot = GetLaneFrontLocation(
        bot:GetTeam(),
        bot:GetAssignedLane(),
        STATUE_BEHIND
    )
    local best
    local bestD = math.huge
    local ____opt_43 = ____exports.Active()
    local castOnly = (____opt_43 and ____opt_43.chaseCast) == true
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, BotMode.None) or ({})) do
        do
            local __continue102
            repeat
                if not h:IsAlive() or h:GetLocation() == nil or GetUnitToLocationDistance(h, spot) > ____exports.CHASE_RANGE then
                    __continue102 = true
                    break
                end
                if castOnly and ____exports.RoleOf(h) ~= "cast" then
                    __continue102 = true
                    break
                end
                local dd = GetUnitToUnitDistance(bot, h)
                if dd < bestD then
                    best = h
                    bestD = dd
                end
                __continue102 = true
            until true
            if not __continue102 then
                break
            end
        end
    end
    local st = lingering[bot:GetPlayerID()]
    if st ~= nil and st.rep ~= ____exports.RepAt(DotaTime()) then
        endLinger(bot, "rep_end")
    end
    local ____opt_45 = ____exports.Active()
    if (____opt_45 and ____opt_45.linger) == true then
        if best ~= nil and lingering[bot:GetPlayerID()] == nil then
            startLinger(bot, best)
        end
        if lingerTick(bot, spot) then
            return true
        end
    end
    local ____opt_47 = ____exports.Active()
    local breakAt = ____opt_47 and ____opt_47.breakAt
    if best ~= nil and breakAt ~= nil and best:GetHealth() / math.max(
        1,
        best:GetMaxHealth()
    ) <= breakAt then
        local rep = ____exports.RepAt(DotaTime())
        brokeOff[bot:GetPlayerID()] = rep
        Telemetry.Event(
            "drill",
            {
                {"ph", "break"},
                {
                    "name",
                    ____exports.Name()
                },
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {
                    "tpid",
                    best:GetPlayerID()
                },
                {"rep", rep},
                {
                    "thp",
                    math.floor(best:GetHealth() / math.max(
                        1,
                        best:GetMaxHealth()
                    ) * 100 + 0.5) / 100
                }
            }
        )
        return false
    end
    if best ~= nil then
        bot:Action_AttackUnit(best, true)
    elseif GetUnitToLocationDistance(bot, spot) > 50 then
        bot:Action_MoveToLocation(spot)
    end
    return true
end
function sentryAttack(bot, spot)
    local step = ____exports.SENTRY_STEP * bot:GetCurrentMovementSpeed()
    if GetUnitToLocationDistance(bot, spot) > step then
        return false
    end
    local reach = bot:GetAttackRange() + bot:GetBoundingRadius() + step
    local best
    local bestD = math.huge
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, BotMode.None) or ({})) do
        do
            local __continue122
            repeat
                if not h:IsAlive() then
                    __continue122 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h) - h:GetBoundingRadius()
                if d <= reach and d < bestD then
                    best = h
                    bestD = d
                end
                __continue122 = true
            until true
            if not __continue122 then
                break
            end
        end
    end
    if best == nil then
        return false
    end
    bot:Action_AttackUnit(best, true)
    return true
end
function keyOf(bot)
    local pos = LaneConfig.PositionOf(bot)
    local ____temp_51
    if pos == nil then
        ____temp_51 = nil
    else
        ____temp_51 = (bot:GetTeam() == Team.Radiant and "r" or "d") .. tostring(pos)
    end
    return ____temp_51
end
function rigOf(d)
    return d and d.rig
end
--- The rep kind for rep `n` (1-based).
function ____exports.RigRepOf(n)
    local r = rigOf(____exports.Active())
    if r == nil or #r.reps == 0 or n <= 0 then
        return nil
    end
    return r.reps[(n - 1) % #r.reps + 1]
end
function rigState()
    local d = ____exports.Active()
    if rigOf(d) == nil then
        return nil
    end
    local n = ____exports.RepAt(DotaTime())
    if n == 0 then
        return nil
    end
    if rig == nil or rig.rep ~= n then
        rig = {
            rep = n,
            start = d.rep.from + (n - 1) * d.rep.every,
            step = {},
            placed = {},
            phase = {},
            bought = {},
            waiting = {},
            idleAt = {},
            hpMet = {},
            mpMet = {},
            atk = {},
            inPlace = {},
            burst = {},
            readyAt = {},
            tracedAt = {},
            swing = {},
            answer = {},
            watchAt = {}
        }
    end
    return rig
end
function rigActor(d, bot)
    local k = keyOf(bot)
    if k == nil or d.rig == nil then
        return false
    end
    return __TS__ArraySome(
        d.rig.reps,
        function(____, r) return r.setup[k] ~= nil end
    )
end
function rigCastHeld(bot)
    local st = rigState()
    if st == nil then
        return rigOf(____exports.Active()) ~= nil
    end
    return st.phase[bot:GetPlayerID()] ~= "released"
end
function releasedModes(bot)
    local d = ____exports.Active()
    local r = rigOf(d)
    local ____temp_56 = r == nil or ____exports.RoleOf(bot) ~= "cast"
    if not ____temp_56 then
        local ____opt_54 = overrides()
        ____temp_56 = (____opt_54 and ____opt_54.DrillHost) == true
    end
    if ____temp_56 then
        return nil
    end
    local st = rigState()
    if st == nil or st.phase[bot:GetPlayerID()] ~= "released" then
        return nil
    end
    local out = {}
    for ____, m in ipairs(r.release.modes) do
        out[m] = true
    end
    return out
end
function rigIdle(bot)
    local m = releasedModes(bot)
    if ____exports.RoleOf(bot) ~= "cast" or m == nil or m.farm == true then
        return false
    end
    local st = rigState()
    if st == nil then
        return false
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local last = st.idleAt[pid]
    if last == nil or now - last[2] > 1 then
        st.idleAt[pid] = {
            bot:GetLocation(),
            now
        }
    else
        last[2] = now
    end
    standAt(bot, st.idleAt[pid][1])
    return true
end
function rawSpot(name)
    local ____opt_62 = rigOf(____exports.Active())
    local s = ____opt_62 and ____opt_62.spots[name]
    if s == nil then
        return nil
    end
    local anchor, dx, dy = unpack(s)
    local side, what = string.match(anchor, "^([rd]):(%w+)$")
    if side == nil then
        return nil
    end
    local team = side == "r" and Team.Radiant or Team.Dire
    if what == "fountain" then
        local x, y, z = unpack(FOUNTAIN[team])
        return Vector(x + dx, y + dy, z)
    end
    local id = TOWER_IDS[what]
    if id == nil then
        return nil
    end
    local tw = GetTower(team, id)
    if tw == nil or tw == nil then
        return nil
    end
    local a = tw:GetLocation()
    return Vector(a.x + dx, a.y + dy, a.z)
end
function passableNear(p)
    if IsLocationPassable(p) then
        return p
    end
    do
        local ring = 1
        while ring <= RIG_SNAP_RINGS do
            local r = ring * RIG_SNAP_STEP
            do
                local k = 0
                while k < 16 do
                    local a = k / 16 * 2 * math.pi
                    local q = Vector(
                        p.x + r * math.cos(a),
                        p.y + r * math.sin(a),
                        p.z
                    )
                    if IsLocationPassable(q) then
                        return q
                    end
                    k = k + 1
                end
            end
            ring = ring + 1
        end
    end
    return nil
end
function nearestTower(team, p)
    local best = math.huge
    for ____, k in ipairs(__TS__ObjectKeys(TOWER_IDS)) do
        do
            local __continue177
            repeat
                local tw = GetTower(team, TOWER_IDS[k])
                if tw == nil or tw == nil or not tw:IsAlive() then
                    __continue177 = true
                    break
                end
                local a = tw:GetLocation()
                best = math.min(
                    best,
                    math.sqrt((a.x - p.x) ^ 2 + (a.y - p.y) ^ 2)
                )
                __continue177 = true
            until true
            if not __continue177 then
                break
            end
        end
    end
    return best
end
function rigPoint(bot, name)
    if name == "fountain" then
        local x, y, z = unpack(FOUNTAIN[bot:GetTeam()])
        return Vector(x, y, z)
    end
    local known = rigSpots[name]
    if known ~= nil then
        local ____temp_64
        if known == false then
            ____temp_64 = nil
        else
            ____temp_64 = known
        end
        return ____temp_64
    end
    local raw = rawSpot(name)
    local ____temp_65
    if raw ~= nil then
        ____temp_65 = passableNear(raw)
    else
        ____temp_65 = nil
    end
    local p = ____temp_65
    rigSpots[name] = p or false
    logSpot(
        name,
        p,
        raw ~= nil and p ~= nil and math.floor(math.sqrt((raw.x - p.x) ^ 2 + (raw.y - p.y) ^ 2)) or nil
    )
    return p
end
function logSpot(name, p, moved)
    Telemetry.Event(
        "drill",
        {
            {"ph", "spot"},
            {
                "name",
                ____exports.Name()
            },
            {"spot", name},
            {
                "x",
                p ~= nil and math.floor(p.x) or nil
            },
            {
                "y",
                p ~= nil and math.floor(p.y) or nil
            },
            {"d", moved},
            {
                "rt",
                p ~= nil and math.floor(nearestTower(Team.Radiant, p)) or nil
            },
            {
                "dt",
                p ~= nil and math.floor(nearestTower(Team.Dire, p)) or nil
            },
            {
                "hl",
                p ~= nil and GetHeightLevel(p) or nil
            }
        }
    )
end
function heroOf(bot, key)
    local side = string.match(key, "^([rd])%d$")
    if side == nil or (side == "r" and Team.Radiant or Team.Dire) ~= bot:GetTeam() then
        return nil
    end
    return rigUnits[key]
end
function lastPoint(st, key, bot)
    local ____opt_66 = ____exports.RigRepOf(st.rep)
    local steps = ____opt_66 and ____opt_66.setup[key]
    if steps == nil or #steps == 0 then
        return nil
    end
    do
        local i = #steps - 1
        while i >= 0 do
            local w = __TS__StringSplit(steps[i + 1], " ")
            if w[1] == "stand" and w[2] ~= nil then
                return rigPoint(bot, w[2])
            end
            i = i - 1
        end
    end
    return rigPoint(
        bot,
        __TS__StringSplit(steps[#steps], " ")[2] or "fountain"
    )
end
function attackTarget(bot, st, key)
    local p = lastPoint(st, key, bot)
    if p == nil then
        return nil
    end
    local own = heroOf(bot, key)
    if own ~= nil then
        return GetUnitToLocationDistance(own, p) <= RIG_PLACED and own or nil
    end
    local best
    local bestD = RIG_PLACED
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue193
            repeat
                if not h:IsAlive() or h:GetLocation() == nil then
                    __continue193 = true
                    break
                end
                local d = GetUnitToLocationDistance(h, p)
                if d <= bestD then
                    best = h
                    bestD = d
                end
                __continue193 = true
            until true
            if not __continue193 then
                break
            end
        end
    end
    return best
end
function hpShare(u)
    return u:GetHealth() / math.max(
        1,
        u:GetMaxHealth()
    )
end
function holdsItem(bot, name)
    local slot = bot:FindItemSlot(name)
    return slot >= 0 and slot <= 8
end
function standAt(bot, p)
    if GetUnitToLocationDistance(bot, p) > RIG_AT then
        bot:Action_MoveToLocation(p)
        return false
    end
    local pid = bot:GetPlayerID()
    local side = statueSide[pid] or 1
    local target = Vector(p.x + side * STATUE_SWAY * 0.5, p.y, p.z)
    if GetUnitToLocationDistance(bot, target) < 15 then
        side = -side
        statueSide[pid] = side
        target = Vector(p.x + side * STATUE_SWAY * 0.5, p.y, p.z)
    end
    bot:Action_MoveToLocation(target)
    return true
end
--- The hero's waiting slot (by position; by player id before its position is known), snapped to passable ground.
function ____exports.WaitSlot(bot)
    local team = bot:GetTeam()
    local n = LaneConfig.PositionOf(bot) or bot:GetPlayerID() % 5 + 1
    local key = (tostring(team) .. ":") .. tostring(n)
    local known = waitSlots[key]
    if known ~= nil then
        return known
    end
    local x, y, z = unpack(FOUNTAIN[team])
    local len = math.sqrt(x * x + y * y)
    local ux = -x / len
    local uy = -y / len
    local a = (n - 3) * WAIT_STEP
    local dx = math.cos(a) * ux - math.sin(a) * uy
    local dy = math.cos(a) * uy + math.sin(a) * ux
    local p = passableNear(Vector(x + WAIT_RADIUS * dx, y + WAIT_RADIUS * dy, z)) or Vector(x, y, z)
    waitSlots[key] = p
    return p
end
function waitInFountain(bot)
    local p = ____exports.WaitSlot(bot)
    if GetUnitToLocationDistance(bot, p) > WAIT_AT then
        bot:Action_MoveToLocation(p)
    end
end
function atFountain(bot)
    local x, y, z = unpack(FOUNTAIN[bot:GetTeam()])
    local f = Vector(x, y, z)
    if GetUnitToLocationDistance(bot, f) <= RIG_SHOP_REACH then
        return true
    end
    bot:Action_MoveToLocation(f)
    return false
end
function burstStep(bot, st, words)
    local pid = bot:GetPlayerID()
    local secs = tonumber(words[4]) or 0
    local spells = __TS__ArraySlice(words, 5)
    local now = DotaTime()
    local b = st.burst[pid]
    if b ~= nil and now - b.start >= secs then
        return true
    end
    local kept = st.atk[pid]
    local target = kept ~= nil and not kept:IsNull() and kept:IsAlive() and kept:CanBeSeen() and kept or attackTarget(bot, st, words[2])
    if target == nil then
        local p = lastPoint(st, words[2], bot)
        if p ~= nil and GetUnitToLocationDistance(bot, p) > RIG_APPROACH then
            bot:Action_MoveToLocation(p)
        end
        return false
    end
    st.atk[pid] = target
    local cur = b or ({start = now, ordered = {}})
    st.burst[pid] = cur
    if bot:IsChanneling() then
        cur.chan = cur.chan or now
        if now - cur.chan < RIG_CHANNEL_SECS then
            return false
        end
    else
        cur.chan = nil
        if bot:IsCastingAbility() then
            return false
        end
    end
    for ____, name in ipairs(spells) do
        do
            local __continue224
            repeat
                local a = bot:GetAbilityByName(name)
                if a == nil or a == nil or a:IsNull() or a:GetLevel() <= 0 or not a:IsFullyCastable() then
                    __continue224 = true
                    break
                end
                local last = cur.ordered[name]
                if last ~= nil and now - last < RIG_REORDER_SECS then
                    return false
                end
                cur.ordered[name] = now
                bot:Action_UseAbilityOnEntity(a, target)
                Telemetry.Event(
                    "drill",
                    {
                        {"ph", "cast"},
                        {
                            "name",
                            ____exports.Name()
                        },
                        {"pid", pid},
                        {"rep", st.rep},
                        {"spell", name},
                        {
                            "lvl",
                            a:GetLevel()
                        },
                        {
                            "s",
                            math.floor((now - cur.start) * 100 + 0.5) / 100
                        },
                        {
                            "mana",
                            math.floor(bot:GetMana())
                        },
                        {
                            "tgt",
                            target:GetPlayerID()
                        }
                    }
                )
                return false
            until true
            if not __continue224 then
                break
            end
        end
    end
    bot:Action_AttackUnit(target, true)
    return false
end
function lastHitPlace(bot)
    local back = math.max(
        LH_BACK_MIN,
        bot:GetAttackRange() - LH_INSIDE
    )
    return GetLaneFrontLocation(
        bot:GetTeam(),
        bot:GetAssignedLane(),
        -back
    )
end
function swingStep(bot, st, place)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local cur = st.swing[pid]
    if cur ~= nil then
        if not cur.c:IsNull() and cur.c:IsAlive() and now - cur.at < SWING_SECS then
            if bot:GetAttackTarget() ~= cur.c then
                bot:Action_AttackUnit(cur.c, true)
            end
            return true
        end
        __TS__Delete(st.swing, pid)
        return false
    end
    local dmg = bot:GetAttackDamage()
    local best
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(1600, true) or ({})) do
        do
            local __continue233
            repeat
                if c:IsNull() or not c:IsAlive() or c:GetLocation() == nil or GetUnitToLocationDistance(c, place) > SWING_REACH then
                    __continue233 = true
                    break
                end
                if c:GetHealth() > SWING_HITS * c:GetActualIncomingDamage(dmg, DamageType.Physical) then
                    __continue233 = true
                    break
                end
                if best == nil or c:GetHealth() < best:GetHealth() then
                    best = c
                end
                __continue233 = true
            until true
            if not __continue233 then
                break
            end
        end
    end
    if best == nil then
        return false
    end
    st.swing[pid] = {c = best, at = now}
    Telemetry.Event(
        "drill",
        {
            {"ph", "swing"},
            {
                "name",
                ____exports.Name()
            },
            {"pid", pid},
            {"rep", st.rep},
            {
                "d",
                math.floor(GetUnitToUnitDistance(bot, best))
            }
        }
    )
    bot:Action_AttackUnit(best, true)
    return true
end
function answerStep(bot, st, place)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local leash = bot:GetAttackRange() + ANSWER_LEASH
    local hitter = __TS__ArrayFind(
        bot:GetNearbyHeroes(1600, true, BotMode.None) or ({}),
        function(____, h) return h:IsAlive() and not h:IsIllusion() and bot:WasRecentlyDamagedByHero(h, ANSWER_HIT) and GetUnitToLocationDistance(h, place) <= leash end
    )
    if hitter ~= nil then
        if st.answer[pid] == nil then
            Telemetry.Event(
                "drill",
                {
                    {"ph", "answer"},
                    {
                        "name",
                        ____exports.Name()
                    },
                    {"pid", pid},
                    {"rep", st.rep},
                    {
                        "tpid",
                        hitter:GetPlayerID()
                    },
                    {
                        "d",
                        math.floor(GetUnitToUnitDistance(bot, hitter))
                    }
                }
            )
        end
        st.answer[pid] = {h = hitter, at = now}
    end
    local a = st.answer[pid]
    if a == nil then
        return false
    end
    local h = a.h
    if now - a.at > ANSWER_KEEP or h:IsNull() or not h:IsAlive() or not h:CanBeSeen() or GetUnitToLocationDistance(h, place) > leash then
        __TS__Delete(st.answer, pid)
        return false
    end
    __TS__Delete(st.swing, pid)
    if bot:GetAttackTarget() ~= h then
        bot:Action_AttackUnit(h, true)
    end
    return true
end
function rigStep(bot, st, step, last)
    local pid = bot:GetPlayerID()
    local words = __TS__StringSplit(step, " ")
    local verb = words[1]
    if verb == "stand" or verb == "leave" then
        local p = rigPoint(bot, words[2] or "fountain")
        if p == nil then
            return false
        end
        local ____temp_71
        if verb == "stand" and words[3] == "until" then
            ____temp_71 = tonumber(words[5])
        else
            ____temp_71 = nil
        end
        local ____until = ____temp_71
        if ____until ~= nil then
            standAt(bot, p)
            return hpShare(bot) <= ____until
        end
        standAt(bot, p)
        st.placed[pid] = last and GetUnitToLocationDistance(bot, p) <= RIG_PLACED
        return false
    end
    if verb == "wait" then
        local own = heroOf(bot, words[2])
        local ____temp_72
        if own ~= nil then
            ____temp_72 = st.placed[own:GetPlayerID()] == true
        else
            ____temp_72 = attackTarget(bot, st, words[2]) ~= nil
        end
        local done = ____temp_72
        if not done then
            bot:Action_MoveToLocation(bot:GetLocation())
        end
        return done
    end
    if verb == "walk" then
        local p = rigPoint(bot, words[2])
        if p == nil then
            return false
        end
        if GetUnitToLocationDistance(bot, p) <= RIG_AT then
            return true
        end
        bot:Action_MoveToLocation(p)
        return false
    end
    if verb == "heal" then
        if hpShare(bot) >= RIG_FULL_HP and bot:GetMana() >= RIG_FULL_HP * bot:GetMaxMana() then
            return true
        end
        atFountain(bot)
        return false
    end
    if verb == "buy" or verb == "sell" then
        if not atFountain(bot) then
            return false
        end
        local b = bot
        local item = words[2]
        if verb == "buy" then
            if holdsItem(bot, item) then
                return true
            end
            local now = DotaTime()
            st.bought[pid] = st.bought[pid] or ({})
            local tried = st.bought[pid][item]
            if tried ~= nil and now - tried[1] >= RIG_BUY_SECS then
                return true
            end
            if tried == nil or now - tried[2] >= 1 then
                st.bought[pid][item] = {tried ~= nil and tried[1] or now, now}
                local res = b:ActionImmediate_PurchaseItem(item)
                Telemetry.Event(
                    "drill",
                    {
                        {"ph", "buy"},
                        {
                            "name",
                            ____exports.Name()
                        },
                        {"pid", pid},
                        {"rep", st.rep},
                        {"step", item},
                        {
                            "res",
                            tostring(res)
                        },
                        {
                            "gold",
                            bot:GetGold()
                        }
                    }
                )
            end
            return false
        end
        do
            local slot = 0
            while slot <= 8 do
                local it = bot:GetItemInSlot(slot)
                if it ~= nil and it ~= nil and it:GetName() == item then
                    b:ActionImmediate_SellItem(it)
                end
                slot = slot + 1
            end
        end
        return true
    end
    if verb == "front" or verb == "lasthit" or verb == "hitback" then
        local p = lastHitPlace(bot)
        if verb == "hitback" and answerStep(bot, st, p) then
            return false
        end
        if verb ~= "front" and swingStep(bot, st, p) then
            return false
        end
        standAt(bot, p)
        st.placed[pid] = last and GetUnitToLocationDistance(bot, p) <= RIG_PLACED
        return false
    end
    if verb == "burst" then
        return burstStep(bot, st, words)
    end
    if verb == "attack" then
        local share = tonumber(words[#words])
        if share == nil then
            return false
        end
        local ____temp_73
        if words[3] == "from" then
            ____temp_73 = tonumber(words[4])
        else
            ____temp_73 = nil
        end
        local from = ____temp_73
        local kept = st.atk[pid]
        local target = kept ~= nil and not kept:IsNull() and kept:IsAlive() and kept:CanBeSeen() and kept or attackTarget(bot, st, words[2])
        if target ~= nil then
            st.atk[pid] = target
        end
        if target ~= nil and hpShare(target) <= share then
            return true
        end
        if target == nil then
            local p = lastPoint(st, words[2], bot)
            if p ~= nil and GetUnitToLocationDistance(bot, p) > RIG_APPROACH then
                bot:Action_MoveToLocation(p)
            else
                bot:Action_MoveToLocation(bot:GetLocation())
            end
            return false
        end
        if from ~= nil and st.inPlace[pid] ~= true then
            local t = target:GetLocation()
            local me = bot:GetLocation()
            local dd = math.max(
                1,
                math.sqrt((me.x - t.x) ^ 2 + (me.y - t.y) ^ 2)
            )
            if math.abs(dd - from) > RIG_FROM_SLACK then
                local goal = passableNear(Vector(t.x + (me.x - t.x) * from / dd, t.y + (me.y - t.y) * from / dd, me.z))
                bot:Action_MoveToLocation(goal or t)
                return false
            end
            st.inPlace[pid] = true
        end
        bot:Action_AttackUnit(target, true)
        return false
    end
    return false
end
function rigHold(bot)
    local st = rigState()
    local k = keyOf(bot)
    if st == nil or k == nil then
        waitInFountain(bot)
        return true
    end
    local rr = ____exports.RigRepOf(st.rep)
    local pid = bot:GetPlayerID()
    local steps = rr and rr.setup[k]
    if steps == nil or #steps == 0 then
        st.placed[pid] = true
        waitInFountain(bot)
        return true
    end
    do
        local guard = 0
        while guard < #steps do
            local i = st.step[pid] or 0
            local last = i >= #steps - 1
            if not rigStep(bot, st, steps[i + 1], last) or last then
                return true
            end
            st.step[pid] = i + 1
            Telemetry.Event(
                "drill",
                {
                    {"ph", "step"},
                    {
                        "name",
                        ____exports.Name()
                    },
                    {"pid", pid},
                    {"rep", st.rep},
                    {"i", i + 1},
                    {"step", steps[i + 1 + 1]}
                }
            )
            guard = guard + 1
        end
    end
    return true
end
function pastReach(bot, h)
    return GetUnitToUnitDistance(bot, h) - (bot:GetAttackRange() + bot:GetBoundingRadius() * 2 + 100)
end
--- RigReady `low` and `foes` (slice trade-reach): whether a live enemy hero in sight at `low[0]` HP share or under stands
-- `low[1]` to `low[2]` past the cast's trade reach, how many live enemy heroes in sight stand within 1,200 of it, and how many
-- other live heroes of its own team do.
function ____exports.LowFacts(bot, low)
    local found = false
    local foes = 0
    local allies = 0
    for ____, h in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue377
            repeat
                if h:GetPlayerID() == bot:GetPlayerID() or not h:IsAlive() or h:GetLocation() == nil or h:IsIllusion() then
                    __continue377 = true
                    break
                end
                if GetUnitToUnitDistance(bot, h) <= 1200 then
                    allies = allies + 1
                end
                __continue377 = true
            until true
            if not __continue377 then
                break
            end
        end
    end
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue381
            repeat
                if not h:IsAlive() or h:GetLocation() == nil or not h:CanBeSeen() or h:IsIllusion() then
                    __continue381 = true
                    break
                end
                if GetUnitToUnitDistance(bot, h) <= 1200 then
                    foes = foes + 1
                end
                if low == nil or hpShare(h) > low[1] then
                    __continue381 = true
                    break
                end
                local p = pastReach(bot, h)
                if p >= low[2] and p <= low[3] then
                    found = true
                end
                __continue381 = true
            until true
            if not __continue381 then
                break
            end
        end
    end
    return found, foes, allies
end
--- An own tower within 1,200 of the bot is attacking an enemy lane creep within `d` of it (RigReady `towerCreep`).
function ____exports.TowerOnCreep(bot, d)
    for ____, tower in ipairs(bot:GetNearbyTowers(1200, false) or ({})) do
        do
            local __continue388
            repeat
                local t = tower:GetAttackTarget()
                if t == nil or t == nil or t:IsNull() or not t:IsAlive() then
                    __continue388 = true
                    break
                end
                if t:GetTeam() == bot:GetTeam() or not t:IsCreep() or t:IsHero() then
                    __continue388 = true
                    break
                end
                if GetUnitToUnitDistance(bot, t) <= d then
                    return true
                end
                __continue388 = true
            until true
            if not __continue388 then
                break
            end
        end
    end
    return false
end
function pairFacts(bot, ally, foe)
    local function live(u)
        return not u:IsNull() and u:IsAlive() and u:GetLocation() ~= nil and not u:IsIllusion()
    end
    local allies = __TS__ArrayFilter(
        GetUnitList(UnitType.AlliedHeroes) or ({}),
        function(____, u) return live(u) end
    )
    local hit
    for ____, a in ipairs(allies) do
        do
            local __continue396
            repeat
                if GetUnitToUnitDistance(a, bot) > ally or not a:WasRecentlyDamagedByAnyHero(1) then
                    __continue396 = true
                    break
                end
                if hit == nil or hpShare(a) < hpShare(hit) then
                    hit = a
                end
                __continue396 = true
            until true
            if not __continue396 then
                break
            end
        end
    end
    if hit == nil then
        return "pairhit"
    end
    local ours = __TS__ArrayFilter(
        allies,
        function(____, a) return GetUnitToUnitDistance(a, hit) <= ally end
    )
    if #ours < 2 then
        return "pairnone"
    end
    local theirs = __TS__ArrayFilter(
        GetUnitList(UnitType.EnemyHeroes) or ({}),
        function(____, e) return live(e) and e:CanBeSeen() and GetUnitToUnitDistance(e, hit) <= foe end
    )
    if #theirs == 0 then
        return "pairhit"
    end
    local function share(from, on)
        local best = 0
        for ____, o in ipairs(on) do
            local d = 0
            for ____, f in ipairs(from) do
                d = d + f:GetEstimatedDamageToTarget(true, o, 3, DamageType.All)
            end
            best = math.max(
                best,
                d / math.max(
                    1,
                    o:GetHealth()
                )
            )
        end
        return best
    end
    return {
        ko = share(ours, theirs),
        kt = share(theirs, ours),
        ours = #ours,
        theirs = #theirs
    }
end
function controlRep(d, n)
    if d.rep.on ~= nil and d.rep.on > 0 then
        return (n - 1) % d.rep.on ~= 0
    end
    return d.rep.control ~= nil and d.rep.control > 0 and n % d.rep.control == 0
end
--- The rep (1-based) that `t` falls in, or 0 before the first.
function ____exports.RepAt(t)
    local d = ____exports.Active()
    if d == nil or t < d.rep.from then
        return 0
    end
    return math.floor((t - d.rep.from) / d.rep.every) + 1
end
Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
local SAFE_CORE = {r = {1}}
local ALL = {r = {
    1,
    2,
    3,
    4,
    5
}, d = {
    1,
    2,
    3,
    4,
    5
}}
--- The sustain rig's tasks (D6, `Ours.Sustain`; master docs/proposals/2026-11-19-sustain-design.md, check 3): each forces one
-- answer's facts on one hero. The recipe sets every hero's HP to 20% at +63 s of each rep (`rig_hp_all`), a hero holding a
-- circlet to 5% (`rig_hp_holding`), one holding branches to 10% mana (`rig_mp_holding`), and every tango to one charge
-- (`rig_charges`), the last three for Radiant heroes only (team 2: the bench buys too): the marker items name the task to the server setters, which cannot read the bot's state. At 25% with no
-- enemy the kill line is the 30% floor (20% leaves a margin for the regen before release: fix1, a home hero at 25% stood at 30% when
-- released and bought instead of going home), so:
-- - `tango` / `salve` / `bottle`: what is in hand clears the line; rule 3 tops up (a tango at a tree, a salve stepped out
--   or used where it stands, the bottle).
-- - `home`: nothing in hand, mana low: rule 2 sends it home at once (`low_both`), retreat walks it, it heals to 80%.
-- - `ship`: nothing in hand, mana full, gold and a free courier: rule 2 buys the cover and waits at the safe spot; our
--   courier delivers it (design step 5, the call games had not proven before the smokes).
-- - `tango_ship`: one tango at 5%: the tango alone falls short, so it is eaten now and a salve shipped with it (`also`).
-- - `bottle_dry` (design step 6, not in the rotation yet): a bottle with no charges (`rig_charges item_bottle 0`); its
--   answer (home for a refill, or hold for a rune) is step 6's to design; add it to SUSTAIN_ROTATION then.
local SUSTAIN_HEALS = {
    "item_tango",
    "item_flask",
    "item_bottle",
    "item_clarity",
    "item_faerie_fire",
    "item_enchanted_mango"
}
local SUSTAIN_MARKS = {"item_branches", "item_circlet"}
local ____array_0 = __TS__SparseArrayNew(unpack(SUSTAIN_HEALS))
__TS__SparseArrayPush(
    ____array_0,
    unpack(SUSTAIN_MARKS)
)
local SUSTAIN_ITEMS = {__TS__SparseArraySpread(____array_0)}
--- No enemy hero this near (none acts: every Dire hero is benched), so the safe-here read's kill is 0.
local SUSTAIN_CLEAR = 1600
--- The tree a tango walks to: within rule 3's idle walk (8 s there and back) with margin. `judgement`.
local SUSTAIN_TREE = 600
local SUSTAIN_TASKS = {
    tango = {buy = {"item_tango"}, ready = {
        hpAtMost = 0.25,
        holds = {"item_tango"},
        charges = {item_tango = {1, 1}},
        clear = SUSTAIN_CLEAR,
        tree = SUSTAIN_TREE
    }},
    salve = {buy = {"item_flask"}, ready = {hpAtMost = 0.25, holds = {"item_flask"}, clear = SUSTAIN_CLEAR}},
    bottle = {buy = {"item_bottle"}, ready = {hpAtMost = 0.25, holds = {"item_bottle"}, charges = {item_bottle = {1, 3}}, clear = SUSTAIN_CLEAR}},
    home = {buy = {"item_branches"}, ready = {hpAtMost = 0.25, mpAtMost = 0.2, holds = {"item_branches"}, clear = SUSTAIN_CLEAR}},
    ship = {buy = {}, ready = {
        hpAtMost = 0.25,
        mpAtLeast = 0.5,
        goldAtLeast = 200,
        courier = true,
        clear = SUSTAIN_CLEAR
    }},
    tango_ship = {buy = {"item_tango", "item_circlet"}, ready = {
        hpAtMost = 0.1,
        mpAtLeast = 0.5,
        holds = {"item_tango", "item_circlet"},
        charges = {item_tango = {1, 1}},
        goldAtLeast = 200,
        courier = true,
        clear = SUSTAIN_CLEAR,
        tree = SUSTAIN_TREE
    }},
    bottle_dry = {buy = {"item_bottle"}, ready = {hpAtMost = 0.25, holds = {"item_bottle"}, charges = {item_bottle = {0, 0}}, clear = SUSTAIN_CLEAR}}
}
--- The tasks the rig rotates through: rep k gives hero r(i+1) task (i + k) mod length (six kinds; a game's five reps meet five of them per hero).
local SUSTAIN_ROTATION = {
    "tango",
    "salve",
    "bottle",
    "home",
    "ship",
    "tango_ship"
}
--- One rep kind per rotation step: each hero sells what the last task left, heals, buys its task's items and stands at its own spot.
local function sustainReps()
    local reps = {}
    do
        local k = 0
        while k < #SUSTAIN_ROTATION do
            local setup = {}
            local readyBy = {}
            local tasks = {}
            do
                local i = 0
                while i < 5 do
                    local key = "r" .. tostring(i + 1)
                    local task = SUSTAIN_ROTATION[(i + k) % #SUSTAIN_ROTATION + 1]
                    local t = SUSTAIN_TASKS[task]
                    local own = t.ready.holds or ({})
                    local ____array_1 = __TS__SparseArrayNew(
                        "heal",
                        unpack(__TS__ArrayMap(
                            SUSTAIN_ITEMS,
                            function(____, it) return "sell " .. it end
                        ))
                    )
                    __TS__SparseArrayPush(
                        ____array_1,
                        unpack(__TS__ArrayMap(
                            t.buy,
                            function(____, it) return "buy " .. it end
                        ))
                    )
                    __TS__SparseArrayPush(
                        ____array_1,
                        "stand s" .. tostring(i + 1)
                    )
                    setup[key] = {__TS__SparseArraySpread(____array_1)}
                    readyBy[key] = __TS__ObjectAssign(
                        {},
                        t.ready,
                        {lacks = __TS__ArrayFilter(
                            SUSTAIN_ITEMS,
                            function(____, it) return __TS__ArrayIndexOf(own, it) < 0 end
                        )}
                    )
                    tasks[key] = task
                    i = i + 1
                end
            end
            reps[#reps + 1] = {
                name = "rot" .. tostring(k + 1),
                setup = setup,
                ready = {},
                readyBy = readyBy,
                tasks = tasks
            }
            k = k + 1
        end
    end
    return reps
end
--- The drill table. Names match dotactl's recipes.json `drills`. A slice whose drill has no entry adds it here (and a
-- recipe when it needs reset steps or a later `--until`).
____exports.TABLE = {
    ["lane-stand"] = {
        note = "rig: Radiant pos2 behind the mid river, the Dire pos2 a statue across it (one hero in reach, not hitting, burst between 0.35 and 1 of the cast's HP at level 6, HP at half or more); then laning, retreat; HP set to 70% before each rep; 30 s reps from 1:00; seed 30",
        cast = {r = {2}},
        others = "bench",
        rep = {every = 30, from = 60},
        rig = {
            half = "execution",
            switch = "Retreat",
            window = 600,
            spots = {home = {"r:mid1", 450, 450}, foe = {"d:mid1", -550, -550}},
            timeout = 15,
            keeps = {"levelup"},
            release = {modes = {"laning", "retreat", "idle"}},
            reps = {{name = "lone", setup = {r2 = {"stand home"}, d2 = {"stand foe"}}, ready = {lone = {1700, 0.35, 1}, hpAtLeast = 0.5}}}
        }
    },
    ["retreat-walk"] = {
        note = "Radiant pos1 walks to a start spot each 60 s rep (Dire bot T1 reach, our lane front, our safe pull camp) and our retreat is forced there; Dire pos3 and pos4 statues in lane; everyone else benched",
        cast = SAFE_CORE,
        statue = {d = {3, 4}},
        others = "bench",
        castSpots = {"tower", "front", "pull:r:safe"},
        rep = {every = 60, from = 30},
        forces = "retreat"
    },
    ["retreat-chase"] = {
        note = "Radiant pos1 lane-only with our retreat live; Dire pos3 chases it within 1,500 of its lane spot on odd reps, waits behind its own T1 on even reps (control); everyone else benched",
        cast = SAFE_CORE,
        chaser = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 60, from = 60, control = 2}
    },
    ["retreat-linger"] = {
        note = "retreat-chase, and once per chase rep the Dire pos3 chaser stands 1,100 off the cast when she is at or under 45% HP, for up to 20 s or until she steps into its attack range; everyone else benched",
        cast = SAFE_CORE,
        chaser = {d = {3}},
        linger = true,
        others = "bench",
        castLaneOnly = true,
        rep = {every = 60, from = 60, control = 2}
    },
    ["retreat-chase2"] = {
        note = "Radiant pos1 lane-only with our retreat live; Dire pos3 and pos4 chase it within 1,500 of their lane spots on odd reps, waits behind its own T1 on even reps (control); everyone else benched",
        cast = SAFE_CORE,
        chaser = {d = {3, 4}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 60, from = 60, control = 2}
    },
    ["retreat-even"] = {
        note = "Radiant pos1 lane-only with our retreat live; Dire pos3 and pos4 chase only it, with their spells and items; Radiant pos5 a sentry beside it (2v2); every 4th rep no chase",
        cast = SAFE_CORE,
        sentry = {r = {5}},
        chaser = {d = {3, 4}},
        chaseCast = true,
        chaserCasts = true,
        others = "bench",
        castLaneOnly = true,
        rep = {every = 60, from = 60, control = 4}
    },
    ["retreat-heal"] = {
        note = "Radiant pos1 lane-only with our retreat live but held in a chase rep until 25% HP, OHA's items on; Dire pos3 chases only it and breaks off at 25%; a salve each rep; every 4th rep no chase",
        cast = SAFE_CORE,
        chaser = {d = {3}},
        chaseCast = true,
        breakAt = 0.25,
        castItems = true,
        others = "bench",
        castLaneOnly = true,
        rep = {every = 90, from = 60, control = 4}
    },
    ["burst-read"] = {
        note = "rig: Radiant pos2 at a side spot off our bot lane at full HP, the Dire pos2 bursts it from about 430 north for 6 s with its unit-target spells and attacks; the read and HP traced; 120 s reps from 0:30; seed 8",
        cast = {r = {2}},
        others = "bench",
        rep = {every = 120, from = 30},
        rig = {
            half = "decision",
            switch = "BurstReady",
            window = 600,
            spots = {side = {"r:bot1", -2750, 700}, foe = {"r:bot1", -2750, 1200}},
            timeout = 100,
            keeps = {"levelup"},
            release = {modes = {"idle"}},
            trace = 12,
            reps = {{name = "burst", setup = {r2 = {"heal", "stand side"}, d2 = {"heal", "walk foe", "burst r2 for 6 using oracle_purifying_flames oracle_fortunes_end zuus_arc_lightning zuus_lightning_bolt", "leave"}}, ready = {near = 1000, hpAtLeast = 0.9}}}
        }
    },
    ["sight-probe"] = {
        note = "rig: Radiant pos1 standing off our bot lane; the Dire pos4 stands 500 north in the lane corridor (open, seen), 800 north-west behind trees (unseen), 700 west up a height step (high, unseen) or 2,200 north, also up a step (far, unseen); the team's sight grid logged at ready; 60 s reps from 0:00; seed 8",
        cast = SAFE_CORE,
        others = "bench",
        rep = {every = 60, from = 0},
        rig = {
            half = "execution",
            switch = "none",
            window = 600,
            spots = {
                side = {"r:bot1", -2750, 700},
                open = {"r:bot1", -2730, 1200},
                trees = {"r:bot1", -3150, 1400},
                high = {"r:bot1", -3350, 700},
                far = {"r:bot1", -2750, 2900}
            },
            timeout = 50,
            release = {modes = {"idle"}},
            grid = {1600, 100},
            reps = {{name = "open", setup = {r1 = {"stand side"}, d4 = {"stand open"}}, ready = {sees = {"d4"}, after = 20}}, {name = "trees", setup = {r1 = {"stand side"}, d4 = {"stand trees"}}, ready = {unseen = {"d4"}, after = 20}}, {name = "far", setup = {r1 = {"stand side"}, d4 = {"stand far"}}, ready = {unseen = {"d4"}, after = 20}}, {name = "high", setup = {r1 = {"stand side"}, d4 = {"stand high"}}, ready = {unseen = {"d4"}, after = 20}}}
        }
    },
    ["retreat-heal-items"] = {
        note = "rig: Radiant pos5 healed and handed a salve or a tango at its fountain, stood west of our bot T1 off the lane and away from camps, hit by the healed Dire pos3 to 25% (60% control); the attacker leaves for its fountain (or stays near); then only our retreat runs for it; four 135 s reps from 1:00, all inside the laning stage",
        cast = {r = {5}},
        others = "bench",
        rep = {every = 135, from = 60},
        rig = {
            half = "decision",
            switch = "Sustain",
            window = 600,
            spots = {cast = {"r:bot1", -2750, 700}, near = {"r:bot1", -2250, 700}},
            timeout = 95,
            keeps = {"levelup"},
            release = {modes = {"retreat", "idle"}},
            reps = {{name = "salve", setup = {r5 = {"heal", "buy item_flask", "stand cast"}, d3 = {"heal", "walk near", "attack r5 until hp 0.2", "leave"}}, ready = {hpAtMost = 0.25, holds = {"item_flask"}, clear = 1600}}, {name = "tango", setup = {r5 = {"heal", "sell item_flask", "buy item_tango", "stand cast"}, d3 = {"heal", "walk near", "attack r5 until hp 0.2", "leave"}}, ready = {hpAtMost = 0.25, holds = {"item_tango"}, lacks = {"item_flask"}, clear = 1600}}, {name = "stays", setup = {r5 = {"heal", "buy item_flask", "stand cast"}, d3 = {"heal", "walk near", "attack r5 until hp 0.2", "stand near"}}, ready = {hpAtMost = 0.25, holds = {"item_flask"}, near = 1200}}, {name = "control", setup = {r5 = {"heal", "buy item_flask", "stand cast"}, d3 = {"heal", "walk near", "attack r5 until hp 0.55", "leave"}}, ready = {hpAtMost = 0.6, holds = {"item_flask"}, clear = 1600}}}
        }
    },
    sustain = {
        note = "rig: the five Radiant heroes, each at its own spot off the lanes, every Dire hero benched; each rep a rotation of six sustain tasks (tango, salve, bottle, home, ship, tango and ship) forced by items bought at the fountain and the recipe's HP, mana and charge setters; then laning, retreat and idle with our sustain's items, purchases and courier; 108 s reps from 1:00",
        cast = {r = {
            1,
            2,
            3,
            4,
            5
        }},
        others = "bench",
        rep = {every = 108, from = 60},
        rig = {
            half = "execution",
            switch = "Sustain",
            window = 600,
            spots = {
                s1 = {"r:bot3", 1350, 1300},
                s2 = {"r:bot3", 2950, 1100},
                s3 = {"r:top3", 1300, 1050},
                s4 = {"r:top3", 2300, 1850},
                s5 = {"r:mid3", 2850, 650}
            },
            timeout = 80,
            release = {modes = {"laning", "retreat", "idle"}, sustain = true},
            idle = 0.05,
            reps = sustainReps()
        }
    },
    ["rune-detour"] = {
        note = "rig: each side's pos5 at a spot by its own jungle bounty before the 4:00 and 8:00 spawns (near, mid, far), everyone else benched; released to farm (the decider) and idle; 120 s reps from 3:30",
        cast = {r = {5}, d = {5}},
        others = "bench",
        rep = {every = 120, from = 210},
        rig = {
            half = "execution",
            switch = "RuneDetour",
            window = 600,
            spots = {
                rnear = {"r:fountain", 7214, 1876},
                rmid = {"r:fountain", 7914, 2176},
                rfar = {"r:fountain", 5814, 2076},
                dnear = {"d:fountain", -7621, -2137},
                dmid = {"d:fountain", -7021, -2587},
                dfar = {"d:fountain", -6171, -1637}
            },
            timeout = 60,
            release = {modes = {"farm", "idle"}},
            reps = {{name = "a", setup = {r5 = {"stand rnear"}, d5 = {"stand dmid"}}, ready = {bounty = true}}, {name = "b", setup = {r5 = {"stand rmid"}, d5 = {"stand dfar"}}, ready = {bounty = true}}, {name = "c", setup = {r5 = {"stand rfar"}, d5 = {"stand dnear"}}, ready = {bounty = true}}}
        }
    },
    ["ladder-solo"] = {
        note = "lane ladder rungs 1-3: our pos 1-3 in-lane, one per lane, everyone else benched",
        cast = {r = {1, 2, 3}},
        others = "bench",
        castInLane = true,
        sided = true,
        rep = {every = 30, from = 0}
    },
    ["ladder-support"] = {
        note = "lane ladder rung 4: our pos 4 and 5 in-lane, alone in their side lanes, everyone else benched",
        cast = {r = {4, 5}},
        others = "bench",
        castInLane = true,
        sided = true,
        rep = {every = 30, from = 0}
    },
    ["ladder-duel"] = {
        note = "lane ladder rung 5: pos 1-3 of both sides in-lane, one against one per lane, everyone else benched",
        cast = {r = {1, 2, 3}, d = {1, 2, 3}},
        others = "bench",
        castInLane = true,
        rep = {every = 30, from = 0}
    },
    ["lane-only"] = {
        note = "every hero lane-only (the last-hit harness)",
        cast = ALL,
        others = "play",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    stack = {
        note = "Radiant pos5 alone, a stack attempt every third minute from 2:00",
        cast = {r = {5}},
        others = "bench",
        rep = {every = 180, from = 120},
        forces = "stack",
        overrides = {StackFar = true}
    },
    ["stack-sweep"] = {
        note = "Radiant pos5 alone, an attempt every minute from 2:00 on the nearest own-side camp not tried yet",
        cast = {r = {5}},
        others = "bench",
        rep = {every = 60, from = 120},
        forces = "stack",
        overrides = {StackFar = true, Sweep = true}
    },
    pull = {
        note = "Radiant pos5 pulls each minute's wave, a statue otherwise; the :30 wave unpulled (control); everyone else benched",
        cast = {r = {5}},
        others = "bench",
        castIdle = "statue",
        rep = {every = 30, from = 60, control = 2},
        forces = "pull"
    },
    ["pull-long"] = {
        note = "both pos5s pull every other minute's wave in their safe lanes (1:00, 3:00 ...), statues otherwise; the other waves unpulled; everyone else benched",
        cast = {r = {5}, d = {5}},
        others = "bench",
        castIdle = "statue",
        rep = {every = 30, from = 60, on = 4},
        forces = "pull"
    },
    ["pull-off"] = {
        note = "both pos4s pull every other minute's wave in their off lanes (1:00, 3:00 ...), statues otherwise; the other waves unpulled; everyone else benched",
        cast = {r = {4}, d = {4}},
        others = "bench",
        castIdle = "statue",
        rep = {every = 30, from = 60, on = 4},
        forces = "pull"
    },
    ["pull-stack"] = {
        note = "both pos5s pull every third minute's wave in their safe lanes (1:00, 4:00 ...), statues otherwise; the other waves unpulled; everyone else benched",
        cast = {r = {5}, d = {5}},
        others = "bench",
        castIdle = "statue",
        rep = {every = 30, from = 60, on = 6},
        forces = "pull"
    },
    ["pull-stack-verb"] = {
        note = "both pos5s stack their safe lane's pull camp the minute before each pulled wave (3:5x, 6:5x ...) and pull every third minute's wave (1:00, 4:00 ...), statues otherwise; everyone else benched",
        cast = {r = {5}, d = {5}},
        others = "bench",
        castIdle = "statue",
        rep = {every = 30, from = 60, on = 6},
        forces = "pull",
        also = {"stack"},
        stackMinutes = {3, 6, 9, 12}
    },
    ["pull-stack-row"] = {
        note = "both pos5s play their safe lane with the stack and pull rows; both pos1s and the enemy pos3s play those lanes in-lane; everyone else benched",
        cast = {r = {5}, d = {5}},
        inLane = {r = {1, 3}, d = {1, 3}},
        others = "bench",
        rep = {every = 60, from = 60}
    },
    ["pull-statue"] = {
        note = "Radiant pos5 pulls each minute's wave, a statue otherwise; Dire pos3 and pos4 statues in the lane; the :30 wave unpulled",
        cast = {r = {5}},
        statue = {d = {3, 4}},
        others = "bench",
        castIdle = "statue",
        rep = {every = 30, from = 60, control = 2},
        forces = "pull"
    },
    ["threat-support"] = {
        note = "Radiant pos5 plays its lane and pulls every wave; Dire pos3 a statue on the lane side of the pos5's pull camp on odd reps, benched on even; everyone else benched",
        cast = {r = {5}},
        statue = {d = {3}},
        spots = {d = {[3] = {"pull:r:safe:seen", "bench"}}},
        others = "bench",
        rep = {every = 120, from = 30},
        forces = "pull"
    }
}
--- Benched, a statue, a sentry or a chaser: the hero holds farm mode above every other mode, takes the drill's step and never casts.
function ____exports.Held(bot)
    local r = ____exports.RoleOf(bot)
    return r == "bench" or r == "statue" or r == "sentry" or r == "chaser" or r == "actor" or r == "cast" and rigCastHeld(bot)
end
--- A chaser of an entry with `chaserCasts`, in a chase rep: OHA's spells and items stay on for it although it is held.
function ____exports.Casts(bot)
    local d = ____exports.Active()
    local rep = ____exports.RepAt(DotaTime())
    return d ~= nil and d.chaserCasts == true and ____exports.RoleOf(bot) == "chaser" and rep > 0 and not controlRep(d, rep)
end
--- The cast of an entry with `castItems`: OHA's item use stays on for it although it is lane-only.
function ____exports.CastItems(bot)
    local ____opt_8 = ____exports.Active()
    return (____opt_8 and ____opt_8.castItems) == true and ____exports.RoleOf(bot) == "cast"
end
--- The rep in which each cast first stood at or under `breakAt` HP (once reached, its retreat is free for the rest of the rep).
local reachedBreak = {}
--- The cast of an entry with `breakAt`, in a chase rep, above that HP share and not yet under it this rep: its retreat starts
-- nothing. `hp` is the cast's HP share (the caller's read).
function ____exports.RetreatHeld(bot, hp)
    local d = ____exports.Active()
    if d == nil or d.breakAt == nil or ____exports.RoleOf(bot) ~= "cast" then
        return false
    end
    local rep = ____exports.RepAt(DotaTime())
    if rep == 0 or controlRep(d, rep) then
        return false
    end
    local pid = bot:GetPlayerID()
    if reachedBreak[pid] == rep then
        return false
    end
    if hp > d.breakAt then
        return true
    end
    reachedBreak[pid] = rep
    Telemetry.Event(
        "drill",
        {
            {"ph", "break"},
            {
                "name",
                ____exports.Name()
            },
            {"pid", pid},
            {"rep", rep},
            {
                "thp",
                math.floor(hp * 100 + 0.5) / 100
            }
        }
    )
    return false
end
brokeOff = {}
--- Lane-only: the cast of an entry with `castLaneOnly`, or another hero under `others: "laneonly"`.
function ____exports.LaneOnly(bot)
    local r = ____exports.RoleOf(bot)
    local d = ____exports.Active()
    return d ~= nil and (r == "cast" and d.castLaneOnly == true or r == "laneonly")
end
--- In-lane: the cast of an entry with `castInLane`, or a hero listed in `inLane` or under `others: "inlane"`.
function ____exports.InLane(bot)
    local r = ____exports.RoleOf(bot)
    local ____temp_13 = r == "inlane"
    if not ____temp_13 then
        local ____temp_12 = r == "cast"
        if ____temp_12 then
            local ____opt_10 = ____exports.Active()
            ____temp_12 = (____opt_10 and ____opt_10.castInLane) == true
        end
        ____temp_13 = ____temp_12
    end
    return ____temp_13
end
--- Modes an in-lane hero may not take (Chooser.Gate's name): each takes a laner out of its lane or across the map (a rune
-- walk, a shop trip, a ward walk, Roshan, the team's gather). Push and defend of another lane are held too; of its own
-- lane they run (the wave is the hero's job). `roam` and `team_roam` run: in this fork they carry in-lane play (team
-- roam's last hits, lane fights and help within 2,200; roam's salve guard, tango and hero specials); roam's gank of
-- another lane is held at its choice (mode_roam_generic CheckLaneToGank asks `InLane`). `judgement`: the ladder's list
-- (proposal section 3, "Blocked across lanes"); the isolation view reads what still leaves.
local OUT_OF_LANE = {
    rune = true,
    assemble = true,
    assemble_with_humans = true,
    roshan = true,
    outpost = true,
    secret_shop = true,
    side_shop = true,
    ward = true
}
local LANE_SUFFIX = {top = Lane.Top, mid = Lane.Mid, bot = Lane.Bot}
--- Whether an in-lane hero's desire for `mode` (Chooser.Gate's name) is held at 0.
function ____exports.InLaneDenies(bot, mode)
    if ____exports.Active() == nil or not ____exports.InLane(bot) then
        return false
    end
    if OUT_OF_LANE[mode] == true then
        return true
    end
    local kind, suffix = string.match(mode, "^(%a+)_tower_(%a+)$")
    if kind ~= "push" and kind ~= "defend" then
        return false
    end
    local lane = LANE_SUFFIX[suffix]
    return lane ~= nil and lane ~= bot:GetAssignedLane()
end
--- Items an in-lane hero never uses: a teleport leaves the lane. API item names.
local TELEPORTS = {item_tpscroll = true, item_travel_boots = true, item_travel_boots_2 = true}
--- Whether an in-lane hero's item use (OHA's ConsiderItemDesire loop) skips `item`.
function ____exports.ForbidsItem(bot, item)
    return TELEPORTS[item] == true and ____exports.Active() ~= nil and ____exports.InLane(bot)
end
--- Spells that reach other lanes, which no placement isolates; the drill forbids the cast and keeps the hero (user,
-- 19/11/2026). Ability names (API); the lineups' only global is Zeus's (lineup A). A hero with another global adds it here.
local GLOBAL_SPELLS = {zuus_thundergods_wrath = true}
--- Whether an in-lane hero's cast of `ability` is refused at its desire (a hero file's hook: hero_zuus ConsiderR).
function ____exports.ForbidsCast(bot, ability)
    return GLOBAL_SPELLS[ability] == true and ____exports.Active() ~= nil and ____exports.InLane(bot)
end
--- The backstop for a global spell no hero file's hook refuses: an in-lane hero in its cast point has its order cleared
-- (each frame, from Tick) and logs `ph=forbid` at most once per 5 s (an episode, not a cast). A hero file that re-queues
-- the spell every frame would loop here: a `forbid` line means that hero needs its own `ForbidsCast` hook.
local forbidLogged = {}
local function forbidCast(bot)
    if not ____exports.InLane(bot) then
        return
    end
    local a = bot:GetCurrentActiveAbility()
    if a == nil or GLOBAL_SPELLS[a:GetName()] ~= true then
        return
    end
    bot:Action_ClearActions(true)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    if forbidLogged[pid] ~= nil and now - forbidLogged[pid] < 5 then
        return
    end
    forbidLogged[pid] = now
    Telemetry.Event(
        "drill",
        {
            {"ph", "forbid"},
            {
                "name",
                ____exports.Name()
            },
            {"pid", pid},
            {
                "ability",
                a:GetName()
            }
        }
    )
end
--- An Overrides key the active drill implies, or undefined.
function ____exports.Implied(key)
    local ____opt_16 = ____exports.Active()
    local ____opt_14 = ____opt_16 and ____opt_16.overrides
    return ____opt_14 and ____opt_14[key]
end
FOUNTAIN = {[Team.Radiant] = {-6619, -6336, 384}, [Team.Dire] = {6624, 6368, 392}}
STATUE_BEHIND = -300
STATUE_SWAY = 40
statueSide = {}
lastSpot = {}
SPOT_OFFSET = 250
--- A sentry answers an enemy hero within its attack range + both bounding radii + this many seconds of its own movement, and
-- never leaves its spot by more than that movement: a laner stepping in to hit someone who walked into it. The same 0.5 s
-- as the contest price's STEP_IN on purpose: this step grades the price's damage and time terms on its own zone; a sentry
-- that chases further is a later step. `judgement`.
____exports.SENTRY_STEP = 0.5
--- A chaser follows an enemy hero up to this far from its lane spot (slice retreat's chase drill). `judgement`.
____exports.CHASE_RANGE = 1500
--- The `tower` cast spot stands this far from the enemy T1 toward our own T1 of the lane: inside its reach (868). `judgement`.
local TOWER_SPOT = 500
--- A cast with `castIdle: "statue"`: it stands as a statue while its forced job does not run (the chooser asks the job
-- first and gives this hero the statue's step only when the job neither runs nor starts).
function ____exports.IdleStatue(bot)
    local ____opt_18 = ____exports.Active()
    return (____opt_18 and ____opt_18.castIdle) == "statue" and ____exports.RoleOf(bot) == "cast"
end
--- The one chooser job a cast may run (the forced context, for an entry with `castIdle`), or undefined: every job.
function ____exports.ForcedJob(bot)
    local d = ____exports.Active()
    local ____temp_20
    if d ~= nil and d.castIdle ~= nil and ____exports.RoleOf(bot) == "cast" then
        ____temp_20 = d.forces
    else
        ____temp_20 = nil
    end
    return ____temp_20
end
--- Whether a cast restricted to its forced job (`ForcedJob`) may run the chooser job `name` too.
function ____exports.AllowsJob(bot, name)
    local only = ____exports.ForcedJob(bot)
    local ____temp_23 = only == nil or only == name
    if not ____temp_23 then
        local ____opt_21 = ____exports.Active()
        ____temp_23 = __TS__ArrayIncludes(____opt_21 and ____opt_21.also or ({}), name)
    end
    return ____temp_23
end
--- For a context the drill forces: whether the rep that `t` falls in carries the input (`on`), withholds it (`off`, a
-- control rep) or is before the first rep (`none`); undefined when the drill does not force `context`. A pull reads it at
-- its pulled wave's spawn second.
function ____exports.ForcedAt(context, t)
    local d = ____exports.Active()
    if d == nil or d.forces ~= context then
        return nil
    end
    local n = ____exports.RepAt(t)
    if n == 0 then
        return "none"
    end
    return controlRep(d, n) and "off" or "on"
end
--- The held hero's step: a benched hero walks to its fountain and waits; a statue (or an idle-statue cast) walks to its lane
-- spot behind its own creeps and sways there. False when the hero is not held.
function ____exports.Hold(bot)
    local r = ____exports.RoleOf(bot)
    local d = ____exports.Active()
    if (d and d.rig) ~= nil and (r == "actor" or r == "cast") then
        local ____Held_result_26
        if ____exports.Held(bot) then
            ____Held_result_26 = rigHold(bot)
        else
            ____Held_result_26 = rigIdle(bot)
        end
        return ____Held_result_26
    end
    if r == "chaser" and d ~= nil and not controlRep(
        d,
        ____exports.RepAt(DotaTime())
    ) and ____exports.RepAt(DotaTime()) > 0 and brokeOff[bot:GetPlayerID()] ~= ____exports.RepAt(DotaTime()) then
        if chase(bot) then
            return true
        end
    end
    if r == "chaser" and lingering[bot:GetPlayerID()] ~= nil and lingerTick(
        bot,
        GetLaneFrontLocation(
            bot:GetTeam(),
            bot:GetAssignedLane(),
            STATUE_BEHIND
        )
    ) then
        return true
    end
    if r == "chaser" then
        local at = behindOwnT1(bot)
        if at ~= nil then
            if GetUnitToLocationDistance(bot, at) > 100 then
                bot:Action_MoveToLocation(at)
            end
            return true
        end
    end
    if r == "bench" or r == "chaser" then
        waitInFountain(bot)
        return true
    end
    if r ~= "statue" and r ~= "sentry" and not ____exports.IdleStatue(bot) then
        return false
    end
    local named = r == "statue" and ____exports.SpotOf(bot) or "lane"
    if named ~= "lane" then
        local at = spotPoint(bot, named)
        noteSpot(bot, named, at)
        if at ~= nil and GetUnitToLocationDistance(bot, at) > 50 then
            bot:Action_MoveToLocation(at)
        end
        return true
    end
    local ____temp_29 = r == "statue"
    if ____temp_29 then
        local ____opt_27 = ____exports.Active()
        ____temp_29 = (____opt_27 and ____opt_27.spots) ~= nil
    end
    if ____temp_29 then
        noteSpot(bot, named, nil)
    end
    local lane = bot:GetAssignedLane()
    local spot = GetLaneFrontLocation(
        bot:GetTeam(),
        lane,
        STATUE_BEHIND
    )
    if r == "sentry" and sentryAttack(bot, spot) then
        return true
    end
    local pid = bot:GetPlayerID()
    local side = statueSide[pid] or 1
    local target = Vector(spot.x + side * STATUE_SWAY * 0.5, spot.y, spot.z)
    if GetUnitToLocationDistance(bot, target) < 15 then
        side = -side
        statueSide[pid] = side
        target = Vector(spot.x + side * STATUE_SWAY * 0.5, spot.y, spot.z)
    end
    bot:Action_MoveToLocation(target)
    return true
end
CHASER_WAIT_BEHIND = 350
LINGER_HP = 0.45
LINGER_SECS = 20
LINGER_DIST = 1100
LINGER_STANDOFF_SLACK = 100
TOWER_REACH_FALLBACK = 868
LINGER_TOWER_MARGIN = 100
lingering = {}
lingered = {}
--- The cast's start spot for rep `rep` (`castSpots`), or undefined when the entry has none.
function ____exports.CastSpot(rep)
    local ____opt_49 = ____exports.Active()
    local list = ____opt_49 and ____opt_49.castSpots
    if list == nil or #list == 0 or rep <= 0 then
        return nil
    end
    return list[(rep - 1) % #list + 1]
end
--- The point a cast spot names for `bot`, or undefined.
function ____exports.CastSpotPoint(bot, spot)
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    if spot == "front" then
        return GetLaneFrontLocation(team, lane, 0)
    end
    if spot == "tower" then
        local ids = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
        local enemy = team == Team.Radiant and Team.Dire or Team.Radiant
        local theirs = GetTower(enemy, ids[lane])
        local ours = GetTower(team, ids[lane])
        if theirs == nil or theirs == nil then
            return nil
        end
        local a = theirs:GetLocation()
        local b = ours ~= nil and ours ~= nil and ours:GetLocation() or GetLaneFrontLocation(team, lane, 0)
        local len = math.max(
            1,
            math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
        )
        return Vector(a.x + (b.x - a.x) * TOWER_SPOT / len, a.y + (b.y - a.y) * TOWER_SPOT / len, a.z)
    end
    return spotPoint(bot, spot)
end
rigSpots = {}
--- A rig owns its heroes (user 12/11/2026, rigA2: OHA spent the cast's 600 gold before each rep, so the salve buy failed):
-- true when OHA's code for `what` must not run for this hero. A rig's actors always; its cast until ready, and after ready
-- for every kind its release does not list (host-on frees only items and abilities: OHA's purchases would spend the gold the
-- next rep's `buy` needs). A kind the rig `keeps` is never owned. False for every other hero, in every other drill, and with no drill. Modes are
-- held through `RigDesire` (Chooser.Decide) instead.
function ____exports.Owns(bot, what)
    local r = rigOf(____exports.Active())
    if r == nil then
        return false
    end
    if r.keeps ~= nil and __TS__ArrayIndexOf(r.keeps, what) >= 0 then
        return false
    end
    local role = ____exports.RoleOf(bot)
    if role == "actor" then
        return true
    end
    if role ~= "cast" then
        return false
    end
    if rigCastHeld(bot) then
        return true
    end
    local ____opt_57 = overrides()
    local host = (____opt_57 and ____opt_57.DrillHost) == true
    if what == "items" and r.release.sustain == true and not Ours.On("Sustain") then
        return false
    end
    if what == "items" then
        return not host and r.release.items ~= true
    end
    if what == "abilities" then
        return not host and r.release.abilities ~= true
    end
    return r.release.also == nil or __TS__ArrayIndexOf(r.release.also, what) < 0
end
--- A released rig cast whose release names `sustain`, with the switch on: our sustain may use its heal and mana items, buy and
-- send its courier, which the rig otherwise owns (`Owns`). False for anyone else, in setup, and with the switch off.
function ____exports.RigFreesSustain(bot)
    local r = rigOf(____exports.Active())
    if r == nil or r.release.sustain ~= true or not Ours.On("Sustain") or ____exports.RoleOf(bot) ~= "cast" then
        return false
    end
    return not rigCastHeld(bot)
end
--- Chooser.Decide: a rig cast after release gets desire 0 for every mode its release does not list.
function ____exports.RigDesire(bot, mode)
    local m = releasedModes(bot)
    if m == nil or m[mode] == true then
        return nil
    end
    local ____temp_61
    if mode == "farm" and m.idle == true then
        local ____opt_59 = rigOf(____exports.Active())
        ____temp_61 = ____opt_59 and ____opt_59.idle or RIG_IDLE_DESIRE
    else
        ____temp_61 = 0
    end
    return ____temp_61
end
--- A released cast's desire for `idle` (farm mode, standing where it was released). Over the Valve built-in mode that took a
-- released cast nothing else wanted (fix6, 12/11/2026: mode 28 at 0.475, which no mode file gates), under the 0.95 at which
-- our retreat and the arbiter's hosts hold. `judgement`.
RIG_IDLE_DESIRE = 0.5
--- Chooser.HoldsCasts: for a rig cast after release, whether OHA's item use (`items`) or ability use waits; undefined when
-- the rig does not decide (not a rig cast, not released, or host on).
function ____exports.RigHoldsCasts(bot, items)
    local r = rigOf(____exports.Active())
    if r == nil or releasedModes(bot) == nil then
        return nil
    end
    return ____exports.Owns(bot, items and "items" or "abilities")
end
TOWER_IDS = {
    top1 = Tower.Top1,
    mid1 = Tower.Mid1,
    bot1 = Tower.Bot1,
    top2 = Tower.Top2,
    mid2 = Tower.Mid2,
    bot2 = Tower.Bot2,
    top3 = Tower.Top3,
    mid3 = Tower.Mid3,
    bot3 = Tower.Bot3
}
RIG_SNAP_STEP = 50
RIG_SNAP_RINGS = 20
rigUnits = {}
RIG_PLACED = 200
RIG_APPROACH = 400
RIG_SHOP_REACH = 400
RIG_BUY_SECS = 10
RIG_FULL_HP = 0.95
RIG_AT = 100
RIG_FROM_SLACK = 50
local function mpShare(u)
    return u:GetMana() / math.max(
        1,
        u:GetMaxMana()
    )
end
--- The charges of the hero's first `name` in slots 0-8; undefined when it holds none.
local function chargesOf(bot, name)
    do
        local slot = 0
        while slot <= 8 do
            local it = bot:GetItemInSlot(slot)
            if it ~= nil and it ~= nil and it:GetName() == name then
                return it:GetCurrentCharges() or 0
            end
            slot = slot + 1
        end
    end
    return nil
end
--- The hero's own courier alive and free: idle or at base (sustain_gather's courier read).
local function courierFree(bot)
    do
        local n = 0
        while n <= 4 do
            do
                local __continue204
                repeat
                    local c = GetCourier(n)
                    if c == nil or c == nil or c:GetPlayerID() ~= bot:GetPlayerID() then
                        __continue204 = true
                        break
                    end
                    local s = GetCourierState(c)
                    return s == COURIER_STATE_IDLE or s == COURIER_STATE_AT_BASE
                until true
                if not __continue204 then
                    break
                end
            end
            n = n + 1
        end
    end
    return false
end
--- The ready checks for this cast hero: its own (`readyBy`), else the rep's.
local function readyOf(bot, rr)
    local k = keyOf(bot)
    local ____temp_70
    if k ~= nil then
        local ____opt_68 = rr.readyBy
        ____temp_70 = ____opt_68 and ____opt_68[k]
    else
        ____temp_70 = nil
    end
    return ____temp_70 or rr.ready
end
WAIT_RADIUS = 350
WAIT_STEP = 0.6
WAIT_AT = 50
waitSlots = {}
RIG_CHANNEL_SECS = 0.3
RIG_REORDER_SECS = 0.5
LH_INSIDE = 50
LH_BACK_MIN = 100
SWING_REACH = 800
SWING_HITS = 2
SWING_SECS = 3
ANSWER_HIT = 0.5
ANSWER_KEEP = 2
ANSWER_LEASH = 400
--- Enemy heroes that damaged the cast within the last second.
local function hitters(bot)
    return __TS__ArrayFilter(
        GetUnitList(UnitType.EnemyHeroes) or ({}),
        function(____, h) return h:IsAlive() and h:GetLocation() ~= nil and bot:WasRecentlyDamagedByHero(h, 1) end
    )
end
--- The nearest hitter's distance past the cast's reach, for the wait and ready lines (undefined when nobody hit it).
local function nearestPast(bot)
    local best
    for ____, h in ipairs(hitters(bot)) do
        local p = math.floor(pastReach(bot, h))
        if best == nil or p < best then
            best = p
        end
    end
    return best
end
--- `clear`: an enemy hero out of sight counts as gone only once its last sighting is farther than `clear`, or RIG_FOG_CLEAR s
-- old (on1 to on3 and r1: the attacker leaving stepped into fog 490 off, `clear` held at once and the cast's heal start read a
-- hero seen 0.3 s before). `judgement`: a 300-speed hero walks 1,600 in about 5.3 s.
local RIG_FOG_CLEAR = 6
--- An enemy hero not in sight whose last sighting is within `r` of `bot` and under RIG_FOG_CLEAR s old.
local function foggedWithin(bot, r)
    do
        local pid = 0
        while pid <= 23 do
            do
                local __continue291
                repeat
                    local t = GetTeamForPlayer(pid)
                    if t == bot:GetTeam() or t ~= Team.Radiant and t ~= Team.Dire or not IsHeroAlive(pid) then
                        __continue291 = true
                        break
                    end
                    local info = GetHeroLastSeenInfo(pid)[1]
                    if info == nil or info.time_since_seen >= RIG_FOG_CLEAR then
                        __continue291 = true
                        break
                    end
                    if GetUnitToLocationDistance(bot, info.location) <= r then
                        return true
                    end
                    __continue291 = true
                until true
                if not __continue291 then
                    break
                end
            end
            pid = pid + 1
        end
    end
    return false
end
--- The spot of hero `key`'s last `stand` step this rep, or undefined when it has none (a `leave` names no point we can read).
local function standPoint(st, key, bot)
    local ____opt_76 = ____exports.RigRepOf(st.rep)
    local steps = ____opt_76 and ____opt_76.setup[key] or ({})
    do
        local i = #steps - 1
        while i >= 0 do
            local w = __TS__StringSplit(steps[i + 1], " ")
            if w[1] == "stand" and w[2] ~= nil then
                return rigPoint(bot, w[2])
            end
            i = i - 1
        end
    end
    return nil
end
--- What the cast's team sees of enemy hero `key` at its stand point: 1 an enemy hero in sight within RIG_PLACED of it, 0 the
-- point out of sight (IsLocationVisible) and no enemy hero seen there, 2 the point in sight and nobody there (not placed yet,
-- or gone); undefined for a key of the cast's own team or one with no `stand` step.
local function rigSight(bot, st, key)
    local side = string.match(key, "^([rd])%d$")
    if side == nil or (side == "r" and Team.Radiant or Team.Dire) == bot:GetTeam() then
        return nil
    end
    local p = standPoint(st, key, bot)
    if p == nil then
        return nil
    end
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        if h:IsAlive() and h:GetLocation() ~= nil and h:CanBeSeen() and not h:IsIllusion() and GetUnitToLocationDistance(h, p) <= RIG_PLACED then
            return 1
        end
    end
    return IsLocationVisible(p) and 2 or 0
end
--- The ph=wait and ph=ready `sight` field: `key:rigSight` for each enemy key of the rep with a stand point, comma-separated.
local function sightField(bot, st, rr)
    local out = {}
    for ____, k in ipairs(__TS__ArraySort(__TS__ObjectKeys(rr.setup))) do
        local s = rigSight(bot, st, k)
        if s ~= nil then
            out[#out + 1] = (k .. ":") .. tostring(s)
        end
    end
    return #out > 0 and table.concat(out, ",") or nil
end
--- With exactly one live enemy hero in sight within `r` of the cast: its estimated damage over 3 s as a share of the cast's HP.
local function loneBurst(bot, r)
    local n = 0
    local dmg = 0
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue309
            repeat
                if not h:IsAlive() or h:GetLocation() == nil or not h:CanBeSeen() or GetUnitToUnitDistance(bot, h) > r then
                    __continue309 = true
                    break
                end
                n = n + 1
                dmg = dmg + h:GetEstimatedDamageToTarget(true, bot, 3, DamageType.All)
                __continue309 = true
            until true
            if not __continue309 then
                break
            end
        end
    end
    return n == 1 and dmg / math.max(
        1,
        bot:GetHealth()
    ) or nil
end
--- The first ready check that fails for the cast, or undefined when all hold. `setup`: a rig hero not yet on its last step.
local function failingCheck(bot, st, rr)
    for ____, k in ipairs(__TS__ObjectKeys(rr.setup)) do
        local u = heroOf(bot, k)
        if u ~= nil and st.placed[u:GetPlayerID()] ~= true and (u:GetPlayerID() == bot:GetPlayerID() or ____exports.RoleOf(u) ~= "cast") then
            return "setup"
        end
    end
    local r = readyOf(bot, rr)
    if r.after ~= nil and DotaTime() - st.start < r.after then
        return "early"
    end
    for ____, k in ipairs(r.sees or ({})) do
        local s = rigSight(bot, st, k)
        if s == nil then
            return "sightkey"
        end
        if s ~= 1 then
            return "sees"
        end
    end
    for ____, k in ipairs(r.unseen or ({})) do
        local s = rigSight(bot, st, k)
        if s == nil then
            return "sightkey"
        end
        if s ~= 0 then
            return "unseen"
        end
    end
    if r.hpAtMost ~= nil then
        if hpShare(bot) <= r.hpAtMost then
            st.hpMet[bot:GetPlayerID()] = true
        elseif st.hpMet[bot:GetPlayerID()] ~= true then
            return "hp"
        end
    end
    if r.hpAtLeast ~= nil and hpShare(bot) < r.hpAtLeast then
        return "hplow"
    end
    if r.mpAtMost ~= nil then
        if mpShare(bot) <= r.mpAtMost then
            st.mpMet[bot:GetPlayerID()] = true
        elseif st.mpMet[bot:GetPlayerID()] ~= true then
            return "mp"
        end
    end
    if r.mpAtLeast ~= nil and mpShare(bot) < r.mpAtLeast then
        return "mplow"
    end
    for ____, it in ipairs(r.holds or ({})) do
        if not holdsItem(bot, it) then
            return "holds"
        end
    end
    for ____, it in ipairs(r.lacks or ({})) do
        if holdsItem(bot, it) then
            return "lacks"
        end
    end
    for ____, ____value in ipairs(__TS__ObjectEntries(r.charges or ({}))) do
        local it = ____value[1]
        local lo = ____value[2][1]
        local hi = ____value[2][2]
        local c = chargesOf(bot, it)
        if c == nil or c < lo or c > hi then
            return "charges"
        end
    end
    if r.goldAtLeast ~= nil and bot:GetGold() < r.goldAtLeast then
        return "gold"
    end
    if r.bounty == true then
        local RD = require(GetScriptDirectory().."/FunLib/humaniser/rune_detour")
        local rd = RD.ReadPass(bot)
        if rd == nil or rd.ex > RD.SETTINGS.Budget then
            return "bounty"
        end
    end
    if r.courier == true and not courierFree(bot) then
        return "courier"
    end
    if r.tree ~= nil and #(bot:GetNearbyTrees(r.tree) or ({})) == 0 then
        return "tree"
    end
    if r.clear ~= nil or r.near ~= nil then
        local nearest = math.huge
        for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
            do
                local __continue348
                repeat
                    if not h:IsAlive() or h:GetLocation() == nil then
                        __continue348 = true
                        break
                    end
                    nearest = math.min(
                        nearest,
                        GetUnitToUnitDistance(bot, h)
                    )
                    __continue348 = true
                until true
                if not __continue348 then
                    break
                end
            end
        end
        if r.clear ~= nil and (nearest <= r.clear or foggedWithin(bot, r.clear)) then
            return "clear"
        end
        if r.near ~= nil and nearest > r.near then
            return "near"
        end
    end
    if r.hit == true or r.past ~= nil or r.behind ~= nil then
        local hs = hitters(bot)
        if #hs == 0 then
            return "hit"
        end
        if r.past ~= nil then
            for ____, h in ipairs(hs) do
                local p = pastReach(bot, h)
                if p < r.past[1] or p > r.past[2] then
                    return "past"
                end
            end
        end
        if r.behind ~= nil and not __TS__ArraySome(
            hs,
            function(____, h) return hpShare(h) - hpShare(bot) >= r.behind end
        ) then
            return "behind"
        end
    end
    if r.lone ~= nil then
        local b = loneBurst(bot, r.lone[1])
        if b == nil then
            return "lone"
        end
        if #hitters(bot) > 0 then
            return "lonehit"
        end
        if b < r.lone[2] or b >= r.lone[3] then
            return "burst"
        end
    end
    if r.pair ~= nil then
        local f = pairFacts(bot, r.pair[1], r.pair[2])
        if type(f) == "string" then
            return f
        end
        if r.ahead == true and not (f.ko > f.kt) then
            return "ahead"
        end
    end
    if r.towerCreep ~= nil then
        if #(bot:GetNearbyTowers(1200, false) or ({})) == 0 then
            return "notower"
        end
        if not ____exports.TowerOnCreep(bot, r.towerCreep) then
            return "towercreep"
        end
    end
    if r.low ~= nil or r.foes ~= nil or r.foesAtMost ~= nil or r.alliesAtMost ~= nil then
        local low, foes, allies = ____exports.LowFacts(bot, r.low)
        if r.low ~= nil and not low then
            return "low"
        end
        if r.foes ~= nil and foes < r.foes then
            return "foes"
        end
        if r.foesAtMost ~= nil and foes > r.foesAtMost then
            return "foesmax"
        end
        if r.alliesAtMost ~= nil and allies > r.alliesAtMost then
            return "allies"
        end
    end
    return nil
end
--- A `lone` rep's burst share for the wait and ready lines, two decimals (undefined otherwise, or with no lone hero).
local function burstField(bot, rr)
    if rr.ready.lone == nil then
        return nil
    end
    local b = loneBurst(bot, rr.ready.lone[1])
    local ____temp_78
    if b == nil then
        ____temp_78 = nil
    else
        ____temp_78 = math.floor(b * 100 + 0.5) / 100
    end
    return ____temp_78
end
local RIG_TRACE_EVERY = 0.25
--- The trace's enemy heroes: in sight within this of the cast (the lone stand's reach).
local RIG_TRACE_REACH = 1700
--- After ready, for `secs`, every RIG_TRACE_EVERY: the cast's HP and the read of the enemy heroes in sight within
-- RIG_TRACE_REACH, each one's GetEstimatedDamageToTarget(true, cast, 3, all) summed (`est`, HP), as the threat read calls
-- it; the nearest one's mana share; whether the cast is rooted (a bolt landed).
local function rigTrace(bot, st, secs)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local from = st.readyAt[pid]
    if from == nil or now - from > secs then
        return
    end
    local last = st.tracedAt[pid]
    if last ~= nil and now - last < RIG_TRACE_EVERY then
        return
    end
    st.tracedAt[pid] = now
    local est = 0
    local n = 0
    local near
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue415
            repeat
                if not h:IsAlive() or h:GetLocation() == nil or not h:CanBeSeen() or GetUnitToUnitDistance(bot, h) > RIG_TRACE_REACH then
                    __continue415 = true
                    break
                end
                n = n + 1
                est = est + h:GetEstimatedDamageToTarget(true, bot, 3, DamageType.All)
                if near == nil or GetUnitToUnitDistance(bot, h) < GetUnitToUnitDistance(bot, near) then
                    near = h
                end
                __continue415 = true
            until true
            if not __continue415 then
                break
            end
        end
    end
    local ____Telemetry_Event_88 = Telemetry.Event
    local ____array_87 = __TS__SparseArrayNew(
        {"ph", "trace"},
        {
            "name",
            ____exports.Name()
        },
        {"pid", pid},
        {"rep", st.rep},
        {
            "s",
            math.floor((now - from) * 100 + 0.5) / 100
        },
        {
            "hp",
            bot:GetHealth()
        },
        {
            "mhp",
            bot:GetMaxHealth()
        },
        {
            "est",
            math.floor(est + 0.5)
        },
        {"n", n},
        {
            "foe",
            near and near:GetUnitName()
        }
    )
    local ____temp_81
    if near == nil then
        ____temp_81 = nil
    else
        ____temp_81 = math.floor(near:GetMana() / math.max(
            1,
            near:GetMaxMana()
        ) * 100 + 0.5) / 100
    end
    __TS__SparseArrayPush(
        ____array_87,
        {"fmana", ____temp_81},
        {
            "flvl",
            near and near:GetLevel()
        }
    )
    local ____temp_84
    if near == nil then
        ____temp_84 = nil
    else
        ____temp_84 = math.floor(GetUnitToUnitDistance(bot, near))
    end
    __TS__SparseArrayPush(____array_87, {"d", ____temp_84})
    local ____this_86
    ____this_86 = bot
    local ____opt_85 = ____this_86.IsRooted
    __TS__SparseArrayPush(
        ____array_87,
        {
            "root",
            (____opt_85 and ____opt_85(____this_86)) == true and 1 or 0
        },
        {
            "alive",
            bot:IsAlive() and 1 or 0
        }
    )
    ____Telemetry_Event_88(
        "drill",
        {__TS__SparseArraySpread(____array_87)}
    )
end
--- Enemy lane creeps within this of a watched cast are read for attacks on it (a ranged creep's reach and its walk).
local WATCH_CREEPS = 900
--- Rig `watch`, per frame of a released cast: `ph=atk` when its GetLastAttackTime rose with an enemy hero its attack target;
-- `ph=chit` for each enemy lane creep attacking it whose GetLastAttackTime falls since the last frame, `ph=hhit` the same for an
-- enemy hero (all on GameTime's clock, so no creep handle need be kept between frames).
local function rigWatch(bot, st)
    local pid = bot:GetPlayerID()
    local now = GameTime()
    local mine = bot:GetLastAttackTime()
    local prev = st.watchAt[pid]
    st.watchAt[pid] = {now, mine}
    if prev == nil then
        return
    end
    if mine > prev[2] then
        local t = bot:GetAttackTarget()
        if t ~= nil and t ~= nil and not t:IsNull() and t:IsHero() and t:GetTeam() ~= bot:GetTeam() then
            Telemetry.Event(
                "drill",
                {
                    {"ph", "atk"},
                    {
                        "name",
                        ____exports.Name()
                    },
                    {"pid", pid},
                    {"rep", st.rep},
                    {
                        "tpid",
                        t:GetPlayerID()
                    },
                    {
                        "d",
                        math.floor(GetUnitToUnitDistance(bot, t))
                    }
                }
            )
        end
    end
    local function hitOn(u, ph, tpid)
        if u:IsNull() or not u:IsAlive() or u:GetAttackTarget() ~= bot then
            return
        end
        local at = u:GetLastAttackTime()
        if at <= prev[1] or at > now then
            return
        end
        Telemetry.Event(
            "drill",
            {
                {"ph", ph},
                {
                    "name",
                    ____exports.Name()
                },
                {"pid", pid},
                {"rep", st.rep},
                {"tpid", tpid},
                {
                    "dmg",
                    math.floor(bot:GetActualIncomingDamage(
                        u:GetAttackDamage(),
                        DamageType.Physical
                    ) + 0.5)
                }
            }
        )
    end
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(WATCH_CREEPS, true) or ({})) do
        hitOn(c, "chit")
    end
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, BotMode.None) or ({})) do
        if not h:IsIllusion() then
            hitOn(
                h,
                "hhit",
                h:GetPlayerID()
            )
        end
    end
end
--- Per frame, a rig's cast: in setup, checks ready; logs `ph=ready` once per rep (ok=1, or ok=0 with the failing check at timeout).
local function rigTick(bot)
    local st = rigState()
    if st == nil then
        return
    end
    local pid = bot:GetPlayerID()
    if st.phase[pid] == nil then
        st.phase[pid] = "setup"
    end
    local r = rigOf(____exports.Active())
    if st.phase[pid] == "released" and (r and r.trace) ~= nil then
        rigTrace(bot, st, r.trace)
    end
    if st.phase[pid] == "released" and (r and r.watch) == true then
        rigWatch(bot, st)
    end
    if st.phase[pid] ~= "setup" then
        return
    end
    local rr = ____exports.RigRepOf(st.rep)
    if rr == nil or r == nil then
        return
    end
    local fail = failingCheck(bot, st, rr)
    local secs = DotaTime() - st.start
    if fail ~= nil and st.waiting[pid] ~= fail then
        st.waiting[pid] = fail
        Telemetry.Event(
            "drill",
            {
                {"ph", "wait"},
                {
                    "name",
                    ____exports.Name()
                },
                {"pid", pid},
                {"rep", st.rep},
                {"fail", fail},
                {
                    "secs",
                    math.floor(secs * 10 + 0.5) / 10
                },
                {
                    "hp",
                    math.floor(hpShare(bot) * 100 + 0.5) / 100
                },
                {
                    "d",
                    nearestPast(bot)
                },
                {
                    "bu",
                    burstField(bot, rr)
                },
                {
                    "sight",
                    sightField(bot, st, rr)
                }
            }
        )
    end
    if fail ~= nil and secs < r.timeout then
        return
    end
    st.phase[pid] = fail == nil and "released" or "invalid"
    st.readyAt[pid] = DotaTime()
    local ____Telemetry_Event_96 = Telemetry.Event
    local ____array_95 = __TS__SparseArrayNew(
        {"ph", "ready"},
        {
            "name",
            ____exports.Name()
        },
        {"pid", pid},
        {"rep", st.rep},
        {"var", rr.name}
    )
    local ____opt_93 = rr.tasks
    __TS__SparseArrayPush(
        ____array_95,
        {
            "task",
            ____opt_93 and ____opt_93[keyOf(bot) or ""]
        },
        {"ok", fail == nil and 1 or 0},
        {"fail", fail},
        {
            "secs",
            math.floor(secs * 10 + 0.5) / 10
        },
        {
            "hp",
            math.floor(hpShare(bot) * 100 + 0.5) / 100
        },
        {
            "mp",
            math.floor(mpShare(bot) * 100 + 0.5) / 100
        },
        {
            "d",
            nearestPast(bot)
        },
        {
            "bu",
            burstField(bot, rr)
        },
        {
            "rend",
            st.start + ____exports.Active().rep.every
        },
        {"win", r.window},
        {
            "rel",
            table.concat(
                __TS__ArrayFilter(
                    r.release.modes,
                    function(____, m) return m ~= "idle" end
                ),
                ","
            )
        },
        {
            "sight",
            sightField(bot, st, rr)
        },
        {
            "hl",
            GetHeightLevel(bot:GetLocation())
        }
    )
    ____Telemetry_Event_96(
        "drill",
        {__TS__SparseArraySpread(____array_95)}
    )
    if r.grid ~= nil then
        local at = bot:GetLocation()
        --- [half-width, step]: at ready (ok or not) the cast logs `ph=grid`, IsLocationVisible over the square of that half-width
        -- around it at that step (`Sight.VisionGridBox`'s `x0,y0,nx,ny,step,hex`): its team's sight, for fitting a sight model.
        local half, step = unpack(r.grid)
        Telemetry.Event(
            "drill",
            {
                {"ph", "grid"},
                {
                    "name",
                    ____exports.Name()
                },
                {"pid", pid},
                {"rep", st.rep},
                {"var", rr.name},
                {
                    "x",
                    math.floor(at.x)
                },
                {
                    "y",
                    math.floor(at.y)
                },
                {
                    "vg",
                    Sight.VisionGridBox(
                        at.x - half,
                        at.y - half,
                        at.x + half,
                        at.y + half,
                        step,
                        at.z
                    )
                },
                {
                    "vu",
                    Sight.Viewers(at.x, at.y, half + 2000, bot)
                },
                {
                    "vr",
                    math.floor(bot:GetCurrentVisionRange())
                }
            }
        )
    end
end
--- The active drill's rep start times for a forced context (DotaTime seconds, up to 60:00), input-on reps only.
function ____exports.RepTimes(context)
    local d = ____exports.Active()
    if d == nil or d.forces ~= context then
        return nil
    end
    local out = {}
    local n = 0
    do
        local t = d.rep.from
        while t <= 3600 do
            n = n + 1
            if not controlRep(d, n) then
                out[#out + 1] = t
            end
            t = t + d.rep.every
        end
    end
    return out
end
local lastRep = {}
local lastRole = {}
local REMOVED = {"Solo", "StackEvery", "LaneOnly"}
local removedLogged = false
--- Per hero per frame: the role line when it changes, and the team's rep line once per rep from its first cast hero. Only
-- from the pregame on: strategy time runs its own clock up to 0 before the pregame resets it to -90, so a line logged then
-- would fall in another game of the log store and fire rep 1 early (drill1, 08/11/2026).
function ____exports.Tick(bot)
    local state = GetGameState()
    if state ~= GameState.PreGame and state ~= GameState.GameInProgress then
        return
    end
    if not removedLogged then
        removedLogged = true
        for ____, k in ipairs(REMOVED) do
            local ____opt_97 = overrides()
            local v = ____opt_97 and ____opt_97[k]
            if v ~= nil and v ~= false and v ~= -1 then
                Telemetry.Event("drill", {{"ph", "removed"}, {"name", k}})
            end
        end
    end
    local name = ____exports.Name()
    if name ~= nil and ____exports.TABLE[name].rig ~= nil then
        local k = keyOf(bot)
        if k ~= nil then
            rigUnits[k] = bot
        end
    end
    if name == nil then
        local ____opt_99 = overrides()
        local asked = ____opt_99 and ____opt_99.Drill
        if type(asked) == "string" and asked ~= "" and lastRole[-1] ~= asked then
            lastRole[-1] = asked
            Telemetry.Event("drill", {{"ph", "unknown"}, {"name", asked}})
        end
        return
    end
    local d = ____exports.TABLE[name]
    local pid = bot:GetPlayerID()
    local role = ____exports.RoleOf(bot)
    local pos = LaneConfig.PositionOf(bot)
    if lastRole[pid] ~= role then
        lastRole[pid] = role
        Telemetry.Event(
            "drill",
            {
                {"ph", "role"},
                {"name", name},
                {"pid", pid},
                {
                    "team",
                    bot:GetTeam()
                },
                {"pos", pos},
                {"role", role}
            }
        )
    end
    forbidCast(bot)
    if role ~= "cast" then
        return
    end
    local now = DotaTime()
    local rep = ____exports.RepAt(now)
    local team = bot:GetTeam()
    if rep == 0 or lastRep[team] == rep then
        rigTick(bot)
        return
    end
    lastRep[team] = rep
    local start = d.rep.from + (rep - 1) * d.rep.every
    local ____Telemetry_Event_104 = Telemetry.Event
    local ____array_103 = __TS__SparseArrayNew(
        {"ph", "rep"},
        {"name", name},
        {"team", team},
        {"rep", rep},
        {
            "input",
            controlRep(d, rep) and "off" or "on"
        },
        {"start", start},
        {"forces", d.forces}
    )
    local ____opt_101 = ____exports.RigRepOf(rep)
    __TS__SparseArrayPush(____array_103, {"var", ____opt_101 and ____opt_101.name})
    ____Telemetry_Event_104(
        "drill",
        {__TS__SparseArraySpread(____array_103)}
    )
    rigTick(bot)
end
--- Tests: forget the role and rep lines already logged.
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(lastRep)) do
        __TS__Delete(lastRep, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(lastRole)) do
        __TS__Delete(lastRole, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(statueSide)) do
        __TS__Delete(statueSide, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(lastSpot)) do
        __TS__Delete(lastSpot, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(lingering)) do
        __TS__Delete(lingering, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(lingered)) do
        __TS__Delete(lingered, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(reachedBreak)) do
        __TS__Delete(reachedBreak, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(brokeOff)) do
        __TS__Delete(brokeOff, k)
    end
    removedLogged = false
    rig = nil
    for ____, k in ipairs(__TS__ObjectKeys(waitSlots)) do
        __TS__Delete(waitSlots, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(rigUnits)) do
        __TS__Delete(rigUnits, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(rigSpots)) do
        __TS__Delete(rigSpots, k)
    end
end
return ____exports
