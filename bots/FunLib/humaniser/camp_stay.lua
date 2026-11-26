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
local r1, lifeField, choiceLine
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local DamageType = ____dota.DamageType
local CampRead = require(GetScriptDirectory().."/FunLib/humaniser/camp_read")
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function r1(x)
    return math.floor(x * 10 + 0.5) / 10
end
function lifeField(life)
    return life == math.huge and -1 or r1(life)
end
function choiceLine(bot, p, go, why, src, aid)
    Telemetry.Event(
        "choice",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "stay"},
            {"aid", aid},
            {"go", go and 1 or 0},
            {"want", p.want and 1 or 0},
            {"why", why},
            {"src", src},
            {
                "lane",
                bot:GetAssignedLane()
            },
            {
                "slot",
                r1(p.slot)
            },
            {"camp", p.camp},
            {"nc", p.nc},
            {"nn", p.nn},
            {
                "walk",
                r1(p.walk)
            },
            {
                "lf",
                lifeField(p.life)
            }
        }
    )
end
____exports.SETTINGS = {
    HpBar = 0.25,
    Within = 1,
    WaitSlack = 0.5,
    BehindShort = 250,
    BehindMin = 150,
    BehindMax = 400,
    Arrive = 60,
    AtSpot = 200,
    Reorder = 0.5,
    Max = 35,
    OutMargin = 150,
    OutFor = 4,
    DangerEvery = 0.5
}
--- The task's host: the decider's (farm).
local HOST = BotMode.Farm
local opps = {}
local running = {}
--- pid -> the read `wants` decided to start on this round, for `begin`.
local pending = {}
function ____exports.ResetCache()
    for ____, t in ipairs({opps, running, pending}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end
function ____exports.On()
    return Ours.On("CampStay")
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
local function centre(list)
    local x = 0
    local y = 0
    local z = 0
    for ____, u in ipairs(list) do
        local l = u:GetLocation()
        x = x + l.x
        y = y + l.y
        z = z + (l.z or 0)
    end
    return Vector(x / #list, y / #list, z / #list)
end
--- The stand's distance behind our creeps' centre for this hero (SETTINGS BehindShort, BehindMin, BehindMax).
function ____exports.BehindBack(bot)
    return math.min(
        ____exports.SETTINGS.BehindMax,
        math.max(
            ____exports.SETTINGS.BehindMin,
            bot:GetAttackRange() - ____exports.SETTINGS.BehindShort
        )
    )
end
--- The stand spot (the old stay's behindPoint): past our creeps' centre on the far side from the neutrals' centre, `BehindBack` from
-- it. Undefined with none of ours; with the two centres on one point, away through where the hero stands.
function ____exports.StandSpot(bot, ours, neutrals, origin)
    if #ours == 0 then
        return nil
    end
    local oc = centre(ours)
    local nc = #neutrals > 0 and centre(neutrals) or origin
    local dx = oc.x - nc.x
    local dy = oc.y - nc.y
    local l = math.sqrt(dx * dx + dy * dy)
    if l < 1 then
        local at = bot:GetLocation()
        dx = at.x - oc.x
        dy = at.y - oc.y
        l = math.sqrt(dx * dx + dy * dy)
        if l < 1 then
            return oc
        end
    end
    local d = ____exports.BehindBack(bot)
    return Vector(oc.x + dx / l * d, oc.y + dy / l * d, oc.z)
end
local function hpShare(bot)
    return bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    )
end
--- OHA's own action holds the hero (the pull's and the creep row's check: a queued order, a cast or channel).
local function acting(bot)
    return bot:NumQueuedActions() > 0 or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility()
end
local function onHero(bot, f)
    for ____, n in ipairs(f.neutrals) do
        if n:GetAttackTarget() == bot then
            return true
        end
    end
    return false
end
--- The fight read for `bot`: opens, updates or closes its opportunity. Returns the read while the opportunity is open, else
-- undefined. A closing opportunity whose line has not gone out writes it with `src`.
local function observe(bot, read, src)
    local pid = bot:GetPlayerID()
    local sp = read.SpawnerFor(bot)
    local f = sp ~= nil and bot:IsAlive() and read.FightOf(sp) or nil
    local open = sp ~= nil and f ~= nil and #f.ours > 0 and #f.neutrals > 0
    local p = opps[pid]
    if p ~= nil and (not open or p.camp ~= sp.idx) then
        if p.logged ~= true then
            choiceLine(
                bot,
                p,
                false,
                src == "shadow" and "off" or (p.why or "idle"),
                src
            )
        end
        opps[pid] = nil
        p = nil
    end
    if not open then
        return nil
    end
    local stand = ____exports.StandSpot(bot, f.ours, f.neutrals, sp.location)
    local walk = dist(
        bot:GetLocation(),
        stand
    ) / math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    if p == nil then
        p = {
            slot = DotaTime(),
            camp = sp.idx,
            want = false,
            nc = 0,
            nn = 0,
            walk = walk,
            life = f.life
        }
        opps[pid] = p
    end
    p.nc = math.max(p.nc, #f.ours)
    p.nn = math.max(p.nn, #f.neutrals)
    p.walk = walk
    p.life = f.life
    return {sp = sp, f = f, stand = stand, walk = walk}
end
--- Worth starting and still possible (rule 5), the same in both arms: undefined when wanted, else why not.
local function worth(bot, r)
    if not r.f.engaged then
        return "idle"
    end
    if hpShare(bot) < ____exports.SETTINGS.HpBar then
        return "hp"
    end
    if r.walk >= r.f.life then
        return "far"
    end
    return nil
end
--- What holds a wanted stay back now, else undefined.
local function block(bot, p, r)
    if p.barred ~= nil then
        return p.barred
    end
    if p.first ~= nil and DotaTime() >= p.first + ____exports.SETTINGS.Max then
        return "timeout"
    end
    local mode = bot:GetActiveMode()
    if mode == BotMode.Attack or mode == BotMode.Retreat then
        return "busy"
    end
    if Tasks.Running(bot) ~= nil then
        return "row"
    end
    if acting(bot) then
        return "acting"
    end
    if onHero(bot, r.f) then
        return "aggro"
    end
    if SafeGather.At(bot, r.stand, {who = "stay"}).level == "deadly" then
        return "danger"
    end
    return nil
end
local function jobLine(bot, st, phase, why, cut)
    local ____end = phase == "end"
    local ____Telemetry_Event_2 = Telemetry.Event
    local ____array_1 = __TS__SparseArrayNew(
        {
            "pid",
            bot:GetPlayerID()
        },
        {"job", "stay"},
        {"aid", st.aid}
    )
    local ____end_0
    if ____end then
        ____end_0 = nil
    else
        ____end_0 = "camp:" .. tostring(st.sp.idx)
    end
    __TS__SparseArrayPush(
        ____array_1,
        {"tgt", ____end_0},
        {"phase", phase},
        {"why", why},
        {"host", HOST},
        {"cut", cut},
        {
            "ss",
            ____end and r1(DotaTime() - st.t0) or nil
        },
        {"hp0", ____end and st.hp0 or nil},
        {
            "hp1",
            ____end and math.floor(bot:IsAlive() and bot:GetHealth() or 0) or nil
        },
        {"lt", ____end and st.tried or nil},
        {"lk", ____end and st.landed or nil}
    )
    ____Telemetry_Event_2(
        "job",
        {__TS__SparseArraySpread(____array_1)}
    )
end
--- A unit name less `npc_dota_neutral_` (the old stay's try line's `u`).
local function shortName(name)
    local pre = "npc_dota_neutral_"
    return string.sub(name, 1, #pre) == pre and string.sub(name, #pre + 1) or name
end
--- The old stay's try line (`ev=stay_try`), with the stay's aid and the neutral's cid.
local function tryLine(bot, st, n, r, hp, hits, t0)
    Telemetry.Event(
        "stay_try",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"aid", st.aid},
            {
                "slot",
                r1(st.slot)
            },
            {"k", "lasthit"},
            {
                "cid",
                Telemetry.CreepId(n)
            },
            {
                "u",
                shortName(n:GetUnitName())
            },
            {"ok", r.success and 1 or 0},
            {"why", r.reason},
            {"m", r.message},
            {
                "hp",
                math.floor(hp + 0.5)
            },
            {
                "hh",
                r1(hits)
            },
            {
                "dt",
                r1(DotaTime() - t0)
            }
        }
    )
end
--- The reference arm's denominator: where the row is off, the same fight read and one line per opportunity (`src=shadow go=0
-- why=off`), `want` set when the stay was worth starting and possible at some read. Reads and logs; nothing is ordered.
function ____exports.Shadow(bot)
    if not Telemetry.IsEnabled() or ____exports.On() or Drill.Held(bot) then
        return
    end
    local r = observe(bot, CampRead, "shadow")
    if r == nil then
        return
    end
    if worth(bot, r) == nil then
        opps[bot:GetPlayerID()].want = true
    end
end
local function rowWants(bot, reads)
    local pid = bot:GetPlayerID()
    pending[pid] = nil
    if not ____exports.On() or Drill.Held(bot) then
        return nil
    end
    Tasks.Tick(bot)
    local st = running[pid]
    if st ~= nil then
        return {tgt = "camp:" .. tostring(st.sp.idx)}
    end
    if Tasks.Jobs() == nil then
        return nil
    end
    local r = observe(bot, reads.camp, "own")
    if r == nil then
        return nil
    end
    local p = opps[pid]
    local no = worth(bot, r)
    if no ~= nil then
        p.why = no
        return nil
    end
    p.want = true
    local why = block(bot, p, r)
    if why ~= nil then
        p.why = why
        return nil
    end
    pending[pid] = r
    local ____temp_4 = "camp:" .. tostring(r.sp.idx)
    local ____temp_3
    if r.f.life == math.huge then
        ____temp_3 = nil
    else
        ____temp_3 = DotaTime() + r.f.life - r.walk
    end
    return {tgt = ____temp_4, by = ____temp_3}
end
--- The hold now: soft unless a last-hit attempt runs.
local function rowSoft(bot)
    local ____opt_5 = running[bot:GetPlayerID()]
    return (____opt_5 and ____opt_5.hard) ~= true
end
--- The neutral our creeps are on that comes due soonest, if one does: its forecast HP (the engine's `hpForecast`) at the walk into
-- the engine's attack reach plus its own hit time plus Within is within one hit of the hero after armour (as the old stay read it;
-- the verb then times the swing on its own belief).
local function dueNeutral(bot, st, f)
    local V = Tasks.Verbs()
    local tb = bot
    local speed = math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local best
    for ____, n in ipairs(f.worked) do
        do
            local __continue58
            repeat
                if __TS__ArrayIncludes(st.skip, n) then
                    __continue58 = true
                    break
                end
                local c = n
                local walk = math.max(
                    0,
                    GetUnitToUnitDistance(bot, n) - V.attackReach(tb, c)
                ) / speed
                local h = walk + V.ownHitTime(tb, c) + ____exports.SETTINGS.Within
                local ahead = V.forecastHp(
                    V.hpForecast(tb, c, h),
                    h
                )
                local hit = math.max(
                    1,
                    n:GetActualIncomingDamage(
                        bot:GetAttackDamage(),
                        DamageType.Physical
                    )
                )
                if ahead <= hit and (best == nil or ahead < best.ahead) then
                    best = {n = n, h = h, ahead = ahead, hit = hit}
                end
                __continue58 = true
            until true
            if not __continue58 then
                break
            end
        end
    end
    return best
end
--- Why the stay ends now, else undefined. In order: `creeps`, `cleared`, `hit`, `hp`, `danger`, `timeout`.
local function endOf(bot, st, f, stand, now)
    if #f.ours == 0 then
        return "creeps"
    end
    if #f.neutrals == 0 then
        return "cleared"
    end
    if onHero(bot, f) then
        return "hit"
    end
    if hpShare(bot) < ____exports.SETTINGS.HpBar then
        return "hp"
    end
    if stand ~= nil and now - st.dangerAt >= ____exports.SETTINGS.DangerEvery then
        st.dangerAt = now
        if SafeGather.At(bot, stand, {who = "stay"}).level == "deadly" then
            return "danger"
        end
    end
    if now >= st.deadline then
        return "timeout"
    end
    return nil
end
--- One neutral last-hit attempt, the one place the hold switches: hard from the go to the verb's end. Returns the verb's result.
local attempt = __TS__Generator(function(bot, st, d, ctx)
    local hp = d.n:GetHealth()
    local t0 = DotaTime()
    st.hard = true
    ctx.label("lasthit")
    local res = __TS__DelegatedYield(ctx.lastHit({target = d.n, maxWait = d.h + ____exports.SETTINGS.WaitSlack}))
    st.hard = false
    st.tried = st.tried + 1
    if res.success then
        st.landed = st.landed + 1
    end
    if not res.success and (res.reason == "etiquette" or res.reason == "unsupported") then
        local ____st_skip_7 = st.skip
        ____st_skip_7[#____st_skip_7 + 1] = d.n
    end
    tryLine(
        bot,
        st,
        d.n,
        res,
        hp,
        hp / d.hit,
        t0
    )
    return res
end)
--- Away from the camp, towards the lane: the lane's nearest point to the hero.
local function lanePoint(bot)
    local lane = bot:GetAssignedLane()
    return GetLocationAlongLane(
        lane,
        GetAmountAlongLane(
            lane,
            bot:GetLocation()
        ).amount
    )
end
--- Out of every neutral's reach of the hero (the engine's attackReach) by OutMargin, and none attacking it.
local function outOfReach(bot, f)
    local V = Tasks.Verbs()
    for ____, n in ipairs(f.neutrals) do
        if n:GetAttackTarget() == bot then
            return false
        end
        if GetUnitToUnitDistance(bot, n) <= V.attackReach(n, bot) + ____exports.SETTINGS.OutMargin then
            return false
        end
    end
    return true
end
--- A neutral attacks the hero: it walks towards its lane until out of the neutrals' reach (OutFor at most), then the stay ends `hit`.
local walkOut = __TS__Generator(function(bot, st, ctx)
    ctx.label("out")
    local t0 = DotaTime()
    local movedAt = -math.huge
    while true do
        if not bot:IsAlive() then
            return ctx.fail("dead")
        end
        local now = DotaTime()
        if now - t0 >= ____exports.SETTINGS.OutFor or outOfReach(
            bot,
            CampRead.FightOf(st.sp)
        ) then
            return {success = true, reason = "ok", message = "hit"}
        end
        if now - movedAt >= ____exports.SETTINGS.Reorder then
            bot:Action_MoveToLocation(lanePoint(bot))
            movedAt = now
        end
        coroutine.yield()
    end
end)
--- The verb: stand behind our creeps, a neutral's last hit when one comes due, until an end.
local body = __TS__Generator(function(bot, st, ctx)
    local movedAt = -math.huge
    local stop = true
    while true do
        do
            local __continue85
            repeat
                if not bot:IsAlive() then
                    return ctx.fail("dead")
                end
                local now = DotaTime()
                local f = CampRead.FightOf(st.sp)
                local stand = ____exports.StandSpot(bot, f.ours, f.neutrals, st.sp.location)
                local ____end = endOf(
                    bot,
                    st,
                    f,
                    stand,
                    now
                )
                if ____end == "hit" then
                    return __TS__DelegatedYield(walkOut(bot, st, ctx))
                end
                if ____end == "timeout" then
                    return ctx.fail("timeout", "late")
                end
                if ____end ~= nil then
                    return {success = true, reason = "ok", message = ____end}
                end
                local ____temp_8
                if stand ~= nil and dist(
                    bot:GetLocation(),
                    stand
                ) <= ____exports.SETTINGS.AtSpot then
                    ____temp_8 = dueNeutral(bot, st, f)
                else
                    ____temp_8 = nil
                end
                local d = ____temp_8
                if d ~= nil then
                    __TS__DelegatedYield(attempt(bot, st, d, ctx))
                    stop = true
                    __continue85 = true
                    break
                end
                ctx.label("stand")
                local to = stand
                if dist(
                    bot:GetLocation(),
                    to
                ) > ____exports.SETTINGS.Arrive then
                    if now - movedAt >= ____exports.SETTINGS.Reorder then
                        bot:Action_MoveToLocation(to)
                        movedAt = now
                        stop = false
                    end
                elseif stop then
                    bot:Action_MoveToLocation(to)
                    stop = false
                end
                coroutine.yield()
                __continue85 = true
            until true
            if not __continue85 then
                break
            end
        end
    end
end)
local function cutBy(bot, r)
    if r.success or r.reason ~= "preempted" then
        return nil
    end
    if Decider.LetGo(bot) or bot:GetActiveMode() == BotMode.Retreat then
        return "retreat"
    end
    return HDebug.ModeName(bot:GetActiveMode())
end
--- The end's name: the body's own (`creeps`, `cleared`, `hit`, `hp`, `danger`), `replaced` (a higher row began over it), else the runner's or the verb's reason.
local function endWhy(r)
    if r.success then
        return r.message or "ok"
    end
    if r.reason == "cancelled" and r.message == "replaced" then
        return "replaced"
    end
    return r.reason
end
local function finish(bot, st, r)
    local pid = bot:GetPlayerID()
    running[pid] = nil
    local why = endWhy(r)
    local p = opps[pid]
    if p ~= nil and p.slot == st.slot and (why == "hit" or why == "hp" or why == "timeout") then
        p.barred = why
    end
    jobLine(
        bot,
        st,
        "end",
        why,
        cutBy(bot, r)
    )
end
--- The row's `begin`: starts the stay `rowWants` decided this round.
local function rowBegin(bot)
    local pid = bot:GetPlayerID()
    local r = pending[pid]
    pending[pid] = nil
    local p = opps[pid]
    if r == nil or p == nil then
        return false
    end
    local now = DotaTime()
    local st = {
        aid = 0,
        sp = r.sp,
        slot = p.slot,
        t0 = now,
        hp0 = math.floor(bot:GetHealth()),
        deadline = (p.first or now) + ____exports.SETTINGS.Max,
        tried = 0,
        landed = 0,
        hard = false,
        skip = {},
        dangerAt = now
    }
    local ok = Tasks.Start(
        bot,
        {
            name = "stay",
            host = HOST,
            preemptAfter = 1,
            stallAfter = 4,
            onEnd = function(res) return finish(bot, st, res) end
        },
        function(ctx) return body(bot, st, ctx) end
    )
    local aid = ok and Telemetry.NextAid(pid) or nil
    if p.logged ~= true then
        local ____choiceLine_11 = choiceLine
        local ____bot_10 = bot
        local ____ok_9
        if ok then
            ____ok_9 = nil
        else
            ____ok_9 = "refused"
        end
        ____choiceLine_11(
            ____bot_10,
            p,
            ok,
            ____ok_9,
            "own",
            aid
        )
    end
    p.logged = true
    if not ok then
        return false
    end
    st.aid = aid
    if p.first == nil then
        p.first = now
    end
    running[pid] = st
    jobLine(bot, st, "start", "trigger")
    return true
end
--- The row's verb: one frame of the stay; true once it has ended.
local function rowStep(bot)
    Tasks.Step(bot, HOST)
    return running[bot:GetPlayerID()] == nil
end
--- The decider's row (registered in index.ts, so the decider imports no row). Soft but in an attempt (`rowSoft`).
____exports.ROW = {
    name = "stay",
    wants = rowWants,
    begin = rowBegin,
    step = rowStep,
    soft = rowSoft
}
return ____exports
