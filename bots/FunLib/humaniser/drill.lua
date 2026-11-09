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
local overrides, sentryAttack, controlRep, Customize
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local GameState = ____dota.GameState
local Team = ____dota.Team
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
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
            local __continue32
            repeat
                if not h:IsAlive() then
                    __continue32 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h) - h:GetBoundingRadius()
                if d <= reach and d < bestD then
                    best = h
                    bestD = d
                end
                __continue32 = true
            until true
            if not __continue32 then
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
    ["drag-melee"] = {
        note = "Radiant pos3 lane-only with lane aggro, the feed refused (ForceLever r:top=none), Dire pos5 a statue in its lane (top), everyone else benched",
        cast = {r = {3}},
        statue = {d = {5}},
        others = "bench",
        castLaneOnly = true,
        laneAggro = true,
        rep = {every = 30, from = 0},
        overrides = {ForceLever = "r:top=none"}
    },
    ["drag-sentry"] = {
        note = "Radiant pos3 lane-only with lane aggro, the feed refused (ForceLever r:top=none), Dire pos5 a sentry in its lane (top), everyone else benched",
        cast = {r = {3}},
        sentry = {d = {5}},
        others = "bench",
        castLaneOnly = true,
        laneAggro = true,
        rep = {every = 30, from = 0},
        overrides = {ForceLever = "r:top=none"}
    },
    ["drag-ranged"] = {
        note = "Radiant pos2 lane-only with lane aggro, the feed refused (ForceLever r:mid=none), Dire pos2 a statue in mid, everyone else benched",
        cast = {r = {2}},
        statue = {d = {2}},
        others = "bench",
        castLaneOnly = true,
        laneAggro = true,
        rep = {every = 30, from = 0},
        overrides = {ForceLever = "r:mid=none"}
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
        d.laneOnly,
        bot:GetTeam(),
        pos
    ) then
        return "laneonly"
    end
    return d.others
end
--- Benched, a statue or a sentry: the hero holds farm mode above every other mode, takes the drill's step and never casts.
function ____exports.Held(bot)
    local r = ____exports.RoleOf(bot)
    return r == "bench" or r == "statue" or r == "sentry"
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
local FOUNTAIN = {[Team.Radiant] = {-6619, -6336, 384}, [Team.Dire] = {6928, 6372, 392}}
local STATUE_BEHIND = -300
local STATUE_SWAY = 40
local statueSide = {}
--- A sentry answers an enemy hero within its attack range + both bounding radii + this many seconds of its own movement, and
-- never leaves its spot by more than that movement: a laner stepping in to hit someone who walked into it. The same 0.5 s
-- as the contest price's STEP_IN on purpose: this step grades the price's damage and time terms on its own zone; a sentry
-- that chases further is a later step. `judgement`.
____exports.SENTRY_STEP = 0.5
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
    if r == "bench" then
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
            local ____opt_15 = overrides()
            local v = ____opt_15 and ____opt_15[k]
            if v ~= nil and v ~= false and v ~= -1 then
                Telemetry.Event("drill", {{"ph", "removed"}, {"name", k}})
            end
        end
    end
    local name = ____exports.Name()
    if name == nil then
        local ____opt_17 = overrides()
        local asked = ____opt_17 and ____opt_17.Drill
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
    removedLogged = false
end
return ____exports
