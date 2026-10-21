--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local Counter = require(GetScriptDirectory().."/FunLib/humaniser/counterplay")
local LastHitSkill = require(GetScriptDirectory().."/FunLib/humaniser/last_hit_skill")
local DENY_HP = 0.49
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function ____exports.IsPreRuneWindow(now, nextRune)
    local timing = LaneConfig.Settings().Timing
    local left = nextRune - now
    return left >= timing.PreRuneMin and left <= timing.PreRuneMax
end
function ____exports.IsPreRune(_team, lane)
    if lane ~= Lane.Mid or not LaneConfig.IsOn("Mid") then
        return false
    end
    local next = LaneConfig.Helpers().NextPowerRuneTime
    return next ~= nil and ____exports.IsPreRuneWindow(
        DotaTime(),
        next()
    )
end
--- Mid bot only: the first allied ranged lane creep it can deny right now; otherwise the Lua fallback decides.
-- The priority drops while counterplay has the enemy mid missing after a shove.
function ____exports.PickDeny(bot, allyCreeps)
    if not LaneConfig.IsOn("Mid") or bot:GetAssignedLane() ~= Lane.Mid then
        return nil
    end
    if Counter.DropRangedDeny(bot:GetTeam()) then
        return nil
    end
    local damage = bot:GetAttackDamage()
    for ____, creep in ipairs(allyCreeps) do
        do
            local __continue9
            repeat
                if not creep:IsAlive() or not LaneState.IsLaneCreepName(creep:GetUnitName()) then
                    __continue9 = true
                    break
                end
                if (string.find(
                    creep:GetUnitName(),
                    "ranged",
                    1,
                    true
                )) == nil then
                    __continue9 = true
                    break
                end
                local hp = creep:GetHealth()
                if hp < DENY_HP * creep:GetMaxHealth() and LastHitSkill.WillKill(
                    bot,
                    creep,
                    damage,
                    0,
                    true
                ) then
                    return creep
                end
                __continue9 = true
            until true
            if not __continue9 then
                break
            end
        end
    end
    return nil
end
--- False for a non-mid bot near the wave of a human mid, so it does not shove, pull or deny there.
function ____exports.MayTouchWave(bot, creep)
    if not LaneConfig.IsOn("Mid") or not LaneConfig.InLaningPhase() or bot:GetAssignedLane() == Lane.Mid then
        return true
    end
    local s = LaneState.Get(
        bot:GetTeam(),
        Lane.Mid,
        bot
    )
    if s == nil then
        return true
    end
    local radii = LaneConfig.Settings().Radii
    if dist2D(
        creep:GetLocation(),
        s.frontLoc
    ) > radii.MidFront then
        return true
    end
    for ____, h in ipairs(s.allies) do
        if not h.isBot and h.alive and h.assigned and h.position == 2 and h.distToFront <= radii.MidHuman then
            return false
        end
    end
    return true
end
function ____exports.MidPullAllowed(team)
    return #Camps.PullCampsFor(team, Lane.Mid) > 0
end
function ____exports.RegisterProbes()
    LaneHooks.SetRotationProbe(function(bot) return bot:GetAssignedLane() == Lane.Mid and ____exports.IsPreRune(
        bot:GetTeam(),
        Lane.Mid
    ) end)
end
LaneState.SetPreRune(____exports.IsPreRune)
____exports.RegisterProbes()
return ____exports
