--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ObjectAssign(target, ...)
    local sources = {...}
    for i = 1, #sources do
        local source = sources[i]
        for key in pairs(source) do
            target[key] = source[key]
        end
    end
    return target
end

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

local function __TS__StringStartsWith(self, searchString, position)
    if position == nil or position < 0 then
        position = 0
    end
    return string.sub(self, position + 1, #searchString + position) == searchString
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
local arrive, decideSafe, favoured, heldBy, heldByGap, seenHero, chaseLost, chaseEnd, fightSafe, commitReaches, killHpFor, isSupport, noteHeading, awayOf, reachRead, lands, holdState, reachOf, lastHitting, hitBackTarget, hitterExchange, hbKeptWhy, unanswered, inLane, frac, valid, distXY, attackPoint, heldUncatchable, question2, shareOn, freshDecision, hitBack, open, joinable, rollFight, keepWhy, safeTime, rawDps, factorFor, awaySpeed, hunterOf, huntersOf, noteChase, predictedPlace, towerCovers, unseenReads, keepKill, noteSeen, chaseDistance, keepCut, huntersText, losing, stepOutPoint, episodeHolds, MIN_HP, BEHIND_BY, KILL_HP, COMMIT_HP, FIGHT_ROLL_EVERY, FIGHT_TIME, JOIN_NEAR, JOIN_WALK, MAX_WAVE, MAX_CREEPS_ON_ME, KEEP_HP_SLACK, KEEP_WAVE_SLACK, LOSING_BY, UNLANDED_CAP, CHASE_BACKSTOP, AT_PLACE, VELOCITY_SPAN, JOIN_TIME, REACH, SAFE_HORIZON, SAFE_ENGAGED, HARASS_REACH, WALK_IN, HOLD_MAX, NEAR, CREEP_AGGRO, LANE_WIDTH, AGGRO_CLEAR, AGGRO_COOLDOWN, COOLDOWN_LEFT, STEP_OUT_LIMIT, HIT_RECENT, HIT_BACK_WALK, HIT_BACK_HP, LOST_AFTER, OUTRANGE, chases, episodes, recoverTo, primedAt, rolledAt, heads, HITTER_RADIUS, NO_EVERY, lastNo, uncatchable, TRADE_CUT_UNTIL, round6, TOWER_IDS, HEADING_SPAN, HEADING_STALE, KEEP_CUT_EVERY, keepCutAt, bit, r1
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local CreepAggro = require(GetScriptDirectory().."/FunLib/humaniser/creep_aggro")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
local SupportDeny = require(GetScriptDirectory().."/FunLib/humaniser/states/support_deny")
local FR = require(GetScriptDirectory().."/FunLib/humaniser/fight_readings")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local SpellReady = require(GetScriptDirectory().."/FunLib/humaniser/spell_ready")
local PairJoin = require(GetScriptDirectory().."/FunLib/humaniser/pair_join")
local Plays = require(GetScriptDirectory().."/FunLib/humaniser/plays/plays")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
function arrive(d, r, close)
    if d <= r then
        return 0
    end
    return close > 0 and (d - r) / close or math.huge
end
--- The catch read (kill-chances step 3b): each hunter's attacks from the moment it is in attack range to the end of `w`,
-- and each ready spell whose cast range it reaches (plus the cast point) within `w`, summed against the target's HP.
function ____exports.CatchRead(hunters, thp, w)
    if w == nil then
        w = ____exports.CATCH_WINDOW
    end
    local dmg = 0
    local first = math.huge
    for ____, h in ipairs(hunters) do
        local ta = arrive(h.d, h.reach, h.close)
        if ta < w then
            dmg = dmg + h.dps * (w - ta)
            first = math.min(first, ta)
        end
        for ____, s in ipairs(h.spells) do
            do
                local __continue7
                repeat
                    local ts = arrive(h.d, s.range, h.close) + s.cp
                    if ts > w then
                        __continue7 = true
                        break
                    end
                    dmg = dmg + s.dmg
                    first = math.min(first, ts)
                    __continue7 = true
                until true
                if not __continue7 then
                    break
                end
            end
        end
    end
    return {ok = dmg >= thp, dmg = dmg, first = first}
end
--- Whether a trade (or kill) is on against a target with these inputs, or why not. `running`: the trade is already under way, so
-- the borders get their slack.
function ____exports.Decide(i, running, killHp)
    if running == nil then
        running = false
    end
    if killHp == nil then
        killHp = KILL_HP
    end
    local slack = running and KEEP_HP_SLACK or 0
    if i.burst ~= nil then
        return decideSafe(i, i.burst, running, killHp)
    end
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
function decideSafe(i, burst, running, killHp)
    local slack = running and KEEP_HP_SLACK or 0
    if i.towerOnMe == true then
        return {respect = "tower"}
    end
    if i.enemiesNear > i.alliesNear then
        return {respect = "outnumbered"}
    end
    if not i.tower and i.targetHp <= killHp and i.hp >= i.targetHp then
        return {kind = "kill"}
    end
    if i.hp < MIN_HP - slack then
        return {respect = "low_hp"}
    end
    if burst >= Threat.SETTINGS.StandBurst + slack then
        return {respect = "burst"}
    end
    if i.hitByCreeps >= MAX_CREEPS_ON_ME then
        return {respect = "creeps"}
    end
    if i.enemyCreepsNear > MAX_WAVE + (running and KEEP_WAVE_SLACK or 0) then
        return {respect = "wave"}
    end
    return {kind = "trade"}
end
function ____exports.Free(targetLastHitting, range, targetRange)
    return targetLastHitting or range >= targetRange + OUTRANGE
end
function favoured(i)
    if i.free == nil then
        return nil
    end
    return i.free or (i.ko or 0) > (i.kt or 0)
end
function heldBy(i, gap)
    local f = favoured(i)
    if f ~= nil then
        return not f and "unfavoured" or (i.denyDue == true and "deny" or nil)
    end
    return heldByGap(i, gap) and "gap" or nil
end
function heldByGap(i, gap)
    return gap ~= nil and i.hp - i.targetHp < gap - 0.000001
end
--- The fresh decision on a target in reach with no trade running, as one answer (the cut kind `trade`, driver core_trade):
-- Decide's kind or respect, or `gap` when a trade is held by the gap a lost trade left (with `Ours.TradeFree`, `unfavoured`
-- when the hit is neither free nor favoured, `deny` when a due deny outbids it).
function ____exports.Answer(i, killHp, gap)
    local d = ____exports.Decide(i, false, killHp)
    local ____temp_0
    if d.kind == "trade" then
        ____temp_0 = heldBy(i, gap)
    else
        ____temp_0 = nil
    end
    local held = ____temp_0
    if held ~= nil then
        return held
    end
    return d.kind or d.respect or "none"
end
--- HP the core lost beyond what the target lost since `hp0`/`thp0`, as a share of the core's max HP (positive: losing).
-- Absolute HP on both sides, so a big hero is not judged against a small one's fractions.
function ____exports.Deficit(hp0, hp, thp0, thp, maxHp)
    return (hp0 - hp - (thp0 - thp)) / math.max(1, maxHp)
end
function seenHero(pid)
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        if h ~= nil and h ~= nil and not h:IsNull() and not h:IsIllusion() and h:GetPlayerID() == pid and h:IsAlive() and h:CanBeSeen() then
            return h
        end
    end
    return nil
