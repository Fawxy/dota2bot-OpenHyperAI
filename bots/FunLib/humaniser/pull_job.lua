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
local running
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local PullTiming = require(GetScriptDirectory().."/FunLib/humaniser/pull_timing")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function ____exports.Running(bot)
    return running[bot:GetPlayerID()] ~= nil
end
____exports.SETTINGS = {
    Priority = 0.9,
    Early = 2,
    PathFactor = 1.2,
    HoldPastQ = 0.5,
    PartnerHp = 0.5,
    PartnerRadius = 900,
    PartnerGank = 3,
    WatchEvery = 0.25
}
running = {}
local handled = {}
local decided = {}
local gateWhy = {}
function ____exports.ResetCache()
    for ____, t in ipairs({running, handled, decided, gateWhy}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end
local function isSupport(u)
    local pos = LaneConfig.PositionOf(u)
    return pos == 4 or pos == 5
end
--- The support that pulls for `bot`'s lane: pos5 when both supports share it.
local function pullerOfLane(bot)
    if LaneConfig.PositionOf(bot) == 5 then
        return true
    end
    local lane = bot:GetAssignedLane()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue9
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m == bot then
                        __continue9 = true
                        break
                    end
                    if LaneConfig.PositionOf(m) == 5 and m:GetAssignedLane() == lane then
                        return false
                    end
                    __continue9 = true
                until true
                if not __continue9 then
                    break
                end
            end
            i = i + 1
        end
    end
    return true
end
local function campFor(bot)
    local lane = bot:GetAssignedLane()
    if lane ~= Lane.Top and lane ~= Lane.Bot then
        return nil
    end
    return Camps.PullCampsFor(
        bot:GetTeam(),
        lane
    )[1]
end
function ____exports.Applies(bot)
    return Ours.On("SupportPull") and Ours.On("JobChooser") and bot:IsBot() and isSupport(bot) and pullerOfLane(bot) and campFor(bot) ~= nil
end
function ____exports.Priority(bot)
    return ____exports.Applies(bot) and ____exports.SETTINGS.Priority or nil
end
function ____exports.Claims(bot)
    return ____exports.Running(bot)
end
--- The next hit second at or after `from` among `seconds` of each minute (camp_jobs' NextAggroTime).
function ____exports.NextSlot(from, seconds, period)
    local base = math.floor(from / period) * period
    local best = math.huge
    for ____, s in ipairs(seconds) do
        for ____, t in ipairs({base + s, base + period + s}) do
            if t >= from and t < best then
                best = t
            end
        end
    end
    return best
end
local function planFor(bot, now)
    local camp = campFor(bot)
    local ____temp_0
    if camp ~= nil then
        ____temp_0 = Camps.SpawnerByIdx(camp.campIdx)
    else
        ____temp_0 = nil
    end
    local spawner = ____temp_0
    if camp == nil or camp.pull == nil or spawner == nil then
        return nil
    end
    local t = LaneConfig.Settings().Timing
    local timing = PullTiming.ForCamp(camp, false)
    if #timing.seconds == 0 then
        return nil
    end
    local slot = ____exports.NextSlot(now - t.JobStartLate, timing.seconds, t.PullPeriod)
    if math.floor(slot / t.PullPeriod) * t.PullPeriod < t.NeutralFirstSpawn then
        return nil
    end
    local meet = camp.pull.meetPoint
    local lead = PullTiming.LeadPath(camp.pull, meet)
    local stand = Camps.StandPoint(
        spawner,
        lead[1],
        LaneConfig.Settings().Radii.StandOffset
    )
    return {
        camp = camp,
        spawner = spawner,
        stand = stand,
        lead = lead,
        meet = meet,
        timing = timing,
        slot = slot,
        waveAt = timing.waveAfter ~= nil and slot + timing.waveAfter or nil
    }
end
local function travel(bot, p)
    return GetUnitToLocationDistance(bot, p.stand) * ____exports.SETTINGS.PathFactor / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
end
--- The reading wants a pull: our clash point moves out (towards their tower), or holds past the middle on their side.
function ____exports.Wanted(r)
    if r == nil then
        return false
    end
    return r.state == "OUT" or r.state == "HOLD" and r.q > ____exports.SETTINGS.HoldPastQ
end
--- Why the lane partner (a teammate core assigned to the lane) should not be left now, else undefined.
local function partnerThreat(bot)
    local lane = bot:GetAssignedLane()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue31
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m == bot or not m:IsAlive() or isSupport(m) or m:GetAssignedLane() ~= lane then
                        __continue31 = true
                        break
                    end
                    local pids = {}
                    local n = 0
                    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
                        do
                            local __continue33
                            repeat
                                if not e:IsAlive() or e:IsIllusion() or GetUnitToUnitDistance(e, m) > ____exports.SETTINGS.PartnerRadius then
                                    __continue33 = true
                                    break
                                end
                                if pids[e:GetPlayerID()] ~= true then
                                    n = n + 1
                                end
                                pids[e:GetPlayerID()] = true
                                __continue33 = true
                            until true
                            if not __continue33 then
                                break
                            end
                        end
                    end
                    if n >= ____exports.SETTINGS.PartnerGank then
                        return "partner-gank"
                    end
                    if n > 0 and m:GetHealth() < m:GetMaxHealth() * ____exports.SETTINGS.PartnerHp then
                        return "partner-low"
                    end
                    __continue31 = true
                until true
                if not __continue31 then
                    break
                end
            end
            i = i + 1
        end
    end
    return nil
end
--- OHA's own action holds the hero (rune_job's check: a queued TP, a cast or channel).
local function acting(bot)
    return bot:NumQueuedActions() > 0 or bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility()
end
local function choiceLine(bot, d, go, why)
    local r = d.reading
    local function r1(x)
        return x ~= nil and math.floor(x + 0.5) or nil
    end
    Telemetry.Event(
        "choice",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "pull"},
            {"go", go and 1 or 0},
            {"want", d.want and 1 or 0},
            {"why", why},
            {"src", "own"},
            {
                "lane",
                bot:GetAssignedLane()
            },
            {"slot", d.slot},
            {"st", r and r.state},
            {
                "q",
                r ~= nil and math.floor(r.q * 100 + 0.5) / 100 or nil
            },
            {
                "mv",
                r1(r and r.move)
            },
            {
                "cf",
                r1(r and r.cf)
            },
            {"tw", r ~= nil and (r.tower and 1 or 0) or nil},
            {"ms", r and r.ms}
        }
    )
