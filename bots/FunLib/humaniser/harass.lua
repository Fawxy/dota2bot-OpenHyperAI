--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
end

local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
end

local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end

local function __TS__ClassExtends(target, base)
    target.____super = base
    local staticMetatable = setmetatable({__index = base}, base)
    setmetatable(target, staticMetatable)
    local baseMetatable = getmetatable(base)
    if baseMetatable then
        if type(baseMetatable.__index) == "function" then
            staticMetatable.__index = baseMetatable.__index
        end
        if type(baseMetatable.__newindex) == "function" then
            staticMetatable.__newindex = baseMetatable.__newindex
        end
    end
    setmetatable(target.prototype, base.prototype)
    if type(base.prototype.__index) == "function" then
        target.prototype.__index = base.prototype.__index
    end
    if type(base.prototype.__newindex) == "function" then
        target.prototype.__newindex = base.prototype.__newindex
    end
    if type(base.prototype.__tostring) == "function" then
        target.prototype.__tostring = base.prototype.__tostring
    end
end

local Error, RangeError, ReferenceError, SyntaxError, TypeError, URIError
do
    local function getErrorStack(self, constructor)
        if debug == nil then
            return nil
        end
        local level = 1
        while true do
            local info = debug.getinfo(level, "f")
            level = level + 1
            if not info then
                level = 1
                break
            elseif info.func == constructor then
                break
            end
        end
        if __TS__StringIncludes(_VERSION, "Lua 5.0") then
            return debug.traceback(("[Level " .. tostring(level)) .. "]")
        else
            return debug.traceback(nil, level)
        end
    end
    local function wrapErrorToString(self, getDescription)
        return function(self)
            local description = getDescription(self)
            local caller = debug.getinfo(3, "f")
            local isClassicLua = __TS__StringIncludes(_VERSION, "Lua 5.0") or _VERSION == "Lua 5.1"
            if isClassicLua or caller and caller.func ~= error then
                return description
            else
                return (description .. "\n") .. tostring(self.stack)
            end
        end
    end
    local function initErrorClass(self, Type, name)
        Type.name = name
        return setmetatable(
            Type,
            {__call = function(____, _self, message) return __TS__New(Type, message) end}
        )
    end
    local ____initErrorClass_1 = initErrorClass
    local ____class_0 = __TS__Class()
    ____class_0.name = ""
    function ____class_0.prototype.____constructor(self, message)
        if message == nil then
            message = ""
        end
        self.message = message
        self.name = "Error"
        self.stack = getErrorStack(nil, self.constructor.new)
        local metatable = getmetatable(self)
        if metatable and not metatable.__errorToStringPatched then
            metatable.__errorToStringPatched = true
            metatable.__tostring = wrapErrorToString(nil, metatable.__tostring)
        end
    end
    function ____class_0.prototype.__tostring(self)
        return self.message ~= "" and (self.name .. ": ") .. self.message or self.name
    end
    Error = ____initErrorClass_1(nil, ____class_0, "Error")
    local function createErrorClass(self, name)
        local ____initErrorClass_3 = initErrorClass
        local ____class_2 = __TS__Class()
        ____class_2.name = ____class_2.name
        __TS__ClassExtends(____class_2, Error)
        function ____class_2.prototype.____constructor(self, ...)
            ____class_2.____super.prototype.____constructor(self, ...)
            self.name = name
        end
        return ____initErrorClass_3(nil, ____class_2, name)
    end
    RangeError = createErrorClass(nil, "RangeError")
    ReferenceError = createErrorClass(nil, "ReferenceError")
    SyntaxError = createErrorClass(nil, "SyntaxError")
    TypeError = createErrorClass(nil, "TypeError")
    URIError = createErrorClass(nil, "URIError")
end

local function __TS__ObjectGetOwnPropertyDescriptors(object)
    local metatable = getmetatable(object)
    if not metatable then
        return {}
    end
    return rawget(metatable, "_descriptors") or ({})
