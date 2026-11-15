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

local function __TS__ArrayIncludes(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    local k = fromIndex
    if fromIndex < 0 then
        k = len + fromIndex
    end
    if k < 0 then
        k = 0
    end
    for i = k + 1, len do
        if self[i] == searchElement then
            return true
        end
    end
    return false
end
-- End of Lua Library inline imports
local ____exports = {}
local heldByGap, killHpFor, isSupport, reachOf, hitBackTarget, unanswered, inLane, frac, valid, freshDecision, hitBack, open, joinable, rollFight, keepWhy, stepOutPoint, MIN_HP, BEHIND_BY, KILL_HP, COMMIT_HP, FIGHT_ROLL_EVERY, FIGHT_TIME, JOIN_NEAR, JOIN_WALK, MAX_WAVE, MAX_CREEPS_ON_ME, KEEP_HP_SLACK, KEEP_WAVE_SLACK, LOSING_BY, KILL_TIME, JOIN_TIME, REACH, HARASS_REACH, NEAR, CREEP_AGGRO, LANE_WIDTH, AGGRO_CLEAR, AGGRO_COOLDOWN, COOLDOWN_LEFT, STEP_OUT_LIMIT, HIT_RECENT, HIT_BACK_WALK, LOST_AFTER, episodes, recoverTo, primedAt, rolledAt, HITTER_RADIUS, NO_EVERY, lastNo
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local CreepAggro = require(GetScriptDirectory().."/FunLib/humaniser/creep_aggro")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local SupportDeny = require(GetScriptDirectory().."/FunLib/humaniser/states/support_deny")
local FR = require(GetScriptDirectory().."/FunLib/humaniser/fight_readings")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local PairJoin = require(GetScriptDirectory().."/FunLib/humaniser/pair_join")
local Plays = require(GetScriptDirectory().."/FunLib/humaniser/plays/plays")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- Whether a trade (or kill) is on against a target with these inputs, or why not. `running`: the trade is already under way, so
-- the borders get their slack.
function ____exports.Decide(i, running, killHp, hitBack)
    if running == nil then
        running = false
    end
    if killHp == nil then
        killHp = KILL_HP
    end
    if hitBack == nil then
        hitBack = false
    end
    local slack = running and KEEP_HP_SLACK or 0
    if i.tower then
        return {respect = "tower"}
    end
    if i.enemiesNear > i.alliesNear then
        return {respect = "outnumbered"}
    end
    if i.targetHp <= killHp and i.hp >= i.targetHp then
        return {kind = "kill"}
    end
    if i.hp < MIN_HP - slack then
        return {respect = "low_hp"}
    end
    if not hitBack and i.hp < i.targetHp - BEHIND_BY - slack then
        return {respect = "behind"}
    end
    if i.hitByCreeps >= MAX_CREEPS_ON_ME then
        return {respect = "creeps"}
    end
    if not hitBack and i.enemyCreepsNear > MAX_WAVE + (running and KEEP_WAVE_SLACK or 0) then
        return {respect = "wave"}
    end
    return {kind = "trade"}
end
function heldByGap(i, gap)
    return gap ~= nil and i.hp - i.targetHp < gap - 0.000001
end
--- HP the core lost beyond what the target lost since `hp0`/`thp0`, as a share of the core's max HP (positive: losing).
-- Absolute HP on both sides, so a big hero is not judged against a small one's fractions.
function ____exports.Deficit(hp0, hp, thp0, thp, maxHp)
    return (hp0 - hp - (thp0 - thp)) / math.max(1, maxHp)
end
--- Slice lane-fight (`Ours.CoreLaneFight`, OWNERSHIP H9): every fight of this in-lane core beyond a trade is this module's. Team
-- roam keeps only its non-fight branches for it and LaneFight makes no claim (its gates close), so a commit is `kill` here.
-- Beyond the commit, in Desire's order: join a running play near it (`fight`, joined), else roll a `lane_fight` play when no
-- clear window decides (`fight`, rolled), else the trade rule. Supports keep OHA's team roam until `Ours.SupportLaneFight` is built.
function ____exports.OwnsLaneFights(bot)
    return Ours.On("CoreLaneFight") and Ours.On("CoreTrade") and CoreLastHit.Applies(bot) and bot:IsAlive() and inLane(bot)
end
function killHpFor(bot)
    return ____exports.OwnsLaneFights(bot) and COMMIT_HP or KILL_HP
end
function isSupport(bot)
    return not CoreLastHit.Applies(bot) and SupportDeny.Harass(bot)
end
function reachOf(bot)
    return bot:GetAttackRange() + bot:GetBoundingRadius() * 2 + (isSupport(bot) and HARASS_REACH or REACH)
end
function hitBackTarget(bot)
    if not Ours.On("HitBack") then
        return nil
    end
    local best
    local bestD = math.huge
    for ____, h in ipairs(bot:GetNearbyHeroes(
        reachOf(bot) + HIT_BACK_WALK,
        true,
        BotMode.None
    )) do
        do
            local __continue27
            repeat
                if not valid(h) or not bot:WasRecentlyDamagedByHero(h, HIT_RECENT) then
                    __continue27 = true
                    break
                end
                if not CreepAggro.Paid(bot, h) then
                    __continue27 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if d < bestD then
                    best = h
                    bestD = d
                end
                __continue27 = true
            until true
            if not __continue27 then
                break
            end
        end
    end
    return best
end
function unanswered(bot, now, why, i)
    local pid = bot:GetPlayerID()
    local last = lastNo[pid]
    if last ~= nil and now - last < NO_EVERY then
        return 0
    end
    local hitter
    local hd = math.huge
    for ____, h in ipairs(bot:GetNearbyHeroes(HITTER_RADIUS, true, BotMode.None)) do
        do
            local __continue34
            repeat
                if not valid(h) or not bot:WasRecentlyDamagedByHero(h, HIT_RECENT) then
                    __continue34 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if d < hd then
                    hitter = h
                    hd = d
                end
                __continue34 = true
            until true
            if not __continue34 then
                break
            end
        end
    end
    if hitter == nil then
        return 0
    end
    lastNo[pid] = now
    local agg = CreepAggro.Paid(bot, hitter)
    local g = i or ____exports.Gather(bot, hitter)
    Telemetry.Event(
        "trade_no",
        {
            {"pid", pid},
            {
                "role",
                isSupport(bot) and "support" or "core"
            },
            {"why", why},
            {
                "tgt",
                hitter:GetPlayerID()
            },
            {
                "d",
                math.floor(hd)
            },
            {
                "reach",
                math.floor(reachOf(bot))
            },
            {
                "har",
                math.floor(hitter:GetAttackRange())
            },
            {"agg", agg and 1 or 0},
            {
                "hp",
                math.floor(frac(bot) * 100) / 100
            },
            {
                "thp",
                math.floor(frac(hitter) * 100) / 100
            },
            {"en", g.enemiesNear},
            {"al", g.alliesNear},
            {"cr", g.enemyCreepsNear},
            {"hc", g.hitByCreeps},
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
    return 0
end
function inLane(bot)
    return Phase.IsLaningFor(bot) and GetAmountAlongLane(
        bot:GetAssignedLane(),
        bot:GetLocation()
    ).distance <= LANE_WIDTH
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
            local __continue54
            repeat
                if not c:IsAlive() then
                    __continue54 = true
                    break
                end
                enemyCreepsNear = enemyCreepsNear + 1
                if c:GetAttackTarget() == bot then
                    hitByCreeps = hitByCreeps + 1
                end
                __continue54 = true
            until true
            if not __continue54 then
                break
            end
        end
    end
    local tower = false
    local reach = LaneConfig.TowerReach()
    for ____, t in ipairs(bot:GetNearbyTowers(reach + 1000, true)) do
        do
            local __continue58
            repeat
                if not t:IsAlive() then
                    __continue58 = true
                    break
                end
                if GetUnitToUnitDistance(bot, t) <= reach or GetUnitToUnitDistance(target, t) <= reach then
                    tower = true
                end
                if t:GetAttackTarget() == bot then
                    hitByCreeps = hitByCreeps + MAX_CREEPS_ON_ME
                end
                __continue58 = true
            until true
            if not __continue58 then
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
function freshDecision(bot, pid, now, owns, target, inputs, killHp)
    local d = inputs ~= nil and ____exports.Decide(inputs, false, killHp) or ({})
    if d.kind ~= "kill" and owns then
        local join = joinable(bot)
        if join ~= nil then
            return open(
                bot,
                "fight",
                join.target,
                now,
                join,
                true
            )
        end
    end
    if target == nil or inputs == nil then
        return hitBack(bot, now, "no_target")
    end
    if owns and d.kind ~= "kill" and d.respect ~= "tower" and d.respect ~= "outnumbered" then
        local play = rollFight(bot, target, now)
        if play ~= nil then
            return open(
                bot,
                "fight",
                target,
                now,
                play,
                false
            )
        end
    end
    local gap = recoverTo[pid]
    local held = d.kind == "trade" and heldByGap(inputs, gap)
    if d.kind == nil or held then
        return hitBack(bot, now, d.respect or "gap", inputs)
    end
    if d.kind == "trade" and gap ~= nil then
        recoverTo[pid] = nil
    end
    return open(bot, d.kind, target, now)
end
function hitBack(bot, now, why, inputs)
    local hb = hitBackTarget(bot)
    if hb == nil then
        return unanswered(bot, now, why, inputs)
    end
    local hd = ____exports.Decide(
        ____exports.Gather(bot, hb),
        false,
        killHpFor(bot),
        true
    )
    if hd.kind == nil then
        return unanswered(
            bot,
            now,
            "hb_" .. tostring(hd.respect)
        )
    end
    return open(
        bot,
        hd.kind,
        hb,
        now,
        nil,
        nil,
        true
    )
end
function open(bot, kind, target, now, play, joined, hb)
    if joined then
        Plays.Join(play, bot)
    end
    episodes[bot:GetPlayerID()] = {
        kind = kind,
        target = target,
        tpid = target:GetPlayerID(),
        offeredAt = now,
        lf = ____exports.OwnsLaneFights(bot),
        hp0 = bot:GetHealth(),
        thp0 = target:GetHealth(),
        thpSeen = target:GetHealth(),
        inputs = ____exports.Gather(bot, target),
        primes = 0,
        stepOuts = 0,
        aggro = 0,
        play = play,
        joined = joined,
        hb = hb
    }
    return kind == "trade" and ____exports.DESIRE_TRADE or ____exports.DESIRE_KILL
end
function joinable(bot)
    if Plays.Of(bot) ~= nil then
        return nil
    end
    local reach = reachOf(bot) + JOIN_WALK
    for ____, p in ipairs(Plays.Near(
        bot:GetLocation(),
        JOIN_NEAR
    )) do
        do
            local __continue99
            repeat
                local t = p.target
                if p.by == bot or not valid(t) or GetUnitToUnitDistance(bot, t) > reach then
                    __continue99 = true
                    break
                end
                local r = ____exports.Decide(
                    ____exports.Gather(bot, t),
                    false,
                    killHpFor(bot)
                ).respect
                if r == "tower" or r == "outnumbered" then
                    __continue99 = true
                    break
                end
                if Plays.Weigh(Plays.InputsOf({
                    kind = p.kind,
                    by = bot,
                    target = t,
                    at = t:GetLocation()
                })).zero ~= nil then
                    __continue99 = true
                    break
                end
                return p
            until true
            if not __continue99 then
                break
            end
        end
    end
    return nil
end
function rollFight(bot, target, now)
    local pid = bot:GetPlayerID()
    local ____temp_7 = rolledAt[pid] or ({})
    rolledAt[pid] = ____temp_7
    local seen = ____temp_7
    local tpid = target:GetPlayerID()
    local last = seen[tpid]
    if last ~= nil and now - last < FIGHT_ROLL_EVERY then
        return nil
    end
    seen[tpid] = now
    return Plays.Roll(
        {
            kind = ____exports.LANE_FIGHT,
            by = bot,
            target = target,
            at = target:GetLocation()
        },
        now
    )
end
function keepWhy(bot, ep, now, join)
    local t = ep.target
    if not IsHeroAlive(ep.tpid) then
        return "target_dead"
    end
    if not valid(t) then
        return "target_lost"
    end
    ep.thpSeen = t:GetHealth()
    if ep.kind == "join" then
        if join == nil then
            return "pair_end"
        end
        if join ~= t then
            return "retarget"
        end
        if ep.startedAt == nil then
            return now - ep.offeredAt > LOST_AFTER and "not_taken" or nil
        end
        return now - ep.startedAt > JOIN_TIME and "time" or nil
    end
    if ep.startedAt == nil then
        return now - ep.offeredAt > LOST_AFTER and "not_taken" or nil
    end
    if ep.kind == "kill" then
        if now - ep.startedAt > KILL_TIME then
            return "time"
        end
    elseif ep.kind == "fight" then
        if now - ep.startedAt > FIGHT_TIME then
            return "time"
        end
        if ep.play ~= nil and not __TS__ArrayIncludes(
            Plays.Active(),
            ep.play
        ) then
            return "play_end"
        end
        if FR.HpFraction(bot) < Plays.SETTINGS.HpFloor then
            return "hp"
        end
        local r = ____exports.Decide(
            ____exports.Gather(bot, ep.target),
            true,
            killHpFor(bot)
        ).respect
        return (r == "tower" or r == "outnumbered") and r or nil
    else
        if ep.stepSince ~= nil and now - ep.stepSince > STEP_OUT_LIMIT then
            return "no_clear"
        end
        local reach = reachOf(bot) + (ep.hb == true and HIT_BACK_WALK or 0)
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
        true,
        killHpFor(bot),
        ep.hb == true
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
            local __continue141
            repeat
                local l = c:GetLocation()
                if l == nil then
                    __continue141 = true
                    break
                end
                x = x + l.x
                y = y + l.y
                seen = seen + 1
                __continue141 = true
            until true
            if not __continue141 then
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
COMMIT_HP = 0.4
--- The speculative lane fight (slice lane-fight, user 04/11/2026: the fights no clear window decides come from the play roll).
-- Before value on cil5, lposchk3, sspotchk1: cores 0.4 kills and 0.5 deaths per 100 encounters at even numbers with the enemy
-- over 40%, about 110 such core encounters a game, so the base is low (`judgement`). lfpchk1 at 0.05: 68 chances and 1.6
-- fired a game at a mean weight of 0.03, so 0.1 for about 4. A chance per target at most every FIGHT_ROLL_EVERY seconds, so standing beside a hero is not a roll a frame.
____exports.LANE_FIGHT = "lane_fight"
local FIGHT_BASE = 0.1
FIGHT_ROLL_EVERY = 15
FIGHT_TIME = 8
JOIN_NEAR = 1600
JOIN_WALK = 600
MAX_WAVE = 3
MAX_CREEPS_ON_ME = 2
KEEP_HP_SLACK = 0.05
KEEP_WAVE_SLACK = 1
LOSING_BY = 0.05
KILL_TIME = 6
JOIN_TIME = FIGHT_TIME
REACH = 100
HARASS_REACH = 300
--- A support prefers an enemy hero whose attack target is a lane creep (a last-hit attempt: its swing goes to the creep, not back
-- at us) by counting it this much nearer (judgement).
local PUNISH_BONUS = 300
NEAR = 1200
CREEP_AGGRO = 500
LANE_WIDTH = 1200
AGGRO_CLEAR = 550
AGGRO_COOLDOWN = 3
COOLDOWN_LEFT = 0.3
STEP_OUT_LIMIT = 2
HIT_RECENT = 1
HIT_BACK_WALK = 300
LOST_AFTER = 1
--- The fresh decision on a target in reach with no trade running, as one answer (the cut kind `trade`, driver core_trade):
-- Decide's kind or respect, or `gap` when a trade is held by the gap a lost trade left.
function ____exports.Answer(i, killHp, gap)
    local d = ____exports.Decide(i, false, killHp)
    if d.kind == "trade" and heldByGap(i, gap) then
        return "gap"
    end
    return d.kind or d.respect or "none"
end
--- The aggro-free attack, for core trades and support harass alike (one plan, so not an engine verb: a lane technique is bot code,
-- CLAUDE.md rule 3; slice support-spot). What a trading hero does this frame so its hits draw no creep aggro: `attack` while its own attack order's cooldown covers it; `prime` (a fresh attack
-- order) when no enemy lane creep is within AGGRO_CLEAR; otherwise `step_out` of the creeps first.
function ____exports.AggroPlan(now, primedAt, creepsWithinClear)
    if primedAt ~= nil and now - primedAt < AGGRO_COOLDOWN - COOLDOWN_LEFT then
        return "attack"
    end
    return creepsWithinClear == 0 and "prime" or "step_out"
end
episodes = {}
recoverTo = {}
--- Which arm this frame's GetDesire took: Think follows it.
local ownsFrame = {}
primedAt = {}
rolledAt = {}
--- The lane fight's own hard zeros on top of the library's (HP floor, two down, a target by its tower): the decline rule (the
-- other side more near the place) and the trade's `behind` (the hero well under the target's HP).
function ____exports.FightZero(i)
    if i.theirs > i.ours then
        return "outnumbered"
    end
    if i.targetHp ~= nil and i.hp < i.targetHp - BEHIND_BY then
        return "behind"
    end
    return nil
end
Plays.Define(____exports.LANE_FIGHT, {base = FIGHT_BASE, timeout = FIGHT_TIME + 2, chases = true, zero = ____exports.FightZero})
--- Load-time: whether mode_attack_generic gives this bot our desire and Think in lane (and OHA's port outside it).
function ____exports.Owns(bot)
    return Ours.On("CoreTrade") and CoreLastHit.Applies(bot) or isSupport(bot)
end
--- The enemy hero is swinging at a lane creep: a last-hit or deny attempt.
local function lastHitting(h)
    local t = h:GetAttackTarget()
    return t ~= nil and t ~= nil and not t:IsNull() and t:IsCreep() and not t:IsHero()
end
HITTER_RADIUS = 1600
NO_EVERY = 5
lastNo = {}
local function nearestTarget(bot)
    local reach = reachOf(bot)
    local support = isSupport(bot)
    local best
    local bestD = math.huge
    for ____, h in ipairs(bot:GetNearbyHeroes(reach, true, BotMode.None)) do
        do
            local __continue43
            repeat
                if not valid(h) then
                    __continue43 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h) - (support and lastHitting(h) and PUNISH_BONUS or 0)
                if d < bestD then
                    best = h
                    bestD = d
                end
                __continue43 = true
            until true
            if not __continue43 then
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
    if ep.play ~= nil and not ep.joined then
        Plays.End(ep.play, why)
    end
    if started and why == "losing" then
        recoverTo[pid] = ep.inputs.hp - ep.inputs.targetHp
    end
    local killed = started and not IsHeroAlive(ep.tpid)
    local thp = killed and 0 or (valid(ep.target) and ep.target:GetHealth() or ep.thpSeen)
    local i = ep.inputs
    local ____Telemetry_Event_3 = Telemetry.Event
    local ____array_2 = __TS__SparseArrayNew(
        {"pid", pid},
        {
            "role",
            isSupport(bot) and "support" or "core"
        },
        {"lf", ep.lf and 1 or 0},
        {"kind", ep.kind},
        {"tgt", ep.tpid}
    )
    local ____opt_0 = ep.play
    __TS__SparseArrayPush(
        ____array_2,
        {"play", ____opt_0 and ____opt_0.id},
        {"join", ep.play ~= nil and (ep.joined and 1 or 0) or nil},
        {"hb", ep.hb == true and 1 or nil},
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
    )
    ____Telemetry_Event_3(
        "trade",
        {__TS__SparseArraySpread(____array_2)}
    )
end
--- The cut's cadence (cut kind `trade`): a fresh decision at most every TRADE_CUT_EVERY s, an unchanged answer every TRADE_CUT_KEEP s, to TRADE_CUT_UNTIL (the laning stage; PairJoin's).
local TRADE_CUT_EVERY = 0.5
local TRADE_CUT_KEEP = 2
local TRADE_CUT_UNTIL = 720
local cutState = {}
--- Six places: under heldByGap's 1e-6 margin's scale of concern, so a replay on a border decides as the game did (review).
local function round6(v)
    return math.floor(v * 1000000 + 0.5) / 1000000
