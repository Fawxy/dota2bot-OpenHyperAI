--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local GameState = ____dota.GameState
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Chat = require(GetScriptDirectory().."/FunLib/humaniser/chat")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local AllyLastHit = require(GetScriptDirectory().."/FunLib/humaniser/ally_last_hit")
local Pings = require(GetScriptDirectory().."/FunLib/humaniser/pings")
local Commands = require(GetScriptDirectory().."/FunLib/humaniser/commands")
local Lane = require(GetScriptDirectory().."/FunLib/humaniser/lane")
local LaneFight = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local LastHitSkill = require(GetScriptDirectory().."/FunLib/humaniser/last_hit_skill")
local Trainer = require(GetScriptDirectory().."/FunLib/humaniser/trainer/trainer")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Perception = require(GetScriptDirectory().."/FunLib/humaniser/perception")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
____exports.Config = Config
____exports.HDebug = HDebug
____exports.Chat = Chat
____exports.Difficulty = Difficulty
____exports.Profile = Profile
____exports.Orders = Orders
____exports.AllyLastHit = AllyLastHit
____exports.Pings = Pings
____exports.Commands = Commands
____exports.Lane = Lane
____exports.LaneFight = LaneFight
____exports.Intent = Intent
____exports.LastHitSkill = LastHitSkill
____exports.Trainer = Trainer
____exports.Telemetry = Telemetry
local OVERLAY_REFRESH = 0.25
local startLogged = {}
local overlayAt = {}
local testHandlerTeams = {}
function ____exports.IsEnabled()
    return Config.IsEnabled()
end
local function teamMemberByPID(team, pid)
    local players = GetTeamPlayers(team)
    do
        local i = 1
        while i <= #players do
            local member = GetTeamMember(i)
            if member ~= nil and member ~= nil and member:GetPlayerID() == pid then
                return member
            end
            i = i + 1
        end
    end
    return nil
end
--- Debug-only smoke test for the Orders bus: "!htest gather" posts a GATHER at the issuer.
local function makeTestCommandHandler(team)
    return function(msg)
        if not Config.Get().Debug or IsPlayerBot(msg.pid) then
            return
        end
        if string.lower(msg.text) ~= "!htest gather" then
            return
        end
        local issuer = teamMemberByPID(team, msg.pid)
        if issuer == nil then
            return
        end
        Orders.Post(
            team,
            {
                type = "GATHER",
                sourceKey = (("htest:" .. tostring(msg.pid)) .. ":") .. string.format("%.2f", msg.time),
                issuerPID = msg.pid,
                location = issuer:GetLocation(),
                duration = 8,
                maxResponders = 2
            }
        )
        HDebug.Log(
            "orders",
            "htest gather posted by " .. tostring(msg.pid)
        )
    end
end
local function logStart(bot)
    local pid = bot:GetPlayerID()
    if startLogged[pid] == true or GetGameState() ~= GameState.GameInProgress then
        return
    end
    startLogged[pid] = true
    local fret = Difficulty.GetFret(bot)
    local profile = Profile.Get(bot)
    local rawPrint = Utils.RawPrint
    local line = (((((((((((((((("[Humaniser] pid=" .. tostring(pid)) .. " ") .. bot:GetUnitName()) .. " valve=") .. tostring(bot:GetDifficulty())) .. " fret=") .. tostring(fret.active)) .. "/") .. tostring(fret.level)) .. "/") .. tostring(fret.allyScale)) .. "(") .. fret.source) .. ") allyOfHuman=") .. tostring(Difficulty.IsAllyOfHuman(bot))) .. " skill=") .. string.format("%.2f", profile.skill);
    (rawPrint or print)(line)
end
local function telemetryContext(bot)
    local order = Orders.GetFor(bot)
    return {
        by = Intent.IsActive() and Intent.Explain(
            bot,
            bot:GetActiveMode()
        ) or nil,
        order = order ~= nil and Orders.Describe(order) or nil,
        competing = Intent.IsActive() and Intent.Competing(bot) or nil
    }
