--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local SLOTS = 6
local installed = {}
local function nearestVisibleEnemy(bot)
    local best
    local bestDist = math.huge
    for ____, enemy in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue3
            repeat
                if not enemy:CanBeSeen() then
                    __continue3 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, enemy)
                if d < bestDist then
                    best = enemy
                    bestDist = d
                end
                __continue3 = true
            until true
            if not __continue3 then
                break
            end
        end
    end
    return best
end
function ____exports.Run(bot)
    local enemy = nearestVisibleEnemy(bot)
    if enemy == nil then
        return {"hfight no visible enemy"}
    end
    local hero = enemy:GetUnitName()
    local lines = {}
    do
        local i = 0
        while i < SLOTS do
            do
                local __continue9
                repeat
                    local ability = enemy:GetAbilityInSlot(i)
                    if ability == nil or ability == nil then
                        __continue9 = true
                        break
                    end
                    lines[#lines + 1] = (((((((((((("hfight " .. hero) .. " slot=") .. tostring(i)) .. " ") .. ability:GetName()) .. " lvl=") .. tostring(ability:GetLevel())) .. " cd=") .. tostring(ability:GetCooldownTimeRemaining())) .. " ult=") .. tostring(ability:IsUltimate())) .. " behavior=") .. tostring(ability:GetBehavior())
                    __continue9 = true
                until true
                if not __continue9 then
                    break
                end
            end
            i = i + 1
        end
    end
    lines[#lines + 1] = "hfight est=" .. tostring(enemy:GetEstimatedDamageToTarget(true, bot, 5, DamageType.All))
    return lines
end
function ____exports.InstallCastLogger(team)
    if not HDebug.IsEnabled() or installed[team] == true then
        return
    end
    installed[team] = true
    local enemyTeam = team == Team.Radiant and Team.Dire or Team.Radiant
    for ____, pid in ipairs(GetTeamPlayers(enemyTeam)) do
        InstallCastCallback(
            pid,
            function(event)
                local visible = false
                for ____, enemy in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
                    if enemy:GetPlayerID() == pid and enemy:CanBeSeen() then
                        visible = true
                    end
                end
                local parts = {}
                if type(event) == "table" then
                    for k, v in pairs(event) do
                        parts[#parts + 1] = (tostring(k) .. "=") .. tostring(v)
                    end
                    table.sort(parts)
                else
                    parts[#parts + 1] = tostring(event)
                end
                HDebug.Log(
                    "fight",
                    (((("hfight cast pid=" .. tostring(pid)) .. " visible=") .. tostring(visible)) .. " ") .. table.concat(parts, " ")
                )
            end
        )
    end
end
return ____exports
