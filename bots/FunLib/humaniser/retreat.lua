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
local dist, valid, unpaid
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
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local LaneFightConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_config")
function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
function valid(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:GetLocation() ~= nil
end
function unpaid(bot, r)
    if #r.eng == 0 then
        return 0
    end
    local radius = LaneFightConfig.Settings().CreepAggroRadius
    local ours = __TS__ArrayFilter(
        bot:GetNearbyLaneCreeps(1600, false) or ({}),
        function(____, c) return valid(c) and c:IsAlive() end
    )
    local n = 0
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, BotMode.None) or ({})) do
        do
            local __continue97
            repeat
                if not valid(h) or not __TS__ArrayIncludes(
                    r.eng,
                    h:GetPlayerID()
                ) then
                    __continue97 = true
                    break
                end
                local at = h:GetLocation()
                if not __TS__ArraySome(
                    ours,
                    function(____, c) return dist(
                        c:GetLocation(),
                        at
                    ) <= radius end
                ) then
                    n = n + 1
                end
                __continue97 = true
            until true
            if not __continue97 then
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
    EpisodeDesire = 0.95,
    DrillDesire = 1,
    Arrive = 200,
    TowerStandBack = 350,
    TowerClear = 50,
    AllyAnchorMax = 3000,
    MaxSecs = 40,
    PlainFountainHP = 0.5,
    ReadEvery = 0.1,
    OrderEvery = 0.3,
    DrillMinHP = 0.5,
    DrillSpotArrive = 150
}
--- Valve's fountain spots (as drill.ts); GetShopLocation(team, SHOP_HOME) is logged beside them at load.
local FOUNTAIN = {[Team.Radiant] = {-6619, -6336, 384}, [Team.Dire] = {6928, 6372, 392}}
local TOWER_IDS = {
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
local function enemyOf(team)
    return team == Team.Radiant and Team.Dire or Team.Radiant
end
local function r2(x)
    return math.floor(x * 100 + 0.5) / 100
end
function ____exports.Fountain(team)
    local x, y, z = unpack(FOUNTAIN[team])
    return Vector(x, y, z)
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
local function readOf(bot, st, now)
    if st.read ~= nil and st.readAt ~= nil and now - st.readAt < ____exports.SETTINGS.ReadEvery then
        return st.read
    end
    local here = bot:GetLocation()
    st.read = Threat.Read(
        bot,
        here,
        here,
        ____exports.SETTINGS.Horizon,
        {engagedWindow = ____exports.SETTINGS.EngagedWindow}
    )
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
--- Our standing towers that are not ahead of the hero: no nearer the enemy fountain than it, less TowerStandBack. Not our own
-- fountain's distance: in the safe lane our T1 is farther from our fountain than our pull camp (drill rtwalk1).
local function ownTowersBehind(bot)
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
            local __continue61
            repeat
                if not valid(a) or a == bot or a:IsIllusion() or RetreatState.Running(a) then
                    __continue61 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, a)
                if d < allyD then
                    ally = a
                    allyD = d
                end
                __continue61 = true
            until true
            if not __continue61 then
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
    RetreatState.SetRunning(bot, true)
    Chooser.Abort(bot, "retreat")
    Lane_.CampJobAbort(bot, "retreat")
    FarmPattern.Abort(bot, "retreat")
    local here = bot:GetLocation()
    local ____Telemetry_Event_5 = Telemetry.Event
    local ____array_4 = __TS__SparseArrayNew(
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
    local ____temp_3
    if #r.reach > 0 then
        ____temp_3 = r.escape
    else
        ____temp_3 = nil
    end
    __TS__SparseArrayPush(
        ____array_4,
        {"esc", ____temp_3},
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
    ____Telemetry_Event_5(
        "retreat",
        {__TS__SparseArraySpread(____array_4)}
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
--- The leave rule: lethal, a tower on us or the heal floor at once; over budget for the hero's reaction time.
local function leaveWhy(bot, st, r, budget, now)
    if r.band == "lethal" then
        return "lethal"
    end
    if ____exports.TowerOnUs(bot) ~= nil then
        return "tower"
    end
    if hpShare(bot) < ____exports.SETTINGS.HealFloor and #r.reach == 0 then
        return "heal"
    end
    if r.threat <= budget then
        st.overSince = nil
        st.stayLogged = nil
        return nil
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
        return nil
    end
    st.overSince = st.overSince or now
    return now - st.overSince >= Profile.Get(bot).reactBase and "threat" or nil
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
    local why = leaveWhy(
        bot,
        st,
        r,
        budget,
        now
    )
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
--- mode_farm_generic: none of ShouldRun's runs apply to a hero our retreat owns.
function ____exports.Owns(bot)
    return RetreatState.Owns(bot)
end
return ____exports
