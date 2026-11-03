--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringAccess(self, index)
    if index >= 0 and index < #self then
        return string.sub(self, index + 1, index + 1)
    end
end

local __TS__Symbol, Symbol
do
    local symbolMetatable = {__tostring = function(self)
        return ("Symbol(" .. (self.description or "")) .. ")"
    end}
    function __TS__Symbol(description)
        return setmetatable({description = description}, symbolMetatable)
    end
    Symbol = {
        asyncDispose = __TS__Symbol("Symbol.asyncDispose"),
        dispose = __TS__Symbol("Symbol.dispose"),
        iterator = __TS__Symbol("Symbol.iterator"),
        hasInstance = __TS__Symbol("Symbol.hasInstance"),
        species = __TS__Symbol("Symbol.species"),
        toStringTag = __TS__Symbol("Symbol.toStringTag")
    }
end

local function __TS__DelegatedYield(iterable)
    if type(iterable) == "string" then
        for index = 0, #iterable - 1 do
            coroutine.yield(__TS__StringAccess(iterable, index))
        end
    elseif iterable.____coroutine ~= nil then
        local co = iterable.____coroutine
        while true do
            local status, value = coroutine.resume(co)
            if not status then
                error(value, 0)
            end
            if coroutine.status(co) == "dead" then
                return value
            else
                coroutine.yield(value)
            end
        end
    elseif iterable[Symbol.iterator] then
        local iterator = iterable[Symbol.iterator](iterable)
        while true do
            local result = iterator:next()
            if result.done then
                return result.value
            else
                coroutine.yield(result.value)
            end
        end
    else
        for ____, value in ipairs(iterable) do
            coroutine.yield(value)
        end
    end
end

local function __TS__CountVarargs(...)
    return select("#", ...)
end

local __TS__Unpack = table.unpack or unpack

local __TS__Generator
do
    local function generatorIterator(self)
        return self
    end
    local function generatorNext(self, ...)
        local co = self.____coroutine
        if coroutine.status(co) == "dead" then
            return {done = true}
        end
        local status, value = coroutine.resume(co, ...)
        if not status then
            error(value, 0)
        end
        return {
            value = value,
            done = coroutine.status(co) == "dead"
        }
    end
    function __TS__Generator(fn)
        return function(...)
            local args = {...}
            local argsLength = __TS__CountVarargs(...)
            return {
                ____coroutine = coroutine.create(function() return fn(__TS__Unpack(args, 1, argsLength)) end),
                [Symbol.iterator] = generatorIterator,
                next = generatorNext
            }
        end
    end
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local LaneSpot = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_spot")
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
local CoreLastHit = require(GetScriptDirectory().."/FunLib/humaniser/states/core_last_hit")
local SupportDeny = require(GetScriptDirectory().."/FunLib/humaniser/states/support_deny")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local LaneClaims = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_claims")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
____exports.NAME = "laning"
--- Beyond this the body reports `walk`, within `NEAR` it reports `hold` (with hysteresis between them).
local NEAR = 600
local FAR = 1200
--- A last-hit attempt is dropped when it would take the bot this far from its spot.
local LEASH = 900
local DEFAULTS = {Spot = "oha", LastHit = {}, LastHitWithin = 1}
local settings
--- Read once: Customize is fixed for the game (tests reload the module with each config).
function ____exports.Settings()
    if settings ~= nil then
        return settings
    end
    local ____opt_0 = Config.Get().States
    if ____opt_0 ~= nil then
        ____opt_0 = ____opt_0.Laning
    end
    local s = ____opt_0
    settings = {Spot = s and s.Spot or DEFAULTS.Spot, LastHit = s and s.LastHit or DEFAULTS.LastHit, LastHitWithin = s and s.LastHitWithin or DEFAULTS.LastHitWithin}
    return settings
end
local spots = {}
function ____exports.SetSpot(bot, fn)
    spots[bot:GetPlayerID()] = fn
end
local function ohaSpot(bot)
    local fn = spots[bot:GetPlayerID()]
    if fn == nil then
        return nil
    end
    local ok, v = pcall(fn)
    local ____ok_8
    if ok then
        ____ok_8 = v
    else
        ____ok_8 = nil
    end
    return ____ok_8
end
function ____exports.RoleOf(bot)
    local pos = LaneConfig.PositionOf(bot)
    return pos ~= nil and pos >= 4 and "support" or "core"
end
local spotCache = {}
--- Ours.LaneSpot: this bot stands on our spot whatever States.Laning.Spot says (cores under Ours.CoreLastHit).
function ____exports.OwnsSpot(bot)
    return Ours.On("LaneSpot") and CoreLastHit.Applies(bot)
