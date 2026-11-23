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
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- Whether the line needs the gate's notes.
function ____exports.On()
    return Ours.On("ChoiceShadow")
end
--- The gate's mode name -> the name Valve's active mode logs as (debug.ts ModeName) and the BotMode Intent keys it by.
local MODES = {
    {"laning", "laning", BotMode.Laning},
    {"attack", "attack", BotMode.Attack},
    {"retreat", "retreat", BotMode.Retreat},
    {"farm", "farm", BotMode.Farm},
    {"team_roam", "team_roam", BotMode.TeamRoam},
    {"roam", "roam", BotMode.Roam},
    {"rune", "rune", BotMode.Rune},
    {"ward", "ward", BotMode.Ward},
    {"assemble", "assemble", BotMode.Assemble},
    {"assemble_with_humans", "assemble_h", nil},
    {"defend_tower_top", "defend_top", BotMode.DefendTowerTop},
    {"defend_tower_mid", "defend_mid", BotMode.DefendTowerMid},
    {"defend_tower_bot", "defend_bot", BotMode.DefendTowerBot},
    {"push_tower_top", "push_top", BotMode.PushTowerTop},
    {"push_tower_mid", "push_mid", BotMode.PushTowerMid},
    {"push_tower_bot", "push_bot", BotMode.PushTowerBot},
    {"roshan", "roshan", BotMode.Roshan},
    {"secret_shop", "secret_shop", BotMode.SecretShop},
    {"side_shop", "side_shop", BotMode.SideShop},
    {"outpost", "outpost", nil}
}
--- judgement: seconds between lines per hero when the active mode does not change.
local PERIOD = 1
--- judgement: a mode's note older than this is not this frame's (Valve asks every mode every frame).
local FRESH = 0.5
local heroes = {}
local function heroOf(pid)
    local h = heroes[pid]
    if h == nil then
        h = {frame = -math.huge, notes = {}, at = -math.huge, laneMark = false}
        heroes[pid] = h
    end
    return h
end
local BOT_MODE = {}
for ____, ____value in ipairs(MODES) do
    local mode = ____value[1]
    local botMode = ____value[3]
    BOT_MODE[mode] = botMode
end
--- Whether the inner value of `mode` is our desire, not OHA's (retreat's own episode). Neutral, but RetreatState.Owns is
-- read here earlier in the frame than without the line, so a line its first read logs may come out in another order.
local function oursFirst(bot, mode)
    return mode == "retreat" and RetreatState.Owns(bot)
end
--- Hook from mode_laning_generic's GetDesire (switch on only): its branch of ours (bOwnsThink's last hit at 0.9, a drill's
-- lane-only hold) set the value it is returning.
function ____exports.MarkMix(bot)
    if not ____exports.On() then
        return
    end
    pcall(function()
        heroOf(bot:GetPlayerID()).laneMark = true
    end)
end
--- Whether a branch of ours inside `mode`'s own GetDesire acted in the call just made (`ran`: OHA's code ran): laning's MarkMix.
local function mixOf(h, mode, ran)
    if mode ~= "laning" then
        return false
    end
    local m = h.laneMark
    h.laneMark = false
    return ran and m
end
--- Called by Chooser.Gate once per mode call, switch on: `inner` is what OHA's code returned (undefined when the gate did
-- not ask it: `why` names the gate's branch), `out` what the gate returns. Everything the line reads is taken here, in the
-- frame of the values.
function ____exports.Note(bot, mode, inner, out, why)
    pcall(function()
        local h = heroOf(bot:GetPlayerID())
        local n = {
            t = DotaTime(),
            out = out
        }
        if why ~= nil then
            n.why = why
        elseif type(inner) ~= "number" then
            n.why = "valve"
        elseif oursFirst(bot, mode) then
            n.why = "ours"
        else
            n.v = inner
        end
        if mixOf(h, mode, why == nil) then
            n.mix = true
        end
        h.notes[mode] = n
    end)
