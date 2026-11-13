--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
--- Units further than this from both the bot and its lane front are left out: Compute queries 1,600 from the bot, but a bot
-- walking back to lane reads its walk to a spot by the front (smoke 1: 5 of 60 cuts lost a hero 3,500 from the bot).
local CUT_R = 3000
local function near(l, a, b)
    return math.abs(l.x - a.x) <= CUT_R and math.abs(l.y - a.y) <= CUT_R or math.abs(l.x - b.x) <= CUT_R and math.abs(l.y - b.y) <= CUT_R
end
--- The vision grid's cell size, and how far past the bot and its front it reaches (Threat's walk points).
local GRID_STEP = 250
local GRID_PAD = 1600
local MAX_PLAYER_ID = 23
--- Threat's TOWER_IDS order; `ta` bit i is this list's i-th tower.
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
local towersLogged = {}
local function f(n)
    return n == nil and -1 or math.floor(n + 0.5)
end
local function live(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:GetLocation() ~= nil
end
local function targetOf(u, bot)
    local t = u:GetAttackTarget()
    if t == nil or t == nil or t:IsNull() then
        return "-"
    end
    if t == bot then
        return "b"
    end
    if t:IsHero() and not t:IsIllusion() then
        return "h" .. tostring(t:GetPlayerID())
    end
    return "u" .. tostring(Telemetry.CreepId(t))
end
local function creeps(kind, bot, at, front)
    local out = {}
    for ____, c in ipairs(GetUnitList(kind) or ({})) do
        do
            local __continue10
            repeat
                if not live(c) or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue10 = true
                    break
                end
                local l = c:GetLocation()
                if not near(l, at, front) then
                    __continue10 = true
                    break
                end
                local ranged = (string.find(
                    c:GetUnitName(),
                    "ranged",
                    1,
                    true
                )) ~= nil and 1 or 0
                out[#out + 1] = table.concat(
                    {
                        Telemetry.CreepId(c),
                        f(l.x),
                        f(l.y),
                        f(c:GetHealth()),
                        f(c:GetMaxHealth()),
                        ranged,
                        targetOf(c, bot),
                        f(c:GetBoundingRadius())
                    },
                    ","
                )
                __continue10 = true
            until true
            if not __continue10 then
                break
            end
        end
    end
    return table.concat(out, ";")
end
local function escapeReady(bot)
    for ____, name in ipairs(Threat.SETTINGS.EscapeItems) do
        do
            local __continue15
            repeat
                local slot = bot:FindItemSlot(name)
                if slot < 0 or slot > 5 then
                    __continue15 = true
                    break
                end
                local item = bot:GetItemInSlot(slot)
                if item ~= nil and item ~= nil and item:IsFullyCastable() then
                    return true
                end
                __continue15 = true
            until true
            if not __continue15 then
                break
            end
        end
    end
    return false
end
--- IsLocationVisible on a grid over the box around the bot and its lane front (GRID_PAD past both), as `x0,y0,nx,ny,step,hex`:
-- bit i of the hex is cell (i % nx, floor(i / nx)) from the south-west corner (x0, y0).
local function visionGrid(at, front)
    local x0 = math.floor((math.min(at.x, front.x) - GRID_PAD) / GRID_STEP) * GRID_STEP
    local y0 = math.floor((math.min(at.y, front.y) - GRID_PAD) / GRID_STEP) * GRID_STEP
    local nx = math.ceil((math.max(at.x, front.x) + GRID_PAD - x0) / GRID_STEP) + 1
    local ny = math.ceil((math.max(at.y, front.y) + GRID_PAD - y0) / GRID_STEP) + 1
    local hex = ""
    local nib = 0
    local bits = 0
    do
        local j = 0
        while j < ny do
            do
                local i = 0
                while i < nx do
                    nib = nib * 2 + (IsLocationVisible(Vector(x0 + i * GRID_STEP, y0 + j * GRID_STEP, at.z)) and 1 or 0)
                    bits = bits + 1
                    if bits == 4 then
                        hex = hex .. string.format("%x", nib)
                        nib = 0
                        bits = 0
                    end
                    i = i + 1
                end
            end
            j = j + 1
        end
    end
    if bits > 0 then
        hex = hex .. string.format("%x", nib * 2 ^ (4 - bits))
    end
    return (((((((((tostring(x0) .. ",") .. tostring(y0)) .. ",") .. tostring(nx)) .. ",") .. tostring(ny)) .. ",") .. tostring(GRID_STEP)) .. ",") .. hex
end
local function logTowers(team)
    if towersLogged[team] then
        return
    end
    towersLogged[team] = true
    local out = {}
    do
        local i = 0
        while i < #____exports.TOWER_IDS do
            do
                local __continue26
                repeat
                    local tw = GetTower(team, ____exports.TOWER_IDS[i + 1])
                    if not live(tw) then
                        __continue26 = true
                        break
                    end
                    local l = tw:GetLocation()
                    out[#out + 1] = table.concat(
                        {
                            i,
                            f(l.x),
                            f(l.y),
                            f(tw:GetAttackRange()),
                            f(tw:GetBoundingRadius())
                        },
                        ","
                    )
                    __continue26 = true
                until true
                if not __continue26 then
                    break
                end
            end
            i = i + 1
        end
    end
    Telemetry.Event(
        "cut_towers",
        {
            {"team", team},
            {
                "tw",
                table.concat(out, ";")
            }
        }
    )
end
--- The towers standing, as a hex mask over TOWER_IDS, and the attack targets of those within CUT_R of `at`.
local function towersNow(team, bot, at, front, out)
    local mask = 0
    do
        local i = 0
        while i < #____exports.TOWER_IDS do
            do
                local __continue29
                repeat
                    local tw = GetTower(team, ____exports.TOWER_IDS[i + 1])
                    if not live(tw) then
                        __continue29 = true
                        break
                    end
                    mask = mask + 2 ^ i
                    local l = tw:GetLocation()
                    if near(l, at, front) then
                        out[#out + 1] = table.concat(
                            {
                                team,
                                i,
                                targetOf(tw, bot)
                            },
                            ","
                        )
                    end
                    __continue29 = true
                until true
                if not __continue29 then
                    break
                end
            end
            i = i + 1
        end
    end
    return string.format("%x", mask)
end
--- The spot's inputs this frame, beside its ev=lane_pos line.
function ____exports.Spot(bot)
    local pid = bot:GetPlayerID()
    local team = bot:GetTeam()
    local enemyTeam = team == Team.Radiant and Team.Dire or Team.Radiant
    local lane = bot:GetAssignedLane()
    local at = bot:GetLocation()
    local role, fed, hold = Laning.SpotInputs(bot)
    logTowers(team)
    logTowers(enemyTeam)
    local front = GetLaneFrontLocation(team, lane, 0)
    local back = GetLaneFrontLocation(team, lane, -400)
    local visible = {}
    local he = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue33
            repeat
                if not live(e) or not e:CanBeSeen() then
                    __continue33 = true
                    break
                end
                local l = e:GetLocation()
                local ill = e:IsIllusion()
                if not ill then
                    visible[e:GetPlayerID()] = true
                end
                if not near(l, at, front) then
                    __continue33 = true
                    break
                end
                local e3 = e:GetEstimatedDamageToTarget(true, bot, 3, DamageType.All)
                local e6 = e:GetEstimatedDamageToTarget(true, bot, 6, DamageType.All)
                local atk = e:GetAttackTarget() == bot and 1 or 0
                local eng = bot:WasRecentlyDamagedByHero(e, Threat.SETTINGS.EngagedRecent) and 1 or 0
                he[#he + 1] = table.concat(
                    {
                        e:GetPlayerID(),
                        f(l.x),
                        f(l.y),
                        f(e:GetHealth()),
                        f(e:GetAttackRange()),
                        f(e:GetBoundingRadius()),
                        f(e:GetCurrentMovementSpeed()),
                        atk,
                        eng,
                        f(e3),
                        f(e6),
                        ill and 1 or 0
                    },
                    ","
                )
                __continue33 = true
            until true
            if not __continue33 then
                break
            end
        end
    end
    local hu = {}
    do
        local p = 0
        while p <= MAX_PLAYER_ID do
            do
                local __continue38
                repeat
                    if GetTeamForPlayer(p) ~= enemyTeam or visible[p] == true or not IsHeroAlive(p) then
                        __continue38 = true
                        break
                    end
                    local info = GetHeroLastSeenInfo(p)[1]
                    if info == nil then
                        __continue38 = true
                        break
                    end
                    hu[#hu + 1] = table.concat(
                        {
                            p,
                            f(info.location.x),
                            f(info.location.y),
                            math.floor(info.time_since_seen * 10 + 0.5) / 10,
                            f(Threat.SeenSpeed(p))
                        },
                        ","
                    )
                    __continue38 = true
                until true
                if not __continue38 then
                    break
                end
            end
            p = p + 1
        end
    end
    local ha = {}
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue41
            repeat
                if not live(a) or a == bot or a:IsIllusion() then
                    __continue41 = true
                    break
                end
                if not near(
                    a:GetLocation(),
                    at,
                    front
                ) then
                    __continue41 = true
                    break
                end
                local l = a:GetLocation()
                ha[#ha + 1] = table.concat(
                    {
                        a:GetPlayerID(),
                        f(l.x),
                        f(l.y),
                        f(a:GetAttackRange()),
                        f(a:GetBoundingRadius()),
                        f(a:GetCurrentMovementSpeed()),
                        RetreatState.Running(a) and 1 or 0
                    },
                    ","
                )
                __continue41 = true
            until true
            if not __continue41 then
                break
            end
        end
    end
    local nearTowers = {}
    local ta = (towersNow(
        team,
        bot,
        at,
        front,
        nearTowers
    ) .. ",") .. towersNow(
        enemyTeam,
        bot,
        at,
        front,
        nearTowers
    )
    Telemetry.Event(
        "cut",
        {
            {"pid", pid},
            {"kind", "spot"},
            {"role", role},
            {"lane", lane},
            {
                "b",
                table.concat(
                    {
                        f(at.x),
                        f(at.y),
                        f(bot:GetHealth()),
                        f(bot:GetMaxHealth()),
                        f(bot:GetAttackRange()),
                        f(bot:GetBoundingRadius()),
                        f(bot:GetCurrentMovementSpeed()),
                        escapeReady(bot) and 1 or 0
                    },
                    ","
                )
            },
            {
                "fr",
                table.concat(
                    {
                        f(front.x),
                        f(front.y),
                        f(back.x),
                        f(back.y)
                    },
                    ","
                )
            },
            {
                "fed",
                live(fed) and Telemetry.CreepId(fed) or nil
            },
            {
                "hold",
                hold ~= nil and (tostring(f(hold.x)) .. ",") .. tostring(f(hold.y)) or nil
            },
            {
                "he",
                table.concat(he, ";")
            },
            {
                "hu",
                #hu > 0 and table.concat(hu, ";") or nil
            },
            {
                "ha",
                #ha > 0 and table.concat(ha, ";") or nil
            },
            {"ta", ta},
            {
                "tt",
                table.concat(nearTowers, ";")
            },
            {
                "vis",
                #hu > 0 and visionGrid(at, front) or nil
            }
        }
    )
    Telemetry.Event(
        "cut_creeps",
        {
            {"pid", pid},
            {
                "ce",
                creeps(UnitType.EnemyCreeps, bot, at, front)
            },
            {
                "ca",
                creeps(UnitType.AlliedCreeps, bot, at, front)
            }
        }
    )
end
return ____exports