end
local function drawOverlay(bot)
    if not HDebug.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    local now = GameTime()
    if now - (overlayAt[pid] or -1) >= OVERLAY_REFRESH then
        overlayAt[pid] = now
        local profile = Profile.Get(bot)
        local fret = Difficulty.GetFret(bot)
        HDebug.Text(
            bot,
            "skill",
            (string.format("%.2f", profile.skill) .. " fret=") .. (fret.active and ((((tostring(fret.level) .. "x") .. tostring(fret.allyScale)) .. "(") .. fret.source) .. ")" or "off")
        )
        HDebug.Text(
            bot,
            "delay",
            (("notice=" .. string.format("%.2f", profile.noticeBase)) .. " react=") .. string.format("%.2f", profile.reactBase)
        )
        local order = Orders.GetFor(bot)
        HDebug.Text(
            bot,
            "order",
            order ~= nil and Orders.Describe(order) or "-"
        )
        local avoid = Orders.GetAccepted(bot, "AVOID")
        HDebug.Text(
            bot,
            "avoid",
            avoid ~= nil and Orders.Describe(avoid) or "-"
        )
        if Intent.IsActive() then
            HDebug.Text(
                bot,
                "intent",
                Intent.Explain(
                    bot,
                    bot:GetActiveMode()
                )
            )
        end
        if LaneFight.IsActive() and LaneFight.Config.AppliesTo(bot) then
            HDebug.Text(
                bot,
                "fight",
                LaneFight.Describe(bot)
            )
        end
        if LastHitSkill.IsActiveFor(bot) then
            local cs = LastHitSkill.Counts(bot)
            HDebug.Text(
                bot,
                "cs",
                string.format(
                    "e=%.3f attempts=%d misses=%d",
                    LastHitSkill.ErrorWidth(bot),
                    cs.attempts,
                    cs.misses
                )
            )
        end
    end
    HDebug.Draw(bot)
end
local function tick(bot)
    if not Config.IsEnabled() then
        if Telemetry.IsEnabled() and bot:IsHero() and not bot:IsIllusion() then
            Telemetry.Tick(bot)
        end
        return
    end
    if not bot:IsHero() or bot:IsIllusion() then
        return
    end
    Chat.EnsureInstalled(bot)
    Chat.FlushDeferred(function(tag, line) return HDebug.Log(tag, line) end)
    Difficulty.Init()
    if testHandlerTeams[bot:GetTeam()] ~= true then
        testHandlerTeams[bot:GetTeam()] = true
        Chat.Subscribe(
            "htest:" .. tostring(bot:GetTeam()),
            makeTestCommandHandler(bot:GetTeam())
        )
    end
    logStart(bot)
    Pings.Tick(bot)
    Commands.Tick(bot)
    Lane.Tick(bot)
    LaneFight.Tick(bot)
    Trainer.Tick(bot)
    LastHitSkill.Tick(bot)
    Orders.GetFor(bot)
    Intent.Tick(bot)
    Telemetry.Tick(bot, telemetryContext)
    HDebug.SharedStateProbe(bot)
    drawOverlay(bot)
end
local function none()
    return nil
end
local function no()
    return false
end
local function zero()
    return 0
end
local function arg1(a)
    return a
end
local function arg2(_a, b)
    return b
end
if Telemetry.GuardsEnabled() then
    Telemetry.GuardModule(
        "Intent",
        Intent,
        {Resolve = function(_bot, _mode, raw) return raw end}
    )
    Telemetry.GuardModule("Lane", Lane, {
        CampJobDesire = zero,
        CampJobRawDesire = arg2,
        CampJobThink = no,
        CampJobOnEnd = none,
        CampJobAbort = none,
        CampJobHoldsRetreat = no,
        CampJobHoldsCasts = no,
        RuneContestDesire = zero,
        PreferStackedCamp = none,
        PreThink = no,
        Think = no,
        HarassThink = no,
        AdjustPosition = arg2
    })
    Telemetry.GuardModule(
        "LaneFight",
        LaneFight,
        {
            Tick = none,
            ReadFor = function() return {noticed = false} end,
            CheckKill = none,
            RoamDesire = arg2,
            Think = no,
            Target = none
        }
    )
    Telemetry.GuardModule(
        "AllyLastHit",
        AllyLastHit,
        {
            FilterCreeps = arg2,
            MayLastHit = function() return true, "free: error" end
        }
    )
    Telemetry.GuardModule("Orders", Orders, {
        FilterAvoided = arg2,
        AvoidsLocation = no,
        CapRetreatDesire = arg2,
        OrderFloor = zero,
        DesireFloor = zero
    })
    Telemetry.GuardModule("Commands", Commands, {ShouldUseOrderedSmoke = no})
    Telemetry.GuardModule(
        "Perception",
        Perception,
        {
            FilterNearbyEnemies = arg2,
            FilterUnitList = arg1,
            FilterChanneling = arg2,
            IsCastKnown = function() return true end,
            GetIncomingTrackingProjectiles = function(target) return target:GetIncomingTrackingProjectiles() end
        }
    )
end
local guardedTick = Telemetry.GuardsEnabled() and Telemetry.Guard("Tick", tick) or tick
function ____exports.Tick(bot)
    guardedTick(bot)
end
return ____exports
