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
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- Plan s3: above 0.95, the most Valve's attack showed, and at most 1.0, since above it J.IsRetreating reads a farm-mode
-- hero as retreating; under OHA's retreat latch (1.1). The value inside that band is judgement.
____exports.HARD = 0.98
--- Plan s3: what a soft hold is worth to Valve, entering or held: above laning's desire (0.45) and under every entry of Valve's
-- attack (none of 7,419 in h2hoha742 under 0.5), so attack, item, evasive and defend-ally outbid it when they want the hero.
-- The value inside that band is judgement.
____exports.SOFT = 0.495
--- Valve multiplies the active mode's desire by about this (derived: ev=snap d over the file's own value, oha-solo-deny
-- 22574266: laning 0.446 reads 0.491, an active soft hold 0.49 reads 0.539; not every round, and the hard hold's 0.98 was
-- never boosted). While the host mode is active a soft hold returns SOFT / BONUS, so it is worth about SOFT either way.
____exports.BONUS = 1.1
--- judgement: the most an OHA Lua mode file may return while a soft row holds (plan s3: the gate caps them beneath it).
-- With Valve's bonus on the active mode (CAP x BONUS, 0.484) it stays under SOFT, so an active capped mode cannot keep the
-- hero from a soft hold.
____exports.CAP = 0.44
--- Not capped under a soft hold: retreat (stock's way out; when it leads, the retreat read lets go) and attack's own file
-- (OHA's override of Valve's attack for a few heroes: the mode a soft hold gives way to; beyond plan s3's "retreat
-- excepted", decided 24/11/2026). `farm` is a guard only: while a row holds, Host never calls farm's gated desire.
local UNCAPPED = {retreat = true, attack = true, farm = true}
--- Doctrine order: the first row that applies holds. Empty: the pass-through.
____exports.ROWS = {}
--- The mode file that hosts the decider. Never a rival in the retreat read: its own desire is not computed while a row holds,
-- and counting it only when fresh (the round after a yield) would make the hold flicker every other round.
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
    if type(v) ~= "number" then
        seen[mode] = nil
        return
    end
    local n = seen[mode]
    if n == nil then
        seen[mode] = {
            v = v,
            t = DotaTime()
        }
    else
        n.v = v
        n.t = DotaTime()
    end
end
--- Plan s3, user 23/11/2026: stock would retreat when the retreat file's desire leads every other mode the hold outbids. Each
-- value is the file's latest within FRESH, as Valve's order of calls gives it, so the read can lag the retreat call by a
-- round. Valve-only modes (attack for most heroes, item, evasive) have no file and are not seen. Every error of this read
-- should only yield to stock, so a tie with a rival lets go (Valve's tie-break is not known); a retreat at 0 never leads.
-- Returns the leading retreat value, else undefined.
local function retreatLeads(s)
    local now = DotaTime()
    local r = s.seen.retreat
    if r == nil or r.v <= 0 or now - r.t > FRESH then
        return nil
    end
    for mode, n in pairs(s.seen) do
        do
            local __continue14
            repeat
                if mode == "retreat" or mode == HOST or now - n.t > FRESH then
                    __continue14 = true
                    break
                end
                if n.v > r.v then
                    return nil
                end
                __continue14 = true
            until true
            if not __continue14 then
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
    if s.held ~= nil then
        fields[#fields + 1] = {"hs", s.held.soft == true and "soft" or "hard"}
    end
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
        if s.held == nil then
            return inner()
        end
        if s.held.soft ~= true then
            return ____exports.HARD
        end
        return bot:GetActiveMode() == BotMode.Farm and ____exports.SOFT / ____exports.BONUS or ____exports.SOFT
    end
end
--- Chooser.Gate, for every gated mode file, after NoteDesire saw the value as returned: while a soft row holds, an OHA Lua
-- mode's desire above CAP is returned as CAP, so only the Valve-only modes, retreat and attack's file outbid the hold. The
-- hold is the one decided at the last farm call, so files Valve asks before farm lag by one round: uncapped in the round a
-- soft hold starts, still capped in the round it lets go or stops applying. The cap follows `held`, so the lag cannot
-- flicker on its own. Anything else, and any value that is not a number, passes unchanged.
-- 
-- Known effect, not stock's: retreat is uncapped, so a retreat value between SOFT and the highest raw Lua mode wins the hero
-- from the hold although the retreat read (raw values) keeps holding; stock would have run that Lua mode. Plan s3 accepts
-- it ("retreat excepted"); the first soft row's smoke counts it.
function ____exports.Cap(bot, mode, v)
    local s = heroes[bot:GetPlayerID()]
    local ____temp_4
    if s == nil then
        ____temp_4 = nil
    else
        ____temp_4 = s.held
    end
    local held = ____temp_4
    if held == nil or held.soft ~= true or UNCAPPED[mode] == true or type(v) ~= "number" then
        return v
    end
    return v > ____exports.CAP and ____exports.CAP or v
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
