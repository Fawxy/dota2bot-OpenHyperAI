--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__ArraySlice(self, first, last)
    local len = #self
    first = first or 0
    if first < 0 then
        first = len + first
        if first < 0 then
            first = 0
        end
    else
        if first > len then
            first = len
        end
    end
    last = last or len
    if last < 0 then
        last = len + last
        if last < 0 then
            last = 0
        end
    else
        if last > len then
            last = len
        end
    end
    local out = {}
    first = first + 1
    last = last + 1
    local n = 1
    while first < last do
        out[n] = self[first]
        first = first + 1
        n = n + 1
    end
    return out
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local GameState = ____dota.GameState
local Lane = ____dota.Lane
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Chat = require(GetScriptDirectory().."/FunLib/humaniser/chat")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Pings = require(GetScriptDirectory().."/FunLib/humaniser/pings")
local Trainer = require(GetScriptDirectory().."/FunLib/humaniser/trainer/trainer")
____exports.DEFAULTS = {
    Enable = true,
    Def = {Duration = 25, MaxResponders = 5},
    Push = {Duration = 30, MaxResponders = 3},
    Rosh = {Duration = 40, MaxResponders = 5},
    Group = {Duration = 15, MaxResponders = 5},
    Go = {Duration = 10, MaxResponders = 5, PingAge = 15, HeroRadius = 300},
    Smoke = {Duration = 30, MaxResponders = 5, AlliesNeeded = 3, AlliesRadius = 600},
    Back = {Duration = 8, Radius = 3000, EnemyRadius = 1500}
}
local function merge(defaults, overrides)
    if overrides == nil or overrides == nil or type(overrides) ~= "table" then
        return defaults
    end
    local result = {}
    for k, v in pairs(defaults) do
        result[k] = v
    end
    for k, v in pairs(overrides) do
        local d = defaults[k]
        local ____k_1 = k
        local ____temp_0
        if d ~= nil and type(d) == "table" and type(v) == "table" then
            ____temp_0 = merge(d, v)
        else
            ____temp_0 = v
        end
        result[____k_1] = ____temp_0
    end
    return result
end
local cached
function ____exports.Get()
    if cached == nil then
        cached = merge(
            ____exports.DEFAULTS,
            Config.Get().Commands
        )
    end
    return cached
end
function ____exports.IsActive()
    return Config.IsFeatureEnabled("Commands")
