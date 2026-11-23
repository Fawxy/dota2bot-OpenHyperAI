--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local GameRules = require(GetScriptDirectory().."/FunLib/humaniser/game_rules")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local ____camps_data = require(GetScriptDirectory().."/FunLib/humaniser/camps_data")
local DEFAULT_STACK_SEC = ____camps_data.DEFAULT_STACK_SEC
local records = {}
function ____exports.ResetCache()
    records = {}
end
local function settings()
    return LaneConfig.Settings()
end
local function currentMinute()
    return math.floor(DotaTime() / GameRules.NEUTRAL_EVERY)
end
--- 7.41 stack windows (seconds to land the hit) from scripts/creep_pull_timings.txt in pak01_dir.vpk (read 22/10/2026,
-- what the `dota_hud_show_creep_spawn_camp_names` overlay shows), by the camp's spawner origin from maps/dota.vpk:
-- [x, y, stack_start, stack_end]. good_14, good_20, evil_11 and evil_20 are the 7.42 positions (19/11/2026, their windows unchanged). Camps 1,300+ apart, so WINDOW_MATCH cannot pick the wrong one.
local WINDOWS = {
    {-4824, 3915, 54, 56},
    {-3911, 4829, 55, 57},
    {1224, 4176, 55, 56},
    {1064, 2580, 55, 56},
    {-852, 4940, 54, 55},
    {7928, -120, 55, 56},
    {4352, 48, 53, 55},
    {3392, -1408, 53, 55},
    {-4229, 8140, 54, 56},
    {2016, 7896, 55, 57},
    {8430, 1263, 55, 56},
    {336, 7696, 55, 56},
    {-2596, 3850, 55, 56},
    {-6408, 7816, 55, 56},
    {3978, -5027, 55, 57},
    {4649, -3699, 52, 54},
    {186, -5197, 54, 55},
    {-1454, -3356, 55, 56},
    {-4013, 992, 53, 55},
    {-5015, -96, 52, 54},
    {-1983, -4815, 56, 57},
    {-720, -7696, 55, 57},
    {-2415, -8402, 53, 55},
    {-8313, -553, 55, 56},
    {4520, -8336, 55, 57},
    {1922, -3975, 56, 57},
    {-8023, -1838, 55, 56},
    {6712, -7632, 55, 56}
}
local WINDOW_MATCH = 300
--- Valve's stack window for the camp, or undefined (another map, a moved camp, StackFromValve off).
function ____exports.Window(campIdx)
    local spawner = Camps.SpawnerByIdx(campIdx)
    if spawner == nil or settings().Timing.StackFromValve ~= true then
        return nil, nil
    end
    for ____, w in ipairs(WINDOWS) do
        local dx = w[1] - spawner.location.x
        local dy = w[2] - spawner.location.y
        if dx * dx + dy * dy <= WINDOW_MATCH * WINDOW_MATCH then
            return w[3], w[4]
        end
    end
    return nil, nil
end
--- The second the stack hit should land: StackWindowAt through Valve's window for a camp on the type's default second,
-- else the data's (a replay or measured stack second is kept). The seeds (small 54.5 to ancient 53.0) were 1-2.5 s
-- early for most 7.41 camps (evil_2/good_1 55-57, evil_1 54-56) and 1.5 s late for good_2/good_8 (52-54).
function ____exports.AggroSec(data)
    local ____opt_0 = data.stack
    local sec = ____opt_0 and ____opt_0.aggroSec or DEFAULT_STACK_SEC[data.type]
    if sec ~= DEFAULT_STACK_SEC[data.type] then
        return sec
    end
    local from, to = ____exports.Window(data.campIdx)
    if from == nil or to == nil then
        return sec
    end
    return from + (to - from) * settings().Timing.StackWindowAt
end
--- Records the attempt as stacked when `assumed` (the hit landed in the safe band; the box is not counted).
function ____exports.NoteStackOutcome(campIdx, minute, assumed)
    if not assumed then
        return false
    end
    local prev = records[campIdx]
    local count = prev ~= nil and prev.minute == minute - 1 and prev.count + 1 or 1
    records[campIdx] = {minute = minute, count = count}
    return true
end
function ____exports.IsStacked(campIdx)
    local rec = records[campIdx]
    return rec ~= nil and rec.minute >= currentMinute() - 1
end
function ____exports.StackCount(campIdx)
    return ____exports.IsStacked(campIdx) and records[campIdx].count or 0
end
function ____exports.NeutralsInBox(bot, campIdx)
    local margin = settings().Radii.BoxMargin
    local n = 0
    for ____, c in ipairs(bot:GetNearbyNeutralCreeps(
        settings().Radii.StackCountScan,
        false
    ) or ({})) do
        if c ~= nil and c ~= nil and c:IsAlive() and c:CanBeSeen() and Camps.InBox(
            campIdx,
            c:GetLocation(),
            margin
        ) then
            n = n + 1
        end
    end
    return n
end
--- The camp idles at its spawner origin, so that is what must be in sight. Distance alone counted fogged boxes: ogre on
-- good_2 at 8:02, night (hero vision 800) and ~1,100 from the origin, read 2 of 3 neutrals and graded the stack failed.
function ____exports.BoxInSight(bot, campIdx)
    local spawner = Camps.SpawnerByIdx(campIdx)
    if spawner == nil or not bot:IsAlive() then
        return false
    end
    return GetUnitToLocationDistance(bot, spawner.location) <= settings().Radii.StackSight and IsLocationVisible(spawner.location)
end
--- A visible neutral near the bot is attacking it.
function ____exports.NeutralTargets(bot)
    for ____, n in ipairs(bot:GetNearbyNeutralCreeps(
        settings().Radii.NeutralSearch,
        false
    ) or ({})) do
        if n ~= nil and n ~= nil and n:IsAlive() and n:CanBeSeen() and n:GetAttackTarget() == bot then
            return true
        end
    end
    return false
end
return ____exports
