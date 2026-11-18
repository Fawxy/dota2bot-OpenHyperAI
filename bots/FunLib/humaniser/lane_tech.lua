--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local Tower = ____dota.Tower
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
____exports.TOWER_IDS = {
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
local towerCache = {}
function ____exports.ResetCache()
    towerCache = {}
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function enemyTowers(team)
    local now = DotaTime()
    local cached = towerCache[team]
    if cached ~= nil and cached.time == now then
        return cached.list
    end
    local list = {}
    local enemy = team == Team.Radiant and Team.Dire or Team.Radiant
    for ____, id in ipairs(____exports.TOWER_IDS) do
        local tower = GetTower(enemy, id)
        if tower ~= nil and tower ~= nil and tower:IsAlive() then
            list[#list + 1] = tower
        end
    end
    towerCache[team] = {time = now, list = list}
    return list
end
local function underEnemyTower(team, loc)
    local range = LaneConfig.TowerReach()
    for ____, tower in ipairs(enemyTowers(team)) do
        if dist2D(
            tower:GetLocation(),
            loc
        ) <= range then
            return true
        end
    end
    return false
end
local function isLaneCreep(unit)
    return unit ~= nil and unit ~= nil and not unit:IsNull() and unit:IsAlive() and unit:CanBeSeen() and LaneState.IsLaneCreepName(unit:GetUnitName())
end
function ____exports.ShoveTarget(bot, enemyCreeps)
    local team = bot:GetTeam()
    local best
    for ____, c in ipairs(enemyCreeps or ({})) do
        do
            local __continue15
            repeat
                if not isLaneCreep(c) or c:GetTeam() == team then
                    __continue15 = true
                    break
                end
                if underEnemyTower(
                    team,
                    c:GetLocation()
                ) then
                    __continue15 = true
                    break
                end
                if best == nil or c:GetHealth() < best:GetHealth() then
                    best = c
                end
                __continue15 = true
            until true
            if not __continue15 then
                break
            end
        end
    end
    return best
end
return ____exports
