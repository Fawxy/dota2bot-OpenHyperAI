--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
local Rune = ____dota.Rune
local FR = require(GetScriptDirectory().."/FunLib/humaniser/fight_readings")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {
    Spawn = 360,
    PlanAt = 360 - 40,
    StandRadii = {550, 750, 950},
    StandAngles = 16,
    LowPenalty = 1500,
    FarSidePenalty = 1000,
    Hide = 5,
    Early = 0.3,
    TakeMargin = 0.3,
    DenySwing = 0.5,
    RaceRadius = 3000,
    OwnAfter = 15
}
local plans = {}
function ____exports.ResetCache()
    for k in pairs(plans) do
        plans[k] = nil
    end
end
function ____exports.On()
    return Ours.On("RuneSpawn") and Ours.On("JobChooser") and Ours.On("RuneRotation")
end
function ____exports.Spots()
    return {Rune.Power1, Rune.Power2}
end
function ____exports.SpotAt(rune)
    return GetRuneSpawnLocation(rune)
end
function ____exports.Other(rune)
    return rune == Rune.Power1 and Rune.Power2 or Rune.Power1
end
local function teamHero(pos)
    do
        local i = 1
        while i <= 5 do
            local m = GetTeamMember(i)
            if m ~= nil and m ~= nil and m:IsBot() and LaneConfig.PositionOf(m) == pos then
                return m
            end
            i = i + 1
        end
    end
    return nil
end
local function nearer(u, a, b)
    return GetUnitToLocationDistance(
        u,
        ____exports.SpotAt(a)
    ) <= GetUnitToLocationDistance(
        u,
        ____exports.SpotAt(b)
    ) and a or b
end
--- The spot plan from plain choices: `mid` takes the spot nearer it; the other spot goes to the free support with the
-- shorter walk to it (pos4 on a tie). `busy(u)` says a support is not free (a stack that minute). Exported for tests.
function ____exports.Make(now, busy)
    local a, b = unpack(____exports.Spots())
    local mid = teamHero(2)
    local plan = {at = now}
    if FR.Alive(mid) then
        plan.mid = mid
        plan.midSpot = nearer(mid, a, b)
    end
    local supSpot = plan.midSpot ~= nil and ____exports.Other(plan.midSpot) or nil
    local best
    local bestD = math.huge
    for ____, pos in ipairs({4, 5}) do
        do
            local __continue14
            repeat
                local s = teamHero(pos)
                if not FR.Alive(s) or busy(s) then
                    __continue14 = true
                    break
                end
                local d = GetUnitToLocationDistance(
                    s,
                    ____exports.SpotAt(supSpot or nearer(s, a, b))
                )
                if d < bestD then
                    best, bestD = s, d
                end
                __continue14 = true
            until true
            if not __continue14 then
                break
            end
        end
    end
    if best ~= nil then
        plan.sup = best
        plan.supSpot = supSpot or nearer(best, a, b)
    else
        plan.why = "no-free-support"
    end
    if plan.mid == nil then
        plan.why = plan.why or "no-mid"
    end
    return plan
end
--- This team's plan for the 6:00 spawn, made once at PlanAt (undefined before, or with the switch off).
function ____exports.For(team, busy, now)
    if now == nil then
        now = DotaTime()
    end
    if not ____exports.On() or now < ____exports.SETTINGS.PlanAt or now > ____exports.SETTINGS.Spawn + 60 then
        return nil
    end
    local p = plans[team]
    if p == nil then
        p = ____exports.Make(now, busy)
        plans[team] = p
        local ____Telemetry_Event_5 = Telemetry.Event
        local ____array_4 = __TS__SparseArrayNew({"team", team})
        local ____opt_0 = p.mid
        __TS__SparseArrayPush(
            ____array_4,
            {
                "mid",
                ____opt_0 and ____opt_0:GetPlayerID()
            },
            {"ms", p.midSpot}
        )
        local ____opt_2 = p.sup
        __TS__SparseArrayPush(
            ____array_4,
            {
                "sup",
                ____opt_2 and ____opt_2:GetPlayerID()
            },
            {"ss", p.supSpot},
            {"why", p.why}
        )
        ____Telemetry_Event_5(
            "rune_plan",
            {__TS__SparseArraySpread(____array_4)}
        )
    end
    return p
end
--- The spot this hero holds in its team's plan, if any.
function ____exports.SpotOf(bot, busy, now)
    if now == nil then
        now = DotaTime()
    end
    local p = ____exports.For(
        bot:GetTeam(),
        busy,
        now
    )
    if p == nil then
        return nil
    end
    if p.mid == bot then
        return p.midSpot
    end
    if p.sup == bot then
        return p.supSpot
    end
    return nil
end
--- The planned hero at `spot` other than `bot`, if any.
function ____exports.HolderOf(team, spot)
    local p = plans[team]
    if p == nil then
        return nil
    end
    local ____temp_7
    if p.midSpot == spot then
        ____temp_7 = p.mid
    else
        local ____temp_6
        if p.supSpot == spot then
            ____temp_6 = p.sup
        else
            ____temp_6 = nil
        end
        ____temp_7 = ____temp_6
    end
    return ____temp_7
