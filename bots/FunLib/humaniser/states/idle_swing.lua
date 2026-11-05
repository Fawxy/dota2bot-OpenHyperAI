--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringTrim(self)
    local result = string.gsub(self, "^[%s ﻿]*(.-)[%s ﻿]*$", "%1")
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Lane = ____dota.Lane
local Team = ____dota.Team
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local LanePick = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_pick")
--- Dota lets a hero attack its own creep below half HP (the deny rule).
____exports.DENY_FRACTION = 0.5
--- Seconds of forecast for the pre-deny's kill time: four attack cycles at early attack speeds. `judgement`.
____exports.HORIZON = 6
--- Enemy heroes farther than this from the creep are not read (no threat within the horizon at lane speeds).
local ENEMY_RADIUS = 1600
--- Own lane creeps within this of the bot are pre-deny candidates (attack range plus a MAX_WALK walk is the real bound).
local CREEP_RADIUS = 900
--- Seconds until our hits kill a creep: our first landing at `first`, then one every `period`, each of `mean` damage, on the
-- creep's forecast HP without our hits (`hpAt`). The others' damage counts through `hpAt`. Math.huge when it outlives `horizon`.
function ____exports.KillTime(hpAt, first, period, mean, horizon)
    if mean <= 0 or period <= 0 then
        return math.huge
    end
    local k = 0
    do
        local t = first
        while t <= horizon do
            k = k + 1
            if hpAt(t) - k * mean <= 0 then
                return t
            end
            t = t + period
        end
    end
    return math.huge
end
--- Whether a pre-deny on our creep is safe from an enemy last hit: every enemy hero's time to reach attack range of it and swing
-- (`reach`, seconds) is longer than our kill time. No enemy hero near: always.
function ____exports.SafeFromEnemy(kill, reach)
    return reach == math.huge or reach > kill
end
--- `ForceShove` tokens: `bot`, `r:bot`, `d:top`, `all`, comma-separated (r Radiant, d Dire, no prefix both teams).
function ____exports.ForcedIn(spec, team, lane)
    if type(spec) ~= "string" or spec == "" then
        return false
    end
    local names = {top = Lane.Top, mid = Lane.Mid, bot = Lane.Bot}
    for raw in string.gmatch(spec, "[^,]+") do
        do
            local __continue9
            repeat
                local tok = __TS__StringTrim(string.lower(raw))
                local side
                local name = tok
                local p, rest = string.match(tok, "^([rd]):(.+)$")
                if p ~= nil then
                    side = p == "r" and Team.Radiant or Team.Dire
                    name = rest
                end
                if side ~= nil and side ~= team then
                    __continue9 = true
                    break
                end
                if name == "all" or names[name] == lane then
                    return true
                end
                __continue9 = true
            until true
            if not __continue9 then
                break
            end
        end
    end
    return false
end
--- The lane's mode for this laner: `shove` only where `Overrides.ForceShove` names its team and lane (slice 1 has no controller).
function ____exports.ModeOf(bot)
    return ____exports.ForcedIn(
        Overrides.Get("ForceShove"),
        bot:GetTeam(),
        bot:GetAssignedLane()
    ) and "shove" or "safe"
end
local notes = {}
--- The note of this bot's last idle swing, if it was on `creep`: a `prehit` target with no note is a tower pre-hit.
function ____exports.Of(pid, creep)
    local n = notes[pid]
    return n ~= nil and n.creep == creep and n or nil
