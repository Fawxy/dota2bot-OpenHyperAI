--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local REFRESH_SECONDS = 5
local profiles = {}
local function lerp(low, high, skill)
    return low + (high - low) * skill
end
local function fill(profile, skill)
    local p = Config.Get().Profile
    profile.skill = skill
    profile.noticeBase = lerp(p.NoticeLow, p.NoticeHigh, skill) * profile.personal
    profile.reactBase = math.max(
        p.MinReact,
        lerp(p.ReactLow, p.ReactHigh, skill) * profile.personal
    )
    profile.pingBase = lerp(p.PingLow, p.PingHigh, skill) * profile.personal
    profile.chatBase = lerp(p.ChatLow, p.ChatHigh, skill) * profile.personal
    profile.jitter = lerp(p.JitterLow, p.JitterHigh, skill)
    profile.lapseChance = lerp(p.LapseLow, p.LapseHigh, skill)
    profile.aimError = lerp(p.AimErrorLow, p.AimErrorHigh, skill)
    profile.deference = lerp(1, 0, skill)
end
function ____exports.Get(bot)
    local pid = bot:GetPlayerID()
    local profile = profiles[pid]
    local now = GameTime()
    if profile == nil then
        local p = Config.Get().Profile
        profile = {
            skill = 0,
            personal = RandomFloat(p.PersonalMin, p.PersonalMax),
            noticeBase = 0,
            reactBase = 0,
            pingBase = 0,
            chatBase = 0,
            jitter = 0,
            lapseChance = 0,
            aimError = 0,
            deference = 0,
            refreshedAt = now
        }
        profiles[pid] = profile
        fill(
            profile,
            Difficulty.GetSkill(bot)
        )
    elseif now - profile.refreshedAt >= REFRESH_SECONDS then
        profile.refreshedAt = now
        fill(
            profile,
            Difficulty.GetSkill(bot)
        )
    end
    return profile
end
local function baseFor(profile, kind)
    if kind == "notice" then
        return profile.noticeBase
    end
    if kind == "react" then
        return profile.reactBase
    end
    if kind == "ping" then
        return profile.pingBase
    end
    return profile.chatBase
end
--- A human-like delay in seconds: base ± jitter, with an occasional "wasn't looking" lapse.
function ____exports.SampleDelay(bot, kind)
    local profile = ____exports.Get(bot)
    local p = Config.Get().Profile
    local delay = baseFor(profile, kind) * (1 - profile.jitter / 2 + RandomFloat(0, profile.jitter))
    if RandomFloat(0, 1) < profile.lapseChance then
        delay = delay + RandomFloat(p.LapseMinExtra, p.LapseMaxExtra)
    end
    if kind == "react" then
        delay = math.max(p.MinReact, delay)
    end
    return delay
end
return ____exports
