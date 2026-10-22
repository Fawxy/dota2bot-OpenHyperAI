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
-- End of Lua Library inline imports
local ____exports = {}
local timing, enemyTeamOf, holdsRemovedUnit, enemyCache
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
function timing()
    return LaneConfig.Settings().Timing
end
function enemyTeamOf(team)
    return team == Team.Radiant and Team.Dire or Team.Radiant
end
function holdsRemovedUnit(list)
    for ____, e in ipairs(list) do
        if e.unit ~= nil and e.unit:IsNull() then
            return true
        end
    end
    return false
end
function ____exports.Enemies(bot, _lane)
    if not LaneConfig.IsActive() then
        return {}
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local cached = enemyCache[pid]
    if cached ~= nil and now - cached.time < timing().SnapshotRefresh and not holdsRemovedUnit(cached.list) then
        return cached.list
    end
    local list = {}
    local seen = {}
    for ____, u in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue106
            repeat
                if not u:CanBeSeen() or not u:IsAlive() or u:IsIllusion() then
                    __continue106 = true
                    break
                end
                local epid = u:GetPlayerID()
                seen[epid] = true
                list[#list + 1] = {
                    unit = u,
                    pid = epid,
                    visible = true,
                    location = u:GetLocation(),
                    timeSinceSeen = 0,
                    position = LaneConfig.PositionOf(u)
                }
                __continue106 = true
            until true
            if not __continue106 then
                break
            end
        end
    end
    for ____, epid in ipairs(GetTeamPlayers(enemyTeamOf(bot:GetTeam()))) do
        do
            local __continue109
            repeat
                if seen[epid] == true or not IsHeroAlive(epid) then
                    __continue109 = true
                    break
                end
                local info = GetHeroLastSeenInfo(epid)[1]
                if info == nil then
                    __continue109 = true
                    break
                end
                list[#list + 1] = {pid = epid, visible = false, location = info.location, timeSinceSeen = info.time_since_seen}
                __continue109 = true
            until true
            if not __continue109 then
                break
            end
        end
    end
    enemyCache[pid] = {time = now, list = list}
    return list
end
local LANES = {Lane.Top, Lane.Mid, Lane.Bot}
local TOWER_IDS = {[Lane.Top] = {Tower.Top1, Tower.Top2, Tower.Top3}, [Lane.Mid] = {Tower.Mid1, Tower.Mid2, Tower.Mid3}, [Lane.Bot] = {Tower.Bot1, Tower.Bot2, Tower.Bot3}}
local WAVE_HISTORY = 3
local EQ_HISTORY = 4
local ARRIVAL_CREEPS = 3
local scans = {}
local snapshots = {}
local tracks = {}
local towerAmounts = {}
enemyCache = {}
local viewCache = {}
local function preRuneFn()
    return false
end
local refreshCallbacks = {}
local function weakKeys()
    return setmetatable({}, {__mode = "k"})
end
local function radii()
    return LaneConfig.Settings().Radii
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function clamp(v, lo, hi)
    return v < lo and lo or (v > hi and hi or v)
end
local function contains(name, part)
    return (string.find(name, part, 1, true)) ~= nil
end
local function copyRecord(r)
    local copy = {}
    for k, v in pairs(r) do
        copy[k] = v
    end
    return copy
end
local function push(list, v, max)
    list[#list + 1] = v
    if #list > max then
        table.remove(list, 1)
    end
end
local function median(list)
    if #list == 0 then
        return nil
    end
    local sorted = {unpack(list)}
    __TS__ArraySort(
        sorted,
        function(____, a, b) return a - b end
    )
    local n = #sorted
    return n % 2 == 1 and sorted[(n - 1) / 2 + 1] or (sorted[n / 2] + sorted[n / 2 + 1]) / 2
end
function ____exports.EqPos(meetAmount, ourTower, theirTower)
    local span = theirTower - ourTower
    if span == 0 then
        return 0
    end
    return clamp(2 * (meetAmount - ourTower) / span - 1, -1, 1)
end
--- A front behind its own side's tower has no wave in lane (it reads that side's base), so the other front is the meet.
function ____exports.MeetAmount(ourFront, enemyFront, ourTower, theirTower)
    local span = theirTower - ourTower
    local oursOut = (ourFront - ourTower) * span < 0
    local theirsOut = (enemyFront - theirTower) * span > 0
    if oursOut and not theirsOut then
        return enemyFront
    end
    if theirsOut and not oursOut then
        return ourFront
    end
    return (ourFront + enemyFront) / 2
end
function ____exports.CreepWeight(name)
    local w = LaneConfig.Settings().ForecastModel.TypeWeight
    if contains(name, "ranged") then
        return w.ranged
    end
    if contains(name, "siege") then
        return w.siege
    end
    return w.melee
end
function ____exports.LanePower(units)
    local power = 0
    for ____, u in ipairs(units) do
        if u:IsAlive() then
            power = power + u:GetHealth() * ____exports.CreepWeight(u:GetUnitName())
        end
    end
    return power
end
function ____exports.Imbalance(allyPower, enemyPower)
    return (allyPower - enemyPower) / (allyPower + enemyPower + LaneConfig.Settings().ForecastModel.PowerFloor)
end
function ____exports.ForecastEq(eqPos, imbalance)
    return clamp(
        eqPos + LaneConfig.Settings().ForecastModel.K * imbalance,
        -1,
        1
    )
end
function ____exports.LaneKindOf(team, lane)
    if lane == Lane.Mid then
        return "mid"
    end
    return lane == Camps.LaneOfKind(team, "safe") and "safe" or "off"
end
function ____exports.DesiredEq(kind, preRune)
    local eq = LaneConfig.Settings().Eq
    if kind == "mid" then
        return preRune and eq.MidPreRune or eq.Mid
    end
    return kind == "safe" and eq.Safe or eq.Off
end
function ____exports.LaneScore(desired, eqPos, enemyXpExposure)
    return desired - eqPos - LaneConfig.Settings().Eq.XpDenyWeight * enemyXpExposure
end
function ____exports.ForesightOf(skill)
    return LaneConfig.IsOn("Forecast") and LaneConfig.Curve("Foresight", skill) or 0
end
function ____exports.ForecastScore(desired, eqPos, forecastEq, foresight, exposure)
    return ____exports.LaneScore(desired, eqPos + foresight * (forecastEq - eqPos), exposure)
end
function ____exports.SetPreRune(fn)
    preRuneFn = fn
end
function ____exports.OnRefresh(fn)
    refreshCallbacks[#refreshCallbacks + 1] = fn
end
function ____exports.ResetCache()
    scans = {}
    snapshots = {}
    tracks = {}
    towerAmounts = {}
    enemyCache = {}
    viewCache = {}
end
function ____exports.IsLaneCreepName(name)
    return contains(name, "creep_goodguys") or contains(name, "creep_badguys") or contains(name, "goodguys_siege") or contains(name, "badguys_siege")
end
local function partition(units, enemy)
    local byLane = {[Lane.Top] = {}, [Lane.Mid] = {}, [Lane.Bot] = {}}
    local assign = radii().LaneAssign
    for ____, unit in ipairs(units) do
        do
            local __continue43
            repeat
                if enemy and not unit:CanBeSeen() then
                    __continue43 = true
                    break
                end
                if not unit:IsAlive() or not ____exports.IsLaneCreepName(unit:GetUnitName()) then
                    __continue43 = true
                    break
                end
                local loc = unit:GetLocation()
                local bestLane
                local bestDist = math.huge
                local bestAmount = 0
                for ____, lane in ipairs(LANES) do
                    local r = GetAmountAlongLane(lane, loc)
                    if r.distance < bestDist then
                        bestDist = r.distance
                        bestLane = lane
                        bestAmount = r.amount
                    end
                end
                if bestLane == nil or bestDist > assign then
                    __continue43 = true
                    break
                end
                local ____byLane_bestLane_0 = byLane[bestLane]
                ____byLane_bestLane_0[#____byLane_bestLane_0 + 1] = {unit = unit, loc = loc, absAmount = bestAmount}
                __continue43 = true
            until true
            if not __continue43 then
                break
            end
        end
    end
    return byLane
end
local function scanFor(team)
    local now = DotaTime()
    local cached = scans[team]
    if cached ~= nil and cached.time == now then
        return cached
    end
    local scan = {
        time = now,
        ally = partition(
            GetUnitList(UnitType.AlliedCreeps),
            false
        ),
        enemy = partition(
            GetUnitList(UnitType.EnemyCreeps),
            true
        )
    }
    scans[team] = scan
    return scan
end
local function summarise(team, list, front, withLead)
    local summary = {
        count = 0,
        totalHP = 0,
        rangedAlive = false,
        siegeAlive = false,
        units = {}
    }
    local radius = radii().LaneCreep
    local leadAmount = -math.huge
    for ____, c in ipairs(list) do
        do
            local __continue54
            repeat
                if dist2D(c.loc, front) > radius then
                    __continue54 = true
                    break
                end
                summary.count = summary.count + 1
                summary.totalHP = summary.totalHP + c.unit:GetHealth()
                local name = c.unit:GetUnitName()
                if contains(name, "ranged") then
                    summary.rangedAlive = true
                end
                if contains(name, "siege") then
                    summary.siegeAlive = true
                end
                local ____summary_units_1 = summary.units
                ____summary_units_1[#____summary_units_1 + 1] = c.unit
                if withLead then
                    local amount = Camps.ToTeamAmount(team, c.absAmount)
                    if amount > leadAmount then
                        leadAmount = amount
                        summary.lead = c.unit
                    end
                end
                __continue54 = true
            until true
            if not __continue54 then
                break
            end
        end
    end
    return summary
end
--- Absolute amount of the nearest alive tower of `owner` on `lane`; undefined when all three are down.
local function nearestTowerAbs(owner, lane)
    for ____, id in ipairs(TOWER_IDS[lane]) do
        do
            local __continue62
            repeat
                local tower = GetTower(owner, id)
                if tower == nil or tower == nil or not tower:IsAlive() then
                    __continue62 = true
                    break
                end
                local key = (((tostring(GetTeam()) .. ":") .. tostring(owner)) .. ":") .. tostring(id)
                local amount = towerAmounts[key]
                if amount == nil then
                    amount = GetAmountAlongLane(
                        lane,
                        tower:GetLocation()
                    ).amount
                    towerAmounts[key] = amount
                end
                return amount
            until true
            if not __continue62 then
                break
            end
        end
    end
    return nil
end
local function teamAmountAt(team, lane, loc)
    return Camps.ToTeamAmount(
        team,
        GetAmountAlongLane(lane, loc).amount
    )
end
local function heroesFor(team, lane, front)
    local result = {}
    local near = radii().AllyNearFront
    local count = #GetTeamPlayers(team)
    do
        local i = 1
        while i <= count do
            do
                local __continue68
                repeat
                    local unit = GetTeamMember(i)
                    if unit == nil or unit == nil or unit:IsIllusion() then
                        __continue68 = true
                        break
                    end
                    local alive = unit:IsAlive()
                    local assigned = unit:GetAssignedLane() == lane
                    local dist = alive and GetUnitToLocationDistance(unit, front) or math.huge
                    if not assigned and not (alive and dist <= near) then
                        __continue68 = true
                        break
                    end
                    local maxHP = unit:GetMaxHealth()
                    result[#result + 1] = {
                        unit = unit,
                        pid = unit:GetPlayerID(),
                        isBot = unit:IsBot(),
                        alive = alive,
                        assigned = assigned,
                        position = LaneConfig.PositionOf(unit),
                        hp = alive and maxHP > 0 and unit:GetHealth() / maxHP or 0,
                        distToFront = dist
                    }
                    __continue68 = true
                until true
                if not __continue68 then
                    break
                end
            end
            i = i + 1
        end
    end
    return result
end
local function trackFor(key, now)
    local t = tracks[key]
    if t == nil then
        t = {
            cycle = math.floor(now / timing().WaveCycle),
            maxEnemy = 0,
            denies = 0,
            deniedCreeps = weakKeys(),
            lastEq = 0,
            arrivals = {},
            waveSizes = {},
            deniesPerCycle = {},
            eqHistory = {},
            aggro = {}
        }
        tracks[key] = t
    end
    return t
end
local function rollCycle(t, now)
    local cycle = math.floor(now / timing().WaveCycle)
    if cycle == t.cycle then
        return
    end
    if t.arrivalSec ~= nil then
        push(t.arrivals, t.arrivalSec, WAVE_HISTORY)
    end
    push(t.waveSizes, t.maxEnemy, WAVE_HISTORY)
    push(t.deniesPerCycle, t.denies, WAVE_HISTORY)
    push(t.eqHistory, t.lastEq, EQ_HISTORY)
    t.cycle = cycle
    t.arrivalSec = nil
    t.maxEnemy = 0
    t.denies = 0
    t.deniedCreeps = weakKeys()
end
local function countDenies(t, observer, lane, enemyLane)
    for ____, e in ipairs(____exports.Enemies(observer, lane)) do
        do
            local __continue77
            repeat
                if not e.visible or e.unit == nil then
                    __continue77 = true
                    break
                end
                local target = e.unit:GetAttackTarget()
                if target == nil or target == nil or t.deniedCreeps[target] == true then
                    __continue77 = true
                    break
                end
                for ____, c in ipairs(enemyLane) do
                    if c.unit == target then
                        t.deniedCreeps[target] = true
                        t.denies = t.denies + 1
                        break
                    end
                end
                __continue77 = true
            until true
            if not __continue77 then
                break
            end
        end
    end
end
local function refresh(team, lane, key, observer)
    local now = DotaTime()
    local enemyTeam = enemyTeamOf(team)
    local scan = scanFor(team)
    local t = trackFor(key, now)
    rollCycle(t, now)
    local frontLoc = GetLaneFrontLocation(team, lane, 0)
    local ourFront = teamAmountAt(team, lane, frontLoc)
    local enemyFront = teamAmountAt(
        team,
        lane,
        GetLaneFrontLocation(enemyTeam, lane, 0)
    )
    local ourAbs = nearestTowerAbs(team, lane)
    local theirAbs = nearestTowerAbs(enemyTeam, lane)
    local ourTowerAmount = ourAbs ~= nil and Camps.ToTeamAmount(team, ourAbs) or 0
    local theirTowerAmount = theirAbs ~= nil and Camps.ToTeamAmount(team, theirAbs) or 1
    local meetAmount = ____exports.MeetAmount(ourFront, enemyFront, ourTowerAmount, theirTowerAmount)
    local eqPos = ____exports.EqPos(meetAmount, ourTowerAmount, theirTowerAmount)
    local kind = ____exports.LaneKindOf(team, lane)
    local ally = summarise(team, scan.ally[lane], frontLoc, true)
    local enemy = summarise(team, scan.enemy[lane], frontLoc, false)
    local allyPower = ____exports.LanePower(ally.units)
    local enemyPower = ____exports.LanePower(enemy.units)
    local imbalance = ____exports.Imbalance(allyPower, enemyPower)
    local cycleSec = now % timing().WaveCycle
    if enemy.count > t.maxEnemy then
        t.maxEnemy = enemy.count
    end
    if t.arrivalSec == nil and enemy.count >= ARRIVAL_CREEPS then
        t.arrivalSec = cycleSec
    end
    t.lastEq = eqPos
    for ____, c in ipairs(enemy.units) do
        local target = c:GetAttackTarget()
        if target ~= nil and target ~= nil and target:GetTeam() == team and target:IsHero() then
            t.aggro[target:GetPlayerID()] = now
        end
    end
    if observer ~= nil then
        countDenies(t, observer, lane, scan.enemy[lane])
    end
    local snapshot = {
        team = team,
        lane = lane,
        kind = kind,
        time = now,
        ourFront = ourFront,
        enemyFront = enemyFront,
        meetAmount = meetAmount,
        ourTowerAmount = ourTowerAmount,
        theirTowerAmount = theirTowerAmount,
        eqPos = eqPos,
        frontLoc = frontLoc,
        ally = ally,
        enemy = enemy,
        cycleSec = cycleSec,
        nextWaveIn = timing().WaveCycle - cycleSec,
        enemyArrivalSec = median(t.arrivals),
        enemyWaveSizes = {unpack(t.waveSizes)},
        allies = heroesFor(team, lane, frontLoc),
        desiredEq = ____exports.DesiredEq(
            kind,
            preRuneFn(team, lane)
        ),
        enemyDeniesPerCycle = {unpack(t.deniesPerCycle)},
        lastAllyAggroAt = copyRecord(t.aggro),
        eqHistory = {unpack(t.eqHistory)},
        allyPower = allyPower,
        enemyPower = enemyPower,
        imbalance = imbalance,
        forecastEq = ____exports.ForecastEq(eqPos, imbalance)
    }
    snapshots[key] = snapshot
    for ____, fn in ipairs(refreshCallbacks) do
        fn(snapshot)
    end
    return snapshot
end
--- `observer` is the bot driving this refresh; it supplies the visible enemy heroes for deny counting.
function ____exports.Get(team, lane, observer)
    if not LaneConfig.IsActive() then
        return nil
    end
    local key = (tostring(team) .. ":") .. tostring(lane)
    local cached = snapshots[key]
    if cached ~= nil and DotaTime() - cached.time < timing().SnapshotRefresh then
        return cached
    end
    return refresh(team, lane, key, observer)
end
function ____exports.ForBot(bot)
    if not LaneConfig.IsActive() then
        return nil
    end
    local lane = bot:GetAssignedLane()
    if lane ~= Lane.Top and lane ~= Lane.Mid and lane ~= Lane.Bot then
        return nil
    end
    return ____exports.Get(
        bot:GetTeam(),
        lane,
        bot
    )
end
function ____exports.ScoreFor(bot, s)
    local pid = bot:GetPlayerID()
    local key = (tostring(pid) .. ":") .. tostring(s.lane)
    local cached = viewCache[key]
    if cached ~= nil and cached.time == s.time then
        return cached.view
    end
    local near = 0
    local radius = radii().Exposure
    local seenWithin = timing().ExposureSeen
    for ____, e in ipairs(____exports.Enemies(bot, s.lane)) do
        do
            local __continue115
            repeat
                if not e.visible and e.timeSinceSeen > seenWithin then
                    __continue115 = true
                    break
                end
                if dist2D(e.location, s.frontLoc) <= radius then
                    near = near + 1
                end
                __continue115 = true
            until true
            if not __continue115 then
                break
            end
        end
    end
    local exposure = math.min(
        1,
        near / LaneConfig.Settings().Thresholds.ExposureEnemies
    )
    local foresight = ____exports.ForesightOf(LaneConfig.SkillOf(bot))
    local view = {
        exposure = exposure,
        laneScore = ____exports.LaneScore(s.desiredEq, s.eqPos, exposure),
        foresight = foresight,
        forecastScore = ____exports.ForecastScore(
            s.desiredEq,
            s.eqPos,
            s.forecastEq,
            foresight,
            exposure
        )
    }
    viewCache[key] = {time = s.time, view = view}
    return view
end
function ____exports.Describe(s, v)
    return string.format(
        "eq=%.2f want=%.2f score=%.2f a%d/e%d next=%.0fs",
        s.eqPos,
        s.desiredEq,
        v.laneScore,
        s.ally.count,
        s.enemy.count,
        s.nextWaveIn
    )
end
return ____exports
