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
local ended, attempts, lastEnd, pending
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local UnitType = ____dota.UnitType
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Busy = require(GetScriptDirectory().."/FunLib/humaniser/transitions/busy")
function ended(bot, r, info)
    local pid = bot:GetPlayerID()
    local a = attempts[pid]
    if a == nil or a.ended ~= nil then
        return
    end
    if r.reason == "preempted" then
        return
    end
    a.ended = r.success and (r.message or "ok") or (r.message or r.reason)
    local now = DotaTime()
    lastEnd[pid] = now
    pending[pid] = nil
    Telemetry.Event(
        "gank",
        {
            {"pid", pid},
            {
                "pos",
                LaneConfig.PositionOf(bot)
            },
            {"target", a.pid},
            {"lane", a.lane},
            {
                "score",
                string.format("%.2f", a.score)
            },
            {"result", r.success and "ok" or "fail"},
            {"msg", a.ended},
            {"label", info.label},
            {"left", a.left},
            {"engaged", a.engaged},
            {"away", now - a.left}
        }
    )
end
____exports.NAME = "gank"
____exports.SETTINGS = {
    Score = 0.75,
    From = {[2] = 330, [4] = 90},
    MinLevel = {[2] = 5, [4] = 2},
    Until = 720,
    MinHP = 0.6,
    MinMana = 0.4,
    Cooldown = 60,
    MaxAttempts = 3,
    MaxEta = 25,
    PathFactor = 1.2,
    Threshold = {1, 1.8},
    Commit = {0.25, 0.55},
    Bucket = 20,
    FlankSkill = 0.5,
    FlankOffset = 700,
    FlankAt = 0.6,
    TelegraphLead = 3,
    AllyRadius = 1400,
    EnemyRadius = 1200,
    TowerRadius = 900,
    WaveRadius = 1200,
    LaneWidth = 1500,
    AbortHP = 0.4
}
attempts = {}
local counts = {}
lastEnd = {}
local rolls = {}
function ____exports.ResetCache()
    for ____, t in ipairs({attempts, counts, lastEnd}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
    for k in pairs(rolls) do
        rolls[k] = nil
    end
end
local function lerp(r, t)
    return r[1] + (r[2] - r[1]) * t
end
local function d2(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
local function laneOf(loc)
    local best
    local bestD = ____exports.SETTINGS.LaneWidth
    for ____, lane in ipairs({Lane.Top, Lane.Mid, Lane.Bot}) do
        local d = GetAmountAlongLane(lane, loc).distance
        if d < bestD then
            bestD = d
            best = lane
        end
    end
    return best
end
local function heroesNear(list, loc, radius, except)
    local n = 0
    for ____, u in ipairs(GetUnitList(list)) do
        if u ~= except and u:IsAlive() and not u:IsIllusion() and d2(
            u:GetLocation(),
            loc
        ) <= radius then
            n = n + 1
        end
    end
    return n
end
local function visibleUnit(pid)
    for ____, u in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        if u:GetPlayerID() == pid and u:CanBeSeen() and u:IsAlive() then
            return u
        end
    end
    return nil
end
local function towerNear(target)
    return #(target:GetNearbyTowers(____exports.SETTINGS.TowerRadius, false) or ({})) > 0
end
--- knowledge.md 3.3: the best visible enemy core in another lane, with its score; undefined when none qualifies.
function ____exports.BestTarget(bot)
    local s = ____exports.SETTINGS
    local own = bot:GetAssignedLane()
    local speed = math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
    local best
    for ____, e in ipairs(LaneState.Enemies(bot, own)) do
        do
            local __continue23
            repeat
                local ____e_visible_0
                if e.visible then
                    ____e_visible_0 = e.unit
                else
                    ____e_visible_0 = nil
                end
                local u = ____e_visible_0
                if u == nil or e.position ~= nil and e.position > 3 then
                    __continue23 = true
                    break
                end
                local loc = u:GetLocation()
                local lane = laneOf(loc)
                if lane == nil or lane == own then
                    __continue23 = true
                    break
                end
                local eta = d2(
                    bot:GetLocation(),
                    loc
                ) * s.PathFactor / speed
                if eta > s.MaxEta then
                    __continue23 = true
                    break
                end
                local hp = u:GetHealth() / math.max(
                    1,
                    u:GetMaxHealth()
                )
                local setup = heroesNear(UnitType.AlliedHeroes, loc, s.AllyRadius, bot) > 0
                if not setup and hp >= 0.5 then
                    __continue23 = true
                    break
                end
                local score = (1 - hp) * 2
                if GetAmountAlongLane(lane, loc).amount < 0.5 then
                    score = score + 1
                end
                if setup then
                    score = score + 1
                end
                score = score - heroesNear(UnitType.EnemyHeroes, loc, s.EnemyRadius, u)
                if towerNear(u) then
                    score = score - 2
                end
                if best == nil or score > best.score then
                    best = {
                        pid = e.pid,
                        unit = u,
                        lane = lane,
                        score = score,
                        eta = eta
                    }
                end
                __continue23 = true
            until true
            if not __continue23 then
                break
            end
        end
    end
    return best
end
--- Why the bot may not start a gank now, else undefined (the cheap checks first).
function ____exports.Gate(bot, now)
    local s = ____exports.SETTINGS
    local pos = LaneConfig.PositionOf(bot) or 0
    local pid = bot:GetPlayerID()
    if s.From[pos] == nil then
        return "role"
    end
    if now < s.From[pos] or now > s.Until then
        return "window"
    end
    if bot:GetLevel() < s.MinLevel[pos] then
        return "level"
    end
    if (counts[pid] or 0) >= s.MaxAttempts then
        return "attempts"
    end
    if now - (lastEnd[pid] or -math.huge) < s.Cooldown then
        return "cooldown"
    end
    if not bot:IsAlive() or bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    ) < s.MinHP then
        return "hp"
    end
    if bot:GetMana() / math.max(
        1,
        bot:GetMaxMana()
    ) < s.MinMana then
        return "mana"
    end
    if Orders.GetFor(bot) ~= nil then
        return "order"
    end
    if CampJobs.Active(bot) or LaneHooks.RotationDecided(bot) or LaneHooks.IsFightCommitting(bot) then
        return "busy"
    end
    if (Busy.IsBusy(bot, now + s.MaxEta)) then
        return "busy"
    end
    if pos == 4 and not (Busy.LaneCanSpare(bot, false)) then
        return "lane"
    end
    if pos == 2 and #(bot:GetNearbyLaneCreeps(s.WaveRadius, true) or ({})) > 0 then
        return "wave"
    end
    return nil
end
local function rollFor(bot, pick, now)
    local key = (((tostring(bot:GetPlayerID()) .. ":") .. tostring(pick.pid)) .. ":") .. tostring(math.floor(now / ____exports.SETTINGS.Bucket))
    if rolls[key] == nil then
        rolls[key] = LaneConfig.Roll(lerp(
            ____exports.SETTINGS.Commit,
            LaneConfig.SkillOf(bot)
        ))
    end
    return rolls[key] == true
end
pending = {}
local function score(bot)
    local pid = bot:GetPlayerID()
    local a = attempts[pid]
    local now = DotaTime()
    if a ~= nil and a.ended == nil then
        if now - a.left <= ____exports.SETTINGS.MaxEta * 1.5 + 20 then
            return ____exports.SETTINGS.Score
        end
        ended(bot, {success = false, reason = "timeout", message = "expired"}, {steps = 0})
        return nil
    end
    if ____exports.Gate(bot, now) ~= nil then
        return nil
    end
    local pick = ____exports.BestTarget(bot)
    if pick == nil or pick.score < lerp(
        ____exports.SETTINGS.Threshold,
        LaneConfig.SkillOf(bot)
    ) then
        return nil
    end
    if not rollFor(bot, pick, now) then
        return nil
    end
    pending[pid] = pick
    return ____exports.SETTINGS.Score
end
--- A point off the lane line on the way to the target: from the side away from the lane (through trees and fog).
function ____exports.FlankPoint(from, target, lane)
    local s = ____exports.SETTINGS
    local dx = target.x - from.x
    local dy = target.y - from.y
    local len = math.max(
        1,
        math.sqrt(dx * dx + dy * dy)
    )
    local mid = Vector(from.x + dx * s.FlankAt, from.y + dy * s.FlankAt, target.z)
    local px = -dy / len * s.FlankOffset
    local py = dx / len * s.FlankOffset
    local a = Vector(mid.x + px, mid.y + py, mid.z)
    local b = Vector(mid.x - px, mid.y - py, mid.z)
    return GetAmountAlongLane(lane, a).distance >= GetAmountAlongLane(lane, b).distance and a or b
end
local function abortWhy(bot, target)
    local s = ____exports.SETTINGS
    if bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    ) < s.AbortHP then
        return "low-hp"
    end
    local here = bot:GetLocation()
    if heroesNear(UnitType.EnemyHeroes, here, s.EnemyRadius) > heroesNear(UnitType.AlliedHeroes, here, s.EnemyRadius) then
        return "outnumbered"
    end
    local t = target()
    if t ~= nil and towerNear(t) and d2(
        here,
        t:GetLocation()
    ) > bot:GetAttackRange() + 200 then
        return "tower"
    end
    return nil