end
--- Pre-denied creeps per bot, newest last, with the swings spent on each, for the later deny's `pre`.
local spent = {}
local SPENT_KEPT = 6
function ____exports.NoteSwing(pid, creep)
    local list = spent[pid]
    if list == nil then
        list = {}
        spent[pid] = list
    end
    for ____, e in ipairs(list) do
        if e.creep == creep then
            e.n = e.n + 1
            return
        end
    end
    list[#list + 1] = {creep = creep, n = 1}
    if #list > SPENT_KEPT then
        table.remove(list, 1)
    end
end
--- Pre-deny swings this bot spent on `creep` (undefined: none).
function ____exports.SpentOn(pid, creep)
    for ____, e in ipairs(spent[pid] or ({})) do
        if e.creep == creep then
            return e.n
        end
    end
    return nil
end
--- The bot's deny or last-hit count (GetDenies is missing from the API typings; 0 where a host lacks it).
function ____exports.Count(bot, name)
    local f = bot[name]
    return f ~= nil and f(bot) or 0
end
local function usable(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive()
end
--- Seconds the nearest enemy hero needs to walk into attack range of `creep` and land a swing (math.huge: none near).
local function enemyReach(bot, creep)
    local best = math.huge
    for ____, h in ipairs(bot:GetNearbyHeroes(ENEMY_RADIUS, true, 0) or ({})) do
        do
            local __continue28
            repeat
                if not usable(h) then
                    __continue28 = true
                    break
                end
                local speed = math.max(
                    100,
                    h:GetCurrentMovementSpeed()
                )
                local walk = math.max(
                    0,
                    GetUnitToUnitDistance(h, creep) - h:GetAttackRange()
                ) / speed
                local ____opt_0 = h.GetAttackPoint
                if ____opt_0 ~= nil then
                    ____opt_0 = ____opt_0(h)
                end
                local ____opt_0_2 = ____opt_0
                if ____opt_0_2 == nil then
                    ____opt_0_2 = 0.4
                end
                local t = walk + ____opt_0_2
                if t < best then
                    best = t
                end
                __continue28 = true
            until true
            if not __continue28 then
                break
            end
        end
    end
    return best
end
--- Our attack is busy until `busy`: a last hit or deny `mine` takes (other than on `creep`) due before then would be lost to it.
local function needed(me, verbs, busy, creep, mine)
    for ____, o in ipairs(verbs.laneTargets(me, {within = busy})) do
        do
            local __continue33
            repeat
                if o.creep == creep or mine ~= nil and not mine(o) then
                    __continue33 = true
                    break
                end
                if LanePick.Reachable(o) and o.eta <= busy then
                    return true
                end
                __continue33 = true
            until true
            if not __continue33 then
                break
            end
        end
    end
    return false
end
local function target(bot, creep)
    local walk = math.max(
        0,
        GetUnitToUnitDistance(bot, creep) - bot:GetAttackRange()
    ) / math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local c = creep
    return {
        creep = c,
        kind = "prehit",
        eta = walk,
        due = 0,
        walk = walk,
        dies = math.huge,
        ranged = LanePick.IsRanged(c)
    }
end
--- Allied heroes within this of the bot are read for the creep they are hitting (a partner's pre-deny or deny).
local ALLY_RADIUS = 1200
--- Creeps an allied hero other than `bot` is attacking now.
local function focused(bot)
    local out = {}
    for ____, h in ipairs(bot:GetNearbyHeroes(ALLY_RADIUS, false, 0) or ({})) do
        do
            local __continue39
            repeat
                if not usable(h) or h == bot then
                    __continue39 = true
                    break
                end
                local t = h:GetAttackTarget()
                if t ~= nil and t ~= nil then
                    out[t] = true
                end
                __continue39 = true
            until true
            if not __continue39 then
                break
            end
        end
    end
    return out
end
--- Order of pre-deny candidates: a creep a partner hits, then ranged, then lower HP.
function ____exports.Better(a, b)
    if b == nil then
        return true
    end
    if a.focus ~= b.focus then
        return a.focus
    end
    if a.ranged ~= b.ranged then
        return a.ranged
    end
    return a.hp < b.hp
end
local function findPreDeny(bot, me, verbs)
    local ____this_4
    ____this_4 = me
    local ____opt_3 = ____this_4.GetSecondsPerAttack
    local period = ____opt_3 and ____opt_3(____this_4) or 1.7
    local partner = focused(bot)
    local best
    local bestKey
    local bestNote
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(CREEP_RADIUS, false) or ({})) do
        do
            local __continue48
            repeat
                if not usable(c) or c:GetTeam() ~= bot:GetTeam() then
                    __continue48 = true
                    break
                end
                local max = c:GetMaxHealth()
                local hp = c:GetHealth()
                if max <= 0 or hp >= max * ____exports.DENY_FRACTION then
                    __continue48 = true
                    break
                end
                local walk = math.max(
                    0,
                    GetUnitToUnitDistance(bot, c) - bot:GetAttackRange()
                ) / math.max(
                    100,
                    bot:GetCurrentMovementSpeed()
                )
                if walk > LanePick.MAX_WALK then
                    __continue48 = true
                    break
                end
                local tc = c
                local f = verbs.hpForecast(me, tc, ____exports.HORIZON)
                local first = walk + verbs.ownHitTime(me, tc)
                local mean = c:GetActualIncomingDamage(
                    bot:GetAttackDamage(),
                    DamageType.Physical
                )
                if verbs.forecastHp(f, first) <= mean then
                    __continue48 = true
                    break
                end
                local kill = ____exports.KillTime(
                    function(t) return verbs.forecastHp(f, t) end,
                    first,
                    period,
                    mean,
                    ____exports.HORIZON
                )
                local reach = enemyReach(bot, c)
                if not ____exports.SafeFromEnemy(kill, reach) then
                    __continue48 = true
                    break
                end
                local key = {
                    focus = partner[c] ~= nil,
                    ranged = LanePick.IsRanged(tc),
                    hp = hp
                }
                if ____exports.Better(key, bestKey) then
                    best = c
                    bestKey = key
                    local at = c:GetLocation()
                    bestNote = {
                        kind = "predeny",
                        mode = "safe",
                        creep = tc,
                        hp = hp,
                        hf = hp / max,
                        x = at.x,
                        y = at.y,
                        kill = kill,
                        reach = reach,
                        focus = key.focus,
                        denies = 0,
                        lastHits = 0
                    }
                end
                __continue48 = true
            until true
            if not __continue48 then
                break
            end
        end
    end
    return {bestNote, best}
end
local function findShove(bot)
    local LaneTech = require(GetScriptDirectory().."/FunLib/humaniser/lane_tech")
    local near = {}
    local speed = math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(CREEP_RADIUS, true) or ({})) do
        do
            local __continue58
            repeat
                if not usable(c) then
                    __continue58 = true
                    break
                end
                if math.max(
                    0,
                    GetUnitToUnitDistance(bot, c) - bot:GetAttackRange()
                ) / speed <= LanePick.MAX_WALK then
                    near[#near + 1] = c
                end
                __continue58 = true
            until true
            if not __continue58 then
                break
            end
        end
    end
    local c = LaneTech.ShoveTarget(bot, near)
    if c == nil then
        return {nil, nil}
    end
    local max = c:GetMaxHealth()
    local at = c:GetLocation()
    return {
        {
            kind = "shove",
            mode = "shove",
            creep = c,
            hp = c:GetHealth(),
            hf = max > 0 and c:GetHealth() / max or 1,
            x = at.x,
            y = at.y,
            denies = 0,
            lastHits = 0
        },
        c
    }
end
--- The idle swing's switch: pre-deny under `Ours.PreDeny`; a forced shove needs no switch of its own (a harness knob).
function ____exports.Applies(mode)
    return mode == "shove" or Ours.On("PreDeny")
end
--- The idle swing this laner would make now, as a `prehit` LaneTarget, or undefined. `mine` is the picker's claims filter (a
-- support's last hits are only its claimed ones), so a core's last hit does not stop the support's swing.
function ____exports.Find(bot, verbs, mine)
    local mode = ____exports.ModeOf(bot)
    if not ____exports.Applies(mode) then
        return nil
    end
    local me = bot
    local note, creep = unpack(mode == "shove" and findShove(bot) or findPreDeny(bot, me, verbs))
    if note == nil or creep == nil then
        return nil
    end
    local t = target(bot, creep)
    local ____temp_7 = t.walk + verbs.ownHitTime(me, t.creep)
    local ____opt_5 = me.GetSecondsPerAttack
    local busy = ____temp_7 + (____opt_5 and ____opt_5(me) or 1.7)
    if needed(
        me,
        verbs,
        busy,
        t.creep,
        mine
    ) then
        return nil
    end
    note.denies = ____exports.Count(bot, "GetDenies")
    note.lastHits = ____exports.Count(bot, "GetLastHits")
    notes[bot:GetPlayerID()] = note
    return t
end
return ____exports
