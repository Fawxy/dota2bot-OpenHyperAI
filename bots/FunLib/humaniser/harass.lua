--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function ____exports.IsLastHitAttempt(enemy, ourCreeps)
    local h = LaneConfig.Helpers()
    local dmg = enemy:GetAttackDamage()
    local target = enemy:GetAttackTarget()
    if target ~= nil and target ~= nil and h.WillKillTarget ~= nil and h.GetAttackProDelayTime ~= nil then
        for ____, creep in ipairs(ourCreeps or ({})) do
            if creep == target and creep:IsAlive() and h.WillKillTarget(
                creep,
                dmg,
                DamageType.Physical,
                h.GetAttackProDelayTime(enemy, creep)
            ) then
                return creep
            end
        end
    end
    local cfg = LaneConfig.Settings()
    local here = enemy:GetLocation()
    local ahead = enemy:GetExtrapolatedLocation(cfg.Radii.ApproachExtrapolate)
    local best
    local bestDist = math.huge
    for ____, creep in ipairs(ourCreeps or ({})) do
        do
            local __continue8
            repeat
                if not creep:IsAlive() or creep:GetHealth() > dmg then
                    __continue8 = true
                    break
                end
                local loc = creep:GetLocation()
                local d = dist2D(here, loc)
                if dist2D(ahead, loc) <= d - cfg.Thresholds.ApproachEpsilon and d < bestDist then
                    best = creep
                    bestDist = d
                end
                __continue8 = true
            until true
            if not __continue8 then
                break
            end
        end
    end
    return best
end
return ____exports
