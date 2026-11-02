--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local frac, valid, keepWhy, MIN_HP, BEHIND_BY, KILL_HP, MAX_WAVE, MAX_CREEPS_ON_ME, TRADE_TIME, KILL_TIME, REACH, NEAR, CREEP_AGGRO, TOWER_REACH, LOST_AFTER
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- Whether a trade (or kill) is on against a target with these inputs, or why not.
function ____exports.Decide(i)
    if i.tower then
        return {respect = "tower"}
    end
    if i.enemiesNear > i.alliesNear then
        return {respect = "outnumbered"}
    end
    if i.targetHp <= KILL_HP and i.hp >= i.targetHp then
        return {kind = "kill"}
    end
    if i.hp < MIN_HP then
        return {respect = "low_hp"}
    end
    if i.hp < i.targetHp - BEHIND_BY then
        return {respect = "behind"}
    end
    if i.hitByCreeps >= MAX_CREEPS_ON_ME then
        return {respect = "creeps"}
    end
    if i.enemyCreepsNear > MAX_WAVE then
        return {respect = "wave"}
    end
    return {kind = "trade"}
end
function frac(u)
    return u:GetHealth() / math.max(
        1,
        u:GetMaxHealth()
    )
end
function valid(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:CanBeSeen() and not u:IsIllusion()
end
function ____exports.Gather(bot, target)
    local enemiesNear = 0
    for ____, h in ipairs(bot:GetNearbyHeroes(NEAR, true, BotMode.None)) do
        if valid(h) then
            enemiesNear = enemiesNear + 1
        end
    end
    local alliesNear = 0
    for ____, h in ipairs(bot:GetNearbyHeroes(NEAR, false, BotMode.None)) do
        if h:IsAlive() and not h:IsIllusion() then
            alliesNear = alliesNear + 1
        end
    end
    local enemyCreepsNear = 0
    local hitByCreeps = 0
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(CREEP_AGGRO, true)) do
        do
            local __continue26
            repeat
                if not c:IsAlive() then
                    __continue26 = true
                    break
                end
                enemyCreepsNear = enemyCreepsNear + 1
                if c:GetAttackTarget() == bot then
                    hitByCreeps = hitByCreeps + 1
                end
                __continue26 = true
            until true
            if not __continue26 then
                break
            end
        end
    end
    local tower = false
    for ____, t in ipairs(bot:GetNearbyTowers(TOWER_REACH + 1000, true)) do
        do
            local __continue30
            repeat
                if not t:IsAlive() then
                    __continue30 = true
                    break
                end
                if GetUnitToUnitDistance(bot, t) <= TOWER_REACH or GetUnitToUnitDistance(target, t) <= TOWER_REACH then
                    tower = true
                end
                if t:GetAttackTarget() == bot then
                    hitByCreeps = hitByCreeps + MAX_CREEPS_ON_ME
                end
                __continue30 = true
            until true
            if not __continue30 then
                break
            end
        end
    end
    return {
        hp = frac(bot),
        targetHp = frac(target),
        enemiesNear = enemiesNear,
        alliesNear = math.max(1, alliesNear),
        enemyCreepsNear = enemyCreepsNear,
        hitByCreeps = hitByCreeps,
        tower = tower
    }
end
function keepWhy(bot, ep, now)
    local t = ep.target
    if not valid(t) then
        return (ep.target:IsNull() or not ep.target:IsAlive()) and "target_dead" or "target_lost"
    end
    if ep.startedAt == nil then
        return now - ep.offeredAt > LOST_AFTER and "not_taken" or nil
    end
    if now - ep.startedAt > (ep.kind == "kill" and KILL_TIME or TRADE_TIME) then
        return "time"
    end
    local reach = bot:GetAttackRange() + bot:GetBoundingRadius() * 2 + REACH
    if ep.kind == "trade" and GetUnitToUnitDistance(bot, ep.target) > reach then
        return "out_of_reach"
    end
    local d = ____exports.Decide(____exports.Gather(bot, ep.target))
    if d.kind == nil then
        return d.respect
    end
    return nil