end
--- A stand point near `spot` for `bot`: passable points on rings around it, cheapest by the walk there and on to the spot,
-- with a penalty for one no higher than the spot or on the far side of the river. Falls back to the spot itself.
function ____exports.StandFor(bot, spot)
    local s = ____exports.SETTINGS
    local spotHeight = GetHeightLevel(spot)
    local home = GetAncient(bot:GetTeam()):GetLocation()
    local spotHome = FR.Dist(spot, home)
    local best = {at = spot, height = spotHeight, spotHeight = spotHeight}
    local bestCost = math.huge
    for ____, r in ipairs(s.StandRadii) do
        do
            local k = 0
            while k < s.StandAngles do
                do
                    local __continue32
                    repeat
                        local a = 2 * math.pi * k / s.StandAngles
                        local c = Vector(
                            spot.x + r * math.cos(a),
                            spot.y + r * math.sin(a),
                            spot.z
                        )
                        if not IsLocationPassable(c) then
                            __continue32 = true
                            break
                        end
                        local h = GetHeightLevel(c)
                        local cost = GetUnitToLocationDistance(bot, c) + FR.Dist(c, spot) + (h > spotHeight and 0 or s.LowPenalty) + (FR.Dist(c, home) > spotHome and s.FarSidePenalty or 0)
                        if cost < bestCost then
                            best, bestCost = {at = c, height = h, spotHeight = spotHeight}, cost
                        end
                        __continue32 = true
                    until true
                    if not __continue32 then
                        break
                    end
                end
                k = k + 1
            end
        end
    end
    return best
end
local function speedOf(u)
    return math.max(
        1,
        u:GetCurrentMovementSpeed()
    )
end
--- Seconds for `u` to walk to `at` in a straight line at its current speed.
function ____exports.WalkSecs(u, at)
    return GetUnitToLocationDistance(u, at) / speedOf(u)
end
--- The soonest any living enemy hero within RaceRadius could reach `at`, in seconds (math.huge with none).
function ____exports.EnemyArrival(at)
    local best = math.huge
    for ____, e in ipairs(FR.EnemiesNear(at, ____exports.SETTINGS.RaceRadius)) do
        best = math.min(
            best,
            FR.Dist(
                e:GetLocation(),
                at
            ) / speedOf(e)
        )
    end
    return best
end
--- At a spot holding the rune: take if we get there first by TakeMargin, deny if our hit lands before they arrive, else off.
function ____exports.RaceAt(i)
    if i.ours + ____exports.SETTINGS.TakeMargin <= i.theirs then
        return "take"
    end
    if i.oursDeny < i.theirs then
        return "deny"
    end
    return "off"
end
function ____exports.RaceInputsOf(bot, spot)
    local d = GetUnitToLocationDistance(bot, spot)
    return {
        ours = d / speedOf(bot),
        oursDeny = math.max(
            0,
            d - bot:GetAttackRange()
        ) / speedOf(bot) + ____exports.SETTINGS.DenySwing,
        theirs = ____exports.EnemyArrival(spot)
    }
end
--- What `bot`, planned at `mine`, does at the spawn. The rune at its spot: the race. The rune at the other spot: cross when
-- it would get there before every enemy hero and the other spot's planned hero would not (dead, or slower); else none.
-- Neither spot shows the rune yet: none (the caller waits a moment and asks again).
function ____exports.Race(bot, mine)
    if GetRuneStatus(mine) == RUNE_STATUS_AVAILABLE then
        local i = ____exports.RaceInputsOf(
            bot,
            ____exports.SpotAt(mine)
        )
        return {
            ____exports.RaceAt(i),
            i
        }
    end
    local other = ____exports.Other(mine)
    if GetRuneStatus(other) ~= RUNE_STATUS_AVAILABLE then
        return {"none", nil}
    end
    local at = ____exports.SpotAt(other)
    local i = ____exports.RaceInputsOf(bot, at)
    local holder = ____exports.HolderOf(
        bot:GetTeam(),
        other
    )
    local holderSecs = FR.Alive(holder) and holder ~= bot and ____exports.WalkSecs(holder, at) or math.huge
    return {i.ours + ____exports.SETTINGS.TakeMargin <= i.theirs and i.ours < holderSecs and "cross" or "none", i}
end
--- After a deny try: the rune left `rune`'s spot with an enemy hero within 200 of it (taken) or not (gone); undefined while it is there.
function ____exports.DenyResult(rune)
    if GetRuneStatus(rune) == RUNE_STATUS_AVAILABLE then
        return nil
    end
    return #FR.EnemiesNear(
        ____exports.SpotAt(rune),
        200
    ) > 0 and "taken" or "gone"
end
--- When `bot` should leave for its stand: so it stands Hide seconds before walking in to arrive Early before the spawn.
function ____exports.LeaveAt(bot, stand, spot)
    local walkIn = FR.Dist(stand, spot) / speedOf(bot)
    return ____exports.SETTINGS.Spawn - ____exports.SETTINGS.Early - walkIn - ____exports.SETTINGS.Hide - ____exports.WalkSecs(bot, stand) * 1.2
end
--- The mid's side of the plan holds it now: from its leave time until OwnAfter after the spawn.
function ____exports.OwnsMid(bot, now)
    if now == nil then
        now = DotaTime()
    end
    if not ____exports.On() or now < ____exports.SETTINGS.PlanAt or now > ____exports.SETTINGS.Spawn + ____exports.SETTINGS.OwnAfter then
        return false
    end
    local p = plans[bot:GetTeam()]
    return p ~= nil and p.mid == bot
end
return ____exports
