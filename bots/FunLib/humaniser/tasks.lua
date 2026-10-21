--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local AllyLastHit = require(GetScriptDirectory().."/FunLib/humaniser/ally_last_hit")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
local attempted = false
local lib
function ____exports.Enabled()
    return Config.IsEnabled() and Config.Get().Tasks.Enable ~= false
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
        local allowed = AllyLastHit.MayLastHit(bot, creep)
        return allowed
    end,
    now = function() return DotaTime() end,
    log = function(tag, msg) return HDebug.Log(tag, msg) end,
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
        GetScriptDirectory() .. "/FunLib/sdk/tasks/tasks"
    )
    local support = ("[H:tasks] support coroutine=" .. type(coroutine)) .. " bundle="
    local rawPrint = Utils.RawPrint
    if ok and type(res) == "table" then
        lib = res
        lib.init(adapter);
        (rawPrint or print)(support .. "ok")
    else
        (rawPrint or print)((support .. "fail ") .. tostring(res))
    end
    return lib
end
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
    local ____opt_7 = loadBundle()
    if ____opt_7 ~= nil then
        ____opt_7.Tasks.Tick(bot)
    end
end
--- Never loads the bundle: no task can be running before one was started.
function ____exports.Current(bot)
    local ____IsActive_result_9
    if ____exports.IsActive() then
        ____IsActive_result_9 = lib.Tasks.Current(bot)
    else
        ____IsActive_result_9 = nil
    end
    return ____IsActive_result_9
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
    local ____opt_14 = loadBundle()
    return ____opt_14 and ____opt_14.Tasks.Describe(bot)
end
function ____exports.Verbs()
    local ____opt_16 = loadBundle()
    return ____opt_16 and ____opt_16.Verbs
end
return ____exports
