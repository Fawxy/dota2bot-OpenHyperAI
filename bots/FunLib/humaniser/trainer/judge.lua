--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end

local function __TS__ArrayFilter(self, callbackfn, thisArg)
    local result = {}
    local len = 0
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            len = len + 1
            result[len] = self[i]
        end
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local Round, Taker
local ____format = require(GetScriptDirectory().."/FunLib/humaniser/trainer/format")
local Sec = ____format.Sec
local Signed = ____format.Signed
function Round(x)
    return math.floor(x + 0.5)
end
function Taker(killer)
    if killer.kind == "tower" then
        return "tower took it"
    end
    if killer.kind == "enemyHero" then
        return "denied by " .. (killer.name or "an enemy hero")
    end
    if killer.kind == "ally" then
        return (killer.name or "an ally") .. " took it"
    end
    return "lane creep took it"
end
local RESOLVE_AFTER = 2.5
local MISS_GRACE = 0.3
local EARLY_WINDOW = 0.2
local EARLY_DROP_FRACTION = 0.6
local MIN_EARLY = 0.01
____exports.Judge = __TS__Class()
local Judge = ____exports.Judge
Judge.name = "Judge"
function Judge.prototype.____constructor(self, easyWindow)
    self.easyWindow = easyWindow
    self.attempts = {}
    self.attempted = {}
    self.reported = {}
    self.prevAnim = "none"
    self.prevTarget = nil
end
function Judge.prototype.Step(self, s, creeps)
    local events = {}
    local byId = {}
    for ____, c in ipairs(creeps) do
        byId[c.id] = c
    end
    self:resolveOpen(s, byId, events)
    self:trackSwing(s, byId, events)
    self:emitOutcomes(creeps, events)
    self.prevAnim = s.anim
    self.prevTarget = s.target
    return events
