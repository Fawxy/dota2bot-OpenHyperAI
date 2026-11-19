--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end

local __TS__Symbol, Symbol
do
    local symbolMetatable = {__tostring = function(self)
        return ("Symbol(" .. (self.description or "")) .. ")"
    end}
    function __TS__Symbol(description)
        return setmetatable({description = description}, symbolMetatable)
    end
    Symbol = {
        asyncDispose = __TS__Symbol("Symbol.asyncDispose"),
        dispose = __TS__Symbol("Symbol.dispose"),
        iterator = __TS__Symbol("Symbol.iterator"),
        hasInstance = __TS__Symbol("Symbol.hasInstance"),
        species = __TS__Symbol("Symbol.species"),
        toStringTag = __TS__Symbol("Symbol.toStringTag")
    }
end

local __TS__Iterator
do
    local function iteratorGeneratorStep(self)
        local co = self.____coroutine
        local status, value = coroutine.resume(co)
        if not status then
            error(value, 0)
        end
        if coroutine.status(co) == "dead" then
            return
        end
        return true, value
    end
    local function iteratorIteratorStep(self)
        local result = self:next()
        if result.done then
            return
        end
        return true, result.value
    end
    local function iteratorStringStep(self, index)
        index = index + 1
        if index > #self then
            return
        end
        return index, string.sub(self, index, index)
    end
    function __TS__Iterator(iterable)
        if type(iterable) == "string" then
            return iteratorStringStep, iterable, 0
        elseif iterable.____coroutine ~= nil then
            return iteratorGeneratorStep, iterable
        elseif iterable[Symbol.iterator] then
            local iterator = iterable[Symbol.iterator](iterable)
            return iteratorIteratorStep, iterator
        else
            return ipairs(iterable)
        end
    end
end

local Map
do
    Map = __TS__Class()
    Map.name = "Map"
    function Map.prototype.____constructor(self, entries)
        self[Symbol.toStringTag] = "Map"
        self.items = {}
        self.size = 0
        self.nextKey = {}
        self.previousKey = {}
        if entries == nil then
            return
        end
        local iterable = entries
        if iterable[Symbol.iterator] then
            local iterator = iterable[Symbol.iterator](iterable)
            while true do
                local result = iterator:next()
                if result.done then
                    break
                end
                local value = result.value
                self:set(value[1], value[2])
            end
        else
            local array = entries
            for ____, kvp in ipairs(array) do
                self:set(kvp[1], kvp[2])
            end
        end
    end
    function Map.prototype.clear(self)
        self.items = {}
        self.nextKey = {}
        self.previousKey = {}
        self.firstKey = nil
        self.lastKey = nil
        self.size = 0
    end
    function Map.prototype.delete(self, key)
        local contains = self:has(key)
        if contains then
            self.size = self.size - 1
            local next = self.nextKey[key]
            local previous = self.previousKey[key]
            if next ~= nil and previous ~= nil then
                self.nextKey[previous] = next
                self.previousKey[next] = previous
            elseif next ~= nil then
                self.firstKey = next
                self.previousKey[next] = nil
            elseif previous ~= nil then
                self.lastKey = previous
                self.nextKey[previous] = nil
            else
                self.firstKey = nil
                self.lastKey = nil
            end
            self.nextKey[key] = nil
            self.previousKey[key] = nil
        end
        self.items[key] = nil
        return contains
    end
    function Map.prototype.forEach(self, callback)
        for ____, key in __TS__Iterator(self:keys()) do
            callback(nil, self.items[key], key, self)
        end
    end
    function Map.prototype.get(self, key)
        return self.items[key]
    end
    function Map.prototype.has(self, key)
        return self.nextKey[key] ~= nil or self.lastKey == key
    end
    function Map.prototype.set(self, key, value)
        local isNewValue = not self:has(key)
        if isNewValue then
            self.size = self.size + 1
        end
        self.items[key] = value
        if self.firstKey == nil then
            self.firstKey = key
            self.lastKey = key
        elseif isNewValue then
            self.nextKey[self.lastKey] = key
            self.previousKey[key] = self.lastKey
            self.lastKey = key
        end
        return self
    end
    Map.prototype[Symbol.iterator] = function(self)
        return self:entries()
    end
    function Map.prototype.entries(self)
        local items = self.items
        local nextKey = self.nextKey
        local key = self.firstKey
        return {
            [Symbol.iterator] = function(self)
                return self
            end,
            next = function(self)
                local result = {done = not key, value = {key, items[key]}}
                key = nextKey[key]
                return result
            end
        }
    end
    function Map.prototype.keys(self)
        local nextKey = self.nextKey
        local key = self.firstKey
        return {
            [Symbol.iterator] = function(self)
                return self
            end,
            next = function(self)
                local result = {done = not key, value = key}
                key = nextKey[key]
                return result
            end
        }
    end
    function Map.prototype.values(self)
        local items = self.items
        local nextKey = self.nextKey
        local key = self.firstKey
        return {
            [Symbol.iterator] = function(self)
                return self
            end,
            next = function(self)
                local result = {done = not key, value = items[key]}
                key = nextKey[key]
                return result
            end
        }
    end
    Map[Symbol.species] = Map
