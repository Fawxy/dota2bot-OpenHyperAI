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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__ArrayEvery(self, callbackfn, thisArg)
    for i = 1, #self do
        if not callbackfn(thisArg, self[i], i - 1, self) then
            return false
        end
    end
    return true
end

local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__ArrayReduce(self, callbackFn, ...)
    local len = #self
    local k = 0
    local accumulator = nil
    if __TS__CountVarargs(...) ~= 0 then
        accumulator = ...
    elseif len > 0 then
        accumulator = self[1]
        k = 1
    else
        error("Reduce of empty array with no initial value", 0)
    end
    for i = k + 1, len do
        accumulator = callbackFn(
            nil,
            accumulator,
            self[i],
            i - 1,
            self
        )
    end
    return accumulator
end

local function __TS__StringStartsWith(self, searchString, position)
    if position == nil or position < 0 then
        position = 0
    end
    return string.sub(self, position + 1, #searchString + position) == searchString
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
-- End of Lua Library inline imports
local ____exports = {}
local dist, enemyOf, valid, ownTowersBehind, nearestTowerBehind, unpaid, FOUNTAIN, TOWER_IDS
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Shop = ____dota.Shop
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Chooser = require(GetScriptDirectory().."/FunLib/humaniser/chooser")
local Lane_ = require(GetScriptDirectory().."/FunLib/humaniser/lane")
local FarmPattern = require(GetScriptDirectory().."/FunLib/humaniser/farm_pattern")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local CreepAggro = require(GetScriptDirectory().."/FunLib/humaniser/creep_aggro")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local ItemUse = require(GetScriptDirectory().."/FunLib/humaniser/item_use")
local Cut = require(GetScriptDirectory().."/FunLib/humaniser/cut")
function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
function enemyOf(team)
    return team == Team.Radiant and Team.Dire or Team.Radiant
end
function valid(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:GetLocation() ~= nil
end
function ____exports.Fountain(team)
    local x, y, z = unpack(FOUNTAIN[team])
    return Vector(x, y, z)
end
function ownTowersBehind(bot)
    local team = bot:GetTeam()
    local ef = ____exports.Fountain(enemyOf(team))
    local mine = dist(
        bot:GetLocation(),
        ef
    )
    local out = {}
    for ____, id in ipairs(TOWER_IDS) do
        local tw = GetTower(team, id)
        if valid(tw) and dist(
            tw:GetLocation(),
            ef
        ) > mine - ____exports.SETTINGS.TowerStandBack then
            out[#out + 1] = tw
        end
    end
    return out
end
function nearestTowerBehind(bot)
    local best
    local bestD = math.huge
    for ____, t in ipairs(ownTowersBehind(bot)) do
        local d = GetUnitToUnitDistance(bot, t)
        if d < bestD then
            best = t
            bestD = d
        end
    end
    return best
end
function unpaid(bot, r)
    if #r.eng == 0 then
        return 0
    end
    local n = 0
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, BotMode.None) or ({})) do
        do
            local __continue136
            repeat
                if not valid(h) or not __TS__ArrayIncludes(
                    r.eng,
                    h:GetPlayerID()
                ) then
                    __continue136 = true
                    break
                end
                if not CreepAggro.Paid(bot, h) then
                    n = n + 1
                end
                __continue136 = true
            until true
            if not __continue136 then
                break
            end
        end
    end
    return n
end
____exports.SETTINGS = {
    Horizon = 2,
    EngagedWindow = 6,
    EvenBurst = 1,
    EvenHp = 0.5,
    BudgetFree = 0.5,
    BudgetBusy = 0.6,
    BudgetCommitted = 0.75,
    ExitBand = 0.15,
    ExitDwell = 1.5,
    HealFloor = 0.3,
    HealUntil = 0.8,
    HealBack = 0.5,
    RouteStep = 300,
    SecsPerCost = 5,
    RegenItems = {"item_tango", "item_tango_single", "item_flask", "item_faerie_fire"},
    RegenCredit = 1,
    HealSets = {
        {"tango_single"},
        {"tango"},
        {"salve"},
        {"fire"},
        {"salve", "tango"},
        {"tango", "fire"}
    },
    HealTree = 300,
    HealUseWait = 1.5,
    HealItemHorizon = Threat.SETTINGS.GateHorizon,
    HealItemUnseenMargin = 200,
    EpisodeDesire = 0.95,
    DrillDesire = 1,
    Arrive = 200,
    TowerStandBack = 350,
    TowerClear = 50,
    AllyAnchorMax = 3000,
    MaxSecs = 40,
    PlainFountainHP = 0.5,
    ReadEvery = 0.1,
    CutEvery = 2,
    OrderEvery = 0.3,
    DrillMinHP = 0.5,
    DrillSpotArrive = 150
}
FOUNTAIN = {[Team.Radiant] = {-6619, -6336, 384}, [Team.Dire] = {6928, 6372, 392}}
TOWER_IDS = {
    Tower.Top1,
    Tower.Top2,
    Tower.Top3,
    Tower.Mid1,
    Tower.Mid2,
    Tower.Mid3,
    Tower.Bot1,
    Tower.Bot2,
    Tower.Bot3,
    Tower.Base1,
    Tower.Base2
}
local HEAL_ITEM = {tango_single = {name = "item_tango_single", modifier = "modifier_tango_heal"}, tango = {name = "item_tango", modifier = "modifier_tango_heal"}, salve = {name = "item_flask", modifier = "modifier_flask_healing"}, fire = {name = "item_faerie_fire"}}
local states = {}
local episodes = 0
local fountainLogged = false
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(states)) do
        __TS__Delete(states, k)
    end
    episodes = 0
    fountainLogged = false
    RetreatState.ResetCache()
