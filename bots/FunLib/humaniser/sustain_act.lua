--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
end

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

local function __TS__ObjectKeys(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = key
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local UnitType = ____dota.UnitType
local Sustain = require(GetScriptDirectory().."/FunLib/humaniser/sustain")
local SustainGather = require(GetScriptDirectory().."/FunLib/humaniser/sustain_gather")
local ItemUse = require(GetScriptDirectory().."/FunLib/humaniser/item_use")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Phase = require(GetScriptDirectory().."/FunLib/humaniser/transitions/phase")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {
    DecideEvery = 0.5,
    DecideHit = 0.1,
    StartWait = 1.5,
    Arrive = 100,
    YieldFresh = 0.3
}
--- Cast on our own hero (OHA's cast type `unit` for these); a tree item on its tree; any other item has no target.
local SELF = {item_flask = true, item_clarity = true}
local acts = {}
local decidedAt = {}
local yieldedAt = {}
--- A hero sustain carries: the switch, a laner we hold, and no drill hold on its items (a lane-only cast without `castItems`, a rig's hold).
function ____exports.Holds(bot)
    if not Ours.On("Sustain") or bot:IsIllusion() or not Phase.LaningHeld(bot) or Drill.Held(bot) then
        return false
    end
    if Drill.RigHoldsCasts(bot, true) == true then
        return false
    end
    return not (Overrides.LaneOnly(bot) and not Drill.CastItems(bot))
end
--- OHA's item loop and roam's tango skip this item on this hero: every heal and mana item sustain reads, on a hero it carries.
function ____exports.HoldsItem(bot, name)
    return SustainGather.ITEMS[name] ~= nil and ____exports.Holds(bot)
end
--- The item's charges over slots 0-8; one held with no charge count (a shared tango, an empty wand) counts a half, so its use or a last charge's still shows as a fall.
local function chargesOf(bot, name)
    local n = 0
    do
        local s = 0
        while s <= 8 do
            do
                local __continue7
                repeat
                    local it = bot:GetItemInSlot(s)
                    if it == nil or it == nil or it:GetName() ~= name then
                        __continue7 = true
                        break
                    end
                    local c = it:GetCurrentCharges() or 0
                    n = n + (c > 0 and c or 0.5)
                    __continue7 = true
                until true
                if not __continue7 then
                    break
                end
            end
            s = s + 1
        end
    end
    return n
end
local function itemIn(bot, slot, name)
    local it = bot:GetItemInSlot(slot)
    return it ~= nil and it ~= nil and it:GetName() == name and it:IsFullyCastable() and it or nil
end
local function allyOf(pid)
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        if a ~= nil and a ~= nil and not a:IsNull() and a:IsAlive() and not a:IsIllusion() and a:GetPlayerID() == pid then
            return a
        end
    end
    return nil
end
--- A walk can be carried now: the laning mode holds the hero (its `sustain` row steps it), or a camp job's supply step yields.
local function carried(bot, now)
    if bot:GetActiveMode() == BotMode.Laning then
        return true
    end
    local y = yieldedAt[bot:GetPlayerID()]
    return y ~= nil and now - y <= ____exports.SETTINGS.YieldFresh
end
--- A walk may start: as `carried`, or a camp job runs whose supply step will yield to it.
local function canWalk(bot, now)
    return carried(bot, now) or CampJobs.Active(bot)
end
local function r1(v)
    return math.floor(v * 10 + 0.5) / 10
end
local function n0(v)
    return math.floor(v + 0.5)
end
local function ____end(bot, why)
    local pid = bot:GetPlayerID()
    local a = acts[pid]
    if a == nil then
        return
    end
    acts[pid] = nil
    if not Telemetry.IsEnabled() then
        return
    end
    Telemetry.Event(
        "sustain",
        {
            {"pid", pid},
            {"k", a.kind},
            {"it", a.item},
            {"to", a.to},
            {"why", a.why},
            {
                "hp0",
                n0(a.hp0)
            },
            {
                "hp1",
                n0(bot:GetHealth())
            },
            {
                "mp0",
                n0(a.mp0)
            },
            {
                "mp1",
                n0(bot:GetMana())
            },
            {
                "sec",
                r1(DotaTime() - a.at)
            },
            {"ed", why},
            {
                "wk",
                a.walk > 0 and r1(a.walk) or nil
            }
        }
    )
end
--- Gives the attempt's order for this frame (a walk's order again while it runs).
local function order(bot, a)
    local item = itemIn(bot, a.slot, a.item)
    if item == nil then
        return
    end
    if a.kind == "step_out_use" then
        if a.spot == nil or a.drunk == true then
            return
        end
        if GetUnitToLocationDistance(bot, a.spot) > ____exports.SETTINGS.Arrive then
            bot:Action_MoveToLocation(a.spot)
            return
        end
        a.drunk = true
        if a.run ~= nil then
            a.run.started = DotaTime()
        end
        if SELF[a.item] == true then
            ItemUse.UseOnSelf(bot, item)
        else
            ItemUse.UseNoTarget(bot, item)
        end
        return
    end
    if bot:GetCurrentActionType() == BOT_ACTION_TYPE_USE_ABILITY and a.at < DotaTime() then
        return
    end
    if a.kind == "give" then
        local ____temp_0
        if a.to ~= nil then
            ____temp_0 = allyOf(a.to)
        else
            ____temp_0 = nil
        end
        local ally = ____temp_0
        if ally ~= nil then
            ItemUse.UseOnAlly(bot, item, ally)
        end
    elseif a.tree ~= nil then
        ItemUse.UseOnTree(bot, item, a.tree)
    elseif SELF[a.item] == true then
        ItemUse.UseOnSelf(bot, item)
    else
        ItemUse.UseNoTarget(bot, item)
    end
end
--- Starts the answer's attempt, if it is one this step carries out and its order can be given now.
local function start(bot, i, ans, now)
    if ans.kind ~= "use" and ans.kind ~= "step_out_use" and ans.kind ~= "give" or ans.slot == nil or ans.name == nil then
        return
    end
    local name = "item_" .. ans.name
    local item = itemIn(bot, ans.slot, name)
    if item == nil then
        return
    end
    local a = {
        kind = ans.kind,
        item = name,
        slot = ans.slot,
        why = ans.reason,
        at = now,
        hp0 = i.hp,
        mp0 = i.mp,
        charges0 = chargesOf(bot, name),
        walk = 0,
        deadline = now + ____exports.SETTINGS.StartWait
    }
    local ____temp_3 = ans.kind == "use"
    if ____temp_3 then
        local ____opt_1 = SustainGather.ITEMS[name]
        ____temp_3 = (____opt_1 and ____opt_1.tree) == true
    end
    if ____temp_3 then
        local t = SustainGather.TreeOf(bot)
        if t == nil or i.tree == nil then
            return
        end
        a.tree = t.id
        a.walk = i.tree.walk
    elseif ans.kind == "step_out_use" then
        if ans.at == nil or i.safeSpot == nil then
            return
        end
        a.spot = Vector(
            ans.at.x,
            ans.at.y,
            bot:GetLocation().z
        )
        a.walk = i.safeSpot.walk
        local it = __TS__ArrayFind(
            i.items,
            function(____, x) return x.slot == ans.slot end
        )
        a.run = {
            kind = "step_out_use",
            slot = ans.slot,
            name = ans.name,
            started = now,
            hp0 = i.hp,
            dur = a.walk + (it and it.dur or 0),
            at = ans.at
        }
    elseif ans.kind == "give" then
        local ____temp_6
        if ans.to ~= nil then
            ____temp_6 = allyOf(ans.to)
        else
            ____temp_6 = nil
        end
        local ally = ____temp_6
        if ally == nil then
            return
        end
        a.to = ans.to
        a.walk = math.max(
            0,
            GetUnitToUnitDistance(bot, ally) - item:GetCastRange()
        ) / math.max(
            100,
            bot:GetCurrentMovementSpeed()
        )
    end
    if a.walk > 0 and not canWalk(bot, now) then
        return
    end
    a.deadline = now + a.walk + ____exports.SETTINGS.StartWait
    acts[bot:GetPlayerID()] = a
    order(bot, a)
end
--- One frame of a running attempt: true once it has ended.
local function progress(bot, a, now)
    if a.kind == "step_out_use" then
        if a.drunk ~= true and not carried(bot, now) and now > a.at then
            ____end(bot, "cut")
            return true
        end
        local pid = bot:GetPlayerID()
        local last = decidedAt[pid]
        if last ~= nil and now - last < ____exports.SETTINGS.DecideEvery then
            return false
        end
        decidedAt[pid] = now
        local i = SustainGather.Gather(bot, a.run)
        local ans = Sustain.Decide(i)
        SustainGather.Cut(bot, i, ans, true)
        if ans.reason ~= "running" then
            ____end(bot, ans.ended or "done")
            return true
        end
        local ____temp_11 = a.drunk ~= true
        if ____temp_11 then
            local ____now_10 = now
            local ____a_deadline_9 = a.deadline
            local ____opt_7 = a.run
            ____temp_11 = ____now_10 > ____a_deadline_9 + (____opt_7 and ____opt_7.dur or 0)
        end
        if ____temp_11 then
            ____end(bot, "missed")
            return true
        end
        return false
    end
    if chargesOf(bot, a.item) < a.charges0 then
        ____end(bot, "started")
        return true
    end
    if a.walk > 0 and not carried(bot, now) and now > a.at then
        ____end(bot, "cut")
        return true
    end
    if now > a.deadline then
        ____end(bot, "missed")
        return true
    end
    return false
end
--- ItemUsageThink's call (ability_item_usage_generic.lua), every hero every frame: nothing unless sustain carries the hero.
-- A running attempt is stepped; else, at DecideEvery (DecideHit under hits), Decide's answer is started and logged.
function ____exports.ItemThink(bot)
    local pid = bot:GetPlayerID()
    if not bot:IsAlive() then
        ____end(bot, "dead")
        return
    end
    if not ____exports.Holds(bot) then
        ____end(bot, "released")
        return
    end
    local now = DotaTime()
    local hit = bot:WasRecentlyDamagedByAnyHero(1)
    local a = acts[pid]
    if a ~= nil and not progress(bot, a, now) and not hit then
        return
    end
    local last = decidedAt[pid]
    if last ~= nil and now - last < (hit and ____exports.SETTINGS.DecideHit or ____exports.SETTINGS.DecideEvery) then
        return
    end
    decidedAt[pid] = now
    SustainGather.NoteCourier(bot)
    local i = SustainGather.Gather(bot)
    local ans = Sustain.Decide(i)
    local running = acts[pid]
    if running ~= nil then
        if ans.reason ~= "survive" or running.why == "survive" then
            return
        end
        ____end(bot, "cut")
    end
    SustainGather.Cut(bot, i, ans, true)
    start(bot, i, ans, now)
end
--- The lane table's `sustain` row: an attempt not yet under way wants the frame, a walk or not (smoke 1: 6 of 49 tangos with
-- the tree in range were never eaten, the body's move given after the cast); a step out once it has drunk does not.
function ____exports.Walking(bot)
    local a = acts[bot:GetPlayerID()]
    if a == nil then
        return false
    end
    return a.kind ~= "step_out_use" or a.drunk ~= true
end
--- The row's run: the walk's order again. True: the frame is taken.
function ____exports.Step(bot)
    local a = acts[bot:GetPlayerID()]
    if a == nil then
        return false
    end
    order(bot, a)
    return true
end
--- camp_jobs' supply step under `Ours.Sustain`: true while an attempt walks, its order given, so the job leaves the frame to it.
function ____exports.Yield(bot)
    if not ____exports.Walking(bot) then
        return false
    end
    yieldedAt[bot:GetPlayerID()] = DotaTime()
    return ____exports.Step(bot)
end
--- Per game: the attempts and the cadence.
function ____exports.ResetCache()
    for ____, k in ipairs(__TS__ObjectKeys(acts)) do
        __TS__Delete(acts, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(decidedAt)) do
        __TS__Delete(decidedAt, k)
    end
    for ____, k in ipairs(__TS__ObjectKeys(yieldedAt)) do
        __TS__Delete(yieldedAt, k)
    end
end
____exports._test = {acts = acts}
return ____exports