end

local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
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
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
local SpellReady = require(GetScriptDirectory().."/FunLib/humaniser/spell_ready")
____exports.SETTINGS = {
    MissingAfter = 3,
    MissingSpeed = 330,
    MissingReachMax = 4000,
    MissingMargin = 600,
    EarlyWeight = 0.2,
    LateWeight = 0.5,
    EarlyUntil = 240,
    DepthFactor = {{0.5, 1}, {0.65, 0.25}, {1.01, 0.1}},
    DepthDefault = 0.5,
    DistFactor = {{2000, 1}, {3000, 0.5}, {math.huge, 0.25}},
    GateHorizon = 4,
    MissingRefuse = 0.5,
    VisionCut = true,
    WalkStep = 300,
    BurstWindow = 3,
    TowerReach = 868,
    WReach = 0.25,
    WMissing = 0.3,
    WTower = 0.4,
    WBurst = 0.5,
    WAlly = 0.15,
    Watch = 0.25,
    Pressured = 0.5,
    EscapeItems = {"item_blink", "item_force_staff", "item_tpscroll"},
    EscapeMargin = 100,
    EngagedRecent = 1,
    StandBurst = 1,
    StayHorizon = 2,
    StayEngaged = 6,
    LogEvery = 5
}
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
local MAX_PLAYER_ID = 23
local speeds = {}
local frames = {}
local logged = {}
function ____exports.ResetCache()
    speeds = {}
    logged = {}
    frames = {}
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
local function valid(u)
    return u ~= nil and u ~= nil and u:IsAlive() and not u:IsIllusion()