end
function Judge.prototype.resolveOpen(self, s, byId, events)
    local open = {}
    local lastForCreep = {}
    for ____, a in ipairs(self.attempts) do
        lastForCreep[a.creepId] = a
    end
    for ____, a in ipairs(self.attempts) do
        local c = byId[a.creepId]
        local ____temp_0
        if c == nil then
            ____temp_0 = self:forced(s, a)
        else
            ____temp_0 = self:resolve(s, a, c, lastForCreep[a.creepId] == a)
        end
        local verdict = ____temp_0
        if verdict == nil then
            open[#open + 1] = a
        else
            events[#events + 1] = {type = "verdict", v = verdict}
        end
    end
    self.attempts = open
end
function Judge.prototype.resolve(self, s, a, c, isLatest)
    if not c.alive then
        local ____temp_1
        if c.killer == nil then
            ____temp_1 = self:forced(s, a)
        else
            ____temp_1 = self:resolveDeath(s, a, c.killer, isLatest)
        end
        return ____temp_1
    end
    local dropWindowStart = a.predictedLand - EARLY_WINDOW
    if s.now < dropWindowStart then
        a.baselineHp = c.hp
    elseif s.now <= a.predictedLand + EARLY_WINDOW and a.baselineHp - c.hp >= EARLY_DROP_FRACTION * a.prediction.effDmg then
        return self:early(s, a)
    end
    if s.now > a.predictedLand + MISS_GRACE then
        return self:verdict("MISS", s, a, "missed - evasion/uphill?")
    end
    return self:forced(s, a)
end
function Judge.prototype.forced(self, s, a)
    if s.now - a.startedAt < RESOLVE_AFTER then
        return nil
    end
    return self:verdict("MISS", s, a, "missed - no result after 2.5s")
end
function Judge.prototype.early(self, s, a)
    local by = math.max(a.prediction.startOpen - a.swingStart, MIN_EARLY)
    local reason = (((("early by " .. Sec(by)) .. "s - creep had ") .. tostring(Round(a.hp))) .. " HP, you deal ") .. tostring(Round(a.prediction.effDmg))
    return self:verdict(
        "EARLY",
        s,
        a,
        reason,
        a.swingStart - a.prediction.ideal,
        s.now
    )
end
function Judge.prototype.resolveDeath(self, s, a, killer, isLatest)
    local offset = a.swingStart - a.prediction.ideal
    if killer.kind == "subject" then
        if not isLatest then
            return self:early(s, a)
        end
        local p = a.prediction
        if a.swingStart >= p.startOpen and a.swingStart < p.startClose then
            return self:verdict(
                "PERFECT",
                s,
                a,
                ("perfect (" .. Signed(offset)) .. "s)",
                offset,
                s.now
            )
        end
        local early = a.swingStart < p.startOpen
        local distance = early and p.startOpen - a.swingStart or a.swingStart - p.startClose
        return self:verdict(
            "OK",
            s,
            a,
            ((("got it (window said " .. Sec(distance)) .. "s ") .. (early and "early" or "late")) .. ")",
            offset,
            s.now
        )
    end
    local taker = Taker(killer)
    if s.now < a.predictedLand then
        return self:verdict(
            "LATE",
            s,
            a,
            (("late by " .. Sec(a.predictedLand - s.now)) .. "s - ") .. taker,
            offset,
            s.now
        )
    end
    return self:verdict("MISS", s, a, "missed - " .. taker)
end
function Judge.prototype.verdict(self, kind, s, a, reason, offset, landedAt)
    return {
        kind = kind,
        at = s.now,
        creepId = a.creepId,
        creepKind = a.creepKind,
        isDeny = a.isDeny,
        harassed = a.harassed,
        swung = true,
        offset = offset,
        predictedLand = a.predictedLand,
        landedAt = landedAt,
        reason = reason
    }
end
function Judge.prototype.trackSwing(self, s, byId, events)
    local current = self:swingingAttempt()
    local retargeted = s.anim == "swing" and current ~= nil and current.creepId ~= s.target
    if current ~= nil then
        if s.anim == "followthrough" then
            current.swinging = false
        elseif s.anim == "none" or retargeted then
            self.attempts = __TS__ArrayFilter(
                self.attempts,
                function(____, a) return a ~= current end
            )
            events[#events + 1] = {
                type = "verdict",
                v = self:verdict("CANCELLED", s, current, "cancelled swing")
            }
        end
    end
    local started = s.anim == "swing" and (self.prevAnim ~= "swing" or s.target ~= self.prevTarget)
    if not started or s.target == nil then
        return
    end
    local c = byId[s.target]
    if c == nil or not c.alive or c.prediction == nil then
        return
    end
    local swingStart = s.swingStart or s.now
    self.attempted[c.id] = true
    local ____self_attempts_2 = self.attempts
    ____self_attempts_2[#____self_attempts_2 + 1] = {
        creepId = c.id,
        creepKind = c.kind,
        isDeny = c.isDeny,
        harassed = s.harassed,
        prediction = c.prediction,
        swingStart = swingStart,
        startedAt = s.now,
        predictedLand = swingStart + c.prediction.delay,
        hp = c.hp,
        baselineHp = c.hp,
        swinging = true
    }
end
function Judge.prototype.swingingAttempt(self)
    do
        local i = #self.attempts - 1
        while i >= 0 do
            if self.attempts[i + 1].swinging then
                return self.attempts[i + 1]
            end
            i = i - 1
        end
    end
    return nil
end
function Judge.prototype.emitOutcomes(self, creeps, events)
    for ____, c in ipairs(creeps) do
        do
            local __continue38
            repeat
                if c.alive or c.killer == nil or not self.attempted[c.id] or self.reported[c.id] then
                    __continue38 = true
                    break
                end
                self.reported[c.id] = true
                events[#events + 1] = {type = "outcome", creepId = c.id, subjectGotIt = c.killer.kind == "subject"}
                __continue38 = true
            until true
            if not __continue38 then
                break
            end
        end
    end
end
return ____exports
