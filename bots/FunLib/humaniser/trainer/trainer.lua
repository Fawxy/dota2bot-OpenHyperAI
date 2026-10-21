--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/trainer/settings")
local ____api = require(GetScriptDirectory().."/FunLib/humaniser/trainer/api")
local GetTrainerHelpers = ____api.GetTrainerHelpers
local SetTrainerHelpers = ____api.SetTrainerHelpers
local ____spike = require(GetScriptDirectory().."/FunLib/humaniser/trainer/spike")
local SpikeTick = ____spike.SpikeTick
local REPLY_INTERVAL = 0.5
local USAGE = "usage: !trainer on|off|stats|reset|bar on|off|chat off|misses|all|denies on|off"
local teams = {}
function ____exports.SetHelpers(h)
    SetTrainerHelpers(h)
end
function ____exports.GetHelpers()
    return GetTrainerHelpers()
end
--- Same rule as commands.ts's lowestBotPID; not imported from there (commands.ts imports this module).
function ____exports.TrainerBotPID(team)
    local best
    for ____, pid in ipairs(GetTeamPlayers(team)) do
        if IsPlayerBot(pid) and (best == nil or pid < best) then
            best = pid
        end
    end
    return best
end
local function stateFor(team)
    local s = teams[team]
    if s == nil then
        local cfg = Settings.Get()
        s = {
            on = false,
            bar = cfg.Bar,
            chat = cfg.Chat,
            denies = cfg.Denies,
            spike = false,
            replies = {},
            lastReplyAt = -math.huge
        }
        teams[team] = s
    end
    return s
end
local function onOff(s)
    return s.on and "on" or "off"
end
local function status(s)
    return (((((("trainer " .. onOff(s)) .. " - bar ") .. (s.bar and "on" or "off")) .. " - chat ") .. s.chat) .. " - denies ") .. (s.denies and "on" or "off")
end
local function parseOnOff(word)
    if word == "on" then
        return true
    end
    if word == "off" then
        return false
    end
    return nil
end
function ____exports.OnCommand(team, _pid, args)
    if not Settings.IsEnabled() then
        return
    end
    local s = stateFor(team)
    local sub = args[1]
    local function reply(line)
        local ____s_replies_0 = s.replies
        local ____temp_1 = #____s_replies_0 + 1
        ____s_replies_0[____temp_1] = line
        return ____temp_1
    end
    if sub == nil then
        reply(status(s))
    elseif sub == "on" or sub == "off" then
        s.on = sub == "on"
        reply(status(s))
    elseif sub == "bar" or sub == "denies" then
        local value = parseOnOff(args[2])
        if value == nil then
            reply(USAGE)
        else
            if sub == "bar" then
                s.bar = value
            else
                s.denies = value
            end
            reply(status(s))
        end
    elseif sub == "chat" then
        local mode = args[2]
        if mode == "off" or mode == "misses" or mode == "all" then
            s.chat = mode
            reply(status(s))
        else
            reply(USAGE)
        end
    elseif sub == "stats" or sub == "reset" then
        HDebug.Log("trainer", sub, "not implemented yet")
    elseif sub == "spike" and Config.Get().Debug == true then
        s.spike = not s.spike
        HDebug.Log("trainer", "spike", s.spike and "on" or "off")
    else
        reply(USAGE)
    end
end
local function humanOnTeam(team)
    local players = GetTeamPlayers(team)
    do
        local i = 1
        while i <= #players do
            local member = GetTeamMember(i)
            if member ~= nil and member ~= nil and not IsPlayerBot(member:GetPlayerID()) then
                return member
            end
            i = i + 1
        end
    end
    return nil
end
function ____exports.Tick(bot)
    if not Settings.IsEnabled() then
        return
    end
    local team = bot:GetTeam()
    local s = teams[team]
    if s == nil or bot:GetPlayerID() ~= ____exports.TrainerBotPID(team) then
        return
    end
    local now = GameTime()
    if #s.replies > 0 and now - s.lastReplyAt >= REPLY_INTERVAL then
        s.lastReplyAt = now
        bot:ActionImmediate_Chat(
            table.remove(s.replies, 1),
            false
        )
    end
    if s.spike then
        local subject = humanOnTeam(team)
        if subject ~= nil then
            SpikeTick(bot, subject)
        end
    end
end
return ____exports