end
function chaseLost(bot, ep, now)
    local pid = bot:GetPlayerID()
    if chases[pid] ~= nil then
        chaseEnd(
            bot,
            chases[pid],
            now,
            "next",
            nil
        )
    end
    chases[pid] = {kind = ep.kind, tpid = ep.tpid, at = now}
    local info = GetHeroLastSeenInfo(ep.tpid)[1]
    local me = bot:GetLocation()
    local d = info ~= nil and distXY(me, info.location) or nil
    local reach = bot:GetAttackRange() + bot:GetBoundingRadius() + ep.thull
    local a = ep.seen0
    local b = ep.seenLast
    local span = a ~= nil and b ~= nil and b.at - a.at or 0
    local hv = span > 0 and distXY(
        Vector(a.x, a.y, 0),
        Vector(b.x, b.y, 0)
    ) / span or nil
    local hd = span > 0 and math.floor(math.deg(math.atan2(b.y - a.y, b.x - a.x)) + 0.5) or nil
    Telemetry.Event(
        "chase",
        {
            {"pid", pid},
            {"ph", "lost"},
            {
                "role",
                isSupport(bot) and "support" or "core"
            },
            {"ek", ep.kind},
            {"tgt", ep.tpid},
            {
                "dur",
                ep.startedAt ~= nil and math.floor((now - ep.startedAt) * 10) / 10 or nil
            },
            {
                "hp",
                math.floor(frac(bot) * 100) / 100
            },
            {
                "thp",
                math.floor(ep.thpSeen / math.max(1, ep.tmax) * 100) / 100
            },
            {
                "kh",
                killHpFor(bot)
            },
            {
                "x",
                math.floor(me.x)
            },
            {
                "y",
                math.floor(me.y)
            },
            {
                "lx",
                info ~= nil and math.floor(info.location.x) or nil
            },
            {
                "ly",
                info ~= nil and math.floor(info.location.y) or nil
            },
            {
                "tss",
                info ~= nil and math.floor(info.time_since_seen * 10 + 0.5) / 10 or nil
            },
            {
                "d",
                d ~= nil and math.floor(d) or nil
            },
            {
                "gap",
                d ~= nil and math.floor(d - reach) or nil
            },
            {
                "ms",
                math.floor(bot:GetCurrentMovementSpeed())
            },
            {
                "tms",
                math.floor(Threat.SeenSpeed(ep.tpid) or -1)
            },
            {
                "hv",
                hv ~= nil and math.floor(hv) or nil
            },
            {"hd", hd},
            {
                "sp",
                SpellReady.ReadyDamage(bot)
            }
        }
    )
end
function chaseEnd(bot, c, now, ph, seen)
    local pid = bot:GetPlayerID()
    chases[pid] = nil
    local ep = episodes[pid]
    Telemetry.Event(
        "chase",
        {
            {"pid", pid},
            {"ph", ph},
            {"ek", c.kind},
            {"tgt", c.tpid},
            {
                "dt",
                math.floor((now - c.at) * 10) / 10
            },
            {
                "alive",
                bot:IsAlive() and 1 or 0
            },
            {
                "d",
                seen ~= nil and bot:IsAlive() and math.floor(GetUnitToUnitDistance(bot, seen)) or nil
            },
            {
                "thp",
                seen ~= nil and math.floor(frac(seen) * 100) / 100 or nil
            },
            {
                "hp",
                bot:IsAlive() and math.floor(frac(bot) * 100) / 100 or nil
            },
            {
                "mode",
                bot:GetActiveMode()
            },
            {"onk", ep ~= nil and ep.tpid == c.tpid and ep.kind or nil}
        }
    )
end
function fightSafe()
    return Ours.On("FightSafe") and Ours.On("TradeSafe")
end
--- Why this core may not roll or join a lane fight on a target with these inputs, before the roll's own zeros: the target by
-- its tower (a fight chases, so the test harass dropped stays), more of them than us, and with `fightSafe` their burst in
-- reach at Threat StandBurst of our HP or more, PackBurst with two or more of them near (trade-safe's `burst` on the stand's
-- bars: a fight commits and chases, so it is never looser than a stand or a hit back; banked fights opened up to 15 points
-- behind on HP dealt about twice what they took, so the HP gap is not the danger, the burst is). Undefined: a chance may be
-- offered.
function ____exports.FightRefusal(i, killHp)
    local r = ____exports.Decide(i, false, killHp).respect
    if i.tower or r == "tower" then
        return "tower"
    end
    if r == "outnumbered" then
        return r
    end
    if not fightSafe() or i.burst == nil then
        return nil
    end
    local bar = i.enemiesNear >= 2 and Threat.SETTINGS.PackBurst or Threat.SETTINGS.StandBurst
    if i.burst >= bar then
        return "burst"
    end
    return nil
end
--- Slice lane-fight (`Ours.CoreLaneFight`, OWNERSHIP H9): every fight of this in-lane core beyond a trade is this module's. Team
-- roam keeps only its non-fight branches for it and LaneFight makes no claim (its gates close), so a commit is `kill` here.
-- Beyond the commit, in Desire's order: join a running play near it (`fight`, joined), else roll a `lane_fight` play when no
-- clear window decides (`fight`, rolled), else the trade rule. Slice support-lane-fight (`Ours.SupportLaneFight`, kill-chances
-- S1): a support whose harass is ours too, on the same bars, the role an input (reach, the last-hitting preference).
function ____exports.OwnsLaneFights(bot)
    local ____CoreLastHit_Applies_result_2
    if CoreLastHit.Applies(bot) then
        ____CoreLastHit_Applies_result_2 = Ours.On("CoreLaneFight") and Ours.On("CoreTrade")
    else
        ____CoreLastHit_Applies_result_2 = Ours.On("SupportLaneFight") and isSupport(bot)
    end
    local role = ____CoreLastHit_Applies_result_2
    return role and bot:IsAlive() and inLane(bot)
end
function commitReaches(bot)
    return Ours.On("KillReach") and (CoreLastHit.Applies(bot) or ____exports.OwnsLaneFights(bot))
end
function killHpFor(bot)
    return ____exports.OwnsLaneFights(bot) and COMMIT_HP or KILL_HP
end
function isSupport(bot)
    return not CoreLastHit.Applies(bot) and SupportDeny.Harass(bot)
end
--- Slice trade-lands: whether a hero at `gap` (distance past attack range plus both hulls, 0 or less when in range) gets into range
-- within `horizon` s when the target moves `away` (signed, along the line from us: towards us is negative) and we run at `ms`.
function ____exports.Arrives(gap, ms, away, horizon)
    if gap <= 0 then
        return true
    end
    local closing = ms - away
    return closing > 0 and gap <= closing * horizon
end
function noteHeading(target, now)
    local pid = target:GetPlayerID()
    local ____temp_3 = heads[pid] or ({})
    heads[pid] = ____temp_3
    local h = ____temp_3
    if h.s1 ~= nil and now - h.s1.at < HEADING_SPAN then
        return
    end
    local l = target:GetLocation()
    h.s0 = h.s1
    h.s1 = {x = l.x, y = l.y, at = now}
end
function awayOf(bot, target, now)
    local ____opt_4 = heads[target:GetPlayerID()]
    local s0 = ____opt_4 and ____opt_4.s0
    if s0 == nil or now - s0.at > HEADING_STALE then
        return 0
    end
    local l = target:GetLocation()
    local me = bot:GetLocation()
    local dx = l.x - me.x
    local dy = l.y - me.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then
        return 0
    end
    local dt = now - s0.at
    return ((l.x - s0.x) * dx + (l.y - s0.y) * dy) / len / dt
end
function reachRead(bot, target, now)
    noteHeading(target, now)
    local gap = GetUnitToUnitDistance(bot, target) - (bot:GetAttackRange() + bot:GetBoundingRadius() + target:GetBoundingRadius())
    local away = gap > 0 and awayOf(bot, target, now) or 0
    return {
        ok = ____exports.Arrives(
            gap,
            bot:GetCurrentMovementSpeed(),
            away,
            WALK_IN
        ),
        gap = gap,
        away = away
    }
end
function lands(bot, target, now)
    return not Ours.On("TradeLands") or reachRead(bot, target, now).ok
end
function holdState(bot, ep, now)
    if not Ours.On("TradeLands") or ep.kind ~= "trade" or ep.startedAt == nil or ep.fired == true then
        return nil
    end
    if not reachRead(bot, ep.target, now).ok then
        return nil
    end
    return now - ep.startedAt > HOLD_MAX and "time" or "wait"
