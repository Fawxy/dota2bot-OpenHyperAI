--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArraySort(self, compareFn)
    if compareFn ~= nil then
        table.sort(
            self,
            function(a, b) return compareFn(nil, a, b) < 0 end
        )
    else
        table.sort(self)
    end
    return self
end

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
local ____format = require(GetScriptDirectory().."/FunLib/humaniser/trainer/format")
local Sec = ____format.Sec
local Signed = ____format.Signed
local MIN_TAKEABLE = 10
local ON_TIME = 0.03
local SPLIT_MIN_OFFSETS = 3
local SPLIT_MIN_DIFF = 0.05
local HARASS_MIN_GROUP = 5
local HARASS_LINE_GAP = 15
local HARASS_LEAK_GAP = 20
local BIAS_MIN_MEAN = 0.06
local BIAS_MIN_SHARE = 0.2
local NO_SWING_MIN = 3
local KIND_SHARE = 0.6
local DENY_MIN = 5
local DENY_MAX_RATE = 0.3
local ADJ_STEP = 0.05
local function Pct(s, t)
    return t == 0 and 0 or math.floor(100 * s / t + 0.5)
end
local function IsSuccess(v)
    return v.kind == "PERFECT" or v.kind == "OK"
end
local function Mean(xs)
    local sum = 0
    for ____, x in ipairs(xs) do
        sum = sum + x
    end
    return sum / #xs
end
local function Median(xs)
    local sorted = {unpack(xs)}
    __TS__ArraySort(
        sorted,
        function(____, a, b) return a - b end
    )
    local n = #sorted
    local mid = math.floor(n / 2)
    return n % 2 == 1 and sorted[mid + 1] or (sorted[mid] + sorted[mid + 1]) / 2
end
local function Direction(avg)
    if math.abs(avg) < ON_TIME then
        return "fine"
    end
    return avg < 0 and "early" or "late"
end
____exports.Stats = __TS__Class()
local Stats = ____exports.Stats
Stats.name = "Stats"
function Stats.prototype.____constructor(self)
    self.takeable = {}
    self.gotIt = {}
