--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
____exports.MELEE_RING = 520
____exports.RANGED_RING = 620
--- Enemy tower attack range (~700) plus a margin; at every level, since nothing in lane owns a dive.
____exports.TOWER_RING = 750
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
local function sub(a, b)
    return {a.x - b.x, a.y - b.y}
end
local function len(x, y)
    return math.sqrt(x * x + y * y)
end
local function d2(a, b)
    local x, y = unpack(sub(a, b))
    return len(x, y)
end
local function isRangedCreep(c)
    return (string.find(
        c:GetUnitName(),
        "ranged",
        1,
        true
    )) ~= nil
end
--- Alive and in sight: a unit in the fog keeps a valid handle but reads no location.
local function alive(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:GetLocation() ~= nil
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
--- The first hard limit `p` breaks, or undefined: an enemy creep's ring (`creep`, or `hp` when only the margin breaks it), a tower.
function ____exports.Breaks(p, creeps, towers, margin)
    if margin == nil then
        margin = 0
    end
    local hp = false
    for ____, c in ipairs(creeps) do
        do
            local __continue11
            repeat
                if not alive(c) then
                    __continue11 = true
                    break
                end
                local ring = isRangedCreep(c) and ____exports.RANGED_RING or ____exports.MELEE_RING
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
                __continue11 = true
            until true
            if not __continue11 then
                break
            end
        end
    end
    for ____, t in ipairs(towers) do
        if alive(t) and d2(
            p,
            t:GetLocation()
        ) < ____exports.TOWER_RING then
            return "tower"
        end
    end
    return hp and "hp" or nil
end
--- The spot. `role` decides the preferred point: a support stands between the nearest enemy hero and our wave. Undefined only
-- when the lane has no direction (front and its back point coincide).
function ____exports.Compute(bot, role)
    local team = bot:GetTeam()
    local lane = bot:GetAssignedLane()
    local front = GetLaneFrontLocation(team, lane, 0)
    local back = GetLaneFrontLocation(team, lane, -400)
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
    for ____, h in ipairs(bot:GetNearbyHeroes(1600, true, 0)) do
        if alive(h) then
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
    if #creeps == 0 then
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
        px = front.x + dx * MELEE_BEHIND
        py = front.y + dy * MELEE_BEHIND
    end
    local nx = -dy
    local ny = dx
    if enemyHero ~= nil then
        local hx, hy = unpack(sub(
            enemyHero:GetLocation(),
            front
        ))
        local side = hx * nx + hy * ny >= 0 and 1 or -1
        local shift = role == "support" and SIDE_SHIFT * 2 or -SIDE_SHIFT
        px = px + nx * side * shift
        py = py + ny * side * shift
    end
    local margin = ____exports.HpMargin(bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    ))
    local pref = Vector(px, py, front.z)
    local first = ____exports.Breaks(pref, creeps, towers, margin)
    if first == nil then
        return {
            spot = pref,
            pushed = 0,
            anchor = anchor,
            why = "pref",
            margin = margin
        }
    end
    local best
    local bestCost = math.huge
    local bestPushed = 0
    local steps = math.floor(MAX_BACK / PUSH_STEP)
    do
        local k = 0
        while k <= steps do
            local bx = px + dx * PUSH_STEP * k
            local by = py + dy * PUSH_STEP * k
            for ____, off in ipairs(LATERAL) do
                do
                    local __continue37
                    repeat
                        local cost = len(PUSH_STEP * k, off)
                        if cost >= bestCost then
                            __continue37 = true
                            break
                        end
                        local p = Vector(bx + nx * off, by + ny * off, front.z)
                        if ____exports.Breaks(p, creeps, towers, margin) == nil then
                            best = p
                            bestCost = cost
                            bestPushed = k
                        end
                        __continue37 = true
                    until true
                    if not __continue37 then
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
        return {
            spot = Vector(px + dx * PUSH_STEP * steps, py + dy * PUSH_STEP * steps, front.z),
            pushed = steps,
            anchor = anchor,
            why = "xp",
            margin = margin
        }
    end
    return {
        spot = best,
        pushed = bestPushed,
        anchor = anchor,
        why = first,
        margin = margin
    }
end
return ____exports
