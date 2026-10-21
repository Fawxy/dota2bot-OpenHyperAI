--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
local Bridge = require(GetScriptDirectory().."/FunLib/sdk/bridge")
local Json = require(GetScriptDirectory().."/ts_libs/utils/json")
local initialised = false
local function log(line)
    local rawPrint = Utils.RawPrint;
    (rawPrint or print)("[H:bridge] " .. line)
end
local function ensureInit()
    if initialised then
        return
    end
    initialised = true
    Bridge.Init(
        {
            log = log,
            realTime = function() return RealTime() end,
            gameTime = function() return GameTime() end,
            encode = Json.encode,
            decode = Json.decode
        },
        Config.Get().Bridge
    )
end
function ____exports.IsEnabled()
    return Config.IsEnabled() and Config.Get().Bridge.Enable == true
end
function ____exports.Tick(bot)
    if not ____exports.IsEnabled() then
        return
    end
    if not bot:IsHero() or bot:IsIllusion() then
        return
    end
    ensureInit()
    Bridge.Tick(
        bot:GetTeam(),
        bot:GetPlayerID()
    )
end
return ____exports
