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
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local claims = {}
local lastDraw = {}
local needSince = {}
local covers = {}
function ____exports.ResetCache()
    claims = {}
    lastDraw = {}
    needSince = {}
    covers = {}
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function positionOf(h)
    return h.position or 0
end
local function selfIn(bot, s)
    local pid = bot:GetPlayerID()
    for ____, h in ipairs(s.allies) do
        if h.pid == pid then
            return h
        end
    end
    return nil
end
local function others(bot, s)
    local pid = bot:GetPlayerID()
    local result = {}
    for ____, h in ipairs(s.allies) do
        if h.alive and h.assigned and h.pid ~= pid then
            result[#result + 1] = h
        end
    end
    return result
end
--- Lowest-position core of the lane, ties by lower pid. `includeDead` serves CoreAbsent only.
local function coreOf(s, includeDead, exclude)
    local best
    for ____, h in ipairs(s.allies) do
        do
            local __continue14
            repeat
                if not h.assigned or h.pid == exclude or not h.alive and not includeDead then
                    __continue14 = true
                    break
                end
                local pos = h.position
                if pos == nil or pos < 1 or pos > 3 then
                    __continue14 = true
                    break
                end
                if best == nil or pos < best.position or pos == best.position and h.pid < best.pid then
                    best = h
                end
                __continue14 = true
            until true
            if not __continue14 then
                break
            end
        end
    end
    return best
end
function ____exports.RoleIn(bot, s)
    if #others(bot, s) == 0 then
        return "solo"
    end
    local ____opt_0 = selfIn(bot, s)
    local own = ____opt_0 and ____opt_0.position or LaneConfig.PositionOf(bot)
    return own ~= nil and own >= 4 and "support" or "core"
end
function ____exports.Partner(bot, s)
    local role = ____exports.RoleIn(bot, s)
    if role == "solo" then
        return nil
    end
    if role == "support" then
        return coreOf(
            s,
            false,
            bot:GetPlayerID()
        )
    end
    local best
    for ____, h in ipairs(others(bot, s)) do
        do
            local __continue24
            repeat
                if positionOf(h) < 4 then
                    __continue24 = true
                    break
                end
                if best == nil or positionOf(h) > positionOf(best) or positionOf(h) == positionOf(best) and h.pid < best.pid then
                    best = h
                end
                __continue24 = true
            until true
            if not __continue24 then
                break
            end
        end
    end
    return best
end
local function isEnemyLaneCreep(target, ownTeam)
    return target ~= nil and target ~= nil and target:GetTeam() ~= ownTeam and LaneState.IsLaneCreepName(target:GetUnitName())
end
function ____exports.CoreBusy(core, _now)
    if not core.alive then
        return false
    end
    local cfg = LaneConfig.Settings().Thresholds
    if core.hp < cfg.CoreBusyHP then
        return true
    end
    local target = core.unit:GetAttackTarget()
    return isEnemyLaneCreep(
        target,
        core.unit:GetTeam()
    ) and target:GetHealth() <= core.unit:GetAttackDamage() * cfg.CoreBusyDamageMult
end
--- Records when this bot's need for an aggro draw began; keeps the first stamp until ClearNeed.
function ____exports.NoteNeed(bot, now)
    local pid = bot:GetPlayerID()
    if needSince[pid] == nil then
        needSince[pid] = now
    end
end
function ____exports.ClearNeed(bot)
    __TS__Delete(
        needSince,
        bot:GetPlayerID()
    )
end
local function claimKey(s)
    return (tostring(s.team) .. ":") .. tostring(s.lane)
end
function ____exports.MayDrawAggro(bot, s)
    local cfg = LaneConfig.Settings()
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local window = cfg.Timing.AggroWindow
    local allyActed = false
    for other, at in pairs(s.lastAllyAggroAt) do
        if other ~= pid and now - at < window then
            allyActed = true
        end
    end
    local claim = claims[claimKey(s)]
    if claim ~= nil and claim.pid ~= pid and now - claim.at < window then
        allyActed = true
    end
    if allyActed then
        if LaneConfig.Roll(LaneConfig.Curve(
            "DoubleDraw",
            LaneConfig.SkillOf(bot)
        )) then
            HDebug.Log(
                "lane",
                ("pid=" .. tostring(pid)) .. " mistake: double-draw"
            )
            return true, "mistake: double-draw"
        end
        return false, "wait: ally-aggro"
    end
    local own = lastDraw[pid]
    if own ~= nil and now - own < cfg.Timing.AggroCooldown then
        return false, "wait: cooldown"
    end
    local ____self = selfIn(bot, s)
    if ____exports.RoleIn(bot, s) == "core" and ____self ~= nil then
        local partner = ____exports.Partner(bot, s)
        if partner ~= nil and partner.isBot and partner.alive and partner.distToFront <= cfg.Thresholds.SupportNearFront then
            if ____exports.CoreBusy(____self, now) then
                return false, "yield: support"
            end
            if needSince[pid] == nil then
                needSince[pid] = now
            end
            if now - needSince[pid] < cfg.Timing.CoreYieldStagger then
                return false, "yield: stagger"
            end
        end
    end
    return true, "ok"
end
function ____exports.NoteAggroDraw(bot, s)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    claims[claimKey(s)] = {pid = pid, at = now}
    lastDraw[pid] = now
end
function ____exports.CampJobOwner(s)
    local best
    for ____, h in ipairs(s.allies) do
        do
            local __continue50
            repeat
                if not h.alive then
                    __continue50 = true
                    break
                end
                if not h.isBot then
                    if positionOf(h) >= 4 then
                        return nil
                    end
                    __continue50 = true
                    break
                end
                if not h.assigned then
                    __continue50 = true
                    break
                end
                if best == nil or positionOf(h) > positionOf(best) or positionOf(h) == positionOf(best) and h.pid < best.pid then
                    best = h
                end
                __continue50 = true
            until true
            if not __continue50 then
                break
            end
        end
    end
    return best and best.pid
end
function ____exports.PartnerSafe(bot, s, enemies)
    local partner = ____exports.Partner(bot, s)
    if partner == nil then
        return true
    end
    local cfg = LaneConfig.Settings().Thresholds
    if partner.hp < cfg.PartnerMinHP then
        return false
    end
    local loc = partner.unit:GetLocation()
    local near = 0
    for ____, e in ipairs(enemies) do
        if e.visible and dist2D(e.location, loc) <= cfg.PartnerDangerRadius then
            near = near + 1
        end
    end
    return near < cfg.PartnerDangerEnemies
end
function ____exports.LaneStable(bot, enemies)
    local cfg = LaneConfig.Settings().Thresholds
    local maxHP = bot:GetMaxHealth()
    if maxHP <= 0 or bot:GetHealth() / maxHP <= cfg.StableMinHP then
        return false
    end
    local loc = bot:GetLocation()
    for ____, e in ipairs(enemies) do
        do
            local __continue65
            repeat
                if not e.visible and e.timeSinceSeen > cfg.StableSeenWithin then
                    __continue65 = true
                    break
                end
                if dist2D(e.location, loc) <= cfg.StableEnemyRadius then
                    return false
                end
                __continue65 = true
            until true
            if not __continue65 then
                break
            end
        end
    end
    return true
end
function ____exports.MayRunCampJob(bot, s, enemies)
    if ____exports.CampJobOwner(s) ~= bot:GetPlayerID() then
        return false, "not-owner"
    end
    if not LaneConfig.InLaningPhase() then
        return false, "not-laning"
    end
    if ____exports.RoleIn(bot, s) == "solo" then
        if LaneConfig.SkillOf(bot) <= LaneConfig.Settings().Gates.SoloCampJob then
            return false, "solo: skill"
        end
        if not ____exports.LaneStable(bot, enemies) then
            return false, "solo: unstable"
        end
    elseif not ____exports.PartnerSafe(bot, s, enemies) then
        return false, "partner unsafe"
    end
    return true, "ok"
end
function ____exports.CoreAbsent(s)
    local core = coreOf(s, true)
    if core == nil then
        return false
    end
    return not core.alive or core.distToFront > LaneConfig.Settings().Thresholds.CoreAbsentDist
end
function ____exports.CoverAbsentCore(bot, s, _now)
    local pid = bot:GetPlayerID()
    local c = covers[pid]
    if c == nil then
        c = {absent = false, cover = false}
        covers[pid] = c
    end
    if not ____exports.CoreAbsent(s) then
        c.absent = false
        c.cover = false
        return false
    end
    if not c.absent then
        c.absent = true
        c.cover = LaneConfig.Roll(LaneConfig.Curve(
            "CoverAbsentCore",
            LaneConfig.SkillOf(bot)
        ))
    end
    return c.cover
end
return ____exports