end

local function __TS__Delete(target, key)
    local descriptors = __TS__ObjectGetOwnPropertyDescriptors(target)
    local descriptor = descriptors[key]
    if descriptor then
        if not descriptor.configurable then
            error(
                __TS__New(
                    TypeError,
                    ((("Cannot delete property " .. tostring(key)) .. " of ") .. tostring(target)) .. "."
                ),
                0
            )
        end
        descriptors[key] = nil
        return true
    end
    target[key] = nil
    return true
end
-- End of Lua Library inline imports
local ____exports = {}
local settings, dist2D, clamp01, toward, stepBack, enemyCreepsNear, maybeDance, dances
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local AllyLastHit = require(GetScriptDirectory().."/FunLib/humaniser/ally_last_hit")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
function settings()
    return LaneConfig.Settings()
end
function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end
function toward(from, to, len)
    local d = dist2D(from, to)
    if d < 0.000001 then
        return from
    end
    return Vector(from.x + (to.x - from.x) / d * len, from.y + (to.y - from.y) / d * len, from.z)
end
function ____exports.AggroDance(enemyCreepsWithin500)
    return enemyCreepsWithin500 >= settings().Thresholds.AggroDanceCreeps
end
function stepBack(bot)
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    local here = bot:GetLocation()
    local a = Camps.ToTeamAmount(
        team,
        GetAmountAlongLane(lane, here).amount
    )
    local behind = GetLocationAlongLane(
        lane,
        clamp01(Camps.ToAbsAmount(
            team,
            a - settings().Camps.LaneSampleStep
        ))
    )
    return toward(
        here,
        behind,
        settings().Radii.AggroDanceStep
    )
end
function enemyCreepsNear(bot, enemyCreeps)
    local r = settings().Thresholds.AggroDanceRadius
    local team = bot:GetTeam()
    local n = 0
    for ____, c in ipairs(enemyCreeps or ({})) do
        if c:IsAlive() and c:GetTeam() ~= team and GetUnitToUnitDistance(bot, c) <= r then
            n = n + 1
        end
    end
    return n
end
function maybeDance(bot, enemyCreeps, now)
    if ____exports.AggroDance(enemyCreepsNear(bot, enemyCreeps)) then
        dances[bot:GetPlayerID()] = {
            ["until"] = now + settings().Timing.AggroDanceBack,
            to = stepBack(bot)
        }
    end
end
local IDLE_START = -90
local TOWER_SCAN = 1600
local idle = {}
local randomInterval = {}
local attempts = {}
dances = {}
local spellHarass = {}
function ____exports.ResetCache()
    idle = {}
    randomInterval = {}
    attempts = {}
    dances = {}
end
local function hpOf(unit)
    local h = LaneConfig.Helpers().GetHP
    if h ~= nil then
        return h(unit)
    end
    local max = unit:GetMaxHealth()
    return max > 0 and unit:GetHealth() / max or 0
end
local function isValidHero(unit)
    if unit == nil then
        return false
    end
    local h = LaneConfig.Helpers().IsValidHero
    local ____temp_0
    if h ~= nil then
        ____temp_0 = h(unit)
    else
        ____temp_0 = unit:IsAlive() and unit:CanBeSeen()
    end
    return ____temp_0
end
local function isSuspiciousIllusion(unit)
    local h = LaneConfig.Helpers().IsSuspiciousIllusion
    return h ~= nil and h(unit)
end
local function isValidBuilding(unit)
    local h = LaneConfig.Helpers().IsValidBuilding
    local ____temp_1
    if h ~= nil then
        ____temp_1 = h(unit)
    else
        ____temp_1 = unit:IsAlive()
    end
    return ____temp_1
end
local function weAreStronger(bot)
    local h = LaneConfig.Helpers().WeAreStronger
    return h ~= nil and h(
        bot,
        settings().Radii.Stronger
    )