end
____exports.DESIRE_TRADE = 0.6
____exports.DESIRE_KILL = 0.75
MIN_HP = 0.5
BEHIND_BY = 0.15
KILL_HP = 0.25
MAX_WAVE = 3
MAX_CREEPS_ON_ME = 2
TRADE_TIME = 3
local TRADE_REST = 3
KILL_TIME = 6
REACH = 100
NEAR = 1200
CREEP_AGGRO = 500
TOWER_REACH = 850
--- Within this of its assigned lane's path the core is in lane (fight_read's LANE_WIDTH).
local LANE_WIDTH = 1200
LOST_AFTER = 1
local episodes = {}
local restUntil = {}
--- Which arm this frame's GetDesire took: Think follows it.
local ownsFrame = {}
--- Load-time: whether mode_attack_generic gives this bot our desire and Think in lane (and OHA's port outside it).
function ____exports.Owns(bot)
    return Ours.On("CoreTrade") and CoreLastHit.Applies(bot)
end
--- The core lanes: laning phase for it (transitions/phase) and standing by its own lane; elsewhere OHA's port fights.
local function inLane(bot)
    return Phase.IsLaningFor(bot) and GetAmountAlongLane(
        bot:GetAssignedLane(),
        bot:GetLocation()
    ).distance <= LANE_WIDTH
end
local function nearestTarget(bot)
    local reach = bot:GetAttackRange() + bot:GetBoundingRadius() * 2 + REACH
    local best
    local bestD = math.huge
    for ____, h in ipairs(bot:GetNearbyHeroes(reach, true, BotMode.None)) do
        do
            local __continue15
            repeat
                if not valid(h) then
                    __continue15 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if d < bestD then
                    best = h
                    bestD = d
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
local function close(bot, ep, why, now)
    local pid = bot:GetPlayerID()
    episodes[pid] = nil
    local started = ep.startedAt ~= nil
    if started then
        restUntil[pid] = now + TRADE_REST
    end
    local killed = started and (ep.target:IsNull() or not ep.target:IsAlive())
    local thp = not ep.target:IsNull() and ep.target:IsAlive() and ep.target:GetHealth() or 0
    local i = ep.inputs
    Telemetry.Event(
        "trade",
        {
            {"pid", pid},
            {"kind", ep.kind},
            {"tgt", ep.tpid},
            {"result", started and (killed and "kill" or "done") or "lost"},
            {"why", why},
            {
                "dur",
                started and math.floor((now - ep.startedAt) * 10) / 10 or 0
            },
            {
                "hpd",
                started and ep.hp0 - bot:GetHealth() or 0
            },
            {"thpd", started and ep.thp0 - thp or 0},
            {
                "hp",
                math.floor(i.hp * 100) / 100
            },
            {
                "thp",
                math.floor(i.targetHp * 100) / 100
            },
            {"en", i.enemiesNear},
            {"al", i.alliesNear},
            {"cr", i.enemyCreepsNear},
            {
                "mode",
                bot:GetActiveMode()
            }
        }
    )
end
--- The in-lane attack desire, or undefined outside lane (the caller then asks OHA's port). Opens, keeps and ends the
-- bot's trade episode; a window attack mode never took is logged as `lost` with the mode that held the bot.
function ____exports.Desire(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local ep = episodes[pid]
    if not bot:IsAlive() or not inLane(bot) then
        if ep ~= nil then
            close(
                bot,
                ep,
                bot:IsAlive() and "lane_end" or "dead",
                now
            )
        end
        ownsFrame[pid] = false
        local ____bot_IsAlive_result_0
        if bot:IsAlive() then
            ____bot_IsAlive_result_0 = nil
        else
            ____bot_IsAlive_result_0 = 0
        end
        return ____bot_IsAlive_result_0
    end
    ownsFrame[pid] = true
    if ep ~= nil then
        local why = keepWhy(bot, ep, now)
        if why == nil then
            return ep.kind == "kill" and ____exports.DESIRE_KILL or ____exports.DESIRE_TRADE
        end
        close(bot, ep, why, now)
        ep = nil
    end
    if now < (restUntil[pid] or -math.huge) then
        return 0
    end
    local target = nearestTarget(bot)
    if target == nil then
        return 0
    end
    local inputs = ____exports.Gather(bot, target)
    local d = ____exports.Decide(inputs)
    if d.kind == nil then
        return 0
    end
    episodes[pid] = {
        kind = d.kind,
        target = target,
        tpid = target:GetPlayerID(),
        offeredAt = now,
        hp0 = bot:GetHealth(),
        thp0 = target:GetHealth(),
        inputs = inputs
    }
    return d.kind == "kill" and ____exports.DESIRE_KILL or ____exports.DESIRE_TRADE
end
--- Whether this frame's GetDesire took our arm; mode_attack_generic's Think runs ours when true, OHA's port otherwise.
function ____exports.OwnsFrame(bot)
    return ownsFrame[bot:GetPlayerID()] == true
end
function ____exports.Think(bot)
    local ep = episodes[bot:GetPlayerID()]
    if ep == nil or not valid(ep.target) then
        return
    end
    if ep.startedAt == nil then
        ep.startedAt = DotaTime()
    end
    if bot:GetAttackTarget() ~= ep.target then
        bot:Action_AttackUnit(ep.target, false)
    end
end
--- Attack mode lost the bot to another mode: a running trade ends there.
function ____exports.OnEnd(bot)
    local ep = episodes[bot:GetPlayerID()]
    if ep ~= nil and ep.startedAt ~= nil then
        close(
            bot,
            ep,
            "mode_" .. tostring(bot:GetActiveMode()),
            DotaTime()
        )
    end
end
--- Laning's 0.9 last-hit desire must not cut a retreat this context's core is already in (core-time-diagnosis s2: a death
-- within 15 s of such a cut was 4 times as likely). A predicate on the laning GetDesire (OWNERSHIP H2).
function ____exports.LastHitYieldsToRetreat(bot)
    return CoreLastHit.Applies(bot) and bot:GetActiveMode() == BotMode.Retreat
end
function ____exports.Reset()
    for k in pairs(episodes) do
        episodes[k] = nil
    end
    for k in pairs(restUntil) do
        restUntil[k] = nil
    end
    for k in pairs(ownsFrame) do
        ownsFrame[k] = nil
    end
end
return ____exports