end
local body = __TS__Generator(function(bot, ctx)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local a = attempts[pid]
    if a == nil or a.ended ~= nil then
        local pick = pending[pid]
        if pick == nil then
            return ctx.fail("no_target", "no-pick")
        end
        a = {pid = pick.pid, lane = pick.lane, score = pick.score, left = now}
        attempts[pid] = a
        counts[pid] = (counts[pid] or 0) + 1
    end
    local attempt = a
    local last
    local function target()
        local u = visibleUnit(attempt.pid)
        if u ~= nil then
            last = u
        elseif last ~= nil and not IsHeroAlive(attempt.pid) then
            return last
        end
        return u
    end
    local t0 = target()
    if t0 == nil then
        return ctx.fail("interrupted", "escaped")
    end
    local skill = ctx.skill()
    local flank = skill >= ____exports.SETTINGS.FlankSkill
    local path = flank and ({____exports.FlankPoint(
        bot:GetLocation(),
        t0:GetLocation(),
        attempt.lane
    )}) or ({})
    local eta = GetUnitToUnitDistance(bot, t0) * ____exports.SETTINGS.PathFactor / math.max(
        1,
        bot:GetCurrentMovementSpeed()
    )
    return __TS__DelegatedYield(Tasks.Verbs().gank(
        bot,
        {
            target = function() return target() end,
            path = path,
            engageRange = math.max(
                600,
                bot:GetAttackRange() + 100
            ),
            deadline = now + eta * 1.5 + 5,
            engageFor = 8,
            telegraph = flank and ({
                lead = ____exports.SETTINGS.TelegraphLead,
                fn = function()
                    local t = target()
                    if t == nil or not Difficulty.IsAllyOfHuman(bot) then
                        return
                    end
                    Orders.Ping(
                        bot,
                        t:GetLocation()
                    )
                end
            }) or nil,
            commit = function() return abortWhy(bot, target) end,
            onEngage = function(t)
                attempt.engaged = t
            end
        },
        {label = ctx.label, urgent = ctx.urgent}
    ))
end)
--- Owned positions run the gank; other bots have no gank state (OHA's upstream roam is not a planned rotation).
function ____exports.Spec(bot, owned)
    return {
        name = ____exports.NAME,
        kind = "job",
        host = BotMode.Roam,
        tier = "TRANSITION",
        floor = ____exports.SETTINGS.Score,
        preemptAfter = 1,
        score = function()
            local ____owned_result_1
            if owned(bot, ____exports.NAME) then
                ____owned_result_1 = score(bot)
            else
                ____owned_result_1 = nil
            end
            return ____owned_result_1
        end,
        onEnd = function(r, info) return ended(bot, r, info) end,
        body = function(ctx) return body(bot, ctx) end
    }
end
return ____exports
