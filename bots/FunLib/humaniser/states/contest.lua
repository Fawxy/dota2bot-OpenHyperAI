--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local LaneSpot = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_spot")
--- Melee by attack range, as the lane-positioning reads (lposchk3 `away` misses: 437 melee against 47 ranged).
____exports.MELEE_RANGE = 200
--- The longest walk into range a walk-in commits to, s (`judgement`: about 750 at 300 movement, the depth of an enemy's reach past the spot).
____exports.CONTEST_WALK = 2.5
--- laneTargets' radius for a contesting core: CONTEST_WALK of walking plus melee range, with slack.
____exports.RADIUS = 1000
--- The priced HP may be at most this share of max HP per creep (`judgement`: about one enemy hit and a nuke at level 1-3).
____exports.COST_CAP = 0.1
--- HP share the core must keep after the priced cost (`judgement`; lane aggro's draws gate at 0.45).
____exports.HP_FLOOR = 0.5
--- Seconds of the enemy hero's movement added to its attack reach: it steps in on a walk-in (`judgement`; the spot's REACT_SECS is 1.5 for standing).
____exports.STEP_IN = 0.5
--- A ready nuke counts when the creep lies within its cast range plus this (`judgement`: a hero steps in to cast).
____exports.NUKE_SLACK = 200
--- Enemy heroes further than this from the creep are not priced.
local QUERY = 1600
--- Our swing's own time in the zone when the API gives no attack point, s.
local SWING_DEFAULT = 0.5
--- The walk-in's price, pure: each enemy whose zone covers the creep hits us for the seconds we stand inside it (walking the
-- zone's depth in and out at `speed`, waiting in range for the creep to become due, and our swing) plus a ready nuke. Two or
-- more such heroes, or the creep inside an enemy tower's ring, refuse it outright.
function ____exports.PriceOf(threats, walk, wait, swing, speed, hp, maxHp, tower)
    local damage = 0
    local heroes = 0
    local exposure = 0
    local walkDist = walk * speed
    for ____, h in ipairs(threats) do
        do
            local __continue3
            repeat
                local depth = h.zone - h.d
                if depth <= 0 then
                    __continue3 = true
                    break
                end
                heroes = heroes + 1
                local inside = 2 * math.min(depth, walkDist) / math.max(speed, 1) + wait + swing
                exposure = math.max(exposure, inside)
                damage = damage + (h.dps * inside + h.nuke)
                __continue3 = true
            until true
            if not __continue3 then
                break
            end
        end
    end
    local cost = maxHp > 0 and damage / maxHp or 1
    local why = "ok"
    if tower then
        why = "tower"
    elseif heroes >= 2 then
        why = "two"
    elseif cost > ____exports.COST_CAP then
        why = "cost"
    elseif maxHp <= 0 or (hp - damage) / maxHp < ____exports.HP_FLOOR then
        why = "hp"
    end
    return {
        ok = why == "ok",
        why = why,
        cost = cost,
        heroes = heroes,
        exposure = exposure
    }
end
--- A melee core under Ours.CoreLastHit with Ours.CoreContest on.
function ____exports.Applies(bot)
    if not Ours.On("CoreContest") or not CoreLastHit.Applies(bot) then
        return false
    end
    return bot:GetAttackRange() <= ____exports.MELEE_RANGE
end
local function alive(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:GetLocation() ~= nil
end
local function dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
--- The largest ready damaging nuke of `enemy` whose cast range (plus NUKE_SLACK) reaches `d`, after our magic resistance.
local function nukeOn(bot, enemy, d)
    local best = 0
    local mana = enemy:GetMana()
    do
        local i = 0
        while i < 6 do
            do
                local __continue15
                repeat
                    local a = enemy:GetAbilityInSlot(i)
                    if a == nil or a == nil or a:IsNull() or a:IsHidden() or a:IsPassive() or a:GetLevel() < 1 then
                        __continue15 = true
                        break
                    end
                    local raw = a:GetAbilityDamage()
                    if raw <= 0 or a:GetCooldownTimeRemaining() > 0 or a:GetManaCost() > mana then
                        __continue15 = true
                        break
                    end
                    if a:GetCastRange() + ____exports.NUKE_SLACK < d then
                        __continue15 = true
                        break
                    end
                    local ____this_1
                    ____this_1 = a
                    local ____opt_0 = ____this_1.GetDamageType
                    local kind = ____opt_0 and ____opt_0(____this_1) or DamageType.Magical
                    best = math.max(
                        best,
                        bot:GetActualIncomingDamage(raw, kind)
                    )
                    __continue15 = true
                until true
                if not __continue15 then
                    break
                end
            end
            i = i + 1
        end
    end
    return best
end
--- The enemies near `at` as the price reads them.
function ____exports.ThreatsAt(bot, at)
    local out = {}
    for ____, h in ipairs(bot:GetNearbyHeroes(QUERY, true, 0)) do
        do
            local __continue20
            repeat
                if not alive(h) then
                    __continue20 = true
                    break
                end
                local d = dist(
                    h:GetLocation(),
                    at
                )
                local zone = h:GetAttackRange() + h:GetBoundingRadius() + bot:GetBoundingRadius() + ____exports.STEP_IN * h:GetCurrentMovementSpeed()
                local ____this_3
                ____this_3 = h
                local ____opt_2 = ____this_3.GetSecondsPerAttack
                local spa = ____opt_2 and ____opt_2(____this_3) or 1.7
                local dps = bot:GetActualIncomingDamage(
                    h:GetAttackDamage(),
                    DamageType.Physical
                ) / math.max(spa, 0.2)
                out[#out + 1] = {
                    d = d,
                    zone = zone,
                    dps = dps,
                    nuke = nukeOn(bot, h, d)
                }
                __continue20 = true
            until true
            if not __continue20 then
                break
            end
        end
    end
    return out
end
local function towerAt(bot, at)
    for ____, t in ipairs(bot:GetNearbyTowers(QUERY, true)) do
        if alive(t) and dist(
            t:GetLocation(),
            at
        ) <= LaneSpot.TOWER_RING then
            return true
        end
    end
    return false
end
--- The price of a walk-in for lane target `t` now.
function ____exports.PriceFor(bot, t)
    local at = t.creep:GetLocation()
    if at == nil then
        return {
            ok = false,
            why = "cost",
            cost = 1,
            heroes = 0,
            exposure = 0
        }
    end
    local ____this_5
    ____this_5 = bot
    local ____opt_4 = ____this_5.GetAttackPoint
    local point = ____opt_4 and ____opt_4(____this_5)
    local swing = point ~= nil and point > 0 and point or SWING_DEFAULT
    return ____exports.PriceOf(
        ____exports.ThreatsAt(bot, at),
        t.walk,
        math.max(0, t.eta - t.walk),
        swing,
        bot:GetCurrentMovementSpeed(),
        bot:GetHealth(),
        bot:GetMaxHealth(),
        towerAt(bot, at)
    )
end
local walks = {}
local refused = {}
--- The last refusal logged per bot (creep and why), so ev=contest_skip is written once per creep and reason.
local skipped = {}
function ____exports.Start(pid, creep, price, hp, now)
    walks[pid] = {creep = creep, price = price, hp = hp, t = now}
end
--- The running walk-in on `creep`, if this bot is in one.
function ____exports.Running(pid, creep)
    local w = walks[pid]
    return w ~= nil and w.creep == creep and w or nil
end
--- Ends the walk-in on `creep` (its attempt reported), returning it.
function ____exports.Finish(pid, creep)
    local w = ____exports.Running(pid, creep)
    if w ~= nil then
        walks[pid] = nil
    end
    return w
end
function ____exports.Refuse(pid, creep)
    refused[pid] = creep
end
function ____exports.Refused(pid, creep)
    return refused[pid] == creep
end
--- Whether a refusal of `creep` for `why` is new (not logged yet).
function ____exports.NoteSkip(pid, creep, why)
    local s = skipped[pid]
    if s ~= nil and s.creep == creep and s.why == why then
        return false
    end
    skipped[pid] = {creep = creep, why = why}
    return true
end
return ____exports
