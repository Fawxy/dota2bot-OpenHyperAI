--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
function ____exports.Arrive(walk, act, deadline)
    local slack = deadline - (walk + act)
    return {ok = slack > 0, slack = slack}
end
--- `away`: the seconds until the hero is back (twice the walk plus the act).
function ____exports.GivenUp(others, away)
    local due = 0
    local ranged = 0
    for ____, o in ipairs(others) do
        do
            local __continue4
            repeat
                if o.due >= away then
                    __continue4 = true
                    break
                end
                due = due + 1
                if o.ranged then
                    ranged = ranged + 1
                end
                __continue4 = true
            until true
            if not __continue4 then
                break
            end
        end
    end
    return {due = due, ranged = ranged}
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
--- The point at `reach` from the creep on the line from the hero to it; the hero's own place when it is already within
-- `reach` (attack range plus both hulls).
function ____exports.StandSpot(hero, creep, reach)
    local d = dist(hero, creep)
    if d <= reach or d == 0 then
        return {x = hero.x, y = hero.y}
    end
    local k = reach / d
    return {x = creep.x + (hero.x - creep.x) * k, y = creep.y + (hero.y - creep.y) * k}
end
--- The length of the segment `from` to `to` that lies inside the circle at `c` with radius `r`.
function ____exports.InsideLength(from, to, c, r)
    local dx = to.x - from.x
    local dy = to.y - from.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then
        return 0
    end
    local fx = from.x - c.x
    local fy = from.y - c.y
    local along = -(fx * (dx / len) + fy * (dy / len))
    local half2 = r * r - (fx * fx + fy * fy - along * along)
    if half2 <= 0 then
        return 0
    end
    local half = math.sqrt(half2)
    local lo = math.max(along - half, 0)
    local hi = math.min(along + half, len)
    return hi > lo and hi - lo or 0
end
function ____exports.PathCost(p)
    local creeps = 0
    local cdps = 0
    for ____, c in ipairs(p.creeps) do
        do
            local __continue15
            repeat
                if dist(c, p.spot) > c.reach then
                    __continue15 = true
                    break
                end
                creeps = creeps + 1
                cdps = cdps + c.dps
                __continue15 = true
            until true
            if not __continue15 then
                break
            end
        end
    end
    local tower = false
    for ____, t in ipairs(p.towers) do
        if dist(t, p.spot) <= t.reach then
            tower = true
            break
        end
    end
    local enemies = {}
    local covering = 0
    local exposure = 0
    for ____, e in ipairs(p.enemies) do
        local r = e.range + e.hull + p.hull
        local d = dist(e, p.spot)
        local exp = ____exports.InsideLength(p.from, p.spot, e, r) / p.speed
        enemies[#enemies + 1] = {
            pid = e.pid,
            dist = d,
            range = e.range,
            dmg = e.dmg,
            spa = e.spa,
            exp = exp
        }
        if d <= r then
            covering = covering + 1
            if exp > exposure then
                exposure = exp
            end
        end
    end
    return {
        creeps = creeps,
        cdps = cdps,
        tower = tower,
        enemies = enemies,
        covering = covering,
        exposure = exposure
    }
end
return ____exports