end
local function whyModule(why)
    if why == "hold:job" then
        return "JobChooser:Hold(job)"
    end
    if why == "hold:retreat" then
        return "Retreat:Hold(episode)"
    end
    if why == "host" then
        return "JobChooser:host"
    end
    if why == "drill" then
        return "Drill:InLaneDenies"
    end
    if why == "rig" then
        return "Drill:RigDesire"
    end
    return why
end
local EPS = 0.000001
local function emit(bot, h, act)
    local pid = bot:GetPlayerID()
    local fields = {{"pid", pid}, {"kind", "shadow"}, {"win", act}}
    local top
    local tv = 0
    local gate = {}
    local mix = {}
    local byName = {}
    for ____, ____value in ipairs(MODES) do
        local mode = ____value[1]
        local name = ____value[2]
        local n0 = h.notes[mode]
        local n = n0 ~= nil and h.frame - n0.t <= FRESH and n0 or nil
        byName[name] = n
        local val
        if n == nil then
            val = "-valve"
        elseif n.v == nil then
            val = "-" .. tostring((n.why == "hold:job" or n.why == "hold:retreat") and "hold" or (n.why == "host" and "ours" or n.why))
        else
            val = n.v
        end
        fields[#fields + 1] = {"d_" .. name, val}
        if n ~= nil and n.mix == true then
            mix[#mix + 1] = name
        end
        if n ~= nil and n.v ~= nil then
            if n.v > tv + EPS then
                tv = n.v
                top = name
            end
        end
        if n ~= nil and n.v ~= nil and type(n.out) == "number" and math.abs(n.out - n.v) > EPS then
            gate[#gate + 1] = (name .. ":") .. string.format("%.2f", n.out)
        end
    end
    local how
    local by
    if top ~= nil and top ~= act then
        local W = byName[act]
        if W == nil then
            how = "valve"
            by = "Valve:" .. act
        elseif W.v == nil and W.why ~= nil and W.why ~= "valve" then
            how = "outbid"
            by = W.why == "ours" and (act == "retreat" and "Retreat:Desire" or act) or whyModule(W.why)
        else
            how = "valve"
            by = "Valve:arbitration"
        end
    end
    __TS__ArrayPush(
        fields,
        {"top", top},
        {"tv", top ~= nil and tv or nil},
        {"how", how},
        {"by", by}
    )
    fields[#fields + 1] = {
        "mix",
        #mix > 0 and table.concat(mix, ",") or nil
    }
    fields[#fields + 1] = {
        "gate",
        #gate > 0 and table.concat(gate, ",") or nil
    }
    local r = byName.retreat
    if r ~= nil and r.why == "ours" and type(r.out) == "number" then
        fields[#fields + 1] = {"rdes", r.out}
    end
    local f = byName.farm
    if f ~= nil and f.v == nil and f.why == "host" and type(f.out) == "number" then
        fields[#fields + 1] = {"hdes", f.out}
    end
    Telemetry.EventUntyped("choice", fields)
end
--- Called first in every gate call, switch on: on a hero's first call of a new frame the last frame's notes are complete,
-- and the active mode is Valve's choice from them; a line goes out on a change of that mode or every PERIOD.
function ____exports.Frame(bot)
    pcall(function()
        local h = heroOf(bot:GetPlayerID())
        local now = DotaTime()
        if h.frame == now then
            return
        end
        local prev = h.frame
        if prev ~= -math.huge and Telemetry.IsEnabled() then
            local act = HDebug.ModeName(bot:GetActiveMode())
            if act ~= h.act or now - h.at >= PERIOD then
                emit(bot, h, act)
                h.act = act
                h.at = now
            end
        end
        h.frame = now
    end)
end
--- Tests: forget every hero.
function ____exports.Reset()
    for k in pairs(heroes) do
        heroes[k] = nil
    end
end
return ____exports
