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
-- End of Lua Library inline imports
local ____exports = {}
local currentMinute, records
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local ____commands = require(GetScriptDirectory().."/FunLib/humaniser/commands")
local teamMembers = ____commands.teamMembers
local ____camps_data = require(GetScriptDirectory().."/FunLib/humaniser/camps_data")
local DEFAULT_STACK_SEC = ____camps_data.DEFAULT_STACK_SEC
function currentMinute()
    return math.floor(DotaTime() / 60)
end
function ____exports.IsStacked(campIdx)
    local rec = records[campIdx]
    return rec ~= nil and rec.minute >= currentMinute() - 1
end
function ____exports.StackCount(campIdx)
    return ____exports.IsStacked(campIdx) and records[campIdx].count or 0
end
function ____exports.ClearStack(campIdx)
    __TS__Delete(records, campIdx)
end
local rolls = {}
local before = {}
records = {}
local telegraphedAt = {}
--- Camps a bot's stack job has claimed, by camp then pid, until that job's walk-off ends (DotaTime). Per pid so a camp
-- both teams have a job on (an off-lane pull camp) keeps each team's claim; only allies' claims block.
local reservations = {}
function ____exports.ResetCache()
    rolls = {}
    before = {}
    records = {}
    telegraphedAt = {}
    reservations = {}
end
local function settings()
    return LaneConfig.Settings()
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
--- 7.41 stack windows (seconds to land the hit) from scripts/creep_pull_timings.txt in pak01_dir.vpk (read 22/10/2026,
-- what the `dota_hud_show_creep_spawn_camp_names` overlay shows), by the camp's spawner origin from maps/dota.vpk:
-- [x, y, stack_start, stack_end]. Camps 1,300+ apart, so WINDOW_MATCH cannot pick the wrong one.
local WINDOWS = {
    {-4824, 3915, 54, 56},
    {-3911, 4829, 55, 57},
    {1224, 4176, 55, 56},
    {1064, 2580, 55, 56},
    {-852, 4940, 54, 55},
    {7928, -120, 55, 56},
    {4352, 48, 53, 55},
    {3392, -1408, 53, 55},
    {-2880, 7376, 54, 56},
    {2016, 7896, 55, 57},
    {8430, 1263, 55, 56},
    {336, 7696, 55, 56},
    {-2596, 3850, 55, 56},
    {-4208, 8336, 55, 56},
    {3978, -5027, 55, 57},
    {4649, -3699, 52, 54},
    {186, -5197, 54, 55},
    {-1454, -3356, 55, 56},
    {-4013, 992, 53, 55},
    {-5015, -96, 52, 54},
    {-1983, -4815, 56, 57},
    {-720, -7696, 55, 57},
    {-2415, -8402, 53, 55},
    {-8313, -553, 55, 56},
    {2768, -8336, 55, 57},
    {1922, -3975, 56, 57},
    {-8023, -1838, 55, 56},
    {4416, -8432, 55, 56}
}
local WINDOW_MATCH = 300
--- Valve's stack window for the camp, or undefined (another map, a moved camp, StackFromValve off).
function ____exports.Window(campIdx)
    local spawner = Camps.SpawnerByIdx(campIdx)
    if spawner == nil or settings().Timing.StackFromValve ~= true then
        return nil, nil
    end
    for ____, w in ipairs(WINDOWS) do
        local dx = w[1] - spawner.location.x
        local dy = w[2] - spawner.location.y
        if dx * dx + dy * dy <= WINDOW_MATCH * WINDOW_MATCH then
            return w[3], w[4]
        end
    end
    return nil, nil
end
--- The second the stack hit should land: StackWindowAt through Valve's window for a camp on the type's default second,
-- else the data's (a replay or measured stack second is kept). The seeds (small 54.5 to ancient 53.0) were 1-2.5 s
-- early for most 7.41 camps (evil_2/good_1 55-57, evil_1 54-56) and 1.5 s late for good_2/good_8 (52-54).
function ____exports.AggroSec(data)
    local ____opt_0 = data.stack
    local sec = ____opt_0 and ____opt_0.aggroSec or DEFAULT_STACK_SEC[data.type]
    if sec ~= DEFAULT_STACK_SEC[data.type] then
        return sec
    end
    local from, to = ____exports.Window(data.campIdx)
    if from == nil or to == nil then
        return sec
    end
    return from + (to - from) * settings().Timing.StackWindowAt
