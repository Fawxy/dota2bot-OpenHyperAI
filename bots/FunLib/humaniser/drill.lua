--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
local overrides, spotPoint, noteSpot, behindOwnT1, endLinger, lingerPoint, nearbyHero, startLinger, lingerTick, chase, sentryAttack, controlRep, Customize, FOUNTAIN, STATUE_BEHIND, lastSpot, SPOT_OFFSET, CHASER_WAIT_BEHIND, LINGER_HP, LINGER_SECS, LINGER_DIST, LINGER_STANDOFF_SLACK, TOWER_REACH_FALLBACK, LINGER_TOWER_MARGIN, lingering, lingered
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local GameState = ____dota.GameState
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
function overrides()
    return Customize.Overrides
end
--- The active drill's name, or undefined (no drill, or a name the table does not hold).
function ____exports.Name()
    local ____opt_0 = overrides()
    local n = ____opt_0 and ____opt_0.Drill
    return type(n) == "string" and ____exports.TABLE[n] ~= nil and n or nil
end
--- The active drill's entry, or undefined.
function ____exports.Active()
    local n = ____exports.Name()
    local ____temp_2
    if n == nil then
        ____temp_2 = nil
    else
        ____temp_2 = ____exports.TABLE[n]
    end
    return ____temp_2