end
local T1_IDS = {Tower.Top1, Tower.Mid1, Tower.Bot1}
--- A team's standing towers among `ids`, in `ids` order.
local function standing(team, ids)
    local out = {}
    for ____, id in ipairs(ids) do
        local tw = GetTower(team, id)
        if valid(tw) then
            out[#out + 1] = tw
        end
    end
    return out
end
local function nearestOf(at, place)
    local best
    for ____, a in ipairs(at) do
        local d = dist(a, place)
        if best == nil or d < best then
            best = d
        end
    end
    return best
end
local function stepFactor(steps, v)
    for ____, ____value in ipairs(steps) do
        local edge = ____value[1]
        local f = ____value[2]
        if v < edge then
            return f
        end
    end
    return steps[#steps][2]
end
--- The walk's points every WalkStep, and the place (the vision cut looks at each).
function ____exports.WalkPoints(from, place)
    local d = dist(from, place)
    local n = math.max(
        1,
        math.ceil(d / ____exports.SETTINGS.WalkStep)
    )
    local out = {}
    do
        local i = 0
        while i <= n do
            out[#out + 1] = Vector(from.x + (place.x - from.x) * i / n, from.y + (place.y - from.y) * i / n, place.z)
            i = i + 1
        end
    end
    return out
end
--- Some walk point within `r` of `at` is out of our sight.
local function unseenWithin(points, at, r)
    for ____, p in ipairs(points) do
        if dist(p, at) <= r and not IsLocationVisible(p) then
            return true
        end
    end
    return false
end
local function itemReady(bot, name)
    local slot = bot:FindItemSlot(name)
    if slot < 0 or slot > 5 then
        return false
    end
    local item = bot:GetItemInSlot(slot)
    return item ~= nil and item ~= nil and item:IsFullyCastable()
end
--- The last movement speed Read saw for an enemy hero (the missing belief's run uses it), or undefined.
function ____exports.SeenSpeed(pid)
    return speeds[pid]
end
function ____exports.BandOf(threat, lethal)
    if lethal then
        return "lethal"
    end
    return threat >= ____exports.SETTINGS.Pressured and "pressured" or (threat >= ____exports.SETTINGS.Watch and "watch" or "none")
end
local function fixedOf(team, now)
    local cached = frames[team]
    if cached ~= nil and cached.t == now then
        return cached
    end
    local enemyTeam = team == Team.Radiant and Team.Dire or Team.Radiant
    local allies = {}
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue31
            repeat
                if not valid(a) then
                    __continue31 = true
                    break
                end
                local at = a:GetLocation()
                if at == nil or at == nil then
                    __continue31 = true
                    break
                end
                allies[#allies + 1] = {
                    u = a,
                    pid = a:GetPlayerID(),
                    at = at,
                    sp = a:GetCurrentMovementSpeed(),
                    range = a:GetAttackRange(),
                    hull = a:GetBoundingRadius()
                }
                __continue31 = true
            until true
            if not __continue31 then
                break
            end
        end
    end
    local enemyTowers = standing(enemyTeam, TOWER_IDS)
    local enemyTowerAt = __TS__ArrayMap(
        enemyTowers,
        function(____, tw) return tw:GetLocation() end
    )
    local function depthAt(t, all)
        local t1 = __TS__ArrayMap(
            standing(t, T1_IDS),
            function(____, tw) return tw:GetLocation() end
        )
        return #t1 > 0 and t1 or (all or __TS__ArrayMap(
            standing(t, TOWER_IDS),
            function(____, tw) return tw:GetLocation() end
        ))
    end
    local enemyPids = {}
    do
        local pid = 0
        while pid <= MAX_PLAYER_ID do
            do
                local __continue39
                repeat
                    local t = GetTeamForPlayer(pid)
                    if t == team or t ~= Team.Radiant and t ~= Team.Dire or not IsHeroAlive(pid) then
                        __continue39 = true
                        break
                    end
                    enemyPids[#enemyPids + 1] = pid
                    __continue39 = true
                until true
                if not __continue39 then
                    break
                end
            end
            pid = pid + 1
        end
    end
    local f = {
        team = team,
        t = now,
        enemies = __TS__New(Map),
        allies = allies,
        enemyTowers = enemyTowers,
        enemyTowerAt = enemyTowerAt,
        enemyTowerReach = {},
        ownDepthAt = depthAt(team, nil),
        enemyDepthAt = depthAt(enemyTeam, enemyTowerAt),
        enemyPids = enemyPids,
        sightings = {}
    }
    frames[team] = f
    return f
end
local function enemyOf(f, e)
    local cached = f.enemies:get(e)
    if cached ~= nil then
        local ____temp_0
        if cached == false then
            ____temp_0 = nil
        else
            ____temp_0 = cached
        end
        return ____temp_0
    end
    if not valid(e) or not e:CanBeSeen() then
        f.enemies:set(e, false)
        return nil
    end
    local x = {
        u = e,
        pid = e:GetPlayerID(),
        at = e:GetLocation(),
        sp = e:GetCurrentMovementSpeed(),
        range = e:GetAttackRange(),
        hull = e:GetBoundingRadius()
    }
    f.enemies:set(e, x)
    return x
end
local function sightingOf(f, pid)
    local s = f.sightings[pid]
    if s == nil then
        s = GetHeroLastSeenInfo(pid)[1] or false
        f.sightings[pid] = s
    end
    local ____temp_1
    if s == false then
        ____temp_1 = nil
    else
        ____temp_1 = s
    end
    return ____temp_1
end
--- The reads for `bot` with `horizon` seconds ahead, as a function of the walk (`from` to `place`). What does not depend on the
-- walk (who is seen and where, the standing towers, the unseen heroes' sightings, an escape item) is read from the game once,
-- here, so a caller weighing several places in one frame (the lane spot) pays for the heroes and towers once; the part no hero's
-- perception changes is read once per team and frame (`TeamFrame`). Use it within
-- the frame it was made in. `lethal` fires when the heroes in reach can deal the bot's HP within the burst window, they
-- outnumber our heroes in reach and the bot has no `escape`.
-- 
-- The missing belief: per alive enemy hero unseen for more than MissingAfter, its possible run since the sighting (its last
-- read speed, capped) plus MissingMargin; one whose run touches the walk, with some of that reach out of our sight
-- (VisionCut), adds EarlyWeight or LateWeight by game minute, scaled by the place prior (DepthFactor for the place's depth,
-- DistFactor for its last-seen distance to the place). Walks player ids with GetTeamForPlayer (GetTeamPlayers is empty for
-- a bot-only team). A hero the API has no sighting of is not placed and not counted.
function ____exports.Reader(bot, horizon, opts)
    local s = ____exports.SETTINGS
    local now = DotaTime()
    local team = bot:GetTeam()
    local hull = bot:GetBoundingRadius()
    local window = opts and opts.window or math.min(horizon, s.BurstWindow)
    local fixed = fixedOf(team, now)
    local visible = {}
    local enemies = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue47
            repeat
                local f = enemyOf(fixed, e)
                if f == nil then
                    __continue47 = true
                    break
                end
                visible[f.pid] = true
                if f.sp ~= nil and f.sp > 0 then
                    speeds[f.pid] = f.sp
                end
                if f.at == nil or f.at == nil then
                    __continue47 = true
                    break
                end
                enemies[#enemies + 1] = {u = e, pid = f.pid, at = f.at, run = f.sp * horizon + f.range + f.hull + hull}
                __continue47 = true
            until true
            if not __continue47 then
                break
            end
        end
    end
    local allies = {}
    for ____, a in ipairs(fixed.allies) do
        do
            local __continue52
            repeat
                if a.u == bot or RetreatState.Running(a.u) then
                    __continue52 = true
                    break
                end
                allies[#allies + 1] = {u = a.u, pid = a.pid, at = a.at, run = a.sp * horizon + a.range + a.hull + hull}
                __continue52 = true
            until true
            if not __continue52 then
                break
            end
        end
    end
    local enemyTowers = fixed.enemyTowers
    local enemyTowerAt = fixed.enemyTowerAt
    local enemyTowerReach = fixed.enemyTowerReach
    local ownDepthAt = fixed.ownDepthAt
    local enemyDepthAt = fixed.enemyDepthAt
    local unseen = {}
    for ____, pid in ipairs(fixed.enemyPids) do
        do
            local __continue55
            repeat
                if visible[pid] == true or pid == (opts and opts.exclude) then
                    __continue55 = true
                    break
                end
                local info = sightingOf(fixed, pid)
                if info == nil or info.time_since_seen <= s.MissingAfter then
                    __continue55 = true
                    break
                end
                unseen[#unseen + 1] = {
                    pid = pid,
                    at = info.location,
                    tss = info.time_since_seen,
                    r = math.min((speeds[pid] or s.MissingSpeed) * info.time_since_seen, s.MissingReachMax) + s.MissingMargin
                }
                __continue55 = true
            until true
            if not __continue55 then
                break
            end
        end
    end
    local early = now < s.EarlyUntil and s.EarlyWeight or s.LateWeight
    local hp = math.max(
        1,
        bot:GetHealth()
    )
    local escapeItem
    return function(from, place)
        local reach = {}
        local chasers = {}
        local eng = {}
        local att = {}
        local rows = {}
        local dmg = 0
        for ____, e in ipairs(enemies) do
            do
                local __continue60
                repeat
                    if distToSegment(e.at, from, place) > e.run then
                        __continue60 = true
                        break
                    end
                    reach[#reach + 1] = e.pid
                    chasers[#chasers + 1] = e.u
                    if e.dmg == nil then
                        local w = window
                        if (opts and opts.engagedWindow) ~= nil then
                            e.att = e.u:GetAttackTarget() == bot
                            e.eng = bot:WasRecentlyDamagedByHero(e.u, s.EngagedRecent)
                            if e.eng then
                                w = opts.engagedWindow
                            end
                        end
                        e.dmg = SpellReady.DamageOn(e.u, bot, w)
                    end
                    if e.att == true then
                        att[#att + 1] = e.pid
                    end
                    if e.eng == true then
                        eng[#eng + 1] = e.pid
                    end
                    rows[#rows + 1] = {
                        pid = e.pid,
                        dmg = e.dmg,
                        eng = e.eng == true,
                        at = e.at,
                        run = e.run
                    }
                    dmg = dmg + e.dmg
                    __continue60 = true
                until true
                if not __continue60 then
                    break
                end
            end
        end
        local near = 0
        for ____, a in ipairs(allies) do
            if distToSegment(a.at, place, place) <= a.run then
                near = near + 1
            end
        end
        local own = nearestOf(ownDepthAt, place)
        local en = nearestOf(enemyDepthAt, place)
        local depth = (own == nil or en == nil or own + en <= 0) and s.DepthDefault or en / (own + en)
        local base = early * stepFactor(s.DepthFactor, depth)
        local missing = 0
        local mcut = 0
        local mtss
        local mpids = {}
        local points
        for ____, m in ipairs(unseen) do
            do
                local __continue71
                repeat
                    if distToSegment(m.at, from, place) > m.r then
                        __continue71 = true
                        break
                    end
                    if s.VisionCut then
                        points = points or ____exports.WalkPoints(from, place)
                        if not unseenWithin(points, m.at, m.r) then
                            mcut = mcut + 1
                            __continue71 = true
                            break
                        end
                    end
                    missing = missing + base * stepFactor(
                        s.DistFactor,
                        dist(m.at, place)
                    )
                    mpids[#mpids + 1] = m.pid
                    mtss = math.max(mtss or 0, m.tss)
                    __continue71 = true
                until true
                if not __continue71 then
                    break
                end
            end
        end
        local tower = false
        do
            local i = 0
            while i < #enemyTowers and not tower do
                local r = enemyTowerReach[i + 1]
                if r == nil then
                    r = WorldFacts.TowerReach(enemyTowers[i + 1], s.TowerReach)
                    enemyTowerReach[i + 1] = r
                end
                tower = dist(enemyTowerAt[i + 1], place) <= r
                i = i + 1
            end
        end
        local escape = true
        if #chasers > 0 then
            if escapeItem == nil then
                escapeItem = false
                for ____, name in ipairs(s.EscapeItems) do
                    if itemReady(bot, name) then
                        escapeItem = true
                    end
                end
            end
            if not escapeItem then
                local ours = bot:GetCurrentMovementSpeed()
                for ____, e in ipairs(chasers) do
                    if e:GetCurrentMovementSpeed() >= ours or GetUnitToUnitDistance(bot, e) - e:GetAttackRange() - e:GetBoundingRadius() - hull < s.EscapeMargin then
                        escape = false
                        break
                    end
                end
            end
        end
        local burst = dmg / hp
        local raw = s.WReach * #reach + s.WMissing * missing + (tower and s.WTower or 0) + s.WBurst * math.min(1, burst) - s.WAlly * near
        local threat = math.max(
            0,
            math.min(1, raw)
        )
        local lethal = burst >= 1 and #reach > near and not escape
        return {
            t = now,
            from = from,
            place = place,
            horizon = horizon,
            depth = depth,
            reach = reach,
            burst = burst,
            allies = near,
            escape = escape,
            tower = tower,
            missing = missing,
            mpids = mpids,
            mtss = mtss,
            mcut = mcut,
            threat = threat,
            band = ____exports.BandOf(threat, lethal),
            eng = eng,
            att = att,
            rows = rows
        }
    end
end
--- One read: `bot` walking from `from` to `place` with `horizon` seconds ahead (see Reader).
function ____exports.Read(bot, from, place, horizon, opts)
    return ____exports.Reader(bot, horizon, opts)(from, place)
end
local gateCut
--- The gate's fixture cut for one logged gate decision (safe_gather.ts `TripGate` calls it after `Log`). A fault in the cut is swallowed.
function ____exports.NoteGateCut(bot, from, place, consumer)
    if gateCut ~= nil then
        pcall(
            gateCut,
            bot,
            from,
            place,
            consumer
        )
    end
end
--- cut.ts registers the gate's fixture cut here (it imports this module, so the module cannot import it); called after each logged gate decision.
function ____exports.SetGateCut(fn)
    gateCut = fn
end
local function r2(x)
    return math.floor(x * 100 + 0.5) / 100
end
--- ev=threat for one consumer's decision on a read: on a changed decision, else at most once per LogEvery per hero and
-- consumer (gates run every think; the design's "once per decision" would flood). Returns whether it logged.
function ____exports.Log(bot, consumer, r, decision)
    local pid = bot:GetPlayerID()
    local key = (tostring(pid) .. ":") .. consumer
    local last = logged[key]
    if last ~= nil and last.decision == decision and r.t - last.t < ____exports.SETTINGS.LogEvery then
        return false
    end
    logged[key] = {t = r.t, decision = decision}
    local ____Telemetry_Event_10 = Telemetry.Event
    local ____array_9 = __TS__SparseArrayNew(
        {"pid", pid},
        {"who", consumer},
        {"dec", decision},
        {
            "x",
            math.floor(r.place.x)
        },
        {
            "y",
            math.floor(r.place.y)
        },
        {
            "hz",
            r2(r.horizon)
        },
        {
            "dep",
            r2(r.depth)
        },
        {
            "threat",
            r2(r.threat)
        },
        {"band", r.band},
        {"reach", #r.reach},
        {
            "rpid",
            #r.reach > 0 and table.concat(r.reach, ",") or nil
        },
        {
            "burst",
            r2(r.burst)
        },
        {"ally", r.allies}
    )
    local ____temp_8
    if #r.reach > 0 then
        ____temp_8 = r.escape
    else
        ____temp_8 = nil
    end
    __TS__SparseArrayPush(
        ____array_9,
        {"esc", ____temp_8},
        {"tower", r.tower},
        {
            "miss",
            r2(r.missing)
        },
        {
            "mpid",
            #r.mpids > 0 and table.concat(r.mpids, ",") or nil
        },
        {
            "mtss",
            r.mtss ~= nil and math.floor(r.mtss + 0.5) or nil
        },
        {"mcut", r.mcut > 0 and r.mcut or nil},
        {
            "hp",
            r2(bot:GetHealth() / math.max(
                1,
                bot:GetMaxHealth()
            ))
        }
    )
    ____Telemetry_Event_10(
        "threat",
        {__TS__SparseArraySpread(____array_9)}
    )
    return true
end
return ____exports