end
local function weakKeys()
    return setmetatable({}, {__mode = "k"})
end
local function attemptsOf(pid)
    local t = attempts[pid]
    if t == nil then
        t = weakKeys()
        attempts[pid] = t
    end
    return t
end
local function towerWithin(towers, range, a, b)
    for ____, tower in ipairs(towers) do
        if isValidBuilding(tower) and (GetUnitToUnitDistance(tower, a) < range or GetUnitToUnitDistance(tower, b) < range) then
            return true
        end
    end
    return false
end
local function log(bot, kind, etiquette)
    HDebug.Log(
        "lane",
        (((("harass pid=" .. tostring(bot:GetPlayerID())) .. " kind=") .. kind) .. " etiquette=") .. tostring(etiquette)
    )
end
function ____exports.GatesFor(bot, etiquette)
    if etiquette then
        local s = AllyLastHit.Settings()
        return {
            etiquette = etiquette,
            interval = s.HarassInterval,
            window = s.HarassWindow,
            idleExtraRange = s.HarassExtraRange,
            minHP = s.HarassMinHP,
            towerAvoidRange = s.TowerAvoidRange,
            needProtectedHuman = true,
            needStronger = true
        }
    end
    local h = settings().HarassIdle
    local pid = bot:GetPlayerID()
    local interval = math.huge
    if LaneConfig.SkillOf(bot) < settings().Gates.RandomHarass then
        local state = idle[pid]
        if state == nil then
            state = {
                startAt = IDLE_START,
                lastAt = GameTime()
            }
            idle[pid] = state
        end
        local r = randomInterval[pid]
        if r == nil or r.forLastAt ~= state.lastAt then
            local t = settings().Timing
            r = {
                interval = RandomFloat(t.RandomHarassMin, t.RandomHarassMax),
                forLastAt = state.lastAt
            }
            randomInterval[pid] = r
        end
        interval = r.interval
    end
    return {
        etiquette = etiquette,
        interval = interval,
        window = h.IdleWindow,
        idleExtraRange = h.IdleExtraRange,
        minHP = h.IdleMinHP,
        towerAvoidRange = h.TowerAvoidRange,
        needProtectedHuman = false,
        needStronger = true
    }
end
function ____exports.IsLastHitAttempt(enemy, ourCreeps)
    local h = LaneConfig.Helpers()
    local dmg = enemy:GetAttackDamage()
    local target = enemy:GetAttackTarget()
    if target ~= nil and target ~= nil and h.WillKillTarget ~= nil and h.GetAttackProDelayTime ~= nil then
        for ____, creep in ipairs(ourCreeps or ({})) do
            if creep == target and not creep:IsNull() and creep:IsAlive() and h.WillKillTarget(
                creep,
                dmg,
                DamageType.Physical,
                h.GetAttackProDelayTime(enemy, creep)
            ) then
                return creep
            end
        end
    end
    local cfg = settings()
    local here = enemy:GetLocation()
    local ahead = enemy:GetExtrapolatedLocation(cfg.Radii.ApproachExtrapolate)
    local best
    local bestDist = math.huge
    for ____, creep in ipairs(ourCreeps or ({})) do
        do
            local __continue33
            repeat
                if creep:IsNull() or not creep:IsAlive() or creep:GetHealth() > dmg then
                    __continue33 = true
                    break
                end
                local loc = creep:GetLocation()
                local d = dist2D(here, loc)
                if dist2D(ahead, loc) <= d - cfg.Thresholds.ApproachEpsilon and d < bestDist then
                    best = creep
                    bestDist = d
                end
                __continue33 = true
            until true
            if not __continue33 then
                break
            end
        end
    end
    return best
end
function ____exports.TowerForbids(botLevel, nearEnemyTower, targetHP)
    local t = settings().Thresholds
    return botLevel < t.HarassTowerLevel and nearEnemyTower and targetHP >= t.HarassTowerTargetHP
