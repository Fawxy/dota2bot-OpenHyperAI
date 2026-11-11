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
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
--- Dota lets a hero attack its own creep below half HP (the deny rule).
____exports.DENY_FRACTION = 0.5
--- Seconds of forecast for the pre-deny's kill time: four attack cycles at early attack speeds. `judgement`.
____exports.HORIZON = 6
--- Enemy heroes farther than this from the creep are not read (no threat within the horizon at lane speeds).
local ENEMY_RADIUS = 1600
--- Lane creeps the idle swing can reach: the bot's attack range plus the walk it allows (`LanePick.MAX_WALK` at its current speed),
-- the same distance the per-creep `walk` test uses, capped at the old fixed 900 so the scan only ever shrinks.
local CREEP_RADIUS_CAP = 900
local function creepRadius(bot)
    return math.min(
        CREEP_RADIUS_CAP,
        bot:GetAttackRange() + LanePick.MAX_WALK * math.max(
            100,
            bot:GetCurrentMovementSpeed()
        )
    )
end
--- Setup: our hits to the kill, this swing and the last hit included (`judgement`: "hit a creep twice and get an easy last
-- hit", user 06/11/2026).
____exports.SETUP_HITS = 3
--- Fallback only: a tower's reach to a target's centre (7.41: attack range 700 + bounding radius 144), read live by
-- WorldFacts.TowerReach. The setup's clearance is that reach plus the creep's own radius (slice 4; was TOWER_CLEAR 800).
local TOWER_REACH = 844
--- Fallbacks only (logged once per game through WorldFacts.Fallback): attack period and an enemy's attack point.
local PERIOD_FALLBACK = 1.7
local ATTACK_POINT_FALLBACK = 0.4
--- Our attack period from the API, the counted fallback when the read gives nothing.
local function periodOf(me)
    local ____this_1
    ____this_1 = me
    local ____opt_0 = ____this_1.GetSecondsPerAttack
    local p = ____opt_0 and ____opt_0(____this_1)
    return p ~= nil and p > 0 and p or WorldFacts.Fallback("attack_period", PERIOD_FALLBACK)
end
--- Seconds until our hits kill a creep: our first landing at `first`, then one every `period`, each of `mean` damage, on the
-- creep's forecast HP without our hits (`hpAt`). The others' damage counts through `hpAt`. Math.huge when it outlives `horizon`;
-- RACE_LOST when the others kill it before one of our hits lands (the deny would come due while our attack is on cooldown).
function ____exports.KillTime(hpAt, first, period, mean, horizon)
    if mean <= 0 or period <= 0 then
        return math.huge
    end
    local k = 0
    do
        local t = first
        while t <= horizon do
            local left = hpAt(t) - k * mean
            if left <= 0 then
                return ____exports.RACE_LOST
            end
            k = k + 1
            if left - mean <= 0 then
                return t
            end
            t = t + period
        end
    end
    return math.huge
end
--- KillTime's value for a creep the others kill between our hits.
____exports.RACE_LOST = -1
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
            local __continue12
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
                    __continue12 = true
                    break
                end
                if name == "all" or names[name] == lane then
                    return true
                end
                __continue12 = true
            until true
            if not __continue12 then
                break
            end
        end
    end
    return false
end
--- Required at the call: lane_control's imports (rune_job, stack_job) reach the chooser and the laning body.
local function laneControl()
    return require(GetScriptDirectory().."/FunLib/humaniser/lane_control")
end
--- The lane's mode for this laner: `shove` where `Overrides.ForceShove` names its team and lane, else the lane controller's.
function ____exports.ModeOf(bot)
    if ____exports.ForcedIn(
        Overrides.Get("ForceShove"),
        bot:GetTeam(),
        bot:GetAssignedLane()
    ) then
        return "shove"
    end
    return laneControl().ModeFor(
        bot:GetTeam(),
        bot:GetAssignedLane()
    )
end
--- Whether the lane controller asks this lane for the setup swing (its intent `forward` in mode `safe`).
function ____exports.SetupWanted(bot)
    return laneControl().Chosen(
        bot:GetTeam(),
        bot:GetAssignedLane(),
        "setup"
    ) == true
end
--- Our hits to a kill at `kill` from the first landing at `first`, one every `period` (this swing included).
function ____exports.HitsTo(kill, first, period)
    return math.floor((kill - first) / math.max(0.01, period) + 0.5) + 1
end
local notes = {}
--- The note of this bot's last idle swing, if it was on `creep`: a `prehit` target with no note is a tower pre-hit.
function ____exports.Of(pid, creep)
    local n = notes[pid]
    return n ~= nil and n.creep == creep and n or nil
end
--- Forgets the bot's note once its swing is logged.
function ____exports.Clear(pid)
    notes[pid] = nil
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
            local __continue36
            repeat
                if not usable(h) then
                    __continue36 = true
                    break
                end
                local speed = math.max(
                    100,
                    h:GetCurrentMovementSpeed()
                )
                local gap = GetUnitToUnitDistance(h, creep) - h:GetAttackRange() - (h:GetBoundingRadius() or 0) - (creep:GetBoundingRadius() or 0)
                local walk = math.max(0, gap) / speed
                local ____this_3
                ____this_3 = h
                local ____opt_2 = ____this_3.GetAttackPoint
                local point = ____opt_2 and ____opt_2(____this_3)
                local t = walk + (point ~= nil and point >= 0 and point or WorldFacts.Fallback("attack_point", ATTACK_POINT_FALLBACK))
                if t < best then
                    best = t
                end
                __continue36 = true
            until true
            if not __continue36 then
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
            local __continue41
            repeat
                if o.creep == creep or mine ~= nil and not mine(o) then
                    __continue41 = true
                    break
                end
                if LanePick.Reachable(o) and o.eta <= busy then
                    return true
                end
                __continue41 = true
            until true
            if not __continue41 then
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
            local __continue47
            repeat
                if not usable(h) or h == bot then
                    __continue47 = true
                    break
                end
                local t = h:GetAttackTarget()
                if t ~= nil and t ~= nil then
                    out[t] = true
                end
                __continue47 = true
            until true
            if not __continue47 then
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
    local period = periodOf(me)
    local partner = focused(bot)
    local best
    local bestKey
    local bestNote
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(
        creepRadius(bot),
        false
    ) or ({})) do
        do
            local __continue56
            repeat
                if not usable(c) or c:GetTeam() ~= bot:GetTeam() then
                    __continue56 = true
                    break
                end
                local max = c:GetMaxHealth()
                local hp = c:GetHealth()
                if max <= 0 or hp >= max * ____exports.DENY_FRACTION then
                    __continue56 = true
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
                    __continue56 = true
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
                    __continue56 = true
                    break
                end
                local kill = ____exports.KillTime(
                    function(t) return verbs.forecastHp(f, t) end,
                    first,
                    period,
                    mean,
                    ____exports.HORIZON
                )
                if kill == ____exports.RACE_LOST then
                    __continue56 = true
                    break
                end
                local reach = enemyReach(bot, c)
                if not ____exports.SafeFromEnemy(kill, reach) then
                    __continue56 = true
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
                __continue56 = true
            until true
            if not __continue56 then
                break
            end
        end
    end
    return {bestNote, best}
