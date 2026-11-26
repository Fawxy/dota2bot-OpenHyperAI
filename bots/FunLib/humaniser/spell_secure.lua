--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
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
--- HP still to lose before the spell would kill.
local function short(a)
    return a.hp - a.taken
end
--- The best of a read's answers: a kill before none, then the reserve met, then the cheaper. With no kill: the creep alive when it
-- lands before dead by then, then the one with the least HP still to lose.
function ____exports.Best(as)
    local best
    for ____, a in ipairs(as) do
        do
            local __continue22
            repeat
                if best == nil then
                    best = a
                    __continue22 = true
                    break
                end
                if a.kill ~= best.kill then
                    if a.kill then
                        best = a
                    end
                    __continue22 = true
                    break
                end
                if a.kill then
                    if a.over >= 0 ~= (best.over >= 0) then
                        if a.over >= 0 then
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
                __continue22 = true
            until true
            if not __continue22 then
                break
            end
        end
    end
    return best
end
return ____exports
