--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayPush(self, ...)
    local items = {...}
    local len = #self
    for i = 1, #items do
        len = len + 1
        self[len] = items[i]
    end
    return len
end
-- End of Lua Library inline imports
local ____exports = {}
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- Plan s3: above 0.95, the most Valve's attack showed, and at most 1.0, since above it J.IsRetreating reads a farm-mode
-- hero as retreating; under OHA's retreat latch (1.1). The value inside that band is judgement.
____exports.HARD = 0.98
--- Doctrine order: the first row that applies holds. Empty: the pass-through.
____exports.ROWS = {}
--- The mode file that hosts the decider. Its own desire is not computed while a row holds, so it never takes part in the retreat read.
local HOST = "farm"
--- judgement: a mode's value older than this is from neither this round nor the last (Valve asks every mode every round), so
-- its file was not asked and its value is not a rival.
local FRESH = 0.5
local heroes = {}
local function stateOf(bot)
    local pid = bot:GetPlayerID()
    local s = heroes[pid]
    if s == nil then
        s = {seen = {}}
        heroes[pid] = s
    end
    return s
end
local function pick(bot)
    for ____, row in ipairs(____exports.ROWS) do
        if row.applies(bot) then
            return row
        end
    end
    return nil
end
--- Chooser.Gate, for every gated mode file: the desire `mode`'s file returned to Valve. A value that is not a number (Valve's
-- own desire falls through) is not known, so it is forgotten.
function ____exports.NoteDesire(bot, mode, v)
    local seen = stateOf(bot).seen
    if type(v) == "number" then
        seen[mode] = {
            v = v,
            t = DotaTime()
        }
    else
        seen[mode] = nil
    end
end
--- Plan s3, user 23/11/2026: stock would retreat when the retreat file's desire leads every other mode the hold outbids. Each
-- value is the file's latest, this round's or the last, as Valve's order of calls gives it, so the read can lag the
-- retreat call by one round. Valve-only modes (attack for most heroes, item, evasive) have no file and are not seen: a
-- let-go they would have outbid only yields to stock. Returns the leading retreat value, else undefined.
local function retreatLeads(s)
    local now = DotaTime()
    local r = s.seen.retreat
    if r == nil or now - r.t > FRESH then
        return nil
    end
    for mode, n in pairs(s.seen) do
        do
            local __continue13
            repeat
                if mode == "retreat" or mode == HOST or now - n.t > FRESH then
                    __continue13 = true
                    break
                end
                if n.v >= r.v then
                    return nil
                end
                __continue13 = true
            until true
            if not __continue13 then
                break
            end
        end
    end
    return r.v
end
--- `win` is the mode Valve gave the hero from the last round's desires, read at this round's farm call: Valve asks every mode
-- once a round, so the hold or yield decided now shows up in the next line.
local function note(bot, s)
    if not Telemetry.IsEnabled() then
        return
    end
    local ____opt_0 = s.held
    local held = ____opt_0 and ____opt_0.name or "-"
    local win = HDebug.ModeName(bot:GetActiveMode())
    local let_ = s.letAt ~= nil
    if held == s.lineHeld and win == s.lineWin and let_ == s.lineLet then
        return
    end
    s.lineHeld = held
    s.lineWin = win
    s.lineLet = let_
    local fields = {
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", "decider"},
        {"held", held},
        {"win", win}
    }
    if s.letAt ~= nil then
        __TS__ArrayPush(fields, {"let", "retreat"}, {"d_retreat", s.letAt})
    end
    Telemetry.Event("choice", fields)
end
--- Wraps the host file's GetDesire: a held row's strength, else the inner desire unchanged. A row does not hold while stock would retreat.
function ____exports.Host(bot, inner)
    return function()
        local s = stateOf(bot)
        local row = pick(bot)
        local ____temp_2
        if row ~= nil then
            ____temp_2 = retreatLeads(s)
        else
            ____temp_2 = nil
        end
        s.letAt = ____temp_2
        local ____temp_3
        if s.letAt == nil then
            ____temp_3 = row
        else
            ____temp_3 = nil
        end
        s.held = ____temp_3
        pcall(function() return note(bot, s) end)
        return s.held ~= nil and ____exports.HARD or inner()
    end
end
--- Wraps the host file's Think: a held row's verb, not stepped while the bot cannot act (as Chooser.HostThink), else the inner Think.
function ____exports.HostThink(bot, inner, cannotAct)
    return function()
        local row = stateOf(bot).held
        if row == nil then
            return inner()
        end
        if cannotAct(bot) then
            return nil
        end
        if row.step(bot) then
            stateOf(bot).held = nil
        end
        return nil
    end
end
--- Tests: forget every hero.
function ____exports.Reset()
    for k in pairs(heroes) do
        heroes[k] = nil
    end
end
return ____exports
