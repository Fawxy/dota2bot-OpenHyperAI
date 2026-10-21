--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Pings = require(GetScriptDirectory().."/FunLib/humaniser/pings")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
function ____exports.IsBusyPure(i)
    local cfg = Settings.Get()
    if i.order then
        return true, "order"
    end
    if i.campJob then
        return true, "job"
    end
    if i.fighting then
        return true, "fight"
    end
    if i.retreating then
        return true, "retreat"
    end
    if i.dead and (i.respawnAfter == nil or i.respawnAfter > i.windowEnd) then
        return true, "dead"
    end
    if not i.dead and i.hp < cfg.BusyHP then
        return true, "hp"
    end
    if not i.dead and i.mana < cfg.BusyMana then
        return true, "mana"
    end
    if i.carrying then
        return true, "item"
    end
    if i.humanPingOnLane then
        return true, "ping"
    end
    return false, ""
end
function ____exports.LaneCanSparePure(i)
    local cfg = Settings.Get()
    if i.humanAskedStay then
        return false, "asked to stay"
    end
    if i.partnerHP < (i.strict and cfg.Pos5PartnerHP or cfg.SparePartnerHP) then
        return false, "partner hp"
    end
    if i.eqPos < cfg.SpareEq and not (i.plan == "FREEZE" and i.coreHealthy) then
        return false, "lane pushed"
    end
    if i.partnerCreepAggro >= cfg.SpareCreepAggro then
        return false, "creep aggro"
    end
    if i.enemyTpIncoming then
        return false, "enemy tp"
    end
    if i.strict and i.enemyNearPartner then
        return false, "enemy near"
    end
    for ____, e in ipairs(i.enemies) do
        if e.inKillPosition then
            return false, "kill position"
        end
        if not e.visible and e.sinceSeen > cfg.SpareSeenWithin then
            return false, "enemy missing"
        end
    end
    return true, "ok"
end
local tpProbe
--- Task 6 registers the enemy-teleport reader here.
function ____exports.SetTpProbe(fn)
    tpProbe = fn
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function frac(cur, max)
    return max > 0 and cur / max or 1
end
local function isFightMode(mode)
    return mode == BotMode.Attack or mode == BotMode.Roam or mode == BotMode.TeamRoam or mode == BotMode.DefendTowerTop or mode == BotMode.DefendTowerMid or mode == BotMode.DefendTowerBot or mode == BotMode.DefendAlly
end
local LANE_PING_RADIUS = 2000
function ____exports.IsBusy(bot, windowEnd)
    local cfg = Settings.Get()
    local alive = bot:IsAlive()
    local mode = bot:GetActiveMode()
    local team = bot:GetTeam()
    local ____exports_IsBusyPure_8 = ____exports.IsBusyPure
    local ____temp_1 = Orders.GetFor(bot) ~= nil
    local ____temp_2 = CampJobs.Active(bot) or CampJobs.UpcomingWithin(bot, 30)
    local ____temp_3 = isFightMode(mode) or LaneHooks.IsBusyByProbe(bot)
    local ____temp_4 = mode == BotMode.Retreat
    local ____temp_5 = alive and frac(
        bot:GetHealth(),
        bot:GetMaxHealth()
    ) or 0
    local ____temp_6 = alive and frac(
        bot:GetMana(),
        bot:GetMaxMana()
    ) or 0
    local ____temp_7 = not alive
    local ____alive_0
    if alive then
        ____alive_0 = nil
    else
        ____alive_0 = DotaTime() + bot:GetRespawnTime()
    end
    return ____exports_IsBusyPure_8({
        order = ____temp_1,
        campJob = ____temp_2,
        fighting = ____temp_3,
        retreating = ____temp_4,
        hp = ____temp_5,
        mana = ____temp_6,
        dead = ____temp_7,
        respawnAfter = ____alive_0,
        windowEnd = windowEnd,
        carrying = false,
        humanPingOnLane = Pings.HumanPingNear(
            team,
            GetLaneFrontLocation(
                team,
                bot:GetAssignedLane(),
                0
            ),
            LANE_PING_RADIUS,
            cfg.HumanPingWindow
        )
    })
end
function ____exports.LaneCanSpare(bot, strict)
    local cfg = Settings.Get()
    local s = LaneState.ForBot(bot)
    if s == nil then
        return false, "no lane"
    end
    local partner = LaneRoles.Partner(bot, s)
    if partner == nil then
        return false, "solo"
    end
    local enemies = LaneState.Enemies(bot, s.lane)
    local reading = LaneRoles.ReadPartner(bot, s, enemies)
    if reading == nil then
        return false, "solo"
    end
    local partnerLoc = partner.unit:GetLocation()
    local partnerLow = reading.hp < 0.5
    local spareEnemies = {}
    local near = false
    for ____, e in ipairs(enemies) do
        do
            local __continue32
            repeat
                if dist2D(e.location, s.frontLoc) > cfg.SpareLaneRadius then
                    __continue32 = true
                    break
                end
                local kill = false
                if e.visible and e.unit ~= nil then
                    local d = dist2D(e.location, partnerLoc)
                    kill = partnerLow and d <= e.unit:GetAttackRange() + 300
                    if d <= cfg.Pos5EnemyRadius then
                        near = true
                    end
                end
                spareEnemies[#spareEnemies + 1] = {visible = e.visible, sinceSeen = e.timeSinceSeen, inKillPosition = kill}
                __continue32 = true
            until true
            if not __continue32 then
                break
            end
        end
    end
    local aggro = 0
    for ____, creep in ipairs(s.enemy.units) do
        local target = creep:GetAttackTarget()
        if target ~= nil and target ~= nil and target:IsHero() and target:GetPlayerID() == partner.pid then
            aggro = aggro + 1
        end
    end
    local coreHP = LaneRoles.RoleIn(bot, s) == "support" and reading.hp or frac(
        bot:GetHealth(),
        bot:GetMaxHealth()
    )
    local asked = Orders.GetAcceptedForLane(bot, "LANE_NOPULL", s.lane) ~= nil or Orders.GetAcceptedForLane(bot, "LANE_HANDSOFF", s.lane) ~= nil or Pings.HumanPingNear(s.team, s.frontLoc, LANE_PING_RADIUS, cfg.HumanPingWindow)
    return ____exports.LaneCanSparePure({
        eqPos = s.eqPos,
        plan = LanePlan.View(bot, s).plan,
        coreHealthy = coreHP >= cfg.SparePartnerHP,
        partnerHP = reading.hp,
        partnerCreepAggro = aggro,
        enemies = spareEnemies,
        enemyTpIncoming = tpProbe ~= nil and tpProbe(bot),
        humanAskedStay = asked,
        strict = strict,
        enemyNearPartner = near
    })
end
return ____exports
