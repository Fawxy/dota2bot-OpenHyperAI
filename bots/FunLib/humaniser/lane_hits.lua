--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
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
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local UnitType = ____dota.UnitType
local LaneRead = require(GetScriptDirectory().."/FunLib/humaniser/lane_read")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
--- The engine's attacker-index radius (engine lasthit QUERY_RADIUS): a reader farther from the creep misses its attackers.
____exports.READER_RADIUS = 1600
--- Seconds of forecast: past the longest wind-up plus flight (about 1.2 s) with room for a creep's repeats. `judgement`.
____exports.HORIZON = 3
local cache = {}
function ____exports.Reset()
    for k in pairs(cache) do
        cache[k] = nil
    end
end
local function dist(a, b)
    local p = a:GetLocation()
    local q = b:GetLocation()
    local dx = p.x - q.x
    local dy = p.y - q.y
    return math.sqrt(dx * dx + dy * dy)
end
--- The team's alive heroes (GetTeamMember answers for the calling script's team).
local function ownHeroes()
    local out = {}
    do
        local i = 1
        while i <= 5 do
            local h = GetTeamMember(i)
            if h ~= nil and h ~= nil and not h:IsNull() and h:IsAlive() and not h:IsIllusion() then
                out[#out + 1] = h
            end
            i = i + 1
        end
    end
    return out
end
--- The heroes within READER_RADIUS of the creep, nearest first.
local function inRange(heroes, creep)
    local out = {}
    for ____, h in ipairs(heroes) do
        local d = dist(h, creep)
        if d <= ____exports.READER_RADIUS then
            out[#out + 1] = {h, d}
        end
    end
    __TS__ArraySort(
        out,
        function(____, a, b) return a[2] - b[2] end
    )
    return __TS__ArrayMap(
        out,
        function(____, x) return x[1] end
    )
end
local function attacking(h, creep)
    return h:GetAttackTarget() == creep
end
--- The creep's forecast and its reader: see the header for who reads and how the reader's own hits are filled in.
local function forecastOf(verbs, cands, creep)
    local reader = cands[1]
    for ____, h in ipairs(cands) do
        if not attacking(h, creep) then
            reader = h
            break
        end
    end
    local function read(h)
        return verbs.hpForecast(h, creep, ____exports.HORIZON)
    end
    local f = read(reader)
    local other = __TS__ArrayFind(
        cands,
        function(____, h) return h ~= reader end
    )
    if attacking(reader, creep) and other ~= nil then
        local function own(x)
            return x.attacker == reader
        end
        local hits = __TS__ArrayFilter(
            f.hits,
            function(____, x) return not own(x) end
        )
        for ____, x in ipairs(read(other).hits) do
            if own(x) then
                hits[#hits + 1] = x
            end
        end
        __TS__ArraySort(
            hits,
            function(____, a, b) return a.t - b.t end
        )
        f.hits = hits
    end
    return {reader, f}
end
local function heroHits(f, team)
    local out = {}
    for ____, h in ipairs(f.hits) do
        do
            local __continue29
            repeat
                if h.by ~= "hero" and h.by ~= "self" then
                    __continue29 = true
                    break
                end
                local a = h.attacker
                out[#out + 1] = {
                    pid = a:GetPlayerID(),
                    ours = a:GetTeam() == team,
                    t = h.t,
                    commit = h.commit,
                    damage = h.damage
                }
                __continue29 = true
            until true
            if not __continue29 then
                break
            end
        end
    end
    return out
end
local function build(team, lane, verbs)
    local heroes = ownHeroes()
    local rows = {}
    if #heroes == 0 then
        return rows
    end
    local sides = {
        {
            true,
            LaneRead.ByLane(
                GetUnitList(UnitType.AlliedCreeps),
                false
            )[lane]
        },
        {
            false,
            LaneRead.ByLane(
                GetUnitList(UnitType.EnemyCreeps),
                true
            )[lane]
        }
    }
    for ____, ____value in ipairs(sides) do
        local own = ____value[1]
        local placed = ____value[2]
        for ____, p in ipairs(placed) do
            do
                local __continue35
                repeat
                    local cands = inRange(heroes, p.unit)
                    if #cands == 0 then
                        __continue35 = true
                        break
                    end
                    local reader, f = unpack(forecastOf(verbs, cands, p.unit))
                    rows[#rows + 1] = {
                        creep = p.unit,
                        own = own,
                        hp = f.hp,
                        reader = reader:GetPlayerID(),
                        forecast = f,
                        heroes = heroHits(f, team)
                    }
                    __continue35 = true
                until true
                if not __continue35 then
                    break
                end
            end
        end
    end
    return rows
end
--- The lane's creeps with the hits coming at them, for `team` (the calling script's team), read once a frame; empty while
-- the engine bundle is not loaded.
function ____exports.Read(team, lane)
    local key = (tostring(team) .. ":") .. tostring(lane)
    local now = DotaTime()
    local c = cache[key]
    if c ~= nil and c.at == now then
        return c.rows
    end
    local verbs = Tasks.Verbs()
    local rows = verbs == nil and ({}) or build(team, lane, verbs)
    cache[key] = {at = now, rows = rows}
    return rows
end
--- The read's row for one creep, if the lane lists it this frame.
function ____exports.Of(team, lane, creep)
    for ____, r in ipairs(____exports.Read(team, lane)) do
        if r.creep == creep then
            return r
        end
    end
    return nil
end
--- The hit the forecast says kills the creep (the first at which its HP, every hit to then counted and the unknown-phase hits
-- spread as lastHit's belief does, is 0 or less), else undefined.
function ____exports.KillingHit(r)
    local verbs = Tasks.Verbs()
    if verbs == nil then
        return nil
    end
    for ____, h in ipairs(r.forecast.hits) do
        if verbs.forecastHp(r.forecast, h.t) <= 0 then
            return h
        end
    end
    return nil
end
return ____exports