end
--- The `ev=cut kind=trade` fields of the fresh decision on `target` when a line is due (its inputs and answer, driver
-- core_trade), read before Desire acts on it; Desire adds `did` once it has. Undefined when no line is due. Reads only.
local function cutFields(bot, target, i, killHp, lf, now)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true or now > TRADE_CUT_UNTIL then
        return nil
    end
    local pid = bot:GetPlayerID()
    local ____temp_4 = cutState[pid] or ({})
    cutState[pid] = ____temp_4
    local st = ____temp_4
    if st.at ~= nil and now >= st.at and now - st.at < TRADE_CUT_EVERY then
        return nil
    end
    st.at = now
    local gap = recoverTo[pid]
    local dec = ____exports.Answer(i, killHp, gap)
    if dec == st.dec and now - (st.cutAt or -math.huge) < TRADE_CUT_KEEP then
        return nil
    end
    st.dec = dec
    st.cutAt = now
    return {
        {"pid", pid},
        {"kind", "trade"},
        {
            "role",
            isSupport(bot) and "support" or "core"
        },
        {
            "tgt",
            target:GetPlayerID()
        },
        {
            "hp",
            round6(i.hp)
        },
        {
            "thp",
            round6(i.targetHp)
        },
        {"en", i.enemiesNear},
        {"ally", i.alliesNear},
        {"cr", i.enemyCreepsNear},
        {"hc", i.hitByCreeps},
        {"tw", i.tower and 1 or 0},
        {"kh", killHp},
        {"lf", lf and 1 or 0},
        {
            "gap",
            gap ~= nil and round6(gap) or nil
        },
        {
            "d",
            math.floor(GetUnitToUnitDistance(bot, target))
        },
        {
            "rch",
            math.floor(reachOf(bot))
        },
        {
            "tlh",
            lastHitting(target) and 1 or 0
        },
        {"dec", dec}
    }
