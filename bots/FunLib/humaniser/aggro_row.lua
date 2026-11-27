--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__StringAccess(self, index)
    if index >= 0 and index < #self then
        return string.sub(self, index + 1, index + 1)
    end
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
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local AggroOffer = require(GetScriptDirectory().."/FunLib/humaniser/aggro_offer")
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {
    OrderGap = 0.1,
    OrderCap = 0.3,
    Switch = 1,
    Backstop = 3.5,
    Tolerance = 50,
    WalkSlack = 0.5,
    Rest = 0.5,
    Closed = 150,
    Touch = 200
}
--- The task's host: the decider's (farm).
local HOST = BotMode.Farm
--- The modes a draw may start from: a hero laning, farming or idle (judgement: any other is a higher rule's, as the rune detour's).
local FROM = {[BotMode.None] = true, [BotMode.Laning] = true, [BotMode.Farm] = true}
--- pid -> the attempt whose task runs.
local running = {}
--- pid -> the last attempt while it can resume (an order went, the task was replaced or preempted).
local memo = {}
local endedAt = {}
--- pid -> what `wants` decided this round, for `begin`: a fresh start's read, or the attempt to resume.
local pending = {}
function ____exports.ResetCache()
    for ____, t in ipairs({running, memo, endedAt, pending}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end
function ____exports.On(bot)
    return AggroOffer.RowOn() and AggroOffer.MayOffer(bot) and not Drill.Held(bot) and LaneConfig.InLaningPhase()
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
local function r1(x)
    return math.floor(x * 10 + 0.5) / 10
end
--- Drawn creeps alive with the hero as their attack target, and of them those on our ranged creep (the hand-over's count).
local function onHero(bot, a)
    local n = 0
    for ____, c in ipairs(a.drawn) do
        if not c:IsNull() and c:IsAlive() and c:GetAttackTarget() == bot then
            n = n + 1
        end
    end
    return n
end
local function onRanged(a)
    if a.ranged:IsNull() or not a.ranged:IsAlive() then
        return 0
    end
    local n = 0
    for ____, c in ipairs(a.drawn) do
        if not c:IsNull() and c:IsAlive() and c:GetAttackTarget() == a.ranged then
            n = n + 1
        end
    end
    return n
end
local function jobLine(bot, a, phase, why, extra)
    if extra == nil then
        extra = {}
    end
    local fields = {
        {
            "pid",
            bot:GetPlayerID()
        },
        {"job", "aggro"},
        {"aid", a.aid},
        {"phase", phase},
        {"why", why},
        {"host", HOST},
        {"cid", a.cid}
    }
    for ____, f in ipairs(extra) do
        fields[#fields + 1] = f
    end
    Telemetry.Event("job", fields)
end
--- Whether an open attempt may take the hero back for its walk (s6b's resume).
local function resumable(bot, a, now)
    if a.orderAt == nil or now - a.orderAt >= ____exports.SETTINGS.Backstop or not bot:IsAlive() then
        return false
    end
    if onHero(bot, a) == 0 then
        return false
    end
    return SafeGather.At(
        bot,
        bot:GetLocation(),
        {remember = false}
    ).level ~= "deadly"
end
--- One step's diagnosis reads: whether the hero's attack target is the order's, and each drawn creep's distance to the hero.
local function watch(bot, a)
    local tg = bot:GetAttackTarget()
    if tg ~= nil and tg ~= nil and tg == a.target then
        a.heroOn = true
    end
    local me = bot:GetLocation()
    if a.d0 == nil then
        a.d0 = {}
    end
    if a.dmin == nil then
        a.dmin = {}
    end
    do
        local i = 0
        while i < #a.drawn do
            do
                local __continue26
                repeat
                    local c = a.drawn[i + 1]
                    if c:IsNull() or not c:IsAlive() then
                        __continue26 = true
                        break
                    end
                    local at = c:GetLocation()
                    if at == nil or at == nil then
                        __continue26 = true
                        break
                    end
                    local d = dist(me, at)
                    if a.d0[i + 1] == nil then
                        a.d0[i + 1] = d
                    end
                    if a.dmin[i + 1] == nil or d < a.dmin[i + 1] then
                        a.dmin[i + 1] = d
                    end
                    __continue26 = true
                until true
                if not __continue26 then
                    break
                end
            end
            i = i + 1
        end
    end
end
--- Drawn creeps that closed on the hero by `Closed` or more since the order (they chased it, whatever their attack target read).
local function closed(a)
    local n = 0
    if a.d0 == nil or a.dmin == nil then
        return 0
    end
    do
        local i = 0
        while i < #a.drawn do
            local d0 = a.d0[i + 1]
            local dm = a.dmin[i + 1]
            if d0 ~= nil and dm ~= nil and (d0 - dm >= ____exports.SETTINGS.Closed or dm <= ____exports.SETTINGS.Touch) then
                n = n + 1
            end
            i = i + 1
        end
    end
    return n
end
--- The walk back to the hand-over spot until the draw lets go; the attempt's phase is `back` and its order has gone.
local back = __TS__Generator(function(ctx, bot, a)
    local orderAt = a.orderAt
    while a.took == nil and ctx.now() < orderAt + ____exports.SETTINGS.OrderCap do
        watch(bot, a)
        if bot:GetCurrentActionType() == BOT_ACTION_TYPE_ATTACK then
            a.took = ctx.now() - orderAt
        end
        coroutine.yield()
    end
    while ctx.now() < orderAt + ____exports.SETTINGS.OrderGap do
        watch(bot, a)
        coroutine.yield()
    end
    while true do
        if not bot:IsAlive() then
            return ctx.fail("dead")
        end
        watch(bot, a)
        local t = ctx.now() - orderAt
        local n = onHero(bot, a)
        if n > a.peak then
            a.peak = n
        end
        if t >= ____exports.SETTINGS.Switch and n == 0 then
            a.letAt = t
            return a.peak > 0 and ctx.ok() or ctx.fail("missed", "nodraw")
        end
        if t >= ____exports.SETTINGS.Backstop then
            return ctx.fail("timeout")
        end
        local me = bot:GetLocation()
        if dist(me, a.hand) > ____exports.SETTINGS.Tolerance then
            bot:Action_MoveToLocation(Vector(a.hand.x, a.hand.y, me.z))
        end
        coroutine.yield()
    end
end)
--- A fresh attempt: the soft walk-in, the go rule again, the order (the commit point), then the walk back.
local draw = __TS__Generator(function(ctx, bot, a, spot, walk)
    if dist(
        bot:GetLocation(),
        spot
    ) > ____exports.SETTINGS.Tolerance then
        local me = bot:GetLocation()
        local r = __TS__DelegatedYield(ctx.walkTo(
            Vector(spot.x, spot.y, me.z),
            {tolerance = ____exports.SETTINGS.Tolerance, timeout = walk + ____exports.SETTINGS.WalkSlack}
        ))
        if not r.success then
            return r
        end
    end
    local s = AggroOffer.ReadNow(bot)
    if s == nil then
        return ctx.fail("cancelled", "noclash")
    end
    if #s.fails > 0 then
        return ctx.fail("cancelled", s.fails[1])
    end
    if s.target == nil then
        return ctx.fail("cancelled", "unseen")
    end
    if bot:NumQueuedActions() > 0 or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility() then
        return ctx.fail("cancelled", "acting")
    end
    a.target = s.target
    a.drawn = s.drawnUnits
    a.hand = s.hand
    bot:Action_AttackUnit(s.target, true)
    a.orderAt = ctx.now()
    a.phase = "back"
    AggroOffer.NoteHeroHit(bot)
    jobLine(
        bot,
        a,
        "order",
        "go",
        {
            {
                "ot",
                r1(a.orderAt - a.t0)
            },
            {"an", #s.drawnUnits}
        }
    )
    return __TS__DelegatedYield(back(ctx, bot, a))
end)
local function finish(bot, res)
    local pid = bot:GetPlayerID()
    local a = running[pid]
    running[pid] = nil
    endedAt[pid] = DotaTime()
    if a == nil then
        return
    end
    local replaced = res.reason == "cancelled" and res.message == "replaced"
    local cut = replaced and "replaced" or (res.reason == "preempted" and (Decider.LetGo(bot) and "retreat" or HDebug.ModeName(bot:GetActiveMode())) or nil)
    memo[pid] = a.orderAt ~= nil and (replaced or res.reason == "preempted") and a or nil
    jobLine(
        bot,
        a,
        "end",
        res.success and "ok" or res.reason,
        {
            {"msg", res.message},
            {"cut", cut},
            {
                "ot",
                a.orderAt ~= nil and r1(a.orderAt - a.t0) or -1
            },
            {
                "lt",
                a.letAt ~= nil and r1(a.letAt) or (a.orderAt ~= nil and r1(DotaTime() - a.orderAt) or nil)
            },
            {"an", #a.drawn},
            {"ah", a.peak},
            {
                "ar",
                onRanged(a)
            },
            {"rs", a.resumes},
            {"ha", a.orderAt ~= nil and (a.heroOn == true and 1 or 0) or nil},
            {
                "ac",
                a.orderAt ~= nil and closed(a) or nil
            },
            {
                "aw",
                a.orderAt ~= nil and (a.took ~= nil and math.floor(a.took * 100 + 0.5) / 100 or -1) or nil
            },
            {"hp0", a.hp0},
            {
                "hp1",
                math.floor(bot:GetHealth())
            }
        }
    )
end
--- The row's `wants`: an offer while an attempt runs, when an open one should resume, or when a fresh read passes the go rule now.
local function rowWants(bot, _reads)
    local pid = bot:GetPlayerID()
    pending[pid] = nil
    if not ____exports.On(bot) then
        memo[pid] = nil
        return nil
    end
    Tasks.Tick(bot)
    local a = running[pid]
    if a ~= nil then
        return {tgt = "creep:" .. tostring(a.cid)}
    end
    if Tasks.Jobs() == nil then
        return nil
    end
    local now = DotaTime()
    local m = memo[pid]
    if m ~= nil then
        if resumable(bot, m, now) then
            pending[pid] = {resume = m}
            return {
                tgt = "creep:" .. tostring(m.cid),
                by = m.orderAt + ____exports.SETTINGS.Backstop
            }
        end
        memo[pid] = nil
    end
    local ended = endedAt[pid]
    if ended ~= nil and now - ended < ____exports.SETTINGS.Rest then
        return nil
    end
    if Tasks.Running(bot) ~= nil or FROM[bot:GetActiveMode()] ~= true then
        return nil
    end
    local s = AggroOffer.ReadNow(bot)
    if s == nil or #s.fails > 0 or s.target == nil then
        return nil
    end
    pending[pid] = {snap = s}
    return {tgt = "creep:" .. tostring(Telemetry.CreepId(s.ranged))}
end
--- The row's `begin`: starts the attempt `rowWants` decided (a fresh draw, or the walk back of an open one).
local function rowBegin(bot)
    local pid = bot:GetPlayerID()
    local pd = pending[pid]
    pending[pid] = nil
    if pd == nil then
        return false
    end
    local opts = {
        name = "aggro",
        host = HOST,
        preemptAfter = 1,
        stallAfter = 4,
        onEnd = function(r) return finish(bot, r) end
    }
    if pd.resume ~= nil then
        local m = pd.resume
        local ok = Tasks.Start(
            bot,
            opts,
            function(ctx) return back(ctx, bot, m) end
        )
        if not ok then
            return false
        end
        memo[pid] = nil
        m.resumes = m.resumes + 1
        running[pid] = m
        jobLine(
            bot,
            m,
            "resume",
            "drawn",
            {{
                "ah",
                onHero(bot, m)
            }}
        )
        return true
    end
    local s = pd.snap
    local walk = s.f.walk
    local a = {
        aid = 0,
        t0 = DotaTime(),
        cid = Telemetry.CreepId(s.ranged),
        ranged = s.ranged,
        target = s.target,
        drawn = s.drawnUnits,
        hand = s.hand,
        phase = "walk",
        peak = 0,
        resumes = 0,
        hp0 = math.floor(bot:GetHealth())
    }
    local spot = s.spot
    local ok = Tasks.Start(
        bot,
        opts,
        function(ctx) return draw(
            ctx,
            bot,
            a,
            spot,
            walk
        ) end
    )
    if not ok then
        return false
    end
    a.aid = Telemetry.NextAid(pid)
    memo[pid] = nil
    running[pid] = a
    AggroOffer.NoteGo(bot, s.ranged, a.aid)
    jobLine(
        bot,
        a,
        "start",
        "go",
        {
            {
                "tgt",
                "creep:" .. tostring(a.cid)
            },
            {
                "gw",
                r1(walk)
            },
            {"an", s.drawn},
            {"k", s.f.k}
        }
    )
    return true
end
--- The row's verb: one frame of the attempt; true once it has ended.
local function rowStep(bot)
    Tasks.Step(bot, HOST)
    return running[bot:GetPlayerID()] == nil
end
--- Soft while walking in; hard from the order (the commit point).
local function rowSoft(bot)
    local ____opt_0 = running[bot:GetPlayerID()]
    return (____opt_0 and ____opt_0.phase) == "walk"
end
--- The decider's row (registered in index.ts, below the creep row, so the decider imports no row).
____exports.ROW = {
    name = "aggro",
    wants = rowWants,
    begin = rowBegin,
    step = rowStep,
    soft = rowSoft
}
return ____exports
