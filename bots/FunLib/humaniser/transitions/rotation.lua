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
local runeAt
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Rune = ____dota.Rune
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
local Runes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/runes")
local Busy = require(GetScriptDirectory().."/FunLib/humaniser/transitions/busy")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
function runeAt(side)
    for ____, rune in ipairs({Rune.Power1, Rune.Power2}) do
        if (GetRuneSpawnLocation(rune).y > 0 and "top" or "bot") == side then
            return rune
        end
    end
    return nil
end
____exports.SOURCE = "transitions:rotate"
local entries = {}
local holdState = {}
function ____exports.ResetCache()
    for k in pairs(entries) do
        __TS__Delete(entries, k)
    end
    for k in pairs(holdState) do
        __TS__Delete(holdState, k)
    end
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
--- Only bot supports decide or rotate; a human support's plans are unknown, so they are never guessed.
local function isSupport(bot)
    local pos = LaneConfig.PositionOf(bot)
    return (pos == 4 or pos == 5) and bot:IsBot()
end
local function teammate(bot, pos, botsOnly)
    local n = #GetTeamPlayers(bot:GetTeam())
    do
        local i = 1
        while i <= n do
            local m = GetTeamMember(i)
            if m ~= nil and m ~= nil and m:IsAlive() and LaneConfig.PositionOf(m) == pos and (not botsOnly or m:IsBot()) then
                return m
            end
            i = i + 1
        end
    end
    return nil
end
--- Enemies visible, or seen within ContestSeenWithin, inside `radius` (ContestRadius) of the spot. Perception goes through LaneState.
local function enemiesNear(bot, spot, radius)
    if radius == nil then
        radius = Settings.Get().ContestRadius
    end
    local cfg = Settings.Get()
    local n = 0
    for ____, e in ipairs(LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )) do
        do
            local __continue11
            repeat
                if not e.visible and e.timeSinceSeen > cfg.ContestSeenWithin then
                    __continue11 = true
                    break
                end
                if dist2D(e.location, spot) <= radius then
                    n = n + 1
                end
                __continue11 = true
            until true
            if not __continue11 then
                break
            end
        end
    end
    return n
end
local function log(bot, d, enemies, us)
    local extra = enemies ~= nil and ((" enemies=" .. tostring(enemies)) .. " ours=") .. tostring(us) or ""
    HDebug.Log(
        "transitions",
        ((((((((((("rotate pid=" .. tostring(bot:GetPlayerID())) .. " spawn=") .. tostring(d.spawn)) .. " go=") .. tostring(d.go)) .. " side=") .. (d.side or "-")) .. " leaveAt=") .. (d.leaveAt ~= nil and string.format("%.1f", d.leaveAt) or "-")) .. " reason=") .. d.reason) .. extra
    )
    Telemetry.Event(
        "tr_rotate",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"spawn", d.spawn},
            {"go", d.go},
            {"side", d.side},
            {"leaveAt", d.leaveAt},
            {"reason", d.reason},
            {"enemies", enemies},
            {"ours", us}
        }
    )
end
function ____exports.Decide(bot, now)
    local cfg = Settings.Get()
    local pid = bot:GetPlayerID()
    local spawn = Runes.NextSpawn("power", now)
    local cached = entries[pid]
    if cached ~= nil and cached.decision.spawn == spawn then
        return cached.decision
    end
    if not Settings.IsOn("Rotation") then
        return {spawn = spawn, go = false, reason = "off"}
    end
    if not isSupport(bot) then
        return {spawn = spawn, go = false, reason = "role"}
    end
    if spawn < Runes.RUNE_RULES.power.first or now < spawn - cfg.DecideFrom or now > spawn - cfg.DecideTo then
        return {spawn = spawn, go = false, reason = "window"}
    end
    if not Phase.LaningTransitions(bot) then
        local off = {spawn = spawn, go = false, reason = "phase"}
        entries[pid] = {decision = off, arriveAt = -math.huge, announced = true, checkAt = math.huge}
        log(bot, off)
        return off
    end
    local ____temp_0
    if LaneConfig.PositionOf(bot) == 5 then
        ____temp_0 = teammate(bot, 4, true)
    else
        ____temp_0 = nil
    end
    local p4 = ____temp_0
    local d4 = p4 ~= nil and ____exports.Decide(p4, now) or nil
    local skill = LaneConfig.SkillOf(bot)
    local rolled = LaneConfig.Roll(Settings.Lerp(cfg.RotateChance, skill))
    local jitter = LaneConfig.Gauss() * Settings.Lerp(cfg.ArriveSigma, skill)
    local mistake = LaneConfig.Roll(Settings.Lerp(cfg.MistakeChance, skill))
    local loc = bot:GetLocation()
    local spot, side = Runes.NearestPowerSpot(loc)
    local travel = dist2D(loc, spot) * cfg.PathFactor / math.max(
        bot:GetCurrentMovementSpeed(),
        1
    )
    local leaveAt = spawn - cfg.ArriveLead - travel + jitter
    local d = {
        spawn = spawn,
        go = false,
        spot = spot,
        side = side,
        leaveAt = leaveAt,
        reason = "ok"
    }
    local strict = LaneConfig.PositionOf(bot) == 5
    local busy, busyWhy = Busy.IsBusy(bot, spawn)
    local spare, spareWhy = Busy.LaneCanSpare(bot, strict)
    if busy then
        d.reason = busyWhy
    elseif leaveAt < now - cfg.LateSlack then
        d.reason = "late"
    elseif not spare and not mistake then
        d.reason = spareWhy
    elseif not rolled then
        d.reason = "roll"
    elseif p4 ~= nil then
        local p4Busy = (Busy.IsBusy(p4, spawn))
        local contested = enemiesNear(bot, spot) >= cfg.Pos5ContestEnemies
        if d4 ~= nil and d4.go and not contested then
            d.reason = "pos4 going"
        elseif not p4Busy and dist2D(loc, spot) > dist2D(
            p4:GetLocation(),
            spot
        ) then
            d.reason = "pos4 closer"
        else
            d.go = true
        end
    else
        d.go = true
    end
    if d.go and not spare then
        d.reason = "mistake"
    end
    entries[pid] = {decision = d, arriveAt = leaveAt + travel, announced = false, checkAt = -math.huge}
    log(bot, d)
    return d
