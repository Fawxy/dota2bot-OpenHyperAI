--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
local GameState = ____dota.GameState
local Lane = ____dota.Lane
local UnitType = ____dota.UnitType
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
____exports.DEFAULTS = {
    Enable = true,
    MaxPingAge = 3,
    RoshanRadius = 600,
    HeroRadius = 300,
    BuildingRadius = 700,
    SpotRadius = 800,
    Roshan = {Duration = 25, MaxResponders = 5},
    Attack = {Duration = 8, MaxResponders = 2, MaxDistance = 4000, AlsoWithin = 1600},
    Push = {Duration = 20, MaxResponders = 3},
    Defend = {Duration = 20, MaxResponders = 2, AlsoTpBeyond = 5000},
    Avoid = {Duration = 10, Radius = 1200, MinSeconds = 4, ClearSeconds = 2},
    Gather = {Duration = 8, MaxResponders = 2}
}
local function merge(defaults, overrides)
    if overrides == nil or overrides == nil or type(overrides) ~= "table" then
        return defaults
    end
    local result = {}
    for k, v in pairs(defaults) do
        result[k] = v
    end
    for k, v in pairs(overrides) do
        local d = defaults[k]
        local ____k_1 = k
        local ____temp_0
        if d ~= nil and type(d) == "table" and type(v) == "table" then
            ____temp_0 = merge(d, v)
        else
            ____temp_0 = v
        end
        result[____k_1] = ____temp_0
    end
    return result
end
local cached
function ____exports.Get()
    if cached == nil then
        cached = merge(
            ____exports.DEFAULTS,
            Config.Get().Pings
        )
    end
    return cached
end
--- True when the interpreter owns ping handling; legacy per-mode ping readers yield to it.
function ____exports.IsActive()
    return Config.IsFeatureEnabled("Pings")
end
--- The single place that decides whether a ping means "danger". The bot API documents normal_ping = false
-- as the danger/X ping, but OHA's push/defend code treats "not normal_ping" as "attack here", so this is
-- unverified. Flip here after the step-0 in-game check (docs/HUMANISER_DEV.md).
function ____exports.IsDangerPing(ping)
    return ping.normal_ping == false
end
local helpers
function ____exports.SetHelpers(h)
    helpers = h
end
function ____exports.GetHelpers()
    return helpers
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
--- Lane encoded in a building's unit name; the fort (and anything unnamed) counts as mid.
function ____exports.LaneFromBuildingName(name)
    if (string.find(name, "_top")) ~= nil then
        return Lane.Top
    end
    if (string.find(name, "_bot")) ~= nil then
        return Lane.Bot
    end
    return Lane.Mid
end
local function isLaneBuilding(name)
    if (string.find(name, "watch_tower")) ~= nil or (string.find(name, "fillers")) ~= nil then
        return false
    end
    return (string.find(name, "tower")) ~= nil or (string.find(name, "rax")) ~= nil or (string.find(name, "_fort")) ~= nil
end
local function nearestBuilding(list, loc, radius)
    local best
    local bestDist = radius
    for ____, unit in ipairs(GetUnitList(list)) do
        do
            local __continue19
            repeat
                if unit == nil or unit == nil or not unit:IsAlive() or not isLaneBuilding(unit:GetUnitName()) then
                    __continue19 = true
                    break
                end
                local d = dist2D(
                    unit:GetLocation(),
                    loc
                )
                if d <= bestDist then
                    best = unit
                    bestDist = d
                end
                __continue19 = true
            until true
            if not __continue19 then
                break
            end
        end
    end
    return best
end
function ____exports.NearestVisibleEnemyHero(loc, radius)
    local best
    local bestDist = radius
    for ____, unit in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue24
            repeat
                if unit == nil or unit == nil or not unit:IsAlive() or not unit:CanBeSeen() then
                    __continue24 = true
                    break
                end
                local d = dist2D(
                    unit:GetLocation(),
                    loc
                )
                if d <= bestDist then
                    best = unit
                    bestDist = d
                end
                __continue24 = true
            until true
            if not __continue24 then
                break
            end
        end
    end
    return best
