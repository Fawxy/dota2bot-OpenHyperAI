--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
--- A sample older than this is not this frame's: the mode's desire is then Valve's own, which cannot be read.
local FRESH = 0.5
--- The gate's mode name -> the BotMode the active mode reads as; a mode with no BotMode in this build is not sampled.
local BOT_MODE = {
    laning = BotMode.Laning,
    attack = BotMode.Attack,
    retreat = BotMode.Retreat,
    farm = BotMode.Farm,
    team_roam = BotMode.TeamRoam,
    roam = BotMode.Roam,
    rune = BotMode.Rune,
    ward = BotMode.Ward,
    assemble = BotMode.Assemble,
    defend_tower_top = BotMode.DefendTowerTop,
    defend_tower_mid = BotMode.DefendTowerMid,
    defend_tower_bot = BotMode.DefendTowerBot,
    push_tower_top = BotMode.PushTowerTop,
    push_tower_mid = BotMode.PushTowerMid,
    push_tower_bot = BotMode.PushTowerBot,
    roshan = BotMode.Roshan,
    secret_shop = BotMode.SecretShop,
    side_shop = BotMode.SideShop
}
local samples = {}
function ____exports.Note(bot, mode, value)
    local m = BOT_MODE[mode]
    if m == nil or type(value) ~= "number" or bot:IsIllusion() then
        return
    end
    local pid = bot:GetPlayerID()
    local s = samples[pid]
    if s == nil then
        s = {}
        samples[pid] = s
    end
    local sample = s[m]
    if sample == nil then
        s[m] = {
            value = value,
            time = GameTime()
        }
    else
        sample.value = value
        sample.time = GameTime()
    end
end
--- "<mode> <desire> by raw", or "<mode> (valve)" for a mode whose own code was not asked just now.
function ____exports.Explain(bot, mode)
    local ____opt_0 = samples[bot:GetPlayerID()]
    local sample = ____opt_0 and ____opt_0[mode]
    if sample == nil or GameTime() - sample.time > FRESH then
        return HDebug.ModeName(mode) .. " (valve)"
    end
    return ((HDebug.ModeName(mode) .. " ") .. string.format("%.2f", sample.value)) .. " by raw"
end
--- The freshest desires, highest first, at most four: "farm=0.62 laning=0.40".
function ____exports.Competing(bot)
    local s = samples[bot:GetPlayerID()]
    if s == nil then
        return ""
    end
    local now = GameTime()
    local fresh = {}
    for mode, sample in pairs(s) do
        if now - sample.time <= FRESH then
            fresh[#fresh + 1] = {mode, sample.value}
        end
    end
    __TS__ArraySort(
        fresh,
        function(____, a, b) return b[2] - a[2] end
    )
    local parts = {}
    do
        local i = 0
        while i < #fresh and i < 4 do
            parts[#parts + 1] = (HDebug.ModeName(fresh[i + 1][1]) .. "=") .. string.format("%.2f", fresh[i + 1][2])
            i = i + 1
        end
    end
    return table.concat(parts, " ")
end
return ____exports
