--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local LaneMain = require(GetScriptDirectory().."/FunLib/humaniser/lane")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Counter = require(GetScriptDirectory().."/FunLib/humaniser/counterplay")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
local Rotation = require(GetScriptDirectory().."/FunLib/humaniser/transitions/rotation")
____exports.SOURCE = "transitions:caution"
function ____exports.CautionLevel(i)
    local base = i.missing > 0 and 1 or (i.alone and math.min(
        1,
        0.5 + 0.25 * math.max(0, i.laneEnemies - 1)
    ) or 0)
    return base * Settings.Lerp(
        Settings.Get().SkillAmount,
        i.skill
    )
end
local states = {}
local episodes = {}
function ____exports.ResetCache()
    states = {}
    episodes = {}
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
function ____exports.IsAlone(bot, s)
    local pid = bot:GetPlayerID()
    local others = {}
    for ____, h in ipairs(s.allies) do
        if h.assigned and h.pid ~= pid then
            others[#others + 1] = h
        end
    end
    if #others == 0 then
        return LanePlan.EnemyLaners(bot, s) >= 2
    end
    if #others > 1 then
        return false
    end
    local p = others[1]
    if not p.alive or p.distToFront > LaneConfig.Settings().Thresholds.CoreAbsentDist then
        return true
    end
    return Rotation.Active(p.unit) ~= nil or CampJobs.Active(p.unit)
end
function ____exports.Missing(bot, s, alone)
    local cfg = Settings.Get()
    local after = alone and cfg.AloneMissing or cfg.LaneMissing
    local n = 0
    for ____, e in ipairs(LaneState.Enemies(bot, s.lane)) do
        do
            local __continue13
            repeat
                if e.visible or e.timeSinceSeen <= after or not IsHeroAlive(e.pid) then
                    __continue13 = true
                    break
                end
                if dist2D(e.location, s.frontLoc) <= cfg.SpareLaneRadius then
                    n = n + 1
                end
                __continue13 = true
            until true
            if not __continue13 then
                break
            end
        end
    end
    return n
end
local function stateOf(bot)
    local pid = bot:GetPlayerID()
    local st = states[pid]
    if st == nil then
        st = {
            applied = 0,
            target = 0,
            targetAt = -math.huge,
            delay = 0,
            checkAt = -math.huge,
            missing = 0
        }
        states[pid] = st
    end
    return st
end
local function update(bot, now)
    local st = stateOf(bot)
    if now >= st.checkAt then
        st.checkAt = now + Settings.Get().Refresh
        local s = LaneState.ForBot(bot)
        local target = 0
        st.missing = 0
        st.lane = s and s.lane
        if s ~= nil then
            local alone = ____exports.IsAlone(bot, s)
            st.missing = ____exports.Missing(bot, s, alone)
            if alone or st.missing > 0 then
                target = ____exports.CautionLevel({
                    alone = alone,
                    laneEnemies = LanePlan.EnemyLaners(bot, s),
                    missing = st.missing,
                    skill = LaneConfig.SkillOf(bot)
                })
            end
        end
        if target ~= st.target then
            st.target = target
            st.targetAt = now
            st.delay = Profile.SampleDelay(bot, "notice")
        end
    end
    if st.applied ~= st.target and now - st.targetAt >= st.delay then
        st.applied = st.target
        HDebug.Log(
            "transitions",
            (((("caution pid=" .. tostring(bot:GetPlayerID())) .. " level=") .. string.format("%.2f", st.applied)) .. " missing=") .. tostring(st.missing)
        )
    end
    return st
end
function ____exports.Level(bot)
    if not Settings.IsOn("Caution") then
        return 0
    end
    return update(
        bot,
        DotaTime()
    ).applied
end
local function clamp01(v)
    return v < 0 and 0 or (v > 1 and 1 or v)
end
local function towardTower(bot, loc, level)
    local s = LaneState.ForBot(bot)
    if s == nil then
        return loc
    end
    local cfg = Settings.Get()
    local tower = GetLocationAlongLane(
        s.lane,
        clamp01(Camps.ToAbsAmount(s.team, s.ourTowerAmount))
    )
    local d = dist2D(loc, tower)
    if d <= 0 then
        return loc
    end
    local step = math.min(d, cfg.OffsetMin + (cfg.OffsetMax - cfg.OffsetMin) * level)
    return Vector(loc.x + (tower.x - loc.x) / d * step, loc.y + (tower.y - loc.y) / d * step, loc.z)
end
--- Lane position override (plan call 6); returns `loc` itself when caution does not apply.
function ____exports.AdjustPosition(bot, loc)
    if not Settings.IsOn("Caution") then
        return loc
    end
    local level = ____exports.Level(bot)
    if level <= 0 or not LaneMain.OwnsLaning(bot) then
        return loc
    end
    return towardTower(bot, loc, level)
end
function ____exports.SuppressTrades(bot)
    if not Settings.IsOn("Caution") or ____exports.Level(bot) < 0.5 then
        return false
    end
    local stronger = LaneConfig.Helpers().WeAreStronger
    return stronger == nil or not stronger(
        bot,
        Settings.Get().CautionStrongerRadius
    )
end
local LANE_NAMES = {[Lane.Top] = "top", [Lane.Mid] = "mid", [Lane.Bot] = "bot"}
local function midAlreadyCalled(bot, now)
    local window = Settings.Get().MidMissingSignalWindow
    for ____, sig in ipairs(Counter.Signals(bot)) do
        if sig.kind == "mid_missing" and now - sig.at <= window then
            return true
        end
    end
    return false
end
local function callout(bot, st, now)
    if st.lane == nil then
        return
    end
    local name = LANE_NAMES[st.lane]
    if name == nil then
        return
    end
    local key = (tostring(bot:GetTeam()) .. ":") .. tostring(st.lane)
    local ep = episodes[key]
    if ep == nil then
        ep = {active = false, saidAt = -math.huge}
        episodes[key] = ep
    end
    if st.missing == 0 then
        ep.active = false
        return
    end
    if ep.active or not Difficulty.IsAllyOfHuman(bot) then
        return
    end
    ep.active = true
    local cooldown = Settings.Get().MissingCooldown
    if now - ep.saidAt < cooldown then
        return
    end
    if st.lane == Lane.Mid and midAlreadyCalled(bot, now) then
        return
    end
    ep.saidAt = now
    Orders.Say(bot, "say_ss_" .. name, cooldown)
end
function ____exports.Tick(bot)
    if not Settings.IsOn("Caution") then
        return
    end
    local now = DotaTime()
    local st = update(bot, now)
    callout(bot, st, now)
    local level = st.applied
    if level <= 0 then
        Intent.ReleaseSource(bot, ____exports.SOURCE)
        return
    end
    local cfg = Settings.Get()
    Intent.Claim(bot, {source = ____exports.SOURCE, tier = "TRANSITION", mode = BotMode.Retreat, scale = 1 + (cfg.RetreatScaleMax - 1) * level})
    Intent.Claim(bot, {source = ____exports.SOURCE, tier = "TRANSITION", mode = BotMode.Attack, scale = 1 - (1 - cfg.AttackScaleMin) * level})
end
function ____exports.RegisterProbes()
    LaneHooks.SetCautionProbe(function(bot) return ____exports.Level(bot) > 0 end)
    LaneHooks.SetPositionProbe(____exports.AdjustPosition)
    LaneHooks.SetTradeProbe(____exports.SuppressTrades)
end
____exports.RegisterProbes()
return ____exports
