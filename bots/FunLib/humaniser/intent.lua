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
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local GameState = ____dota.GameState
local Team = ____dota.Team
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
local TIER_RANK = {
    MOOD = 1,
    TRANSITION = 2,
    CAMP_JOB = 3,
    LANE_PLAN = 4,
    FIGHT = 5,
    HUMAN_ORDER = 6,
    SURVIVAL = 7
}
____exports.DEFAULTS = {
    Enable = true,
    ClaimTTL = 0.2,
    ScaleClamp = 0.3,
    Sticky = {Bonus = 0.06, MinDwell = 1, Decay = 1},
    Thrash = {Window = 5, MaxSwitches = 4, Bonus = 0.12, Duration = 3},
    Stuck = {
        Enable = true,
        After = 1.5,
        StillRadius = 50,
        Match = "idle_and_still",
        MinDesire = 0.1,
        Drop = 0.15,
        Duration = 2,
        BaseRadius = 2600
    },
    Survival = {Enable = true, HP = 0.25, MinRetreat = 0.5, Margin = 0.05},
    Summary = true
}
local SAMPLE_FRESH = 0.5
local SUMMARY_CHECK_INTERVAL = 1
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
            Config.Get().Intent
        )
    end
    return cached
end
function ____exports.IsActive()
    return Config.IsFeatureEnabled("Intent")
end
local states = {}
local function stateFor(bot)
    local pid = bot:GetPlayerID()
    local s = states[pid]
    if s == nil then
        s = {
            claims = {},
            priorityAt = -math.huge,
            samples = {},
            modeSince = 0,
            switchTimes = {},
            switchCount = 0,
            thrashUntil = -math.huge,
            thrashEpisodes = 0,
            stillSince = 0,
            stuckEpisode = false,
            stuckByMode = {},
            conflicts = {},
            lastConflict = {},
            summaryCheckAt = -math.huge,
            summaryPrinted = false
        }
        states[pid] = s
    end
    return s
end
local function sharesPlayerID(bot)
    return bot:GetUnitName() == "npc_dota_hero_meepo" or bot:HasModifier("modifier_arc_warden_tempest_double")
end
function ____exports.Claim(bot, claim)
    if not ____exports.IsActive() or sharesPlayerID(bot) then
        return
    end
    local s = stateFor(bot)
    local now = GameTime()
    local stored = __TS__ObjectAssign(
        {},
        claim,
        {expires = claim["until"] or now + ____exports.Get().ClaimTTL}
    )
    s.claims[(claim.source .. "|") .. tostring(claim.mode)] = stored
    if claim.tier == "SURVIVAL" or claim.tier == "HUMAN_ORDER" then
        s.priorityAt = now
    end
end
function ____exports.Release(bot, source, mode)
    local s = states[bot:GetPlayerID()]
    if s ~= nil then
        s.claims[(source .. "|") .. tostring(mode)] = nil
    end
end
local function applies(claim, mode)
    if claim.mode == mode then
        return true
    end
    if claim.mode ~= "ANY" then
        return false
    end
    if claim.except ~= nil then
        for ____, m in ipairs(claim.except) do
            if m == mode then
                return false
            end
        end
    end
    return true
end
local function compareClaims(a, b)
    local ta = TIER_RANK[a.tier]
    local tb = TIER_RANK[b.tier]
    if ta ~= tb then
        return ta - tb
    end
    if a.expires ~= b.expires then
        return a.expires - b.expires
    end
    if a.source ~= b.source then
        return a.source < b.source and -1 or 1
    end
    return a.mode == "ANY" and (b.mode == "ANY" and 0 or -1) or (b.mode == "ANY" and 1 or 0)
end
local function stickyBonus(s, mode, now)
    local cfg = ____exports.Get()
    local bonus = 0
    local dwell = now - s.modeSince
    if dwell <= cfg.Sticky.MinDwell then
        bonus = cfg.Sticky.Bonus
    elseif cfg.Sticky.Decay > 0 and dwell < cfg.Sticky.MinDwell + cfg.Sticky.Decay then
        bonus = cfg.Sticky.Bonus * (1 - (dwell - cfg.Sticky.MinDwell) / cfg.Sticky.Decay)
    end
    if now < s.thrashUntil and s.thrashMode == mode then
        bonus = math.max(bonus, cfg.Thrash.Bonus)
    end
    return bonus
