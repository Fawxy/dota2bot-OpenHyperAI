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
local logSkip, DEFAULTS, settings, holdPoint
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
local PreHit = require(GetScriptDirectory().."/FunLib/humaniser/states/pre_hit")
local IdleSwing = require(GetScriptDirectory().."/FunLib/humaniser/states/idle_swing")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Contest = require(GetScriptDirectory().."/FunLib/humaniser/states/contest")
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
function logSkip(bot, t, price, at)
    Telemetry.Event(
        "contest_skip",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"at", at},
            {"why", price.why},
            {
                "cc",
                math.floor(price.cost * 1000) / 10
            },
            {"n", price.heroes},
            {
                "ex",
                math.floor(price.exposure * 100) / 100
            },
            {
                "walk",
                math.floor(t.walk * 100) / 100
            },
            {
                "dies",
                t.dies == math.huge and -1 or math.floor(t.dies * 100) / 100
            },
            {
                "hf",
                math.floor(bot:GetHealth() / math.max(
                    bot:GetMaxHealth(),
                    1
                ) * 100) / 100
            }
        }
    )
end
____exports.NAME = "laning"
--- Beyond this the body reports `walk`, within `NEAR` it reports `hold` (with hysteresis between them).
local NEAR = 600
local FAR = 1200
--- A last-hit attempt is dropped when it would take the bot this far from its spot.
local LEASH = 900
DEFAULTS = {Spot = "oha", LastHit = {}, LastHitWithin = 1}
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
--- lane_aggro's fed creep per bot (the lane_spot input `fed`), set while its feed watch runs.
local fedCreep = {}
--- lane_aggro: the creep this bot fed their wave onto, or undefined when its watch ends.
function ____exports.SetFed(bot, creep)
    fedCreep[bot:GetPlayerID()] = creep
end
function ____exports.ClearFed()
    for k in pairs(fedCreep) do
        fedCreep[k] = nil
    end
    for k in pairs(holdPoint) do
        holdPoint[k] = nil
    end
end
--- wave_hold's hold point per bot (the lane_spot input `hold`), set while a hold runs.
holdPoint = {}
--- wave_hold: the point this bot holds their wave at, or undefined when the hold ends.
function ____exports.SetHold(bot, at)
    holdPoint[bot:GetPlayerID()] = at