end
local function nearReservedSpot(loc, radius)
    if helpers == nil then
        return false
    end
    for ____, spot in ipairs(helpers.reservedSpots()) do
        if dist2D(spot, loc) <= radius then
            return true
        end
    end
    return false
end
--- Classifies a ping by what is near it, in the spec's precedence order. Only reads state every bot on the
-- team sees identically. `issuerSmoked` widens GATHER/ATTACK to the whole team (moving out of a smoke).
function ____exports.Classify(issuerPID, ping, issuerSmoked)
    local cfg = ____exports.Get()
    local loc = ping.location
    local sourceKey = (("ping:" .. tostring(issuerPID)) .. ":") .. string.format("%.2f", ping.time)
    local base = {
        sourceKey = sourceKey,
        issuerPID = issuerPID,
        location = loc,
        delayKind = "ping",
        ackPing = true
    }
    if helpers ~= nil and dist2D(
        loc,
        helpers.roshanLocation()
    ) <= cfg.RoshanRadius then
        return {
            context = "roshan",
            spec = __TS__ObjectAssign(
                {},
                base,
                {
                    type = "ROSHAN",
                    location = helpers.roshanLocation(),
                    duration = cfg.Roshan.Duration,
                    maxResponders = cfg.Roshan.MaxResponders
                }
            )
        }
    end
    local hero = ____exports.NearestVisibleEnemyHero(loc, cfg.HeroRadius)
    if hero ~= nil then
        return {
            context = "enemy_hero",
            spec = __TS__ObjectAssign(
                {},
                base,
                {
                    type = "ATTACK",
                    target = hero,
                    location = hero:GetLocation(),
                    duration = cfg.Attack.Duration,
                    maxResponders = issuerSmoked and 5 or cfg.Attack.MaxResponders,
                    maxDistance = cfg.Attack.MaxDistance,
                    alsoWithin = cfg.Attack.AlsoWithin
                }
            )
        }
    end
    local enemyBuilding = nearestBuilding(UnitType.EnemyBuildings, loc, cfg.BuildingRadius)
    if enemyBuilding ~= nil then
        return {
            context = "enemy_building",
            spec = __TS__ObjectAssign(
                {},
                base,
                {
                    type = "PUSH",
                    lane = ____exports.LaneFromBuildingName(enemyBuilding:GetUnitName()),
                    location = enemyBuilding:GetLocation(),
                    duration = cfg.Push.Duration,
                    maxResponders = cfg.Push.MaxResponders
                }
            )
        }
    end
    local ownBuilding = nearestBuilding(UnitType.AlliedBuildings, loc, cfg.BuildingRadius)
    if ownBuilding ~= nil then
        return {
            context = "own_building",
            spec = __TS__ObjectAssign(
                {},
                base,
                {
                    type = "DEFEND",
                    lane = ____exports.LaneFromBuildingName(ownBuilding:GetUnitName()),
                    location = ownBuilding:GetLocation(),
                    duration = cfg.Defend.Duration,
                    maxResponders = cfg.Defend.MaxResponders,
                    alsoTpBeyond = cfg.Defend.AlsoTpBeyond
                }
            )
        }
    end
    if nearReservedSpot(loc, cfg.SpotRadius) then
        return {context = "reserved_spot"}
    end
    if ____exports.IsDangerPing(ping) then
        return {
            context = "danger",
            spec = __TS__ObjectAssign({}, base, {
                type = "AVOID",
                radius = cfg.Avoid.Radius,
                duration = cfg.Avoid.Duration,
                maxResponders = 5,
                ackPing = false
            })
        }
    end
    return {
        context = "ground",
        spec = __TS__ObjectAssign({}, base, {type = "GATHER", duration = cfg.Gather.Duration, maxResponders = issuerSmoked and 5 or cfg.Gather.MaxResponders})
    }
end
local lastPingTime = {}
local scannedAt = {}
local clearSince = {}
local lastSummary = "-"
local function cancelSmokeFrom(team, issuerPID)
    for ____, order in ipairs(Orders.GetActive(team)) do
        if order.type == "SMOKE" and order.issuerPID == issuerPID then
            Orders.Cancel(team, order.id)
            return
        end
    end