end
local function noteConflict(s, mode, key)
    if s.lastConflict[mode] == key then
        return
    end
    s.lastConflict[mode] = key
    s.conflicts[key] = (s.conflicts[key] or 0) + 1
end
--- Applies this bot's claims to a mode's raw desire. Call at the end of every GetDesire().
-- Non-numbers (nil = use Valve's desire) pass through untouched.
function ____exports.Resolve(bot, mode, raw)
    if type(raw) ~= "number" or mode == nil or not ____exports.IsActive() or sharesPlayerID(bot) then
        return raw
    end
    local cfg = ____exports.Get()
    local now = GameTime()
    local s = stateFor(bot)
    local ordered
    local scale = 1
    local riskAllowed = false
    local capped = false
    for key, claim in pairs(s.claims) do
        if claim.expires < now then
            s.claims[key] = nil
        elseif applies(claim, mode) then
            if claim.scale ~= nil then
                scale = scale * claim.scale
            end
            if claim.tier == "HUMAN_ORDER" and claim.allowRisk == true then
                riskAllowed = true
            end
            if claim.cap ~= nil then
                capped = true
            end
            if claim.floor ~= nil or claim.cap ~= nil then
                if ordered == nil then
                    ordered = {}
                end
                ordered[#ordered + 1] = claim
            end
        end
    end
    local scaled = raw * math.min(
        math.max(scale, 1 - cfg.ScaleClamp),
        1 + cfg.ScaleClamp
    )
    local desire = scaled
    local by = desire ~= raw and "scale" or "raw"
    local setter
    local conflicted = false
    if ordered ~= nil then
        if #ordered > 1 then
            __TS__ArraySort(
                ordered,
                function(____, a, b) return compareClaims(a, b) end
            )
        end
        for ____, claim in ipairs(ordered) do
            do
                local __continue47
                repeat
                    if claim.tier == "SURVIVAL" and riskAllowed then
                        __continue47 = true
                        break
                    end
                    if claim.onlyLifted == true and desire <= scaled then
                        __continue47 = true
                        break
                    end
                    local value = desire
                    if claim.floor ~= nil and value < claim.floor then
                        value = claim.floor
                    end
                    if claim.cap ~= nil and value > claim.cap then
                        value = claim.cap
                    end
                    if value ~= desire then
                        if setter ~= nil and setter ~= claim.source then
                            noteConflict(s, mode, (claim.source .. ">") .. setter)
                            conflicted = true
                        end
                        setter = claim.source
                        by = claim.source
                        desire = value
                    end
                    __continue47 = true
                until true
                if not __continue47 then
                    break
                end
            end
        end
    end
    if not conflicted then
        s.lastConflict[mode] = nil
    end
    local retreat = s.samples[BotMode.Retreat]
    local retreatContends = mode ~= BotMode.Retreat and retreat ~= nil and now - retreat.time <= SAMPLE_FRESH and retreat.resolved >= desire
    if mode == s.mode and desire > 0 and not capped and not retreatContends and now - s.priorityAt > cfg.ClaimTTL then
        local bonus = stickyBonus(s, mode, now)
        if bonus > 0 then
            desire = desire + bonus
            by = by .. "+sticky"
        end
    end
    desire = math.max(desire, 0)
    if mode == BotMode.Retreat and cfg.Survival.Enable and desire >= cfg.Survival.MinRetreat then
        if bot:GetHealth() / bot:GetMaxHealth() < cfg.Survival.HP then
            ____exports.Claim(bot, {
                source = "intent:survival",
                tier = "SURVIVAL",
                mode = "ANY",
                except = {BotMode.Retreat},
                cap = desire - cfg.Survival.Margin,
                onlyLifted = true
            })
        end
    end
    local sample = s.samples[mode]
    if sample == nil then
        s.samples[mode] = {raw = raw, resolved = desire, time = now, by = by}
    else
        sample.raw = raw
        sample.resolved = desire
        sample.time = now
        sample.by = by
    end
    HDebug.RecordDesire(bot, mode, desire)
    return desire
end
--- "<mode> <desire> by <winning claim source>", for the overlay and logs.
function ____exports.Explain(bot, mode)
    local s = states[bot:GetPlayerID()]
    local sample = s and s.samples[mode]
    if sample == nil or GameTime() - sample.time > SAMPLE_FRESH then
        return HDebug.ModeName(mode) .. " (valve)"
    end
    return (((HDebug.ModeName(mode) .. " ") .. string.format("%.2f", sample.resolved)) .. " by ") .. sample.by
end
local function competingModes(s, now)
    local fresh = {}
    for mode, sample in pairs(s.samples) do
        if now - sample.time <= SAMPLE_FRESH then
            fresh[#fresh + 1] = {mode, sample.resolved}
        end
    end
    __TS__ArraySort(
        fresh,
        function(____, a, b) return b[2] - a[2] end
    )
    local parts = {}
    do
        local i = 0
        while i < #fresh and i < 4 do
            parts[#parts + 1] = (HDebug.ModeName(fresh[i + 1][1]) .. "=") .. string.format("%.2f", fresh[i + 1][2])
            i = i + 1
        end
    end
    return table.concat(parts, " ")
end
--- The freshest resolved desires, highest first, e.g. "farm=0.62 laning=0.40".
function ____exports.Competing(bot)
    local s = states[bot:GetPlayerID()]
    return s ~= nil and competingModes(
        s,
        GameTime()
    ) or ""
end
local function onModeSwitch(bot, s, mode, now)
    local first = s.mode == nil
    s.mode = mode
    s.modeSince = now
    s.stuckEpisode = false
    if first then
        return
    end
    local cfg = ____exports.Get().Thrash
    s.switchCount = s.switchCount + 1
    local ____s_switchTimes_4 = s.switchTimes
    ____s_switchTimes_4[#____s_switchTimes_4 + 1] = now
    while #s.switchTimes > 0 and s.switchTimes[1] < now - cfg.Window do
        table.remove(s.switchTimes, 1)
    end
    if #s.switchTimes > cfg.MaxSwitches and now >= s.thrashUntil then
        s.thrashUntil = now + cfg.Duration
        s.thrashMode = mode
        s.thrashEpisodes = s.thrashEpisodes + 1
        HDebug.Log(
            "intent",
            (((((((("thrash pid=" .. tostring(bot:GetPlayerID())) .. " switches=") .. tostring(#s.switchTimes)) .. "/") .. tostring(cfg.Window)) .. "s now=") .. HDebug.ModeName(mode)) .. " ") .. competingModes(s, now)
        )
        Telemetry.Event(
            "thrash",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"switches", #s.switchTimes},
                {"window", cfg.Window},
                {
                    "mode",
                    HDebug.ModeName(mode)
                },
                {
                    "competing",
                    competingModes(s, now)
                }
            }
        )
    end
end
local function isIdle(bot)
    local action = bot:GetCurrentActionType()
    return (action == BOT_ACTION_TYPE_IDLE or action == BOT_ACTION_TYPE_NONE) and bot:NumQueuedActions() == 0
end
local function isBusyOrSafe(bot, cfg)
    return bot:IsChanneling() or bot:IsUsingAbility() or bot:IsCastingAbility() or bot:IsStunned() or bot:IsHexed() or bot:DistanceFromFountain() < cfg.BaseRadius
end
local function checkStuck(bot, s, mode, now)
    local cfg = ____exports.Get().Stuck
    if not cfg.Enable then
        return
    end
    local actor = bot
    if GetGameState() ~= GameState.GameInProgress or DotaTime() <= 0 or not bot:IsAlive() or mode == BotMode.None then
        s.stuckEpisode = false
        s.stillAnchor = nil
        s.idleSince = nil
        return
    end
    local loc = bot:GetLocation()
    if s.stillAnchor == nil or Utils.GetLocationToLocationDistance(loc, s.stillAnchor) > cfg.StillRadius then
        s.stillAnchor = loc
        s.stillSince = now
    end
    if not isIdle(actor) then
        s.idleSince = nil
    elseif s.idleSince == nil then
        s.idleSince = now
    end
    if isBusyOrSafe(actor, cfg) then
        s.stuckEpisode = false
        return
    end
    local idle = s.idleSince ~= nil and now - s.idleSince >= cfg.After
    local still = now - s.stillSince >= cfg.After
    local ____temp_5
    if cfg.Match == "idle_or_still" then
        ____temp_5 = idle or still
    else
        ____temp_5 = idle and still
    end
    local frozen = ____temp_5
    local desire = bot:GetActiveModeDesire()
    local sample = s.samples[mode]
    local raw = sample ~= nil and now - sample.time <= SAMPLE_FRESH and sample.raw or desire
    if not frozen or now - s.modeSince < cfg.After or raw < cfg.MinDesire then
        s.stuckEpisode = false
        return
    end
    ____exports.Claim(
        bot,
        {
            source = "intent:stuck",
            tier = "LANE_PLAN",
            mode = mode,
            cap = math.max(raw - cfg.Drop, 0),
            ["until"] = now + cfg.Duration
        }
    )
    if s.stuckEpisode then
        return
    end
    s.stuckEpisode = true
    s.stuckByMode[mode] = (s.stuckByMode[mode] or 0) + 1
    HDebug.Log(
        "intent",
        (((((("stuck pid=" .. tostring(bot:GetPlayerID())) .. " mode=") .. HDebug.ModeName(mode)) .. " desire=") .. string.format("%.2f", desire)) .. " since=") .. string.format("%.1f", s.modeSince)
    )
    Telemetry.Event(
        "stuck",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {
                "mode",
                HDebug.ModeName(mode)
            },
            {"d", desire},
            {"raw", raw},
            {"inMode", now - s.modeSince}
        }
    )
end
local function ancientDown(team)
    local ancient = GetAncient(team)
    return ancient == nil or ancient == nil or not ancient:IsAlive() or ancient:GetHealth() <= 0
end
local function joinCounts(counts, name)
    local parts = {}
    for k, n in pairs(counts) do
        parts[#parts + 1] = (name(k) .. ":") .. tostring(n)
    end
    __TS__ArraySort(parts)
    return #parts > 0 and table.concat(parts, ",") or "-"
end
function ____exports.SummaryLine(bot)
    local s = stateFor(bot)
    return (((((((((("[H:intent] summary pid=" .. tostring(bot:GetPlayerID())) .. " ") .. (string.gsub(
        bot:GetUnitName(),
        "npc_dota_hero_",
        ""
    ))) .. " switches=") .. tostring(s.switchCount)) .. " thrash=") .. tostring(s.thrashEpisodes)) .. " stuck=") .. joinCounts(
        s.stuckByMode,
        function(k) return HDebug.ModeName(tonumber(k)) end
    )) .. " conflicts=") .. joinCounts(
        s.conflicts,
        function(k) return tostring(k) end
    )
end
local function maybeSummary(bot, s, now)
    if s.summaryPrinted or not ____exports.Get().Summary or now - s.summaryCheckAt < SUMMARY_CHECK_INTERVAL then
        return
    end
    s.summaryCheckAt = now
    if GetGameState() ~= GameState.PostGame and not ancientDown(Team.Radiant) and not ancientDown(Team.Dire) then
        return
    end
    s.summaryPrinted = true
    local rawPrint = Utils.RawPrint;
    (rawPrint or print)(____exports.SummaryLine(bot))
end
--- Mode-switch tracking, stuck detection and the end-of-game summary. Runs every frame from Humaniser.Tick.
function ____exports.Tick(bot)
    if not ____exports.IsActive() or sharesPlayerID(bot) then
        return
    end
    local s = stateFor(bot)
    local now = GameTime()
    local mode = bot:GetActiveMode()
    if mode ~= s.mode then
        onModeSwitch(bot, s, mode, now)
    end
    checkStuck(bot, s, mode, now)
    maybeSummary(bot, s, now)
end
return ____exports
