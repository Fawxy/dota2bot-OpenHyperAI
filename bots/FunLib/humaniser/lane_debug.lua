--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Chat = require(GetScriptDirectory().."/FunLib/humaniser/chat")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local FightProbe = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_probe")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local ____commands = require(GetScriptDirectory().."/FunLib/humaniser/commands")
local memberByPID = ____commands.memberByPID
local commands = {}
function ____exports.Register(name, fn)
    commands[string.lower(name)] = fn
end
local function fmt(v)
    return string.format("Vector(%.0f, %.0f, %.0f)", v.x, v.y, v.z)
end
____exports.Register(
    "hpt",
    function(_team, issuer)
        HDebug.Log(
            "lane",
            "hpt",
            fmt(issuer:GetLocation())
        )
    end
)
____exports.Register(
    "hcamp",
    function(team, issuer)
        local s = Camps.NearestSpawner(issuer:GetLocation())
        if s == nil then
            HDebug.Log("lane", "hcamp none")
            return
        end
        local job = Camps.ByIdx(s.idx, team)
        HDebug.Log(
            "lane",
            "hcamp",
            (((((((((((((("idx=" .. tostring(s.idx)) .. " team=") .. tostring(s.team)) .. " type=") .. s.type) .. " min=") .. fmt(s.min)) .. " max=") .. fmt(s.max)) .. " job=") .. (job and job.key or "-")) .. " source=") .. (job and job.source or "-")) .. " derived=") .. tostring(job and job.derived)
        )
    end
)
____exports.Register(
    "hfight",
    function(team, issuer)
        FightProbe.InstallCastLogger(team)
        for ____, line in ipairs(FightProbe.Run(issuer)) do
            HDebug.Log("fight", line)
        end
    end
)
function ____exports.HandleMessage(team, msg)
    if not HDebug.IsEnabled() or not LaneConfig.IsEnabled() then
        return
    end
    if not Chat.IsCommand(msg.text) or IsPlayerBot(msg.pid) then
        return
    end
    local words = {}
    for w in string.gmatch(
        string.sub(msg.text, 2),
        "%S+"
    ) do
        words[#words + 1] = string.lower(w)
    end
    local name = table.remove(words, 1)
    if name == nil then
        return
    end
    local fn = commands[name]
    if fn == nil then
        return
    end
    local issuer = memberByPID(team, msg.pid)
    if issuer == nil then
        return
    end
    fn(team, issuer, words)
end
local subscribed = {}
function ____exports.Tick(bot)
    if not HDebug.IsEnabled() or not LaneConfig.IsEnabled() then
        return
    end
    local team = bot:GetTeam()
    if subscribed[team] == true then
        return
    end
    subscribed[team] = true
    Chat.Subscribe(
        "lanedebug:" .. tostring(team),
        function(msg) return ____exports.HandleMessage(team, msg) end
    )
end
return ____exports
