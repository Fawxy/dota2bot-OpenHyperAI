--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local frac, valid, keepWhy, stepOutPoint, MIN_HP, BEHIND_BY, KILL_HP, MAX_WAVE, MAX_CREEPS_ON_ME, KEEP_HP_SLACK, KEEP_WAVE_SLACK, LOSING_BY, KILL_TIME, REACH, NEAR, CREEP_AGGRO, TOWER_REACH, AGGRO_CLEAR, AGGRO_COOLDOWN, COOLDOWN_LEFT, STEP_OUT_LIMIT, LOST_AFTER, primedAt
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- Whether a trade (or kill) is on against a target with these inputs, or why not. `running`: the trade is already under way, so
-- the borders get their slack.
function ____exports.Decide(i, running)
    if running == nil then
        running = false
    end
    local slack = running and KEEP_HP_SLACK or 0
    if i.tower then
        return {respect = "tower"}
    end
    if i.enemiesNear > i.alliesNear then
        return {respect = "outnumbered"}
    end
    if i.targetHp <= KILL_HP and i.hp >= i.targetHp then
        return {kind = "kill"}
    end
    if i.hp < MIN_HP - slack then
        return {respect = "low_hp"}
    end
    if i.hp < i.targetHp - BEHIND_BY - slack then
        return {respect = "behind"}
    end
    if i.hitByCreeps >= MAX_CREEPS_ON_ME then
        return {respect = "creeps"}
    end
    if i.enemyCreepsNear > MAX_WAVE + (running and KEEP_WAVE_SLACK or 0) then
        return {respect = "wave"}
    end
    return {kind = "trade"}
end
--- HP the core lost beyond what the target lost since `hp0`/`thp0`, as a share of the core's max HP (positive: losing).
-- Absolute HP on both sides, so a big hero is not judged against a small one's fractions.
function ____exports.Deficit(hp0, hp, thp0, thp, maxHp)
    return (hp0 - hp - (thp0 - thp)) / math.max(1, maxHp)
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
            local __continue29
            repeat
                if not c:IsAlive() then
                    __continue29 = true
                    break
                end
                enemyCreepsNear = enemyCreepsNear + 1
                if c:GetAttackTarget() == bot then
                    hitByCreeps = hitByCreeps + 1
                end
                __continue29 = true
            until true
            if not __continue29 then
                break
            end
        end
    end
    local tower = false
    for ____, t in ipairs(bot:GetNearbyTowers(TOWER_REACH + 1000, true)) do
        do
            local __continue33
            repeat
                if not t:IsAlive() then
                    __continue33 = true
                    break
                end
                if GetUnitToUnitDistance(bot, t) <= TOWER_REACH or GetUnitToUnitDistance(target, t) <= TOWER_REACH then
                    tower = true
                end
                if t:GetAttackTarget() == bot then
                    hitByCreeps = hitByCreeps + MAX_CREEPS_ON_ME
                end
                __continue33 = true
            until true
            if not __continue33 then
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
    if ep.kind == "kill" then
        if now - ep.startedAt > KILL_TIME then
            return "time"
        end
    else
        if ep.stepSince ~= nil and now - ep.stepSince > STEP_OUT_LIMIT then
            return "no_clear"
        end
        local reach = bot:GetAttackRange() + bot:GetBoundingRadius() * 2 + REACH
        local primed = primedAt[bot:GetPlayerID()]
        local walkingIn = primed ~= nil and now - primed < AGGRO_COOLDOWN - COOLDOWN_LEFT
        if ep.stepSince == nil and not walkingIn and GetUnitToUnitDistance(bot, ep.target) > reach then
            return "out_of_reach"
        end
        if ____exports.Deficit(
            ep.hp0,
            bot:GetHealth(),
            ep.thp0,
            ep.target:GetHealth(),
            bot:GetMaxHealth()
        ) > LOSING_BY then
            return "losing"
        end
    end
    local d = ____exports.Decide(
        ____exports.Gather(bot, ep.target),
        true
    )
    if d.kind == nil then
        return d.respect
    end
    return nil
end
function stepOutPoint(bot, creeps)
    local me = bot:GetLocation()
    local x = 0
    local y = 0
    local seen = 0
    for ____, c in ipairs(creeps) do
        do
            local __continue74
            repeat
                local l = c:GetLocation()
                if l == nil then
                    __continue74 = true
                    break
                end
                x = x + l.x
                y = y + l.y
                seen = seen + 1
                __continue74 = true
            until true
            if not __continue74 then
                break
            end
        end
    end
    x = seen > 0 and x / seen or me.x
    y = seen > 0 and y / seen or me.y
    local dx = me.x - x
    local dy = me.y - y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then
        local back = GetLocationAlongLane(
            bot:GetAssignedLane(),
            math.max(
                0,
                GetAmountAlongLane(
                    bot:GetAssignedLane(),
                    me
                ).amount - 0.05
            )
        )
        dx = back.x - me.x
        dy = back.y - me.y
    end
    local n = math.max(
        1,
        math.sqrt(dx * dx + dy * dy)
    )
    return Vector(x + dx / n * (AGGRO_CLEAR + 100), y + dy / n * (AGGRO_CLEAR + 100), me.z)