end
--- What the fresh decision opened (the cut's `did`): no episode, or its kind (`fight` joined from a play is `play`, a hit back `hitback`).
local function didOf(ep)
    if ep == nil then
        return "none"
    end
    if ep.kind == "fight" then
        return ep.joined == true and "play" or "fight"
    end
    return ep.hb == true and "hitback" or ep.kind
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
        local ____bot_IsAlive_result_5
        if bot:IsAlive() then
            ____bot_IsAlive_result_5 = nil
        else
            ____bot_IsAlive_result_5 = 0
        end
        return ____bot_IsAlive_result_5
    end
    ownsFrame[pid] = true
    Plays.Tick(now)
    if ep ~= nil and ep.ended then
        close(
            bot,
            ep,
            "mode_" .. tostring(bot:GetActiveMode()),
            now
        )
        ep = nil
    end
    local join = PairJoin.Joins(bot)
    if ep ~= nil and ep.kind ~= "join" and join ~= nil then
        close(bot, ep, "pair_join", now)
        ep = nil
    end
    if ep ~= nil then
        local why = keepWhy(bot, ep, now, join)
        if why == nil then
            return ep.kind == "trade" and ____exports.DESIRE_TRADE or ____exports.DESIRE_KILL
        end
        close(bot, ep, why, now)
        ep = nil
    end
    if join ~= nil then
        return open(bot, "join", join, now)
    end
    local owns = ____exports.OwnsLaneFights(bot)
    if owns and Plays.Of(bot) ~= nil then
        return unanswered(bot, now, "play")
    end
    local target = nearestTarget(bot)
    local inputs = target ~= nil and ____exports.Gather(bot, target) or nil
    local killHp = killHpFor(bot)
    local ____temp_6
    if target ~= nil and inputs ~= nil then
        ____temp_6 = cutFields(
            bot,
            target,
            inputs,
            killHp,
            owns,
            now
        )
    else
        ____temp_6 = nil
    end
    local cut = ____temp_6
    local desire = freshDecision(
        bot,
        pid,
        now,
        owns,
        target,
        inputs,
        killHp
    )
    if cut ~= nil then
        cut[#cut + 1] = {
            "did",
            didOf(episodes[pid])
        }
        Telemetry.Event("cut", cut)
    end
    return desire
end
--- A pair join (D10) is open for this hero: the arbiter's pair group (2). Reads only.
function ____exports.Joining(bot)
    local ep = episodes[bot:GetPlayerID()]
    return ep ~= nil and ep.ended ~= true and ep.kind == "join"
end
--- A trade, kill, fight or join episode is open for this hero (Desire returns its desire in attack mode); reads only.
function ____exports.Running(bot)
    local ep = episodes[bot:GetPlayerID()]
    return ep ~= nil and ep.ended ~= true
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
            local __continue131
            repeat
                if c:IsNull() or not c:IsAlive() then
                    __continue131 = true
                    break
                end
                creeps[#creeps + 1] = c
                if c:GetAttackTarget() == bot then
                    onMe = onMe + 1
                end
                __continue131 = true
            until true
            if not __continue131 then
                break
            end
        end
    end
    ep.aggro = math.max(ep.aggro, onMe)
    local commits = ep.kind ~= "trade"
    local plan = commits and "attack" or ____exports.AggroPlan(now, primedAt[pid], #creeps)
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
        if commits then
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
--- OHA's farm mode runs a laning core (or, since slice support-spot, a harassing support) off for 1-4 s on its own triggers (`X.ShouldRun`: a trade it judges lost, creep hits,
-- enemy tower proximity at low level, ...). In lane this context decides when its core backs off, so farm GetDesire skips
-- ShouldRun for it (user 03/11/2026; cil4: with only the trade triggers skipped, the tower branches still held cores 330 s).
function ____exports.TradeOwnsLaneRun(bot)
    return ____exports.Owns(bot) and inLane(bot)
end
--- Laning's 0.9 last-hit desire must not cut a retreat this context's core is already in (core-time-diagnosis s2: a death
-- within 15 s of such a cut was 4 times as likely), nor a kill or fight this context's lane fights committed to (lfpchk1:
-- 2 of 8 fights ended in a last hit at 4.9 s, t=154 and t=236; kills by the same reasoning, `judgement`). Trades still
-- give way to it, as does a commit with Ours.CoreLaneFight off. A predicate on the laning GetDesire (OWNERSHIP H2).
function ____exports.LastHitYields(bot)
    if not CoreLastHit.Applies(bot) then
        return false
    end
    if bot:GetActiveMode() == BotMode.Retreat then
        return true
    end
    local ep = episodes[bot:GetPlayerID()]
    return ep ~= nil and (ep.lf or ep.kind == "join") and ep.kind ~= "trade" and ep.startedAt ~= nil and not ep.ended
end
--- When this bot last gave an attack order on an enemy hero from a trade (lane_aggro shares the 3 s draw clock).
function ____exports.PrimedAt(pid)
    return primedAt[pid]
end
--- Another lane module gave an attack order on an enemy hero: the trade's aggro-free plan counts it as its prime.
function ____exports.NotePrimed(pid, t)
    primedAt[pid] = t
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
    for k in pairs(rolledAt) do
        rolledAt[k] = nil
    end
    for k in pairs(lastNo) do
        lastNo[k] = nil
    end
    for k in pairs(cutState) do
        cutState[k] = nil
    end
end
return ____exports
