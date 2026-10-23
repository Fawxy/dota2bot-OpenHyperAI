--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local dist2D, towerCovering, towerInRange, TOWER_RANGE, TOWER_IDS
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Tower = ____dota.Tower
local LaneFightConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_config")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local CooldownMemory = require(GetScriptDirectory().."/FunLib/humaniser/cooldown_memory")
local CastWatch = require(GetScriptDirectory().."/FunLib/humaniser/cast_watch")
local AbilityClasses = require(GetScriptDirectory().."/FunLib/humaniser/ability_classes")
local FightRead = require(GetScriptDirectory().."/FunLib/humaniser/fight_read")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function towerCovering(enemyTeam, loc)
    for ____, id in ipairs(TOWER_IDS) do
        do
            local __continue34
            repeat
                local tower = GetTower(enemyTeam, id)
                if tower == nil or tower == nil or not tower:IsAlive() then
                    __continue34 = true
                    break
                end
                if dist2D(
                    loc,
                    tower:GetLocation()
                ) <= TOWER_RANGE then
                    return tower
                end
                __continue34 = true
            until true
            if not __continue34 then
                break
            end
        end
    end
    return nil
end
function towerInRange(enemyTeam, loc)
    return towerCovering(enemyTeam, loc) ~= nil
end
local BURST_RANGE = 1200
local BURST_SECONDS = 5
TOWER_RANGE = 900
local COUNTER_ENEMIES = 2
local COUNTER_HP = 0.5
local COUNTER_RANGE = 1200
TOWER_IDS = {
    Tower.Top1,
    Tower.Top2,
    Tower.Top3,
    Tower.Mid1,
    Tower.Mid2,
    Tower.Mid3,
    Tower.Bot1,
    Tower.Bot2,
    Tower.Bot3
}
local cache = {}
local function marginOf(i)
    local err = LaneFightConfig.Curve("BurstError", i.skill) * (2 * i.errRoll - 1)
    return i.burst * (1 + err) / math.max(1, i.hp + i.regen * BURST_SECONDS)
end
function ____exports.Evaluate(i)
    local s = LaneFightConfig.Settings()
    local margin = marginOf(i)
    local overwhelming = margin >= s.Overwhelming
    local reason
    if margin < (i.minMargin or 1) then
        reason = "burst"
    elseif i.escapeReady then
        reason = "escape"
    elseif i.towerInRange and margin < s.TowerOverride then
        reason = "tower"
    elseif i.enemiesNear > i.alliesNear then
        reason = "outnumbered"
    elseif i.botHP ~= nil and (i.enemiesNearBot or 0) >= COUNTER_ENEMIES and i.botHP < COUNTER_HP then
        reason = "counter"
    elseif i.incoming ~= nil and i.botHealth ~= nil and i.botMaxHealth ~= nil and i.botHealth - i.incoming < s.SurviveHP * i.botMaxHealth then
        reason = "survive"
    end
    return {pass = reason == nil, margin = margin, overwhelming = overwhelming, reason = reason}
end
function ____exports.Passes(i)
    local r = ____exports.Evaluate(i)
    return r.pass, r.margin
