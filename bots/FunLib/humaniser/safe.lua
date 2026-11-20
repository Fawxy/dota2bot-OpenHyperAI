--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local ThreatSettings = ____threat.SETTINGS
--- Every number the decision owns, with its source. The unseen bar is `Threat.SETTINGS.MissingRefuse`, read at call time, not copied.
____exports.BARS = {stay = 1.25, idle = 1, hold = 1, slack = 0.15}
--- Whether the hero is under a hero's hits: `pressed`, or a reacher `hitting` (the shorter flag, the only one an older cut carries).
function ____exports.Pressed(i)
    if i.pressed == true then
        return true
    end
    for ____, r in ipairs(i.reach) do
        if r.hitting then
            return true
        end
    end
    return false
end
--- The HP / kill ratio under which a held place is deadly: `stay` under a hero's hits, else the lower of it and `BARS.idle`.
function ____exports.Line(pressed, stay)
    if stay == nil then
        stay = ____exports.BARS.stay
    end
    return pressed and stay or math.min(stay, ____exports.BARS.idle)
end
function ____exports.Decide(i, stay)
    if stay == nil then
        stay = ____exports.BARS.stay
    end
    local kill = 0
    for ____, r in ipairs(i.reach) do
        kill = kill + r.dmg
    end
    local heroes = kill
    local towers = 0
    for ____, d in ipairs(i.drawn or ({})) do
        kill = kill + d.dmg
        if d.src == "tower" then
            towers = towers + d.dmg
        end
    end
    local ratio = kill > 0 and i.hp / kill or math.huge
    local ____i_landing_0 = i.landing
    local hero = ____i_landing_0.hero
    local creeps = ____i_landing_0.creeps
    local tower = ____i_landing_0.tower
    local price = hero + creeps + tower
    local function answer(level, reason)
        return {
            level = level,
            kill = kill,
            heroes = heroes,
            ratio = ratio,
            price = price,
            reason = reason
        }
    end
    if i.drawn == nil and (i.towerOnMe or i.tower and not i.held) then
        return answer("deadly", "tower")
    end
    local line = ____exports.Line(
        ____exports.Pressed(i),
        stay
    )
    local bar = i.hold and math.min(line, ____exports.BARS.hold) or (i.held and line or line * (1 + ____exports.BARS.slack))
    if ratio < bar then
        return answer(
            "deadly",
            towers > 0 and (kill == towers or i.hp / math.max(heroes, kill - towers) >= bar) and "tower" or "kill"
        )
    end
    if i.away and i.missing >= ThreatSettings.MissingRefuse then
        return answer("deadly", "unknown")
    end
    if price > 0 then
        return answer("costly", hero >= creeps and hero >= tower and "hero" or (creeps >= tower and "creeps" or "tower"))
    end
    return answer("safe", "safe")
end
return ____exports