end
local IDLE_MODES = {[BotMode.Laning] = true, [BotMode.Farm] = true, [BotMode.None] = true}
--- The safety half of Eligible; forced (debug) stack jobs check only this. `committed`: the stack is already under way,
-- so the partner check is LaneRoles.PartnerHolding instead of the start gate.
function ____exports.Safe(bot, s, enemies, committed)
    if committed == nil then
        committed = false
    end
    local t = settings().Thresholds
    local maxHP = bot:GetMaxHealth()
    if LaneConfig.InLaningPhase() then
        if committed then
            if maxHP <= 0 or bot:GetHealth() / maxHP <= t.StableMinHP then
                return false, "low-hp"
            end
            if s ~= nil then
                return LaneRoles.PartnerHolding(bot, s, enemies)
            end
            return true, "ok"
        end
        if not LaneRoles.LaneStable(bot, enemies) then
            return false, "unstable"
        end
        if s ~= nil and not LaneRoles.PartnerSafe(bot, s, enemies) then
            return false, "partner-unsafe"
        end
        return true, "ok"
    end
    if maxHP <= 0 or bot:GetHealth() / maxHP <= t.StableMinHP then
        return false, "low-hp"
    end
    local loc = bot:GetLocation()
    for ____, e in ipairs(enemies) do
        if e.visible and dist2D(e.location, loc) <= t.StableEnemyRadius then
            return false, "enemy-near"
        end
    end
    return true, "ok"
end
function ____exports.Eligible(bot, s, enemies, committed)
    if committed == nil then
        committed = false
    end
    if not LaneConfig.IsOn("Stack") then
        return false, "flag-off"
    end
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil or pos < 4 or pos > 5 then
        return false, "not-support"
    end
    if IDLE_MODES[bot:GetActiveMode()] ~= true then
        return false, "busy-mode"
    end
    if LaneConfig.InLaningPhase() then
        if s == nil then
            return false, "no-lane"
        end
    elseif Orders.GetFor(bot) ~= nil then
        return false, "has-order"
    end
    return ____exports.Safe(bot, s, enemies, committed)
end
--- Where a stack job waits: just outside the box on the exit side, so the walk-off starts away from the camp.
function ____exports.StandPoint(spawner, data)
    local ____opt_2 = data.stack
    local exit = ____opt_2 and ____opt_2.exitPath[1]
    return exit ~= nil and Camps.StandPoint(
        spawner,
        exit,
        settings().Radii.StandOffset
    ) or spawner.location
end
--- Claims `campIdx` for `pid`'s stack job so allies still choosing a camp skip it, not only once it stands in the box.
function ____exports.Reserve(campIdx, pid, ____until)
    reservations[campIdx] = reservations[campIdx] or ({})
    reservations[campIdx][pid] = ____until
end
function ____exports.Release(campIdx, pid)
    if reservations[campIdx] ~= nil then
        __TS__Delete(reservations[campIdx], pid)
    end
end
local function contested(bot, idx, enemies, allies)
    local margin = settings().Radii.BoxMargin
    for ____, e in ipairs(enemies) do
        if e.visible and Camps.InBox(idx, e.location, margin) then
            return true
        end
    end
    local pid = bot:GetPlayerID()
    local claims = reservations[idx] or ({})
    for ____, a in ipairs(allies) do
        do
            local __continue40
            repeat
                if a:GetPlayerID() == pid then
                    __continue40 = true
                    break
                end
                local ____until = claims[a:GetPlayerID()]
                if ____until ~= nil and DotaTime() < ____until then
                    return true
                end
                if a:IsAlive() and Camps.InBox(
                    idx,
                    a:GetLocation(),
                    margin
                ) then
                    return true
                end
                __continue40 = true
            until true
            if not __continue40 then
                break
            end
        end
    end
    return false
end
local function reachable(bot, data, minute)
    local spawner = Camps.SpawnerByIdx(data.campIdx)
    if spawner == nil or data.stack == nil then
        return false
    end
    local travel = GetUnitToLocationDistance(
        bot,
        ____exports.StandPoint(spawner, data)
    ) / math.max(
        bot:GetCurrentMovementSpeed(),
        1
    )
    return travel <= settings().Timing.MaxTravel and DotaTime() + travel <= minute * 60 + ____exports.AggroSec(data)
end
local function multiStackOk(bot, data)
    if ____exports.StackCount(data.campIdx) < settings().Thresholds.StackMaxCampCount then
        return true
    end
    return LaneConfig.SkillOf(bot) > settings().Gates.MultiStackAncients
