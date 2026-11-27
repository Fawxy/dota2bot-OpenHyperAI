--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____math_atan2_0 = math.atan2
if ____math_atan2_0 == nil then
    ____math_atan2_0 = math.atan
end
local atan2 = ____math_atan2_0
local function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
--- `p` moved `by` towards `to` (away for a negative `by`).
local function toward(p, to, by)
    local d = dist(p, to)
    if d <= 0 or by == 0 then
        return {x = p.x, y = p.y}
    end
    return {x = p.x + (to.x - p.x) * by / d, y = p.y + (to.y - p.y) * by / d}
end
--- An angle folded into (-pi, pi].
local function norm(a)
    local x = a % (2 * math.pi)
    if x > math.pi then
        x = x - 2 * math.pi
    elseif x <= -math.pi then
        x = x + 2 * math.pi
    end
    return x
end
--- Whether the line from `from` along angle `th` hits `b` within `length` and `half` plus `extra` of its axis.
local function onLine(from, th, b, g, extra)
    local px = b.x - from.x
    local py = b.y - from.y
    local along = px * math.cos(th) + py * math.sin(th)
    if along < 0 or along > g.length + extra then
        return false
    end
    return math.abs(py * math.cos(th) - px * math.sin(th)) <= g.half + extra
end
--- The centre of the circle an `r` spell lands, facing angle `th` from `from`.
local function ringCentre(from, th, g)
    return {
        x = from.x + g.offset * math.cos(th),
        y = from.y + g.offset * math.sin(th)
    }
end
local function hitsAt(g, from, th, b)
    if g.k == "l" then
        return onLine(
            from,
            th,
            b,
            g,
            b.hull
        )
    end
    return dist(
        ringCentre(from, th, g),
        b
    ) <= g.radius + b.hull
end
--- The half-width of the arc of facing angles from `from` at which the spell hits a unit `d` away with `extra` of slack (its hull,
-- or 0 for `must`), around the angle to it; undefined when no facing reaches it.
local function arcOf(g, d, extra)
    if g.k == "l" then
        if d > g.length + extra then
            return nil
        end
        local w = g.half + extra
        return d <= w and math.pi / 2 or math.asin(w / d)
    end
    local r = g.radius + extra
    if d <= 0 or g.offset <= 0 then
        return d + g.offset <= r and math.pi or nil
    end
    local c = (d * d + g.offset * g.offset - r * r) / (2 * d * g.offset)
    if c > 1 then
        return nil
    end
    return c <= -1 and math.pi or math.acos(c)
