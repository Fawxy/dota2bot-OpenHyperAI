--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {GiveUpAfter = 3, Near = 150, LeftAt = 400, SpawnEvery = 120}
local tries = {}
local unpickableUntil = {}
function ____exports.ResetCache()
    for k in pairs(tries) do
        tries[k] = nil
    end
    for k in pairs(unpickableUntil) do
        unpickableUntil[k] = nil
    end
end
function ____exports.On()
    return Ours.On("RuneSpawn")
end
local function actionType(bot)
    return bot:GetCurrentActionType()
end
--- The next river spawn after `now` (2:00, 4:00, ...).
function ____exports.NextSpawn(now)
    return (math.floor(math.max(now, 0) / ____exports.SETTINGS.SpawnEvery) + 1) * ____exports.SETTINGS.SpawnEvery
end
--- Given up by any hero of this team until the rune's next spawn.
function ____exports.Unpickable(rune, now)
    if now == nil then
        now = DotaTime()
    end
    local ____until = unpickableUntil[rune]
    return ____until ~= nil and now < ____until
end
local function line(bot, t, res, now)
    Telemetry.Event(
        "rune_try",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"rune", t.rune},
            {"res", res},
            {
                "d",
                math.floor(GetUnitToLocationDistance(
                    bot,
                    GetRuneSpawnLocation(t.rune)
                ))
            },
            {"act0", t.act0},
            {
                "act",
                actionType(bot)
            },
            {
                "st",
                GetRuneStatus(t.rune)
            },
            {
                "dt",
                math.floor((now - t.from) * 10) / 10
            }
        }
    )
end
--- Every frame from the rune mode: closes this hero's open try once the rune went or the hero walked off.
function ____exports.Tick(bot, now)
    if now == nil then
        now = DotaTime()
    end
    local pid = bot:GetPlayerID()
    local t = tries[pid]
    if t == nil then
        return
    end
    if GetRuneStatus(t.rune) ~= RUNE_STATUS_AVAILABLE then
        line(bot, t, "gone", now)
        tries[pid] = nil
    elseif GetUnitToLocationDistance(
        bot,
        GetRuneSpawnLocation(t.rune)
    ) > ____exports.SETTINGS.LeftAt then
        line(bot, t, "left", now)
        tries[pid] = nil
    end
end
--- Before each pickup order: false when the rune is given up (the caller does not order it). Gives the rune up once this
-- hero has been ordering it within Near for GiveUpAfter seconds while it stays available.
function ____exports.Try(bot, rune, now)
    if now == nil then
        now = DotaTime()
    end
    if ____exports.Unpickable(rune, now) then
        return false
    end
    local pid = bot:GetPlayerID()
    local t = tries[pid]
    if t ~= nil and t.rune ~= rune then
        line(bot, t, "left", now)
        t = nil
    end
    if t == nil then
        t = {
            rune = rune,
            from = now,
            act0 = actionType(bot)
        }
        tries[pid] = t
        line(bot, t, "try", now)
        return true
    end
    local near = GetUnitToLocationDistance(
        bot,
        GetRuneSpawnLocation(rune)
    ) <= ____exports.SETTINGS.Near
    if near and now - t.from >= ____exports.SETTINGS.GiveUpAfter and GetRuneStatus(rune) == RUNE_STATUS_AVAILABLE then
        unpickableUntil[rune] = ____exports.NextSpawn(now)
        line(bot, t, "gave_up", now)
        tries[pid] = nil
        return false
    end
    if not near then
        t.from = now
    end
    return true
end
return ____exports
