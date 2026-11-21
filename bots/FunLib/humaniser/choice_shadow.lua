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
local Arbiter = require(GetScriptDirectory().."/FunLib/humaniser/arbiter")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Trade = require(GetScriptDirectory().."/FunLib/humaniser/states/trade")
--- Whether the line or the probe needs the gate's notes (both need ChoiceShadow).
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
--- The modes Ours.ChoiceProbe asks where the drive zeroes them before their code.
____exports.PROBED = {roam = true, team_roam = true}
--- judgement: seconds between lines per hero when the active mode does not change.
local PERIOD = 1
--- judgement: a mode's note older than this is not this frame's (Valve asks every mode every frame).
local FRESH = 0.5
local heroes = {}
local function heroOf(pid)
    local h = heroes[pid]
    if h == nil then
        h = {
            frame = -math.huge,
            notes = {},
            at = -math.huge,
            snapFrame = -math.huge,
            snap = {},
            laneMark = false
        }
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
--- Whether the inner value of `mode` is our desire, not OHA's (retreat's own episode, the trade's attack desire). Neutral,
-- but RetreatState.Owns reaches Phase.LaningHeld here, earlier in the frame than without the line, so its first read's
-- `arb ph=own` line may come out in another order beside the frame's other lines.
local function oursFirst(bot, mode)
    if mode == "retreat" then
        return RetreatState.Owns(bot)
    end
    if mode == "attack" then
        return Trade.OwnsFrame(bot)
    end
    return false
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
--- Whether a branch of ours inside `mode`'s own GetDesire acted in the call just made (`ran`: OHA's code ran): laning's
-- MarkMix; team_roam: Trade's fights skip OHA's fight branches; rune: DeniesOhaRune denies OHA's trips.
local function mixOf(bot, h, mode, ran)
    if mode == "laning" then
        local m = h.laneMark
        h.laneMark = false
        return ran and m
    end
    if not ran then
        return false
    end
    if mode == "team_roam" then
        return Trade.OwnsFights(bot)
    end
    if mode == "rune" then
        return Arbiter.DeniesOhaRune(bot)
    end
    return false
end
--- The source of an Intent claim on the mode's value (Intent.Explain's `by`), when not raw.
local function claimOf(bot, botMode)
    if botMode == nil then
        return nil
    end
    local e = Intent.Explain(bot, botMode)
    local src = string.match(e, " by (.+)$")
    return src ~= nil and src ~= "raw" and src or nil