end
local function jobLine(bot, p, phase, why)
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "pull"},
            {"phase", phase},
            {"why", why},
            {"host", p.host},
            unpack(phase == "end" and ({{"hit", p.hit == true and 1 or 0}}) or ({}))
        }
    )
end
local function finish(bot, p, r, label)
    running[bot:GetPlayerID()] = nil
    local why = r.success and "ok" or r.reason .. (r.message ~= nil and ":" .. r.message or "")
    jobLine(bot, p, "end", why)
    local function r1(x)
        return math.floor(x * 10) / 10
    end
    Telemetry.Event(
        "pull_job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {
                "pos",
                LaneConfig.PositionOf(bot)
            },
            {
                "lane",
                bot:GetAssignedLane()
            },
            {"camp", p.plan.camp.campIdx},
            {"slot", p.plan.slot},
            {"res", r.success and "ok" or "fail"},
            {"why", why},
            {"label", label or p.label},
            {
                "div",
                p.wave > 0 and math.floor(p.peak / p.wave * 100 + 0.5) / 100 or 0
            },
            {"n", p.wave},
            {
                "left",
                r1(p.left)
            },
            {
                "away",
                r1(DotaTime() - p.left)
            },
            {
                "died",
                bot:IsAlive() and 0 or 1
            },
            {"hit", p.hit == true and 1 or 0},
            {"idle", p.idle},
            {
                "wd",
                p.near ~= nil and math.floor(p.near + 0.5) or nil
            },
            {"nn", p.neutrals}
        }
    )
end
local function laneCreepsNear(center, radius)
    local out = {}
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue46
            repeat
                if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue46 = true
                    break
                end
                if GetUnitToLocationDistance(c, center) <= radius then
                    out[#out + 1] = c
                end
                __continue46 = true
            until true
            if not __continue46 then
                break
            end
        end
    end
    return out
end
local function onNeutral(c)
    local t = c:GetAttackTarget()
    return t ~= nil and t ~= nil and t:GetTeam() == Team.Neutral
end
--- During lead and watch: our wave's largest diverted share (camp_jobs' sample: the wave is counted once the first of it
-- is seen on a neutral).
local function sample(p)
    if p.label ~= "lead" and p.label ~= "watch" then
        return
    end
    local now = DotaTime()
    if p.sampledAt ~= nil and now - p.sampledAt < ____exports.SETTINGS.WatchEvery then
        return
    end
    p.sampledAt = now
    local radii = LaneConfig.Settings().Radii
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        do
            local __continue54
            repeat
                if not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue54 = true
                    break
                end
                local d = GetUnitToLocationDistance(c, p.plan.meet)
                if p.near == nil or d < p.near then
                    p.near = d
                end
                __continue54 = true
            until true
            if not __continue54 then
                break
            end
        end
    end
    local nn = 0
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        if u:IsAlive() and GetUnitToLocationDistance(u, p.plan.meet) <= radii.MeetWatch then
            nn = nn + 1
        end
    end
    p.neutrals = math.max(p.neutrals, nn)
    local n = 0
    for ____, c in ipairs(laneCreepsNear(p.plan.meet, radii.MeetWatch)) do
        if onNeutral(c) then
            n = n + 1
        end
    end
    if n == 0 then
        return
    end
    if p.wave == 0 then
        p.wave = math.max(
            1,
            #laneCreepsNear(p.plan.meet, radii.WaveSize)
        )
    end
    p.peak = math.max(
        p.peak,
        math.min(n, p.wave)
    )
