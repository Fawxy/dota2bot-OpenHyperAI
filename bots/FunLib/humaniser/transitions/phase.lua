--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Tower = ____dota.Tower
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local Commands = require(GetScriptDirectory().."/FunLib/humaniser/commands")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Trainer = require(GetScriptDirectory().."/FunLib/humaniser/trainer/trainer")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
____exports.SOURCE_PHASE = "transitions:phase"
____exports.FARM_ITEMS = {
    "item_maelstrom",
    "item_battle_fury",
    "item_radiance",
    "item_hand_of_midas",
    "item_mjollnir"
}
local T1 = {[Lane.Top] = Tower.Top1, [Lane.Mid] = Tower.Mid1, [Lane.Bot] = Tower.Bot1}
local states = {}
local laningReads = {}
local held = {}
function ____exports.ResetCache()
    states = {}
    laningReads = {}
    held = {}
end
local function stateOf(bot)
    local pid = bot:GetPlayerID()
    local st = states[pid]
    if st == nil then
        st = {checkAt = -math.huge, wasLaning = false, phaseEnded = false, jungleSaid = false}
        states[pid] = st
    end
    return st
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function towerDown(team, lane)
    local id = T1[lane]
    if id == nil then
        return false
    end
    local t = GetTower(team, id)
    return t == nil or t == nil or not t:IsAlive()
end
local function hasFarmItem(bot)
    for ____, name in ipairs(____exports.FARM_ITEMS) do
        local slot = bot:FindItemSlot(name)
        if slot ~= nil and slot >= 0 and slot <= 8 then
            return true
        end
    end
    return false
end
--- No enemy hero seen recently near our nearest jungle camp. With no camp known the jungle is not safe.
local function jungleSafe(bot)
    local cfg = Settings.Get()
    local team = bot:GetTeam()
    local loc = bot:GetLocation()
    local camp
    local best = math.huge
    for ____, sp in ipairs(Camps.Spawners()) do
        do
            local __continue13
            repeat
                if sp.team ~= team then
                    __continue13 = true
                    break
                end
                local c = Camps.BoxCenter(sp)
                local d = dist2D(c, loc)
                if d < best then
                    best = d
                    camp = c
                end
                __continue13 = true
            until true
            if not __continue13 then
                break
            end
        end
    end
    if camp == nil then
        return false
    end
    for ____, e in ipairs(LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )) do
        if (e.visible or e.timeSinceSeen <= cfg.JungleSeenWindow) and dist2D(e.location, camp) <= cfg.JungleCampRadius then
            return false
        end
    end
    return true
end
--- Why the bot is no longer laning ("phase", "tower", "smoke", "farm"), or undefined while it still is.
local function notLaningWhy(bot)
    if not LaneConfig.InLaningPhase() then
        return "phase"
    end
    local cfg = Settings.Get()
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    if towerDown(team, lane) or towerDown(team == 2 and 3 or 2, lane) then
        return "tower"
    end
    local pos = LaneConfig.PositionOf(bot)
    local now = Config.Now()
    if pos ~= nil and pos >= 4 then
        if bot:GetLevel() > cfg.SupportLevel and now >= cfg.SupportFrom and now <= cfg.SupportTo then
            if Commands.HasSmoke(bot) or Orders.GetAccepted(bot, "ATTACK") ~= nil or Orders.GetAccepted(bot, "SMOKE") ~= nil then
                return "smoke"
            end
        end
    elseif pos ~= nil and hasFarmItem(bot) and jungleSafe(bot) then
        return "farm"
    end
    return nil
end
function ____exports.IsLaningFor(bot)
    return notLaningWhy(bot) == nil
