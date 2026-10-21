--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__ObjectAssign(target, ...)
    local sources = {...}
    for i = 1, #sources do
        local source = sources[i]
        for key in pairs(source) do
            target[key] = source[key]
        end
    end
    return target
end
-- End of Lua Library inline imports
local ____exports = {}
local teamOrders, release, removeAt, ackKey, onAccepted, ordersByTeam, version, MIN_LINE_GAP, ACK_PING_GAP, LANE_NAMES, lastLineAt, lastAckPingAt, avoidZones, botState, announcer
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
function teamOrders(team)
    local list = ordersByTeam[team]
    if list == nil then
        list = {}
        ordersByTeam[team] = list
    end
    return list
end
function release(order)
    version = version + 1
    local zone = avoidZones[order.id]
    if zone ~= nil then
        avoidZones[order.id] = nil
        RemoveAvoidanceZone(zone)
    end
end
function removeAt(list, i)
    release(list[i + 1])
    __TS__ArraySplice(list, i, 1)
end
function ____exports.OrderLocation(order)
    if order.target ~= nil and order.target:CanBeSeen() and order.target:IsAlive() then
        return order.target:GetLocation()
    end
    return order.location
end
function ____exports.CancelAll(team)
    local list = teamOrders(team)
    do
        local i = #list - 1
        while i >= 0 do
            removeAt(list, i)
            i = i - 1
        end
    end
end
--- The first non-declined responder speaks for the team so only one bot acknowledges.
function ____exports.IsSpokesperson(bot, order)
    for ____, pid in ipairs(order.responders) do
        local ____opt_2 = botState[pid]
        local state = ____opt_2 and ____opt_2[order.id]
        if state == nil or state.declined == nil then
            return pid == bot:GetPlayerID()
        end
    end
    return false
end
function ____exports.HasTeleportReady(bot)
    local tp = bot:GetItemInSlot(15)
    return tp ~= nil and tp ~= nil and tp:IsFullyCastable()
end
function ackKey(order)
    local base = "say_order_ack_" .. string.lower(order.type)
    local lane = order.lane ~= nil and LANE_NAMES[order.lane] or nil
    return lane ~= nil and (order.type == "DEFEND" or order.type == "PUSH") and (base .. "_") .. lane or base
end
function onAccepted(bot, order)
    if order.type == "AVOID" and avoidZones[order.id] == nil and order.location ~= nil then
        local left = math.max(
            0,
            order.expiresAt - GameTime()
        )
        avoidZones[order.id] = AddAvoidanceZone(
            Vector(order.location.x, order.location.y, order.radius or 0),
            left
        )
    end
    if not ____exports.IsSpokesperson(bot, order) then
        return
    end
    ____exports.Say(
        bot,
        ackKey(order)
    )
    local loc = ____exports.OrderLocation(order)
    local pid = bot:GetPlayerID()
    if order.ackPing == true and loc ~= nil and GameTime() - (lastAckPingAt[pid] or -ACK_PING_GAP) >= ACK_PING_GAP then
        lastAckPingAt[pid] = GameTime()
        bot:ActionImmediate_Ping(loc.x, loc.y, true)
    end
end
function ____exports.CanSay(bot)
    return GameTime() - (lastLineAt[bot:GetPlayerID()] or -MIN_LINE_GAP) >= MIN_LINE_GAP
end
--- Team-chat line for humaniser features; at most one per bot per MIN_LINE_GAP. Returns false if suppressed.
function ____exports.Say(bot, key, cooldown)
    if announcer == nil or not ____exports.CanSay(bot) then
        return false
    end
    lastLineAt[bot:GetPlayerID()] = GameTime()
    announcer(
        bot,
        key,
        cooldown or Config.Get().Orders.AckCooldown
    )
    return true
end
local PRIORITY = {
    BACK = 8,
    AVOID = 7,
    DEFEND = 6,
    ROSHAN = 5,
    ATTACK = 4,
    SMOKE = 3,
    GATHER = 2,
    PUSH = 1,
    RELEASE = 0
}
ordersByTeam = {}
local seenSourceKeys = {}
local nextId = 1
version = 0
MIN_LINE_GAP = 10
ACK_PING_GAP = 10
local COMMIT_MIN_HP = 0.5
local COMMIT_RETREAT_MARGIN = 0.1
LANE_NAMES = {[Lane.Top] = "top", [Lane.Mid] = "mid", [Lane.Bot] = "bot"}
lastLineAt = {}
lastAckPingAt = {}
avoidZones = {}
botState = {}
local function prune(team)
    local list = teamOrders(team)
    local now = GameTime()
    do
        local i = #list - 1
        while i >= 0 do
            if list[i + 1].expiresAt <= now then
                removeAt(list, i)
            end
            i = i - 1
        end
    end