end
--- The spot the body holds this frame (cached per frame: holdAt and its exits read it several times). OHA's spot only when
-- ours is not on for the bot or cannot be computed (no lane direction, an error).
function ____exports.Spot(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local c = spotCache[pid]
    if c ~= nil and c.t == now then
        return c.v
    end
    local v
    local info
    if ____exports.Settings().Spot == "sdk" or ____exports.OwnsSpot(bot) then
        local ok, res = pcall(
            LaneSpot.Compute,
            bot,
            ____exports.RoleOf(bot)
        )
        if ok and res ~= nil then
            info = res
            v = res.spot
        end
    end
    if v == nil then
        v = ohaSpot(bot)
    end
    spotCache[pid] = {t = now, v = v, info = info}
    return v
end
--- The last computed SDK spot details for telemetry, if any.
function ____exports.SpotInfo(bot)
    local ____opt_9 = spotCache[bot:GetPlayerID()]
    return ____opt_9 and ____opt_9.info
end
--- Whether the body takes this bot's last hits and denies (read every frame by mode_laning_generic.lua).
function ____exports.OwnsLastHit(bot)
    if CoreLastHit.Applies(bot) then
        return true
    end
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil then
        return false
    end
    for ____, p in ipairs(____exports.Settings().LastHit) do
        if p == pos then
            return true
        end
    end
    return false
end
--- Whether the body takes this support's lane hits (Ours.SupportDeny): its denies, and with Ours.SupportLastHit the last hits
-- no core will take (states/lane_claims). Stepped only by its support_lane step, so OHA's positioning and harass keep the
-- other frames.
function ____exports.OwnsSupportHits(bot)
    return not ____exports.OwnsLastHit(bot) and SupportDeny.Applies(bot)
end
--- The creeps this laner may take: undefined for a core (all), the support's claims otherwise.
local function claimsFor(bot)
    if not ____exports.OwnsSupportHits(bot) then
        return nil
    end
    local lastHits = SupportDeny.LastHits(bot)
    local within = ____exports.Settings().LastHitWithin
    return function(t)
        local ____temp_11
        if t.kind == "deny" then
            ____temp_11 = true
        else
            ____temp_11 = lastHits and LaneClaims.SupportClaim(bot, t, within) ~= nil
        end
        return ____temp_11
    end
end
--- The claims on each support's last few picks, for its ev=lh (`claim`): a retarget picks the next creep before the attempt it
-- replaces reports, so the claim is looked up by creep.
local claims = {}
local CLAIMS_KEPT = 4
local function noteClaim(pid, creep, claim)
    local list = claims[pid]
    if list == nil then
        list = {}
        claims[pid] = list
    end
    list[#list + 1] = {creep = creep, claim = claim}
    if #list > CLAIMS_KEPT then
        table.remove(list, 1)
    end
end
local function claimOf(pid, creep)
    local list = claims[pid]
    if list == nil then
        return nil
    end
    do
        local i = #list - 1
        while i >= 0 do
            if list[i + 1].creep == creep then
                return list[i + 1].claim
            end
            i = i - 1
        end
    end
    return nil
end
--- Where each bot's attempt creep was last seen alive, for its ev=lh (`cx`, `cy`, `ca`): a creep that died ends the attempt,
-- and a dead creep's handle no longer answers, so the end reads the place from the last scan that offered it.
local seen = {}
local function noteSeen(pid, creep)
    local at = creep:GetLocation()
    seen[pid] = {
        creep = creep,
        x = at.x,
        y = at.y,
        t = DotaTime()
    }
end
local function placeOf(pid, creep)
    if creep:IsAlive() then
        local at = creep:GetLocation()
        return {
            math.floor(at.x),
            math.floor(at.y),
            0
        }
    end
    local s = seen[pid]
    if s == nil or s.creep ~= creep then
        return {nil, nil, nil}
    end
    return {
        math.floor(s.x),
        math.floor(s.y),
        math.floor((DotaTime() - s.t) * 100) / 100
    }
end
local function choose(bot, targets, current)
    return LanePick.Choose(
        targets,
        current,
        claimsFor(bot)
    )
end
--- A lane hit the support's body would go for now: what its own scan would pick (same laneTargets query and claims), within
-- the leash of the spot. support_lane reads it to step the body ahead of OHA's own laning steps.
function ____exports.HitOffered(bot)
    if not ____exports.OwnsSupportHits(bot) then
        return false
    end
    local spot = ____exports.Spot(bot)
    if spot ~= nil and GetUnitToLocationDistance(bot, spot) > LEASH then
        return false
    end
    local verbs = Tasks.Verbs()
    if verbs == nil then
        return false
    end
    return choose(
        bot,
        verbs.laneTargets(
            bot,
            {within = ____exports.Settings().LastHitWithin}
        )
    ) ~= nil
end
local body = __TS__Generator(function(bot, ctx)
    local sdk = ____exports.Settings().Spot == "sdk" or ____exports.OwnsSpot(bot)
    local tight = ____exports.OwnsSpot(bot)
    local hold = sdk and ({
        tolerance = 40,
        repath = 1.05,
        jitter = 0.85,
        scatter = tight and 40 or 130,
        step = tight and ({30, 60}) or ({50, 150}),
        follow = tight and 50 or 150,
        hold = "state:laning"
    }) or ({
        tolerance = 100,
        repath = 1,
        jitter = 0.3,
        scatter = 50,
        hold = "state:laning"
    })
    return __TS__DelegatedYield(ctx.laneFarm(
        function() return ____exports.Spot(bot) end,
        {
            hold = hold,
            lastHits = function()
                local spot = ____exports.Spot(bot)
                LanePick.NoteScan(
                    bot:GetPlayerID(),
                    DotaTime(),
                    spot ~= nil and GetUnitToLocationDistance(bot, spot) or nil
                )
                local owns = ____exports.OwnsLastHit(bot) or ____exports.OwnsSupportHits(bot)
                if owns then
                    LanePick.NoteWait(bot)
                end
                return owns
            end,
            within = ____exports.Settings().LastHitWithin,
            pick = function(targets, current)
                local chosen = choose(bot, targets, current)
                if chosen ~= nil then
                    noteSeen(
                        bot:GetPlayerID(),
                        chosen.creep
                    )
                end
                if current == nil or chosen == nil or chosen.creep ~= current.creep then
                    LanePick.NotePick(
                        bot:GetPlayerID(),
                        DotaTime(),
                        targets,
                        chosen
                    )
                    if chosen ~= nil and ____exports.OwnsSupportHits(bot) then
                        noteClaim(
                            bot:GetPlayerID(),
                            chosen.creep,
                            LaneClaims.SupportClaim(
                                bot,
                                chosen,
                                ____exports.Settings().LastHitWithin
                            )
                        )
                    end
                end
                return chosen
            end,
            label = function(l)
                ctx.label(l)
                LanePick.NotePhase(
                    bot:GetPlayerID(),
                    l
                )
            end,
            near = NEAR,
            far = FAR,
            leash = LEASH,
            retarget = true,
            dropLost = ____exports.OwnsSupportHits(bot),
            onAttempt = function(t, res, contested)
                local ol, od, ow = LanePick.AttemptOffers(bot:GetPlayerID())
                local ____OwnsSupportHits_result_12
                if ____exports.OwnsSupportHits(bot) then
                    ____OwnsSupportHits_result_12 = claimOf(
                        bot:GetPlayerID(),
                        t.creep
                    )
                else
                    ____OwnsSupportHits_result_12 = nil
                end
                local claim = ____OwnsSupportHits_result_12
                local cx, cy, ca = unpack(placeOf(
                    bot:GetPlayerID(),
                    t.creep
                ))
                Telemetry.Event(
                    "lh",
                    {
                        {
                            "pid",
                            bot:GetPlayerID()
                        },
                        {"kind", t.kind},
                        {"result", res.success and "ok" or "fail"},
                        {"reason", res.reason},
                        {"ranged", t.ranged},
                        {
                            "eta",
                            math.floor(t.eta * 100) / 100
                        },
                        {"contested", contested},
                        {"ol", ol},
                        {"od", od},
                        {"ow", ow},
                        {
                            "walk",
                            math.floor(t.walk * 100) / 100
                        },
                        {
                            "dies",
                            t.dies == math.huge and -1 or math.floor(t.dies * 100) / 100
                        },
                        {"claim", claim},
                        {"cx", cx},
                        {"cy", cy},
                        {"ca", ca},
                        {"msg", res.message}
                    }
                )
            end
        }
    ))
end)
function ____exports.Spec(bot)
    return {
        name = ____exports.NAME,
        kind = "posture",
        host = BotMode.Laning,
        floor = 0,
        preemptAfter = 3,
        score = function() return Phase.IsLaningFor(bot) and 0.5 or nil end,
        body = function(ctx) return body(bot, ctx) end
    }
end
return ____exports
