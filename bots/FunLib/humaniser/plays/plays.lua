--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArraySetLength(self, length)
    if length < 0 or length ~= length or length == math.huge or math.floor(length) ~= length then
        error(
            "invalid array length: " .. tostring(length),
            0
        )
    end
    for i = length + 1, #self do
        self[i] = nil
    end
    return length
end

local function __TS__ArraySome(self, callbackfn, thisArg)
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            return true
        end
    end
    return false
end

local function __TS__ArrayIndexOf(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    if len == 0 then
        return -1
    end
    if fromIndex >= len then
        return -1
    end
    if fromIndex < 0 then
        fromIndex = len + fromIndex
        if fromIndex < 0 then
            fromIndex = 0
        end
    end
    for i = fromIndex + 1, len do
        if self[i] == searchElement then
            return i - 1
        end
    end
    return -1
end

local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__ArraySplice(self, ...)
    local args = {...}
    local len = #self
    local actualArgumentCount = __TS__CountVarargs(...)
    local start = args[1]
    local deleteCount = args[2]
    if start < 0 then
        start = len + start
        if start < 0 then
            start = 0
        end
    elseif start > len then
        start = len
    end
    local itemCount = actualArgumentCount - 2
    if itemCount < 0 then
        itemCount = 0
    end
    local actualDeleteCount
    if actualArgumentCount == 0 then
        actualDeleteCount = 0
    elseif actualArgumentCount == 1 then
        actualDeleteCount = len - start
    else
        actualDeleteCount = deleteCount or 0
        if actualDeleteCount < 0 then
            actualDeleteCount = 0
        end
        if actualDeleteCount > len - start then
            actualDeleteCount = len - start
        end
    end
    local out = {}
    for k = 1, actualDeleteCount do
        local from = start + k
        if self[from] ~= nil then
            out[k] = self[from]
        end
    end
    if itemCount < actualDeleteCount then
        for k = start + 1, len - actualDeleteCount do
            local from = k + actualDeleteCount
            local to = k + itemCount
            if self[from] then
                self[to] = self[from]
            else
                self[to] = nil
            end
        end
        for k = len - actualDeleteCount + itemCount + 1, len do
            self[k] = nil
        end
    elseif itemCount > actualDeleteCount then
        for k = len - actualDeleteCount, start + 1, -1 do
            local from = k + actualDeleteCount
            local to = k + itemCount
            if self[from] then
                self[to] = self[from]
            else
                self[to] = nil
            end
        end
    end
    local j = start + 1
    for i = 3, actualArgumentCount do
        self[j] = args[i]
        j = j + 1
    end
    for k = #self, len - actualDeleteCount + itemCount + 1, -1 do
        self[k] = nil
    end
    return out
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

local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
end
-- End of Lua Library inline imports
local ____exports = {}
local heroesOf, killedNear, line, kinds, active, settling
local FR = require(GetScriptDirectory().."/FunLib/humaniser/fight_readings")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function heroesOf(p)
    return {
        p.by,
        unpack(p.joiners)
    }
end
function killedNear(p)
    local t = p.target
    if not FR.Backed(t) or t:IsAlive() then
        return false
    end
    local at = t:GetLocation()
    return __TS__ArraySome(
        heroesOf(p),
        function(____, u) return FR.Alive(u) and FR.Dist(
            u:GetLocation(),
            at
        ) <= ____exports.SETTINGS.KillNear end
    )
end
--- The play's result so far from the units: kill (target dead with a play hero near), trade (that and the initiator dead),
-- died, forced (target low or moved far), else none. A target out of our vision reads as alive where it was.
function ____exports.Classify(p)
    local t = p.target
    local dead = FR.Backed(t) and not t:IsAlive()
    local died = not p.by:IsAlive()
    if dead and died then
        return "trade"
    end
    if dead and killedNear(p) then
        return "kill"
    end
    if died then
        return "died"
    end
    if FR.Alive(t) then
        if FR.HpFraction(t) < ____exports.SETTINGS.ForcedHp and (p.targetHp0 or 1) >= ____exports.SETTINGS.ForcedHp then
            return "forced"
        end
        if p.targetAt0 ~= nil and FR.Dist(
            t:GetLocation(),
            p.targetAt0
        ) > ____exports.SETTINGS.ForcedMoved then
            return "forced"
        end
    end
    return "none"
end
function line(p, res, why, ended)
    Telemetry.Event(
        "play_end",
        {
            {"id", p.id},
            {
                "pid",
                p.by:GetPlayerID()
            },
            {"kind", p.kind},
            {"tgt", p.tgt},
            {"res", res},
            {"why", why},
            {"join", #p.joiners},
            {
                "dur",
                math.floor((ended - p.started) * 10) / 10
            }
        }
    )
end
--- Ends a play once: it leaves the team's running plays now. With `res` given, or a result that cannot change (kill,
-- trade, died), the line is written now; otherwise it settles for KillAfter seconds so a kill just after the end counts.
function ____exports.End(p, why, res, now)
    if now == nil then
        now = DotaTime()
    end
    local idx = __TS__ArrayIndexOf(active, p)
    if idx < 0 then
        return
    end
    __TS__ArraySplice(active, idx, 1)
    local r = res or ____exports.Classify(p)
    if res ~= nil or r == "kill" or r == "trade" or r == "died" or p.target == nil then
        line(p, r, why, now)
    else
        settling[#settling + 1] = {play = p, why = why, ended = now}
    end
end
--- Ends every play past its kind's timeout and writes settled lines. Called from Roll and by consumers each frame.
function ____exports.Tick(now)
    if now == nil then
        now = DotaTime()
    end
    for ____, p in ipairs({unpack(active)}) do
        local def = kinds[p.kind]
        if def ~= nil and now - p.started >= def.timeout then
            ____exports.End(p, "timeout", nil, now)
        end
    end
    for ____, s in ipairs({unpack(settling)}) do
        local r = ____exports.Classify(s.play)
        if r == "kill" or r == "trade" or now - s.ended >= ____exports.SETTINGS.KillAfter then
            __TS__ArraySplice(
                settling,
                __TS__ArrayIndexOf(settling, s),
                1
            )
            line(s.play, r, s.why, s.ended)
        end
    end
end
--- The running play this hero is in, as its initiator or a joiner: such a hero is driven by the play.
function ____exports.Of(u)
    return __TS__ArrayFind(
        active,
        function(____, p) return p.by == u or __TS__ArrayIncludes(p.joiners, u) end
    )
end
____exports.SETTINGS = {
    MaxWeight = 0.9,
    Radius = 1600,
    PerLevel = 0.15,
    LevelClamp = {0.4, 1.6},
    CountUp = 1.3,
    CountDown = 0.5,
    HpFloor = 0.4,
    HpLow = 0.6,
    ManaShare = 0.2,
    TargetLow = 0.4,
    TargetHigh = 0.7,
    TargetLowFactor = 1.6,
    TargetHighFactor = 0.8,
    Rune = 1.4,
    TowerZero = 700,
    TowerNear = 1500,
    TowerFactor = 0.5,
    ForecastClamp = {0.5, 1.5},
    KillAfter = 5,
    KillNear = 1200,
    ForcedHp = 0.3,
    ForcedMoved = 1200
}
kinds = {}
--- Registers (or replaces) a kind. Consumers call it at load.
function ____exports.Define(kind, def)
    kinds[kind] = def
end
function ____exports.DefOf(kind)
    return kinds[kind]
end
--- The sure tier both lane commits and rune fights use: a target at or under TargetLow HP, within `reach`, with our heroes
-- at least even. A kind passes `SureKill(reach)` as its `sure`.
function ____exports.SureKill(reach)
    return function(i) return i.targetHp ~= nil and i.targetHp <= ____exports.SETTINGS.TargetLow and i.reach ~= nil and i.reach <= reach and i.ours >= i.theirs and "low-target" or nil end
end
local function clamp(v, lo, hi)
    return math.max(
        lo,
        math.min(hi, v)
    )
end
local function targetFactor(hp)
    local s = ____exports.SETTINGS
    if hp == nil then
        return 1
    end
    if hp <= s.TargetLow then
        return s.TargetLowFactor
    end
    if hp >= s.TargetHigh then
        return s.TargetHighFactor
    end
    return s.TargetLowFactor + (hp - s.TargetLow) / (s.TargetHigh - s.TargetLow) * (s.TargetHighFactor - s.TargetLowFactor)
end
function ____exports.Weigh(i)
    local s = ____exports.SETTINGS
    local def = kinds[i.kind]
    local level = clamp(1 + s.PerLevel * (i.ourLevel - i.theirLevel), s.LevelClamp[1], s.LevelClamp[2])
    local up = i.ours - i.theirs
    local count = up >= 1 and s.CountUp or (up == 0 and 1 or (up == -1 and s.CountDown or 0))
    local hpPart = i.hp < s.HpFloor and 0 or (i.hp >= s.HpLow and 1 or (i.hp - s.HpFloor) / (s.HpLow - s.HpFloor))
    local hp = hpPart * (1 - s.ManaShare + s.ManaShare * clamp(i.mana, 0, 1))
    local target = targetFactor(i.targetHp)
    local rune = i.rune and s.Rune or 1
    local chases = (def and def.chases) == true
    local tower = chases and i.tower < s.TowerZero and 0 or (chases and i.tower < s.TowerNear and s.TowerFactor or 1)
    local forecast = i.forecast ~= nil and clamp(i.forecast, s.ForecastClamp[1], s.ForecastClamp[2]) or 1
    local ____temp_6
    if def == nil then
        ____temp_6 = "unknown-kind"
    else
        local ____temp_5
        if i.hp < s.HpFloor then
            ____temp_5 = "hp"
        else
            local ____temp_4
            if up <= -2 then
                ____temp_4 = "outnumbered"
            else
                local ____temp_3
                if tower == 0 then
                    ____temp_3 = "tower"
                else
                    local ____temp_2
                    if def.zero ~= nil then
                        ____temp_2 = def.zero(i)
                    else
                        ____temp_2 = nil
                    end
                    ____temp_3 = ____temp_2
                end
                ____temp_4 = ____temp_3
            end
            ____temp_5 = ____temp_4
        end
        ____temp_6 = ____temp_5
    end
    local zero = ____temp_6
    local w = zero ~= nil and 0 or clamp(def.base * level * count * hp * target * rune * tower * forecast, 0, s.MaxWeight)
    local ____temp_7
    if zero == nil and def.sure ~= nil then
        ____temp_7 = def.sure(i)
    else
        ____temp_7 = nil
    end
    local sure = ____temp_7
    local commit = sure ~= nil and LaneConfig.Curve("SureCommit", i.skill) or nil
    return {
        w = w,
        level = level,
        count = count,
        hp = hp,
        target = target,
        rune = rune,
        tower = tower,
        forecast = forecast,
        zero = zero,
        sure = sure,
        commit = commit
    }
end
local nextId = 1
active = {}
settling = {}
function ____exports.ResetCache()
    nextId = 1
    __TS__ArraySetLength(active, 0)
    __TS__ArraySetLength(settling, 0)
end
--- Gathers a chance's inputs from the shared fight readings.
function ____exports.InputsOf(c)
    local r = ____exports.SETTINGS.Radius
    local ours = FR.AlliesNear(c.at, r, {c.by})
    local theirs = FR.EnemiesNear(c.at, r, c.target ~= nil and ({c.target}) or ({}))
    local target = FR.Alive(c.target) and c.target or nil
    return {
        kind = c.kind,
        ourLevel = FR.AverageLevel(ours),
        theirLevel = #theirs > 0 and FR.AverageLevel(theirs) or FR.AverageLevel(ours),
        ours = #ours,
        theirs = #theirs,
        hp = FR.HpFraction(c.by),
        mana = FR.ManaFraction(c.by),
        targetHp = target ~= nil and FR.HpFraction(target) or nil,
        rune = FR.HoldsPowerRune(c.by),
        tower = target ~= nil and FR.TowerDistance(
            target:GetTeam(),
            target:GetLocation()
        ) or math.huge,
        forecast = c.forecast,
        reach = target ~= nil and FR.Dist(
            c.by:GetLocation(),
            target:GetLocation()
        ) or nil,
        skill = LaneConfig.SkillOf(c.by)
    }
end
local function r2(x)
    return math.floor(x * 100 + 0.5) / 100
end
--- Offers one chance: weighs it and logs `ev=play`. A sure chance commits with no weighted roll: at skill 1 with no draw at
-- all, below it on one draw under Curve SureCommit (with no engine rng it commits). Any other chance draws once from the
-- engine's Skill rng against its weight. Returns the fired play, or undefined (a hard zero, the draw above the weight or
-- the commit chance, a hero already in a play, or no engine rng for a weighted chance: never a host-side draw).
function ____exports.Roll(c, now)
    if now == nil then
        now = DotaTime()
    end
    ____exports.Tick(now)
    local i = ____exports.InputsOf(c)
    local wt = ____exports.Weigh(i)
    local busy = ____exports.Of(c.by) ~= nil
    local sure = wt.sure ~= nil and not busy
    local chance = sure and wt.commit or wt.w
    local ____temp_8
    if chance > 0 and chance < 1 and not busy then
        ____temp_8 = LaneConfig.Draw()
    else
        ____temp_8 = nil
    end
    local draw = ____temp_8
    local ____sure_9
    if sure then
        ____sure_9 = chance >= 1 or draw == nil or draw < chance
    else
        ____sure_9 = draw ~= nil and draw < chance
    end
    local fire = ____sure_9
    local why = wt.zero or (busy and "in-play" or (not sure and wt.w > 0 and draw == nil and "no-rng" or nil))
    local play
    if fire then
        local target = FR.Alive(c.target) and c.target or nil
        local ____nextId_10 = nextId
        nextId = ____nextId_10 + 1
        play = {
            id = ____nextId_10,
            kind = c.kind,
            by = c.by,
            target = c.target,
            tgt = c.target ~= nil and c.target:GetPlayerID() or -1,
            at = c.at,
            started = now,
            joiners = {},
            targetHp0 = target ~= nil and FR.HpFraction(target) or nil,
            targetAt0 = target ~= nil and target:GetLocation() or nil
        }
        active[#active + 1] = play
    end
    Telemetry.Event(
        "play",
        {
            {
                "pid",
                c.by:GetPlayerID()
            },
            {"kind", c.kind},
            {
                "tgt",
                c.target ~= nil and c.target:GetPlayerID() or -1
            },
            {
                "w",
                r2(wt.w)
            },
            {
                "fl",
                r2(wt.level)
            },
            {
                "fc",
                r2(wt.count)
            },
            {
                "fh",
                r2(wt.hp)
            },
            {
                "fth",
                r2(wt.target)
            },
            {
                "fr",
                r2(wt.rune)
            },
            {
                "ft",
                r2(wt.tower)
            },
            {
                "ff",
                r2(wt.forecast)
            },
            {"al", i.ours},
            {"en", i.theirs},
            {"zero", why},
            {"sure", wt.sure},
            {
                "pc",
                wt.commit ~= nil and r2(wt.commit) or nil
            },
            {
                "draw",
                draw ~= nil and r2(draw) or nil
            },
            {"fire", fire and 1 or 0},
            {"id", play and play.id}
        }
    )
    return play
end
--- The team's running plays, optionally of one kind.
function ____exports.Active(kind)
    return __TS__ArrayFilter(
        active,
        function(____, p) return kind == nil or p.kind == kind end
    )
end
--- Running plays whose place is within `radius` of `at` ("a fired play near me"), optionally of one kind.
function ____exports.Near(at, radius, kind)
    return __TS__ArrayFilter(
        active,
        function(____, p) return (kind == nil or p.kind == kind) and FR.Dist(p.at, at) <= radius end
    )
end
--- A hero from any context signs up for a running play (its own decision); counted on the play's end line.
function ____exports.Join(p, u)
    if not __TS__ArrayIncludes(active, p) or ____exports.Of(u) ~= nil then
        return false
    end
    local ____p_joiners_13 = p.joiners
    ____p_joiners_13[#____p_joiners_13 + 1] = u
    return true
end
return ____exports