end
--- Ours.LaneSpot: this bot stands on our spot whatever States.Laning.Spot says: cores under Ours.CoreLastHit, and since slice
-- support-spot supports whose lane hits and harass are ours (Ours.SupportHarass; their attacks on heroes run in our attack
-- mode, so the body's hold no longer cancels them).
function ____exports.OwnsSpot(bot)
    if not Ours.On("LaneSpot") then
        return false
    end
    return CoreLastHit.Applies(bot) or ____exports.OwnsSupportHits(bot) and SupportDeny.Harass(bot)
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
            ____exports.RoleOf(bot),
            fedCreep[pid],
            holdPoint[pid]
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
--- The creeps this laner may take: for a core all but a deny an allied support is attempting (LaneClaims.CoreMine; all with
-- Ours.CoreDenyYield off), the support's claims otherwise.
local function claimsFor(bot)
    if ____exports.OwnsLastHit(bot) then
        return LaneClaims.CoreMine(bot)
    end
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
    if at == nil then
        return
    end
    seen[pid] = {
        creep = creep,
        x = at.x,
        y = at.y,
        t = DotaTime()
    }
end
local function placeOf(pid, creep)
    local ____this_13
    ____this_13 = creep
    local ____opt_12 = ____this_13.IsNull
    local ____temp_14 = ____opt_12 and ____opt_12(____this_13)
    if ____temp_14 == nil then
        ____temp_14 = false
    end
    local at = not ____temp_14 and creep:IsAlive() and creep:GetLocation() or nil
    if at ~= nil then
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
--- The idle swing the body last picked, per bot, so its phase label and attempt line name it (states/idle_swing).
local idlePicks = {}
--- The price of each creep the pick last asked `far` about, per bot, so a chosen walk-in starts with the price it was chosen on.
local farPrices = {}
--- Ours.CoreContest: a melee core may walk past MAX_WALK to a last hit whose walk-in price passes (states/contest).
local function farFor(bot)
    if not Contest.Applies(bot) then
        return nil
    end
    local pid = bot:GetPlayerID()
    local asked = {}
    farPrices[pid] = asked
    return function(t)
        if t.walk > Contest.CONTEST_WALK or Contest.Refused(pid, t.creep) then
            return false
        end
        local price = Contest.PriceFor(bot, t)
        asked[#asked + 1] = {creep = t.creep, price = price}
        if not price.ok and Contest.NoteSkip(pid, t.creep, price.why) then
            logSkip(bot, t, price, "pick")
        end
        return price.ok
    end
end
local function choose(bot, targets, current, pre)
    local pid = bot:GetPlayerID()
    local claims = claimsFor(bot)
    local far = farFor(bot)
    local ____temp_15
    if far == nil then
        ____temp_15 = claims
    else
        ____temp_15 = function(t) return not Contest.Refused(pid, t.creep) and (claims == nil or claims(t)) end
    end
    local mine = ____temp_15
    local idle
    local chosen = LanePick.Choose(
        targets,
        current,
        mine,
        pre,
        function()
            local verbs = Tasks.Verbs()
            local ____temp_16
            if verbs ~= nil then
                ____temp_16 = IdleSwing.Find(bot, verbs, mine)
            else
                ____temp_16 = nil
            end
            idle = ____temp_16
            return idle
        end,
        far
    )
    idlePicks[pid] = idle ~= nil and chosen == idle and idle or nil
    return chosen
end
--- A walk-in starts when the pick chose a last hit beyond MAX_WALK; while it runs its price is read again every scan, and a
-- price that no longer passes (a second hero came, HP fell) refuses the creep, which releases the attempt through laneFarm's
-- dropLost. Any other undefined pick keeps the wait, as for every core attempt.
local function contestPick(bot, chosen, current)
    local pid = bot:GetPlayerID()
    if current ~= nil and Contest.Running(pid, current.creep) ~= nil and (chosen == nil or chosen.creep == current.creep) then
        local price = Contest.PriceFor(bot, current)
        if not price.ok then
            Contest.Refuse(pid, current.creep)
            if Contest.NoteSkip(pid, current.creep, price.why) then
                logSkip(bot, current, price, "walk")
            end
            return nil
        end
    end
    if chosen ~= nil and chosen.kind == "lasthit" and chosen.walk > LanePick.MAX_WALK and Contest.Running(pid, chosen.creep) == nil then
        for ____, fp in ipairs(farPrices[pid] or ({})) do
            if fp.creep == chosen.creep then
                Contest.Start(
                    pid,
                    chosen.creep,
                    fp.price,
                    bot:GetHealth(),
                    DotaTime()
                )
            end
        end
    end
    return chosen
end
--- A core's last yield (Ours.CoreDenyYield) not yet reported, for its ev=lh `yd`: the support it left a deny to, and when. The
-- next attempt reported carries it if it ends within YIELD_REPORT_SECS of the yield; in smoke game deny-yield_fn1 most yields
-- came with nothing else on offer, so the yield and the next attempt are often seconds apart (ev=snap's `yc` counts every
-- yield). An older yield is dropped unreported (review 2026-11-06-deny-yield-0ee970a F2: a stale yd on a later last hit).
local yields = {}
local YIELD_REPORT_SECS = 6
--- After a core's pick: whether the pick without the yield was a deny an allied support is attempting, so the core yielded it.
local function noteYield(bot, targets, current, pre, chosen)
    if not ____exports.OwnsLastHit(bot) or LaneClaims.CoreMine(bot) == nil then
        return
    end
    local plain = LanePick.Choose(targets, current, nil, pre)
    if plain == nil or plain.kind ~= "deny" or chosen ~= nil and chosen.creep == plain.creep then
        return
    end
    local sup = LaneClaims.DenyYield(bot, plain)
    if sup == nil then
        return
    end
    local pid = bot:GetPlayerID()
    LanePick.NoteYield(pid, plain.creep)
    yields[pid] = {
        sup = sup,
        t = DotaTime()
    }
end
local function yieldOf(pid)
    local y = yields[pid]
    yields[pid] = nil
    return y ~= nil and DotaTime() - y.t <= YIELD_REPORT_SECS and y.sup or nil
end
--- The creeps this bot pre-hit (states/pre_hit), newest last, so the ev=lh of a later attempt on one says `ph=1` (last hits per
-- pre-hit). A creep handle stays the same unit until it dies.
local preHits = {}
local PRE_HITS_KEPT = 4
local function notePreHit(pid, creep)
    local list = preHits[pid]
    if list == nil then
        list = {}
        preHits[pid] = list
    end
    list[#list + 1] = creep
    if #list > PRE_HITS_KEPT then
        table.remove(list, 1)
    end
end
local function wasPreHit(pid, creep)
    for ____, c in ipairs(preHits[pid] or ({})) do
        if c == creep then
            return true
        end
    end
    return false
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
                local verbs = Tasks.Verbs()
                local ____temp_17
                if verbs ~= nil then
                    ____temp_17 = PreHit.Find(bot, verbs)
                else
                    ____temp_17 = nil
                end
                local pre = ____temp_17
                local chosen = contestPick(
                    bot,
                    choose(bot, targets, current, pre),
                    current
                )
                noteYield(
                    bot,
                    targets,
                    current,
                    pre,
                    chosen
                )
                if chosen ~= nil then
                    noteSeen(
                        bot:GetPlayerID(),
                        chosen.creep
                    )
                end
                if chosen == nil and #targets == 0 then
                    return nil
                end
                if current == nil or chosen == nil or chosen.creep ~= current.creep or chosen.kind ~= current.kind then
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
                local ip = idlePicks[bot:GetPlayerID()]
                if l == "prehit" and ip ~= nil then
                    local ____opt_18 = IdleSwing.Of(
                        bot:GetPlayerID(),
                        ip.creep
                    )
                    l = ____opt_18 and ____opt_18.kind or l
                end
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
            dropLost = function(cur) return ____exports.OwnsSupportHits(bot) or Contest.Refused(
                bot:GetPlayerID(),
                cur.creep
            ) end,
            radius = Contest.Applies(bot) and Contest.RADIUS or nil,
            onAttempt = function(t, res, contested)
                local ol, od, ow = LanePick.AttemptOffers(bot:GetPlayerID())
                local ____temp_20
                if t.kind == "prehit" then
                    ____temp_20 = IdleSwing.Of(
                        bot:GetPlayerID(),
                        t.creep
                    )
                else
                    ____temp_20 = nil
                end
                local idle = ____temp_20
                if idle ~= nil then
                    local prior = idle.kind ~= "shove" and (IdleSwing.SpentOn(
                        bot:GetPlayerID(),
                        t.creep
                    ) or 0) or nil
                    if res.success and idle.kind ~= "shove" then
                        IdleSwing.NoteSwing(
                            bot:GetPlayerID(),
                            t.creep
                        )
                    end
                    local ____Telemetry_Event_27 = Telemetry.Event
                    local ____array_26 = __TS__SparseArrayNew(
                        {
                            "pid",
                            bot:GetPlayerID()
                        },
                        {"kind", idle.kind},
                        {"n", prior},
                        {
                            "cx",
                            math.floor(idle.x)
                        },
                        {
                            "cy",
                            math.floor(idle.y)
                        },
                        {"mode", idle.mode},
                        {"result", res.success and "ok" or "fail"},
                        {"reason", res.reason},
                        {"ranged", t.ranged},
                        {
                            "walk",
                            math.floor(t.walk * 100) / 100
                        },
                        {
                            "hp",
                            math.floor(idle.hp)
                        },
                        {
                            "hf",
                            math.floor(idle.hf * 100) / 100
                        }
                    )
                    local ____temp_21
                    if idle.kill == nil or idle.kill == math.huge then
                        ____temp_21 = nil
                    else
                        ____temp_21 = math.floor(idle.kill * 100) / 100
                    end
                    __TS__SparseArrayPush(____array_26, {"kill", ____temp_21})
                    local ____temp_22
                    if idle.reach == nil then
                        ____temp_22 = nil
                    else
                        ____temp_22 = idle.reach == math.huge and -1 or math.floor(idle.reach * 100) / 100
                    end
                    __TS__SparseArrayPush(____array_26, {"reach", ____temp_22})
                    local ____temp_23
                    if idle.focus == true then
                        ____temp_23 = true
                    else
                        ____temp_23 = nil
                    end
                    __TS__SparseArrayPush(
                        ____array_26,
                        {"focus", ____temp_23},
                        {"hits", idle.hits},
                        {
                            "cid",
                            Telemetry.CreepId(t.creep)
                        }
                    )
                    local ____temp_24
                    if IdleSwing.Count(bot, "GetDenies") > idle.denies then
                        ____temp_24 = true
                    else
                        ____temp_24 = nil
                    end
                    __TS__SparseArrayPush(____array_26, {"dn", ____temp_24})
                    local ____temp_25
                    if IdleSwing.Count(bot, "GetLastHits") > idle.lastHits then
                        ____temp_25 = true
                    else
                        ____temp_25 = nil
                    end
                    __TS__SparseArrayPush(____array_26, {"lh", ____temp_25}, {"contested", contested}, {"msg", res.message})
                    ____Telemetry_Event_27(
                        "idle_swing",
                        {__TS__SparseArraySpread(____array_26)}
                    )
                    IdleSwing.Clear(bot:GetPlayerID())
                    return
                end
                if t.kind == "prehit" then
                    local n = PreHit.NoteOf(
                        bot:GetPlayerID(),
                        t.creep
                    )
                    if res.success then
                        notePreHit(
                            bot:GetPlayerID(),
                            t.creep
                        )
                    end
                    Telemetry.Event(
                        "prehit",
                        {
                            {
                                "pid",
                                bot:GetPlayerID()
                            },
                            {"result", res.success and "ok" or "fail"},
                            {"reason", res.reason},
                            {"ranged", t.ranged},
                            {
                                "walk",
                                math.floor(t.walk * 100) / 100
                            },
                            {
                                "dies",
                                t.dies == math.huge and -1 or math.floor(t.dies * 100) / 100
                            },
                            {
                                "hp",
                                (n and n.hp) ~= nil and math.floor(n.hp) or nil
                            },
                            {
                                "t0",
                                (n and n.t0) ~= nil and math.floor(n.t0 * 100) / 100 or nil
                            },
                            {
                                "lo",
                                (n and n.lo) ~= nil and math.floor(n.lo) or nil
                            },
                            {"np", (n and n.plan) ~= nil and #n.plan.swings - 1 or nil},
                            {
                                "tk",
                                (n and n.plan) ~= nil and math.floor(n.plan.swings[#n.plan.swings] * 100) / 100 or nil
                            },
                            {
                                "hk",
                                (n and n.plan) ~= nil and math.floor(n.plan.hpKill) or nil
                            },
                            {
                                "mg",
                                (n and n.plan) ~= nil and math.floor(n.plan.margin) or nil
                            },
                            {"ol", ol},
                            {"contested", contested}
                        }
                    )
                    return
                end
                local ____OwnsSupportHits_result_42
                if ____exports.OwnsSupportHits(bot) then
                    ____OwnsSupportHits_result_42 = claimOf(
                        bot:GetPlayerID(),
                        t.creep
                    )
                else
                    ____OwnsSupportHits_result_42 = nil
                end
                local claim = ____OwnsSupportHits_result_42
                local cx, cy, ca = unpack(placeOf(
                    bot:GetPlayerID(),
                    t.creep
                ))
                local walkIn = Contest.Finish(
                    bot:GetPlayerID(),
                    t.creep
                )
                local maxHp = math.max(
                    bot:GetMaxHealth(),
                    1
                )
                local ____Telemetry_Event_49 = Telemetry.Event
                local ____array_48 = __TS__SparseArrayNew(
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
                    {"ca", ca}
                )
                local ____temp_43
                if t.kind == "lasthit" and wasPreHit(
                    bot:GetPlayerID(),
                    t.creep
                ) then
                    ____temp_43 = true
                else
                    ____temp_43 = nil
                end
                __TS__SparseArrayPush(____array_48, {"ph", ____temp_43})
                local ____temp_44
                if t.kind == "deny" then
                    ____temp_44 = IdleSwing.SpentOn(
                        bot:GetPlayerID(),
                        t.creep
                    )
                else
                    ____temp_44 = nil
                end
                __TS__SparseArrayPush(
                    ____array_48,
                    {"pre", ____temp_44},
                    {
                        "yd",
                        yieldOf(bot:GetPlayerID())
                    }
                )
                local ____temp_45
                if walkIn ~= nil then
                    ____temp_45 = true
                else
                    ____temp_45 = nil
                end
                __TS__SparseArrayPush(
                    ____array_48,
                    {"cw", ____temp_45},
                    {
                        "cc",
                        walkIn ~= nil and math.floor(walkIn.price.cost * 1000) / 10 or nil
                    },
                    {"cn", walkIn and walkIn.price.heroes},
                    {
                        "dh",
                        walkIn ~= nil and math.floor((walkIn.hp - bot:GetHealth()) / maxHp * 1000) / 10 or nil
                    },
                    {"msg", res.message}
                )
                ____Telemetry_Event_49(
                    "lh",
                    {__TS__SparseArraySpread(____array_48)}
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
