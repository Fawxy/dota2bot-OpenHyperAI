--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneGeom = require(GetScriptDirectory().."/FunLib/humaniser/lane_geom")
____exports.WAVE_CYCLE = 30
local TEAM_SLOTS = 5
local LANES = {Lane.Top, Lane.Mid, Lane.Bot}
local TOWER_IDS = {[Lane.Top] = {Tower.Top1, Tower.Top2, Tower.Top3}, [Lane.Mid] = {Tower.Mid1, Tower.Mid2, Tower.Mid3}, [Lane.Bot] = {Tower.Bot1, Tower.Bot2, Tower.Bot3}}
local memory = {}
local towerAmounts = {}
function ____exports.Reset()
    memory = {}
    towerAmounts = {}
end
local function memoryFor(team)
    local m = memory[team]
    if m == nil then
        m = {enemyPids = {}, aggroAt = {}}
        memory[team] = m
    end
    return m
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function absAmount(lane, loc)
    local r = GetAmountAlongLane(lane, loc)
    return {
        amount = Camps.ToTeamAmount(Team.Radiant, r.amount),
        distance = r.distance
    }
end
function ____exports.CreepWeight(name)
    local w = LaneConfig.Settings().ForecastModel.TypeWeight
    if (string.find(name, "ranged", 1, true)) ~= nil then
        return w.ranged
    end
    if (string.find(name, "siege", 1, true)) ~= nil then
        return w.siege
    end
    return w.melee
end
--- Imbalance + 1: 0 when the enemy has every creep, 1 even, 2 when we have every creep; PowerFloor damps small totals.
function ____exports.Advantage(allyPower, enemyPower)
    return 1 + (allyPower - enemyPower) / (allyPower + enemyPower + LaneConfig.Settings().ForecastModel.PowerFloor)
end
--- The most-advanced amount of `team`'s creeps: Radiant pushes towards 1, Dire towards 0.
function ____exports.Leads(team, a, b)
    if a == nil then
        return b
    end
    return team == Team.Radiant and math.max(a, b) or math.min(a, b)
end
local function emptyCreeps()
    return {count = 0, hp = 0, power = 0}
end
local function addCreep(c, team, unit, amount, loc)
    local hp = unit:GetHealth()
    c.count = c.count + 1
    c.hp = c.hp + hp
    c.power = c.power + hp * ____exports.CreepWeight(unit:GetUnitName())
    local lead = ____exports.Leads(team, c.lead, amount)
    if lead ~= c.lead then
        c.lead = lead
        c.leadLoc = loc
    end
end
function ____exports.IsLaneCreepName(name)
    for ____, part in ipairs({"creep_goodguys", "creep_badguys", "goodguys_siege", "badguys_siege"}) do
        if (string.find(name, part, 1, true)) ~= nil then
            return true
        end
    end
    return false
