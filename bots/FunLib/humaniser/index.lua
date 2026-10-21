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
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local Trainer = require(GetScriptDirectory().."/FunLib/humaniser/trainer/trainer")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
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
____exports.Intent = Intent
____exports.Trainer = Trainer
____exports.Tasks = Tasks
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
        if Tasks.IsActive() then
            HDebug.Text(
                bot,
                "task",
                Tasks.Describe(bot) or "-"
            )
        end
    end
    HDebug.Draw(bot)
end
function ____exports.Tick(bot)
    if not Config.IsEnabled() then
        return
    end
    if not bot:IsHero() or bot:IsIllusion() then
        return
    end
    Chat.EnsureInstalled(bot)
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
    Trainer.Tick(bot)
    Orders.GetFor(bot)
    Intent.Tick(bot)
    Tasks.Tick(bot)
    HDebug.SharedStateProbe(bot)
    drawOverlay(bot)
end
return ____exports