end
function ____exports.Capitalises(skill)
    return LaneConfig.Roll(LaneConfig.Curve("HarassCapitalise", skill))
end
function ____exports.StandPoint(bot, enemy, ourCreeps)
    local cfg = settings()
    if LaneConfig.SkillOf(bot) < cfg.Gates.HarassPosition then
        return nil
    end
    local g = ____exports.GatesFor(
        bot,
        AllyLastHit.OwnsLaning(bot)
    )
    if hpOf(bot) < g.minHP or g.needStronger and not weAreStronger(bot) then
        return nil
    end
    local enemyLoc = enemy:GetLocation()
    local creep
    for ____, c in ipairs(ourCreeps or ({})) do
        do
            local __continue44
            repeat
                if not c:IsAlive() or dist2D(
                    c:GetLocation(),
                    enemyLoc
                ) > cfg.Radii.LowHpCreep then
                    __continue44 = true
                    break
                end
                if creep == nil or c:GetHealth() < creep:GetHealth() then
                    creep = c
                end
                __continue44 = true
            until true
            if not __continue44 then
                break
            end
        end
    end
    if creep == nil then
        return nil
    end
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    local loc = creep:GetLocation()
    local a = Camps.ToTeamAmount(
        team,
        GetAmountAlongLane(lane, loc).amount
    )
    local behind = GetLocationAlongLane(
        lane,
        clamp01(Camps.ToAbsAmount(team, a - cfg.Camps.LaneSampleStep))
    )
    local point = toward(
        loc,
        behind,
        math.max(
            0,
            bot:GetAttackRange() - cfg.Radii.HarassStandBack
        )
    )
    for ____, tower in ipairs(bot:GetNearbyTowers(TOWER_SCAN, true)) do
        if isValidBuilding(tower) and dist2D(
            tower:GetLocation(),
            point
        ) <= cfg.Thresholds.EnemyTowerRange then
            return nil
        end
    end
    return point
end
--- 04's HarassThink with its gates as parameters; keeps 04's statement order and engine call order.
function ____exports.IdlePoke(bot, enemies, g, enemyCreeps)
    local pid = bot:GetPlayerID()
    local st = idle[pid]
    if st == nil then
        st = {startAt = IDLE_START, lastAt = IDLE_START}
        idle[pid] = st
    end
    local now = GameTime()
    if isValidHero(st.target) and now - st.startAt < g.window and bot:GetLastAttackTime() < st.startAt then
        bot:Action_AttackUnit(st.target, true)
        return true
    end
    st.target = nil
    if now - st.lastAt < g.interval or hpOf(bot) < g.minHP then
        return false
    end
    if g.needProtectedHuman then
        local human = AllyLastHit.GetProtectedHuman(
            bot,
            bot:GetLocation()
        )
        if human == nil then
            return false
        end
    end
    if g.needStronger and not weAreStronger(bot) then
        return false
    end
    local towers = bot:GetNearbyTowers(TOWER_SCAN, true)
    local target
    local targetDist = bot:GetAttackRange() + g.idleExtraRange
    for ____, enemy in ipairs(enemies or ({})) do
        if isValidHero(enemy) and not isSuspiciousIllusion(enemy) and GetUnitToUnitDistance(bot, enemy) <= targetDist then
            if not towerWithin(towers, g.towerAvoidRange, bot, enemy) then
                target = enemy
                targetDist = GetUnitToUnitDistance(bot, enemy)
            end
        end
    end
    if target == nil then
        return false
    end
    st.target = target
    st.startAt = now
    st.lastAt = now
    bot:Action_AttackUnit(target, true)
    if not g.etiquette then
        maybeDance(bot, enemyCreeps or ({}), now)
    end
    log(bot, "poke", g.etiquette)
    return true
end
local function noteIdleHit(pid, now)
    local st = idle[pid]
    if st == nil then
        idle[pid] = {startAt = IDLE_START, lastAt = now}
    else
        st.lastAt = now
    end