end
local function teamBots(team)
    local result = {}
    local players = GetTeamPlayers(team)
    do
        local i = 1
        while i <= #players do
            local member = GetTeamMember(i)
            if member ~= nil and member ~= nil and member:IsBot() and not member:IsIllusion() then
                result[#result + 1] = member
            end
            i = i + 1
        end
    end
    return result
end
local function hasTeleportByPID(team, pid)
    for ____, member in ipairs(teamBots(team)) do
        if member:GetPlayerID() == pid then
            return ____exports.HasTeleportReady(member)
        end
    end
    return false
end
local function rankResponders(spec, team)
    local loc = spec.location or (spec.target ~= nil and spec.target:GetLocation() or nil)
    local candidates = {}
    for ____, member in ipairs(teamBots(team)) do
        do
            local __continue20
            repeat
                local pid = member:GetPlayerID()
                if spec.onlyPIDs ~= nil and __TS__ArrayIndexOf(spec.onlyPIDs, pid) < 0 then
                    __continue20 = true
                    break
                end
                local dist = loc ~= nil and GetUnitToLocationDistance(member, loc) or 0
                if spec.maxDistance ~= nil and spec.maxDistance > 0 and dist > spec.maxDistance then
                    __continue20 = true
                    break
                end
                candidates[#candidates + 1] = {pid, dist}
                __continue20 = true
            until true
            if not __continue20 then
                break
            end
        end
    end
    __TS__ArraySort(
        candidates,
        function(____, a, b) return a[2] ~= b[2] and a[2] - b[2] or a[1] - b[1] end
    )
    local responders = {}
    do
        local i = 0
        while i < #candidates do
            local pid, dist = unpack(candidates[i + 1])
            if i < spec.maxResponders or spec.alsoWithin ~= nil and dist <= spec.alsoWithin or spec.alsoTpBeyond ~= nil and dist > spec.alsoTpBeyond and hasTeleportByPID(team, pid) then
                responders[#responders + 1] = pid
            end
            i = i + 1
        end
    end
    return responders
end
--- Posts an order for the team and returns it. Re-posting the same sourceKey returns undefined.
-- An active order of the same type and lane is replaced. RELEASE cancels everything and is not stored.
function ____exports.Post(team, spec)
    if seenSourceKeys[spec.sourceKey] == true then
        return nil
    end
    seenSourceKeys[spec.sourceKey] = true
    if spec.type == "RELEASE" then
        ____exports.CancelAll(team)
        return nil
    end
    prune(team)
    local list = teamOrders(team)
    do
        local i = #list - 1
        while i >= 0 do
            if list[i + 1].type == spec.type and list[i + 1].lane == spec.lane then
                removeAt(list, i)
            end
            i = i - 1
        end
    end
    local now = GameTime()
    local ____spec_1 = spec
    local ____nextId_0 = nextId
    nextId = ____nextId_0 + 1
    local order = __TS__ObjectAssign(
        {},
        ____spec_1,
        {
            id = ____nextId_0,
            team = team,
            createdAt = now,
            expiresAt = now + spec.duration,
            responders = rankResponders(spec, team)
        }
    )
    list[#list + 1] = order
    version = version + 1
    Telemetry.Event(
        "order_post",
        {
            {"id", order.id},
            {"team", team},
            {"type", order.type},
            {"lane", order.lane},
            {"issuer", order.issuerPID},
            {
                "responders",
                table.concat(order.responders, ",")
            },
            {"dur", order.duration},
            {"kind", order.delayKind or "ping"},
            {"src", order.sourceKey}
        }
    )
    return order
end
function ____exports.Cancel(team, id)
    local list = teamOrders(team)
    do
        local i = #list - 1
        while i >= 0 do
            if list[i + 1].id == id then
                removeAt(list, i)
            end
            i = i - 1
        end
    end
end
function ____exports.GetActive(team)
    prune(team)
    return teamOrders(team)
end
local function stateFor(bot, order)
    local pid = bot:GetPlayerID()
    local perBot = botState[pid]
    if perBot == nil then
        perBot = {}
        botState[pid] = perBot
    end
    local state = perBot[order.id]
    if state == nil then
        state = {readAt = order.createdAt + Profile.SampleDelay(bot, order.delayKind or "ping")}
        perBot[order.id] = state
    end
    return state
end
function ____exports.IsResponder(bot, order)
    return __TS__ArrayIndexOf(
        order.responders,
        bot:GetPlayerID()
    ) >= 0
end
--- Why this bot cannot respond right now, or undefined if it can.
function ____exports.DeclineReason(bot, order)
    if order.type == "AVOID" then
        return nil
    end
    if not bot:IsAlive() then
        return "dead"
    end
    if bot:IsChanneling() then
        return "channeling"
    end
    if bot:GetActiveMode() == BotMode.Retreat and bot:GetHealth() / bot:GetMaxHealth() < 0.35 then
        return "low_hp"
    end
    if order.type == "DEFEND" or order.type == "ROSHAN" then
        local loc = ____exports.OrderLocation(order)
        if loc ~= nil and GetUnitToLocationDistance(bot, loc) > 5000 and not ____exports.HasTeleportReady(bot) then
            return "far"
        end
    end
    return nil
end
--- Marks this bot as accepting the order if it is a responder, has had time to read it, and can respond.
-- Returns false while the bot is still "reading", or if it declined.
function ____exports.TryAccept(bot, order)
    if not ____exports.IsResponder(bot, order) then
        return false
    end
    local state = stateFor(bot, order)
    if GameTime() < state.readAt then
        return false
    end
    if state.declined ~= nil then
        return false
    end
    local reason = ____exports.DeclineReason(bot, order)
    if reason ~= nil then
        state.declined = reason
        Telemetry.Event(
            "order_decline",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"id", order.id},
                {"type", order.type},
                {"reason", reason}
            }
        )
        ____exports.Say(bot, "say_order_decline_" .. reason)
        return false
    end
    if state.announced ~= true then
        state.announced = true
        Telemetry.Event(
            "order_accept",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"id", order.id},
                {"type", order.type},
                {"lane", order.lane},
                {"kind", order.delayKind or "ping"},
                {"read", state.readAt - order.createdAt},
                {
                    "latency",
                    GameTime() - order.createdAt
                }
            }
        )
        onAccepted(bot, order)
    end
    return true