end
local function verbCamp(p)
    local radii = LaneConfig.Settings().Radii
    local o = p.spawner.location
    local d = math.sqrt((p.stand.x - o.x) ^ 2 + (p.stand.y - o.y) ^ 2)
    local approach = d > radii.StandApproach + radii.JobArrive and Vector(o.x + (p.stand.x - o.x) * radii.StandApproach / d, o.y + (p.stand.y - o.y) * radii.StandApproach / d, o.z) or nil
    return {
        stand = p.stand,
        approach = approach,
        box = {min = p.spawner.min, max = p.spawner.max},
        origin = o,
        margin = radii.BoxMargin,
        search = radii.NeutralSearch
    }
end
local function verbPlan(p, aggroAt)
    local s = LaneConfig.Settings()
    return {
        camp = verbCamp(p),
        aggroAt = aggroAt,
        lead = p.lead,
        watchSec = s.Timing.WatchSec,
        watchUntil = p.waveAt ~= nil and p.waveAt + s.PullTiming.WatchAfterWave or nil,
        leadDeadline = aggroAt + s.Timing.JobMaxAfterAggro,
        arrive = s.Radii.JobArrive,
        startLate = s.Timing.JobStartLate,
        approachLead = s.Timing.StandApproachLead,
        noCampAfter = s.Timing.NoCampAfter,
        confirmFor = s.Timing.AggroConfirm
    }
end
local body = __TS__Generator(function(bot, p, aggroAt, ctx)
    local hooks = {
        label = function(l)
            ctx.label(l)
            p.label = l
        end,
        urgent = ctx.urgent
    }
    return __TS__DelegatedYield(Tasks.Jobs().pull(
        bot,
        verbPlan(p.plan, aggroAt),
        hooks
    ))
end)
--- The pull side of the lane path: our walking wave is everything of ours short of the meet point (the counterfactual).
local function meetAlong(bot, p)
    local path = LanePush.PathOf(bot:GetAssignedLane())
    return path ~= nil and (LanePush.Project(path, p.meet.x, p.meet.y)) or nil
end
--- Every frame while the chooser asks: true while a pull runs or as one starts. The lane is read once per slot at the leave
-- time; a wanted pull then waits for `blocked` (the chooser's checks, a higher job's claim), the partner check and OHA's own
-- action until it could no longer reach the camp by the hit's late limit.
function ____exports.Wants(bot, blocked, host)
    if not ____exports.Applies(bot) then
        return false
    end
    local pid = bot:GetPlayerID()
    Tasks.Tick(bot)
    if running[pid] ~= nil then
        return true
    end
    if Tasks.Jobs() == nil or not LaneConfig.InLaningPhase() or not bot:IsAlive() then
        return false
    end
    local now = DotaTime()
    local p = planFor(bot, now)
    if p == nil or handled[pid] == p.slot then
        return false
    end
    local walk = travel(bot, p)
    if now < p.slot - walk - ____exports.SETTINGS.Early then
        return false
    end
    local d = decided[pid]
    if d == nil or d.slot ~= p.slot then
        local reading = LanePush.Read(
            bot:GetTeam(),
            bot:GetAssignedLane(),
            meetAlong(bot, p)
        )
        d = {
            slot = p.slot,
            want = ____exports.Wanted(reading),
            reading = reading
        }
        decided[pid] = d
        gateWhy[pid] = nil
    end
    local function done(go, why)
        handled[pid] = p.slot
        gateWhy[pid] = nil
        choiceLine(bot, d, go, why)
    end
    if not d.want then
        done(false, d.reading == nil and "no-read" or "lane")
        return false
    end
    local why = blocked(bot) or partnerThreat(bot) or (acting(bot) and "acting" or nil)
    if now + walk > p.slot + LaneConfig.Settings().Timing.JobStartLate then
        done(false, gateWhy[pid] or why or "late")
        return false
    end
    if why ~= nil then
        gateWhy[pid] = why
        return false
    end
    local aggroAt = p.slot + (PullTiming.LiveShift(p.timing, p.slot, now) or 0)
    local pull = {
        plan = p,
        left = now,
        host = host,
        wave = 0,
        peak = 0,
        neutrals = 0
    }
    local ok = Tasks.Start(
        bot,
        {
            name = "pull",
            host = host,
            preemptAfter = 1,
            stallAfter = 4,
            onEnd = function(r, info) return finish(bot, pull, r, info.label) end
        },
        function(ctx) return body(bot, pull, aggroAt, ctx) end
    )
    if not ok then
        done(false, "refused")
        return false
    end
    done(true, nil)
    running[pid] = pull
    jobLine(bot, pull, "start", "trigger")
    return true
end
function ____exports.Step(bot, host)
    local p = running[bot:GetPlayerID()]
    if p == nil then
        return false
    end
    sample(p)
    return Tasks.Step(bot, host)
end
function ____exports.End(bot, why)
    if running[bot:GetPlayerID()] ~= nil then
        Tasks.Cancel(bot, "cancelled", why)
    end
end
function ____exports.NoteHit(bot)
    local p = running[bot:GetPlayerID()]
    if p ~= nil then
        p.hit = true
    end
end
function ____exports.NoteIdleHeld(bot)
    local p = running[bot:GetPlayerID()]
    if p ~= nil then
        p.idle = (p.idle or 0) + 1
    end
end
return ____exports
