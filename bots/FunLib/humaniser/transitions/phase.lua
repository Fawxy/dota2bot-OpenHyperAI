--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Tower = ____dota.Tower
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local Commands = require(GetScriptDirectory().."/FunLib/humaniser/commands")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Pings = require(GetScriptDirectory().."/FunLib/humaniser/pings")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Trainer = require(GetScriptDirectory().."/FunLib/humaniser/trainer/trainer")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
____exports.SOURCE_PHASE = "transitions:phase"
____exports.SOURCE_LOST = "transitions:lostlane"
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
function ____exports.ResetCache()
    states = {}
    laningReads = {}
end
local function stateOf(bot)
    local pid = bot:GetPlayerID()
    local st = states[pid]
    if st == nil then
        st = {
            record = {deaths = {}, lastHits = {}},
            checkAt = -math.huge,
            wasLaning = false,
            levelSeen = {},
            phaseEnded = false,
            lostResp = false,
            capStarted = false,
            jungleSaid = false
        }
        states[pid] = st
    end
    return st
end
function ____exports.Record(bot)
    return stateOf(bot).record
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
            local __continue14
            repeat
                if sp.team ~= team then
                    __continue14 = true
                    break
                end
                local c = Camps.BoxCenter(sp)
                local d = dist2D(c, loc)
                if d < best then
                    best = d
                    camp = c
                end
                __continue14 = true
            until true
            if not __continue14 then
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
function ____exports.IsLaningFor(bot)
    if not LaneConfig.InLaningPhase() then
        return false
    end
    local cfg = Settings.Get()
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    if towerDown(team, lane) or towerDown(team == 2 and 3 or 2, lane) then
        return false
    end
    local pos = LaneConfig.PositionOf(bot)
    local now = DotaTime()
    if pos ~= nil and pos >= 4 then
        if bot:GetLevel() > cfg.SupportLevel and now >= cfg.SupportFrom and now <= cfg.SupportTo then
            if Commands.HasSmoke(bot) or Orders.GetAccepted(bot, "ATTACK") ~= nil or Orders.GetAccepted(bot, "SMOKE") ~= nil then
                return false
            end
        end
    elseif pos ~= nil and hasFarmItem(bot) and jungleSafe(bot) then
        return false
    end
    return true
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
function ____exports.LaneLostPure(i)
    local cfg = Settings.Get()
    if i.deathsInWindow >= cfg.LostDeaths then
        return true, "deaths"
    end
    if i.expectedLhPerMin > 0 and i.lhPerMin / i.expectedLhPerMin < cfg.LostLHRatio then
        return true, "lasthits"
    end
    if i.levelGap >= cfg.LostLevelGap then
        return true, "levels"
    end
    return false, ""
end
local function lastHits(bot)
    return bot:GetLastHits()
end
local function pruneRecord(r, now)
    local from = now - Settings.Get().LostWindow
    r.deaths = __TS__ArrayFilter(
        r.deaths,
        function(____, t) return t >= from end
    )
    r.lastHits = __TS__ArrayFilter(
        r.lastHits,
        function(____, h) return h.at >= from end
    )
end
--- Highest lane opponent level minus ours, from visible units or the last level seen; 0 when none is known.
local function levelGapOf(bot, st, s)
    if s == nil then
        return 0
    end
    local radius = Settings.Get().SpareLaneRadius
    local top = 0
    for ____, e in ipairs(LaneState.Enemies(bot, s.lane)) do
        do
            local __continue41
            repeat
                if dist2D(e.location, s.frontLoc) > radius then
                    __continue41 = true
                    break
                end
                local level = e.visible and e.unit ~= nil and e.unit:GetLevel() or st.levelSeen[e.pid]
                if level ~= nil and level > top then
                    top = level
                end
                __continue41 = true
            until true
            if not __continue41 then
                break
            end
        end
    end
    return top > 0 and top - bot:GetLevel() or 0
end
function ____exports.LaneLost(bot)
    local cfg = Settings.Get()
    local st = stateOf(bot)
    local now = DotaTime()
    pruneRecord(st.record, now)
    local pos = LaneConfig.PositionOf(bot)
    local rate = 0
    local expected = 0
    local first = st.record.lastHits[1]
    if pos ~= nil and pos <= 3 and first ~= nil and now - first.at >= cfg.LostMinSpan then
        expected = Settings.Lerp(
            cfg.ExpectedLHPerMin,
            LaneConfig.SkillOf(bot)
        )
        rate = (lastHits(bot) - first.total) / (now - first.at) * 60
    end
    return ____exports.LaneLostPure({
        deathsInWindow = #st.record.deaths,
        lhPerMin = rate,
        expectedLhPerMin = expected,
        levelGap = levelGapOf(
            bot,
            st,
            LaneState.ForBot(bot)
        )
    })