end
--- jmz_func injects J.ModeAnnounce here; requiring jmz_func from this module would be circular.
function ____exports.SetAnnouncer(fn)
    announcer = fn
end
local forCache = {}
local function acceptedFor(bot)
    local pid = bot:GetPlayerID()
    local now = GameTime()
    local cache = forCache[pid]
    if cache ~= nil and cache.time == now and cache.version == version then
        return cache
    end
    local accepted = {}
    local best
    for ____, order in ipairs(____exports.GetActive(bot:GetTeam())) do
        do
            local __continue71
            repeat
                if not ____exports.TryAccept(bot, order) then
                    __continue71 = true
                    break
                end
                accepted[#accepted + 1] = order
                if order.type == "AVOID" then
                    __continue71 = true
                    break
                end
                if best == nil or PRIORITY[order.type] > PRIORITY[best.type] then
                    best = order
                end
                __continue71 = true
            until true
            if not __continue71 then
                break
            end
        end
    end
    cache = {time = now, version = version, best = best, accepted = accepted}
    forCache[pid] = cache
    return cache
end
--- Highest-priority order this bot has accepted and should execute (AVOID excluded), or undefined.
function ____exports.GetFor(bot)
    return acceptedFor(bot).best
end
--- An accepted order of the given type, e.g. AVOID alongside the order being executed.
function ____exports.GetAccepted(bot, ____type)
    for ____, order in ipairs(acceptedFor(bot).accepted) do
        if order.type == ____type then
            return order
        end
    end
    return nil
end
local function insideZone(order, loc)
    if order.location == nil then
        return false
    end
    local dx = loc.x - order.location.x
    local dy = loc.y - order.location.y
    local r = order.radius or 0
    return dx * dx + dy * dy <= r * r
end
--- True when this bot has read a danger ping whose zone covers `loc`.
function ____exports.AvoidsLocation(bot, loc)
    for ____, order in ipairs(acceptedFor(bot).accepted) do
        if order.type == "AVOID" and insideZone(order, loc) then
            return true
        end
    end
    return false
end
--- `units` without those inside a zone this bot avoids; the same table when nothing is removed.
function ____exports.FilterAvoided(bot, units)
    local avoiding = false
    for ____, order in ipairs(acceptedFor(bot).accepted) do
        if order.type == "AVOID" then
            avoiding = true
        end
    end
    if not avoiding then
        return units
    end
    local result = {}
    for ____, unit in ipairs(units) do
        if not ____exports.AvoidsLocation(
            bot,
            unit:GetLocation()
        ) then
            result[#result + 1] = unit
        end
    end
    return #result == #units and units or result
end
--- Caps retreat desire while the bot is committed to an accepted order and still healthy.
-- Also posts the cap as a HUMAN_ORDER claim, so Intent.Resolve keeps it above lower tiers.
function ____exports.CapRetreatDesire(bot, desire)
    if not Config.IsEnabled() then
        return desire
    end
    if bot:GetHealth() / bot:GetMaxHealth() <= COMMIT_MIN_HP then
        return desire
    end
    local order = ____exports.GetFor(bot)
    if order == nil or order.type == "BACK" then
        return desire
    end
    local cap = Config.Get().Orders.DesireFloor - COMMIT_RETREAT_MARGIN
    Intent.Claim(
        bot,
        {
            source = "orders:" .. order.type,
            tier = "HUMAN_ORDER",
            mode = BotMode.Retreat,
            cap = cap,
            ["until"] = GameTime()
        }
    )
    return math.min(desire, cap)
end
local function modeMatches(order, botMode, lane)
    repeat
        local ____switch100 = order.type
        local ____cond100 = ____switch100 == "GATHER" or ____switch100 == "ATTACK" or ____switch100 == "SMOKE" or ____switch100 == "BACK"
        if ____cond100 then
            return botMode == BotMode.Assemble
        end
        ____cond100 = ____cond100 or ____switch100 == "ROSHAN"
        if ____cond100 then
            return botMode == BotMode.Roshan
        end
        ____cond100 = ____cond100 or ____switch100 == "DEFEND"
        if ____cond100 then
            return (botMode == BotMode.DefendTowerTop or botMode == BotMode.DefendTowerMid or botMode == BotMode.DefendTowerBot) and (order.lane == nil or order.lane == lane)
        end
        ____cond100 = ____cond100 or ____switch100 == "PUSH"
        if ____cond100 then
            return (botMode == BotMode.PushTowerTop or botMode == BotMode.PushTowerMid or botMode == BotMode.PushTowerBot) and (order.lane == nil or order.lane == lane)
        end
        do
            return false
        end
    until true
end
--- The desire floor an accepted order gives this mode, else 0. Pure: posts no claim.
function ____exports.OrderFloor(bot, botMode, lane)
    if not Config.IsEnabled() then
        return 0
    end
    local order = ____exports.GetFor(bot)
    if order == nil or not modeMatches(order, botMode, lane) then
        return 0
    end
    return Config.Get().Orders.DesireFloor
end
--- OrderFloor, also posted as a same-frame HUMAN_ORDER claim so Intent.Resolve keeps it above lower tiers.
-- Call it only on the path that returns the floor: the claim must not outlive the call site's own gates.
function ____exports.DesireFloor(bot, botMode, lane)
    local floor = ____exports.OrderFloor(bot, botMode, lane)
    if floor > 0 then
        Intent.Claim(
            bot,
            {
                source = "orders:" .. ____exports.GetFor(bot).type,
                tier = "HUMAN_ORDER",
                mode = botMode,
                floor = floor,
                ["until"] = GameTime()
            }
        )
    end
    return floor
end
function ____exports.Describe(order)
    local left = math.max(
        0,
        order.expiresAt - GameTime()
    )
    local lane = order.lane ~= nil and " lane=" .. tostring(order.lane) or ""
    return (((((order.type .. "#") .. tostring(order.id)) .. lane) .. " ") .. string.format("%.0f", left)) .. "s"
end
return ____exports
