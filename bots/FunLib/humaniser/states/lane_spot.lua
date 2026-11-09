--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local sub, len, d2, alive, breaksTower, HOLD_DRIFT
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local UnitType = ____dota.UnitType
local ____ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local On = ____ours.On
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
function sub(a, b)
    return {a.x - b.x, a.y - b.y}
end
function len(x, y)
    return math.sqrt(x * x + y * y)
end
function d2(a, b)
    local x, y = unpack(sub(a, b))
    return len(x, y)
end
function alive(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:GetLocation() ~= nil
end
function breaksTower(p, towers)
    for ____, t in ipairs(towers) do
        if alive(t) and d2(
            p,
            t:GetLocation()
        ) < ____exports.TOWER_RING + HOLD_DRIFT then
            return true
        end
    end
    return false
end
____exports.MELEE_RING = 520
____exports.RANGED_RING = 620
--- Enemy tower attack range (~700) plus a margin; at every level, since nothing in lane owns a dive.
____exports.TOWER_RING = 750
HOLD_DRIFT = 80
local RANGED_ABOVE = 320
--- Ranged cores stand this much inside their range from the creep they will hit next.
local RANGE_INSET = 50
--- Melee cores stand this far behind our front, before the limits push them back.
local MELEE_BEHIND = 100
local SIDE_SHIFT = 120
local PUSH_STEP = 50
--- No push further back than this from the front: XP is shared within 1500 of a dying creep.
local MAX_BACK = 1000
--- Sideways candidates either side of the lane axis, so a ring can be cleared without giving ground.
local LATERAL = {
    0,
    -100,
    100,
    -200,
    200
}
local QUERY = 1400
--- HP margin added to the creep rings (judgement, step 0: cores laning took back from retreat at 45-48% HP walked into the
-- enemy wave): none at HP_SAFE or more, rising linearly to HP_MARGIN at HP_LOW and below.
local HP_SAFE = 0.5
local HP_LOW = 0.25
local HP_MARGIN = 300
--- Seconds of the enemy hero's movement added to its attack reach: the ground it closes before we react (judgement). lposchk1
-- with a fixed 150: cores held 400-800 from an enemy hero lost 0.7-1.1 HP-% a second there, against 0.3 at 800-1,200.
-- lposchk2 with 1 s (reach about 920 against a 570-range hero): idle cores 800-1,000 from a ranged enemy still lost 0.39 a
-- second, 0.06 beyond 1,000; 1.5 s puts that reach at about 1,070.
local REACT_SECS = 1.5
--- With Ours.LaneSpotThreat the hero limit is the threat read (slice retreat, user 10/11/2026): the spot is acceptable where the
-- walk from the bot to it and the standing there for READ_HORIZON seconds read under both bars below, so the walk past a
-- hero counts and low HP counts once (through `burst`, which divides by current HP) instead of by a second margin. The
-- horizon is the core camp's GateHorizon (4 s); the burst bar is the read's Watch edge (a hero that takes a quarter of our
-- HP in the window), the threat bar its Pressured edge (judgement; graded on rtwatch1 and the drill, slice file "Open items").
-- rtwatch1 7:33: the old limits (reach 800 plus HP margin) put the spot beyond a chaser 850-920 away, then a `wave` spot
-- 1,400 forward past him, because they test the point, not the walk.
local READ_HORIZON = 4
--- No enemy hero's reach is under this (the melee margin, judgement): lposchk2 idle cores 400-600 from a melee enemy (reach
-- about 500) lost 0.5 HP-% a second, 600-800 0.24, beyond 800 0.09; a melee hero closes on a core that stands at its reach.
local MIN_REACH = 800
--- An enemy creep under our tower that is attacking our tower or our creeps does not turn on us for standing near it (judgement:
-- lane creeps keep a target until it dies; EC-053 gives acquisition about 500 for a creep without one). HELD_RING keeps the
-- hero clear of the creep's body and its 100 melee reach.
local HELD_RING = 200
--- Movement allowed for an enemy hero that our tower punishes for attacking us (judgement): a step in, not a chase.
local TOWER_REACT_SECS = 0.5
--- Our tower's attack range when the API gives none.
local OWN_TOWER_RANGE = 700
--- The fed creep anchors the spot at or below this HP share (judgement: the deny window opens below 50%, the walk takes time).
____exports.FED_HP = 0.75
--- How far behind the fed creep, as a share of the bot's attack reach (capped at FED_REACH_CAP): inside reach, never past it.
local FED_BEHIND = 0.8
local FED_REACH_CAP = 300
--- Enemy creeps within this of our front are in the spot's own creep read; a clash anchor needs theirs further back.
local FRONT_SEEN = 1000
--- Their creeps up to our T1's range behind it still count as a clash at our tower.
local CLASH_BEHIND = 700
--- Their rearmost creep must be within this of our T1 (along the lane) for the clash to anchor: our tower's range plus 300.
local NEAR_T1 = 1000
--- Our creep within this of their rearmost creep, on our side, is fighting it (wave_hold's MeetR).
local MEET_R = 700
--- Lane creeps further than this from the lane path are not on it (wave_hold's PathR).
local PATH_R = 600
--- The lane direction is read between the anchor and this far back along the path (GetLaneFrontLocation's -400).
local BACK_ALONG = 400
local function isRangedCreep(c)
    return (string.find(
        c:GetUnitName(),
        "ranged",
        1,
        true
    )) ~= nil
end
--- An enemy hero's damaging abilities it could cast now (trained, not passive or hidden, off cooldown, its mana covers them) and
-- the longest cast range among them: read for telemetry (ev=lane_pos `nk`, `nr`), not a limit yet (lane-positioning Open items).
function ____exports.ReadyNukes(enemy)
    local n = 0
    local range = 0
    local mana = enemy:GetMana()
    do
        local i = 0
        while i < 6 do
            do
                local __continue8
                repeat
                    local a = enemy:GetAbilityInSlot(i)
                    if a == nil or a == nil or a:IsNull() or a:IsHidden() or a:IsPassive() or a:GetLevel() < 1 then
                        __continue8 = true
                        break
                    end
                    if a:GetAbilityDamage() <= 0 or a:GetCooldownTimeRemaining() > 0 or a:GetManaCost() > mana then
                        __continue8 = true
                        break
                    end
                    n = n + 1
                    range = math.max(
                        range,
                        a:GetCastRange()
                    )
                    __continue8 = true
                until true
                if not __continue8 then
                    break
                end
            end
            i = i + 1
        end
    end
    return {n, range}
end
--- The nearest visible enemy hero within 1,600 of `bot`: its distance and ReadyNukes, or undefined with none.
function ____exports.NearestNuke(bot)
    local best
    local bestD = math.huge
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, 0)) do
        do
            local __continue12
            repeat
                if not alive(h) then
                    __continue12 = true
                    break
                end
                local dist = GetUnitToUnitDistance(bot, h)
                if dist < bestD then
                    bestD = dist
                    best = h
                end
                __continue12 = true
            until true
            if not __continue12 then
                break
            end
        end
    end
    if best == nil then
        return nil
    end
    local n, range = unpack(____exports.ReadyNukes(best))
    return {bestD, n, range}
end
function ____exports.HpMargin(hpFrac)
    if hpFrac >= HP_SAFE then
        return 0
    end
    if hpFrac <= HP_LOW then
        return HP_MARGIN
    end
    return HP_MARGIN * (HP_SAFE - hpFrac) / (HP_SAFE - HP_LOW)
end
--- How close `self` may stand to an enemy hero: its attack reach to us plus REACT_SECS of its movement, at least MIN_REACH.
function ____exports.HeroReach(____self, enemy)
    return math.max(
        MIN_REACH,
        enemy:GetAttackRange() + enemy:GetBoundingRadius() + ____self:GetBoundingRadius() + REACT_SECS * enemy:GetCurrentMovementSpeed()
    )
end
--- Whether every point an enemy needs (within `hit` of `p`) to attack `p` lies inside one of our towers' range.
local function covers(cover, p, hit)
    for ____, t in ipairs(cover.towers) do
        if d2(p, t.at) + hit <= t.range then
            return true
        end
    end
    return false
end
--- The first hard limit `p` breaks, or undefined: an enemy hero's reach (`hero`), an enemy creep's ring (`creep`), a tower, or
-- `hp` when only the HP margin breaks a hero or creep limit. `reach` holds each hero's reach (HeroReach), in `heroes` order;
-- `cover`, when given, relaxes them under our towers.
function ____exports.Breaks(p, creeps, towers, margin, heroes, reach, cover, busy)
    if margin == nil then
        margin = 0
    end
    if heroes == nil then
        heroes = {}
    end
    if reach == nil then
        reach = {}
    end
    local hp = false
    do
        local i = 0
        while i < #heroes do
            do
                local __continue26
                repeat
                    local h = heroes[i + 1]
                    if not alive(h) then
                        __continue26 = true
                        break
                    end
                    local r = reach[i + 1]
                    if cover ~= nil and (cover.tanking[i + 1] or covers(cover, p, cover.hit[i + 1])) then
                        r = cover.near[i + 1]
                    end
                    local dist = d2(
                        p,
                        h:GetLocation()
                    )
                    if dist < r then
                        return "hero"
                    end
                    if dist < r + margin then
                        hp = true
                    end
                    __continue26 = true
                until true
                if not __continue26 then
                    break
                end
            end
            i = i + 1
        end
    end
    do
        local i = 0
        while i < #creeps do
            do
                local __continue31
                repeat
                    local c = creeps[i + 1]
                    if not alive(c) then
                        __continue31 = true
                        break
                    end
                    local ring = (cover ~= nil and cover.held[i + 1] or busy ~= nil and busy[i + 1]) and HELD_RING or (isRangedCreep(c) and ____exports.RANGED_RING or ____exports.MELEE_RING)
                    local dist = d2(
                        p,
                        c:GetLocation()
                    )
                    if dist < ring then
                        return "creep"
                    end
                    if dist < ring + margin then
                        hp = true
                    end
                    __continue31 = true
                until true
                if not __continue31 then
                    break
                end
            end
            i = i + 1
        end
    end
    if breaksTower(p, towers) then
        return "tower"
    end
    return hp and "hp" or nil
end
--- Our towers in reach and what they cover; undefined with Ours.LaneSpotTower off or no tower of ours near.
local function coverFor(bot, creeps, heroes)
    if not On("LaneSpotTower") then
        return nil
    end
    local towers = {}
    local targets = {}
    for ____, t in ipairs(bot:GetNearbyTowers(1600, false)) do
        do
            local __continue38
            repeat
                if not alive(t) then
                    __continue38 = true
                    break
                end
                towers[#towers + 1] = {
                    at = t:GetLocation(),
                    range = t:GetAttackRange() or OWN_TOWER_RANGE
                }
                local target = t:GetAttackTarget()
                if target ~= nil and target ~= nil then
                    targets[#targets + 1] = target
                end
                __continue38 = true
            until true
            if not __continue38 then
                break
            end
        end
    end
    if #towers == 0 then
        return nil
    end
    local held = {}
    for ____, c in ipairs(creeps) do
        local target = c:GetAttackTarget()
        local inRange = false
        for ____, t in ipairs(towers) do
            if d2(
                c:GetLocation(),
                t.at
            ) <= t.range + c:GetBoundingRadius() then
                inRange = true
            end
        end
        held[#held + 1] = inRange and target ~= nil and target ~= nil and target ~= bot
    end
    local tanking = {}
    local near = {}
    local hit = {}
    for ____, h in ipairs(heroes) do
        local tanked = false
        for ____, u in ipairs(targets) do
            if u == h then
                tanked = true
            end
        end
        tanking[#tanking + 1] = tanked
        local r = h:GetAttackRange() + h:GetBoundingRadius() + bot:GetBoundingRadius()
        hit[#hit + 1] = r
        near[#near + 1] = r + TOWER_REACT_SECS * h:GetCurrentMovementSpeed()
    end
    return {
        towers = towers,
        held = held,
        tanking = tanking,
        near = near,
        hit = hit
    }
end
--- The fed creep when it anchors the spot: alive, in sight and at FED_HP or below.
function ____exports.FedAnchor(fed)
    if not alive(fed) then
        return nil
    end
    return fed:GetHealth() / math.max(
        1,
        fed:GetMaxHealth()
    ) <= ____exports.FED_HP and fed or nil
end
--- Pure: the rearmost clash, as a distance from our T1 along the lane (positive towards theirs), or undefined. `theirs` and
-- `ours` are the lane creeps' distances, `front` our front's. Their creeps from CLASH_BEHIND behind our T1 to FRONT_SEEN short
-- of our front count, and only while the rearmost of them is within NEAR_T1 of our T1; the anchor is our creep nearest the rearmost of them, on our side within MEET_R, else that creep.
function ____exports.RearClash(theirs, ours, front)
    local rear = math.huge
    for ____, o in ipairs(theirs) do
        if o >= -CLASH_BEHIND and o <= front - FRONT_SEEN and o < rear then
            rear = o
        end
    end
    if rear > NEAR_T1 then
        return nil
    end
    local fight
    for ____, o in ipairs(ours) do
        if o <= rear and o >= rear - MEET_R and (fight == nil or o > fight) then
            fight = o
        end
    end
    return fight or rear
end
--- CANDIDATE(laneView): wave_hold's viewOf reads the same lane creep distances from our T1.
local function ownDistances(path, t1, dir, list)
    local out = {}
    for ____, c in ipairs(list) do
        do
            local __continue68
            repeat
                if c == nil or c == nil or c:IsNull() or not c:IsAlive() or not LanePush.IsLaneCreep(c:GetUnitName()) then
                    __continue68 = true
                    break
                end
                local l = c:GetLocation()
                if l == nil then
                    __continue68 = true
                    break
                end
                local s, d = LanePush.Project(path, l.x, l.y)
                if d <= PATH_R then
                    out[#out + 1] = dir * (s - t1)
                end
                __continue68 = true
            until true
            if not __continue68 then
                break
            end
        end
    end
    return out
end
--- The rearmost clash on `lane` against our `front`: its point, the point BACK_ALONG behind it, and both distances.
local function clashFor(team, lane, front)
    local path = LanePush.PathOf(lane)
    if path == nil then
        return nil
    end
    local t1, dir = LanePush.OwnT1(path, team)
    local far = dir * ((LanePush.Project(path, front.x, front.y)) - t1)
    local own = ____exports.RearClash(
        ownDistances(
            path,
            t1,
            dir,
            GetUnitList(UnitType.EnemyCreeps)
        ),
        ownDistances(
            path,
            t1,
            dir,
            GetUnitList(UnitType.AlliedCreeps)
        ),
        far
    )
    if own == nil then
        return nil
    end
    local ax, ay = unpack(LanePush.PointAt(path, t1 + dir * own))
    local bx, by = unpack(LanePush.PointAt(path, t1 + dir * (own - BACK_ALONG)))
    return {
        at = Vector(ax, ay, front.z),
        back = Vector(bx, by, front.z),
        own = own,
        far = far
    }
end
--- The spot. `role` decides the preferred point: a support stands between the nearest enemy hero and our wave. `fed` is
-- lane_aggro's fed creep (see FedAnchor), `hold` wave_hold's hold point. Undefined only when the lane has no direction (front
-- and its back point coincide).
function ____exports.Compute(bot, role, fed, hold)
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    local front = GetLaneFrontLocation(team, lane, 0)
    local back = GetLaneFrontLocation(team, lane, -400)
    local anchorFed = ____exports.FedAnchor(fed)
    local ____temp_0
    if role == "core" and anchorFed == nil and hold == nil then
        ____temp_0 = clashFor(team, lane, front)
    else
        ____temp_0 = nil
    end
    local clash = ____temp_0
    if clash ~= nil then
        front = clash.at
        back = clash.back
    end
    local dx, dy = unpack(sub(back, front))
    local l = len(dx, dy)
    if l < 1 then
        return nil
    end
    dx = dx / l
    dy = dy / l
    local creeps = {}
    for ____, c in ipairs(bot:GetNearbyLaneCreeps(QUERY, true)) do
        if alive(c) and d2(
            c:GetLocation(),
            front
        ) <= 1000 then
            creeps[#creeps + 1] = c
        end
    end
    local towers = bot:GetNearbyTowers(1600, true)
    local enemyHero
    local heroDist = math.huge
    local heroes = {}
    local reach = {}
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, 0)) do
        if alive(h) then
            heroes[#heroes + 1] = h
            reach[#reach + 1] = ____exports.HeroReach(bot, h)
            local dist = d2(
                h:GetLocation(),
                front
            )
            if dist < heroDist then
                heroDist = dist
                enemyHero = h
            end
        end
    end
    local px
    local py
    local anchor = "front"
    local range = bot:GetAttackRange()
    local busy
    if hold ~= nil then
        px = hold.x
        py = hold.y
        anchor = "hold"
        busy = {}
        for ____, _ in ipairs(creeps) do
            busy[#busy + 1] = true
        end
    elseif anchorFed ~= nil then
        local reachFed = range + bot:GetBoundingRadius() + anchorFed:GetBoundingRadius()
        local at = anchorFed:GetLocation()
        local back = math.min(reachFed, FED_REACH_CAP) * FED_BEHIND
        px = at.x + dx * back
        py = at.y + dy * back
        anchor = "fed"
        busy = {}
        for ____, c in ipairs(creeps) do
            busy[#busy + 1] = c:GetAttackTarget() == anchorFed
        end
    elseif #creeps == 0 then
        anchor = "wave"
        px = front.x + dx * MELEE_BEHIND
        py = front.y + dy * MELEE_BEHIND
    elseif role == "core" and range > RANGED_ABOVE then
        local low
        for ____, c in ipairs(creeps) do
            if low == nil or c:GetHealth() < low:GetHealth() then
                low = c
            end
        end
        local at = low:GetLocation()
        px = at.x + dx * (range - RANGE_INSET)
        py = at.y + dy * (range - RANGE_INSET)
        anchor = "creep"
    else
        local behind = role == "support" and math.max(MELEE_BEHIND, range - RANGE_INSET) or MELEE_BEHIND
        px = front.x + dx * behind
        py = front.y + dy * behind
    end
    local nx = -dy
    local ny = dx
    if enemyHero ~= nil and anchor ~= "fed" and anchor ~= "hold" then
        local hx, hy = unpack(sub(
            enemyHero:GetLocation(),
            front
        ))
        local side = hx * nx + hy * ny >= 0 and 1 or -1
        local shift = role == "support" and SIDE_SHIFT * 2 or -SIDE_SHIFT
        px = px + nx * side * shift
        py = py + ny * side * shift
    end
    local hpFrac = bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    )
    local margin = ____exports.HpMargin(hpFrac)
    local ____temp_1
    if role == "core" and hpFrac > HP_LOW then
        ____temp_1 = coverFor(bot, creeps, heroes)
    else
        ____temp_1 = nil
    end
    local cover = ____temp_1
    local cl = clash and clash.own
    local fo = clash and clash.far
    local byRead = On("LaneSpotThreat")
    local hs = byRead and ({}) or heroes
    local rs = byRead and ({}) or reach
    local here = bot:GetLocation()
    local reads = {}
    local function readAt(p)
        local key = (tostring(math.floor(p.x)) .. ",") .. tostring(math.floor(p.y))
        local r = reads[key]
        if r == nil then
            r = Threat.Read(bot, here, p, READ_HORIZON)
            reads[key] = r
        end
        return r
    end
    local function readBreaks(p)
        if not byRead then
            return false
        end
        local r = readAt(p)
        return r.burst >= Threat.SETTINGS.Watch or r.threat >= Threat.SETTINGS.Pressured
    end
    local function covered(p)
        return cover ~= nil and ____exports.Breaks(
            p,
            creeps,
            towers,
            margin,
            hs,
            rs,
            nil,
            busy
        ) ~= nil and 1 or 0
    end
    local function done(spot, pushed, why, cov)
        local info = {
            spot = spot,
            pushed = pushed,
            anchor = anchor,
            why = why,
            margin = margin,
            covered = cov,
            clash = cl,
            far = fo
        }
        if byRead then
            local r = readAt(spot)
            info.rb = r.burst
            info.rt = r.threat
            info.ob = ____exports.Breaks(
                spot,
                creeps,
                towers,
                margin,
                heroes,
                reach,
                cover,
                busy
            ) or "none"
        end
        return info
    end
    local pref = Vector(px, py, front.z)
    local first = ____exports.Breaks(
        pref,
        creeps,
        towers,
        margin,
        hs,
        rs,
        cover,
        busy
    )
    if first == nil and readBreaks(pref) then
        first = "hero"
    end
    if first == nil then
        return done(
            pref,
            0,
            "pref",
            covered(pref)
        )
    end
    local best
    local bestCost = math.huge
    local bestPushed = 0
    local keep
    local keepPushed = 0
    local steps = math.floor(MAX_BACK / PUSH_STEP)
    do
        local k = 0
        while k <= steps do
            local bx = px + dx * PUSH_STEP * k
            local by = py + dy * PUSH_STEP * k
            for ____, off in ipairs(LATERAL) do
                do
                    local __continue109
                    repeat
                        local cost = len(PUSH_STEP * k, off)
                        if cost >= bestCost then
                            __continue109 = true
                            break
                        end
                        local p = Vector(bx + nx * off, by + ny * off, front.z)
                        if best == nil and (keep == nil or k > keepPushed) and not breaksTower(p, towers) then
                            keep = p
                            keepPushed = k
                        end
                        if ____exports.Breaks(
                            p,
                            creeps,
                            towers,
                            margin,
                            hs,
                            rs,
                            cover,
                            busy
                        ) == nil and not readBreaks(p) then
                            best = p
                            bestCost = cost
                            bestPushed = k
                        end
                        __continue109 = true
                    until true
                    if not __continue109 then
                        break
                    end
                end
            end
            if best ~= nil and PUSH_STEP * (k + 1) >= bestCost then
                break
            end
            k = k + 1
        end
    end
    if best == nil then
        if keep ~= nil then
            return done(keep, keepPushed, "xp", 0)
        end
        return done(
            Vector(px + dx * PUSH_STEP * steps, py + dy * PUSH_STEP * steps, front.z),
            steps,
            "xp",
            0
        )
    end
    return done(
        best,
        bestPushed,
        first,
        covered(best)
    )
end
return ____exports
