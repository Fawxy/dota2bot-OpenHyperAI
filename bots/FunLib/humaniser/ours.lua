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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local ScopedTeam, OtherTeamScoped, Customize
function ScopedTeam()
    local ____opt_0 = Customize.Ours
    local scope = ____opt_0 and ____opt_0.Team
    if scope == 2 or scope == 3 then
        return scope
    end
    if type(scope) ~= "string" then
        return nil
    end
    local name = string.lower(scope)
    return name == "radiant" and 2 or (name == "dire" and 3 or nil)
end
function OtherTeamScoped()
    local team = ScopedTeam()
    return team ~= nil and GetTeam() ~= team
end
function ____exports.On(feature)
    if Customize.Enable == false then
        return false
    end
    if OtherTeamScoped() then
        return false
    end
    local ____opt_2 = Customize.Ours
    if ____opt_2 ~= nil then
        ____opt_2 = ____opt_2[feature]
    end
    local value = ____opt_2
    if value == nil or value == nil then
        return ____exports.DEFAULTS[feature]
    end
    return value == true
end
Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
____exports.DEFAULTS = {
    LeaveCoreCreep = true,
    StackExecute = true,
    DoubleStack = true,
    JobChooser = true,
    CoreLastHit = true,
    CoreTrade = true,
    CoreLastHitDire = true,
    SupportDeny = true,
    SupportDenyDire = true,
    SupportLastHit = true,
    CoreDenyYield = true,
    PreHit = true,
    RuneRotation = true,
    RuneSpawn = true,
    SupportPull = true,
    LaneSpot = true,
    SupportHarass = true,
    LaneSpotTower = true,
    LaneSpotThreat = true,
    CoreLaneFight = true,
    LaneAggro = true,
    CoreContest = true,
    CoreHold = true,
    CoreCampTrip = true,
    SupportPullFarm = true,
    PreDeny = true,
    LaneControl = true,
    LaneControlDrive = true,
    CorePull = true,
    Threat = true,
    Retreat = true,
    RetreatOdds = false,
    HealStop = true,
    HealItems = false,
    ArbiterShadow = true
}
--- Every switch's value as `Name:1|0` in name order (telemetry: which arm a game ran when no --set shows it).
function ____exports.Describe()
    local names = {}
    for name in pairs(____exports.DEFAULTS) do
        names[#names + 1] = name
    end
    __TS__ArraySort(names)
    return table.concat(
        __TS__ArrayMap(
            names,
            function(____, n) return (n .. ":") .. tostring(____exports.On(n) and 1 or 0) end
        ),
        ","
    )
end
return ____exports
