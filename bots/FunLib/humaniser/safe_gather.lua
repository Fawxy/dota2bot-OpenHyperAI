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
local distToSegment, lanerRows, towerOnMe, enemyTowers, creepHitsOf, drawnAt, pressed, exitFrame, pressedBy, exitDamage, drawnField, cutOn, log, frameReader, ask, r1, r2, n0, b01, dist, samplers, laners, towerSeen, towerFacts, TOWER_IDS, pressSeen, exitSeen, cutState, frames
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Safe = require(GetScriptDirectory().."/FunLib/humaniser/safe")
local SpellReady = require(GetScriptDirectory().."/FunLib/humaniser/spell_ready")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
function distToSegment(p, a, b)
    local vx = b.x - a.x
    local vy = b.y - a.y
    local len2 = vx * vx + vy * vy
    local u = len2 > 0 and math.max(
        0,
        math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2)
    ) or 0
    return math.sqrt((p.x - (a.x + u * vx)) ^ 2 + (p.y - (a.y + u * vy)) ^ 2)
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
            local __continue20
            repeat
                if now - x.t > ____exports.SETTINGS.Window then
                    __continue20 = true
                    break
                end
                out.hero = out.hero + x.hero
                out.creeps = out.creeps + x.creeps
                out.tower = out.tower + x.tower
                __continue20 = true
            until true
            if not __continue20 then
                break
            end
        end
    end
    out.hero = out.hero / ____exports.SETTINGS.Window
    out.creeps = out.creeps / ____exports.SETTINGS.Window
    out.tower = out.tower / ____exports.SETTINGS.Window
    return out