end
--- The pre-humaniser "everyone defend" command; still handled by aba_role.ShouldTpToDefend too.
____exports.LEGACY_DEFEND = "-都来守家"
local LANE_WORDS = {
    top = Lane.Top,
    t = Lane.Top,
    mid = Lane.Mid,
    m = Lane.Mid,
    middle = Lane.Mid,
    bot = Lane.Bot,
    b = Lane.Bot,
    bottom = Lane.Bot
}
--- top/mid/bot are map lanes, the same for both teams (Valve's LANE_* are absolute).
-- safe/off depend on the side: Radiant's safe lane is bot, Dire's is top.
function ____exports.ParseLane(word, team)
    if word == nil then
        return nil
    end
    local direct = LANE_WORDS[word]
    if direct ~= nil then
        return direct
    end
    local radiant = team == Team.Radiant
    if word == "safe" or word == "s" then
        return radiant and Lane.Bot or Lane.Top
    end
    if word == "off" or word == "o" then
        return radiant and Lane.Top or Lane.Bot
    end
    return nil
end
function ____exports.teamMembers(team)
    local result = {}
    local players = GetTeamPlayers(team)
    do
        local i = 1
        while i <= #players do
            local member = GetTeamMember(i)
            if member ~= nil and member ~= nil and not member:IsIllusion() then
                result[#result + 1] = member
            end
            i = i + 1
        end
    end
    return result
end
function ____exports.memberByPID(team, pid)
    for ____, member in ipairs(____exports.teamMembers(team)) do
        if member:GetPlayerID() == pid then
            return member
        end
    end
    return nil
end
local function lowestBotPID(team)
    local best
    for ____, pid in ipairs(GetTeamPlayers(team)) do
        if IsPlayerBot(pid) and (best == nil or pid < best) then
            best = pid
        end
    end
    return best
end
local function heroKey(unit)
    return (string.gsub(
        unit:GetUnitName(),
        "npc_dota_hero_",
        ""
    ))
end
--- "2" -> the team's second slot; "lion" / "crystal" / "crystalmaiden" -> a unique bot by hero name.
function ____exports.ResolveSelector(team, word)
    if string.len(word) < 1 then
        return nil
    end
    local players = GetTeamPlayers(team)
    local slot = tonumber(word)
    if slot ~= nil then
        local pid = players[slot]
        return pid ~= nil and IsPlayerBot(pid) and ({pid}) or nil
    end
    if string.len(word) < 3 then
        return nil
    end
    local exact = {}
    local partial = {}
    for ____, member in ipairs(____exports.teamMembers(team)) do
        do
            local __continue30
            repeat
                if not member:IsBot() then
                    __continue30 = true
                    break
                end
                local name = heroKey(member)
                local squashed = (string.gsub(name, "_", ""))
                if name == word or squashed == word then
                    exact[#exact + 1] = member:GetPlayerID()
                elseif (string.find(name, word, 1, true)) ~= nil or (string.find(squashed, word, 1, true)) ~= nil then
                    partial[#partial + 1] = member:GetPlayerID()
                end
                __continue30 = true
            until true
            if not __continue30 then
                break
            end
        end
    end
    if #exact == 1 then
        return exact
    end
    if #exact == 0 and #partial == 1 then
        return partial
    end
    return nil
end
local function enemyHeroNear(loc, radius)
    return Pings.NearestVisibleEnemyHero(loc, radius)
end
--- Lane whose creep front is closest to our ancient, with visible enemy heroes there weighing heavily.
function ____exports.MostThreatenedLane(team)
    local ancient = GetAncient(team)
    local enemies = GetUnitList(UnitType.EnemyHeroes)
    local best = Lane.Mid
    local bestScore = -math.huge
    for ____, lane in ipairs({Lane.Top, Lane.Mid, Lane.Bot}) do
        local front = GetLaneFrontLocation(team, lane, 0)
        local score = ancient ~= nil and ancient ~= nil and -GetUnitToLocationDistance(ancient, front) or 0
        for ____, enemy in ipairs(enemies) do
            if enemy ~= nil and enemy ~= nil and enemy:IsAlive() and enemy:CanBeSeen() and GetUnitToLocationDistance(enemy, front) <= 2500 then
                score = score + 10000
            end
        end
        if score > bestScore then
            best = lane
            bestScore = score
        end
    end
    return best
end
local function laneNearest(team, loc)
    local best = Lane.Mid
    local bestDist = math.huge
    for ____, lane in ipairs({Lane.Top, Lane.Mid, Lane.Bot}) do
        local front = GetLaneFrontLocation(team, lane, 0)
        local dx = front.x - loc.x
        local dy = front.y - loc.y
        local d = dx * dx + dy * dy
        if d < bestDist then
            best = lane
            bestDist = d
        end
    end
    return best
end
--- Nearest alive own tower to `loc` with no visible enemy hero close to it; falls back to our ancient.
function ____exports.SafeTowerLocation(team, loc)
    local cfg = ____exports.Get().Back
    local enemies = GetUnitList(UnitType.EnemyHeroes)
    local best
    local bestDist = math.huge
    do
        local id = 0
        while id <= 10 do
            do
                local __continue50
                repeat
                    local tower = GetTower(team, id)
                    if tower == nil or tower == nil or not tower:IsAlive() then
                        __continue50 = true
                        break
                    end
                    local threatened = false
                    for ____, enemy in ipairs(enemies) do
                        if enemy ~= nil and enemy ~= nil and enemy:IsAlive() and enemy:CanBeSeen() and GetUnitToUnitDistance(enemy, tower) <= cfg.EnemyRadius then
                            threatened = true
                            break
                        end
                    end
                    if threatened then
                        __continue50 = true
                        break
                    end
                    local tl = tower:GetLocation()
                    local d = (tl.x - loc.x) * (tl.x - loc.x) + (tl.y - loc.y) * (tl.y - loc.y)
                    if d < bestDist then
                        best = tl
                        bestDist = d
                    end
                    __continue50 = true
                until true
                if not __continue50 then
                    break
                end
            end
            id = id + 1
        end
    end
    return best or GetAncient(team):GetLocation()
end
function ____exports.HasSmoke(unit)
    local slot = unit:FindItemSlot("item_smoke_of_deceit")
    return slot ~= nil and slot >= 0 and slot <= 8
end
local pendingSay = {}
local function queueSay(team, key)
    local pid = lowestBotPID(team)
    if pid == nil then
        return
    end
    if pendingSay[pid] == nil then
        pendingSay[pid] = {}
    end
    local ____pendingSay_pid_2 = pendingSay[pid]
    ____pendingSay_pid_2[#____pendingSay_pid_2 + 1] = key
end
local function responders(ctx, normal)
    return ctx.onlyPIDs ~= nil and #ctx.onlyPIDs or normal
end
local function post(ctx, spec)
    return Orders.Post(
        ctx.team,
        __TS__ObjectAssign({}, spec, {sourceKey = ctx.sourceKey, issuerPID = ctx.issuerPID, onlyPIDs = ctx.onlyPIDs, delayKind = "chat"})
    )
end
local function release(ctx)
    Orders.Post(ctx.team, {
        type = "RELEASE",
        sourceKey = ctx.sourceKey .. ":release",
        issuerPID = ctx.issuerPID,
        duration = 0,
        maxResponders = 0
    })
end
local function laneCommand(name, ____type, duration)
    return {
        name = name,
        aliases = {},
        needsLanePlan = true,
        handler = function(ctx)
            local lane = ____exports.ParseLane(ctx.args[1], ctx.team) or laneNearest(
                ctx.team,
                ctx.issuer:GetLocation()
            )
            local pids = ctx.onlyPIDs or Orders.BotsAssignedTo(ctx.team, lane)
            if #pids == 0 then
                return
            end
            Orders.Post(
                ctx.team,
                {
                    type = ____type,
                    sourceKey = ctx.sourceKey,
                    issuerPID = ctx.issuerPID,
                    lane = lane,
                    duration = duration(),
                    maxResponders = #pids,
                    onlyPIDs = pids,
                    delayKind = "chat"
                }
            )
        end
    }
end
local COMMANDS = {
    {
        name = "def",
        aliases = {"defend"},
        handler = function(ctx)
            local cfg = ____exports.Get().Def
            local lane = ____exports.ParseLane(ctx.args[1], ctx.team) or ____exports.MostThreatenedLane(ctx.team)
            post(
                ctx,
                {
                    type = "DEFEND",
                    lane = lane,
                    location = GetLaneFrontLocation(ctx.team, lane, 0),
                    duration = cfg.Duration,
                    maxResponders = responders(ctx, cfg.MaxResponders)
                }
            )
        end
    },
    {
        name = "push",
        aliases = {},
        handler = function(ctx)
            local cfg = ____exports.Get().Push
            local lane = ____exports.ParseLane(ctx.args[1], ctx.team) or laneNearest(
                ctx.team,
                ctx.issuer:GetLocation()
            )
            post(
                ctx,
                {
                    type = "PUSH",
                    lane = lane,
                    location = GetLaneFrontLocation(ctx.team, lane, 0),
                    duration = cfg.Duration,
                    maxResponders = responders(ctx, cfg.MaxResponders)
                }
            )
        end
    },
    {
        name = "rosh",
        aliases = {"roshan"},
        handler = function(ctx)
            local cfg = ____exports.Get().Rosh
            local h = Pings.GetHelpers()
            local location = h ~= nil and h.roshanLocation() or nil
            post(
                ctx,
                {
                    type = "ROSHAN",
                    location = location,
                    duration = cfg.Duration,
                    maxResponders = responders(ctx, cfg.MaxResponders)
                }
            )
        end
    },
    {
        name = "group",
        aliases = {"g"},
        handler = function(ctx)
            local cfg = ____exports.Get().Group
            post(
                ctx,
                {
                    type = "GATHER",
                    location = ctx.issuer:GetLocation(),
                    duration = cfg.Duration,
                    maxResponders = responders(ctx, cfg.MaxResponders)
                }
            )
        end
    },
    {
        name = "go",
        aliases = {},
        handler = function(ctx)
            local cfg = ____exports.Get().Go
            local location
            local target
            local ping = ctx.issuer:GetMostRecentPing()
            if ping ~= nil and ping ~= nil and ping.time ~= 0 and GameTime() - ping.time <= cfg.PingAge then
                location = ping.location
                target = enemyHeroNear(location, cfg.HeroRadius)
            else
                local attackTarget = ctx.issuer:GetAttackTarget()
                if attackTarget ~= nil and attackTarget ~= nil and attackTarget:IsHero() and attackTarget:GetTeam() ~= ctx.team then
                    target = attackTarget
                    location = attackTarget:GetLocation()
                end
            end
            if location == nil then
                return
            end
            post(
                ctx,
                {
                    type = "ATTACK",
                    location = location,
                    target = target,
                    duration = cfg.Duration,
                    maxResponders = responders(ctx, cfg.MaxResponders)
                }
            )
        end
    },
    {
        name = "smoke",
        aliases = {},
        handler = function(ctx)
            local cfg = ____exports.Get().Smoke
            local anySmoke = false
            for ____, member in ipairs(____exports.teamMembers(ctx.team)) do
                if ____exports.HasSmoke(member) then
                    anySmoke = true
                end
            end
            if not anySmoke then
                queueSay(ctx.team, "say_cmd_no_smoke")
                return
            end
            post(
                ctx,
                {
                    type = "SMOKE",
                    target = ctx.issuer,
                    location = ctx.issuer:GetLocation(),
                    duration = cfg.Duration,
                    maxResponders = responders(ctx, cfg.MaxResponders)
                }
            )
        end
    },
    {
        name = "back",
        aliases = {},
        handler = function(ctx)
            local cfg = ____exports.Get().Back
            release(ctx)
            local pids = ctx.onlyPIDs
            if pids == nil then
                pids = {}
                for ____, member in ipairs(____exports.teamMembers(ctx.team)) do
                    if member:IsBot() and GetUnitToUnitDistance(member, ctx.issuer) <= cfg.Radius then
                        pids[#pids + 1] = member:GetPlayerID()
                    end
                end
            end
            if #pids == 0 then
                return
            end
            local location = ____exports.SafeTowerLocation(
                ctx.team,
                ctx.issuer:GetLocation()
            )
            Orders.Post(ctx.team, {
                type = "BACK",
                sourceKey = ctx.sourceKey,
                issuerPID = ctx.issuerPID,
                location = location,
                duration = cfg.Duration,
                maxResponders = #pids,
                onlyPIDs = pids,
                delayKind = "chat"
            })
        end
    },
    {
        name = "farm",
        aliases = {},
        handler = function(ctx)
            release(ctx)
            queueSay(ctx.team, "say_order_ack_release")
        end
    },
    {
        name = "trainer",
        aliases = {},
        handler = function(ctx) return Trainer.OnCommand(ctx.team, ctx.issuerPID, ctx.args) end
    },
    {
        name = "bhelp",
        aliases = {},
        handler = function(ctx)
            queueSay(ctx.team, "say_cmd_help")
            if LaneConfig.IsOn("Plan") then
                queueSay(ctx.team, "say_cmd_help_lane")
            end
        end
    },
    laneCommand(
        "freeze",
        "LANE_FREEZE",
        function() return LaneConfig.Settings().Orders.FreezeShove end
    ),
    laneCommand(
        "shove",
        "LANE_SHOVE",
        function() return LaneConfig.Settings().Orders.FreezeShove end
    ),
    laneCommand(
        "pull",
        "LANE_PULL",
        function() return LaneConfig.Settings().Orders.PullNoPull end
    ),
    laneCommand(
        "nopull",
        "LANE_NOPULL",
        function() return LaneConfig.Settings().Orders.PullNoPull end
    ),
    laneCommand(
        "stack",
        "LANE_STACK",
        function() return LaneConfig.Settings().Orders.Stack end
    )
}
local function findCommand(word)
    for ____, def in ipairs(COMMANDS) do
        do
            local __continue97
            repeat
                if def.needsLanePlan == true and not LaneConfig.IsOn("Plan") then
                    __continue97 = true
                    break
                end
                if def.name == word or __TS__ArrayIndexOf(def.aliases, word) >= 0 then
                    return def
                end
                __continue97 = true
            until true
            if not __continue97 then
                break
            end
        end
    end
    return nil
end
--- Parses "!def mid", "!2 push bot", "!lion def top", "!lion !def top" and the legacy defend line.
function ____exports.Parse(text, team)
    local trimmed = string.lower((string.gsub(text, "^%s*(.-)%s*$", "%1")))
    if trimmed == ____exports.LEGACY_DEFEND then
        return {name = "def", args = {}}
    end
    if not Chat.IsCommand(trimmed) then
        return nil
    end
    local words = {}
    for w in string.gmatch(
        string.sub(trimmed, 2),
        "%S+"
    ) do
        words[#words + 1] = w
    end
    if #words == 0 then
        return nil
    end
    local direct = findCommand(words[1])
    if direct ~= nil then
        return {
            name = direct.name,
            args = __TS__ArraySlice(words, 1)
        }
    end
    if #words < 2 then
        return nil
    end
    local onlyPIDs = ____exports.ResolveSelector(team, words[1])
    if onlyPIDs == nil then
        return nil
    end
    local second = string.sub(words[2], 1, 1) == "!" and string.sub(words[2], 2) or words[2]
    local def = findCommand(second)
    if def == nil or def.name == "bhelp" or def.name == "farm" or def.name == "trainer" then
        return nil
    end
    return {
        name = def.name,
        args = __TS__ArraySlice(words, 2),
        onlyPIDs = onlyPIDs
    }
end
local repeatCount = {}
local lastSummary = "-"
--- Chat hub subscriber for one team. Exported for tests.
function ____exports.HandleMessage(team, msg)
    if not ____exports.IsActive() or GetGameState() ~= GameState.GameInProgress then
        return
    end
    if IsPlayerBot(msg.pid) then
        return
    end
    local parsed = ____exports.Parse(msg.text, team)
    if parsed == nil then
        return
    end
    if __TS__ArrayIndexOf(
        GetTeamPlayers(team),
        msg.pid
    ) < 0 then
        HDebug.Log(
            "commands",
            (((("[WARN] ignoring '" .. msg.text) .. "' from player ") .. tostring(msg.pid)) .. ", not on team ") .. tostring(team)
        )
        return
    end
    if not msg.teamOnly then
        return
    end
    local issuer = ____exports.memberByPID(team, msg.pid)
    if issuer == nil then
        return
    end
    local countKey = (tostring(msg.pid) .. ":") .. string.lower(msg.text)
    local n = (repeatCount[countKey] or 0) + 1
    repeatCount[countKey] = n
    local def = findCommand(parsed.name)
    def.handler({
        team = team,
        issuerPID = msg.pid,
        issuer = issuer,
        args = parsed.args,
        onlyPIDs = parsed.onlyPIDs,
        sourceKey = (("cmd:" .. countKey) .. ":") .. tostring(n)
    })
    lastSummary = ((parsed.name .. (parsed.onlyPIDs ~= nil and " ->" .. tostring(parsed.onlyPIDs[1]) or "")) .. " by ") .. tostring(msg.pid)
    HDebug.Log("commands", lastSummary, msg.text)
    Telemetry.Event(
        "cmd",
        {
            {"by", msg.pid},
            {"team", team},
            {"name", parsed.name},
            {
                "args",
                table.concat(parsed.args, ",")
            },
            {
                "only",
                parsed.onlyPIDs ~= nil and table.concat(parsed.onlyPIDs, ",") or nil
            },
            {"text", msg.text}
        }
    )
end
--- Order-driven smoke: true for the one responder chosen to pop smoke (first responder holding one in an
-- active slot) once enough allied heroes are close. Called from ConsiderItemDesire['item_smoke_of_deceit'].
function ____exports.ShouldUseOrderedSmoke(bot)
    if not ____exports.IsActive() then
        return false
    end
    local order = Orders.GetAccepted(bot, "SMOKE")
    if order == nil or bot:HasModifier("modifier_smoke_of_deceit") then
        return false
    end
    local holder
    for ____, pid in ipairs(order.responders) do
        do
            local __continue120
            repeat
                local member = ____exports.memberByPID(
                    bot:GetTeam(),
                    pid
                )
                if member == nil then
                    __continue120 = true
                    break
                end
                local slot = member:FindItemSlot("item_smoke_of_deceit")
                if slot ~= nil and slot >= 0 and slot <= 5 then
                    holder = pid
                    break
                end
                __continue120 = true
            until true
            if not __continue120 then
                break
            end
        end
    end
    if holder ~= bot:GetPlayerID() then
        return false
    end
    local cfg = ____exports.Get().Smoke
    local near = 0
    for ____, ally in ipairs(GetUnitList(UnitType.AlliedHeroes)) do
        if ally ~= nil and ally ~= nil and ally:IsAlive() and not ally:IsIllusion() and GetUnitToUnitDistance(ally, bot) <= cfg.AlliesRadius then
            near = near + 1
        end
    end
    return near >= cfg.AlliesNeeded
end
local subscribedTeams = {}
function ____exports.Tick(bot)
    if not ____exports.IsActive() then
        return
    end
    local team = bot:GetTeam()
    if subscribedTeams[team] ~= true then
        subscribedTeams[team] = true
        Chat.Subscribe(
            "commands:" .. tostring(team),
            function(msg) return ____exports.HandleMessage(team, msg) end
        )
    end
    local queue = pendingSay[bot:GetPlayerID()]
    if queue ~= nil and #queue > 0 and Orders.CanSay(bot) then
        Orders.Say(
            bot,
            table.remove(queue, 1),
            0
        )
    end
    HDebug.Text(bot, "cmd", lastSummary)
end
return ____exports