end
local function stateOf(bot)
    local pid = bot:GetPlayerID()
    local s = states[pid]
    if s == nil then
        s = {}
        states[pid] = s
    end
    return s
end
local function hpShare(bot)
    return bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    )
end
local function r2(x)
    return math.floor(x * 100 + 0.5) / 100
end
local function logFountain()
    if fountainLogged then
        return
    end
    fountainLogged = true
    for ____, team in ipairs({Team.Radiant, Team.Dire}) do
        local shop = GetShopLocation(team, Shop.Home)
        local f = ____exports.Fountain(team)
        local live = shop ~= nil and shop ~= nil
        Telemetry.Event(
            "world_fact",
            {
                {"team", team},
                {"fact", "fountain_x"},
                {
                    "live",
                    live and math.floor(shop.x) or nil
                },
                {
                    "constant",
                    math.floor(f.x)
                }
            }
        )
        Telemetry.Event(
            "world_fact",
            {
                {"team", team},
                {"fact", "fountain_y"},
                {
                    "live",
                    live and math.floor(shop.y) or nil
                },
                {
                    "constant",
                    math.floor(f.y)
                }
            }
        )
    end
end
--- An enemy tower whose reach holds `bot` and that is attacking it now or hit it in the last half second.
function ____exports.TowerOnUs(bot)
    local enemy = enemyOf(bot:GetTeam())
    local br = bot:GetBoundingRadius()
    for ____, id in ipairs(TOWER_IDS) do
        do
            local __continue18
            repeat
                local tw = GetTower(enemy, id)
                if not valid(tw) then
                    __continue18 = true
                    break
                end
                if GetUnitToUnitDistance(bot, tw) > WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) + br then
                    __continue18 = true
                    break
                end
                if tw:GetAttackTarget() == bot or bot:WasRecentlyDamagedByTower(0.5) then
                    return tw
                end
                __continue18 = true
            until true
            if not __continue18 then
                break
            end
        end
    end
    return nil
end
--- Busy (a pull, stack, camp or pull farm job, or a last hit on a creep in hand), committed (a rune walk), else free.
local function purposeOf(bot)
    local s = ____exports.SETTINGS
    local job = Chooser.RunningJobName(bot)
    if job == "rune" then
        return {"committed", s.BudgetCommitted}
    end
    if job ~= nil or Lane_.CampJobDesire(bot) > 0 then
        return {"busy", s.BudgetBusy}
    end
    local target = bot:GetAttackTarget()
    if valid(target) and target:IsCreep() then
        return {"busy", s.BudgetBusy}
    end
    return {"free", s.BudgetFree}
end
--- The read `leaveWhy` decides on: Threat.Read at the hero's own place with the retreat's horizon and engaged window.
function ____exports.ReadHere(bot)
    local here = bot:GetLocation()
    return Threat.Read(
        bot,
        here,
        here,
        ____exports.SETTINGS.Horizon,
        {engagedWindow = ____exports.SETTINGS.EngagedWindow}
    )
end
local function readOf(bot, st, now)
    if st.read ~= nil and st.readAt ~= nil and now - st.readAt < ____exports.SETTINGS.ReadEvery then
        return st.read
    end
    st.read = ____exports.ReadHere(bot)
    st.readAt = now
    return st.read
end
--- The cost of standing at `p` when we reach it `t` seconds from now: enemy tower reach, enemy creep acquisition, heroes who can be in range by then.
local function pointCost(bot, p, t, towers, creeps, heroes)
    local tower = false
    for ____, tw in ipairs(towers) do
        if dist(
            tw:GetLocation(),
            p
        ) <= WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) then
            tower = true
        end
    end
    local wave = false
    local br = bot:GetBoundingRadius()
    for ____, c in ipairs(creeps) do
        if dist(
            c:GetLocation(),
            p
        ) <= c:GetAcquisitionRange() + c:GetBoundingRadius() + br then
            wave = true
        end
    end
    local n = 0
    for ____, e in ipairs(heroes) do
        local run = e:GetCurrentMovementSpeed() * t + e:GetAttackRange() + e:GetBoundingRadius() + br
        if dist(
            e:GetLocation(),
            p
        ) <= run then
            n = n + 1
        end
    end
    return {tower = tower, wave = wave, heroes = n}