end
function lanerRows(bot, r)
    local pid = bot:GetPlayerID()
    local mine = laners[pid] or ({})
    laners[pid] = mine
    local now = DotaTime()
    local visible = {}
    local here = bot:GetLocation()
    local own = dist(r.from, here) <= ____exports.SETTINGS.OwnPlace and dist(r.place, here) <= ____exports.SETTINGS.OwnPlace
    for ____, row in ipairs(r.rows) do
        visible[row.pid] = true
        if own then
            mine[row.pid] = {dmg = row.dmg, at = now}
        end
    end
    local out = {}
    for k, c in pairs(mine) do
        do
            local __continue27
            repeat
                if c == nil or visible[k] == true then
                    __continue27 = true
                    break
                end
                if now - c.at > ____exports.SETTINGS.LanerSeen then
                    mine[k] = nil
                    __continue27 = true
                    break
                end
                if not IsHeroAlive(k) then
                    __continue27 = true
                    break
                end
                local info = GetHeroLastSeenInfo(k)[1]
                if info == nil or info.time_since_seen <= ____exports.SETTINGS.UnseenAfter then
                    __continue27 = true
                    break
                end
                local run = math.min(
                    (Threat.SeenSpeed(k) or Threat.SETTINGS.MissingSpeed) * info.time_since_seen,
                    Threat.SETTINGS.MissingReachMax
                ) + Threat.SETTINGS.MissingMargin
                if distToSegment(info.location, r.from, r.place) > run then
                    __continue27 = true
                    break
                end
                out[#out + 1] = {pid = k, hitting = false, dmg = c.dmg, unseen = true}
                __continue27 = true
            until true
            if not __continue27 then
                break
            end
        end
    end
    return out
end
function towerOnMe(bot, now, place)
    local pid = bot:GetPlayerID()
    local seen = towerSeen[pid]
    if seen == nil or seen.t ~= now then
        seen = {t = now, on = {}}
        local br = bot:GetBoundingRadius()
        local here = bot:GetLocation()
        for ____, tw in ipairs(bot:GetNearbyTowers(1200, true) or ({})) do
            do
                local __continue35
                repeat
                    if not tw:IsAlive() then
                        __continue35 = true
                        break
                    end
                    local at = tw:GetLocation()
                    local reach = WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach) + br
                    if dist(at, here) > reach then
                        __continue35 = true
                        break
                    end
                    if tw:GetAttackTarget() == bot or bot:WasRecentlyDamagedByTower(0.5) then
                        local ____seen_on_0 = seen.on
                        ____seen_on_0[#____seen_on_0 + 1] = {at = at, reach = reach}
                    end
                    __continue35 = true
                until true
                if not __continue35 then
                    break
                end
            end
        end
        towerSeen[pid] = seen
    end
    for ____, tw in ipairs(seen.on) do
        if dist(tw.at, place) <= tw.reach then
            return true
        end
    end
    return false
end
--- Pure: a tower's damage on us over `window` s from the moment it would be on us. `hit` is one attack's damage on us, `spa` its seconds per attack;
-- `onUs`: it targets us now. Else it turns to us when our lane creeps in its reach are dead: `creepHits`, the attacks it needs to kill them
-- (0: none there). Other damage on those creeps is not counted, so the turn can come sooner than read.
function ____exports.TowerDrawn(hit, spa, onUs, creepHits, window)
    local from = onUs and 0 or creepHits * spa
    return hit / math.max(spa, 0.1) * math.max(0, window - from)
end
function enemyTowers(bot, now)
    local team = bot:GetTeam()
    local seen = towerFacts[team]
    if seen == nil or seen.t ~= now then
        seen = {t = now, towers = {}}
        local enemy = team == Team.Radiant and Team.Dire or Team.Radiant
        for ____, id in ipairs(TOWER_IDS) do
            do
                local __continue46
                repeat
                    local tw = GetTower(enemy, id)
                    if tw == nil or tw == nil or tw:IsNull() or not tw:IsAlive() then
                        __continue46 = true
                        break
                    end
                    local ____this_2
                    ____this_2 = tw
                    local ____opt_1 = ____this_2.GetSecondsPerAttack
                    local spa = ____opt_1 and ____opt_1(____this_2)
                    local ____seen_towers_3 = seen.towers
                    ____seen_towers_3[#____seen_towers_3 + 1] = {
                        unit = tw,
                        at = tw:GetLocation(),
                        reach = WorldFacts.TowerReach(tw, Threat.SETTINGS.TowerReach),
                        dmg = tw:GetAttackDamage(),
                        spa = spa ~= nil and spa > 0 and spa or 1
                    }
                    __continue46 = true
                until true
                if not __continue46 then
                    break
                end
            end
        end
        towerFacts[team] = seen
    end
    return seen.towers
end
function creepHitsOf(tw)
    if tw.creepHits ~= nil then
        return tw.creepHits
    end
    local hits = 0
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps) or ({})) do
        do
            local __continue51
            repeat
                if c == nil or c:IsNull() or not c:IsAlive() or not LaneState.IsLaneCreepName(c:GetUnitName()) then
                    __continue51 = true
                    break
                end
                if dist(
                    c:GetLocation(),
                    tw.at
                ) > tw.reach + c:GetBoundingRadius() then
                    __continue51 = true
                    break
                end
                hits = hits + math.ceil(c:GetHealth() / math.max(
                    1,
                    c:GetActualIncomingDamage(tw.dmg, DamageType.Physical)
                ))
                __continue51 = true
            until true
            if not __continue51 then
                break
            end
        end
    end
    tw.creepHits = hits
    return hits
