--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local JobVerbs = require(GetScriptDirectory().."/FunLib/humaniser/job_verbs")
local AllyLastHit = require(GetScriptDirectory().."/FunLib/humaniser/ally_last_hit")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LastHitSkill = require(GetScriptDirectory().."/FunLib/humaniser/last_hit_skill")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
local attempted = false
local lib
function ____exports.Enabled()
    return Config.IsEnabled() and Config.Get().Tasks.Enable ~= false
end
--- An allied core (position 1-3, not the bot) within 1600 that can take the creep itself.
local function CoreCanTake(bot, creep, allies)
    for ____, ally in ipairs(allies) do
        if ally ~= bot and ally:IsAlive() then
            local pos = LaneConfig.PositionOf(ally)
            if pos ~= nil and pos <= 3 and AllyLastHit.CoreCanReach(ally, creep) then
                return true
            end
        end
    end
    return false
end
--- One table per bot, cleared on a new frame (no allocation per frame).
local filterCache = {}
local function mayTake(bot, creep, f)
    local allowed, reason = AllyLastHit.MayLastHit(bot, creep)
    if not allowed then
        return false
    end
    if string.sub(reason, 1, 5) == "take:" then
        return true
    end
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil or pos <= 2 then
        return true
    end
    if f.allies == nil then
        f.allies = bot:GetNearbyHeroes(1600, false, BotMode.None)
    end
    return not CoreCanTake(bot, creep, f.allies)
end
local adapter = {
    claim = function(bot, c)
        local ____Intent_Claim_6 = Intent.Claim
        local ____bot_5 = bot
        local ____c_source_1 = c.source
        local ____c_tier_2 = c.tier
        local ____c_mode_3 = c.mode
        local ____c_floor_4 = c.floor
        local ____temp_0
        if c.urgent == true then
            ____temp_0 = true
        else
            ____temp_0 = nil
        end
        return ____Intent_Claim_6(____bot_5, {
            source = ____c_source_1,
            tier = ____c_tier_2,
            mode = ____c_mode_3,
            floor = ____c_floor_4,
            unsticks = ____temp_0
        })
    end,
    release = function(bot, source, mode) return Intent.Release(bot, source, mode) end,
    hold = function(bot, tag) return Intent.Hold(bot, tag) end,
    lastHitFilter = function(bot, creep)
        local pid = bot:GetPlayerID()
        local now = DotaTime()
        local f = filterCache[pid]
        if f == nil then
            f = {t = now, by = {}}
            filterCache[pid] = f
        elseif f.t ~= now then
            f.t = now
            f.allies = nil
            for k in pairs(f.by) do
                f.by[k] = nil
            end
        end
        local by = f.by
        local hit = by[creep]
        if hit ~= nil then
            return hit
        end
        local allowed = mayTake(bot, creep, f)
        by[creep] = allowed
        return allowed
    end,
    skill = function(bot) return Difficulty.GetSkill(bot) end,
    profile = function(bot)
        local p = Profile.Get(bot)
        return {react = p.reactBase, jitter = p.jitter, aimError = p.aimError, lapse = p.lapseChance}
    end,
    lastHitError = function(bot) return LastHitSkill.ErrorWidth(bot) end,
    random = function() return RandomFloat(0, 1) end,
    attackClock = function() return GameTime() end,
    now = function() return DotaTime() end,
    log = function(tag, msg) return HDebug.Log(tag, msg) end,
    event = function(name, fields) return Telemetry.EventUntyped(name, fields) end,
    vector = function(x, y, z) return Vector(x, y, z) end,
    enabled = function() return ____exports.Enabled() end
}
local function loadBundle()
    if not ____exports.Enabled() then
        return nil
    end
    if attempted then
        return lib
    end
    attempted = true
    local ok, res = pcall(
        require,
        GetScriptDirectory() .. "/FunLib/engine/tasks"
    )
    local support = ("[H:tasks] support coroutine=" .. type(coroutine)) .. " bundle="
    local rawPrint = Utils.RawPrint
    if ok and type(res) == "table" then
        lib = res
        lib.init(adapter)
        JobVerbs.Bind(lib, adapter);
        (rawPrint or print)(support .. "ok")
    else
        (rawPrint or print)((support .. "fail ") .. tostring(res))
    end
    return lib
end
--- The loaded bundle (loading it on first use), or undefined when tasks are off or it failed to load.
function ____exports.Loaded()
    return loadBundle()
end
LaneConfig.SetRng(function()
    local ____opt_7 = loadBundle()
    return ____opt_7 and ____opt_7.Skill
end)
--- True once the bundle has loaded and tasks are enabled.
function ____exports.IsActive()
    return lib ~= nil and ____exports.Enabled()
end
function ____exports.Start(bot, opts, body)
    local l = loadBundle()
    return l ~= nil and l.Tasks.task(bot, opts, body)
end
--- Call from the host mode's Think(); returns false when no task of this bot runs under `mode`.
function ____exports.Step(bot, mode)
    local l = loadBundle()
    return l ~= nil and l.Tasks.Step(bot, mode)
end
function ____exports.Tick(bot)
    local ____opt_9 = loadBundle()
    if ____opt_9 ~= nil then
        ____opt_9.Tasks.Tick(bot)
    end
end
--- Never loads the bundle: no task can be running before one was started.
function ____exports.Current(bot)
    local ____IsActive_result_11
    if ____exports.IsActive() then
        ____IsActive_result_11 = lib.Tasks.Current(bot)
    else
        ____IsActive_result_11 = nil
    end
    return ____IsActive_result_11
end
function ____exports.Cancel(bot, reason, message)
    if ____exports.IsActive() then
        lib.Tasks.Cancel(bot, reason, message)
    end
end
function ____exports.Urgent(bot, on)
    if lib ~= nil then
        lib.Tasks.Urgent(bot, on)
    end
end
function ____exports.Label(bot, label)
    if lib ~= nil then
        lib.Tasks.Label(bot, label)
    end
end
function ____exports.Describe(bot)
    local ____opt_16 = loadBundle()
    return ____opt_16 and ____opt_16.Tasks.Describe(bot)
end
function ____exports.Verbs()
    local ____opt_18 = loadBundle()
    return ____opt_18 and ____opt_18.Verbs
end
--- The job verbs (bot code on the engine's verbs), or undefined when tasks are off or the bundle failed to load.
function ____exports.Jobs()
    return loadBundle() ~= nil and JobVerbs or nil
end
return ____exports
