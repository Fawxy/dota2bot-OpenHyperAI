--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ObjectKeys(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = key
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Team = ____dota.Team
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
local PROBE_LOG_INTERVAL = 5
local modeNames = {
    [BotMode.None] = "none",
    [BotMode.Laning] = "laning",
    [BotMode.Attack] = "attack",
    [BotMode.Roam] = "roam",
    [BotMode.Retreat] = "retreat",
    [BotMode.SecretShop] = "secret_shop",
    [BotMode.SideShop] = "side_shop",
    [BotMode.Rune] = "rune",
    [BotMode.PushTowerTop] = "push_top",
    [BotMode.PushTowerMid] = "push_mid",
    [BotMode.PushTowerBot] = "push_bot",
    [BotMode.DefendTowerTop] = "defend_top",
    [BotMode.DefendTowerMid] = "defend_mid",
    [BotMode.DefendTowerBot] = "defend_bot",
    [BotMode.Assemble] = "assemble",
    [BotMode.TeamRoam] = "team_roam",
    [BotMode.Farm] = "farm",
    [BotMode.DefendAlly] = "defend_ally",
    [BotMode.EvasiveManeuvers] = "evasive",
    [BotMode.Roshan] = "roshan",
    [BotMode.Item] = "item",
    [BotMode.Ward] = "ward"
}
function ____exports.IsEnabled()
    local cfg = Config.Get()
    return cfg.Enable == true and cfg.Debug == true
end
function ____exports.ModeName(mode)
    return modeNames[mode] or "mode_" .. tostring(mode)
end
function ____exports.Log(tag, ...)
    local args = {...}
    if not ____exports.IsEnabled() then
        return
    end
    local parts = {("[H:" .. tag) .. "]"}
    for ____, arg in ipairs(args) do
        parts[#parts + 1] = tostring(arg)
    end
    local rawPrint = Utils.RawPrint;
    (rawPrint or print)(table.concat(parts, " "))
end
local probeTotal = 0
local probeByPlayer = {}
local probeTeamsSeen = {}
local probeLastLog = {}
function ____exports.SharedStateProbe(bot)
    if not ____exports.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    probeTotal = probeTotal + 1
    probeByPlayer[pid] = (probeByPlayer[pid] or 0) + 1
    probeTeamsSeen[bot:GetTeam()] = true
    local now = DotaTime()
    if now - (probeLastLog[pid] or -PROBE_LOG_INTERVAL) < PROBE_LOG_INTERVAL then
        return
    end
    probeLastLog[pid] = now
    local playersSeen = 0
    for ____, _ in ipairs(__TS__ObjectKeys(probeByPlayer)) do
        playersSeen = playersSeen + 1
    end
    local bothTeams = probeTeamsSeen[Team.Radiant] == true and probeTeamsSeen[Team.Dire] == true
    ____exports.Log(
        "probe",
        (((((((((("pid=" .. tostring(pid)) .. " team=") .. tostring(bot:GetTeam())) .. " total=") .. tostring(probeTotal)) .. " mine=") .. tostring(probeByPlayer[pid])) .. " playersInThisModule=") .. tostring(playersSeen)) .. " bothTeamsInThisModule=") .. tostring(bothTeams)
    )
end
return ____exports