end
function drawnAt(bot, now, place)
    local out = {}
    local br = bot:GetBoundingRadius()
    for ____, tw in ipairs(enemyTowers(bot, now)) do
        do
            local __continue56
            repeat
                if dist(tw.at, place) > tw.reach + br then
                    __continue56 = true
                    break
                end
                local onUs = tw.unit:GetAttackTarget() == bot
                local dmg = ____exports.TowerDrawn(
                    bot:GetActualIncomingDamage(tw.dmg, DamageType.Physical),
                    tw.spa,
                    onUs,
                    onUs and 0 or creepHitsOf(tw),
                    ____exports.SETTINGS.KillWindow
                )
                if dmg > 0 then
                    out[#out + 1] = {src = "tower", dmg = dmg}
                end
                __continue56 = true
            until true
            if not __continue56 then
                break
            end
        end
    end
    return out
end
function pressed(bot, now)
    local pid = bot:GetPlayerID()
    local seen = pressSeen[pid]
    if seen ~= nil and seen.t == now then
        return seen.on
    end
    local on = bot:WasRecentlyDamagedByAnyHero(____exports.SETTINGS.PressWindow)
    pressSeen[pid] = {t = now, on = on}
    return on
end
function exitFrame(bot, now)
    local pid = bot:GetPlayerID()
    local seen = exitSeen[pid]
    if seen == nil or seen.t ~= now then
        seen = {t = now, dmg = {}, by = {}}
        exitSeen[pid] = seen
    end
    return seen
end
function pressedBy(bot, e, now)
    local seen = exitFrame(bot, now)
    local pid = e:GetPlayerID()
    local on = seen.by[pid]
    if on == nil then
        on = bot:WasRecentlyDamagedByHero(e, ____exports.SETTINGS.PressWindow)
        seen.by[pid] = on
    end
    return on
end
function exitDamage(bot, e, w, now)
    local seen = exitFrame(bot, now)
    local key = (tostring(e:GetPlayerID()) .. ":") .. tostring(w)
    local dmg = seen.dmg[key]
    if dmg == nil then
        dmg = SpellReady.DamageOn(e, bot, w)
        seen.dmg[key] = dmg
    end
    return dmg
end
--- `Safe.Inputs` from a read the consumer made this frame (no second read; a consumer that caches its read for a fraction of a second
-- passes the cached one, and the clock here is the game's now, not the read's `t`). `hitting` is the read's `eng`, so it is only set when
-- the read was made with `engagedWindow`; a gate's read (no window) has none hitting and every row at the short window.
-- `exit`: the longest, over the reachers, of the seconds for the hero to walk straight away from the walk's nearest point to that hero (the place itself for an own-place read) to the edge of
-- that hero's reach (its `run`: speed x the read's horizon + attack range + both hulls), at our current speed. A place already
-- outside a row's reach adds 0, and an unseen lane row has no place to measure from. With `Ours.ExitWindow` a visible hero that
-- is not hitting us that did not damage us within `PressWindow`
-- is counted over `exit` + `ExitTurn` when that is under `KillWindow` (never more than the read gave it; not on an `away` walk).
function ____exports.FromRead(bot, r, opts)
    local reach = {}
    local exit = 0
    if #r.rows > 0 then
        local speed = math.max(
            1,
            bot:GetCurrentMovementSpeed()
        )
        for ____, row in ipairs(r.rows) do
            exit = math.max(
                exit,
                math.max(
                    0,
                    row.run - distToSegment(row.at, r.from, r.place)
                ) / speed
            )
        end
    end
    local now = DotaTime()
    local w = Ours.On("ExitWindow") and not opts.away and math.ceil((exit + ____exports.SETTINGS.ExitTurn) * 2) / 2 or ____exports.SETTINGS.KillWindow
    for ____, row in ipairs(r.rows) do
        local capped = not row.eng and row.u ~= nil and w < ____exports.SETTINGS.KillWindow and not pressedBy(bot, row.u, now)
        reach[#reach + 1] = {
            pid = row.pid,
            hitting = row.eng,
            dmg = capped and math.min(
                row.dmg,
                exitDamage(bot, row.u, w, now)
            ) or row.dmg
        }
    end
    for ____, l in ipairs(lanerRows(bot, r)) do
        reach[#reach + 1] = l
    end
    local ____temp_5 = bot:GetHealth()
    local ____temp_6 = bot:GetMaxHealth()
    local ____reach_7 = reach
    local ____r_missing_8 = r.missing
    local ____r_tower_9 = r.tower
    local ____towerOnMe_result_10 = towerOnMe(
        bot,
        DotaTime(),
        r.place
    )
    local ____exports_Landing_result_11 = ____exports.Landing(
        bot,
        DotaTime()
    )
    local ____temp_12 = #r.rows > 0 and exit or nil
    local ____opts_away_13 = opts.away
    local ____opts_held_14 = opts.held
    local ____temp_4
    if type(opts.hold) == "function" then
        ____temp_4 = opts.hold()
    else
        ____temp_4 = opts.hold
    end
    return {
        hp = ____temp_5,
        hpMax = ____temp_6,
        reach = ____reach_7,
        missing = ____r_missing_8,
        tower = ____r_tower_9,
        towerOnMe = ____towerOnMe_result_10,
        landing = ____exports_Landing_result_11,
        exit = ____temp_12,
        away = ____opts_away_13,
        held = ____opts_held_14,
        hold = ____temp_4,
        pressed = not Ours.On("IdleBar") or pressed(
            bot,
            DotaTime()
        ),
        drawn = Ours.On("TowerRead") and drawnAt(bot, now, r.place) or nil
    }
end
function drawnField(drawn)
    local rows = {}
    for ____, d in ipairs(drawn) do
        rows[#rows + 1] = (d.src .. ",") .. tostring(n0(d.dmg))
    end
    return table.concat(rows, ";")
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
    local ____array_16 = __TS__SparseArrayNew(
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
        {
            "prs",
            b01(i.pressed == true)
        }
    )
    local ____temp_15
    if i.drawn == nil then
        ____temp_15 = nil
    else
        ____temp_15 = #i.drawn == 0 and "-" or drawnField(i.drawn)
    end
    __TS__SparseArrayPush(
        ____array_16,
        {"dr", ____temp_15},
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
    )
    return {__TS__SparseArraySpread(____array_16)}
end
function cutOn()
    return Telemetry.IsEnabled() and Telemetry.Get().Cut == true
end
function log(bot, who, place, i, a)
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
            place,
            i,
            a
        )
    )
