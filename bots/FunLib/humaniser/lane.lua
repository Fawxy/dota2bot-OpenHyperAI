--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LanePlanner = require(GetScriptDirectory().."/FunLib/humaniser/lane_planner")
local LaneTech = require(GetScriptDirectory().."/FunLib/humaniser/lane_tech")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Stacking = require(GetScriptDirectory().."/FunLib/humaniser/stacking")
local LaneDebug = require(GetScriptDirectory().."/FunLib/humaniser/lane_debug")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local ____commands = require(GetScriptDirectory().."/FunLib/humaniser/commands")
local teamMembers = ____commands.teamMembers
____exports.Config = LaneConfig
____exports.Hooks = LaneHooks
____exports.Camps = Camps
____exports.LaneState = LaneState
____exports.LaneRoles = LaneRoles
____exports.LanePlan = LanePlan
____exports.LanePlanner = LanePlanner
____exports.LaneTech = LaneTech
____exports.CampJobs = CampJobs
____exports.Stacking = Stacking
function ____exports.IsEnabled()
    return LaneConfig.IsEnabled()
end
function ____exports.SetHelpers(h)
    LaneConfig.SetHelpers(h)
end
function ____exports.Tick(bot)
    LaneDebug.Tick(bot)
    local snapshot = LaneState.ForBot(bot)
    if snapshot == nil then
        return
    end
    if HDebug.IsEnabled() then
        local state = LaneState.Describe(
            snapshot,
            LaneState.ScoreFor(bot, snapshot)
        )
        HDebug.Text(
            bot,
            "lane",
            (state .. " ") .. LanePlan.Describe(LanePlan.View(bot, snapshot))
        )
    end
end
--- Whether this bot's laning Think() is OHA's (decided once at mode-file load, like AllyLastHit.OwnsLaning).
function ____exports.OwnsLaning(bot)
    return LaneTech.OwnsLaning(bot)
end
--- Runs before last hits; true means this frame's action is issued.
function ____exports.PreThink(bot, allyCreeps, enemyCreeps, enemies)
    return LaneTech.PreThink(bot, allyCreeps, enemyCreeps, enemies)
end
--- Runs after last hit and deny; true means this frame's action is issued.
function ____exports.Think(bot, allyCreeps, enemyCreeps, enemies)
    return LaneTech.Think(bot, allyCreeps, enemyCreeps, enemies)
end
--- Lane position override for the final move; returns `loc` itself when nothing applies.
function ____exports.AdjustPosition(bot, loc)
    return LaneTech.AdjustPosition(bot, loc)
end
function ____exports.PickDeny(_bot, _allyCreeps)
    return nil
end
function ____exports.SupersedesHarass(_bot)
    return false
end
--- mode_farm_generic GetDesire: a camp job's desire, 0 when no job runs (and before any engine call when off).
function ____exports.CampJobDesire(bot)
    return CampJobs.Desire(bot)
end
--- mode_farm_generic Think: true when the camp job owns this frame.
function ____exports.CampJobThink(bot)
    return CampJobs.Think(bot)
end
--- mode_laning_generic's last-hit desire yields to a running camp job.
function ____exports.CampJobActive(bot)
    return CampJobs.Active(bot)
end
function ____exports.CampJobOnEnd(bot)
    CampJobs.OnEnd(bot)
end
local function nearestBot(team, issuer)
    local best
    local bestDist = math.huge
    for ____, member in ipairs(teamMembers(team)) do
        do
            local __continue18
            repeat
                if not member:IsBot() or not member:IsAlive() then
                    __continue18 = true
                    break
                end
                local d = GetUnitToLocationDistance(
                    member,
                    issuer:GetLocation()
                )
                if d < bestDist then
                    best = member
                    bestDist = d
                end
                __continue18 = true
            until true
            if not __continue18 then
                break
            end
        end
    end
    return best
end
LaneDebug.Register(
    "hpulltest",
    function(team, issuer, args)
        local campIdx = tonumber(args[1])
        if campIdx == nil then
            HDebug.Log("lane", "hpulltest usage: !hpulltest <idx> [half]")
            return
        end
        local best = nearestBot(team, issuer)
        if best == nil then
            HDebug.Log("lane", "hpulltest no bot")
            return
        end
        local kind = args[2] == "half" and "half_pull" or "full_pull"
        local ok = CampJobs.Start(best, {kind = kind, campIdx = campIdx, forced = true})
        HDebug.Log(
            "lane",
            (((((("hpulltest pid=" .. tostring(best:GetPlayerID())) .. " camp=") .. tostring(campIdx)) .. " kind=") .. kind) .. " started=") .. tostring(ok)
        )
    end
)
LaneDebug.Register(
    "hstacktest",
    function(team, issuer, args)
        local campIdx = tonumber(args[1])
        if campIdx == nil then
            HDebug.Log("lane", "hstacktest usage: !hstacktest <idx>")
            return
        end
        local best = nearestBot(team, issuer)
        if best == nil then
            HDebug.Log("lane", "hstacktest no bot")
            return
        end
        local ok = CampJobs.Start(best, {kind = "stack", campIdx = campIdx, forced = true})
        HDebug.Log(
            "lane",
            (((("hstacktest pid=" .. tostring(best:GetPlayerID())) .. " camp=") .. tostring(campIdx)) .. " started=") .. tostring(ok)
        )
    end
)
return ____exports