end
function ____exports.Active(bot)
    if not Settings.IsOn("Rotation") or not bot:IsBot() then
        return nil
    end
    local e = entries[bot:GetPlayerID()]
    if e == nil or not e.decision.go then
        return nil
    end
    local now = DotaTime()
    local d = e.decision
    local cfg = Settings.Get()
    if d.leaveAt == nil or now < d.leaveAt then
        return nil
    end
    if now <= d.spawn + cfg.RotateLinger then
        return d
    end
    local rune = runeAt(d.side)
    return rune ~= nil and now <= d.spawn + cfg.RuneHoldMax and GetRuneStatus(rune) == RUNE_STATUS_AVAILABLE and d or nil
end
--- The power rune id at the active decision's side.
function ____exports.RuneTarget(bot)
    local d = ____exports.Active(bot)
    local ____temp_1
    if d ~= nil then
        ____temp_1 = runeAt(d.side)
    else
        ____temp_1 = nil
    end
    return ____temp_1
end
--- Whether a rotating support at its spawned rune leaves it on the ground for our mid (who is coming while within
-- ContestMidRadius of the spot). It takes the rune once an enemy hero is near, once our mid is still not coming
-- RuneHoldGrace s after the spawn, or at RuneHoldMax.
function ____exports.HoldsRune(bot, rune)
    local d = ____exports.Active(bot)
    if d == nil or d.spot == nil or runeAt(d.side) ~= rune then
        return false
    end
    local cfg = Settings.Get()
    local now = DotaTime()
    local mid = teammate(bot, 2, false)
    local midComing = mid ~= nil and dist2D(
        mid:GetLocation(),
        d.spot
    ) <= cfg.ContestMidRadius
    local take
    if now >= d.spawn + cfg.RuneHoldMax then
        take = "max"
    elseif enemiesNear(bot, d.spot, cfg.RuneHoldEnemyRadius) > 0 then
        take = "enemy"
    elseif now >= d.spawn + cfg.RuneHoldGrace and not midComing then
        take = "late"
    end
    local state = take or "hold"
    local pid = bot:GetPlayerID()
    if holdState[pid] ~= (tostring(d.spawn) .. ":") .. state then
        holdState[pid] = (tostring(d.spawn) .. ":") .. state
        Telemetry.Event(
            "tr_rune_hold",
            {
                {"pid", pid},
                {"spawn", d.spawn},
                {"state", take == nil and "hold" or "take"},
                {"reason", take},
                {
                    "mid",
                    mid ~= nil and math.floor(dist2D(
                        mid:GetLocation(),
                        d.spot
                    )) or nil
                }
            }
        )
    end
    return take == nil