end
function frameReader(bot, horizon, engaged, exclude)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local f = frames[pid]
    if f == nil or f.t ~= now then
        f = {t = now, readers = {}}
        frames[pid] = f
    end
    local key = (((tostring(horizon) .. ":") .. tostring(engaged and 1 or 0)) .. ":") .. tostring(exclude or "-")
    local rd = f.readers[key]
    if rd == nil then
        rd = Threat.Reader(bot, horizon, {engagedWindow = engaged and Threat.SETTINGS.StayEngaged or nil, exclude = exclude, window = ____exports.SETTINGS.KillWindow})
        f.readers[key] = rd
    end
    return rd
end
function ask(bot, place, opts)
    local horizon = opts and opts.horizon or (((opts and opts.held) == true or (opts and opts.hold) == true) and Threat.SETTINGS.StayHorizon or ____exports.SETTINGS.FreshHorizon)
    local from = opts and opts.from or bot:GetLocation()
    local ____frameReader_31 = frameReader
    local ____bot_30 = bot
    local ____temp_27 = opts and opts.engaged
    if ____temp_27 == nil then
        ____temp_27 = true
    end
    local r = ____frameReader_31(____bot_30, horizon, ____temp_27, opts and opts.exclude)(from, place)
    local ____exports_FromRead_42 = ____exports.FromRead
    local ____bot_41 = bot
    local ____temp_34 = opts and opts.away
    if ____temp_34 == nil then
        ____temp_34 = false
    end
    local ____temp_37 = opts and opts.held
    if ____temp_37 == nil then
        ____temp_37 = false
    end
    local ____temp_40 = opts and opts.hold
    if ____temp_40 == nil then
        ____temp_40 = false
    end
    local i = ____exports_FromRead_42(____bot_41, r, {away = ____temp_34, held = ____temp_37, hold = ____temp_40})
    local a = Safe.Decide(i)
    local who = opts and opts.who
    if who ~= nil and cutOn() and bot:IsAlive() then
        local ok, err = pcall(
            log,
            bot,
            who,
            place,
            i,
            a
        )
        if not ok then
            Telemetry.Failed("SafeGather.At", err)
        end
    end
    return {a = a, r = r}