end
--- Whether the laning-phase transitions (caution and its callout, the TP reaction, support rotations) apply to this
-- bot: IsLaningFor with the Phase flag on, the global laning phase otherwise. Never for the trainer self-test bot.
-- Read at most once per Refresh, since the caution probes ask every frame.
function ____exports.LaningTransitions(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local r = laningReads[pid]
    if r ~= nil and now >= r.at and now - r.at < Settings.Get().Refresh then
        return r.value
    end
    local ____temp_1 = not Trainer.IsSelfTestBot(bot)
    if ____temp_1 then
        local ____Settings_IsOn_result_0
        if Settings.IsOn("Phase") then
            ____Settings_IsOn_result_0 = ____exports.IsLaningFor(bot)
        else
            ____Settings_IsOn_result_0 = LaneConfig.InLaningPhase()
        end
        ____temp_1 = ____Settings_IsOn_result_0
    end
    local value = ____temp_1
    laningReads[pid] = {at = now, value = value}
    return value
end
--- The value LaningTransitions last stored for this hero, without reading or storing anything; undefined when none was
-- stored in the last two seconds. For a caller that must not move the cache's clock (the shadow arbiter).
function ____exports.LaningTransitionsSeen(bot)
    local r = laningReads[bot:GetPlayerID()]
    local now = DotaTime()
    local ____temp_2
    if r ~= nil and now >= r.at and now - r.at <= 2 then
        ____temp_2 = r.value
    else
        ____temp_2 = nil
    end
    return ____temp_2
end
--- judgement: seconds between end checks of a held hero (LaningHeld).
local HELD_CHECK = 1
--- Why a held hero's laning ends (rework step 7): the clock exit (until D23), a tier-1 of its lane lost (ours or theirs).
local function heldEndWhy(bot)
    if not LaneConfig.InLaningPhase() then
        return "clock"
    end
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    if towerDown(team, lane) or towerDown(team == 2 and 3 or 2, lane) then
        return "tower"
    end
    return nil
end
--- Rework step 7 (`Ours.ArbiterDrive`, asked by the arbiter and our retreat): the hero is held from its first laning read
-- (LaningTransitions true) to an end event (heldEndWhy), and never again after it. Other not-laning reasons (a support's
-- smoke, a core's farm item) do not end it, and no read goes stale. The start and the end log `ev=arb` with `ph`.
function ____exports.LaningHeld(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local h = held[pid]
    if h == nil then
        h = {on = false, checkAt = -math.huge}
        held[pid] = h
    end
    if h.ended ~= nil then
        return false
    end
    if not h.on then
        if not ____exports.LaningTransitions(bot) then
            return false
        end
        h.on = true
        h.checkAt = now + HELD_CHECK
        Telemetry.Event("arb", {{"pid", pid}, {"ph", "own"}})
        return true
    end
    if now < h.checkAt then
        return true
    end
    h.checkAt = now + HELD_CHECK
    local why = heldEndWhy(bot)
    if why == nil then
        return true
    end
    h.on = false
    h.ended = why
    Telemetry.Event("arb", {{"pid", pid}, {"ph", "end"}, {"why", why}})
    return false
end
local function sample(bot, st)
    local why = notLaningWhy(bot)
    st.wasLaning = why == nil
    if why ~= st.laningWhy then
        st.laningWhy = why
        Telemetry.Event(
            "tr_laning",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"laning", why == nil},
                {"why", why}
            }
        )
    end
end
local function evaluate(bot, st)
    st.phaseEnded = false
    st.cap = nil
    if not LaneConfig.InLaningPhase() then
        return
    end
    if st.wasLaning then
        st.jungleSaid = false
        return
    end
    st.phaseEnded = true
    st.cap = ____exports.SOURCE_PHASE
    local pos = LaneConfig.PositionOf(bot)
    if not st.jungleSaid and pos ~= nil and pos <= 3 and Difficulty.IsAllyOfHuman(bot) then
        st.jungleSaid = Orders.Say(
            bot,
            "say_going_jungle",
            Settings.Get().SuggestCooldown
        )
    end
end
function ____exports.Tick(bot)
    if not Settings.IsOn("Phase") then
        Intent.Release(bot, ____exports.SOURCE_PHASE, BotMode.Laning)
        return
    end
    local st = stateOf(bot)
    local now = DotaTime()
    if now >= st.checkAt then
        st.checkAt = now + Settings.Get().Refresh
        sample(bot, st)
        evaluate(bot, st)
    end
    if st.cap == ____exports.SOURCE_PHASE then
        Intent.Claim(
            bot,
            {
                source = ____exports.SOURCE_PHASE,
                tier = "TRANSITION",
                mode = BotMode.Laning,
                cap = Settings.Get().LaningCap
            }
        )
    else
        Intent.Release(bot, ____exports.SOURCE_PHASE, BotMode.Laning)
    end
end
--- Farm-mode hook: a core whose laning has ended may farm.
function ____exports.FarmAllowedInLaning(bot)
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil or pos > 3 then
        return false
    end
    local st = states[bot:GetPlayerID()]
    if st == nil then
        return false
    end
    return Settings.IsOn("Phase") and st.phaseEnded
end
return ____exports
