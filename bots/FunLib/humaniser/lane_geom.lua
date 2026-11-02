--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- Lane geometry shared by lane_state and lane_read. No imports from humaniser modules, so telemetry can load lane_read
-- without a require cycle through lane_state (which logs ev=lane_eq through telemetry).
-- Amounts are along the lane in any one frame: EqPos is unchanged by which way the frame runs.
local function clamp(v, lo, hi)
    return v < lo and lo or (v > hi and hi or v)
end
function ____exports.EqPos(meetAmount, ourTower, theirTower)
    local span = theirTower - ourTower
    if span == 0 then
        return 0
    end
    return clamp(2 * (meetAmount - ourTower) / span - 1, -1, 1)
end
--- A front behind its own side's tower has no wave in lane (it reads that side's base), so the other front is the meet.
function ____exports.MeetAmount(ourFront, enemyFront, ourTower, theirTower)
    local span = theirTower - ourTower
    local oursOut = (ourFront - ourTower) * span < 0
    local theirsOut = (enemyFront - theirTower) * span > 0
    if oursOut and not theirsOut then
        return enemyFront
    end
    if theirsOut and not oursOut then
        return ourFront
    end
    return (ourFront + enemyFront) / 2
end
return ____exports