end
--- Reads every human ally's latest ping and posts orders for new ones. Cheap when nothing changed.
function ____exports.Scan(team)
    local cfg = ____exports.Get()
    local now = GameTime()
    local players = GetTeamPlayers(team)
    do
        local i = 1
        while i <= #players do
            do
                local __continue45
                repeat
                    local pid = players[i]
                    if IsPlayerBot(pid) then
                        __continue45 = true
                        break
                    end
                    local member = GetTeamMember(i)
                    if member == nil or member == nil then
                        __continue45 = true
                        break
                    end
                    local ping = member:GetMostRecentPing()
                    if ping == nil or ping == nil or ping.time == 0 or ping.location == nil then
                        __continue45 = true
                        break
                    end
                    if lastPingTime[pid] == ping.time then
                        __continue45 = true
                        break
                    end
                    lastPingTime[pid] = ping.time
                    if now - ping.time > cfg.MaxPingAge then
                        __continue45 = true
                        break
                    end
                    local smoked = member:HasModifier("modifier_smoke_of_deceit")
                    local result = ____exports.Classify(pid, ping, smoked)
                    lastSummary = (((result.context .. " by ") .. tostring(pid)) .. " @") .. string.format("%.1f", ping.time)
                    HDebug.Log(
                        "pings",
                        lastSummary,
                        "danger=" .. tostring(____exports.IsDangerPing(ping))
                    )
                    local ____Telemetry_Event_5 = Telemetry.Event
                    local ____array_4 = __TS__SparseArrayNew(
                        {"by", pid},
                        {"team", team},
                        {"context", result.context},
                        {
                            "danger",
                            ____exports.IsDangerPing(ping)
                        },
                        {
                            "x",
                            math.floor(ping.location.x)
                        },
                        {
                            "y",
                            math.floor(ping.location.y)
                        }
                    )
                    local ____opt_2 = result.spec
                    __TS__SparseArrayPush(____array_4, {"order", ____opt_2 and ____opt_2.type})
                    ____Telemetry_Event_5(
                        "ping",
                        {__TS__SparseArraySpread(____array_4)}
                    )
                    if result.spec == nil then
                        __continue45 = true
                        break
                    end
                    if smoked and (result.spec.type == "GATHER" or result.spec.type == "ATTACK") then
                        cancelSmokeFrom(team, pid)
                    end
                    Orders.Post(team, result.spec)
                    __continue45 = true
                until true
                if not __continue45 then
                    break
                end
            end
            i = i + 1
        end
    end
end
--- Cancels AVOID orders whose area the team can see is clear. Inputs are team-visible, so every bot agrees.
function ____exports.ForgetClearedDangers(team)
    local cfg = ____exports.Get().Avoid
    local now = GameTime()
    for ____, order in ipairs(Orders.GetActive(team)) do
        do
            local __continue54
            repeat
                if order.type ~= "AVOID" or order.location == nil then
                    __continue54 = true
                    break
                end
                if now - order.createdAt < cfg.MinSeconds then
                    __continue54 = true
                    break
                end
                local radius = order.radius or cfg.Radius
                if not IsLocationVisible(order.location) or ____exports.NearestVisibleEnemyHero(order.location, radius) ~= nil then
                    clearSince[order.id] = nil
                    __continue54 = true
                    break
                end
                local since = clearSince[order.id] or now
                clearSince[order.id] = since
                if now - since >= cfg.ClearSeconds then
                    clearSince[order.id] = nil
                    HDebug.Log(
                        "pings",
                        ("forgot danger ping " .. tostring(order.id)) .. ": area clear"
                    )
                    Orders.Cancel(team, order.id)
                end
                __continue54 = true
            until true
            if not __continue54 then
                break
            end
        end
    end
end
function ____exports.Tick(bot)
    if not ____exports.IsActive() or GetGameState() ~= GameState.GameInProgress then
        return
    end
    local team = bot:GetTeam()
    local now = GameTime()
    if scannedAt[team] ~= now then
        scannedAt[team] = now
        ____exports.Scan(team)
        ____exports.ForgetClearedDangers(team)
    end
    HDebug.Text(bot, "ping", lastSummary)
end
return ____exports
