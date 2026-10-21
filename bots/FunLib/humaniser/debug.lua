--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ObjectEntries(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = {key, obj[key]}
    end
    return result
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
local LINE_HEIGHT = 14
local BLOCK_HEIGHT = 100
local TOP_OFFSET = 120
local RADIANT_X = 10
local DIRE_X = 1100
local DESIRE_STALE_SECONDS = 0.5
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
local linesByPlayer = {}
local desiresByPlayer = {}
function ____exports.IsEnabled()
    local cfg = Config.Get()
    return cfg.Enable == true and cfg.Debug == true
end
function ____exports.ModeName(mode)
    return modeNames[mode] or "mode_" .. tostring(mode)
end
--- Sets a persistent line for this bot, replaced on the next call with the same key.
function ____exports.Text(bot, key, text)
    if not ____exports.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    local lines = linesByPlayer[pid]
    if lines == nil then
        lines = {order = {}, text = {}}
        linesByPlayer[pid] = lines
    end
    if lines.text[key] == nil then
        local ____lines_order_0 = lines.order
        ____lines_order_0[#____lines_order_0 + 1] = key
    end
    lines.text[key] = text
end
function ____exports.Circle(loc, radius, r, g, b)
    if not ____exports.IsEnabled() then
        return
    end
    DebugDrawCircle(
        loc,
        radius,
        r,
        g,
        b
    )
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
--- Mode files can report their own GetDesire() results here so the overlay can rank them.
-- Modes that return nil fall through to Valve's C++ desire, which cannot be read.
function ____exports.RecordDesire(bot, mode, desire)
    if not ____exports.IsEnabled() or desire == nil then
        return
    end
    local pid = bot:GetPlayerID()
    local desires = desiresByPlayer[pid]
    if desires == nil then
        desires = {}
        desiresByPlayer[pid] = desires
    end
    desires[mode] = {
        value = desire,
        time = DotaTime()
    }
end
local function topDesires(pid, count)
    local desires = desiresByPlayer[pid]
    if desires == nil then
        return ""
    end
    local now = DotaTime()
    local fresh = {}
    for ____, ____value in ipairs(__TS__ObjectEntries(desires)) do
        local mode = ____value[1]
        local sample = ____value[2]
        if now - sample.time <= DESIRE_STALE_SECONDS then
            fresh[#fresh + 1] = {
                tonumber(mode),
                sample.value
            }
        end
    end
    __TS__ArraySort(
        fresh,
        function(____, a, b) return b[2] - a[2] end
    )
    local parts = {}
    do
        local i = 0
        while i < #fresh and i < count do
            parts[#parts + 1] = (____exports.ModeName(fresh[i + 1][1]) .. "=") .. string.format("%.2f", fresh[i + 1][2])
            i = i + 1
        end
    end
    return table.concat(parts, " ")
end
local function slotOf(bot)
    local players = GetTeamPlayers(bot:GetTeam())
    local pid = bot:GetPlayerID()
    do
        local i = 0
        while i < #players do
            if players[i + 1] == pid then
                return i
            end
            i = i + 1
        end
    end
    return 0
end
--- Draws this bot's overlay block. Call once per frame per bot.
function ____exports.Draw(bot)
    if not ____exports.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    local x = bot:GetTeam() == Team.Radiant and RADIANT_X or DIRE_X
    local y = TOP_OFFSET + slotOf(bot) * BLOCK_HEIGHT
    local header = ((((((string.gsub(
        bot:GetUnitName(),
        "npc_dota_hero_",
        ""
    )) .. " [") .. tostring(pid)) .. "] ") .. ____exports.ModeName(bot:GetActiveMode())) .. " ") .. string.format(
        "%.2f",
        bot:GetActiveModeDesire()
    )
    DebugDrawText(
        x,
        y,
        header,
        255,
        255,
        0
    )
    y = y + LINE_HEIGHT
    local top = topDesires(pid, 3)
    if top ~= "" then
        DebugDrawText(
            x,
            y,
            top,
            200,
            200,
            200
        )
        y = y + LINE_HEIGHT
    end
    local lines = linesByPlayer[pid]
    if lines == nil then
        return
    end
    for ____, key in ipairs(lines.order) do
        DebugDrawText(
            x,
            y,
            (key .. ": ") .. lines.text[key],
            255,
            255,
            255
        )
        y = y + LINE_HEIGHT
    end
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
