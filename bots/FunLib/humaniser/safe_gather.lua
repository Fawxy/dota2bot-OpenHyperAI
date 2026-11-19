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
local Safe = require(GetScriptDirectory().."/FunLib/humaniser/safe")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
____exports.SETTINGS = {
    LanerSeen = 10,
    UnseenAfter = 0.5,
    Window = 2,
    MaxGap = 1,
    CutEvery = 2
}
local function r1(v)
    return math.floor(v * 10 + 0.5) / 10
end
local function r2(v)
    return math.floor(v * 100 + 0.5) / 100
end
local function n0(v)
    return math.floor(v + 0.5)
end
local function b01(b)
    return b and 1 or 0
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
local function distToSegment(p, a, b)
    local vx = b.x - a.x
    local vy = b.y - a.y
    local len2 = vx * vx + vy * vy
    local u = len2 > 0 and math.max(
        0,
        math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2)
    ) or 0
    return math.sqrt((p.x - (a.x + u * vx)) ^ 2 + (p.y - (a.y + u * vy)) ^ 2)
end
local samplers = {}
--- One frame's HP drop against the last sample, split equally between the sources whose damage flag covers the gap (a hero, a
-- creep, a tower). A drop with no flag is not counted (burn, fall damage, an unflagged source); a rise is ignored. Called by
-- `Shadow` before it reads the landing; a second call in the same frame does nothing.
function ____exports.Sample(bot, now)
    local pid = bot:GetPlayerID()
    local hp = bot:GetHealth()
    local s = samplers[pid]
    if s == nil or now < s.t then
        samplers[pid] = {hp = hp, t = now, ring = {}}
        return
    end
    if now == s.t then
        return
    end
    local dt = now - s.t
    local drop = s.hp - hp
    s.hp = hp
    s.t = now
    local keep = {}
    for ____, x in ipairs(s.ring) do
        if now - x.t <= ____exports.SETTINGS.Window then
            keep[#keep + 1] = x
        end
    end
    s.ring = keep
    if dt > ____exports.SETTINGS.MaxGap or drop <= 0 then
        return
    end
    local w = math.max(dt, 0.1)
    local hero = bot:WasRecentlyDamagedByAnyHero(w)
    local creeps = bot:WasRecentlyDamagedByCreep(w)
    local tower = bot:WasRecentlyDamagedByTower(w)
    local n = b01(hero) + b01(creeps) + b01(tower)
    if n == 0 then
        return
    end
    local share = drop / n
    keep[#keep + 1] = {t = now, hero = hero and share or 0, creeps = creeps and share or 0, tower = tower and share or 0}
end
--- HP a second lost to each source over the last `Window` seconds, from the samples taken so far.
function ____exports.Landing(bot, now)
    local out = {hero = 0, creeps = 0, tower = 0}
    local s = samplers[bot:GetPlayerID()]
    if s == nil then
        return out
    end
    for ____, x in ipairs(s.ring) do
        do
            local __continue18
            repeat
                if now - x.t > ____exports.SETTINGS.Window then
                    __continue18 = true
                    break
                end
                out.hero = out.hero + x.hero
                out.creeps = out.creeps + x.creeps
                out.tower = out.tower + x.tower
                __continue18 = true
            until true
            if not __continue18 then
                break
            end
        end
    end
    out.hero = out.hero / ____exports.SETTINGS.Window
    out.creeps = out.creeps / ____exports.SETTINGS.Window
    out.tower = out.tower / ____exports.SETTINGS.Window
    return out
end
--- Per bot, per enemy pid: the damage it could deal us when it last reached us, and when.
local laners = {}
--- Records this read's reachers and returns the lane opponents that reached us within `LanerSeen`, are not visible now and could
-- have run to the walk since their last sighting (the missing belief's run: the speed the read last saw, capped, plus its margin).
local function lanerRows(bot, r)
    local pid = bot:GetPlayerID()
    local mine = laners[pid] or ({})
    laners[pid] = mine
    local now = DotaTime()
    local visible = {}
    for ____, row in ipairs(r.rows) do
        visible[row.pid] = true
        mine[row.pid] = {dmg = row.dmg, at = now}
    end
    local out = {}
    for k, c in pairs(mine) do
        do
            local __continue24
            repeat
                if c == nil or visible[k] == true then
                    __continue24 = true
                    break
                end
                if now - c.at > ____exports.SETTINGS.LanerSeen then
                    mine[k] = nil
                    __continue24 = true
                    break
                end
                if not IsHeroAlive(k) then
                    __continue24 = true
                    break
                end
                local info = GetHeroLastSeenInfo(k)[1]
                if info == nil or info.time_since_seen <= ____exports.SETTINGS.UnseenAfter then
                    __continue24 = true
                    break
                end
                local run = math.min(
                    (Threat.SeenSpeed(k) or Threat.SETTINGS.MissingSpeed) * info.time_since_seen,
                    Threat.SETTINGS.MissingReachMax
                ) + Threat.SETTINGS.MissingMargin
                if distToSegment(info.location, r.from, r.place) > run then
                    __continue24 = true
                    break
                end
                out[#out + 1] = {pid = k, hitting = false, dmg = c.dmg, unseen = true}
                __continue24 = true
            until true
            if not __continue24 then
                break
            end
        end
    end
    return out
end
local towerSeen = {}
--- A live enemy tower whose reach holds `bot` is attacking it or hit it in the last half second: retreat's `TowerOnUs` test
-- written again here, since retreat imports this module (a require cycle). Read once a frame per hero.
local function towerOnMe(bot, now)
    local pid = bot:GetPlayerID()
    local seen = towerSeen[pid]
    if seen ~= nil and seen.t == now then
        return seen.on
    end
    local on = false
    local br = bot:GetBoundingRadius()
    for ____, tw in ipairs(bot:GetNearbyTowers(1200, true) or ({})) do
        do
            local __continue32
            repeat
                if not tw:IsAlive() then
                    __continue32 = true
                    break
                end
                if GetUnitToUnitDistance(bot, tw) > WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) + br then
                    __continue32 = true
                    break
                end
                if tw:GetAttackTarget() == bot or bot:WasRecentlyDamagedByTower(0.5) then
                    on = true
                    break
                end
                __continue32 = true
            until true
            if not __continue32 then
                break
            end
        end
    end
    towerSeen[pid] = {t = now, on = on}
    return on
end
--- `Safe.Inputs` from a read the consumer made this frame (no second read; a consumer that caches its read for a fraction of a second
-- passes the cached one, and the clock here is the game's now, not the read's `t`). `hitting` is the read's `eng`, so it is only set when
-- the read was made with `engagedWindow`; a gate's read (no window) has none hitting and every row at the short window.
-- `exit`: the longest, over the reachers, of the seconds for the hero to walk straight away from where it stands to the edge of
-- that hero's reach (its `run`: speed x the read's horizon + attack range + both hulls), at our current speed. A hero already
-- outside a row's reach adds 0, and an unseen lane row has no place to measure from. Logged only.
function ____exports.FromRead(bot, r, opts)
    local reach = {}
    for ____, row in ipairs(r.rows) do
        reach[#reach + 1] = {pid = row.pid, hitting = row.eng, dmg = row.dmg}
    end
    local exit = 0
    if #r.rows > 0 then
        local here = bot:GetLocation()
        local speed = math.max(
            1,
            bot:GetCurrentMovementSpeed()
        )
        for ____, row in ipairs(r.rows) do
            exit = math.max(
                exit,
                math.max(
                    0,
                    row.run - dist(here, row.at)
                ) / speed
            )
        end
    end
    for ____, l in ipairs(lanerRows(bot, r)) do
        reach[#reach + 1] = l
    end
    local ____temp_1 = bot:GetHealth()
    local ____temp_2 = bot:GetMaxHealth()
    local ____reach_3 = reach
    local ____r_missing_4 = r.missing
    local ____r_tower_5 = r.tower
    local ____towerOnMe_result_6 = towerOnMe(
        bot,
        DotaTime()
    )
    local ____exports_Landing_result_7 = ____exports.Landing(
        bot,
        DotaTime()
    )
    local ____temp_8 = #r.rows > 0 and exit or nil
    local ____opts_away_9 = opts.away
    local ____opts_held_10 = opts.held
    local ____temp_0
    if type(opts.hold) == "function" then
        ____temp_0 = opts.hold()
    else
        ____temp_0 = opts.hold
    end
    return {
        hp = ____temp_1,
        hpMax = ____temp_2,
        reach = ____reach_3,
        missing = ____r_missing_4,
        tower = ____r_tower_5,
        towerOnMe = ____towerOnMe_result_6,
        landing = ____exports_Landing_result_7,
        exit = ____temp_8,
        away = ____opts_away_9,
        held = ____opts_held_10,
        hold = ____temp_0
    }
end
--- The `ev=cut kind=safe` fields (tools/hlog/cut.js reads them back into Inputs; the place is `pl`).
function ____exports.CutFields(pid, who, place, i, a)
    local rows = {}
    for ____, x in ipairs(i.reach) do
        rows[#rows + 1] = table.concat(
            {
                x.pid,
                b01(x.hitting),
                n0(x.dmg),
                b01(x.unseen == true)
            },
            ","
        )
    end
    return {
        {"pid", pid},
        {"kind", "safe"},
        {"who", who},
        {
            "pl",
            (tostring(n0(place.x)) .. ",") .. tostring(n0(place.y))
        },
        {
            "hpa",
            n0(i.hp)
        },
        {
            "hpm",
            n0(i.hpMax)
        },
        {
            "rr",
            #rows > 0 and table.concat(rows, ";") or nil
        },
        {
            "mi",
            r2(i.missing)
        },
        {
            "stw",
            (tostring(b01(i.tower)) .. ",") .. tostring(b01(i.towerOnMe))
        },
        {
            "ld",
            (((tostring(r2(i.landing.hero)) .. ",") .. tostring(r2(i.landing.creeps))) .. ",") .. tostring(r2(i.landing.tower))
        },
        {
            "ex",
            i.exit ~= nil and r1(i.exit) or nil
        },
        {
            "awy",
            b01(i.away)
        },
        {
            "hld",
            b01(i.held)
        },
        {
            "hd",
            b01(i.hold)
        },
        {"lv", a.level},
        {
            "kill",
            n0(a.kill)
        },
        {
            "ra",
            a.kill > 0 and r2(a.ratio) or nil
        },
        {
            "pr",
            r2(a.price)
        },
        {"why", a.reason}
    }
end
local cutState = {}
local function shadow(bot, who, r, opts)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true or not bot:IsAlive() then
        return
    end
    ____exports.Sample(
        bot,
        DotaTime()
    )
    local i = ____exports.FromRead(bot, r, opts)
    local a = Safe.Decide(i)
    local key = (a.level .. ":") .. a.reason
    local id = (tostring(bot:GetPlayerID()) .. ":") .. who
    local now = DotaTime()
    local last = cutState[id]
    if last ~= nil and last.key == key and (now - last.at < ____exports.SETTINGS.CutEvery or #i.reach == 0 and a.price <= 0) then
        return
    end
    cutState[id] = {key = key, at = now}
    Telemetry.Event(
        "cut",
        ____exports.CutFields(
            bot:GetPlayerID(),
            who,
            r.place,
            i,
            a
        )
    )
end
--- The shadow of one consumer's question: the safe-here answer for the read it made, logged as `ev=cut kind=safe who=<who>` when the
-- level or reason changes, else every `CutEvery` s while a hero is in reach or the landing price is over 0. The answer is not
-- returned: nothing can act on it, and a fault inside is reported as ev=lua_error and dropped.
function ____exports.Shadow(bot, who, r, opts)
    local ok, err = pcall(
        shadow,
        bot,
        who,
        r,
        opts
    )
    if not ok then
        Telemetry.Failed("SafeGather.Shadow", err)
    end
end
--- Per game (the other caches' reset): the sampler, the lane memory and the shadow's cadence.
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(samplers)) do
        __TS__Delete(samplers, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(laners)) do
        __TS__Delete(laners, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(towerSeen)) do
        __TS__Delete(towerSeen, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(cutState)) do
        __TS__Delete(cutState, k)
    end
end
--- Threat.Gate's call (a trip: the walk leaves our creeps and tower; the gate holds nothing). index.ts registers it with `Threat.SetGateShadow`.
function ____exports.GateShadow(bot, consumer, r)
    ____exports.Shadow(bot, consumer, r, {away = true, held = false, hold = false})
end
____exports._test = {samplers = samplers, laners = laners, cutState = cutState}
return ____exports