end
local function nearEnemyTower(bot, c)
    for ____, tw in ipairs(bot:GetNearbyTowers(1600, true) or ({})) do
        if usable(tw) and GetUnitToUnitDistance(tw, c) <= WorldFacts.TowerReach(tw, TOWER_REACH) + (c:GetBoundingRadius() or 0) then
            return true
        end
    end
    return false
end
--- Order of setup candidates: fewer of our hits to the kill, then ranged (more gold), then lower HP.
function ____exports.BetterSetup(a, b)
    if b == nil then
        return true
    end
    if a.hits ~= b.hits then
        return a.hits < b.hits
    end
    if a.ranged ~= b.ranged then
        return a.ranged
    end
    return a.hp < b.hp
end
local function findSetup(bot, me, verbs)
    local period = periodOf(me)
    local best
    local bestKey
    local bestNote
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(
        creepRadius(bot),
        true
    ) or ({})) do
        do
            local __continue75
            repeat
                if not usable(c) then
                    __continue75 = true
                    break
                end
                local max = c:GetMaxHealth()
                local hp = c:GetHealth()
                if max <= 0 then
                    __continue75 = true
                    break
                end
                local walk = math.max(
                    0,
                    GetUnitToUnitDistance(bot, c) - bot:GetAttackRange()
                ) / math.max(
                    100,
                    bot:GetCurrentMovementSpeed()
                )
                if walk > LanePick.MAX_WALK or nearEnemyTower(bot, c) then
                    __continue75 = true
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
                    __continue75 = true
                    break
                end
                local kill = ____exports.KillTime(
                    function(t) return verbs.forecastHp(f, t) end,
                    first,
                    period,
                    mean,
                    ____exports.HORIZON
                )
                if kill == ____exports.RACE_LOST or kill == math.huge then
                    __continue75 = true
                    break
                end
                local hits = ____exports.HitsTo(kill, first, period)
                if hits > ____exports.SETUP_HITS then
                    __continue75 = true
                    break
                end
                local reach = enemyReach(bot, c)
                if not ____exports.SafeFromEnemy(kill, reach) then
                    __continue75 = true
                    break
                end
                local key = {
                    hits = hits,
                    ranged = LanePick.IsRanged(tc),
                    hp = hp
                }
                if ____exports.BetterSetup(key, bestKey) then
                    best = c
                    bestKey = key
                    local at = c:GetLocation()
                    bestNote = {
                        kind = "setup",
                        mode = "safe",
                        creep = tc,
                        hp = hp,
                        hf = hp / max,
                        x = at.x,
                        y = at.y,
                        kill = kill,
                        reach = reach,
                        hits = hits,
                        denies = 0,
                        lastHits = 0
                    }
                end
                __continue75 = true
            until true
            if not __continue75 then
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
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(
        creepRadius(bot),
        true
    ) or ({})) do
        do
            local __continue87
            repeat
                if not usable(c) then
                    __continue87 = true
                    break
                end
                if math.max(
                    0,
                    GetUnitToUnitDistance(bot, c) - bot:GetAttackRange()
                ) / speed <= LanePick.MAX_WALK then
                    near[#near + 1] = c
                end
                __continue87 = true
            until true
            if not __continue87 then
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
    local note, creep = unpack(mode == "shove" and findShove(bot) or (____exports.SetupWanted(bot) and findSetup(bot, me, verbs) or ({nil, nil})))
    if note == nil and mode ~= "shove" then
        note, creep = unpack(findPreDeny(bot, me, verbs))
    end
    if note == nil or creep == nil then
        return nil
    end
    local t = target(bot, creep)
    local busy = t.walk + verbs.ownHitTime(me, t.creep) + periodOf(me)
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