end
--- Pull camp of our lane, then camps near our cores (by core position), then our ancients (nearest first).
function ____exports.ChooseCamp(bot, s, minute)
    local team = bot:GetTeam()
    local enemies = LaneState.Enemies(
        bot,
        s and s.lane or bot:GetAssignedLane()
    )
    local allies = teamMembers(team)
    local function ok(data)
        return not contested(bot, data.campIdx, enemies, allies) and reachable(bot, data, minute)
    end
    if s ~= nil and LaneConfig.InLaningPhase() then
        for ____, data in ipairs(Camps.PullCampsFor(s.team, s.lane)) do
            if ok(data) then
                return data
            end
        end
    end
    local camps = Camps.Resolve()
    local cores = {}
    for ____, a in ipairs(allies) do
        local pos = LaneConfig.PositionOf(a)
        if pos ~= nil and pos >= 1 and pos <= 3 and a:IsAlive() then
            cores[#cores + 1] = {pos = pos, unit = a}
        end
    end
    __TS__ArraySort(
        cores,
        function(____, a, b) return a.pos ~= b.pos and a.pos - b.pos or a.unit:GetPlayerID() - b.unit:GetPlayerID() end
    )
    local radius = settings().Radii.StackCoreCamp
    for ____, core in ipairs(cores) do
        local loc = core.unit:GetLocation()
        local best
        local bestDist = math.huge
        for ____, data in ipairs(camps) do
            do
                local __continue60
                repeat
                    if data.team ~= team or data.type == "ancient" then
                        __continue60 = true
                        break
                    end
                    local spawner = Camps.SpawnerByIdx(data.campIdx)
                    if spawner == nil or spawner.team ~= team then
                        __continue60 = true
                        break
                    end
                    local d = dist2D(
                        Camps.BoxCenter(spawner),
                        loc
                    )
                    if d <= radius and d < bestDist and ok(data) then
                        best = data
                        bestDist = d
                    end
                    __continue60 = true
                until true
                if not __continue60 then
                    break
                end
            end
        end
        if best ~= nil then
            return best
        end
    end
    local best
    local bestDist = math.huge
    for ____, data in ipairs(camps) do
        do
            local __continue67
            repeat
                if data.team ~= team or data.type ~= "ancient" then
                    __continue67 = true
                    break
                end
                local spawner = Camps.SpawnerByIdx(data.campIdx)
                if spawner == nil then
                    __continue67 = true
                    break
                end
                local d = GetUnitToLocationDistance(
                    bot,
                    Camps.BoxCenter(spawner)
                )
                if d < bestDist and multiStackOk(bot, data) and ok(data) then
                    best = data
                    bestDist = d
                end
                __continue67 = true
            until true
            if not __continue67 then
                break
            end
        end
    end
    return best
end
local function attemptRoll(bot, minute)
    local pid = bot:GetPlayerID()
    local r = rolls[pid]
    if r ~= nil and r.minute == minute then
        return r.ok
    end
    local ok = LaneConfig.Roll(LaneConfig.Curve(
        "StackAttempt",
        LaneConfig.SkillOf(bot)
    ))
    rolls[pid] = {minute = minute, ok = ok}
    return ok
end
--- Eligibility, then one attempt roll per minute (a `!stack` order skips the roll, not the safety checks).
function ____exports.WantsStack(bot, minute)
    if not LaneConfig.IsOn("Stack") then
        return nil
    end
    local s = LaneState.ForBot(bot)
    local enemies = LaneState.Enemies(
        bot,
        s and s.lane or bot:GetAssignedLane()
    )
    local eligible = ____exports.Eligible(bot, s, enemies)
    if not eligible then
        return nil
    end
    local view = s ~= nil and LanePlan.View(bot, s) or nil
    if view ~= nil and view.handsOff then
        return nil
    end
    local requested = view ~= nil and view.stackRequested
    if not requested and not attemptRoll(bot, minute) then
        return nil
    end
    return ____exports.ChooseCamp(bot, s, minute)
end
function ____exports.NoteStackAttempt(campIdx, _minute, countBefore)
    before[campIdx] = countBefore
    if countBefore == 0 then
        ____exports.ClearStack(campIdx)
    end
end
--- `countAfter` undefined: the box was not visible; `assumed` then decides (aggro timing in the safe band).
-- Returns whether the attempt counts as stacked.
function ____exports.NoteStackOutcome(campIdx, minute, countAfter, assumed)
    if assumed == nil then
        assumed = false
    end
    local prior = before[campIdx]
    __TS__Delete(before, campIdx)
    local ____temp_8
    if countAfter ~= nil then
        ____temp_8 = prior ~= nil and countAfter > prior
    else
        ____temp_8 = assumed
    end
    local stacked = ____temp_8
    if not stacked then
        return false
    end
    local prev = records[campIdx]
    local count = prev ~= nil and prev.minute == minute - 1 and prev.count + 1 or 1
    records[campIdx] = {minute = minute, count = count}
    return true
end
--- "stacked big camp" for allies of humans, at most once per StackTelegraphCooldown per bot.
function ____exports.Telegraph(bot, ____type)
    if ____type ~= "large" and ____type ~= "ancient" then
        return
    end
    if not LaneConfig.IsOn("Telegraph") or not Difficulty.IsAllyOfHuman(bot) then
        return
    end
    local pid = bot:GetPlayerID()
    local cooldown = settings().Timing.StackTelegraphCooldown
    local last = telegraphedAt[pid]
    if last ~= nil and GameTime() - last < cooldown then
        return
    end
    if Orders.Say(bot, "say_lane_stacked_big", cooldown) then
        telegraphedAt[pid] = GameTime()
    end
end
function ____exports.RegisterProbes()
    LaneHooks.SetStackedProbe(____exports.IsStacked)
end
____exports.RegisterProbes()
return ____exports