end
local function located(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:CanBeSeen() and u:GetLocation() ~= nil
end
local function contributes(u, targetLoc)
    return located(u) and not u:IsIllusion() and dist2D(
        u:GetLocation(),
        targetLoc
    ) <= BURST_RANGE
end
--- Each unit's burst over the window, less the part of it spent walking into attack range.
local function burstOn(units, target)
    local total = 0
    local loc = target:GetLocation()
    for ____, u in ipairs(units) do
        local walk = math.max(
            0,
            dist2D(
                u:GetLocation(),
                loc
            ) - u:GetAttackRange()
        ) / math.max(
            1,
            u:GetCurrentMovementSpeed()
        )
        total = total + u:GetEstimatedDamageToTarget(true, target, BURST_SECONDS, DamageType.All) * math.max(0, BURST_SECONDS - walk) / BURST_SECONDS
    end
    return total
end
--- Damage the bot takes over SurviveWindow for attacking `target`: the enemy creeps by it, a covering tower, enemy heroes near the bot.
local function incomingOn(bot, target, snap)
    local s = LaneFightConfig.Settings()
    local window = s.SurviveWindow
    local loc = target:GetLocation()
    local total = 0
    for ____, c in ipairs(snap.enemy.units) do
        do
            local __continue18
            repeat
                if not located(c) or dist2D(
                    c:GetLocation(),
                    loc
                ) > s.CreepAggroRadius then
                    __continue18 = true
                    break
                end
                total = total + bot:GetActualIncomingDamage(
                    c:GetAttackDamage() * c:GetAttackSpeed() * window,
                    DamageType.Physical
                )
                __continue18 = true
            until true
            if not __continue18 then
                break
            end
        end
    end
    local tower = towerCovering(
        target:GetTeam(),
        loc
    )
    if tower ~= nil then
        total = total + bot:GetActualIncomingDamage(
            tower:GetAttackDamage() * tower:GetAttackSpeed() * window,
            DamageType.Physical
        )
    end
    local botLoc = bot:GetLocation()
    for ____, e in ipairs(LaneState.Enemies(bot, snap.lane)) do
        do
            local __continue22
            repeat
                if not e.visible or not located(e.unit) or dist2D(
                    e.unit:GetLocation(),
                    botLoc
                ) > COUNTER_RANGE then
                    __continue22 = true
                    break
                end
                total = total + e.unit:GetEstimatedDamageToTarget(true, bot, window, DamageType.All)
                __continue22 = true
            until true
            if not __continue22 then
                break
            end
        end
    end
    return total
end
local function minMarginFor(bot, contributors)
    local s = LaneFightConfig.Settings()
    local pos = LaneConfig.PositionOf(bot)
    local min = #contributors == 1 and contributors[1] == bot and (pos == 1 or pos == 2) and s.CoreSoloMargin or 1
    if LaneHooks.EnemiesMissing(bot) > 0 then
        min = math.max(min, s.MissingMargin)
    end
    return min
end
local function escapeReady(botPid, target, now, skill)
    local targetPid = target:GetPlayerID()
    for ____, a in ipairs(CastWatch.AbilitiesOf(target)) do
        do
            local __continue28
            repeat
                if not a.learned or not AbilityClasses.IsEscape(a.name) then
                    __continue28 = true
                    break
                end
                local ready = CooldownMemory.ProbablyReady(
                    botPid,
                    targetPid,
                    a.name,
                    true,
                    now,
                    skill
                )
                if ready then
                    return true
                end
                __continue28 = true
            until true
            if not __continue28 then
                break
            end
        end
    end
    return false
end
--- An alive tower of `enemyTeam` covers `loc` (the kill check's tower rule).
function ____exports.TowerCovers(enemyTeam, loc)
    return towerInRange(enemyTeam, loc)
end
local function hpFraction(u)
    local max = u:GetMaxHealth()
    return max > 0 and u:GetHealth() / max or 0
end
local function skipReason(bot, target)
    local h = LaneConfig.Helpers()
    if target:IsIllusion() or h.IsSuspiciousIllusion ~= nil and h.IsSuspiciousIllusion(target) then
        return "illusion"
    end
    if h.CannotBeKilled ~= nil and h.CannotBeKilled(bot, target) then
        return "unkillable"
    end
    if target.IsMagicImmune ~= nil and target:IsMagicImmune() then
        return "magic_immune"
    end
    return nil
end
local function compute(bot, contributors, target, snap, now)
    local skip = skipReason(bot, target)
    if skip ~= nil then
        return {pass = false, margin = 0, overwhelming = false, reason = skip}
    end
    local pid = bot:GetPlayerID()
    local skill = Profile.Get(bot).skill
    local loc = target:GetLocation()
    local counts = FightRead.LaneCounts(bot, snap, COUNTER_RANGE, loc)
    return ____exports.Evaluate({
        burst = burstOn(contributors, target),
        hp = target:GetHealth(),
        regen = target.GetHealthRegen ~= nil and target:GetHealthRegen() or 0,
        escapeReady = escapeReady(pid, target, now, skill),
        towerInRange = towerInRange(
            target:GetTeam(),
            loc
        ),
        enemiesNear = counts.enemies,
        alliesNear = counts.allies,
        skill = skill,
        errRoll = RandomFloat(0, 1),
        botHP = hpFraction(bot),
        enemiesNearBot = counts.enemiesNearBot,
        incoming = incomingOn(bot, target, snap),
        botHealth = bot:GetHealth(),
        botMaxHealth = bot:GetMaxHealth(),
        minMargin = minMarginFor(bot, contributors)
    })
end
--- Undefined when there is nothing to check: Kill off, no lane snapshot, or a target that is removed, dead, unseen or
-- has no location. Cached for KillCheckEvery per (bot, target, partners that contribute burst); `fresh` recomputes (an
-- abort re-check must not reuse a result from before the signal).
function ____exports.Check(bot, partners, target, now, fresh)
    if not LaneFightConfig.IsOn("Kill") or not located(bot) or not located(target) then
        return nil
    end
    local snap = LaneState.ForBot(bot)
    if snap == nil then
        return nil
    end
    local pid = bot:GetPlayerID()
    local loc = target:GetLocation()
    local contributors = {}
    local partnerPids = {}
    if contributes(bot, loc) then
        contributors[#contributors + 1] = bot
    end
    for ____, p in ipairs(partners) do
        do
            local __continue50
            repeat
                if p == bot or not contributes(p, loc) then
                    __continue50 = true
                    break
                end
                contributors[#contributors + 1] = p
                partnerPids[#partnerPids + 1] = p:GetPlayerID()
                __continue50 = true
            until true
            if not __continue50 then
                break
            end
        end
    end
    table.sort(partnerPids)
    local key = (tostring(target:GetPlayerID()) .. ":") .. (#partnerPids > 0 and table.concat(partnerPids, ",") or "solo")
    local byTarget = cache[pid]
    if byTarget == nil then
        byTarget = {}
        cache[pid] = byTarget
    end
    local cached = byTarget[key]
    if fresh ~= true and cached ~= nil and now >= cached.at and now - cached.at < LaneFightConfig.Settings().KillCheckEvery then
        return cached.result
    end
    local result = compute(
        bot,
        contributors,
        target,
        snap,
        now
    )
    byTarget[key] = {at = now, result = result}
    return result
end
function ____exports.ResetCache()
    cache = {}
end
return ____exports
