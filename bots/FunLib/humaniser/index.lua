--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local GameState = ____dota.GameState
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local Chat = require(GetScriptDirectory().."/FunLib/humaniser/chat")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local AllyLastHit = require(GetScriptDirectory().."/FunLib/humaniser/ally_last_hit")
local Pings = require(GetScriptDirectory().."/FunLib/humaniser/pings")
local Commands = require(GetScriptDirectory().."/FunLib/humaniser/commands")
local Lane = require(GetScriptDirectory().."/FunLib/humaniser/lane")
local LaneFight = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight")
local Transitions = require(GetScriptDirectory().."/FunLib/humaniser/transitions/transitions")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local LastHitSkill = require(GetScriptDirectory().."/FunLib/humaniser/last_hit_skill")
local FarmPattern = require(GetScriptDirectory().."/FunLib/humaniser/farm_pattern")
local Trainer = require(GetScriptDirectory().."/FunLib/humaniser/trainer/trainer")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local RegenObs = require(GetScriptDirectory().."/FunLib/humaniser/regen_obs")
local ApiProbe = require(GetScriptDirectory().."/FunLib/humaniser/api_probe")
local Perception = require(GetScriptDirectory().."/FunLib/humaniser/perception")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Etiquette = require(GetScriptDirectory().."/FunLib/humaniser/etiquette")
local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
local CoreCamp = require(GetScriptDirectory().."/FunLib/humaniser/core_camp")
local RunePickup = require(GetScriptDirectory().."/FunLib/humaniser/rune_pickup")
local RunePlan = require(GetScriptDirectory().."/FunLib/humaniser/rune_plan")
local Plays = require(GetScriptDirectory().."/FunLib/humaniser/plays/plays")
local PullFarm = require(GetScriptDirectory().."/FunLib/humaniser/pull_farm")
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local CampClaims = require(GetScriptDirectory().."/FunLib/humaniser/camp_claims")
local Chooser = require(GetScriptDirectory().."/FunLib/humaniser/chooser")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local States = require(GetScriptDirectory().."/FunLib/humaniser/states/index")
local CoreTrade = require(GetScriptDirectory().."/FunLib/humaniser/states/core_trade")
local LaneControl = require(GetScriptDirectory().."/FunLib/humaniser/lane_control")
local Retreat = require(GetScriptDirectory().."/FunLib/humaniser/retreat")
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
____exports.Transitions = Transitions
____exports.Intent = Intent
____exports.LastHitSkill = LastHitSkill
____exports.FarmPattern = FarmPattern
____exports.Trainer = Trainer
____exports.Telemetry = Telemetry
____exports.Ours = Ours
____exports.Etiquette = Etiquette
____exports.StackJob = StackJob
____exports.RuneJob = RuneJob
____exports.RunePickup = RunePickup
____exports.RunePlan = RunePlan
____exports.Plays = Plays
____exports.PullJob = PullJob
____exports.PullFarm = PullFarm
____exports.CampClaims = CampClaims
____exports.Chooser = Chooser
____exports.Overrides = Overrides
____exports.Drill = Drill
____exports.CoreCamp = CoreCamp
____exports.Tasks = Tasks
____exports.States = States
____exports.CoreTrade = CoreTrade
____exports.LaneControl = LaneControl
____exports.Retreat = Retreat
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
        if Transitions.IsActive() then
            HDebug.Text(
                bot,
                "phase",
                Transitions.Overlay(bot)
            )
        end
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
        if Tasks.IsActive() then
            HDebug.Text(
                bot,
                "task",
                Tasks.Describe(bot) or "-"
            )
        end
        if States.IsEnabled() then
            HDebug.Text(
                bot,
                "state",
                States.Describe(bot) or "-"
            )
        end
    end
    HDebug.Draw(bot)