end
local function enemyUnits(bot)
    local enemy = enemyOf(bot:GetTeam())
    local towers = {}
    for ____, id in ipairs(TOWER_IDS) do
        local tw = GetTower(enemy, id)
        if valid(tw) then
            towers[#towers + 1] = tw
        end
    end
    local creeps = __TS__ArrayFilter(
        bot:GetNearbyLaneCreeps(1600, true) or ({}),
        function(____, c) return valid(c) end
    )
    local heroes = __TS__ArrayFilter(
        GetUnitList(UnitType.EnemyHeroes) or ({}),
        function(____, e) return valid(e) and not e:IsIllusion() and e:CanBeSeen() end
    )
    return {towers, creeps, heroes}
end
--- The straight walk from `from` to `to`, its points every RouteStep (the start excluded) scored and summed.
local function routeCost(bot, from, to, units)
    local d = dist(from, to)
    local n = math.max(
        1,
        math.ceil(d / ____exports.SETTINGS.RouteStep)
    )
    local speed = math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local cost = 0
    do
        local i = 1
        while i <= n do
            local p = Vector(from.x + (to.x - from.x) * i / n, from.y + (to.y - from.y) * i / n, to.z)
            local c = pointCost(
                bot,
                p,
                d * i / n / speed,
                units[1],
                units[2],
                units[3]
            )
            cost = cost + ((c.tower and 1 or 0) + (c.wave and 1 or 0) + c.heroes)
            i = i + 1
        end
    end
    return cost
end
local function towards(a, b, by)
    local d = math.max(
        1,
        dist(a, b)
    )
    return Vector(a.x + (b.x - a.x) * by / d, a.y + (b.y - a.y) * by / d, a.z)
end
local function standPoint(tower, team)
    local p = towards(
        tower:GetLocation(),
        ____exports.Fountain(team),
        ____exports.SETTINGS.TowerStandBack
    )
    return IsLocationPassable(p) and p or tower:GetLocation()
end
--- The anchors (design 5.4): out of a targeting tower's reach, our nearest tower behind us, the nearest ally hero, the fountain.
local function anchorsOf(bot, why)
    local team = bot:GetTeam()
    local here = bot:GetLocation()
    local f = ____exports.Fountain(team)
    local out = {{
        kind = "fountain",
        at = f,
        cost = 0,
        len = dist(here, f)
    }}
    if why == "heal" then
        return out
    end
    local tw = ____exports.TowerOnUs(bot)
    if tw ~= nil then
        local reach = WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) + ____exports.SETTINGS.Arrive + ____exports.SETTINGS.TowerClear
        local away = dist(
            tw:GetLocation(),
            here
        ) < 1 and f or here
        local p = towards(
            tw:GetLocation(),
            away,
            reach
        )
        if IsLocationPassable(p) then
            out[#out + 1] = {
                kind = "tower_edge",
                at = p,
                cost = 0,
                len = dist(here, p)
            }
        end
    end
    local nearT
    local nearD = math.huge
    for ____, t in ipairs(ownTowersBehind(bot)) do
        local d = GetUnitToUnitDistance(bot, t)
        if d < nearD then
            nearT = t
            nearD = d
        end
    end
    if nearT ~= nil then
        local p = standPoint(nearT, team)
        out[#out + 1] = {
            kind = "tower",
            at = p,
            cost = 0,
            len = dist(here, p)
        }
    end
    local ally
    local allyD = ____exports.SETTINGS.AllyAnchorMax
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue62
            repeat
                if not valid(a) or a == bot or a:IsIllusion() or RetreatState.Running(a) then
                    __continue62 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, a)
                if d < allyD then
                    ally = a
                    allyD = d
                end
                __continue62 = true
            until true
            if not __continue62 then
                break
            end
        end
    end
    if ally ~= nil then
        out[#out + 1] = {
            kind = "ally",
            at = ally:GetLocation(),
            ally = ally,
            cost = 0,
            len = allyD
        }
    end
    return out
end
--- Whether our lane front of the hero's lane is nearer than our fountain: going back costs less walk than going on.
local function laneNearer(bot, here)
    local front = GetLaneFrontLocation(
        bot:GetTeam(),
        bot:GetAssignedLane(),
        0
    )
    return front ~= nil and dist(here, front) < dist(
        here,
        ____exports.Fountain(bot:GetTeam())
    )
end
--- Whether a healing item is held in the inventory (slots 0-5).
local function regenHeld(bot)
    for ____, name in ipairs(____exports.SETTINGS.RegenItems) do
        local slot = bot:FindItemSlot(name)
        if slot >= 0 and slot <= 5 then
            return true
        end
    end
    return false
end
--- The least-cost anchor (exposed route points plus the walk's seconds per SecsPerCost, less RegenCredit on a tower anchor while
-- a healing item is held; ties to the shorter), the next-best's cost, the least exposure on any anchor (the route around) and
-- whether regen is held.
local function chooseAnchor(bot, why)
    local units = enemyUnits(bot)
    local here = bot:GetLocation()
    local list = anchorsOf(bot, why)
    local regen = regenHeld(bot)
    local speed = math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local minExp = math.huge
    for ____, a in ipairs(list) do
        a.exp = routeCost(bot, here, a.at, units)
        a.secs = a.len / speed
        minExp = math.min(minExp, a.exp)
        local credit = regen and a.kind == "tower" and ____exports.SETTINGS.RegenCredit or 0
        a.cost = math.floor((a.exp + a.secs / ____exports.SETTINGS.SecsPerCost - credit) * 10 + 0.5) / 10
    end
    __TS__ArraySort(
        list,
        function(____, a, b) return a.cost ~= b.cost and a.cost - b.cost or a.len - b.len end
    )
    local ____list__1_2 = list[1]
    local ____opt_0 = list[2]
    return {____list__1_2, ____opt_0 and ____opt_0.cost, minExp, regen}