end
--- Manners at fire time; true when the punish may go ahead.
local function mannersAllow(bot, enemy, towers, etiquette)
    local t = settings().Thresholds
    local near = towerWithin(towers, t.EnemyTowerRange, bot, enemy)
    if ____exports.TowerForbids(
        bot:GetLevel(),
        near,
        hpOf(enemy)
    ) then
        return false
    end
    if etiquette then
        local g = ____exports.GatesFor(bot, true)
        if hpOf(bot) < g.minHP or not weAreStronger(bot) or towerWithin(towers, g.towerAvoidRange, bot, enemy) then
            return false
        end
    end
    return true
end
local function fire(bot, enemy, enemyCreeps, etiquette)
    local fn = spellHarass[bot:GetUnitName()]
    if fn == nil or not fn(bot, enemy) then
        bot:Action_AttackUnit(enemy, true)
    end
    local now = GameTime()
    noteIdleHit(
        bot:GetPlayerID(),
        now
    )
    maybeDance(bot, enemyCreeps, now)
    log(bot, "punish", etiquette)
end
local function punish(bot, allyCreeps, enemyCreeps, enemies, etiquette)
    local pid = bot:GetPlayerID()
    local now = GameTime()
    local dance = dances[pid]
    if dance ~= nil then
        if now < dance["until"] then
            bot:Action_MoveToLocation(dance.to)
            return true
        end
        __TS__Delete(dances, pid)
    end
    local cfg = settings()
    local team = bot:GetTeam()
    local reach = bot:GetAttackRange() + cfg.Thresholds.HarassExtraRange
    local mine = attemptsOf(pid)
    local towers
    for ____, enemy in ipairs(enemies or ({})) do
        do
            local __continue83
            repeat
                if not isValidHero(enemy) or enemy:GetTeam() == team then
                    __continue83 = true
                    break
                end
                local a = mine[enemy]
                if GetUnitToUnitDistance(bot, enemy) > reach then
                    if a ~= nil and a.fireAt ~= nil and now >= a.fireAt then
                        a.fireAt = nil
                    end
                    __continue83 = true
                    break
                end
                local creep = ____exports.IsLastHitAttempt(enemy, allyCreeps)
                if creep ~= nil and (a == nil or a.creep ~= creep) then
                    local skill = LaneConfig.SkillOf(bot)
                    a = {creep = creep}
                    mine[enemy] = a
                    if ____exports.Capitalises(skill) then
                        local delay = Profile.SampleDelay(bot, "react")
                        if skill < cfg.Gates.RandomHarass then
                            delay = delay + RandomFloat(0, cfg.Timing.LowSkillHarassExtra)
                        end
                        a.fireAt = now + delay
                    end
                end
                if a == nil or a.fireAt == nil or now < a.fireAt then
                    __continue83 = true
                    break
                end
                a.fireAt = nil
                if towers == nil then
                    towers = bot:GetNearbyTowers(TOWER_SCAN, true)
                end
                if not mannersAllow(bot, enemy, towers, etiquette) then
                    __continue83 = true
                    break
                end
                fire(bot, enemy, enemyCreeps, etiquette)
                return true
            until true
            if not __continue83 then
                break
            end
        end
    end
    return false
end
function ____exports.Think(bot, allyCreeps, enemyCreeps, enemies, etiquette)
    if not LaneConfig.IsOn("Harass") then
        return false
    end
    local s = LaneState.ForBot(bot)
    if s ~= nil and LanePlan.View(bot, s).handsOff then
        return false
    end
    if punish(
        bot,
        allyCreeps,
        enemyCreeps,
        enemies,
        etiquette
    ) then
        return true
    end
    return ____exports.IdlePoke(
        bot,
        enemies,
        ____exports.GatesFor(bot, etiquette),
        enemyCreeps
    )
end
function ____exports.RegisterSpellHarass(heroName, fn)
    spellHarass[heroName] = fn
end
return ____exports
