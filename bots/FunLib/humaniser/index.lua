--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
-- End of Lua Library inline imports
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local Chat = require(GetScriptDirectory().."/FunLib/humaniser/chat")
local DesireLog = require(GetScriptDirectory().."/FunLib/humaniser/desire_log")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local RegenObs = require(GetScriptDirectory().."/FunLib/humaniser/regen_obs")
local ApiProbe = require(GetScriptDirectory().."/FunLib/humaniser/api_probe")
local VisionMap = require(GetScriptDirectory().."/FunLib/humaniser/vision_map")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local StackJob = require(GetScriptDirectory().."/FunLib/humaniser/stack_job")
local RuneJob = require(GetScriptDirectory().."/FunLib/humaniser/rune_job")
local RunePickup = require(GetScriptDirectory().."/FunLib/humaniser/rune_pickup")
local RunePlan = require(GetScriptDirectory().."/FunLib/humaniser/rune_plan")
local Plays = require(GetScriptDirectory().."/FunLib/humaniser/plays/plays")
local PullFarm = require(GetScriptDirectory().."/FunLib/humaniser/pull_farm")
local PullJob = require(GetScriptDirectory().."/FunLib/humaniser/pull_job")
local SupportDeny = require(GetScriptDirectory().."/FunLib/humaniser/support_deny")
local Chooser = require(GetScriptDirectory().."/FunLib/humaniser/chooser")
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local ChoiceShadow = require(GetScriptDirectory().."/FunLib/humaniser/choice_shadow")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local States = require(GetScriptDirectory().."/FunLib/humaniser/states/index")
local Retreat = require(GetScriptDirectory().."/FunLib/humaniser/retreat")
local SustainGather = require(GetScriptDirectory().."/FunLib/humaniser/sustain_gather")
local SustainAct = require(GetScriptDirectory().."/FunLib/humaniser/sustain_act")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
local CastLog = require(GetScriptDirectory().."/FunLib/humaniser/cast_log")
____exports.Config = Config
____exports.HDebug = HDebug
____exports.Chat = Chat
____exports.LaneConfig = LaneConfig
____exports.Telemetry = Telemetry
____exports.Ours = Ours
____exports.StackJob = StackJob
____exports.RuneJob = RuneJob
____exports.RunePickup = RunePickup
____exports.RunePlan = RunePlan
____exports.Plays = Plays
____exports.PullJob = PullJob
____exports.PullFarm = PullFarm
____exports.Chooser = Chooser
____exports.Decider = Decider
____exports.Overrides = Overrides
____exports.Drill = Drill
____exports.ChoiceShadow = ChoiceShadow
____exports.Tasks = Tasks
____exports.States = States
____exports.Retreat = Retreat
____exports.SustainGather = SustainGather
____exports.SustainAct = SustainAct
____exports.SafeGather = SafeGather
local OVERLAY_REFRESH = 0.25
local overlayAt = {}
function ____exports.IsEnabled()
    return Config.IsEnabled()
end
local function telemetryContext(bot)
    return {
        by = DesireLog.Explain(
            bot,
            bot:GetActiveMode()
        ),
        competing = DesireLog.Competing(bot)
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
        HDebug.Text(
            bot,
            "desire",
            DesireLog.Explain(
                bot,
                bot:GetActiveMode()
            )
        )
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
local steps = {
    feed = Camps.FeedNeutralSpeeds,
    telemetry = Telemetry.Tick,
    regen = RegenObs.Tick,
    sustain = function(bot)
        if not SustainAct.Holds(bot) then
            SustainGather.Tick(bot)
        end
    end,
    landing = SafeGather.Tick,
    pullShadow = PullJob.Shadow,
    probe = ApiProbe.Tick,
    tasks = Tasks.Tick,
    overlay = drawOverlay
}
local frameAt
local frameNo = 0
local allSteps = true
--- Whether this frame runs every step (each Config TickEvery-th frame) or only the frame steps.
local function stepsDue()
    local now = GameTime()
    if now ~= frameAt then
        frameAt = now
        frameNo = frameNo + 1
        local every = Config.Get().TickEvery
        allSteps = every <= 1 or frameNo % every == 0
    end
    return allSteps
end
--- The steps that run on the frames between: each names what a lower rate would lose. Every other step reads the world
-- ten times a second: the modes that act on them run 3 to 6 times a second, and a step that counts time in tenths
-- (a teleport's settle) may be read a tick late.
local function frameSteps(bot)
    if Drill.Active() ~= nil then
        Drill.Tick(bot)
    end
    steps.telemetry(bot, telemetryContext, true)
    steps.overlay(bot)
end
local function tick(bot)
    local all = stepsDue()
    if not Config.IsEnabled() then
        if Telemetry.IsEnabled() and bot:IsHero() and not bot:IsIllusion() then
            Telemetry.Tick(bot, nil, not all)
            if all then
                pcall(RegenObs.Tick, bot)
            end
        end
        return
    end
    if not bot:IsHero() or bot:IsIllusion() then
        return
    end
    if not all then
        frameSteps(bot)
        return
    end
    steps.feed(bot)
    Chat.EnsureInstalled(bot)
    Chat.FlushDeferred(function(tag, line) return HDebug.Log(tag, line) end)
    Drill.Tick(bot)
    Retreat.Tick(bot)
    pcall(steps.landing, bot)
    steps.telemetry(bot, telemetryContext)
    pcall(CastLog.Tick, bot)
    pcall(steps.regen, bot)
    pcall(steps.sustain, bot)
    pcall(steps.pullShadow, bot)
    pcall(steps.probe, bot)
    pcall(VisionMap.Tick, bot)
    steps.tasks(bot)
    HDebug.SharedStateProbe(bot)
    steps.overlay(bot)
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
if Telemetry.GuardsEnabled() then
    Telemetry.GuardModule("States", States, {MayOwn = no, WisdomOwned = no})
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
            InLane = no,
            InLaneDenies = no,
            ForbidsItem = no,
            ForbidsCast = no,
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
    Telemetry.GuardModule("SustainGather", SustainGather, {Bought = none})
    Telemetry.GuardModule("SustainAct", SustainAct, {
        ItemThink = none,
        Holds = no,
        HoldsItem = no,
        HoldsBuy = no,
        OwnsCourier = no,
        Walking = no,
        Step = no,
        ResetCache = none
    })
    Telemetry.GuardModule("Retreat", Retreat, {
        Desire = none,
        Think = none,
        Tick = none,
        Running = no,
        Owns = no,
        On = no,
        Fountain = none,
        TowerOnUs = none,
        ResetCache = none
    })
end
if Telemetry.GuardsEnabled() then
    for k, fn in pairs(steps) do
        steps[k] = Telemetry.PerfStep("Tick:" .. k, fn)
    end
end
Telemetry.PerfDeepInstall()
if __TS__ArrayIndexOf(Decider.ROWS, SupportDeny.ROW) < 0 then
    if Telemetry.GuardsEnabled() then
        SupportDeny.ROW.applies = Telemetry.Guard("DenyRow.applies", SupportDeny.ROW.applies, no)
        SupportDeny.ROW.step = Telemetry.Guard(
            "DenyRow.step",
            SupportDeny.ROW.step,
            function() return true end
        )
    end
    local ____Decider_ROWS_0 = Decider.ROWS
    ____Decider_ROWS_0[#____Decider_ROWS_0 + 1] = SupportDeny.ROW
end
local guardedTick = Telemetry.GuardsEnabled() and Telemetry.Guard("Tick", tick) or tick
function ____exports.Tick(bot)
    guardedTick(bot)
end
return ____exports