end
____exports.SETTINGS = {
    PressWindow = 3,
    LanerSeen = 10,
    OwnPlace = 50,
    UnseenAfter = 0.5,
    Window = 2,
    MaxGap = 1,
    CutEvery = 2,
    FreshHorizon = 3,
    KillWindow = 4,
    ExitTurn = 1
}
r1 = function(v) return math.floor(v * 10 + 0.5) / 10 end
r2 = function(v) return math.floor(v * 100 + 0.5) / 100 end
n0 = function(v) return math.floor(v + 0.5) end
b01 = function(b) return b and 1 or 0 end
dist = function(a, b) return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2) end
samplers = {}
--- One frame's HP drop against the last sample, split equally between the sources whose damage flag covers the gap (a hero, a
-- creep, a tower). A drop with no flag is not counted (burn, fall damage, an unflagged source); a rise is ignored. A second
-- call with the same `now` does nothing.
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
--- The sampler's step, run once per hero per Humaniser tick (index.ts `steps.landing`, every `TickEvery`-th frame, 10 Hz), whether
-- or not telemetry is on. A lower rate loses the attribution: the damage flags cover only a short window (`MaxGap` = 1 s), so
-- samples further apart than that give no drop and the `landing` price reads 0 under real damage. A dead hero is not sampled
-- (its respawn would read as a rise and a death as a drop with a flag).
function ____exports.Tick(bot)
    if not bot:IsAlive() then
        return
    end
    ____exports.Sample(
        bot,
        DotaTime()
    )
end
laners = {}
towerSeen = {}
towerFacts = {}
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
pressSeen = {}
exitSeen = {}
cutState = {}
local function shadow(bot, who, r, opts)
    if not cutOn() or not bot:IsAlive() then
        return
    end
    local i = ____exports.FromRead(bot, r, opts)
    log(
        bot,
        who,
        r.place,
        i,
        Safe.Decide(i)
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
frames = {}
--- Can `bot` be killed walking to `place` (design section 3, "one way to ask"): the only call a consumer makes. Reads the walk on the frame's
-- shared reader (several places in one frame cost one unit scan), builds the inputs, returns `Safe.Decide`'s answer, and logs it as
-- `who` when asked. It works with telemetry off. An error in the read or the decision is not caught here: it reaches the caller's
-- own error path (the consumers run under the Humaniser's guards), since a made-up answer would be a decision nobody can see. A fault
-- in the logging alone is reported and dropped.
function ____exports.At(bot, place, opts)
    return ask(bot, place, opts).a
end
--- Per game (the other caches' reset): the sampler, the lane memory, the shared readers and the shadow's cadence.
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(frames)) do
        __TS__Delete(frames, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(samplers)) do
        __TS__Delete(samplers, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(laners)) do
        __TS__Delete(laners, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(towerSeen)) do
        __TS__Delete(towerSeen, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(towerFacts)) do
        __TS__Delete(towerFacts, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(pressSeen)) do
        __TS__Delete(pressSeen, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(exitSeen)) do
        __TS__Delete(exitSeen, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(cutState)) do
        __TS__Delete(cutState, k)
    end
end
--- The start gate every trip shares (a camp, a pull, a stack, a farm trip, a core's pull): `At` for the walk from `from` (default the hero's place) to
-- `place`, 4 s, `away`, not held, and no hold. Held on `deadly`, with the answer's reason (`kill`, `tower`, `unknown`). The read and its
-- decision are logged as ev=threat for `consumer` (with the gate's cut for the fixtures), and as ev=cut kind=safe under the same name.
function ____exports.TripGate(bot, place, consumer, from)
    local ____ask_result_45 = ask(bot, place, {
        from = from,
        horizon = ____exports.WalkHorizon,
        away = true,
        held = false,
        hold = false,
        who = consumer
    })
    local a = ____ask_result_45.a
    local r = ____ask_result_45.r
    local why = a.level == "deadly" and a.reason or nil
    if Threat.Log(bot, consumer, r, why or "go") then
        Threat.NoteGateCut(bot, r.from, r.place, consumer)
    end
    return {why = why, r = r, a = a}
end
--- The horizon (s) of a walk to a place away from here (a trip, a kill or join target, a joiner's walk): design section 3. Here is `Threat.SETTINGS.StayHorizon`, 2 s.
____exports.WalkHorizon = 4
____exports._test = {samplers = samplers, laners = laners, cutState = cutState, frames = frames}
return ____exports