end
--- The drive's pick once Decide has computed it this frame, and the candidates that apply beside it (read only).
local function snapshot(bot, h)
    if h.snapFrame ~= h.frame then
        h.snapFrame = h.frame
        h.snap = {}
    end
    if h.snap.pick ~= nil or not Arbiter.Drives(bot) then
        return
    end
    local p = Arbiter.PickThisFrame(bot)
    if p == nil then
        return
    end
    local cands = {}
    local ____Arbiter_Candidates_2 = Arbiter.Candidates
    local ____bot_1 = bot
    local ____temp_0
    if h.jobName ~= nil then
        ____temp_0 = h.jobName()
    else
        ____temp_0 = nil
    end
    for ____, c in ipairs(____Arbiter_Candidates_2(____bot_1, ____temp_0)) do
        if c.applies then
            cands[#cands + 1] = (c.name .. ":") .. tostring(c.group)
        end
    end
    h.snap = {
        pick = p.name,
        host = p.host,
        group = p.group,
        cand = table.concat(cands, ",")
    }
end
--- Called by Chooser.Gate once per mode call, switch on: `inner` is what OHA's code returned (undefined when the gate did
-- not ask it: `why` names the gate's branch), `out` what the gate returns. Everything the line reads is taken here, in the
-- frame of the values.
function ____exports.Note(bot, mode, inner, out, why, probed)
    pcall(function()
        local h = heroOf(bot:GetPlayerID())
        snapshot(bot, h)
        local n = {
            t = DotaTime(),
            out = out,
            probed = probed
        }
        if probed and type(inner) ~= "number" then
            n.why = "probe"
        elseif why ~= nil and not probed then
            n.why = why
        elseif type(inner) ~= "number" then
            n.why = "valve"
        elseif oursFirst(bot, mode) then
            n.why = "ours"
        else
            n.v = inner
        end
        if mixOf(bot, h, mode, why == nil or probed) then
            n.mix = true
        end
        if n.v ~= nil and not probed then
            n.clm = claimOf(bot, BOT_MODE[mode])
        end
        h.notes[mode] = n
    end)
end
--- Runs OHA's body for a probed mode; its value or undefined. The caller returns the drive's value whatever this does.
function ____exports.Probe(inner)
    local ok, v = pcall(inner)
    local ____ok_3
    if ok then
        ____ok_3 = v
    else
        ____ok_3 = nil
    end
    return ____ok_3
end
local function whyModule(why, pick)
    if why == "drive" then
        return ("ArbiterDrive:DriveDecide(" .. (pick or "?")) .. ")"
    end
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
    local snap = h.snapFrame == h.frame and h.snap or ({})
    local pick = snap.pick
    local fields = {{"pid", pid}, {"kind", "shadow"}, {"win", act}}
    local top
    local tv = 0
    local gate = {}
    local probed = {}
    local claims = {}
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
            if n.probed then
                probed[#probed + 1] = name
            end
            if n.clm ~= nil then
                claims[#claims + 1] = (name .. "=") .. n.clm
            end
        end
        if n ~= nil and n.v ~= nil and type(n.out) == "number" and math.abs(n.out - n.v) > EPS then
            gate[#gate + 1] = (name .. ":") .. string.format("%.2f", n.out)
        end
    end
    local how
    local by
    if top ~= nil and top ~= act then
        local T = byName[top]
        local W = byName[act]
        local wOut = W ~= nil and type(W.out) == "number" and W.out or nil
        if type(T.out) == "number" and T.out < T.v - EPS and (wOut == nil or T.v > wOut + EPS) then
            how = "zeroed"
            by = T.probed and whyModule("drive", pick) or ("ArbiterDrive:DriveAfter borrowed(" .. (pick or "?")) .. ")"
        elseif W == nil then
            how = "valve"
            by = "Valve:" .. act
        elseif W.v == nil and W.why ~= nil and W.why ~= "valve" and W.why ~= "probe" then
            how = "outbid"
            by = W.why == "ours" and (act == "retreat" and "Retreat:Desire" or (act == "attack" and "Trade:Desire" or act)) or whyModule(W.why, pick)
        elseif W.v ~= nil and wOut ~= nil and wOut > W.v + EPS then
            how = "held"
            by = act == "laning" and "ArbiterDrive:DriveAfter lane_floor" or ("ArbiterDrive:DriveAfter(" .. act) .. ")"
        elseif W.clm ~= nil then
            how = "outbid"
            by = "Intent:" .. W.clm
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
        "clm",
        #claims > 0 and table.concat(claims, ",") or nil
    }
    fields[#fields + 1] = {
        "pr",
        #probed > 0 and table.concat(probed, ",") or nil
    }
    fields[#fields + 1] = {
        "gate",
        #gate > 0 and table.concat(gate, ",") or nil
    }
    if pick ~= nil then
        fields[#fields + 1] = {"pick", pick}
        fields[#fields + 1] = {"cand", snap.cand}
        fields[#fields + 1] = {"lfl", pick == "lane" and Arbiter.SETTINGS.LaneDesire or nil}
    end
    local r = byName.retreat
    if r ~= nil and r.why == "ours" and type(r.out) == "number" then
        fields[#fields + 1] = {"rdes", r.out}
    end
    local a = byName.attack
    if a ~= nil and a.why == "ours" and type(a.out) == "number" then
        fields[#fields + 1] = {"tdes", a.out}
    end
    local f = byName.farm
    local farmHost = f ~= nil and f.v == nil and (f.why == "host" or f.why == "drive" and pick ~= nil and (snap.host == "farm" or (snap.group or 0) > 6))
    if farmHost and type(f.out) == "number" then
        fields[#fields + 1] = {"hdes", f.out}
    end
    Telemetry.EventUntyped("choice", fields)
end
--- Called first in every gate call, switch on: on a hero's first call of a new frame the last frame's notes are complete,
-- and the active mode is Valve's choice from them; a line goes out on a change of that mode or every PERIOD.
function ____exports.Frame(bot, jobName)
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
        h.jobName = jobName
    end)
end
--- Tests: forget every hero.
function ____exports.Reset()
    for k in pairs(heroes) do
        heroes[k] = nil
    end
end
return ____exports