end
____exports.DESIRE_TRADE = 0.6
____exports.DESIRE_KILL = 0.75
MIN_HP = 0.5
BEHIND_BY = 0.15
KILL_HP = 0.25
MAX_WAVE = 3
MAX_CREEPS_ON_ME = 2
KEEP_HP_SLACK = 0.05
KEEP_WAVE_SLACK = 1
LOSING_BY = 0.05
KILL_TIME = 6
REACH = 100
NEAR = 1200
CREEP_AGGRO = 500
TOWER_REACH = 850
--- Within this of its assigned lane's path the core is in lane (fight_read's LANE_WIDTH).
local LANE_WIDTH = 1200
AGGRO_CLEAR = 550
AGGRO_COOLDOWN = 3
COOLDOWN_LEFT = 0.3
STEP_OUT_LIMIT = 2
LOST_AFTER = 1
--- CANDIDATE(aggroFreeAttack): Support in lane's harass is the second consumer, then the engine's. What a trading hero does this
-- frame so its hits draw no creep aggro: `attack` while its own attack order's cooldown covers it; `prime` (a fresh attack
-- order) when no enemy lane creep is within AGGRO_CLEAR; otherwise `step_out` of the creeps first.
function ____exports.AggroPlan(now, primedAt, creepsWithinClear)
    if primedAt ~= nil and now - primedAt < AGGRO_COOLDOWN - COOLDOWN_LEFT then
        return "attack"
    end
    return creepsWithinClear == 0 and "prime" or "step_out"
end
local episodes = {}
--- After a trade lost on the exchange: the core's HP fraction minus the target's when that trade began. No new trade until the
-- gap is back there (the core regained what it lost relative to the enemy), instead of a fixed wait.
local recoverTo = {}
--- Which arm this frame's GetDesire took: Think follows it.
local ownsFrame = {}
primedAt = {}
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
            local __continue18
            repeat
                if not valid(h) then
                    __continue18 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if d < bestD then
                    best = h
                    bestD = d
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
local function close(bot, ep, why, now)
    local pid = bot:GetPlayerID()
    episodes[pid] = nil
    local started = ep.startedAt ~= nil
    if started and why == "losing" then
        recoverTo[pid] = ep.inputs.hp - ep.inputs.targetHp
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
            {"pr", ep.primes},
            {"so", ep.stepOuts},
            {"ag", ep.aggro},
            {
                "mode",
                bot:GetActiveMode()
            },
            {
                "md",
                math.floor(bot:GetActiveModeDesire() * 100) / 100
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
    if ep ~= nil and ep.ended then
        close(
            bot,
            ep,
            "mode_" .. tostring(bot:GetActiveMode()),
            now
        )
        ep = nil
    end
    if ep ~= nil then
        local why = keepWhy(bot, ep, now)
        if why == nil then
            return ep.kind == "kill" and ____exports.DESIRE_KILL or ____exports.DESIRE_TRADE
        end
        close(bot, ep, why, now)
        ep = nil
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
    local gap = recoverTo[pid]
    if d.kind == "trade" and gap ~= nil then
        if inputs.hp - inputs.targetHp < gap - 0.000001 then
            return 0
        end
        recoverTo[pid] = nil
    end
    episodes[pid] = {
        kind = d.kind,
        target = target,
        tpid = target:GetPlayerID(),
        offeredAt = now,
        hp0 = bot:GetHealth(),
        thp0 = target:GetHealth(),
        inputs = inputs,
        primes = 0,
        stepOuts = 0,
        aggro = 0
    }
    return d.kind == "kill" and ____exports.DESIRE_KILL or ____exports.DESIRE_TRADE
end
--- Whether this frame's GetDesire took our arm; mode_attack_generic's Think runs ours when true, OHA's port otherwise.
function ____exports.OwnsFrame(bot)
    return ownsFrame[bot:GetPlayerID()] == true
end
function ____exports.Think(bot)
    local pid = bot:GetPlayerID()
    local ep = episodes[pid]
    if ep == nil or not valid(ep.target) then
        return
    end
    local now = DotaTime()
    if ep.startedAt == nil then
        ep.startedAt = now
    end
    local creeps = {}
    local onMe = 0
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(AGGRO_CLEAR, true)) do
        do
            local __continue64
            repeat
                if c:IsNull() or not c:IsAlive() then
                    __continue64 = true
                    break
                end
                creeps[#creeps + 1] = c
                if c:GetAttackTarget() == bot then
                    onMe = onMe + 1
                end
                __continue64 = true
            until true
            if not __continue64 then
                break
            end
        end
    end
    ep.aggro = math.max(ep.aggro, onMe)
    local plan = ep.kind == "kill" and "attack" or ____exports.AggroPlan(now, primedAt[pid], #creeps)
    if plan == "step_out" then
        if ep.stepSince == nil then
            ep.stepSince = now
            ep.stepOuts = ep.stepOuts + 1
        end
        bot:Action_MoveToLocation(stepOutPoint(bot, creeps))
        return
    end
    ep.stepSince = nil
    if plan == "prime" then
        primedAt[pid] = now
        ep.primes = ep.primes + 1
        bot:Action_AttackUnit(ep.target, false)
        return
    end
    if bot:GetAttackTarget() ~= ep.target then
        if ep.kind == "kill" then
            primedAt[pid] = now
        end
        bot:Action_AttackUnit(ep.target, false)
    end
end
--- Attack mode lost the bot to another mode: a running trade ends there (closed by the next Desire, which can name that mode).
function ____exports.OnEnd(bot)
    local ep = episodes[bot:GetPlayerID()]
    if ep ~= nil and ep.startedAt ~= nil then
        ep.ended = true
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
    for k in pairs(recoverTo) do
        recoverTo[k] = nil
    end
    for k in pairs(primedAt) do
        primedAt[k] = nil
    end
    for k in pairs(ownsFrame) do
        ownsFrame[k] = nil
    end
end
return ____exports