end
local function byLane(units, visibleOnly)
    local out = {[Lane.Top] = {}, [Lane.Mid] = {}, [Lane.Bot] = {}}
    local assign = LaneConfig.Settings().Radii.LaneAssign
    for ____, unit in ipairs(units) do
        do
            local __continue21
            repeat
                if visibleOnly and not unit:CanBeSeen() then
                    __continue21 = true
                    break
                end
                if not unit:IsAlive() or not ____exports.IsLaneCreepName(unit:GetUnitName()) then
                    __continue21 = true
                    break
                end
                local loc = unit:GetLocation()
                local best
                local bestDist = math.huge
                local bestAmount = 0
                for ____, lane in ipairs(LANES) do
                    local r = absAmount(lane, loc)
                    if r.distance < bestDist then
                        bestDist = r.distance
                        best = lane
                        bestAmount = r.amount
                    end
                end
                if best ~= nil and bestDist <= assign then
                    local ____out_best_0 = out[best]
                    ____out_best_0[#____out_best_0 + 1] = {unit = unit, loc = loc, amount = bestAmount}
                end
                __continue21 = true
            until true
            if not __continue21 then
                break
            end
        end
    end
    return out
end
--- Absolute amount of `owner`'s nearest alive tower on `lane`; its base end (0 or 1) when all three are down.
local function towerAmount(team, owner, lane)
    for ____, id in ipairs(TOWER_IDS[lane]) do
        do
            local __continue30
            repeat
                local tower = GetTower(owner, id)
                if tower == nil or tower == nil or not tower:IsAlive() then
                    __continue30 = true
                    break
                end
                local key = (((tostring(team) .. ":") .. tostring(owner)) .. ":") .. tostring(id)
                local amount = towerAmounts[key]
                if amount == nil then
                    amount = absAmount(
                        lane,
                        tower:GetLocation()
                    ).amount
                    towerAmounts[key] = amount
                end
                return amount
            until true
            if not __continue30 then
                break
            end
        end
    end
    return owner == Team.Radiant and 0 or 1
end
local function readEnemies(team, m, front)
    local enemyTeam = team == Team.Radiant and Team.Dire or Team.Radiant
    for ____, pid in ipairs(GetTeamPlayers(enemyTeam)) do
        m.enemyPids[pid] = true
    end
    local enemies = {}
    local seen = {}
    for ____, u in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue37
            repeat
                if not u:CanBeSeen() or not u:IsAlive() or u:IsIllusion() then
                    __continue37 = true
                    break
                end
                local pid = u:GetPlayerID()
                m.enemyPids[pid] = true
                seen[pid] = true
                local maxHP = u:GetMaxHealth()
                enemies[#enemies + 1] = {
                    pid = pid,
                    visible = true,
                    seen = 0,
                    dist = dist2D(
                        u:GetLocation(),
                        front
                    ),
                    hp = maxHP > 0 and u:GetHealth() / maxHP or 0,
                    lvl = u:GetLevel()
                }
                __continue37 = true
            until true
            if not __continue37 then
                break
            end
        end
    end
    local dead = 0
    for pid in pairs(m.enemyPids) do
        do
            local __continue40
            repeat
                local id = pid
                if seen[id] == true then
                    __continue40 = true
                    break
                end
                if not IsHeroAlive(id) then
                    dead = dead + 1
                    __continue40 = true
                    break
                end
                local info = GetHeroLastSeenInfo(id)[1]
                if info == nil then
                    __continue40 = true
                    break
                end
                enemies[#enemies + 1] = {
                    pid = id,
                    visible = false,
                    seen = info.time_since_seen,
                    dist = dist2D(info.location, front)
                }
                __continue40 = true
            until true
            if not __continue40 then
                break
            end
        end
    end
    return {enemies = enemies, dead = dead}
end
local function readAggro(lane, m, enemyCreeps, front, now)
    local near = LaneConfig.Settings().Radii.AllyNearFront
    local result = {}
    do
        local i = 1
        while i <= TEAM_SLOTS do
            do
                local __continue45
                repeat
                    local hero = GetTeamMember(i)
                    if hero == nil or hero == nil or hero:IsIllusion() or not hero:IsAlive() then
                        __continue45 = true
                        break
                    end
                    if hero:GetAssignedLane() ~= lane and GetUnitToLocationDistance(hero, front) > near then
                        __continue45 = true
                        break
                    end
                    local n = 0
                    for ____, c in ipairs(enemyCreeps) do
                        if c.unit:GetAttackTarget() == hero then
                            n = n + 1
                        end
                    end
                    local pid = hero:GetPlayerID()
                    if n > 0 then
                        m.aggroAt[pid] = now
                    end
                    local at = m.aggroAt[pid]
                    result[#result + 1] = {pid = pid, now = n, since = at ~= nil and now - at or nil}
                    __continue45 = true
                until true
                if not __continue45 then
                    break
                end
            end
            i = i + 1
        end
    end
    return result
end
--- One reading per lane for `team`, which must be the calling script's team.
function ____exports.Read(team, now)
    local enemyTeam = team == Team.Radiant and Team.Dire or Team.Radiant
    local m = memoryFor(team)
    local own = byLane(
        GetUnitList(UnitType.AlliedCreeps),
        false
    )
    local foes = byLane(
        GetUnitList(UnitType.EnemyCreeps),
        true
    )
    local radius = LaneConfig.Settings().Radii.LaneCreep
    local reads = {}
    for ____, lane in ipairs(LANES) do
        local frontLoc = GetLaneFrontLocation(team, lane, 0)
        local enemyFrontLoc = GetLaneFrontLocation(enemyTeam, lane, 0)
        local ourFront = absAmount(lane, frontLoc).amount
        local enemyFront = absAmount(lane, enemyFrontLoc).amount
        local ourTower = towerAmount(team, team, lane)
        local theirTower = towerAmount(team, enemyTeam, lane)
        local meet = LaneGeom.MeetAmount(ourFront, enemyFront, ourTower, theirTower)
        local census = emptyCreeps()
        local near = emptyCreeps()
        local enemyNear = emptyCreeps()
        local censusAtEnemy = emptyCreeps()
        for ____, c in ipairs(own[lane]) do
            addCreep(
                census,
                team,
                c.unit,
                c.amount,
                c.loc
            )
            if dist2D(c.loc, frontLoc) <= radius then
                addCreep(
                    near,
                    team,
                    c.unit,
                    c.amount,
                    c.loc
                )
            end
            if dist2D(c.loc, enemyFrontLoc) <= radius then
                addCreep(
                    censusAtEnemy,
                    team,
                    c.unit,
                    c.amount,
                    c.loc
                )
            end
        end
        for ____, c in ipairs(foes[lane]) do
            if dist2D(c.loc, frontLoc) <= radius then
                addCreep(
                    enemyNear,
                    enemyTeam,
                    c.unit,
                    c.amount,
                    c.loc
                )
            end
        end
        local ____readEnemies_result_1 = readEnemies(team, m, frontLoc)
        local enemies = ____readEnemies_result_1.enemies
        local dead = ____readEnemies_result_1.dead
        local cycleSec = now % ____exports.WAVE_CYCLE
        reads[#reads + 1] = {
            team = team,
            lane = lane,
            adv = ____exports.Advantage(near.power, enemyNear.power),
            eq = LaneGeom.EqPos(meet, ourTower, theirTower),
            near = near,
            enemyNear = enemyNear,
            ourFront = ourFront,
            enemyFront = enemyFront,
            ourTower = ourTower,
            theirTower = theirTower,
            cycleSec = cycleSec,
            nextWaveIn = ____exports.WAVE_CYCLE - cycleSec,
            enemies = enemies,
            dead = dead,
            aggro = readAggro(
                lane,
                m,
                foes[lane],
                frontLoc,
                now
            ),
            census = census,
            censusAtEnemy = censusAtEnemy,
            frontLoc = frontLoc
        }
    end
    return reads
end
--- The `ee` field of ev=lane_read, parsed by hlog query `@lane_read_check`: per enemy `pid:v:dist:hp%:lvl` when visible,
-- `pid:secs_since_seen:dist` when not, joined by `;`.
function ____exports.FormatEnemies(enemies)
    local out = {}
    for ____, e in ipairs(enemies) do
        local head = (((tostring(e.pid) .. ":") .. tostring(e.visible and "v" or math.floor(e.seen))) .. ":") .. tostring(math.floor(e.dist))
        out[#out + 1] = e.visible and (((head .. ":") .. tostring(math.floor((e.hp or 0) * 100 + 0.5))) .. ":") .. tostring(e.lvl) or head
    end
    return table.concat(out, ";")
end
--- The `ag` field of ev=lane_read: per allied hero `pid:creeps_on_it_now:secs_since_last` (-1 never), joined by `;`.
function ____exports.FormatAggro(aggro)
    local out = {}
    for ____, a in ipairs(aggro) do
        out[#out + 1] = (((tostring(a.pid) .. ":") .. tostring(a.now)) .. ":") .. (a.since == nil and "-1" or string.format(
            "%.1f",
            math.floor(a.since * 10) / 10
        ))
    end
    return table.concat(out, ";")
end
return ____exports