end
function reachOf(bot)
    return bot:GetAttackRange() + bot:GetBoundingRadius() * 2 + (isSupport(bot) and HARASS_REACH or REACH)
end
function lastHitting(h)
    local t = h:GetAttackTarget()
    return t ~= nil and t ~= nil and not t:IsNull() and t:IsCreep() and not t:IsHero()
end
function hitBackTarget(bot)
    local reach = reachOf(bot)
    local best
    local bestD = math.huge
    for ____, h in ipairs(bot:GetNearbyHeroes(reach + HIT_BACK_WALK, true, BotMode.None)) do
        do
            local __continue80
            repeat
                if not valid(h) or not bot:WasRecentlyDamagedByHero(h, HIT_RECENT) then
                    __continue80 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if d >= bestD or d > reach and not CreepAggro.Paid(bot, h) then
                    __continue80 = true
                    break
                end
                best = h
                bestD = d
                __continue80 = true
            until true
            if not __continue80 then
                break
            end
        end
    end
    return best
end
--- The one trade decision on a target (slice hitback-fold, D24 in D18; the cut kind `trade`'s driver): Answer (safe, free or
-- favoured, no due deny). When the target is hitting us (`hitting`), whether we take the exchange as a hit back, the one
-- retreat's threat leave waits for: two caution bars first, our HP at HIT_BACK_HP or more and, with two or more enemy heroes
-- near, their burst under Threat PackBurst of our HP (the two-hero stand's bar; D1's own bars there cost lives, h2hstand1).
-- `trade` or `kill` when taken, else the refusal (`hb_hp`, `hb_burst` or Answer's). A hitter in reach that only the bars
-- refuse still gets Answer's plain trade, which retreat does not wait for.
function ____exports.Exchange(i, killHp, gap)
    if i.hitting == true then
        if i.hp < HIT_BACK_HP then
            return "hb_hp"
        end
        if i.enemiesNear >= 2 and (i.burst or 0) >= Threat.SETTINGS.PackBurst then
            return "hb_burst"
        end
    end
    return ____exports.Answer(i, killHp, gap)
end
function hitterExchange(bot)
    local h = hitBackTarget(bot)
    if h == nil then
        return nil, "no_hitter"
    end
    if frac(bot) < HIT_BACK_HP then
        return h, "hb_hp"
    end
    return h, ____exports.Exchange(
        ____exports.Gather(bot, h),
        killHpFor(bot),
        recoverTo[bot:GetPlayerID()]
    )
end
function hbKeptWhy(g)
    if g.hp < HIT_BACK_HP - KEEP_HP_SLACK then
        return "hb_hp"
    end
    if g.enemiesNear >= 2 and (g.burst or 0) >= Threat.SETTINGS.PackBurst + KEEP_HP_SLACK then
        return "hb_burst"
    end
    return nil
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
            local __continue99
            repeat
                if not valid(h) or not bot:WasRecentlyDamagedByHero(h, HIT_RECENT) then
                    __continue99 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if d < hd then
                    hitter = h
                    hd = d
                end
                __continue99 = true
            until true
            if not __continue99 then
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
    return Phase.LaningHeld(bot) and GetAmountAlongLane(
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
function distXY(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function attackPoint(bot, target)
    local me = bot:GetLocation()
    local at = target:GetLocation()
    local range = bot:GetAttackRange() + bot:GetBoundingRadius() + target:GetBoundingRadius()
    local d = distXY(me, at)
    if d <= range then
        return me
    end
    local f = range / d
    return Vector(at.x + (me.x - at.x) * f, at.y + (me.y - at.y) * f, me.z)
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
            local __continue129
            repeat
                if not c:IsAlive() then
                    __continue129 = true
                    break
                end
                enemyCreepsNear = enemyCreepsNear + 1
                if c:GetAttackTarget() == bot then
                    hitByCreeps = hitByCreeps + 1
                end
                __continue129 = true
            until true
            if not __continue129 then
                break
            end
        end
    end
    local tower = false
    local safe = Ours.On("TradeSafe")
    local towerOnMe = false
    local stand = safe and attackPoint(bot, target) or nil
    local reach = LaneConfig.TowerReach()
    for ____, t in ipairs(bot:GetNearbyTowers(reach + 1000, true)) do
        do
            local __continue133
            repeat
                if not t:IsAlive() then
                    __continue133 = true
                    break
                end
                if GetUnitToUnitDistance(bot, t) <= reach or GetUnitToUnitDistance(target, t) <= reach then
                    tower = true
                end
                if t:GetAttackTarget() == bot then
                    hitByCreeps = hitByCreeps + MAX_CREEPS_ON_ME
                    towerOnMe = true
                end
                if stand ~= nil and distXY(
                    stand,
                    t:GetLocation()
                ) <= reach then
                    towerOnMe = true
                end
                __continue133 = true
            until true
            if not __continue133 then
                break
            end
        end
    end
    local q2 = Ours.On("TradeFree") and question2(bot, target) or ({})
    local ____temp_6
    if CoreLastHit.Applies(bot) and bot:WasRecentlyDamagedByHero(target, HIT_RECENT) then
        ____temp_6 = true
    else
        ____temp_6 = nil
    end
    local hitting = ____temp_6
    if safe then
        local here = bot:GetLocation()
        local burst = Threat.Read(
            bot,
            here,
            here,
            SAFE_HORIZON,
            {engagedWindow = SAFE_ENGAGED}
        ).burst
        return __TS__ObjectAssign(
            {
                hp = frac(bot),
                targetHp = frac(target),
                enemiesNear = enemiesNear,
                alliesNear = math.max(1, alliesNear),
                enemyCreepsNear = enemyCreepsNear,
                hitByCreeps = hitByCreeps,
                tower = tower,
                burst = burst,
                towerOnMe = towerOnMe
            },
            q2,
            {hitting = hitting}
        )
    end
    return __TS__ObjectAssign(
        {
            hp = frac(bot),
            targetHp = frac(target),
            enemiesNear = enemiesNear,
            alliesNear = math.max(1, alliesNear),
            enemyCreepsNear = enemyCreepsNear,
            hitByCreeps = hitByCreeps,
            tower = tower
        },
        q2,
        {hitting = hitting}
    )
end
function heldUncatchable(bot, target)
    local pid = bot:GetPlayerID()
    if uncatchable[pid] ~= target:GetPlayerID() then
        return false
    end
    local ep = {
        kind = "kill",
        target = target,
        tpid = target:GetPlayerID(),
        offeredAt = DotaTime(),
        lf = false,
        hp0 = 0,
        thp0 = 0,
        tmax = target:GetMaxHealth(),
        thull = target:GetBoundingRadius(),
        thpSeen = target:GetHealth(),
        inputs = nil,
        primes = 0,
        stepOuts = 0,
        aggro = 0
    }
    noteChase(ep)
    local place = target:GetLocation()
    if ____exports.CatchRead(
        huntersOf(bot, ep, place, true),
        target:GetHealth(),
        safeTime(bot, ep, place)
    ).ok then
        uncatchable[pid] = nil
        return false
    end
    return true
end
function question2(bot, target)
    local free = ____exports.Free(
        lastHitting(target),
        bot:GetAttackRange(),
        target:GetAttackRange()
    )
    local denyDue = Laning.DenyDue(bot)
    if free then
        return {free = free, denyDue = denyDue}
    end
    return {
        free = free,
        ko = shareOn(bot, target),
        kt = shareOn(target, bot),
        denyDue = denyDue
    }
end
function shareOn(from, on)
    return SpellReady.DamageOn(from, on, PairJoin.SETTINGS.Window) / math.max(
        1,
        on:GetHealth()
    )
end
function freshDecision(bot, pid, now, owns, target, inputs, killHp)
    local d = inputs ~= nil and ____exports.Decide(inputs, false, killHp) or ({})
    if d.kind == "kill" and target ~= nil and heldUncatchable(bot, target) then
        return hitBack(bot, now, "cannot_catch", inputs)
    end
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
    if owns and d.kind ~= "kill" and ____exports.FightRefusal(inputs, killHp) == nil then
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
    if d.kind == "trade" and not lands(bot, target, now) then
        return unanswered(bot, now, "no_reach", inputs)
    end
    local gap = recoverTo[pid]
    local ____temp_19
    if d.kind == "trade" then
        ____temp_19 = heldBy(inputs, gap)
    else
        ____temp_19 = nil
    end
    local heldWhy = ____temp_19
    local held = heldWhy ~= nil
    if heldWhy == "deny" then
        return unanswered(bot, now, "deny", inputs)
    end
    if d.kind == nil or held then
        return hitBack(bot, now, d.respect or heldWhy or "gap", inputs)
    end
    local ex = inputs.hitting == true and ____exports.Exchange(inputs, killHp, gap) or nil
    if ex == "trade" or ex == "kill" then
        if d.kind == "trade" and gap ~= nil then
            recoverTo[pid] = nil
        end
        return open(
            bot,
            d.kind,
            target,
            now,
            nil,
            nil,
            true
        )
    end
    if d.kind == "trade" and gap ~= nil then
        recoverTo[pid] = nil
    end
    return open(bot, d.kind, target, now)
end
function hitBack(bot, now, why, inputs)
    if not CoreLastHit.Applies(bot) then
        return unanswered(bot, now, why, inputs)
    end
    local hb, a = hitterExchange(bot)
    if hb == nil then
        return unanswered(bot, now, why, inputs)
    end
    if a ~= "trade" and a ~= "kill" then
        return unanswered(
            bot,
            now,
            __TS__StringStartsWith(a, "hb_") and a or "hb_" .. a
        )
    end
    if a == "trade" and not lands(bot, hb, now) then
        return unanswered(bot, now, "hb_no_reach")
    end
    if a == "kill" and heldUncatchable(bot, hb) then
        return unanswered(bot, now, "cannot_catch", inputs)
    end
    return open(
        bot,
        a,
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
        tmax = target:GetMaxHealth(),
        thull = target:GetBoundingRadius(),
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
            local __continue203
            repeat
                local t = p.target
                if p.by == bot or not valid(t) or GetUnitToUnitDistance(bot, t) > reach then
                    __continue203 = true
                    break
                end
                if ____exports.FightRefusal(
                    ____exports.Gather(bot, t),
                    killHpFor(bot)
                ) ~= nil then
                    __continue203 = true
                    break
                end
                if Plays.Weigh(Plays.InputsOf({
                    kind = p.kind,
                    by = bot,
                    target = t,
                    at = t:GetLocation()
                })).zero ~= nil then
                    __continue203 = true
                    break
                end
                return p
            until true
            if not __continue203 then
                break
            end
        end
    end
    return nil
end
function rollFight(bot, target, now)
    local pid = bot:GetPlayerID()
    local ____temp_20 = rolledAt[pid] or ({})
    rolledAt[pid] = ____temp_20
    local seen = ____temp_20
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
    if ep.kind == "kill" or ep.kind == "join" then
        return keepKill(bot, ep, now, join)
    end
    local t = ep.target
    if not IsHeroAlive(ep.tpid) then
        return "target_dead"
    end
    if not valid(t) then
        return "target_lost"
    end
    noteSeen(ep, now)
    if ep.kind == "trade" and Ours.On("TradeFree") and Laning.DenyDue(bot) then
        local hold = holdState(bot, ep, now)
        if hold == nil then
            return "deny"
        end
        if hold == "time" then
            return "hold_time"
        end
    end
    if ep.startedAt == nil then
        return now - ep.offeredAt > LOST_AFTER and "not_taken" or nil
    end
    if ep.kind == "fight" then
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
        local g = ____exports.Gather(bot, ep.target)
        if g.tower then
            return "tower"
        end
        local r = ____exports.Decide(
            g,
            true,
            killHpFor(bot)
        ).respect
        return (r == "tower" or r == "outnumbered") and r or nil
    else
        local kh = killHpFor(bot)
        if ep.kind == "trade" and frac(t) <= kh and commitReaches(bot) and ____exports.Decide(
            ____exports.Gather(bot, t),
            false,
            kh
        ).kind == "kill" and not heldUncatchable(bot, t) then
            return "kill_up"
        end
        if ep.stepSince ~= nil and now - ep.stepSince > STEP_OUT_LIMIT then
            return "no_clear"
        end
        local reach = reachOf(bot) + (ep.hb == true and HIT_BACK_WALK or 0)
        local primed = primedAt[bot:GetPlayerID()]
        local walkingIn = primed ~= nil and now - primed < AGGRO_COOLDOWN - COOLDOWN_LEFT
        if ep.stepSince == nil and not walkingIn and GetUnitToUnitDistance(bot, ep.target) > reach then
            return "out_of_reach"
        end
        if losing(bot, ep, now) then
            return "losing"
        end
    end
    local g = ____exports.Gather(bot, ep.target)
    local d = ____exports.Decide(
        g,
        true,
        killHpFor(bot)
    )
    if d.kind == nil then
        return d.respect
    end
    if ep.hb == true then
        return hbKeptWhy(g)
    end
    return nil
end
--- Why a running kill or join ends now, or undefined to keep it: keepWhy's answer for those kinds, pure over its inputs.
function ____exports.KeepAnswer(k)
    if not k.alive then
        return "target_dead"
    end
    if k.kind == "join" then
        if not k.seen then
            return "target_lost"
        end
        if k.killUp == true then
            return "kill_up"
        end
        if k.join == "none" then
            return "pair_end"
        end
        if k.join == "other" then
            return "retarget"
        end
        if k.started == nil then
            return k.offered > LOST_AFTER and "not_taken" or nil
        end
        return k.started > JOIN_TIME and "time" or nil
    end
    if k.started == nil then
        if not k.seen then
            return "target_lost"
        end
        return k.offered > LOST_AFTER and "not_taken" or nil
    end
    if k.started > CHASE_BACKSTOP then
        return "backstop"
    end
    if k.seen then
        local g = k.g
        if g.tower then
            return "tower"
        end
        local d = ____exports.Decide(g, true, k.killHp)
        if d.kind == nil then
            return d.respect
        end
        if k.hb then
            local hb = hbKeptWhy(g)
            if hb ~= nil then
                return hb
            end
        end
    else
        if k.at == true then
            return "spot_clear"
        end
        if k.utower == true then
            return "tower"
        end
        if k.uout == true then
            return "outnumbered"
        end
        if k.threat == true then
            return "threat"
        end
    end
    if k.hunters ~= nil and k.thpAbs ~= nil and not ____exports.CatchRead(k.hunters, k.thpAbs, k.safe).ok then
        return "cannot_catch"
    end
    return nil
end
function safeTime(bot, ep, place)
    local theirs = bot:GetTeam() == Team.Radiant and Team.Dire or Team.Radiant
    local best
    local bestD = math.huge
    for ____, id in ipairs(TOWER_IDS) do
        do
            local __continue253
            repeat
                local t = GetTower(theirs, id)
                if t == nil or t == nil or not t:IsAlive() then
                    __continue253 = true
                    break
                end
                local d = distXY(
                    t:GetLocation(),
                    place
                )
                if d < bestD then
                    bestD = d
                    best = t:GetLocation()
                end
                __continue253 = true
            until true
            if not __continue253 then
                break
            end
        end
    end
    if best == nil then
        return ____exports.CATCH_WINDOW
    end
    local left = bestD - LaneConfig.TowerReach()
    if left <= 0 then
        return 0
    end
    local v
    if ep.tvx == nil then
        v = Threat.SeenSpeed(ep.tpid) or Threat.SETTINGS.MissingSpeed
    else
        v = (ep.tvx * (best.x - place.x) + (ep.tvy or 0) * (best.y - place.y)) / math.max(1, bestD)
    end
    return v > 0 and math.min(____exports.CATCH_WINDOW, left / v) or ____exports.CATCH_WINDOW
end
function rawDps(u)
    local ____this_22
    ____this_22 = u
    local ____opt_21 = ____this_22.GetSecondsPerAttack
    local spa = ____opt_21 and ____opt_21(____this_22)
    return spa ~= nil and spa > 0 and u:GetAttackDamage() / spa or 0
end
function factorFor(ep, dtype)
    if dtype == DamageType.Pure then
        return 1
    end
    return dtype == DamageType.Physical and (ep.physF or 1) or (ep.magF or 1)
end
function awaySpeed(ep, u, place, seen)
    local me = u:GetLocation()
    local dx = place.x - me.x
    local dy = place.y - me.y
    local n = math.sqrt(dx * dx + dy * dy)
    if n < 1 then
        return 0
    end
    if not seen and ep.tvx == nil then
        return Threat.SeenSpeed(ep.tpid) or Threat.SETTINGS.MissingSpeed
    end
    return ((ep.tvx or 0) * dx + (ep.tvy or 0) * dy) / n
end
function hunterOf(ep, u, place, seen)
    local spells = {}
    for ____, s in ipairs(SpellReady.ReadySpells(u)) do
        spells[#spells + 1] = {
            range = s.range,
            cp = s.cp,
            dmg = s.dmg * factorFor(ep, s.dtype)
        }
    end
    return {
        d = distXY(
            u:GetLocation(),
            place
        ),
        reach = u:GetAttackRange() + u:GetBoundingRadius() + ep.thull,
        close = u:GetCurrentMovementSpeed() - awaySpeed(ep, u, place, seen),
        dps = rawDps(u) * (ep.physF or 1),
        spells = spells
    }
end
function huntersOf(bot, ep, place, seen)
    local out = {hunterOf(ep, bot, place, seen)}
    local me = bot:GetPlayerID()
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue271
            repeat
                if a == nil or a == nil or a:IsNull() or not a:IsAlive() or a:IsIllusion() or a:GetPlayerID() == me then
                    __continue271 = true
                    break
                end
                local o = episodes[a:GetPlayerID()]
                if o == nil or o.ended == true or o.tpid ~= ep.tpid or o.kind ~= "kill" and o.kind ~= "join" then
                    __continue271 = true
                    break
                end
                out[#out + 1] = hunterOf(ep, a, place, seen)
                __continue271 = true
            until true
            if not __continue271 then
                break
            end
        end
    end
    return out
end
function noteChase(ep)
    local t = ep.target
    local l = t:GetLocation()
    local x = t:GetExtrapolatedLocation(VELOCITY_SPAN)
    ep.tvx = (x.x - l.x) / VELOCITY_SPAN
    ep.tvy = (x.y - l.y) / VELOCITY_SPAN
    ep.physF = t:GetActualIncomingDamage(100, DamageType.Physical) / 100
    ep.magF = t:GetActualIncomingDamage(100, DamageType.Magical) / 100
end
function predictedPlace(ep)
    local info = GetHeroLastSeenInfo(ep.tpid)[1]
    if info == nil then
        return nil
    end
    local l = info.location
    local tss = info.time_since_seen
    local vx = ep.tvx or 0
    local vy = ep.tvy or 0
    local v = math.sqrt(vx * vx + vy * vy)
    local cap = Threat.SeenSpeed(ep.tpid) or Threat.SETTINGS.MissingSpeed
    local f = v > cap and v > 0 and cap / v or 1
    return Vector(l.x + vx * f * tss, l.y + vy * f * tss, l.z)
end
function towerCovers(bot, a, b)
    local reach = LaneConfig.TowerReach()
    for ____, t in ipairs(bot:GetNearbyTowers(1600, true)) do
        do
            local __continue279
            repeat
                if not t:IsAlive() then
                    __continue279 = true
                    break
                end
                local tl = t:GetLocation()
                if distXY(tl, a) <= reach or distXY(tl, b) <= reach then
                    return true
                end
                __continue279 = true
            until true
            if not __continue279 then
                break
            end
        end
    end
    return false
end
function unseenReads(bot, ep, place, k)
    local here = bot:GetLocation()
    k.at = distXY(here, place) <= bot:GetBoundingRadius() + ep.thull + AT_PLACE
    k.utower = towerCovers(bot, here, place)
    local enemies = distXY(here, place) <= NEAR and 1 or 0
    for ____, h in ipairs(bot:GetNearbyHeroes(NEAR, true, BotMode.None)) do
        if valid(h) then
            enemies = enemies + 1
        end
    end
    local allies = 0
    for ____, h in ipairs(bot:GetNearbyHeroes(NEAR, false, BotMode.None)) do
        if h:IsAlive() and not h:IsIllusion() then
            allies = allies + 1
        end
    end
    k.uout = enemies > math.max(1, allies)
    local r = Threat.Read(
        bot,
        here,
        place,
        Threat.SETTINGS.GateHorizon,
        {exclude = ep.tpid}
    )
    k.threat = #r.mpids > 0 and r.missing >= Threat.SETTINGS.MissingRefuse
end
function keepKill(bot, ep, now, join)
    local alive = IsHeroAlive(ep.tpid)
    if alive and not valid(ep.target) then
        local h = seenHero(ep.tpid)
        if h ~= nil then
            ep.target = h
        end
    end
    local seen = alive and valid(ep.target)
    if seen then
        noteSeen(ep, now)
        if ep.kind == "kill" then
            noteChase(ep)
        end
        ep.unseenSince = nil
    elseif alive and ep.kind == "kill" and ep.startedAt ~= nil and ep.unseenSince == nil then
        ep.unseenSince = now
        if Telemetry.IsEnabled() then
            chaseLost(bot, ep, now)
        end
    end
    local k = {
        kind = ep.kind,
        alive = alive,
        seen = seen,
        offered = now - ep.offeredAt,
        started = ep.startedAt ~= nil and now - ep.startedAt or nil,
        join = ep.kind == "join" and (join == nil and "none" or (join == ep.target and "same" or "other")) or nil,
        killHp = killHpFor(bot),
        hb = ep.hb == true
    }
    ep.chaseAt = nil
    if ep.kind == "join" and seen then
        local kh = k.killHp
        k.killUp = frac(ep.target) <= kh and ____exports.Decide(
            ____exports.Gather(bot, ep.target),
            false,
            kh
        ).kind == "kill" and not heldUncatchable(bot, ep.target)
    end
    if ep.kind == "kill" and alive and k.started ~= nil and k.started <= CHASE_BACKSTOP then
        local place = seen and ep.target:GetLocation() or predictedPlace(ep)
        if seen then
            k.g = ____exports.Gather(bot, ep.target)
        end
        if place ~= nil then
            if not seen then
                ep.chaseAt = place
                unseenReads(bot, ep, place, k)
            end
            k.hunters = huntersOf(bot, ep, place, seen)
            k.thpAbs = seen and ep.target:GetHealth() or ep.thpSeen
            k.safe = safeTime(bot, ep, place)
        elseif not seen then
            k.at = true
        end
    end
    local why = ____exports.KeepAnswer(k)
    keepCut(
        bot,
        ep,
        k,
        why,
        now
    )
    return why
end
function noteSeen(ep, now)
    local t = ep.target
    ep.thpSeen = t:GetHealth()
    local l = t:GetLocation()
    if ep.seen == nil or now - ep.seen.at >= HEADING_SPAN then
        ep.seen0 = ep.seen
        ep.seen = {x = l.x, y = l.y, at = now}
    end
    ep.seenLast = {x = l.x, y = l.y, at = now}
end
function chaseDistance(bot, ep, seen)
    if seen then
        return GetUnitToUnitDistance(bot, ep.target)
    end
    local info = GetHeroLastSeenInfo(ep.tpid)[1]
    return info ~= nil and distXY(
        bot:GetLocation(),
        info.location
    ) or nil
end
function keepCut(bot, ep, k, why, now)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true or now > TRADE_CUT_UNTIL then
        return
    end
    local pid = bot:GetPlayerID()
    local last = keepCutAt[pid]
    if why == nil and last ~= nil and now >= last and now - last < KEEP_CUT_EVERY then
        return
    end
    keepCutAt[pid] = now
    local g = k.g
    local info = not k.seen and k.alive and GetHeroLastSeenInfo(ep.tpid)[1] or nil
    local ____k_alive_23
    if k.alive then
        ____k_alive_23 = chaseDistance(bot, ep, k.seen)
    else
        ____k_alive_23 = nil
    end
    local d = ____k_alive_23
    local c = k.hunters ~= nil and k.thpAbs ~= nil and ____exports.CatchRead(k.hunters, k.thpAbs, k.safe) or nil
    Telemetry.Event(
        "cut",
        {
            {"pid", pid},
            {"kind", "keep"},
            {
                "role",
                isSupport(bot) and "support" or "core"
            },
            {"tgt", ep.tpid},
            {"ek", k.kind},
            {"alv", k.alive and 1 or 0},
            {"sn", k.seen and 1 or 0},
            {
                "oa",
                round6(k.offered)
            },
            {
                "sa",
                k.started ~= nil and round6(k.started) or nil
            },
            {"jn", k.join},
            {"kh", k.killHp},
            {"hb", k.hb and 1 or nil},
            {
                "hp",
                g ~= nil and round6(g.hp) or nil
            },
            {
                "thp",
                g ~= nil and round6(g.targetHp) or nil
            },
            {"en", g and g.enemiesNear},
            {"ally", g and g.alliesNear},
            {"cr", g and g.enemyCreepsNear},
            {"hc", g and g.hitByCreeps},
            {"tw", g ~= nil and (g.tower and 1 or 0) or nil},
            {
                "bu",
                (g and g.burst) ~= nil and round6(g.burst) or nil
            },
            {"tm", (g and g.burst) ~= nil and (g.towerOnMe == true and 1 or 0) or nil},
            {"dec", why or "keep"},
            {
                "d",
                d ~= nil and math.floor(d) or nil
            },
            {
                "ar",
                math.floor(bot:GetAttackRange())
            },
            {
                "hl",
                math.floor(bot:GetBoundingRadius() + (k.seen and ep.target:GetBoundingRadius() or 0))
            },
            {
                "ms",
                math.floor(bot:GetCurrentMovementSpeed())
            },
            {
                "tms",
                k.seen and math.floor(ep.target:GetCurrentMovementSpeed()) or math.floor(Threat.SeenSpeed(ep.tpid) or -1)
            },
            {
                "sp",
                SpellReady.ReadyDamage(bot)
            },
            {
                "lx",
                info ~= nil and math.floor(info.location.x) or nil
            },
            {
                "ly",
                info ~= nil and math.floor(info.location.y) or nil
            },
            {
                "tss",
                info ~= nil and math.floor(info.time_since_seen * 10 + 0.5) / 10 or nil
            },
            {
                "chu",
                k.hunters ~= nil and huntersText(k.hunters) or nil
            },
            {
                "cth",
                k.thpAbs ~= nil and math.floor(k.thpAbs + 0.5) or nil
            },
            {
                "cdm",
                c ~= nil and math.floor(c.dmg + 0.5) or nil
            },
            {
                "cft",
                c ~= nil and (c.first == math.huge and -1 or round6(c.first)) or nil
            },
            {
                "csf",
                k.safe ~= nil and round6(k.safe) or nil
            },
            {
                "uat",
                bit(k.at)
            },
            {
                "utw",
                bit(k.utower)
            },
            {
                "uou",
                bit(k.uout)
            },
            {
                "uth",
                bit(k.threat)
            },
            {
                "kup",
                bit(k.killUp)
            }
        }
    )
end
function huntersText(hs)
    local out = {}
    for ____, h in ipairs(hs) do
        local sp = {}
        for ____, s in ipairs(h.spells) do
            sp[#sp + 1] = (((tostring(r1(s.range)) .. ":") .. tostring(math.floor(s.cp * 100 + 0.5) / 100)) .. ":") .. tostring(r1(s.dmg))
        end
        out[#out + 1] = table.concat(
            {
                r1(h.d),
                r1(h.reach),
                r1(h.close),
                r1(h.dps),
                table.concat(sp, "/")
            },
            ","
        )
    end
    return table.concat(out, ";")
end
function losing(bot, ep, now)
    local hp = bot:GetHealth()
    local thp = ep.target:GetHealth()
    local max = bot:GetMaxHealth()
    if not Ours.On("TradeLanded") then
        return ____exports.Deficit(
            ep.hp0,
            hp,
            ep.thp0,
            thp,
            max
        ) > LOSING_BY
    end
    local fired = bot:GetLastAttackTime()
    local rose = ep.atkSeen ~= nil and fired > ep.atkSeen
    if rose then
        ep.atkSeen = fired
    end
    local at = bot:GetAttackTarget()
    if ep.landedAt == nil and rose and at ~= nil and at:IsHero() and at:GetPlayerID() == ep.tpid then
        ep.landedAt = now
        ep.hpL = ep.hpPrev or ep.hp0
        ep.thpL = ep.thpPrev or ep.thp0
    end
    if ep.landedAt == nil then
        ep.hpPrev = hp
        ep.thpPrev = thp
        return ____exports.Deficit(
            ep.hp0,
            hp,
            ep.thp0,
            thp,
            max
        ) > UNLANDED_CAP
    end
    return ____exports.Deficit(
        ep.hpL,
        hp,
        ep.thpL,
        thp,
        max
    ) > LOSING_BY
end
function stepOutPoint(bot, creeps)
    local me = bot:GetLocation()
    local x = 0
    local y = 0
    local seen = 0
    for ____, c in ipairs(creeps) do
        do
            local __continue344
            repeat
                local l = c:GetLocation()
                if l == nil then
                    __continue344 = true
                    break
                end
                x = x + l.x
                y = y + l.y
                seen = seen + 1
                __continue344 = true
            until true
            if not __continue344 then
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
function episodeHolds(ep)
    return ep ~= nil and (ep.lf or ep.kind == "join" or ep.pair == true) and ep.kind ~= "trade" and ep.startedAt ~= nil and not ep.ended
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
UNLANDED_CAP = 0.15
--- Slice kill-chase (kill-chances step 3b, D19): a running kill is kept while CatchRead says the damage we and the allies on
-- the target can deal before it reaches safety, after closing to attack or cast range, reaches its HP. Safety is its own
-- tower's reach at its speed towards that tower (safeTime); a target not heading there has none in sight, and the horizon
-- is this cap. A fitted fixed window (5.7 s, h2hoha3 kills from 40% HP to death, 80th percentile) ended 94 of 124 kills in
-- the smoke game within 0.3 s while seen: one hero's attacks (30 to 40 a second) do not take a laner's 40% (240 to 290 HP)
-- in it, and the kills it was fitted on had several heroes hitting.
____exports.CATCH_WINDOW = 30
CHASE_BACKSTOP = 30
AT_PLACE = 100
VELOCITY_SPAN = 0.5
--- Slice trade-reach (`Ours.KillReach`, D19): a core's commit looks this far past the trade's reach for a hero at the commit bar,
-- JOIN_WALK's "about 2 s of walking" (`judgement`). h2hcurrent1: 13 of 62 side-core hunter-chances never had the low hero in
-- reach and none attacked; 10 were within reach + 400, all within reach + 700.
local KILL_WALK = JOIN_WALK
JOIN_TIME = FIGHT_TIME
REACH = 100
SAFE_HORIZON = 2
SAFE_ENGAGED = 6
HARASS_REACH = 300
WALK_IN = 1.5
HOLD_MAX = 4
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
HIT_BACK_HP = 0.7
LOST_AFTER = 1
OUTRANGE = 100
--- Slice chase-log: after an episode loses sight of its target (`target_lost`), what follows within CHASE_WATCH s: the first
-- frame the target is seen again (`ph=seen`), its death (`dead`), or neither (`gone`). One `ev=chase ph=lost` line at the loss.
local CHASE_WATCH = 12
chases = {}
--- A running watch's end, if this frame has one: the target seen again, dead, or the watch out of time.
local function chaseTick(bot, now)
    local pid = bot:GetPlayerID()
    local c = chases[pid]
    if c == nil then
        return
    end
    local dead = not IsHeroAlive(c.tpid)
    local ____dead_1
    if dead then
        ____dead_1 = nil
    else
        ____dead_1 = seenHero(c.tpid)
    end
    local seen = ____dead_1
    local out = now - c.at > CHASE_WATCH
    if not dead and seen == nil and not out then
        return
    end
    chaseEnd(
        bot,
        c,
        now,
        dead and "dead" or (seen ~= nil and "seen" or "gone"),
        seen
    )
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
-- other side more near the place) and, without `fightSafe`, the trade's `behind` (the hero well under the target's HP).
function ____exports.FightZero(i)
    if i.theirs > i.ours then
        return "outnumbered"
    end
    if not fightSafe() and i.targetHp ~= nil and i.hp < i.targetHp - BEHIND_BY then
        return "behind"
    end
    return nil
end
--- The lane-fight gate as one answer (the cut's `fg`, the cut kind `trade`'s `fight` action): `kill` when the commit comes
-- first, the core's refusal, the roll's hard zero on `pi`, else `roll`. The roll's weighted draw is not part of it.
function ____exports.FightAnswer(i, killHp, pi)
    if ____exports.Decide(i, false, killHp).kind == "kill" then
        return "kill"
    end
    return ____exports.FightRefusal(i, killHp) or Plays.Weigh(pi).zero or "roll"
end
Plays.Define(____exports.LANE_FIGHT, {base = FIGHT_BASE, timeout = FIGHT_TIME + 2, chases = true, zero = ____exports.FightZero})
--- Load-time: whether mode_attack_generic gives this bot our desire and Think in lane (and OHA's port outside it).
function ____exports.Owns(bot)
    return Ours.On("CoreTrade") and CoreLastHit.Applies(bot) or isSupport(bot)
end
heads = {}
--- Whether this core is taking an exchange with a hero hitting it: retreat's threat leave waits while it holds (LeaveWhy's
-- `hitback` stay). A running hit back inside its bars, or a hitter Exchange takes now (retreat leaves 0.17 s after its read
-- goes over, before attack mode can open the episode). Lethal, a tower on us and the heal floor still leave first.
function ____exports.Taking(bot)
    if not Ours.On("CoreTrade") or not CoreLastHit.Applies(bot) then
        return false
    end
    local ep = episodes[bot:GetPlayerID()]
    if ep ~= nil and ep.hb == true and ep.ended ~= true then
        return valid(ep.target) and hbKeptWhy(____exports.Gather(bot, ep.target)) == nil
    end
    local h, a = hitterExchange(bot)
    return h ~= nil and (a == "trade" or a == "kill" and not heldUncatchable(bot, h))
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
            local __continue108
            repeat
                if not valid(h) then
                    __continue108 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h) - (support and lastHitting(h) and PUNISH_BONUS or 0)
                if d < bestD then
                    best = h
                    bestD = d
                end
                __continue108 = true
            until true
            if not __continue108 then
                break
            end
        end
    end
    return best
end
--- Slice trade-reach: the commit's target for a core, an enemy hero at `killHp` or less within reach + KILL_WALK that Decide
-- calls `kill` on (so not outnumbered, not by its tower, not over our HP), the lowest HP first. Undefined: the trade rule's
-- nearest hero in reach decides as before.
local function commitTarget(bot, killHp)
    if not commitReaches(bot) then
        return nil, nil
    end
    local best
    local bestI
    local bestHp = math.huge
    for ____, h in ipairs(bot:GetNearbyHeroes(
        reachOf(bot) + KILL_WALK,
        true,
        BotMode.None
    )) do
        do
            local __continue114
            repeat
                if not valid(h) then
                    __continue114 = true
                    break
                end
                local f = frac(h)
                if f > killHp or f >= bestHp then
                    __continue114 = true
                    break
                end
                local i = ____exports.Gather(bot, h)
                if ____exports.Decide(i, false, killHp).kind ~= "kill" then
                    __continue114 = true
                    break
                end
                best = h
                bestI = i
                bestHp = f
                __continue114 = true
            until true
            if not __continue114 then
                break
            end
        end
    end
    return best, bestI
end
uncatchable = {}
--- Slice kill-chase: the target Think named with SetTarget is cleared, if it is still the one set (another module's stays).
local function clearTarget(bot, ep)
    local t = bot:GetTarget()
    if t == nil or t == nil then
        return
    end
    if t == ep.target or valid(t) and t:IsHero() and t:GetPlayerID() == ep.tpid or not valid(t) then
        bot:SetTarget(nil)
    end
end
local function close(bot, ep, why, now)
    local pid = bot:GetPlayerID()
    episodes[pid] = nil
    if ep.kind ~= "trade" then
        clearTarget(bot, ep)
    end
    if ep.kind == "kill" then
        uncatchable[pid] = why == "cannot_catch" and ep.tpid or nil
    end
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
    if why == "target_lost" and Telemetry.IsEnabled() then
        chaseLost(bot, ep, now)
    end
    local ____Telemetry_Event_10 = Telemetry.Event
    local ____array_9 = __TS__SparseArrayNew(
        {"pid", pid},
        {
            "role",
            isSupport(bot) and "support" or "core"
        },
        {"lf", ep.lf and 1 or 0},
        {"kind", ep.kind},
        {"tgt", ep.tpid}
    )
    local ____opt_7 = ep.play
    __TS__SparseArrayPush(
        ____array_9,
        {"play", ____opt_7 and ____opt_7.id},
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
            "ld",
            started and ep.landedAt ~= nil and math.floor((ep.landedAt - ep.startedAt) * 10) / 10 or nil
        },
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
        {"fa", ep.first},
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
    ____Telemetry_Event_10(
        "trade",
        {__TS__SparseArraySpread(____array_9)}
    )
    if started then
        PairJoin.After(bot, ep.kind, why, ep.tpid)
    end
end
--- The cut's cadence (cut kind `trade`): a fresh decision at most every TRADE_CUT_EVERY s, an unchanged answer every TRADE_CUT_KEEP s, to TRADE_CUT_UNTIL (the laning stage; PairJoin's).
local TRADE_CUT_EVERY = 0.5
local TRADE_CUT_KEEP = 2
TRADE_CUT_UNTIL = 720
local cutState = {}
round6 = function(v) return math.floor(v * 1000000 + 0.5) / 1000000 end
--- The `ev=cut kind=trade` fields of the fresh decision on `target` when a line is due (its inputs and answer, driver
-- core_trade), read before Desire acts on it; Desire adds `did` once it has. Undefined when no line is due. Writes only the heading samples `reachRead` keeps.
local function cutFields(bot, target, i, killHp, lf, now)
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true or now > TRADE_CUT_UNTIL then
        return nil
    end
    local pid = bot:GetPlayerID()
    local ____temp_11 = cutState[pid] or ({})
    cutState[pid] = ____temp_11
    local st = ____temp_11
    if st.at ~= nil and now >= st.at and now - st.at < TRADE_CUT_EVERY then
        return nil
    end
    st.at = now
    local gap = recoverTo[pid]
    local xa = i.hitting == true and ____exports.Exchange(i, killHp, gap) or nil
    local dec = ____exports.Answer(i, killHp, gap)
    local key = xa ~= nil and (dec .. "/") .. xa or dec
    if key == st.dec and now - (st.cutAt or -math.huge) < TRADE_CUT_KEEP then
        return nil
    end
    st.dec = key
    st.cutAt = now
    local pi = lf and Plays.InputsOf({
        kind = ____exports.LANE_FIGHT,
        by = bot,
        target = target,
        at = target:GetLocation()
    }) or nil
    local rr = reachRead(bot, target, now)
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
            "hl",
            math.floor(bot:GetBoundingRadius() + target:GetBoundingRadius())
        },
        {
            "ms",
            math.floor(bot:GetCurrentMovementSpeed())
        },
        {
            "tms",
            math.floor(target:GetCurrentMovementSpeed())
        },
        {
            "aw",
            math.floor(rr.away)
        },
        {"lw", rr.ok and 1 or 0},
        {
            "tlh",
            lastHitting(target) and 1 or 0
        },
        {
            "bu",
            i.burst ~= nil and round6(i.burst) or nil
        },
        {"tm", i.burst ~= nil and (i.towerOnMe == true and 1 or 0) or nil},
        {
            "ar",
            math.floor(bot:GetAttackRange())
        },
        {
            "tar",
            math.floor(target:GetAttackRange())
        },
        {
            "tme",
            target:GetAttackTarget() == bot and 1 or 0
        },
        {
            "ko",
            round6(i.ko or shareOn(bot, target))
        },
        {
            "kt",
            round6(i.kt or shareOn(target, bot))
        },
        {"tf", i.free ~= nil and 1 or nil},
        {"dn", i.free ~= nil and (i.denyDue == true and 1 or 0) or nil},
        {"dec", dec},
        {"hb", i.hitting == true and 1 or nil},
        {"xa", xa},
        {
            "fg",
            pi ~= nil and ____exports.FightAnswer(i, killHp, pi) or nil
        },
        {"fpo", pi and pi.ours},
        {"fpt", pi and pi.theirs},
        {
            "ftd",
            pi ~= nil and math.floor(math.min(pi.tower, 99999)) or nil
        },
        {
            "fs",
            pi ~= nil and (fightSafe() and 1 or 0) or nil
        }
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
    if Telemetry.IsEnabled() then
        chaseTick(bot, now)
    end
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
        local ____bot_IsAlive_result_16
        if bot:IsAlive() then
            ____bot_IsAlive_result_16 = nil
        else
            ____bot_IsAlive_result_16 = 0
        end
        return ____bot_IsAlive_result_16
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
    if ep ~= nil and ep.kind == "trade" and ep.fired ~= true and ep.atkSeen ~= nil and bot:GetLastAttackTime() > ep.atkSeen then
        ep.fired = true
    end
    local sameKill = ep ~= nil and ep.kind == "kill" and join ~= nil and join:GetPlayerID() == ep.tpid
    if sameKill then
        ep.pair = true
    end
    if ep ~= nil and ep.kind ~= "join" and join ~= nil and not sameKill then
        local ____temp_17
        if join:GetPlayerID() ~= ep.tpid then
            ____temp_17 = holdState(bot, ep, now)
        else
            ____temp_17 = nil
        end
        local hold = ____temp_17
        if hold ~= "wait" then
            close(bot, ep, hold == "time" and "hold_time" or "pair_join", now)
            ep = nil
        end
    end
    if ep ~= nil then
        local why = keepWhy(bot, ep, now, join)
        if why == nil then
            return ep.kind == "trade" and ____exports.DESIRE_TRADE or ____exports.DESIRE_KILL
        end
        close(bot, ep, why, now)
        if why == "kill_up" and ep.kind == "join" and valid(ep.target) then
            local d = open(bot, "kill", ep.target, now)
            episodes[pid].pair = true
            return d
        end
        ep = nil
    end
    if join ~= nil then
        return open(bot, "join", join, now)
    end
    local owns = ____exports.OwnsLaneFights(bot)
    if owns and Plays.Of(bot) ~= nil then
        return unanswered(bot, now, "play")
    end
    local killHp = killHpFor(bot)
    local committed, ci = commitTarget(bot, killHp)
    local target = committed or nearestTarget(bot)
    local inputs = ci or (target ~= nil and ____exports.Gather(bot, target) or nil)
    if target ~= nil and Ours.On("TradeLands") then
        noteHeading(target, now)
    end
    local ____temp_18
    if target ~= nil and inputs ~= nil then
        ____temp_18 = cutFields(
            bot,
            target,
            inputs,
            killHp,
            owns,
            now
        )
    else
        ____temp_18 = nil
    end
    local cut = ____temp_18
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
TOWER_IDS = {
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
--- Seconds between the two places a seen target's heading is read from (`hv`, `hd` on ev=chase).
HEADING_SPAN = 0.5
--- A heading sample older than this is not a heading (a target seen again after a gap).
HEADING_STALE = 1.5
KEEP_CUT_EVERY = 0.5
keepCutAt = {}
bit = function(b)
    local ____temp_36
    if b == nil then
        ____temp_36 = nil
    else
        ____temp_36 = b and 1 or 0
    end
    return ____temp_36
end
r1 = function(v) return math.floor(v * 10 + 0.5) / 10 end
--- Slice chase-log (ev=cast): the hero's running episode, its kind and target. Reads only.
function ____exports.EpisodeOf(pid)
    local ep = episodes[pid]
    local ____temp_37
    if ep == nil or ep.ended == true then
        ____temp_37 = nil
    else
        ____temp_37 = {kind = ep.kind, tpid = ep.tpid, target = ep.target, at = ep.offeredAt}
    end
    return ____temp_37
end
PairJoin.SetReaders({
    episodeOf = ____exports.EpisodeOf,
    refusal = function(bot, target) return ____exports.FightRefusal(
        ____exports.Gather(bot, target),
        killHpFor(bot)
    ) end
})
--- A pair join (D10) is open for this hero, or a kill carrying one (`pair`): the arbiter's pair group (2). Reads only.
function ____exports.Joining(bot)
    local ep = episodes[bot:GetPlayerID()]
    return ep ~= nil and ep.ended ~= true and (ep.kind == "join" or ep.pair == true)
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
    if ep == nil then
        return
    end
    if not valid(ep.target) then
        if ep.kind ~= "trade" then
            clearTarget(bot, ep)
        end
        if ep.kind == "kill" and ep.chaseAt ~= nil then
            bot:Action_MoveToLocation(ep.chaseAt)
        end
        return
    end
    local now = DotaTime()
    if ep.kind ~= "trade" then
        bot:SetTarget(ep.target)
    end
    if ep.startedAt == nil then
        ep.startedAt = now
        ep.atkSeen = bot:GetLastAttackTime()
        PairJoin.Reopened(bot)
    end
    local creeps = {}
    local onMe = 0
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(AGGRO_CLEAR, true)) do
        do
            local __continue334
            repeat
                if c:IsNull() or not c:IsAlive() then
                    __continue334 = true
                    break
                end
                creeps[#creeps + 1] = c
                if c:GetAttackTarget() == bot then
                    onMe = onMe + 1
                end
                __continue334 = true
            until true
            if not __continue334 then
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
        ep.first = ep.first or "step"
        bot:Action_MoveToLocation(stepOutPoint(bot, creeps))
        return
    end
    ep.stepSince = nil
    ep.first = ep.first or "order"
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
-- give way to it, as does a commit with Ours.CoreLaneFight off. A predicate on the laning GetDesire (OWNERSHIP H2). Slice
-- support-lane-fight: a support whose lane fights are ours is held by its kill, fight or join the same way (D18: a due last
-- hit or deny never outbids a kill); its retreat is left as it was.
function ____exports.LastHitYields(bot)
    if not CoreLastHit.Applies(bot) then
        return ____exports.OwnsLaneFights(bot) and episodeHolds(episodes[bot:GetPlayerID()])
    end
    if bot:GetActiveMode() == BotMode.Retreat then
        return true
    end
    return episodeHolds(episodes[bot:GetPlayerID()])
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
    for k in pairs(chases) do
        chases[k] = nil
    end
    for k in pairs(keepCutAt) do
        keepCutAt[k] = nil
    end
    for k in pairs(heads) do
        heads[k] = nil
    end
    for k in pairs(uncatchable) do
        uncatchable[k] = nil
    end
end
return ____exports
