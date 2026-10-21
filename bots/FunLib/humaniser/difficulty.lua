--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local GameState = ____dota.GameState
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Chat = require(GetScriptDirectory().."/FunLib/humaniser/chat")
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
local SKILL_CACHE_SECONDS = 5
local FRET_MARKER_MODIFIER = "modifier_special_bonus_cooldown_reduction"
local FRET_MARKER_MAX_LEVEL = 9
local FRET_MARKER_MAX_TIME = 300
local ALLY_VOTE_WINDOW = 40
local FRET_MAX_LEVEL = 10
local function valveDifficultyToSkill()
    return {
        [DIFFICULTY_PASSIVE] = 0,
        [DIFFICULTY_EASY] = 0.25,
        [DIFFICULTY_MEDIUM] = 0.5,
        [DIFFICULTY_HARD] = 0.75,
        [DIFFICULTY_UNFAIR] = 1
    }
end
local fretMarkerSeen = false
local difficultyVotes = {}
local allyScaleVotes = {}
local skillCache = {}
local function clamp(x, lo, hi)
    return x < lo and lo or (x > hi and hi or x)
end
local function average(votes)
    local total = 0
    local count = 0
    for ____, v in pairs(votes) do
        total = total + v
        count = count + 1
    end
    return count > 0 and total / count or nil
end
local function onChatForVotes(msg)
    local value = tonumber(msg.text)
    if value == nil then
        return
    end
    local state = GetGameState()
    if state < GameState.GameInProgress then
        if difficultyVotes[msg.pid] == nil then
            difficultyVotes[msg.pid] = clamp(value, 0, FRET_MAX_LEVEL)
        end
    elseif DotaTime() < ALLY_VOTE_WINDOW then
        if allyScaleVotes[msg.pid] == nil then
            allyScaleVotes[msg.pid] = clamp(value, 0, 1)
        end
    end
end
local subscribed = false
--- Must run before voting so the mirror sees the votes; called from the humaniser tick.
function ____exports.Init()
    if subscribed then
        return
    end
    subscribed = true
    Chat.Subscribe("difficulty-vote-mirror", onChatForVotes)
end
local function readBridgeModifier(bot, name)
    local index = bot:GetModifierByName(name)
    if index == nil or index < 0 then
        return nil
    end
    local stacks = bot:GetModifierStackCount(index)
    local level = stacks % 1000 / 10
    local allyScale = math.floor(stacks / 1000) / 100
    return {level, allyScale}
end
local function IsFretBotsMarked(bot)
    if fretMarkerSeen then
        return true
    end
    if DotaTime() > FRET_MARKER_MAX_TIME or bot:GetLevel() > FRET_MARKER_MAX_LEVEL then
        return false
    end
    if bot:HasModifier(FRET_MARKER_MODIFIER) then
        fretMarkerSeen = true
    end
    return fretMarkerSeen
end
function ____exports.GetFret(bot)
    local cfg = Config.Get()
    local override = cfg.FretBridge.FretBotsLevelOverride
    local ____Customize_Fretbots_0 = Customize.Fretbots
    if ____Customize_Fretbots_0 == nil then
        ____Customize_Fretbots_0 = {}
    end
    local defaults = ____Customize_Fretbots_0
    local ____defaults_Default_Difficulty_1 = defaults.Default_Difficulty
    if ____defaults_Default_Difficulty_1 == nil then
        ____defaults_Default_Difficulty_1 = 2
    end
    local defaultLevel = ____defaults_Default_Difficulty_1
    local ____defaults_Default_Ally_Scale_2 = defaults.Default_Ally_Scale
    if ____defaults_Default_Ally_Scale_2 == nil then
        ____defaults_Default_Ally_Scale_2 = 0.5
    end
    local defaultAllyScale = ____defaults_Default_Ally_Scale_2
    if override ~= nil then
        return {
            active = true,
            level = clamp(override, 0, FRET_MAX_LEVEL),
            allyScale = defaultAllyScale,
            source = "override"
        }
    end
    if cfg.FretBridge.BridgeModifier ~= nil then
        local bridged = readBridgeModifier(bot, cfg.FretBridge.BridgeModifier)
        if bridged ~= nil then
            return {active = true, level = bridged[1], allyScale = bridged[2], source = "modifier"}
        end
    end
    if not IsFretBotsMarked(bot) then
        return {active = false, level = 0, allyScale = 1, source = "inactive"}
    end
    local votedLevel = average(difficultyVotes)
    local votedScale = average(allyScaleVotes)
    if votedLevel ~= nil then
        return {active = true, level = votedLevel, allyScale = votedScale or defaultAllyScale, source = "chat"}
    end
    return {active = true, level = defaultLevel, allyScale = votedScale or defaultAllyScale, source = "default"}
end
function ____exports.GetValveSkill(bot)
    return valveDifficultyToSkill()[bot:GetDifficulty()] or 0.5
end
--- True when the bot's team has at least one human player.
function ____exports.IsAllyOfHuman(bot)
    for ____, pid in ipairs(GetTeamPlayers(bot:GetTeam())) do
        if not IsPlayerBot(pid) then
            return true
        end
    end
    return false
end
local function computeSkill(bot)
    local cfg = Config.Get()
    if cfg.SkillOverride ~= nil then
        return clamp(cfg.SkillOverride, 0, 1)
    end
    local valve = ____exports.GetValveSkill(bot)
    local fret = ____exports.GetFret(bot)
    if not fret.active then
        return valve
    end
    local fretSkill = fret.level / FRET_MAX_LEVEL
    if ____exports.IsAllyOfHuman(bot) then
        fretSkill = fretSkill * fret.allyScale
    end
    local weightTotal = cfg.ValveWeight + cfg.FretWeight
    if weightTotal <= 0 then
        return valve
    end
    return clamp((cfg.ValveWeight * valve + cfg.FretWeight * fretSkill) / weightTotal, 0, 1)
end
--- Skill in [0,1], cached per bot for 5 s.
function ____exports.GetSkill(bot)
    local pid = bot:GetPlayerID()
    local now = GameTime()
    local entry = skillCache[pid]
    if entry ~= nil and now - entry.time < SKILL_CACHE_SECONDS then
        return entry.skill
    end
    local skill = computeSkill(bot)
    skillCache[pid] = {skill = skill, time = now}
    return skill
end
return ____exports
