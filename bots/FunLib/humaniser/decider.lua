--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- Plan s3: above 0.95, the most Valve's attack showed, and at most 1.0, since above it J.IsRetreating reads a farm-mode
-- hero as retreating; under OHA's retreat latch (1.1). The value inside that band is judgement.
____exports.HARD = 0.98
--- Doctrine order: the first row that applies holds. Empty: the pass-through.
____exports.ROWS = {}
local heroes = {}
local function stateOf(bot)
    local pid = bot:GetPlayerID()
    local s = heroes[pid]
    if s == nil then
        s = {}
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
--- `win` is the mode Valve gave the hero from the last round's desires, read at this round's farm call: Valve asks every mode
-- once a round, so the hold or yield decided now shows up in the next line.
local function note(bot, s)
    if not Telemetry.IsEnabled() then
        return
    end
    local ____opt_0 = s.held
    local held = ____opt_0 and ____opt_0.name or "-"
    local win = HDebug.ModeName(bot:GetActiveMode())
    if held == s.lineHeld and win == s.lineWin then
        return
    end
    s.lineHeld = held
    s.lineWin = win
    Telemetry.Event(
        "choice",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "decider"},
            {"held", held},
            {"win", win}
        }
    )
end
--- Wraps the host file's GetDesire: a held row's strength, else the inner desire unchanged.
function ____exports.Host(bot, inner)
    return function()
        local s = stateOf(bot)
        s.held = pick(bot)
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