end
--- The facing for a line or a ring: the arc that hits `must` is cut at the edges of each wanted unit's arc, and of the pieces the
-- one that hits the most wanted units wins. Within it the facing straight at `must` if the piece holds it, else the piece's middle,
-- so the unit nearest an edge keeps the most margin.
local function facing(g, from, must, wanted)
    local base = atan2(must.y - from.y, must.x - from.x)
    local a0 = arcOf(
        g,
        dist(from, must),
        0
    ) or 0
    local cuts = {-a0, a0}
    local arcs = {}
    for ____, w in ipairs(wanted) do
        do
            local __continue19
            repeat
                local a = arcOf(
                    g,
                    dist(from, w),
                    w.hull
                )
                if a == nil then
                    __continue19 = true
                    break
                end
                local c = norm(atan2(w.y - from.y, w.x - from.x) - base)
                arcs[#arcs + 1] = {c = c, a = a}
                for ____, e in ipairs({
                    norm(c - a),
                    norm(c + a)
                }) do
                    if e > -a0 and e < a0 then
                        cuts[#cuts + 1] = e
                    end
                end
                __continue19 = true
            until true
            if not __continue19 then
                break
            end
        end
    end
    table.sort(cuts)
    local best = 0
    local bestN = -1
    local bestHas0 = false
    do
        local i = 0
        while i + 1 < #cuts do
            local lo = cuts[i + 1]
            local hi = cuts[i + 1 + 1]
            local mid = (lo + hi) / 2
            local n = 0
            for ____, r in ipairs(arcs) do
                if math.abs(norm(mid - r.c)) <= r.a then
                    n = n + 1
                end
            end
            local has0 = lo <= 0 and hi >= 0
            if n > bestN or n == bestN and has0 and not bestHas0 then
                bestN = n
                best = has0 and 0 or mid
                bestHas0 = has0
            end
            i = i + 1
        end
    end
    return base + best
end
local function count(units, hit)
    local n = 0
    for ____, b in ipairs(units) do
        if hit(b) then
            n = n + 1
        end
    end
    return n
end
--- Centres an area may take to hit `must` and wanted units: `must` itself; for each wanted unit near enough, the point between them
-- at the middle of the stretch where both are hit; and the middle of `must` and all of those. Each is pulled back within `range`.
local function areaCentres(g, from, must, wanted)
    local out = {must}
    local sx = must.x
    local sy = must.y
    local n = 1
    for ____, w in ipairs(wanted) do
        do
            local __continue35
            repeat
                local d = dist(must, w)
                if d > 2 * g.radius + w.hull then
                    __continue35 = true
                    break
                end
                local lo = math.max(0, d - g.radius - w.hull)
                local hi = math.min(g.radius, d)
                out[#out + 1] = toward(must, w, (lo + hi) / 2)
                sx = sx + w.x
                sy = sy + w.y
                n = n + 1
                __continue35 = true
            until true
            if not __continue35 then
                break
            end
        end
    end
    if n > 2 then
        out[#out + 1] = {x = sx / n, y = sy / n}
    end
    local pulled = {}
    for ____, c in ipairs(out) do
        local d = dist(from, c)
        pulled[#pulled + 1] = d > g.range and toward(from, c, g.range) or c
    end
    return pulled
end
--- Where to cast `g` from `caster` so that it hits `must` and as many of `wanted` as it can; `others` are counted, not aimed for.
function ____exports.AimAt(g, caster, must, wanted, others)
    local d = dist(caster, must)
    if g.k == "s" then
        local gap = math.max(0, d - g.radius)
        local from = toward(caster, must, gap)
        local function hit(b)
            return dist(from, b) <= g.radius + b.hull
        end
        return {
            gap = gap,
            from = from,
            at = from,
            off = dist(from, must),
            also = count(wanted, hit),
            others = count(others, hit)
        }
    end
    if g.k == "a" then
        local gap = math.max(0, d - (g.range + g.radius))
        local from = toward(caster, must, gap)
        local centres = areaCentres(g, from, must, wanted)
        local at = centres[1]
        local bestN = -1
        local bestOff = math.huge
        for ____, c in ipairs(centres) do
            do
                local __continue45
                repeat
                    local off = dist(c, must)
                    if off > g.radius + 0.000001 * math.max(1, g.radius) then
                        __continue45 = true
                        break
                    end
                    local n = count(
                        wanted,
                        function(b) return dist(c, b) <= g.radius + b.hull end
                    )
                    if n > bestN or n == bestN and off < bestOff then
                        at = c
                        bestN = n
                        bestOff = off
                    end
                    __continue45 = true
                until true
                if not __continue45 then
                    break
                end
            end
        end
        local function hit(b)
            return dist(at, b) <= g.radius + b.hull
        end
        return {
            gap = gap,
            from = from,
            at = at,
            off = dist(at, must),
            also = count(wanted, hit),
            others = count(others, hit)
        }
    end
    local gap
    local from
    if g.k == "l" then
        gap = math.max(0, d - g.length)
        from = toward(caster, must, gap)
    else
        local miss = math.abs(d - g.offset) - g.radius
        gap = math.max(0, miss)
        from = toward(caster, must, d > g.offset and gap or -gap)
    end
    local th = facing(g, from, must, wanted)
    local function hit(b)
        return hitsAt(g, from, th, b)
    end
    local at
    local off
    if g.k == "l" then
        local px = must.x - from.x
        local py = must.y - from.y
        local along = px * math.cos(th) + py * math.sin(th)
        at = {
            x = from.x + along * math.cos(th),
            y = from.y + along * math.sin(th)
        }
        off = math.abs(py * math.cos(th) - px * math.sin(th))
    else
        at = ringCentre(from, th, g)
        off = dist(at, must)
    end
    return {
        gap = gap,
        from = from,
        at = at,
        off = off,
        also = count(wanted, hit),
        others = count(others, hit)
    }
end
return ____exports
