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
    claim = function(bot, c) return Intent.Claim(bot, {source = c.source, tier = c.tier, mode = c.mode, floor = c.floor}) end,
    release = function(bot, source, mode) return Intent.Release(bot, source, mode) end,
    lastHitFilter = function(bot, creep)
        local allowed = AllyLastHit.MayLastHit(bot, creep)
        return allowed
    end,
    now = function() return GameTime() end,
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
    local ____opt_0 = loadBundle()
    if ____opt_0 ~= nil then
        ____opt_0.Tasks.Tick(bot)
    end
end
function ____exports.Describe(bot)
    local ____opt_2 = loadBundle()
    return ____opt_2 and ____opt_2.Tasks.Describe(bot)
end
function ____exports.Verbs()
    local ____opt_4 = loadBundle()
    return ____opt_4 and ____opt_4.Verbs
end
return ____exports
