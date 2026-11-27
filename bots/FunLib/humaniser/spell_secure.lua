--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayIndexOf(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    if len == 0 then
        return -1
    end
    if fromIndex >= len then
        return -1
    end
    if fromIndex < 0 then
        fromIndex = len + fromIndex
        if fromIndex < 0 then
            fromIndex = 0
        end
    end
    for i = fromIndex + 1, len do
        if self[i] == searchElement then
            return i - 1
        end
    end
    return -1
end
-- End of Lua Library inline imports
local ____exports = {}
local SpellAim = require(GetScriptDirectory().."/FunLib/humaniser/spell_aim")
local function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
--- When the spell's damage lands on a creep `d` away, the hero walking straight into range at `heroSpeed` and turning for `turn` s.
-- The flight is from where the hero casts (no farther than the cast range). The cast range is read centre to centre: whether
-- Valve adds hulls is not checked, so `gap` near 0 is uncertain by a hull (about 16 to 24).
function ____exports.TimingOf(s, d, heroSpeed, turn)
    local gap = d - s.range
    local walk = math.max(0, gap) / math.max(100, heroSpeed)
    if s.shape == "n" then
        return {gap = gap, walk = walk, land = walk + s.cp}
    end
    local flight = s.speed > 0 and math.min(d, s.range) / s.speed or 0
    return {gap = gap, walk = walk, land = walk + turn + s.cp + flight}
end
--- The spell kills the creep: it is alive when the damage lands (`hp` the forecast HP then) and the damage after resistance covers it.
function ____exports.Kills(hp, taken)
    return hp > 0 and hp <= taken
end
--- Mana left after the cast over the reserve (user 27/11/2026: after the cast the hero can still cast its disable): the dearest of
-- the hero's other learned key spells, castable now or not. 0 or more meets the reserve.
function ____exports.OverReserve(mana, s, keys)
    local reserve = 0
    for name, cost in pairs(keys) do
        if name ~= s.name and cost > reserve then
            reserve = cost
        end
    end
    return mana - s.mana - reserve
end
--- Enemy heroes the cast aimed at the creep would also hit. A line (`half` over 0, not `n`): from the hero through the creep to the
-- farther of the cast range and the creep, within `half` plus the foe's hull of it. Otherwise an area (`radius` over 0) around the
-- creep, or around the hero for `n`. Else none. A bounce (Arc Lightning's jump radius) reads as an area around the creep.
function ____exports.AlsoHit(s, hero, creep, foes)
    local n = 0
    if s.half > 0 and s.shape ~= "n" then
        local d = dist(hero, creep)
        if d <= 0 then
            return 0
        end
        local ux = (creep.x - hero.x) / d
        local uy = (creep.y - hero.y) / d
        local len = math.max(s.range, d)
        for ____, f in ipairs(foes) do
            do
                local __continue12
                repeat
                    local px = f.x - hero.x
                    local py = f.y - hero.y
                    local along = px * ux + py * uy
                    if along < 0 or along > len then
                        __continue12 = true
                        break
                    end
                    if math.abs(px * uy - py * ux) <= s.half + f.hull then
                        n = n + 1
                    end
                    __continue12 = true
                until true
                if not __continue12 then
                    break
                end
            end
        end
        return n
    end
    if s.radius <= 0 then
        return 0
    end
    local centre = s.shape == "n" and hero or creep
    for ____, f in ipairs(foes) do
        if dist(f, centre) <= s.radius + f.hull then
            n = n + 1
        end
    end
    return n
end
--- Where a point or no-target spell lands (slice oha-spell-aim): SPELL_SHAPE's kind, else for a spell with no row the read before it
-- (a line when it has a width, else an area at the point; a no-target spell around the hero).
function ____exports.GeomOf(s)
    local k = s.geom or (s.shape == "n" and "s" or (s.half > 0 and "l" or "a"))
    return {
        k = k,
        range = s.range,
        radius = k == "s" and s.radius <= 0 and s.range or s.radius,
        half = s.half,
        length = k == "l" and math.max(s.length, s.range) or 0,
        offset = s.offset
    }
end
local function movedBy(u, t)
    return {
        x = u.x + u.vx * t,
        y = u.y + u.vy * t,
        hull = u.hull,
        vx = u.vx,
        vy = u.vy
    }
end
--- A `p` or `n` spell's landing on an aim: the walk, the turn (not for a spell around the hero), the cast point, the flight from
-- where it casts, the delay. `flight` is returned apart: an `s` spell with a speed (Death Pulse) picks its units at the cast and
-- homes on them, so they are placed `flight` before the landing.
local function aimedTiming(s, g, aim, creep, heroSpeed, turn)
    local walk = aim.gap / math.max(100, heroSpeed)
    local flight = s.speed > 0 and dist(aim.from, (g.k == "l" or g.k == "s") and creep or aim.at) / s.speed or 0
    return {timing = {gap = aim.gap, walk = walk, land = walk + (g.k == "s" and 0 or turn) + s.cp + flight + s.delay}, flight = flight}
end
--- Seconds from now until the spell's units are placed: at the landing, or at the cast for a homing `s` spell.
local function placedAt(g, t)
    return g.k == "s" and t.timing.land - t.flight or t.timing.land
end
--- A `p` or `n` spell aimed at the creep (spell_aim.ts): aimed at the creep and the foes where they are, then again where their
-- velocities put them when that cast lands, and timed on the second aim. `others` (their other creeps) are counted where they are.
-- `turn` is the turn to face the creep: a line or ring aimed off it to catch a hero turns at most its arc further (a hundredth
-- of a second or two). `centre`: the foes the same cast hits aimed straight at the creep, for the line to show what the aim added.
function ____exports.Aimed(s, hero, heroSpeed, turn, creep, foes, others)
    local g = ____exports.GeomOf(s)
    local first = SpellAim.AimAt(
        g,
        hero,
        creep,
        foes,
        others
    )
    local t = placedAt(
        g,
        aimedTiming(
            s,
            g,
            first,
            creep,
            heroSpeed,
            turn
        )
    )
    local c2 = movedBy(creep, t)
    local f2 = {}
    for ____, f in ipairs(foes) do
        f2[#f2 + 1] = movedBy(f, t)
    end
    local aim = SpellAim.AimAt(
        g,
        hero,
        c2,
        f2,
        others
    )
    local centre = SpellAim.AimAt(
        g,
        hero,
        c2,
        {},
        f2
    ).others
    return {
        aim = aim,
        timing = aimedTiming(
            s,
            g,
            aim,
            c2,
            heroSpeed,
            turn
        ).timing,
        centre = centre
    }
end
--- HP still to lose before the spell would kill.
local function short(a)
    return a.hp - a.taken
end
--- The best of a read's answers (the line's, nothing decides on it): a kill before none, then the reserve met, then no walk, then the cheaper. With no kill: the creep alive when it
-- lands before dead by then, then the one with the least HP still to lose.
function ____exports.Best(as)
    local best
    for ____, a in ipairs(as) do
        do
            local __continue29
            repeat
                if best == nil then
                    best = a
                    __continue29 = true
                    break
                end
                if a.kill ~= best.kill then
                    if a.kill then
                        best = a
                    end
                    __continue29 = true
                    break
                end
                if a.kill then
                    if a.over >= 0 ~= (best.over >= 0) then
                        if a.over >= 0 then
                            best = a
                        end
                    elseif a.timing.gap <= 0 ~= (best.timing.gap <= 0) then
                        if a.timing.gap <= 0 then
                            best = a
                        end
                    elseif a.spell.mana < best.spell.mana then
                        best = a
                    end
                elseif a.hp > 0 ~= (best.hp > 0) then
                    if a.hp > 0 then
                        best = a
                    end
                elseif short(a) < short(best) then
                    best = a
                end
                __continue29 = true
            until true
            if not __continue29 then
                break
            end
        end
    end
    return best
end
--- Whether the cast lands where the hero faces, so the hero turns before it (slice oha-aimed-cast): a no-target line or circle in front
-- of the hero. A point spell turns the hero to its point in the game's own order; a spell around the hero needs no facing.
function ____exports.Turns(s)
    if s.shape ~= "n" then
        return false
    end
    local k = ____exports.GeomOf(s).k
    return k == "l" or k == "r"
end
--- The facing (radians) an aimed line or ring casts at (the aim's `th`); undefined for any other answer.
function ____exports.FacingOf(a)
    local ____opt_0 = a.aim
    return ____opt_0 and ____opt_0.th
end
local CAST_STAGES = {
    "shape",
    "nokill",
    "walk",
    "reserve",
    "key",
    "aim",
    "aimoff"
}
local function castWhyOf(a, o)
    if a.spell.shape ~= "u" and a.aim == nil then
        return "shape"
    end
    if not a.kill then
        return "nokill"
    end
    if a.timing.gap > 0 then
        return "walk"
    end
    if a.over < 0 then
        return "reserve"
    end
    if a.spell.key and a.also <= 0 then
        return "key"
    end
    if a.spell.shape == "u" then
        return nil
    end
    if ____exports.Turns(a.spell) and (a.aim.slack or 0) < o.slack then
        return "aim"
    end
    local ____o_aimed_2
    if o.aimed then
        ____o_aimed_2 = nil
    else
        ____o_aimed_2 = "aimoff"
    end
    return ____o_aimed_2
end
--- Whether `a` is the better of two casts that both pass: a damage spell before a key spell, a unit-target one before an aimed one, then the cheaper.
local function castBefore(a, b)
    if a.spell.key ~= b.spell.key then
        return not a.spell.key
    end
    local au = a.spell.shape == "u"
    if au ~= (b.spell.shape == "u") then
        return au
    end
    return a.spell.mana < b.spell.mana
end
local UNIT_ONLY = {aimed = false, slack = 0}
--- The cast the creep row may order (slices oha-creep-spells, oha-aimed-cast): a spell that kills now, needs no walk, meets the reserve,
-- and is a damage spell or also hits an enemy hero; a point or no-target one only aimed, with `o.aimed`, and with the slack to turn to
-- when it turns the hero. Of those `castBefore`'s order. With none, `why` is the furthest any answer got (`CAST_STAGES`' order), so the
-- line says what came closest.
function ____exports.CastPick(as, o)
    if o == nil then
        o = UNIT_ONLY
    end
    local pick
    local far = -1
    for ____, a in ipairs(as) do
        do
            local __continue58
            repeat
                local why = castWhyOf(a, o)
                if why == nil then
                    if pick == nil or castBefore(a, pick) then
                        pick = a
                    end
                    __continue58 = true
                    break
                end
                local at = __TS__ArrayIndexOf(CAST_STAGES, why)
                if at > far then
                    far = at
                end
                __continue58 = true
            until true
            if not __continue58 then
                break
            end
        end
    end
    if pick ~= nil then
        return {pick = pick}
    end
    return {why = far >= 0 and CAST_STAGES[far + 1] or nil}
end
return ____exports