end
local function tick(bot)
    if not Config.IsEnabled() then
        if Telemetry.IsEnabled() and bot:IsHero() and not bot:IsIllusion() then
            Telemetry.Tick(bot)
            pcall(RegenObs.Tick, bot)
        end
        return
    end
    if not bot:IsHero() or bot:IsIllusion() then
        return
    end
    Camps.FeedNeutralSpeeds(bot)
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
    Drill.Tick(bot)
    Retreat.Tick(bot)
    Pings.Tick(bot)
    Commands.Tick(bot)
    Lane.Tick(bot)
    LaneFight.Tick(bot)
    Transitions.Tick(bot)
    Trainer.Tick(bot)
    LastHitSkill.Tick(bot)
    Orders.GetFor(bot)
    Intent.Tick(bot)
    LaneControl.Tick(bot)
    Telemetry.Tick(bot, telemetryContext)
    pcall(RegenObs.Tick, bot)
    pcall(ApiProbe.Tick, bot)
    States.Tick(bot)
    Tasks.Tick(bot)
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
        "Transitions",
        Transitions,
        {
            Tick = none,
            MidRunesOn = no,
            MidRuneFocus = function() return false, false, nil end,
            MidRuneYield = none,
            MidRuneSkip = none,
            RuneTarget = none,
            HoldsRune = no,
            MidRuneDesire = zero,
            RotationYield = none,
            PickLaneWard = none,
            ConfirmLaneWard = none,
            FarmAllowedInLaning = no
        }
    )
    Telemetry.GuardModule("States", States, {
        Tick = none,
        Step = no,
        MayOwn = no,
        SetLaneSpot = none,
        Describe = none,
        IsEnabled = no,
        WisdomOwned = no,
        Owns = no,
        BodyLastHits = no,
        BodyBusy = no,
        BodySupportHits = no,
        BodySupportLastHits = no,
        SupportOwnsAttack = no,
        SupportStep = no
    })
    Telemetry.GuardModule("CoreTrade", CoreTrade, {
        Owns = no,
        Desire = none,
        OwnsFrame = no,
        Think = none,
        OnEnd = none,
        LastHitYields = no,
        TradeOwnsLaneRun = no,
        OwnsLaneFights = no
    })
    Telemetry.GuardModule("FarmPattern", FarmPattern, {Desire = zero, Think = no, OnEnd = none, Abort = none})
    Telemetry.GuardModule(
        "Etiquette",
        Etiquette,
        {
            Applies = no,
            CoreCanTake = function() return true end,
            MayLastHit = no,
            LeavesTarget = no
        }
    )
    Telemetry.GuardModule(
        "StackJob",
        StackJob,
        {
            Wants = no,
            Step = no,
            End = none,
            Running = no,
            NoteIdleHeld = none,
            NoteHit = none,
            Benched = no,
            Bench = no,
            Minutes = function() return StackJob.SETTINGS.TriggerMinutes end
        }
    )
    Telemetry.GuardModule(
        "Drill",
        Drill,
        {
            Tick = none,
            Held = no,
            Casts = no,
            Hold = no,
            LaneOnly = no,
            LaneHold = no,
            LaneAggro = no,
            IdleStatue = no,
            Owns = no,
            ForcedJob = none,
            ForcedAt = none,
            RoleOf = function() return "play" end,
            Implied = none,
            RepTimes = none,
            RepAt = zero,
            Name = none,
            Active = none
        }
    )
    Telemetry.GuardModule("Chooser", Chooser, {
        RunningJobName = none,
        Decide = none,
        FarmDesire = zero,
        FarmThink = no,
        Abort = none,
        HoldsRun = no,
        HoldsIdle = no,
        HoldsCasts = no,
        Benched = no,
        Bench = no
    })
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
    Telemetry.GuardModule("LaneControl", LaneControl, {Tick = none})
    Telemetry.GuardModule("Retreat", Retreat, {
        Desire = none,
        Think = none,
        Tick = none,
        Running = no,
        Owns = no,
        HoldsItem = no,
        On = no,
        Fountain = none,
        TowerOnUs = none,
        ResetCache = none
    })
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