end
--- A statue's spot for the current rep (`lane` before the first rep or without a spot list).
function ____exports.SpotOf(bot)
    local d = ____exports.Active()
    local pos = LaneConfig.PositionOf(bot)
    local ____temp_29
    if pos ~= nil then
        local ____temp_28
        if bot:GetTeam() == Team.Radiant then
            local ____opt_20 = d and d.spots
            ____temp_28 = ____opt_20 and ____opt_20.r
        else
            local ____opt_24 = d and d.spots
            ____temp_28 = ____opt_24 and ____opt_24.d
        end
        ____temp_29 = ____temp_28 and ____temp_28[pos]
    else
        ____temp_29 = nil
    end
    local list = ____temp_29
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
    local side, kind = string.match(spot, "^pull:([rd]):(%a+)$")
    if side == nil or kind ~= "safe" and kind ~= "off" then
        return nil
    end
    local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
    local team = side == "r" and Team.Radiant or Team.Dire
    local camp = Camps.PullCampsFor(
        team,
        Camps.LaneOfKind(team, kind)
    )[1]
    local ____temp_30
    if camp ~= nil then
        ____temp_30 = Camps.SpawnerByIdx(camp.campIdx)
    else
        ____temp_30 = nil
    end
    local s = ____temp_30
    if s == nil then
        return nil
    end
    local c = Camps.BoxCenter(s)
    local lane = GetLaneFrontLocation(
        team,
        Camps.LaneOfKind(team, kind),
        0
    )
    return Camps.StandPoint(
        s,
        Vector(2 * c.x - lane.x, 2 * c.y - lane.y, c.z),
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
                math.floor(st.dmin)
            },
            {
                "dmax",
                math.floor(st.dmax)
            },
            {
                "dend",
                dnow ~= nil and math.floor(dnow) or nil
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
    local share = target:GetHealth() / math.max(
        1,
        target:GetMaxHealth()
    )
    if lingered[pid] == rep or share > LINGER_HP then
        return false
    end
    local d = GetUnitToUnitDistance(bot, target)
    lingered[pid] = rep
    lingering[pid] = {
        rep = rep,
        tgo = DotaTime(),
        tpid = target:GetPlayerID(),
        dmin = d,
        dmax = d,
        clamp = 0
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
    local target = nearbyHero(bot, st.tpid)
    if target == nil then
        endLinger(
            bot,
            IsHeroAlive(st.tpid) and "lost" or "died"
        )
        return false
    end
    local now = DotaTime()
    local dd = GetUnitToUnitDistance(bot, target)
    st.dmin = math.min(st.dmin, dd)
    st.dmax = math.max(st.dmax, dd)
    if st.t0 == nil then
        if dd >= LINGER_DIST - LINGER_STANDOFF_SLACK then
            st.t0 = now
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
                        math.floor(target:GetHealth() / math.max(
                            1,
                            target:GetMaxHealth()
                        ) * 100 + 0.5) / 100
                    },
                    {
                        "d",
                        math.floor(dd)
                    }
                }
            )
        elseif now - st.tgo >= LINGER_SECS then
            endLinger(bot, "no_standoff", dd)
            return false
        end
    elseif dd <= bot:GetAttackRange() + 100 then
        endLinger(bot, "contact", dd)
        return false
    elseif now - st.t0 >= LINGER_SECS then
        endLinger(bot, "timeout", dd)
        return false
    end
    local p, clamp = unpack(lingerPoint(bot, target, spot))
    if clamp == 1 then
        st.clamp = 1
    end
    if GetUnitToLocationDistance(bot, p) > 50 then
        bot:Action_MoveToLocation(p)
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
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, BotMode.None) or ({})) do
        do
            local __continue71
            repeat
                if not h:IsAlive() or GetUnitToLocationDistance(h, spot) > ____exports.CHASE_RANGE then
                    __continue71 = true
                    break
                end
                local dd = GetUnitToUnitDistance(bot, h)
                if dd < bestD then
                    best = h
                    bestD = dd
                end
                __continue71 = true
            until true
            if not __continue71 then
                break
            end
        end
    end
    local st = lingering[bot:GetPlayerID()]
    if st ~= nil and st.rep ~= ____exports.RepAt(DotaTime()) then
        endLinger(bot, "rep_end")
    end
    local ____opt_31 = ____exports.Active()
    if (____opt_31 and ____opt_31.linger) == true then
        if best ~= nil and lingering[bot:GetPlayerID()] == nil then
            startLinger(bot, best)
        end
        if lingerTick(bot, spot) then
            return true
        end
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
            local __continue89
            repeat
                if not h:IsAlive() then
                    __continue89 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h) - h:GetBoundingRadius()
                if d <= reach and d < bestD then
                    best = h
                    bestD = d
                end
                __continue89 = true
            until true
            if not __continue89 then
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
function controlRep(d, n)
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
--- The drill table. Names match dotactl's recipes.json `drills`. A slice whose drill has no entry adds it here (and a
-- recipe when it needs reset steps or a later `--until`).
____exports.TABLE = {
    ["lane-spot"] = {
        note = "Radiant pos1 lane-only, everyone else benched",
        cast = SAFE_CORE,
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    ["lane-spot-statue"] = {
        note = "Radiant pos1 lane-only, Dire pos3 a statue in its lane, everyone else benched",
        cast = SAFE_CORE,
        statue = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    ["lane-spot-duel"] = {
        note = "Radiant pos1 and Dire pos3 lane-only, everyone else benched",
        cast = {r = {1}, d = {3}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
    },
    ["lane-spot-sentry"] = {
        note = "Radiant pos1 lane-only, Dire pos3 a sentry in its lane (a statue that attacks an enemy hero inside its zone), everyone else benched",
        cast = SAFE_CORE,
        sentry = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0}
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
    ["lane-still"] = {note = "every hero benched; the controller's forecast against untouched waves", cast = {}, others = "bench", rep = {every = 30, from = 0}},
    pull = {
        note = "Radiant pos5 pulls each minute's wave, a statue otherwise; the :30 wave unpulled (control); everyone else benched",
        cast = {r = {5}},
        others = "bench",
        castIdle = "statue",
        rep = {every = 30, from = 60, control = 2},
        forces = "pull"
    },
    ["core-pull"] = {
        note = "Radiant pos3 pulls its hard camp each minute's wave, a statue otherwise; the :30 wave unpulled; everyone else benched",
        cast = {r = {3}},
        others = "bench",
        castIdle = "statue",
        rep = {every = 30, from = 60, control = 2},
        forces = "pull"
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
    ["shove-statue"] = {
        note = "Radiant pos1 lane-only in a forced shove (ForceShove r:bot), Dire pos3 a statue in the lane, everyone else benched",
        cast = SAFE_CORE,
        statue = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0},
        overrides = {ForceShove = "r:bot"}
    },
    hold = {
        note = "Radiant pos5 pulls each minute's wave, a statue otherwise; Radiant pos1 lane-only with the wave hold; the :30 wave unpulled; everyone else benched",
        cast = {r = {5}},
        laneOnly = {r = {1}},
        laneHold = true,
        others = "bench",
        castIdle = "statue",
        rep = {every = 30, from = 60, control = 2},
        forces = "pull"
    },
    shove = {
        note = "Radiant pos1 lane-only in a forced shove (ForceShove r:bot), everyone else benched",
        cast = SAFE_CORE,
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0},
        overrides = {ForceShove = "r:bot"}
    },
    ["lever-setup"] = {
        note = "Radiant pos1 lane-only, the setup forced every wave (ForceLever r:bot=setup), everyone else benched",
        cast = SAFE_CORE,
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0},
        overrides = {ForceLever = "r:bot=setup"}
    },
    ["lever-none"] = {
        note = "Radiant pos1 lane-only, no lever every wave (ForceLever r:bot=none; lever-setup's control), everyone else benched",
        cast = SAFE_CORE,
        others = "bench",
        castLaneOnly = true,
        rep = {every = 30, from = 0},
        overrides = {ForceLever = "r:bot=none"}
    },
    ["feed-every"] = {
        note = "Radiant pos1 lane-only with lane aggro, the lane controller live, Dire pos3 a sentry in the lane, everyone else benched",
        cast = SAFE_CORE,
        sentry = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        laneAggro = true,
        rep = {every = 30, from = 0}
    },
    ["lever-feed"] = {
        note = "Radiant pos1 lane-only with lane aggro, the feed forced every wave (ForceLever r:bot=feed), Dire pos3 a statue in the lane (the feed orders an attack on a visible enemy hero), everyone else benched",
        cast = SAFE_CORE,
        statue = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        laneAggro = true,
        rep = {every = 30, from = 0},
        overrides = {ForceLever = "r:bot=feed"}
    },
    ["threat-missing"] = {
        note = "Radiant pos3 lane-only in its lane; Dire pos5 a statue at a spot per rep (by the pos3's pull camp, bench, Dire offlane camp, its lane); everyone else benched",
        cast = {r = {3}},
        statue = {d = {5}},
        spots = {d = {[5] = {"pull:r:off", "bench", "pull:d:off", "lane"}}},
        others = "bench",
        castLaneOnly = true,
        rep = {every = 90, from = 30}
    },
    ["lever-feed-off"] = {
        note = "Radiant pos1 lane-only with lane aggro, no lever every wave (ForceLever r:bot=none; lever-feed's control), Dire pos3 a statue in the lane, everyone else benched",
        cast = SAFE_CORE,
        statue = {d = {3}},
        others = "bench",
        castLaneOnly = true,
        laneAggro = true,
        rep = {every = 30, from = 0},
        overrides = {ForceLever = "r:bot=none"}
    }
}
local function listed(s, team, pos)
    if s == nil or pos == nil then
        return false
    end
    local ____temp_3
    if team == Team.Radiant then
        ____temp_3 = s.r
    else
        ____temp_3 = s.d
    end
    local list = ____temp_3
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
    return d.others
end
--- Benched, a statue, a sentry or a chaser: the hero holds farm mode above every other mode, takes the drill's step and never casts.
function ____exports.Held(bot)
    local r = ____exports.RoleOf(bot)
    return r == "bench" or r == "statue" or r == "sentry" or r == "chaser"
end
--- Lane-only: the cast of an entry with `castLaneOnly`, or another hero under `others: "laneonly"`.
function ____exports.LaneOnly(bot)
    local r = ____exports.RoleOf(bot)
    local d = ____exports.Active()
    return d ~= nil and (r == "cast" and d.castLaneOnly == true or r == "laneonly")
end
--- A lane-only hero of an entry with `laneHold`: the wave hold may act for it.
function ____exports.LaneHold(bot)
    local ____opt_4 = ____exports.Active()
    return (____opt_4 and ____opt_4.laneHold) == true and ____exports.LaneOnly(bot)
end
--- A lane-only hero of an entry with `laneAggro`: lane aggro's draws may act for it.
function ____exports.LaneAggro(bot)
    local ____opt_6 = ____exports.Active()
    return (____opt_6 and ____opt_6.laneAggro) == true and ____exports.LaneOnly(bot)
end
--- An Overrides key the active drill implies, or undefined.
function ____exports.Implied(key)
    local ____opt_10 = ____exports.Active()
    local ____opt_8 = ____opt_10 and ____opt_10.overrides
    return ____opt_8 and ____opt_8[key]
end
FOUNTAIN = {[Team.Radiant] = {-6619, -6336, 384}, [Team.Dire] = {6928, 6372, 392}}
STATUE_BEHIND = -300
local STATUE_SWAY = 40
local statueSide = {}
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
    local ____opt_12 = ____exports.Active()
    return (____opt_12 and ____opt_12.castIdle) == "statue" and ____exports.RoleOf(bot) == "cast"
end
--- The one chooser job a cast may run (the forced context, for an entry with `castIdle`), or undefined: every job.
function ____exports.ForcedJob(bot)
    local d = ____exports.Active()
    local ____temp_14
    if d ~= nil and d.castIdle ~= nil and ____exports.RoleOf(bot) == "cast" then
        ____temp_14 = d.forces
    else
        ____temp_14 = nil
    end
    return ____temp_14
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
    if r == "chaser" and d ~= nil and not controlRep(
        d,
        ____exports.RepAt(DotaTime())
    ) and ____exports.RepAt(DotaTime()) > 0 then
        return chase(bot)
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
        local x, y, z = unpack(FOUNTAIN[bot:GetTeam()])
        local f = Vector(x, y, z)
        if GetUnitToLocationDistance(bot, f) > 300 then
            bot:Action_MoveToLocation(f)
        end
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
    local ____temp_17 = r == "statue"
    if ____temp_17 then
        local ____opt_15 = ____exports.Active()
        ____temp_17 = (____opt_15 and ____opt_15.spots) ~= nil
    end
    if ____temp_17 then
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
    local ____opt_33 = ____exports.Active()
    local list = ____opt_33 and ____opt_33.castSpots
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
            local ____opt_35 = overrides()
            local v = ____opt_35 and ____opt_35[k]
            if v ~= nil and v ~= false and v ~= -1 then
                Telemetry.Event("drill", {{"ph", "removed"}, {"name", k}})
            end
        end
    end
    local name = ____exports.Name()
    if name == nil then
        local ____opt_37 = overrides()
        local asked = ____opt_37 and ____opt_37.Drill
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
    if role ~= "cast" then
        return
    end
    local now = DotaTime()
    local rep = ____exports.RepAt(now)
    local team = bot:GetTeam()
    if rep == 0 or lastRep[team] == rep then
        return
    end
    lastRep[team] = rep
    local start = d.rep.from + (rep - 1) * d.rep.every
    Telemetry.Event(
        "drill",
        {
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
        }
    )
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
    removedLogged = false
end
return ____exports