end
function Stats.prototype.Add(self, e)
    if e.type == "outcome" then
        self.gotIt[e.creepId] = e.subjectGotIt
    elseif e.v.kind ~= "CANCELLED" then
        local ____self_takeable_0 = self.takeable
        ____self_takeable_0[#____self_takeable_0 + 1] = e.v
    end
end
function Stats.prototype.Reset(self)
    self.takeable = {}
    self.gotIt = {}
end
function Stats.prototype.Lines(self, o)
    local lines = {
        self:scoreLine(o.denies),
        self:timingLine(o.outcomeOnly),
        self:Leak(o.denies)
    }
    local harass = self:harassLine()
    if harass ~= nil then
        lines[#lines + 1] = harass
    end
    return lines
end
function Stats.prototype.SelfTestLine(self)
    local t = #self.takeable
    local s = #__TS__ArrayFilter(
        self.takeable,
        function(____, v) return IsSuccess(v) end
    )
    return ((((((((("selftest: " .. tostring(s)) .. "/") .. tostring(t)) .. " PERFECT+OK (") .. tostring(Pct(s, t))) .. "%) - easy misses ") .. tostring(self:count(function(v) return v.kind == "MISSED_EASY" end))) .. " of ") .. tostring(t)) .. " reachable"
end
function Stats.prototype.Leak(self, denies)
    if #self.takeable < MIN_TAKEABLE then
        return "not enough data yet"
    end
    local rules = {}
    local function add(r)
        if r ~= nil then
            rules[#rules + 1] = r
        end
    end
    add(self:noSwingRule())
    add(self:lateRule())
    add(self:earlyRule())
    add(self:harassRule())
    if denies then
        add(self:denyRule())
    end
    local best = nil
    for ____, r in ipairs(rules) do
        if best == nil or r.cost > best.cost then
            best = r
        end
    end
    return best == nil and "no clear leak - keep going" or best.line
end
function Stats.prototype.count(self, pred)
    return #__TS__ArrayFilter(
        self.takeable,
        function(____, v) return pred(v) end
    )
end
function Stats.prototype.scoreLine(self, denies)
    local lh = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return not v.isDeny end
    )
    local dn = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.isDeny end
    )
    local lhOk = #__TS__ArrayFilter(
        lh,
        function(____, v) return IsSuccess(v) end
    )
    local line = ((((("LH " .. tostring(lhOk)) .. "/") .. tostring(#lh)) .. " (") .. tostring(Pct(lhOk, #lh))) .. "%)"
    if denies then
        line = line .. ((" - denies " .. tostring(#__TS__ArrayFilter(
            dn,
            function(____, v) return IsSuccess(v) end
        ))) .. "/") .. tostring(#dn)
    end
    return (line .. " - easy misses ") .. tostring(self:count(function(v) return v.kind == "MISSED_EASY" end))
end
function Stats.prototype.offsets(self, filter)
    local out = {}
    for ____, v in ipairs(self.takeable) do
        do
            local __continue39
            repeat
                if v.offset == nil or not v.swung then
                    __continue39 = true
                    break
                end
                if filter ~= nil and not filter(v) then
                    __continue39 = true
                    break
                end
                out[#out + 1] = v.offset
                __continue39 = true
            until true
            if not __continue39 then
                break
            end
        end
    end
    return out
end
function Stats.prototype.isLate(self, v)
    return v.kind == "LATE" or v.kind == "MISSED_EASY" and v.swung
end
function Stats.prototype.timingLine(self, outcomeOnly)
    if outcomeOnly then
        local early = self:count(function(v) return v.kind == "EARLY" end)
        return ((("early " .. tostring(early)) .. " - late ") .. tostring(self:count(function(v) return self:isLate(v) end))) .. " (no timing detail)"
    end
    local offsets = self:offsets()
    if #offsets == 0 then
        return "no timing data yet"
    end
    local mean = Mean(offsets)
    local median = ("(median " .. Signed(Median(offsets))) .. "s)"
    local line = math.abs(mean) < ON_TIME and "you start on time on average " .. median or (((("you start " .. Sec(mean)) .. "s ") .. (mean < 0 and "early" or "late")) .. " on average ") .. median
    local ranged = self:offsets(function(v) return v.creepKind == "ranged" end)
    local melee = self:offsets(function(v) return v.creepKind == "melee" end)
    if #ranged >= SPLIT_MIN_OFFSETS and #melee >= SPLIT_MIN_OFFSETS then
        local r = Mean(ranged)
        local m = Mean(melee)
        if math.abs(r - m) > SPLIT_MIN_DIFF then
            line = line .. ((((((("; " .. Direction(r)) .. " on ranged (") .. Signed(r)) .. "s), ") .. Direction(m)) .. " on melee (") .. Signed(m)) .. "s)"
        end
    end
    return line
end
function Stats.prototype.group(self, harassed)
    local g = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.harassed == harassed end
    )
    return {
        t = #g,
        s = #__TS__ArrayFilter(
            g,
            function(____, v) return IsSuccess(v) end
        )
    }
end
function Stats.prototype.harassGap(self)
    local harassed = self:group(true)
    local free = self:group(false)
    if harassed.t < HARASS_MIN_GROUP or free.t < HARASS_MIN_GROUP then
        return nil
    end
    return {harassed = harassed, free = free, gap = 100 * free.s / free.t - 100 * harassed.s / harassed.t}
end
function Stats.prototype.harassLine(self)
    local g = self:harassGap()
    if g == nil or math.abs(g.gap) < HARASS_LINE_GAP then
        return nil
    end
    return ((("under harass " .. tostring(Pct(g.harassed.s, g.harassed.t))) .. "% vs ") .. tostring(Pct(g.free.s, g.free.t))) .. "% free"
end
function Stats.prototype.noSwingRule(self)
    local misses = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.kind == "MISSED_EASY" and not v.swung end
    )
    if #misses < NO_SWING_MIN then
        return nil
    end
    local suffix = ". Watch every creep near you, not just your target."
    local kinds = {{"ranged", ", mostly ranged. Watch the backline."}, {"melee", ", mostly melee. Watch the front line."}, {"siege", ", mostly siege. Watch the catapult."}}
    for ____, ____value in ipairs(kinds) do
        local kind = ____value[1]
        local text = ____value[2]
        if #__TS__ArrayFilter(
            misses,
            function(____, v) return v.creepKind == kind end
        ) >= KIND_SHARE * #misses then
            suffix = text
            break
        end
    end
    return {
        cost = #misses,
        line = (tostring(#misses) .. " easy creeps lost with no swing") .. suffix
    }
end
function Stats.prototype.attempts(self)
    return self:count(function(v) return v.swung end)
end
function Stats.prototype.adjustment(self, mean)
    return Sec(math.max(
        ADJ_STEP,
        math.floor(math.abs(mean) / ADJ_STEP + 0.5) * ADJ_STEP
    ))
end
function Stats.prototype.lateRule(self)
    local offsets = self:offsets()
    if #offsets == 0 then
        return nil
    end
    local mean = Mean(offsets)
    local late = self:count(function(v) return self:isLate(v) end)
    if mean < BIAS_MIN_MEAN or late < BIAS_MIN_SHARE * self:attempts() then
        return nil
    end
    return {
        cost = late,
        line = ("you're late: start your swing about " .. self:adjustment(mean)) .. "s sooner"
    }
end
function Stats.prototype.earlyRule(self)
    local offsets = self:offsets()
    if #offsets == 0 then
        return nil
    end
    local mean = Mean(offsets)
    local early = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.kind == "EARLY" end
    )
    if mean > -BIAS_MIN_MEAN or #early < BIAS_MIN_SHARE * self:attempts() then
        return nil
    end
    local lost = #__TS__ArrayFilter(
        early,
        function(____, v) return self.gotIt[v.creepId] == false end
    )
    return {
        cost = lost,
        line = ("you're early: wait about " .. self:adjustment(mean)) .. "s longer before swinging"
    }
end
function Stats.prototype.harassRule(self)
    local g = self:harassGap()
    if g == nil or g.gap < HARASS_LEAK_GAP then
        return nil
    end
    return {
        cost = math.floor(g.gap / 100 * g.harassed.t + 0.5),
        line = "you lose timing when hit: back off or swing earlier under pressure"
    }
end
function Stats.prototype.denyRule(self)
    local dn = __TS__ArrayFilter(
        self.takeable,
        function(____, v) return v.isDeny end
    )
    local ok = #__TS__ArrayFilter(
        dn,
        function(____, v) return IsSuccess(v) end
    )
    if #dn < DENY_MIN or ok >= DENY_MAX_RATE * #dn then
        return nil
    end
    return {
        cost = #dn - ok,
        line = ((("denies " .. tostring(ok)) .. "/") .. tostring(#dn)) .. ": check allied creeps under half HP"
    }
end
return ____exports
