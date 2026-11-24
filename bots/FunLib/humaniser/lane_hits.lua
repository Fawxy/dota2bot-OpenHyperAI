--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
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
local function nearestReader(heroes, creep)
    local best
    local bestD = ____exports.READER_RADIUS
    for ____, h in ipairs(heroes) do
        local d = dist(h, creep)
        if d <= bestD then
            bestD = d
            best = h
        end
    end
    return best
end
local function heroHits(f, team)
    local out = {}
    for ____, h in ipairs(f.hits) do
        do
            local __continue13
            repeat
                if h.by ~= "hero" and h.by ~= "self" then
                    __continue13 = true
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
                __continue13 = true
            until true
            if not __continue13 then
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
                local __continue19
                repeat
                    local reader = nearestReader(heroes, p.unit)
                    if reader == nil then
                        __continue19 = true
                        break
                    end
                    local f = verbs.hpForecast(reader, p.unit, ____exports.HORIZON)
                    rows[#rows + 1] = {
                        creep = p.unit,
                        own = own,
                        hp = f.hp,
                        reader = reader:GetPlayerID(),
                        forecast = f,
                        heroes = heroHits(f, team)
                    }
                    __continue19 = true
                until true
                if not __continue19 then
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
