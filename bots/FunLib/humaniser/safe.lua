--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local ThreatSettings = ____threat.SETTINGS
--- Every number the decision owns, with its source. The unseen bar is `Threat.SETTINGS.MissingRefuse`, read at call time, not copied.
____exports.BARS = {stay = 1.25, idle = 1, hold = 1, slack = 0.15}
function ____exports.Decide(i, stay)
    if stay == nil then
        stay = ____exports.BARS.stay
    end
    local kill = 0
    for ____, r in ipairs(i.reach) do
        kill = kill + r.dmg
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
            ratio = ratio,
            price = price,
            reason = reason
        }
    end
    if i.towerOnMe or i.tower and not i.held then
        return answer("deadly", "tower")
    end
    local hit = false
    for ____, r in ipairs(i.reach) do
        hit = hit or r.hitting
    end
    local line = hit and stay or math.min(stay, ____exports.BARS.idle)
    local bar = i.hold and math.min(line, ____exports.BARS.hold) or (i.held and line or line * (1 + ____exports.BARS.slack))
    if ratio < bar then
        return answer("deadly", "kill")
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