end
local function partnerOf(bot)
    local s = LaneState.ForBot(bot)
    local ____temp_2
    if s ~= nil then
        ____temp_2 = LaneRoles.Partner(bot, s)
    else
        ____temp_2 = nil
    end
    return ____temp_2
end
local function sample(bot, st, now)
    local cfg = Settings.Get()
    local alive = bot:IsAlive()
    if st.wasAlive == true and not alive and st.wasLaning then
        local ____st_record_deaths_3 = st.record.deaths
        ____st_record_deaths_3[#____st_record_deaths_3 + 1] = now
    end
    st.wasAlive = alive
    st.wasLaning = ____exports.IsLaningFor(bot)
    if alive and now >= cfg.LostLHFrom then
        local last = st.record.lastHits[#st.record.lastHits]
        if last == nil or now - last.at >= cfg.LHSampleGap then
            local ____st_record_lastHits_4 = st.record.lastHits
            ____st_record_lastHits_4[#____st_record_lastHits_4 + 1] = {
                at = now,
                total = lastHits(bot)
            }
        end
        local s = LaneState.ForBot(bot)
        if s ~= nil then
            for ____, e in ipairs(LaneState.Enemies(bot, s.lane)) do
                if e.visible and e.unit ~= nil then
                    st.levelSeen[e.pid] = e.unit:GetLevel()
                end
            end
        end
    end
    pruneRecord(st.record, now)
end
--- Advances the human-partner flow; true while the bot should keep laning because it still waits on the human.
local function humanWaiting(bot, st, now)
    local partner = partnerOf(bot)
    if partner == nil or partner.isBot then
        return false
    end
    if st.capStarted then
        return false
    end
    local cfg = Settings.Get()
    if st.suggestedAt ~= nil then
        local base = st.orderBase
        local order = Orders.GetFor(bot)
        local absent = not partner.alive or partner.distToFront > LaneConfig.Settings().Thresholds.CoreAbsentDist
        if absent then
            if st.absentSince == nil then
                st.absentSince = now
            end
        else
            st.absentSince = nil
        end
        if Pings.HumanPingNear(
            bot:GetTeam(),
            bot:GetLocation(),
            cfg.LostPingRadius,
            now - st.suggestedAt
        ) or order ~= nil and order.id ~= base or st.absentSince ~= nil and now - st.absentSince >= cfg.AbsentHold then
            st.capStarted = true
            return false
        end
    end
    if (st.suggestedAt == nil or now - st.suggestedAt >= cfg.SuggestCooldown) and Orders.Say(bot, "say_lane_lost_roam", cfg.SuggestCooldown) then
        st.suggestedAt = now
        local ____st_7 = st
        local ____opt_5 = Orders.GetFor(bot)
        ____st_7.orderBase = ____opt_5 and ____opt_5.id
        st.absentSince = nil
    end
    return true
end
local function evaluate(bot, st, now)
    st.phaseEnded = false
    st.lostResp = false
    st.cap = nil
    if not LaneConfig.InLaningPhase() then
        return
    end
    if Settings.IsOn("Phase") and not ____exports.IsLaningFor(bot) then
        st.phaseEnded = true
        st.cap = ____exports.SOURCE_PHASE
    end
    local lost = false
    if Settings.IsOn("LostLane") then
        lost = ____exports.LaneLost(bot)
    end
    if not lost then
        st.capStarted = false
        st.absentSince = nil
    elseif not humanWaiting(bot, st, now) then
        st.lostResp = true
        st.cap = st.cap or ____exports.SOURCE_LOST
    end
    if not st.phaseEnded and not st.lostResp then
        st.jungleSaid = false
        return
    end
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
    if not Settings.IsOn("Phase") and not Settings.IsOn("LostLane") then
        Intent.Release(bot, ____exports.SOURCE_PHASE, BotMode.Laning)
        Intent.Release(bot, ____exports.SOURCE_LOST, BotMode.Laning)
        return
    end
    local st = stateOf(bot)
    local now = DotaTime()
    if now >= st.checkAt then
        st.checkAt = now + Settings.Get().Refresh
        sample(bot, st, now)
        evaluate(bot, st, now)
    end
    local cap = Settings.Get().LaningCap
    for ____, source in ipairs({____exports.SOURCE_PHASE, ____exports.SOURCE_LOST}) do
        if st.cap == source then
            Intent.Claim(bot, {source = source, tier = "TRANSITION", mode = BotMode.Laning, cap = cap})
        else
            Intent.Release(bot, source, BotMode.Laning)
        end
    end
end
--- Farm-mode hook: a core whose laning has ended (or whose lane is lost, with no human left waiting) may farm.
function ____exports.FarmAllowedInLaning(bot)
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil or pos > 3 then
        return false
    end
    local st = states[bot:GetPlayerID()]
    if st == nil then
        return false
    end
    return Settings.IsOn("Phase") and st.phaseEnded or Settings.IsOn("LostLane") and st.lostResp
end
return ____exports
