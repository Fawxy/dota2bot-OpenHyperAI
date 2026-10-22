--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Rune = ____dota.Rune
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
local Runes = require(GetScriptDirectory().."/FunLib/humaniser/transitions/runes")
____exports.SOURCE = "transitions:mid_rune"
local states = {}
local function stateFor(bot)
    local pid = bot:GetPlayerID()
    local s = states[pid]
    if s == nil then
        s = {
            checkAt = -math.huge,
            claim = false,
            focus = false,
            preSpawn = false,
            doneSpawn = -1,
            skipSpawn = -1
        }
        states[pid] = s
    end
    return s
end
function ____exports.IsMid(bot)
    return LaneConfig.PositionOf(bot) == 2
end
function ____exports.IsOn(bot)
    return Settings.IsOn("MidRunes") and ____exports.IsMid(bot)
end
local function nearestPower(loc)
    local best = Rune.Power1
    local bestD = math.huge
    for ____, rune in ipairs({Rune.Power1, Rune.Power2}) do
        local spot = GetRuneSpawnLocation(rune)
        local d = math.sqrt((spot.x - loc.x) ^ 2 + (spot.y - loc.y) ^ 2)
        if d < bestD then
            bestD = d
            best = rune
        end
    end
    return best, bestD
end
--- The latest power spawn strictly before `now`, or undefined before the first.
local function lastSpawn(now)
    local last = Runes.NextSpawn("power", now) - Runes.RUNE_RULES.power.every
    return last >= Runes.RUNE_RULES.power.first and last < now and last or nil
end
local function refresh(bot, s, now)
    local cfg = Settings.Get()
    s.checkAt = now + cfg.Refresh
    local due = Runes.NextSpawn("power", now) - now
    local rune, dist = nearestPower(bot:GetLocation())
    local status = GetRuneStatus(rune)
    local last = lastSpawn(now)
    if last ~= nil and status == RUNE_STATUS_MISSING then
        s.doneSpawn = last
    end
    local pending = last ~= nil and s.doneSpawn ~= last and status ~= RUNE_STATUS_MISSING
    local inReach = dist <= cfg.MidRuneRadius
    s.preSpawn = due <= cfg.MidRuneFocus
    s.focus = s.preSpawn or pending and (status == RUNE_STATUS_AVAILABLE or inReach)
    s.claim = inReach and (due <= cfg.MidRuneLead or pending)
end
local function current(bot)
    local s = stateFor(bot)
    local now = DotaTime()
    if now >= s.checkAt then
        refresh(bot, s, now)
    end
    return s
end
--- For the rune mode: whether only power spots count (a power rune is due within MidRuneFocus or is up),
-- and whether it is due rather than up, so a MISSING (not yet spawned) power spot still counts.
function ____exports.Focus(bot)
    if not ____exports.IsOn(bot) then
        return false, false
    end
    local s = current(bot)
    return s.focus, s.focus and s.preSpawn
end
function ____exports.Tick(bot)
    if not ____exports.IsOn(bot) then
        return
    end
    local s = current(bot)
    if s.claim then
        Intent.Claim(
            bot,
            {
                source = ____exports.SOURCE,
                tier = "TRANSITION",
                mode = BotMode.Rune,
                floor = Settings.Get().MidRuneFloor
            }
        )
    end
end
--- The rune mode refused this frame (a safety gate, no power target): the floor must not apply.
function ____exports.Yield(bot)
    Intent.Release(bot, ____exports.SOURCE, BotMode.Rune)
end
--- rune_skip telemetry: a mid with little rune desire around a power spawn, at most once per spawn.
function ____exports.NoteSkip(bot, raw, desire, target, status, gate)
    if not Telemetry.IsEnabled() or not ____exports.IsMid(bot) then
        return
    end
    local cfg = Settings.Get()
    if type(desire) ~= "number" or desire >= cfg.MidRuneSkipDesire then
        return
    end
    local now = DotaTime()
    local next = Runes.NextSpawn("power", now)
    local last = lastSpawn(now)
    local spawn
    if next - now <= cfg.MidRuneSkipWindow then
        spawn = next
    elseif last ~= nil and now - last <= cfg.MidRuneSkipWindow then
        spawn = last
    end
    if spawn == nil then
        return
    end
    local s = stateFor(bot)
    if s.skipSpawn == spawn then
        return
    end
    s.skipSpawn = spawn
    Telemetry.Event(
        "rune_skip",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"spawn", spawn},
            {"target", target},
            {"status", status},
            {"raw", raw},
            {"desire", desire},
            {
                "laning",
                Intent.Competing(bot)
            },
            {"gate", gate}
        }
    )
end
return ____exports
