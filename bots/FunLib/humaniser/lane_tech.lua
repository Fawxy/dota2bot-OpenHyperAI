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
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local Tower = ____dota.Tower
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LanePlanner = require(GetScriptDirectory().."/FunLib/humaniser/lane_planner")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local IN_LANE_FLAGS = {
    "Block",
    "AggroPull",
    "Freeze",
    "Shove",
    "Harass",
    "Mid"
}
local TOWER_IDS = {
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
local sequences = {}
local drops = {}
local shoves = {}
local finished = {}
local started = {}
local drawAt = {}
local plans = {}
local towerCache = {}
function ____exports.ResetCache()
    sequences = {}
    drops = {}
    shoves = {}
    finished = {}
    started = {}
    drawAt = {}
    plans = {}
    towerCache = {}
end
local function settings()
    return LaneConfig.Settings()
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end
--- Point `len` from `from` toward `to`; `from` itself when the two coincide.
local function toward(from, to, len)
    local d = dist2D(from, to)
    if d < 0.000001 then
        return from
    end
    return Vector(from.x + (to.x - from.x) / d * len, from.y + (to.y - from.y) / d * len, from.z)
end
local function cycleOf(time)
    return math.floor(time / settings().Timing.WaveCycle)
end
local function hpOf(unit)
    local max = unit:GetMaxHealth()
    return max > 0 and unit:GetHealth() / max or 0
end
local function enemyTeamOf(team)
    return team == Team.Radiant and Team.Dire or Team.Radiant
end
local function forwardSign(team)
    return Camps.ToAbsAmount(team, 1) > Camps.ToAbsAmount(team, 0) and 1 or -1
end
local function inLaneFlagsOn()
    if not LaneConfig.IsActive() then
        return false
    end
    for ____, flag in ipairs(IN_LANE_FLAGS) do
        if LaneConfig.IsOn(flag) then
            return true
        end
    end
    return false
end
function ____exports.OwnsLaning(bot)
    if not inLaneFlagsOn() then
        return false
    end
    local mode = LaneConfig.OwnLaningMode()
    if mode == "all" then
        return true
    end
    if mode == "allies" then
        return Difficulty.IsAllyOfHuman(bot)
    end
    return false
end
--- The bot's lane snapshot when the in-lane techniques may act this frame; undefined before any engine call otherwise.
local function activeSnapshot(bot)
    if not inLaneFlagsOn() then
        return nil
    end
    local s = LaneState.ForBot(bot)
    if s == nil then
        return nil
    end
    if GetUnitToLocationDistance(bot, s.frontLoc) > settings().Radii.LaneActive then
        return nil
    end
    return s
end
local function planFor(bot, s)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local cached = plans[pid]
    if cached ~= nil and cached.time == now then
        return cached.choice
    end
    local choice = LanePlanner.Plan(bot, s)
    plans[pid] = {time = now, choice = choice}
    return choice
end
local function enemyTowers(team)
    local now = DotaTime()
    local cached = towerCache[team]
    if cached ~= nil and cached.time == now then
        return cached.list
    end
    local list = {}
    local enemy = enemyTeamOf(team)
    for ____, id in ipairs(TOWER_IDS) do
        local tower = GetTower(enemy, id)
        if tower ~= nil and tower ~= nil and tower:IsAlive() then
            list[#list + 1] = tower
        end
    end
    towerCache[team] = {time = now, list = list}
    return list
end
local function underEnemyTower(team, loc)
    local range = settings().Thresholds.EnemyTowerRange
    for ____, tower in ipairs(enemyTowers(team)) do
        if dist2D(
            tower:GetLocation(),
            loc
        ) <= range then
            return true
        end
    end
    return false
end
local function isUsable(unit)
    return unit ~= nil and unit ~= nil and unit:IsAlive() and unit:CanBeSeen()
end
local function isLaneCreep(unit)
    return isUsable(unit) and LaneState.IsLaneCreepName(unit:GetUnitName())
end
local function cycleSecText(time)
    return string.format(
        "%.1f",
        time % settings().Timing.WaveCycle
    )
end
local function noteStart(bot, tech, reason)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local key = (tostring(cycleOf(now)) .. ":") .. tech
    if started[pid] == key then
        return
    end
    started[pid] = key
    HDebug.Log(
        "lane",
        (((((("pid=" .. tostring(pid)) .. " tech=") .. tech) .. " @") .. cycleSecText(now)) .. " reason=") .. reason
    )
end
function ____exports.Mistake(bot, kind)
    HDebug.Log(
        "lane",
        (("mistake pid=" .. tostring(bot:GetPlayerID())) .. " ") .. kind
    )
end
local function overlay(bot, text)
    HDebug.Text(bot, "lane_exec", text)
end
local function finish(bot)
    local pid = bot:GetPlayerID()
    __TS__Delete(sequences, pid)
    finished[pid] = cycleOf(DotaTime())
end
local function finishedThisCycle(pid)
    return finished[pid] == cycleOf(DotaTime())
end
function ____exports.BlockPoint(lead, dirAmountSign, lane, ahead, side)
    local step = settings().Camps.LaneSampleStep
    local a = GetAmountAlongLane(lane, lead).amount
    local p0 = GetLocationAlongLane(lane, a)
    local p1 = GetLocationAlongLane(
        lane,
        clamp01(a + dirAmountSign * step)
    )
    local d = dist2D(p0, p1)
    if d < 0.000001 then
        return lead
    end
    local dx = (p1.x - p0.x) / d
    local dy = (p1.y - p0.y) / d
    return Vector(lead.x + dx * ahead - dy * side, lead.y + dy * ahead + dx * side, lead.z)
end
function ____exports.HoldPoint(team, lane, eq, ourTower, theirTower, back)
    local step = settings().Camps.LaneSampleStep
    local teamAmount = ourTower + (eq + 1) / 2 * (theirTower - ourTower)
    local loc = GetLocationAlongLane(
        lane,
        clamp01(Camps.ToAbsAmount(team, teamAmount))
    )
    local behind = GetLocationAlongLane(
        lane,
        clamp01(Camps.ToAbsAmount(team, teamAmount - step))
    )
    return toward(loc, behind, back)
end
function ____exports.ShoveTarget(bot, enemyCreeps)
    local team = bot:GetTeam()
    local best
    for ____, c in ipairs(enemyCreeps or ({})) do
        do
            local __continue49
            repeat
                if not isLaneCreep(c) or c:GetTeam() == team then
                    __continue49 = true
                    break
                end
                if underEnemyTower(
                    team,
                    c:GetLocation()
                ) then
                    __continue49 = true
                    break
                end
                if best == nil or c:GetHealth() < best:GetHealth() then
                    best = c
                end
                __continue49 = true
            until true
            if not __continue49 then
                break
            end
        end
    end
    return best
end
local function nearest(from, units, maxDist)
    local best
    local bestDist = maxDist
    for ____, u in ipairs(units) do
        local d = dist2D(
            u:GetLocation(),
            from
        )
        if d <= bestDist then
            best = u
            bestDist = d
        end
    end
    return best
end
local function alliedLaneCreeps(bot, allyCreeps)
    local result = {}
    local team = bot:GetTeam()
    for ____, c in ipairs(allyCreeps or ({})) do
        if isLaneCreep(c) and c:GetTeam() == team then
            result[#result + 1] = c
        end
    end
    return result
end
local function towerTargeting(bot, target, radius)
    local loc = target:GetLocation()
    for ____, tower in ipairs(enemyTowers(bot:GetTeam())) do
        do
            local __continue63
            repeat
                if dist2D(
                    tower:GetLocation(),
                    loc
                ) > radius then
                    __continue63 = true
                    break
                end
                if tower:GetAttackTarget() == target then
                    return tower
                end
                __continue63 = true
            until true
            if not __continue63 then
                break
            end
        end
    end
    return nil
end
--- Safety reaction (exempt from the planner, attempt roll and commit lock): shed tower aggro, then leave its range.
local function towerDrop(bot, s, allyCreeps)
    local pid = bot:GetPlayerID()
    local radii = settings().Radii
    local drop = drops[pid]
    if drop == nil then
        if not LaneConfig.Knows(
            "aggro_pull",
            LaneConfig.SkillOf(bot)
        ) then
            return false
        end
        local tower = towerTargeting(bot, bot, radii.TowerAggro)
        if tower == nil then
            return false
        end
        drop = {tower = tower, dropped = false}
        drops[pid] = drop
        noteStart(bot, "tower_drop", "tower aggro")
    end
    local exit = radii.TowerAggro + radii.TowerExitMargin
    local towerLoc = drop.tower:GetLocation()
    local here = bot:GetLocation()
    if not drop.dropped then
        drop.dropped = true
        local range = bot:GetAttackRange()
        local heroes = {}
        for ____, h in ipairs(s.allies) do
            if h.alive and h.pid ~= pid then
                heroes[#heroes + 1] = h.unit
            end
        end
        local target = nearest(
            here,
            alliedLaneCreeps(bot, allyCreeps),
            range
        ) or nearest(here, heroes, range)
        if target ~= nil then
            overlay(
                bot,
                ("tech=tower_drop@" .. cycleSecText(DotaTime())) .. " drop"
            )
            bot:Action_AttackUnit(target, true)
            return true
        end
    end
    if not drop.tower:IsAlive() or dist2D(here, towerLoc) >= exit - settings().Thresholds.ApproachEpsilon then
        __TS__Delete(drops, pid)
        return false
    end
    overlay(
        bot,
        ("tech=tower_drop@" .. cycleSecText(DotaTime())) .. " exit"
    )
    bot:Action_MoveToLocation(toward(towerLoc, here, exit))
    return true
end
local function blockContact(lead, s, enemyCreeps)
    local contact = settings().Radii.BlockContact
    local loc = lead:GetLocation()
    for ____, list in ipairs({s.enemy.units, enemyCreeps or ({})}) do
        for ____, c in ipairs(list) do
            if isLaneCreep(c) and c:GetTeam() ~= s.team and dist2D(
                c:GetLocation(),
                loc
            ) <= contact then
                return true
            end
        end
    end
    return false
end
local function runBlock(bot, s, seq, enemyCreeps, choice)
    local cfg = settings()
    local now = DotaTime()
    local lead = s.ally.lead
    if choice.tech ~= "block" or now >= cfg.Timing.BlockEnd or lead == nil or not lead:IsAlive() or blockContact(lead, s, enemyCreeps) then
        finish(bot)
        return false
    end
    local leadLoc = lead:GetLocation()
    local dist = GetUnitToLocationDistance(bot, leadLoc)
    if dist <= cfg.Radii.BlockLost then
        seq.engaged = true
    end
    if seq.engaged == true and dist > cfg.Radii.BlockLost then
        if seq.lostSince == nil then
            seq.lostSince = now
        end
        if now - seq.lostSince >= cfg.Timing.BlockLostSec then
            ____exports.Mistake(bot, "block-lost")
            finish(bot)
            return false
        end
    else
        seq.lostSince = nil
    end
    if seq.engaged ~= true and dist > cfg.Radii.BlockStart then
        seq.phase = "approach"
        overlay(
            bot,
            ("tech=block@" .. cycleSecText(seq.startedAt)) .. " approach"
        )
        bot:Action_MoveToLocation(leadLoc)
        return true
    end
    seq.phase = "block"
    if seq.noiseAt == nil or now - seq.noiseAt >= cfg.Timing.BlockNoiseEvery then
        seq.noiseAt = now
        seq.noise = RandomFloat(-1, 1) * LaneConfig.Curve(
            "PathNoise",
            LaneConfig.SkillOf(bot)
        )
        seq.side = (seq.side == nil or seq.side < 0) and 1 or -1
    end
    local point = ____exports.BlockPoint(
        leadLoc,
        forwardSign(s.team),
        s.lane,
        cfg.Radii.BlockAhead + (seq.noise or 0),
        (seq.side or 1) * cfg.Radii.BlockSide
    )
    overlay(
        bot,
        ("tech=block@" .. cycleSecText(seq.startedAt)) .. " block"
    )
    bot:Action_MoveToLocation(point)
    return true
end
local function startBlock(bot, s, enemyCreeps, choice)
    local lead = s.ally.lead
    if DotaTime() >= settings().Timing.BlockEnd or lead == nil or blockContact(lead, s, enemyCreeps) then
        return false
    end
    local seq = {
        tech = "block",
        phase = "approach",
        startedAt = DotaTime()
    }
    sequences[bot:GetPlayerID()] = seq
    local acted = runBlock(
        bot,
        s,
        seq,
        enemyCreeps,
        choice
    )
    if acted then
        LanePlanner.Commit(bot, "block")
        noteStart(bot, "block", choice.reason)
    end
    return acted
end
local function drawTarget(bot, enemies)
    local reach = bot:GetAttackRange() + settings().Radii.AggroDrawExtra
    local team = bot:GetTeam()
    local candidates = {}
    for ____, e in ipairs(enemies or ({})) do
        do
            local __continue96
            repeat
                if not isUsable(e) or e:GetTeam() == team or underEnemyTower(
                    team,
                    e:GetLocation()
                ) then
                    __continue96 = true
                    break
                end
                candidates[#candidates + 1] = e
                __continue96 = true
            until true
            if not __continue96 then
                break
            end
        end
    end
    return nearest(
        bot:GetLocation(),
        candidates,
        reach
    )
end
--- Lane point to walk the drawn creeps back to: one aggro step behind the wave, never ahead of the bot.
local function walkBackPoint(bot, s)
    local cfg = settings()
    local here = bot:GetLocation()
    local own = LaneState.EqPos(
        Camps.ToTeamAmount(
            s.team,
            GetAmountAlongLane(s.lane, here).amount
        ),
        s.ourTowerAmount,
        s.theirTowerAmount
    )
    local eq = math.min(s.eqPos - cfg.Planner.AggroStepEq, own)
    local lanePoint = ____exports.HoldPoint(
        s.team,
        s.lane,
        eq,
        s.ourTowerAmount,
        s.theirTowerAmount,
        cfg.Radii.AggroWalkBack
    )
    local noise = LaneConfig.Curve(
        "PathNoise",
        LaneConfig.SkillOf(bot)
    )
    local point = Vector(
        lanePoint.x + RandomFloat(-1, 1) * noise,
        lanePoint.y + RandomFloat(-1, 1) * noise,
        lanePoint.z
    )
    return dist2D(here, point) > cfg.Radii.AggroWalkMax and toward(here, point, cfg.Radii.AggroWalkMax) or point
end
local function beginDrop(bot, s, phase, reason)
    local now = DotaTime()
    LanePlanner.Commit(bot, "aggro_pull")
    LaneRoles.NoteAggroDraw(bot, s)
    sequences[bot:GetPlayerID()] = {
        tech = "aggro_pull",
        phase = phase,
        startedAt = now,
        walkTo = phase == "walk" and walkBackPoint(bot, s) or nil
    }
    noteStart(bot, "aggro_pull", reason)
end
--- Planned swap: an allied core is losing HP to an enemy tower, so the bot takes the tower's aggro instead.
local function trySwap(bot, s, enemies, reason)
    local t = settings().Thresholds
    if hpOf(bot) <= t.TowerSwapBotHP then
        return false
    end
    local pid = bot:GetPlayerID()
    for ____, h in ipairs(s.allies) do
        do
            local __continue103
            repeat
                if not h.alive or h.pid == pid or h.position == nil or h.position < 1 or h.position > 3 or h.hp >= t.TowerSwapAllyHP then
                    __continue103 = true
                    break
                end
                local tower = towerTargeting(
                    bot,
                    h.unit,
                    settings().Radii.TowerAggro
                )
                if tower == nil then
                    __continue103 = true
                    break
                end
                local candidates = {}
                for ____, e in ipairs(enemies or ({})) do
                    if isUsable(e) and e:GetTeam() ~= s.team then
                        candidates[#candidates + 1] = e
                    end
                end
                local hero = nearest(
                    tower:GetLocation(),
                    candidates,
                    t.EnemyTowerRange
                )
                if hero == nil then
                    __continue103 = true
                    break
                end
                bot:Action_AttackUnit(hero, true)
                beginDrop(bot, s, "swap", reason .. ": tower swap")
                overlay(
                    bot,
                    ("tech=aggro_pull@" .. cycleSecText(DotaTime())) .. " swap"
                )
                return true
            until true
            if not __continue103 then
                break
            end
        end
    end
    return false
end
local function startAggro(bot, s, enemies, choice)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local at = drawAt[pid]
    if at == nil then
        at = now + math.max(
            0,
            LaneConfig.Jitter(LaneConfig.SkillOf(bot))
        )
        drawAt[pid] = at
    end
    if now < at then
        overlay(
            bot,
            string.format("tech=aggro_pull wait: jitter %.1fs", at - now)
        )
        return false
    end
    local may, why = LaneRoles.MayDrawAggro(bot, s)
    if not may then
        overlay(bot, "tech=aggro_pull " .. why)
        return false
    end
    if trySwap(bot, s, enemies, choice.reason) then
        __TS__Delete(drawAt, pid)
        return true
    end
    local hero = drawTarget(bot, enemies)
    if hero == nil then
        overlay(bot, "tech=aggro_pull wait: no target")
        return false
    end
    __TS__Delete(drawAt, pid)
    bot:Action_AttackUnit(hero, true)
    beginDrop(bot, s, "walk", choice.reason)
    overlay(
        bot,
        ("tech=aggro_pull@" .. cycleSecText(DotaTime())) .. " draw"
    )
    return true
end
local function runAggro(bot, seq, allyCreeps)
    local now = DotaTime()
    local walkBack = settings().Timing.WalkBack
    if seq.phase == "swap" then
        if now - seq.startedAt < walkBack then
            Intent.Hold(bot, "lane:swap")
            return true
        end
        finish(bot)
        return false
    end
    if seq.phase == "walk" and now - seq.startedAt < walkBack then
        overlay(
            bot,
            ("tech=aggro_pull@" .. cycleSecText(seq.startedAt)) .. " walk"
        )
        bot:Action_MoveToLocation(seq.walkTo or bot:GetLocation())
        return true
    end
    finish(bot)
    local creeps = alliedLaneCreeps(bot, allyCreeps)
    local here = bot:GetLocation()
    local target = nearest(
        here,
        creeps,
        bot:GetAttackRange()
    ) or nearest(here, creeps, math.huge)
    if target == nil then
        return false
    end
    overlay(
        bot,
        ("tech=aggro_pull@" .. cycleSecText(seq.startedAt)) .. " drop"
    )
    bot:Action_AttackUnit(target, true)
    return true
end
--- Only the tower-aggro drop: for a bot that must otherwise leave this wave alone.
function ____exports.TowerDropThink(bot, allyCreeps)
    local s = activeSnapshot(bot)
    return s ~= nil and towerDrop(bot, s, allyCreeps)
end
function ____exports.PreThink(bot, allyCreeps, enemyCreeps, enemies)
    local s = activeSnapshot(bot)
    if s == nil then
        return false
    end
    if towerDrop(bot, s, allyCreeps) then
        return true
    end
    local pid = bot:GetPlayerID()
    local choice = planFor(bot, s)
    local seq = sequences[pid]
    if seq ~= nil then
        if seq.tech == "block" then
            return runBlock(
                bot,
                s,
                seq,
                enemyCreeps,
                choice
            )
        end
        return runAggro(bot, seq, allyCreeps)
    end
    if choice.tech ~= "aggro_pull" then
        __TS__Delete(drawAt, pid)
    end
    if finishedThisCycle(pid) then
        return false
    end
    if choice.tech == "block" then
        return startBlock(bot, s, enemyCreeps, choice)
    end
    if choice.tech == "aggro_pull" then
        return startAggro(bot, s, enemies, choice)
    end
    return false
end
local function enemyCreepsNearFront(s)
    local n = 0
    for ____, c in ipairs(s.enemy.units) do
        if isLaneCreep(c) then
            n = n + 1
        end
    end
    return n
end
function ____exports.Think(bot, _allyCreeps, enemyCreeps, _enemies)
    local s = activeSnapshot(bot)
    if s == nil then
        return false
    end
    local pid = bot:GetPlayerID()
    local cfg = settings()
    local now = DotaTime()
    local choice = planFor(bot, s)
    local shove = shoves[pid]
    if shove ~= nil then
        if choice.tech ~= "shove" or now - shove.startedAt >= cfg.Timing.ShoveMaxSec or enemyCreepsNearFront(s) <= cfg.Thresholds.ShoveDoneCreeps then
            __TS__Delete(shoves, pid)
            finished[pid] = cycleOf(now)
            return false
        end
    elseif choice.tech ~= "shove" or finishedThisCycle(pid) or enemyCreepsNearFront(s) <= cfg.Thresholds.ShoveDoneCreeps then
        return false
    end
    local stronger = LaneConfig.Helpers().WeAreStronger
    if stronger == nil or not stronger(bot, cfg.Radii.Stronger) or hpOf(bot) < cfg.Thresholds.ShoveMinHP then
        return false
    end
    local target = ____exports.ShoveTarget(bot, enemyCreeps)
    if target == nil then
        return false
    end
    if shove == nil then
        shove = {startedAt = now}
        shoves[pid] = shove
        LanePlanner.Commit(bot, "shove")
        noteStart(bot, "shove", choice.reason)
        if choice.reason == "shove before rotating" and LaneConfig.IsOn("Telegraph") and Difficulty.IsAllyOfHuman(bot) then
            Orders.Say(bot, "say_lane_shove_rotate", cfg.Timing.ShoveTelegraphCooldown)
        end
    end
    overlay(
        bot,
        ("tech=shove@" .. cycleSecText(shove.startedAt)) .. " hit"
    )
    bot:Action_AttackUnit(target, true)
    return true
end
--- Visible enemy laner nearest our lead creep, within Zone of the front.
local function zoneTarget(bot, s)
    local zone = settings().Radii.Zone
    local best
    local bestDist = math.huge
    for ____, e in ipairs(LaneState.Enemies(bot, s.lane)) do
        do
            local __continue146
            repeat
                if not e.visible or dist2D(e.location, s.frontLoc) > zone then
                    __continue146 = true
                    break
                end
                local d = dist2D(e.location, s.frontLoc)
                if d < bestDist then
                    best = e.location
                    bestDist = d
                end
                __continue146 = true
            until true
            if not __continue146 then
                break
            end
        end
    end
    return best
end
--- Between our lead creep and the nearest visible enemy laner: where a support zones from.
function ____exports.ZonePoint(bot, s)
    local lead = s.ally.lead
    if lead == nil then
        return nil
    end
    local enemy = zoneTarget(bot, s)
    return enemy ~= nil and toward(
        lead:GetLocation(),
        enemy,
        settings().Radii.ZoneOffset
    ) or nil
end
--- freeze/hold, or the plan's posture when the one-per-cycle lock (after e.g. a drag-back) hides it from the choice.
local function postureOf(bot, s, choice)
    if choice.tech == "freeze" or choice.tech == "hold" then
        return choice.tech
    end
    if choice.tech ~= "none" or string.sub(choice.reason, 1, 13) ~= "one per cycle" then
        return nil
    end
    local pos = LaneConfig.PositionOf(bot)
    local plan = (pos ~= nil and pos >= 4 and LanePlan.ForSupport(bot, s) or LanePlan.View(bot, s)).plan
    return plan == "FREEZE" and "freeze" or (plan == "HOLD" and "hold" or nil)
end
function ____exports.AdjustPosition(bot, loc)
    local s = activeSnapshot(bot)
    if s == nil then
        return loc
    end
    local choice = planFor(bot, s)
    local posture = postureOf(bot, s, choice)
    if posture == nil then
        return loc
    end
    noteStart(bot, posture, choice.reason)
    Intent.Hold(bot, "lane:" .. posture)
    local cfg = settings()
    local pos = LaneConfig.PositionOf(bot)
    if pos ~= nil and pos >= 4 then
        local zone = ____exports.ZonePoint(bot, s)
        if zone ~= nil then
            overlay(
                bot,
                ((("tech=" .. posture) .. "@") .. cycleSecText(DotaTime())) .. " zone"
            )
            return zone
        end
    end
    overlay(
        bot,
        ((("tech=" .. posture) .. "@") .. cycleSecText(DotaTime())) .. " hold"
    )
    local back = math.max(
        bot:GetAttackRange(),
        cfg.Radii.HoldMinBack
    )
    return ____exports.HoldPoint(
        s.team,
        s.lane,
        s.desiredEq,
        s.ourTowerAmount,
        s.theirTowerAmount,
        back
    )
end
return ____exports
