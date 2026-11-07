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
local GameRules = require(GetScriptDirectory().."/FunLib/humaniser/game_rules")
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneGeom = require(GetScriptDirectory().."/FunLib/humaniser/lane_geom")
____exports.WAVE_CYCLE = GameRules.WAVE_EVERY
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
local function ownTower(team, lane)
    local ids = TOWER_IDS[lane]
    do
        local i = 0
        while i < #ids do
            local tower = GetTower(team, ids[i + 1])
            if tower ~= nil and tower ~= nil and tower:IsAlive() then
                return {
                    tier = i + 1,
                    hp = tower:GetHealth(),
                    loc = tower:GetLocation()
                }
            end
            i = i + 1
        end
    end
    return {tier = 0}
end
function ____exports.CreepKind(name)
    if (string.find(name, "siege", 1, true)) ~= nil then
        return "s"
    end
    if (string.find(name, "ranged", 1, true)) ~= nil then
        return "r"
    end
    if (string.find(name, "flag", 1, true)) ~= nil then
        return "f"
    end
    return "m"
end
local MAX_PLAYER_ID = 23
local function placed(pid, visible, seen, loc, p)
    local allyDist = {}
    for ____, ____value in ipairs(p.allies) do
        local aid = ____value[1]
        local aloc = ____value[2]
        allyDist[#allyDist + 1] = {
            aid,
            dist2D(loc, aloc)
        }
    end
    return {
        pid = pid,
        visible = visible,
        seen = seen,
        dist = dist2D(loc, p.front),
        towerDist = p.tower ~= nil and dist2D(loc, p.tower) or -1,
        allyDist = allyDist
    }
end
local function readEnemies(team, m, p)
    local enemyTeam = team == Team.Radiant and Team.Dire or Team.Radiant
    for ____, pid in ipairs(GetTeamPlayers(enemyTeam)) do
        m.enemyPids[pid] = true
    end
    do
        local pid = 0
        while pid <= MAX_PLAYER_ID do
            if GetTeamForPlayer(pid) == enemyTeam then
                m.enemyPids[pid] = true
            end
            pid = pid + 1
        end
    end
    local enemies = {}
    local neverSeen = {}
    local seen = {}
    for ____, u in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue49
            repeat
                if not u:CanBeSeen() or not u:IsAlive() or u:IsIllusion() then
                    __continue49 = true
                    break
                end
                local pid = u:GetPlayerID()
                m.enemyPids[pid] = true
                seen[pid] = true
                local maxHP = u:GetMaxHealth()
                local e = placed(
                    pid,
                    true,
                    0,
                    u:GetLocation(),
                    p
                )
                e.hp = maxHP > 0 and u:GetHealth() / maxHP or 0
                e.lvl = u:GetLevel()
                enemies[#enemies + 1] = e
                __continue49 = true
            until true
            if not __continue49 then
                break
            end
        end
    end
    local dead = 0
    for pid in pairs(m.enemyPids) do
        do
            local __continue52
            repeat
                local id = pid
                if seen[id] == true then
                    __continue52 = true
                    break
                end
                if not IsHeroAlive(id) then
                    dead = dead + 1
                    __continue52 = true
                    break
                end
                local info = GetHeroLastSeenInfo(id)[1]
                if info == nil then
                    neverSeen[#neverSeen + 1] = id
                    __continue52 = true
                    break
                end
                enemies[#enemies + 1] = placed(
                    id,
                    false,
                    info.time_since_seen,
                    info.location,
                    p
                )
                __continue52 = true
            until true
            if not __continue52 then
                break
            end
        end
    end
    __TS__ArraySort(
        neverSeen,
        function(____, a, b) return a - b end
    )
    return {enemies = enemies, dead = dead, neverSeen = neverSeen}
end
local function readAggro(lane, m, enemyCreeps, front, now)
    local near = LaneConfig.Settings().Radii.AllyNearFront
    local result = {}
    local allies = {}
    do
        local i = 1
        while i <= TEAM_SLOTS do
            do
                local __continue58
                repeat
                    local hero = GetTeamMember(i)
                    if hero == nil or hero == nil or hero:IsIllusion() or not hero:IsAlive() then
                        __continue58 = true
                        break
                    end
                    if hero:GetAssignedLane() ~= lane and GetUnitToLocationDistance(hero, front) > near then
                        __continue58 = true
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
                    allies[#allies + 1] = {
                        pid,
                        hero:GetLocation()
                    }
                    __continue58 = true
                until true
                if not __continue58 then
                    break
                end
            end
            i = i + 1
        end
    end
    return {aggro = result, allies = allies}
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
        local creeps = {}
        local enemyCreeps = {}
        for ____, c in ipairs(own[lane]) do
            creeps[#creeps + 1] = {
                kind = ____exports.CreepKind(c.unit:GetUnitName()),
                amount = c.amount,
                hp = c.unit:GetHealth()
            }
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
            enemyCreeps[#enemyCreeps + 1] = {
                kind = ____exports.CreepKind(c.unit:GetUnitName()),
                amount = c.amount,
                hp = c.unit:GetHealth()
            }
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
        local tower = ownTower(team, lane)
        local ____readAggro_result_1 = readAggro(
            lane,
            m,
            foes[lane],
            frontLoc,
            now
        )
        local aggro = ____readAggro_result_1.aggro
        local allies = ____readAggro_result_1.allies
        local ____readEnemies_result_2 = readEnemies(team, m, {front = frontLoc, tower = tower.loc, allies = allies})
        local enemies = ____readEnemies_result_2.enemies
        local dead = ____readEnemies_result_2.dead
        local neverSeen = ____readEnemies_result_2.neverSeen
        __TS__ArraySort(
            creeps,
            function(____, a, b) return a.amount - b.amount end
        )
        __TS__ArraySort(
            enemyCreeps,
            function(____, a, b) return a.amount - b.amount end
        )
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
            aggro = aggro,
            census = census,
            censusAtEnemy = censusAtEnemy,
            creeps = creeps,
            enemyCreeps = enemyCreeps,
            neverSeen = neverSeen,
            towerTier = tower.tier,
            towerHp = tower.hp,
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
--- The `ed` field of ev=lane_read, in `ee`'s order: per enemy `pid:dist_to_our_tower:ally=dist,...` (-1 when our towers on
-- the lane are down; the ally list is empty with no ally in the lane), from the same spot as `ee`'s distance.
function ____exports.FormatEnemyDistances(enemies)
    local out = {}
    for ____, e in ipairs(enemies) do
        local allies = {}
        for ____, ____value in ipairs(e.allyDist) do
            local pid = ____value[1]
            local d = ____value[2]
            allies[#allies + 1] = (tostring(pid) .. "=") .. tostring(math.floor(d))
        end
        out[#out + 1] = (((tostring(e.pid) .. ":") .. tostring(math.floor(e.towerDist))) .. ":") .. table.concat(allies, ",")
    end
    return table.concat(out, ";")
end
--- The `cc` field of ev=lane_read: per own creep `kind:amount_in_thousandths:hp`, by amount, joined by `;`.
function ____exports.FormatCreeps(creeps)
    local out = {}
    for ____, c in ipairs(creeps) do
        out[#out + 1] = (((c.kind .. ":") .. tostring(math.floor(c.amount * 1000 + 0.5))) .. ":") .. tostring(math.floor(c.hp + 0.5))
    end
    return table.concat(out, ";")
end
return ____exports