end
local function anchorPoint(a)
    return a.ally ~= nil and valid(a.ally) and a.ally:GetLocation() or a.at
end
--- Enemy heroes who can reach `bot` within HealItemHorizon, seen or just out of sight: items wait for none. Also the nearest
-- enemy hero's last sighting (distance, seconds since), for the log.
local function itemReach(bot)
    local s = ____exports.SETTINGS
    local t = Threat.SETTINGS
    local here = bot:GetLocation()
    local read = Threat.Read(bot, here, here, s.HealItemHorizon)
    local n = #read.reach
    local near
    local tss
    do
        local pid = 0
        while pid <= 23 do
            do
                local __continue78
                repeat
                    local team = GetTeamForPlayer(pid)
                    if team == bot:GetTeam() or team ~= Team.Radiant and team ~= Team.Dire or not IsHeroAlive(pid) then
                        __continue78 = true
                        break
                    end
                    local info = GetHeroLastSeenInfo(pid)[1]
                    if info == nil then
                        __continue78 = true
                        break
                    end
                    local d = dist(info.location, here)
                    if near == nil or d < near then
                        near = d
                        tss = info.time_since_seen
                    end
                    if __TS__ArrayIncludes(read.reach, pid) or info.time_since_seen <= 0.1 or info.time_since_seen > t.MissingAfter then
                        __continue78 = true
                        break
                    end
                    if d <= t.MissingSpeed * (info.time_since_seen + s.HealItemHorizon) + s.HealItemUnseenMargin then
                        n = n + 1
                    end
                    __continue78 = true
                until true
                if not __continue78 then
                    break
                end
            end
            pid = pid + 1
        end
    end
    return n, near, tss