end
--- For our mid: contest the rune harder when a rotating support is with it or at the spot.
function ____exports.MidRuneDesire(bot)
    if not Settings.IsOn("Rotation") or LaneConfig.PositionOf(bot) ~= 2 then
        return 0
    end
    local cfg = Settings.Get()
    local now = DotaTime()
    for ____, pos in ipairs({4, 5}) do
        do
            local __continue50
            repeat
                local support = teammate(bot, pos, true)
                local ____temp_2
                if support ~= nil then
                    ____temp_2 = ____exports.Active(support)
                else
                    ____temp_2 = nil
                end
                local d = ____temp_2
                if support == nil or d == nil or d.spot == nil then
                    __continue50 = true
                    break
                end
                if now < d.spawn - cfg.MidContestFrom then
                    __continue50 = true
                    break
                end
                local sLoc = support:GetLocation()
                if dist2D(
                    sLoc,
                    bot:GetLocation()
                ) <= cfg.MidSupportRadius or dist2D(sLoc, d.spot) <= cfg.MidSupportRadius then
                    return cfg.MidContestDesire
                end
                __continue50 = true
            until true
            if not __continue50 then
                break
            end
        end
    end
    return 0
end
--- The planned (or current) rotation side, for the overlay.
function ____exports.Target(bot)
    if not Settings.IsOn("Rotation") then
        return nil
    end
    local e = entries[bot:GetPlayerID()]
    if e == nil or not e.decision.go or DotaTime() > e.decision.spawn + Settings.Get().RotateLinger then
        return nil
    end
    return e.decision.side
end
local function say(bot, key)
    if Difficulty.IsAllyOfHuman(bot) then
        Orders.Say(
            bot,
            key,
            Settings.Get().ChatCooldown
        )
    end
end
--- Our heroes at or heading for the spot: the support, our mid within ContestMidRadius, another bot support
-- rotating there, and any other human ally standing within ContestRadius of it now (by position only).
local function ours(bot, d)
    local cfg = Settings.Get()
    if d.spot == nil then
        return 1
    end
    local n = 1
    local mid = teammate(bot, 2, false)
    if mid ~= nil and dist2D(
        mid:GetLocation(),
        d.spot
    ) <= cfg.ContestMidRadius then
        n = n + 1
    end
    local other = teammate(
        bot,
        LaneConfig.PositionOf(bot) == 4 and 5 or 4,
        true
    )
    local od = other ~= nil and entries[other:GetPlayerID()] or nil
    if od ~= nil and od.decision.go and od.decision.spawn == d.spawn and od.decision.side == d.side then
        n = n + 1
    end
    local count = #GetTeamPlayers(bot:GetTeam())
    do
        local i = 1
        while i <= count do
            do
                local __continue64
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m == mid or m == bot or m:IsBot() or not m:IsAlive() then
                        __continue64 = true
                        break
                    end
                    if dist2D(
                        m:GetLocation(),
                        d.spot
                    ) <= cfg.ContestRadius then
                        n = n + 1
                    end
                    __continue64 = true
                until true
                if not __continue64 then
                    break
                end
            end
            i = i + 1
        end
    end
    return n
end
function ____exports.Tick(bot)
    if not Settings.IsOn("Rotation") or not isSupport(bot) then
        return
    end
    local cfg = Settings.Get()
    local now = DotaTime()
    ____exports.Decide(bot, now)
    local e = entries[bot:GetPlayerID()]
    if e ~= nil and e.decision.go and not Phase.LaningTransitions(bot) then
        e.decision.go = false
        e.decision.reason = "phase"
        Intent.Release(bot, ____exports.SOURCE, BotMode.Rune)
        log(bot, e.decision)
        return
    end
    if e ~= nil and e.decision.go and now <= e.decision.spawn + cfg.RotateLinger then
        local d = e.decision
        if not e.announced then
            e.announced = true
            say(bot, "say_rune_coming_mid")
        end
        if now >= e.checkAt and now >= e.arriveAt - cfg.ContestFrom and d.spot ~= nil then
            e.checkAt = now + cfg.Refresh
            local enemies = enemiesNear(bot, d.spot)
            local us = ours(bot, d)
            if enemies > us then
                d.go = false
                d.reason = "contested"
                Intent.Release(bot, ____exports.SOURCE, BotMode.Rune)
                log(bot, d, enemies, us)
                say(bot, "say_rune_lost")
                return
            end
        end
    end
    local a = ____exports.Active(bot)
    if a == nil then
        return
    end
    Intent.Claim(bot, {source = ____exports.SOURCE, tier = "TRANSITION", mode = BotMode.Rune, floor = cfg.RotateFloor})
    if now < a.spawn and a.spot ~= nil and dist2D(
        bot:GetLocation(),
        a.spot
    ) <= cfg.RotateHoldRadius then
        Intent.Hold(bot, ____exports.SOURCE)
    end
end
--- The rune mode refused this frame (a safety gate, no power target): the floor must not apply.
function ____exports.Yield(bot)
    Intent.Release(bot, ____exports.SOURCE, BotMode.Rune)
end
function ____exports.RegisterProbes()
    LaneHooks.SetRotationProbe(function(bot) return ____exports.Active(bot) ~= nil end)
end
____exports.RegisterProbes()
return ____exports
