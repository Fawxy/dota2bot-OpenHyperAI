--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
____exports.MELEE_RING = 520
____exports.RANGED_RING = 620
--- Enemy T1 attack range (~700) plus a margin.
____exports.TOWER_RING = 750
--- Below this level the tower ring applies (no tower dives before 6).
local TOWER_RING_LEVEL = 6
local RANGED_ABOVE = 320
--- Ranged cores stand this much inside their range from the creep they will hit next.
local RANGE_INSET = 50
--- Melee cores stand this far behind our front, before the rings push them back.
local MELEE_BEHIND = 100
local SIDE_SHIFT = 120
local PUSH_STEP = 50
--- No push further back than this from the front: XP is shared within 1500 of a dying creep.
local MAX_BACK = 1000
local QUERY = 1400
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
--- Rings the spot must stay outside of: enemy creeps by type, the enemy tower before level 6.
function ____exports.Violates(bot, p, creeps, towers)
    for ____, c in ipairs(creeps) do
        if alive(c) and d2(
            p,
            c:GetLocation()
        ) < (isRangedCreep(c) and ____exports.RANGED_RING or ____exports.MELEE_RING) then
            return true
        end
    end
    if bot:GetLevel() < TOWER_RING_LEVEL then
        for ____, t in ipairs(towers) do
            if alive(t) and d2(
                p,
                t:GetLocation()
            ) < ____exports.TOWER_RING then
                return true
            end
        end
    end
    return false
end
--- The spot, or undefined when no enemy lane creep is visible near the lane front (then OHA's spot is used).
-- `role` decides the anchor: a support stands between the nearest enemy hero and our wave, at the same rings.
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
    if #creeps == 0 then
        return nil
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
    if role == "core" and range > RANGED_ABOVE then
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
    local pushed = 0
    local p = Vector(px, py, front.z)
    while ____exports.Violates(bot, p, creeps, towers) and pushed * PUSH_STEP < MAX_BACK do
        pushed = pushed + 1
        p = Vector(px + dx * PUSH_STEP * pushed, py + dy * PUSH_STEP * pushed, front.z)
    end
    return {spot = p, pushed = pushed, anchor = anchor}
end
return ____exports
