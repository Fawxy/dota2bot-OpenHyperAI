--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Lane = ____dota.Lane
local UnitType = ____dota.UnitType
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local Settings = require(GetScriptDirectory().."/FunLib/humaniser/transitions/settings")
____exports.SOURCE = "transitions:ward"
____exports.GANK_ANCHORS = {
    [2] = {
        [Lane.Top] = Vector(-4014, 2569, 0),
        [Lane.Mid] = Vector(-1615, -122, 0),
        [Lane.Bot] = Vector(3097, -4069, 0)
    },
    [3] = {
        [Lane.Top] = Vector(-4310, 3639, 0),
        [Lane.Mid] = Vector(1141, -458, 0),
        [Lane.Bot] = Vector(3810, -4562, 0)
    }
}
local rolls = {}
local reads = {}
local liveAt = {}
local pending = {}
local planted = {}
function ____exports.ResetCache()
    rolls = {}
    reads = {}
    liveAt = {}
    pending = {}
    planted = {}
end
local function dist2D(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
--- Our observer wards' positions, read from the game at most once per WardScanPeriod per team.
local function observers(team)
    local now = DotaTime()
    local cached = reads[team]
    if cached ~= nil and now - cached.at < Settings.Get().WardScanPeriod then
        return cached.locations
    end
    local locations = {}
    for ____, w in ipairs(GetUnitList(UnitType.AlliedWards)) do
        if w:GetUnitName() == "npc_dota_observer_wards" then
            locations[#locations + 1] = w:GetLocation()
        end
    end
    reads[team] = {at = now, locations = locations}
    return locations
end
--- The support of the snapshot's lane: pos 4 off, pos 5 safe, else the lowest support position present. Needs a core in the lane.
local function laneSupport(s)
    local kind = LaneState.LaneKindOf(s.team, s.lane)
    if kind == "mid" then
        return nil
    end
    local core = false
    local lowest
    local expectedPresent = false
    local expected = kind == "off" and 4 or 5
    for ____, h in ipairs(s.allies) do
        do
            local __continue11
            repeat
                if not h.assigned or h.position == nil then
                    __continue11 = true
                    break
                end
                if h.position <= 3 then
                    core = true
                elseif h.position == 4 or h.position == 5 then
                    if h.position == expected then
                        expectedPresent = true
                    end
                    if lowest == nil or h.position < lowest then
                        lowest = h.position
                    end
                end
                __continue11 = true
            until true
            if not __continue11 then
                break
            end
        end
    end
    if not core then
        return nil
    end
    return expectedPresent and expected or lowest
end
function ____exports.Pick(bot, spots)
    pending[bot:GetPlayerID()] = nil
    if not Settings.IsOn("LaneWard") or #spots == 0 then
        return nil
    end
    local cfg = Settings.Get()
    local now = DotaTime()
    if now < cfg.WardFrom or now > cfg.WardTo then
        return nil
    end
    local s = LaneState.ForBot(bot)
    if s == nil then
        return nil
    end
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil or pos ~= laneSupport(s) then
        return nil
    end
    local key = (tostring(s.team) .. ":") .. tostring(s.lane)
    local passed = rolls[key]
    if passed == nil then
        passed = LaneConfig.Roll(Settings.Lerp(
            cfg.WardChance,
            LaneConfig.SkillOf(bot)
        ))
        rolls[key] = passed
    end
    if not passed then
        return nil
    end
    local ____opt_0 = ____exports.GANK_ANCHORS[s.team]
    local anchor = ____opt_0 and ____opt_0[s.lane]
    if anchor == nil then
        return nil
    end
    local done = planted[key]
    if done ~= nil and done.spot.plant_time_obs ~= nil and done.spot.plant_time_obs > 0 and now - done.spot.plant_time_obs < cfg.WardLifetime then
        return nil
    end
    for ____, loc in ipairs(observers(s.team)) do
        if dist2D(loc, anchor) <= cfg.WardCoverRadius then
            return nil
        end
    end
    local best
    local bestD = math.huge
    for ____, spot in ipairs(spots) do
        local d = dist2D(spot.location, anchor)
        if d < bestD then
            bestD = d
            best = spot
        end
    end
    if best == nil or bestD > cfg.WardAnchorRadius then
        return nil
    end
    pending[bot:GetPlayerID()] = {spot = best, key = key}
    return best
end
--- The ward mode took `spot` as its target after its own safety checks: only now does the pick count as live.
function ____exports.Confirm(bot, spot)
    local p = pending[bot:GetPlayerID()]
    if not Settings.IsOn("LaneWard") or p == nil or p.spot ~= spot then
        return
    end
    liveAt[bot:GetPlayerID()] = DotaTime()
    planted[p.key] = {location = spot.location, spot = spot}
end
function ____exports.Tick(bot)
    local at = liveAt[bot:GetPlayerID()]
    if Settings.IsOn("LaneWard") and at ~= nil and DotaTime() - at <= Settings.Get().WardLive then
        Intent.Claim(
            bot,
            {
                source = ____exports.SOURCE,
                tier = "TRANSITION",
                mode = BotMode.Ward,
                floor = Settings.Get().WardFloor
            }
        )
    else
        Intent.Release(bot, ____exports.SOURCE, BotMode.Ward)
    end
end
return ____exports