end
local function planItems(bot, ep)
    local s = ____exports.SETTINGS
    local max = math.max(
        1,
        bot:GetMaxHealth()
    )
    local need = math.ceil(s.HealBack * max - bot:GetHealth())
    local here = bot:GetLocation()
    local salveHeld = ItemUse.Usable(bot, HEAL_ITEM.salve.name) ~= nil
    local tree = ItemUse.TangoTree(bot, s.HealTree)
    local got = {}
    for ____, k in ipairs(__TS__ObjectKeys(HEAL_ITEM)) do
        do
            local __continue85
            repeat
                local it = ItemUse.Usable(bot, HEAL_ITEM[k].name)
                if it == nil then
                    __continue85 = true
                    break
                end
                local mod = HEAL_ITEM[k].modifier
                if mod ~= nil and bot:HasModifier(mod) then
                    __continue85 = true
                    break
                end
                if (k == "tango" or k == "tango_single") and tree == nil then
                    __continue85 = true
                    break
                end
                if k == "fire" and salveHeld then
                    __continue85 = true
                    break
                end
                got[k] = ItemUse.HpRestore(it)
                __continue85 = true
            until true
            if not __continue85 then
                break
            end
        end
    end
    local set
    local restore = 0
    for ____, cand in ipairs(s.HealSets) do
        do
            local __continue91
            repeat
                local items = __TS__ArrayMap(
                    cand,
                    function(____, k) return #cand > 1 and k == "tango" and got.tango_single ~= nil and "tango_single" or k end
                )
                if not __TS__ArrayEvery(
                    items,
                    function(____, k) return got[k] ~= nil end
                ) then
                    __continue91 = true
                    break
                end
                local sum = __TS__ArrayReduce(
                    items,
                    function(____, a, k) return a + (got[k] or 0) end,
                    0
                )
                if sum >= need then
                    set = items
                    restore = sum
                    break
                end
                __continue91 = true
            until true
            if not __continue91 then
                break
            end
        end
    end
    local tower = nearestTowerBehind(bot)
    local reachN, near, tss = itemReach(bot)
    local skip = not laneNearer(bot, here) and "fountain" or (reachN > 0 and "reach" or (#__TS__ObjectKeys(got) == 0 and "none" or (set == nil and "short" or (tower == nil and "no-tower" or nil))))
    Telemetry.Event(
        "retreat",
        {
            {"ph", "items"},
            {
                "pid",
                bot:GetPlayerID()
            },
            {"ep", ep.id},
            {"need", need},
            {
                "held",
                table.concat(
                    __TS__ObjectKeys(got),
                    ","
                ) or "-"
            },
            {
                "set",
                skip == nil and set ~= nil and table.concat(set, ",") or "-"
            },
            {
                "got",
                math.floor(restore)
            },
            {"tree", tree ~= nil},
            {"skip", skip or "-"},
            {
                "ed",
                near ~= nil and math.floor(near) or -1
            },
            {
                "ets",
                tss ~= nil and r2(tss) or -1
            }
        }
    )
    if skip ~= nil or set == nil or tower == nil then
        return
    end
    ep.uses = __TS__ArraySort(
        __TS__ArraySlice(set),
        function(____, a, b) return (__TS__StringStartsWith(b, "tango") and 1 or 0) - (__TS__StringStartsWith(a, "tango") and 1 or 0) end
    )
    ep.tree = tree
    ep.itemHeal = true
    local p = standPoint(
        tower,
        bot:GetTeam()
    )
    ep.anchor = {
        kind = "tower",
        at = p,
        cost = ep.anchor.cost,
        len = dist(here, p)
    }
end
--- HealItems: the wait at our tower ends, and the walk home resumes, when a hero reaches us or the items are spent without a `healed` end.
local function itemHealOn(bot, ep, r, now)
    local spent = (ep.uses == nil or #ep.uses == 0) and (ep.useUntil == nil or now >= ep.useUntil) and not bot:HasModifier("modifier_tango_heal") and not bot:HasModifier("modifier_flask_healing")
    local reachN = itemReach(bot)
    local why = (#r.reach > 0 or reachN > 0) and "reach" or (spent and "spent" or nil)
    if why == nil then
        return
    end
    ep.itemHeal = false
    ep.uses = nil
    local f = ____exports.Fountain(bot:GetTeam())
    ep.anchor = {
        kind = "fountain",
        at = f,
        cost = ep.anchor.cost,
        len = dist(
            bot:GetLocation(),
            f
        )
    }
    Telemetry.Event(
        "retreat",
        {
            {"ph", "items_off"},
            {
                "pid",
                bot:GetPlayerID()
            },
            {"ep", ep.id},
            {"skip", why},
            {
                "hp",
                r2(hpShare(bot))
            }
        }
    )
end
--- HealItems, from Think: the next use, or true while the last one's wait holds every other order.
local function useItems(bot, st, ep, now)
    if ep.useUntil ~= nil then
        local ____temp_3
        if ep.useMod ~= nil then
            ____temp_3 = bot:HasModifier(ep.useMod)
        else
            ____temp_3 = bot:GetHealth() > (ep.useHp or 0)
        end
        local shown = ____temp_3
        if now < ep.useUntil and not shown then
            return true
        end
        ep.useUntil = nil
    end
    local ____opt_4 = ep.uses
    local k = ____opt_4 and table.remove(ep.uses, 1)
    if k == nil then
        return false
    end
    local item = ItemUse.Usable(bot, HEAL_ITEM[k].name)
    Telemetry.Event(
        "retreat",
        {
            {"ph", "use"},
            {
                "pid",
                bot:GetPlayerID()
            },
            {"ep", ep.id},
            {"set", k},
            {"skip", item == nil and "gone" or "-"},
            {
                "hp",
                r2(hpShare(bot))
            }
        }
    )
    if item == nil then
        return false
    end
    ep.useUntil = now + ____exports.SETTINGS.HealUseWait
    ep.useMod = HEAL_ITEM[k].modifier
    ep.useHp = bot:GetHealth()
    st.orderTo = nil
    if k == "fire" then
        ItemUse.UseNoTarget(bot, item)
    elseif k == "salve" then
        ItemUse.UseOnSelf(bot, item)
    elseif ep.tree ~= nil then
        ItemUse.UseOnTree(bot, item, ep.tree)
    end
    return true
end
local function start(bot, st, why, r, budget, purp, spot, rep)
    local now = DotaTime()
    local anchor, alt, minExp, regen = unpack(chooseAnchor(bot, why))
    episodes = episodes + 1
    local hp = hpShare(bot)
    st.ep = {
        id = episodes,
        start = now,
        why = why,
        budget = budget,
        anchor = anchor,
        hp0 = hp,
        lastHp = bot:GetHealth(),
        dmgh = 0,
        twr = false,
        wave = false
    }
    st.overSince = nil
    if why == "heal" and Ours.On("HealItems") and Ours.On("HealStop") then
        planItems(bot, st.ep)
    end
    RetreatState.SetRunning(bot, true)
    Chooser.Abort(bot, "retreat")
    Lane_.CampJobAbort(bot, "retreat")
    FarmPattern.Abort(bot, "retreat")
    local here = bot:GetLocation()
    local ____Telemetry_Event_8 = Telemetry.Event
    local ____array_7 = __TS__SparseArrayNew(
        {"ph", "start"},
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", "ours"},
        {"ep", st.ep.id},
        {"why", why},
        {
            "hp",
            r2(hp)
        },
        {
            "thr",
            r2(r.threat)
        },
        {"band", r.band},
        {"reach", #r.reach},
        {"al", r.allies},
        {
            "burst",
            r2(r.burst)
        },
        {"eng", #r.eng},
        {
            "unp",
            unpaid(bot, r)
        },
        {"tower", r.tower}
    )
    local ____temp_6
    if #r.reach > 0 then
        ____temp_6 = r.escape
    else
        ____temp_6 = nil
    end
    __TS__SparseArrayPush(
        ____array_7,
        {"esc", ____temp_6},
        {
            "budget",
            r2(budget)
        },
        {"purp", purp},
        {"anchor", anchor.kind},
        {"cost", anchor.cost},
        {"alt", alt},
        {"exp", anchor.exp},
        {"minexp", minExp},
        {"regen", regen},
        {
            "dist",
            math.floor(anchor.len)
        },
        {"spot", spot},
        {"rep", rep},
        {
            "x",
            math.floor(here.x)
        },
        {
            "y",
            math.floor(here.y)
        }
    )
    ____Telemetry_Event_8(
        "retreat",
        {__TS__SparseArraySpread(____array_7)}
    )
end
local function ____end(bot, st, res)
    local ep = st.ep
    if ep == nil then
        return
    end
    st.ep = nil
    st.orderTo = nil
    RetreatState.SetRunning(bot, false)
    local max = math.max(
        1,
        bot:GetMaxHealth()
    )
    Telemetry.Event(
        "retreat",
        {
            {"ph", "end"},
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "ours"},
            {"ep", ep.id},
            {"why", ep.why},
            {"anchor", ep.anchor.kind},
            {"res", res},
            {
                "secs",
                r2(DotaTime() - ep.start)
            },
            {
                "hpl",
                r2(math.max(
                    0,
                    ep.hp0 - (bot:IsAlive() and hpShare(bot) or 0)
                ))
            },
            {"twr", ep.twr},
            {"wave", ep.wave},
            {
                "dmgh",
                r2(ep.dmgh / max)
            }
        }
    )
    if st.drill ~= nil and st.drill.phase == "retreat" then
        st.drill.phase = "done"
    end
end
--- Per think while an episode runs: the walk's exposure, then the stop rule. Returns the result when it ends.
local function step(bot, st, r, now)
    local ep = st.ep
    local s = ____exports.SETTINGS
    local hp = bot:GetHealth()
    if hp < ep.lastHp and bot:WasRecentlyDamagedByAnyHero(0.3) then
        ep.dmgh = ep.dmgh + (ep.lastHp - hp)
    end
    ep.lastHp = hp
    local here = bot:GetLocation()
    local towers, creeps = unpack(enemyUnits(bot))
    local c = pointCost(
        bot,
        here,
        0,
        towers,
        creeps,
        {}
    )
    if c.tower then
        ep.twr = true
    end
    if c.wave then
        ep.wave = true
    end
    local forced = ep.why == "forced"
    if not forced and not RetreatState.Owns(bot) then
        return "cut"
    end
    local at = dist(
        here,
        anchorPoint(ep.anchor)
    ) <= s.Arrive
    if ep.why == "heal" then
        if at and hpShare(bot) >= s.HealUntil then
            return "anchor"
        end
        if Ours.On("HealStop") and hpShare(bot) >= s.HealBack and #r.reach == 0 and r.threat < ep.budget - s.ExitBand and laneNearer(bot, here) then
            return "healed"
        end
        if ep.itemHeal == true then
            itemHealOn(bot, ep, r, now)
        end
        return nil
    end
    if at then
        if forced or r.threat < ep.budget then
            return "anchor"
        end
        if ep.anchor.kind ~= "fountain" then
            local f = ____exports.Fountain(bot:GetTeam())
            ep.anchor = {
                kind = "fountain",
                at = f,
                cost = ep.anchor.cost,
                len = dist(here, f)
            }
        end
    end
    if now - ep.start > s.MaxSecs then
        return "cut"
    end
    if forced or ____exports.TowerOnUs(bot) ~= nil or r.threat >= ep.budget - s.ExitBand then
        ep.underSince = nil
        return nil
    end
    if #r.reach == 0 then
        return "gone"
    end
    ep.underSince = ep.underSince or now
    return now - ep.underSince >= s.ExitDwell and "safe" or nil
end
--- The leave rule: lethal, a tower on us or the heal floor at once; over budget for `Profile.ThreatHold`. Returns the reason to
-- leave, or, with none, the reason to stay (ev=cut kind=leave logs it; the driver retreat_leave compares it).
function ____exports.LeaveWhy(bot, st, r, budget, now)
    if r.band == "lethal" then
        return "lethal", nil
    end
    if ____exports.TowerOnUs(bot) ~= nil then
        return "tower", nil
    end
    if hpShare(bot) < ____exports.SETTINGS.HealFloor and #r.reach == 0 then
        return "heal", nil
    end
    if r.threat <= budget then
        st.overSince = nil
        st.stayLogged = nil
        return nil, "under"
    end
    local even = #r.reach <= r.allies + 1 and r.burst < ____exports.SETTINGS.EvenBurst and hpShare(bot) >= ____exports.SETTINGS.EvenHp
    if Ours.On("RetreatOdds") and even and unpaid(bot, r) == 0 then
        st.overSince = nil
        if st.stayLogged ~= true then
            st.stayLogged = true
            Telemetry.Event(
                "retreat",
                {
                    {"ph", "stay"},
                    {
                        "pid",
                        bot:GetPlayerID()
                    },
                    {
                        "thr",
                        r2(r.threat)
                    },
                    {"band", r.band},
                    {"reach", #r.reach},
                    {"al", r.allies},
                    {
                        "burst",
                        r2(r.burst)
                    },
                    {"eng", #r.eng},
                    {
                        "budget",
                        r2(budget)
                    },
                    {
                        "hp",
                        r2(hpShare(bot))
                    }
                }
            )
        end
        return nil, "even"
    end
    st.overSince = st.overSince or now
    if now - st.overSince >= Profile.ThreatHold(bot) then
        return "threat", nil
    end
    return nil, "hold"
end
--- The retreat-walk drill's cast: walk to the rep's start spot, then the forced episode, then stand. Undefined when not in it.
local function drillDesire(bot, st, now)
    if Drill.ForcedAt("retreat", now) == nil or Drill.RoleOf(bot) ~= "cast" then
        return nil
    end
    local rep = Drill.RepAt(now)
    if rep == 0 then
        return nil
    end
    if st.drill == nil or st.drill.rep ~= rep then
        if st.ep ~= nil then
            ____end(bot, st, "cut")
        end
        local spot = Drill.CastSpot(rep) or "front"
        local skip = hpShare(bot) < ____exports.SETTINGS.DrillMinHP
        st.drill = {
            rep = rep,
            phase = skip and "skip" or "walk",
            spot = spot,
            at = skip and ____exports.Fountain(bot:GetTeam()) or Drill.CastSpotPoint(bot, spot)
        }
        if skip then
            Telemetry.Event(
                "retreat",
                {
                    {"ph", "skip"},
                    {
                        "pid",
                        bot:GetPlayerID()
                    },
                    {"rep", rep},
                    {"spot", spot},
                    {
                        "hp",
                        r2(hpShare(bot))
                    }
                }
            )
        end
    end
    local d = st.drill
    if d.phase == "walk" and (d.at == nil or GetUnitToLocationDistance(bot, d.at) <= ____exports.SETTINGS.DrillSpotArrive) then
        d.phase = "retreat"
        start(
            bot,
            st,
            "forced",
            readOf(bot, st, now),
            ____exports.SETTINGS.BudgetFree,
            "free",
            d.spot,
            rep
        )
    end
    if d.phase == "retreat" and st.ep ~= nil then
        local res = step(
            bot,
            st,
            readOf(bot, st, now),
            now
        )
        if res ~= nil then
            ____end(bot, st, res)
        end
    end
    return ____exports.SETTINGS.DrillDesire
end
--- ev=cut kind=leave on a changed answer, else while a hero is in reach, at most every CutEvery. Reads state; the decision does not use it.
local function cutLeave(bot, st, r, budget, purp, why, stay, overBefore, now)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true then
        return
    end
    local dec = why or stay
    local changed = st.cutDec ~= dec
    if not changed and not (#r.reach > 0 and now - (st.cutAt or -math.huge) >= ____exports.SETTINGS.CutEvery) then
        return
    end
    st.cutDec = dec
    st.cutAt = now
    pcall(
        Cut.Leave,
        bot,
        {
            r = r,
            dec = dec,
            budget = budget,
            purp = purp,
            over = overBefore ~= nil and now - overBefore or nil,
            hold = Profile.ThreatHold(bot),
            unp = unpaid(bot, r),
            short = math.min(____exports.SETTINGS.Horizon, Threat.SETTINGS.BurstWindow),
            long = ____exports.SETTINGS.EngagedWindow
        }
    )
end
--- With the switch on: Think is assigned at load (mode_retreat_generic).
function ____exports.On()
    return Ours.On("Retreat")
end
--- mode_retreat_generic GetDesire: our desire for a hero we own (EpisodeDesire while an episode runs, else 0); undefined lets OHA's desire run.
function ____exports.Desire(bot)
    local st = stateOf(bot)
    local now = DotaTime()
    logFountain()
    local drill = drillDesire(bot, st, now)
    if drill ~= nil then
        return drill
    end
    if not RetreatState.Owns(bot) then
        if st.ep ~= nil then
            ____end(bot, st, "cut")
        end
        return nil
    end
    if not bot:IsAlive() then
        if st.ep ~= nil then
            ____end(bot, st, "died")
        end
        st.overSince = nil
        return 0
    end
    local readAtBefore = st.readAt
    local r = readOf(bot, st, now)
    if st.ep ~= nil then
        local res = step(bot, st, r, now)
        if res == nil then
            return ____exports.SETTINGS.EpisodeDesire
        end
        ____end(bot, st, res)
        return 0
    end
    local purp, budget = unpack(purposeOf(bot))
    if r.band ~= st.band then
        st.band = r.band
        Telemetry.Event(
            "retreat",
            {
                {"ph", "read"},
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"band", r.band},
                {
                    "thr",
                    r2(r.threat)
                },
                {"reach", #r.reach},
                {
                    "burst",
                    r2(r.burst)
                },
                {"eng", #r.eng},
                {"tower", r.tower},
                {"esc", r.escape},
                {"budget", budget},
                {
                    "hp",
                    r2(hpShare(bot))
                },
                {
                    "crp",
                    bot:WasRecentlyDamagedByCreep(1)
                }
            }
        )
    end
    if Drill.RetreatHeld(
        bot,
        hpShare(bot)
    ) then
        return 0
    end
    local overBefore = st.overSince
    local why, stay = ____exports.LeaveWhy(
        bot,
        st,
        r,
        budget,
        now
    )
    if readAtBefore ~= st.readAt then
        cutLeave(
            bot,
            st,
            r,
            budget,
            purp,
            why,
            stay,
            overBefore,
            now
        )
    end
    if why == nil then
        return 0
    end
    start(
        bot,
        st,
        why,
        r,
        budget,
        purp
    )
    return ____exports.SETTINGS.EpisodeDesire
end
--- Per frame (index Tick): a death ends the episode even when GetDesire is not asked while dead.
function ____exports.Tick(bot)
    local st = states[bot:GetPlayerID()]
    if (st and st.ep) ~= nil and not bot:IsAlive() then
        ____end(bot, st, "died")
    end
end
local function moveTo(bot, st, p, now)
    if st.orderTo ~= nil and st.orderAt ~= nil and dist(st.orderTo, p) < 50 and now - st.orderAt < ____exports.SETTINGS.OrderEvery then
        return
    end
    st.orderTo = p
    st.orderAt = now
    bot:Action_MoveToLocation(p)
end
--- The plain walk: the fountain under PlainFountainHP, else our nearest tower behind the hero, else the fountain.
local function plainTarget(bot)
    local team = bot:GetTeam()
    if hpShare(bot) < ____exports.SETTINGS.PlainFountainHP then
        return {
            "fountain",
            ____exports.Fountain(team)
        }
    end
    local best
    local bestD = math.huge
    for ____, t in ipairs(ownTowersBehind(bot)) do
        local d = GetUnitToUnitDistance(bot, t)
        if d < bestD then
            best = t
            bestD = d
        end
    end
    return best ~= nil and ({
        "tower",
        standPoint(best, team)
    }) or ({
        "fountain",
        ____exports.Fountain(team)
    })
end
--- mode_retreat_generic Think (assigned at load with the switch on): our episode's walk, a drill rep's walk, or the plain walk.
function ____exports.Think(bot)
    local st = stateOf(bot)
    local now = DotaTime()
    local d = st.drill
    if d ~= nil and Drill.ForcedAt("retreat", now) ~= nil and st.ep == nil then
        if (d.phase == "walk" or d.phase == "skip") and d.at ~= nil then
            moveTo(bot, st, d.at, now)
        else
            moveTo(
                bot,
                st,
                plainTarget(bot)[2],
                now
            )
        end
        return
    end
    if st.ep ~= nil then
        if st.ep.itemHeal == true and useItems(bot, st, st.ep, now) then
            return
        end
        moveTo(
            bot,
            st,
            anchorPoint(st.ep.anchor),
            now
        )
        return
    end
    local kind, p = unpack(RetreatState.Owns(bot) and plainTarget(bot) or ({
        "fountain",
        ____exports.Fountain(bot:GetTeam())
    }))
    if st.plainAt == nil or now - st.plainAt > 1 then
        Telemetry.Event(
            "retreat",
            {
                {"ph", "start"},
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"kind", "plain"},
                {"anchor", kind},
                {
                    "hp",
                    r2(hpShare(bot))
                },
                {
                    "x",
                    math.floor(p.x)
                },
                {
                    "y",
                    math.floor(p.y)
                }
            }
        )
    end
    st.plainAt = now
    moveTo(bot, st, p, now)
end
--- The lane-only drill harness steps aside for our retreat while an episode runs (mode_laning_generic).
function ____exports.Running(bot)
    return RetreatState.Running(bot)
end
--- HealItems: OHA's item code (ItemUsageComplement, roam's tango) leaves our heal items alone on a hero our retreat owns while
-- a heal episode runs, or under the heal floor (where one starts; faerie fire only with nobody in reach): the heal start's plan decides their
-- use, and a walk home keeps them. hi1: OHA drank the planned salve the frame our episode started (rep 2), and in the second
-- between a `gone` end and the heal start (rep 5). In a fight OHA's salve and faerie fire stay. Reads the cached read only.
function ____exports.HoldsItem(bot, name)
    if not Ours.On("HealItems") or not Ours.On("HealStop") or not RetreatState.Owns(bot) then
        return false
    end
    if not __TS__ArraySome(
        __TS__ObjectKeys(HEAL_ITEM),
        function(____, k) return HEAL_ITEM[k].name == name end
    ) then
        return false
    end
    local st = states[bot:GetPlayerID()]
    if (st and st.ep) ~= nil then
        return st.ep.why == "heal"
    end
    if hpShare(bot) >= ____exports.SETTINGS.HealFloor then
        return false
    end
    if name ~= HEAL_ITEM.fire.name then
        return true
    end
    return (st and st.read) ~= nil and #st.read.reach == 0
end
--- mode_farm_generic: none of ShouldRun's runs apply to a hero our retreat owns.
function ____exports.Owns(bot)
    return RetreatState.Owns(bot)
end
return ____exports
