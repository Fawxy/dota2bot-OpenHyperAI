--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayFind(self, predicate, thisArg)
    for i = 1, #self do
        local elem = self[i]
        if predicate(thisArg, elem, i - 1, self) then
            return elem
        end
    end
    return nil
end

local function __TS__ObjectAssign(target, ...)
    local sources = {...}
    for i = 1, #sources do
        local source = sources[i]
        for key in pairs(source) do
            target[key] = source[key]
        end
    end
    return target
end

local function __TS__ArrayIncludes(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    local k = fromIndex
    if fromIndex < 0 then
        k = len + fromIndex
    end
    if k < 0 then
        k = 0
    end
    for i = k + 1, len do
        if self[i] == searchElement then
            return true
        end
    end
    return false
end

local function __TS__ArrayFilter(self, callbackfn, thisArg)
    local result = {}
    local len = 0
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            len = len + 1
            result[len] = self[i]
        end
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local GameRules = require(GetScriptDirectory().."/FunLib/humaniser/game_rules")
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Lane = ____dota.Lane
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LanePush = require(GetScriptDirectory().."/FunLib/humaniser/lane_push")
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
--- What the team sees of the camp now holds at the hit: the origin is in sight and no spawn mark comes before the hit.
function ____exports.ReadsHit(s, now, hitAt)
    local period = LaneConfig.Settings().Timing.PullPeriod
    return s.vis and math.floor(hitAt / period) <= math.floor(now / period)
end
____exports.SETTINGS = {StrongAt = 6, SetSize = {small = 3, medium = 3, large = 3, ancient = 3}}
--- By camp idx: this hero's record of each camp (CampRecord).
local records = {}
--- By camp idx: the look `CampStateOf` took in the frame `t`.
local looks = {}
--- By camp idx: the fight `FightOf` read in the frame `t`.
local fights = {}
function ____exports.ResetCache()
    for ____, t in ipairs({records, looks, fights}) do
        for k in pairs(t) do
            t[k] = nil
        end
    end
end
local function isSupport(u)
    local pos = LaneConfig.PositionOf(u)
    return pos == 4 or pos == 5
end
--- The support that pulls for `bot`'s lane: pos5 when both supports share it.
local function pullerOfLane(bot)
    if LaneConfig.PositionOf(bot) == 5 then
        return true
    end
    local lane = bot:GetAssignedLane()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue9
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or m == bot then
                        __continue9 = true
                        break
                    end
                    if LaneConfig.PositionOf(m) == 5 and m:GetAssignedLane() == lane then
                        return false
                    end
                    __continue9 = true
                until true
                if not __continue9 then
                    break
                end
            end
            i = i + 1
        end
    end
    return true
end
--- The lane's first pull camp; with `Overrides.PullCamp` (a rig's camp type, e.g. `large` for the hard camp) the first of that type.
function ____exports.CampFor(bot)
    local lane = bot:GetAssignedLane()
    if lane ~= Lane.Top and lane ~= Lane.Bot then
        return nil
    end
    local camps = Camps.PullCampsFor(
        bot:GetTeam(),
        lane
    )
    local kind = Overrides.Get("PullCamp")
    if type(kind) == "string" and kind ~= "" then
        return __TS__ArrayFind(
            camps,
            function(____, c) return c.type == kind end
        )
    end
    return camps[1]
end
--- The hero that would pull for its lane, whatever the switches say.
function ____exports.IsPuller(bot)
    return bot:IsBot() and TripTable.Does(
        "pull",
        LaneConfig.PositionOf(bot)
    ) and isSupport(bot) and pullerOfLane(bot) and ____exports.CampFor(bot) ~= nil
end
--- The spawner of the lane's pull camp (the pull's and the stack row's camp).
function ____exports.SpawnerFor(bot)
    local camp = ____exports.CampFor(bot)
    local ____temp_0
    if camp ~= nil then
        ____temp_0 = Camps.SpawnerByIdx(camp.campIdx)
    else
        ____temp_0 = nil
    end
    return ____temp_0
end
local function scan(spawner)
    local m = LaneConfig.Settings().Radii.BoxMargin
    local lo = spawner.min
    local hi = spawner.max
    local z = spawner.location.z
    local x0, y0, x1, y1 = lo.x - m, lo.y - m, hi.x + m, hi.y + m
    local full = IsLocationVisible(Vector(x0, y0, z)) and IsLocationVisible(Vector(x1, y0, z)) and IsLocationVisible(Vector(x0, y1, z)) and IsLocationVisible(Vector(x1, y1, z))
    local s = {
        n = 0,
        seen = 0,
        hp = 0,
        vis = IsLocationVisible(spawner.location),
        full = full,
        units = {}
    }
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        do
            local __continue19
            repeat
                if not u:IsAlive() then
                    __continue19 = true
                    break
                end
                local p = u:GetLocation()
                if p == nil or p == nil then
                    __continue19 = true
                    break
                end
                if p.x < lo.x - m or p.x > hi.x + m or p.y < lo.y - m or p.y > hi.y + m then
                    __continue19 = true
                    break
                end
                s.n = s.n + 1
                if u:CanBeSeen() then
                    s.seen = s.seen + 1
                end
                s.hp = s.hp + u:GetHealth()
                local ____s_units_1 = s.units
                ____s_units_1[#____s_units_1 + 1] = u
                __continue19 = true
            until true
            if not __continue19 then
                break
            end
        end
    end
    return s
end
--- The look at the camp's box now. It scans the neutral list, and the pull asks it more than once in a frame (its `wants` for
-- the record and again for the decision, and its first step after the start), so the scan is kept for the frame. Callers write
-- the decision's fields onto what they get, so each gets its own copy.
function ____exports.CampStateOf(spawner)
    local now = DotaTime()
    local k = looks[spawner.idx]
    if k == nil or k.t ~= now then
        k = {
            t = now,
            s = scan(spawner)
        }
        looks[spawner.idx] = k
    end
    return __TS__ObjectAssign(
        {},
        k.s,
        {units = {unpack(k.s.units)}}
    )
end
local function within(u, at, r)
    if not u:IsAlive() then
        return false
    end
    local p = u:GetLocation()
    if p == nil or p == nil then
        return false
    end
    local dx = p.x - at.x
    local dy = p.y - at.y
    return dx * dx + dy * dy <= r * r
end
local function scanFight(spawner)
    local r = LaneConfig.Settings().Radii.MeetWatch
    local at = spawner.location
    local f = {
        ours = {},
        neutrals = {},
        worked = {},
        engaged = false,
        life = math.huge
    }
    for ____, u in ipairs(GetUnitList(UnitType.NeutralCreeps)) do
        if within(u, at, r) then
            local ____f_neutrals_2 = f.neutrals
            ____f_neutrals_2[#____f_neutrals_2 + 1] = u
        end
    end
    for ____, c in ipairs(GetUnitList(UnitType.AlliedCreeps)) do
        if LanePush.IsLaneCreep(c:GetUnitName()) and within(c, at, r) then
            local ____f_ours_3 = f.ours
            ____f_ours_3[#____f_ours_3 + 1] = c
        end
    end
    if #f.ours == 0 or #f.neutrals == 0 then
        return f
    end
    local hp = 0
    for ____, c in ipairs(f.ours) do
        hp = hp + c:GetHealth()
        local t = c:GetAttackTarget()
        if t ~= nil and t ~= nil and t:GetTeam() == Team.Neutral and __TS__ArrayIncludes(f.neutrals, t) and not __TS__ArrayIncludes(f.worked, t) then
            local ____f_worked_4 = f.worked
            ____f_worked_4[#____f_worked_4 + 1] = t
        end
    end
    local dps = 0
    for ____, n in ipairs(f.neutrals) do
        do
            local __continue41
            repeat
                local t = n:GetAttackTarget()
                if t == nil or t == nil or not __TS__ArrayIncludes(f.ours, t) then
                    __continue41 = true
                    break
                end
                dps = dps + n:GetEstimatedDamageToTarget(true, t, 1, DamageType.All)
                __continue41 = true
            until true
            if not __continue41 then
                break
            end
        end
    end
    f.engaged = #f.worked > 0 or dps > 0
    if dps > 0 then
        f.life = hp / dps
    end
    return f
end
--- The fight at the camp now (CampFight). It scans the neutral and creep lists, and every hero of the team at the camp asks it each
-- round (the stay's `wants`, its verb and its shadow), so the scan is kept for the frame; each asker gets its own copy.
function ____exports.FightOf(spawner)
    local now = DotaTime()
    local k = fights[spawner.idx]
    if k == nil or k.t ~= now then
        k = {
            t = now,
            f = scanFight(spawner)
        }
        fights[spawner.idx] = k
    end
    return __TS__ObjectAssign(
        {},
        k.f,
        {
            ours = {unpack(k.f.ours)},
            neutrals = {unpack(k.f.neutrals)},
            worked = {unpack(k.f.worked)}
        }
    )
end
--- A camp's neutrals within this of its origin, seen alive, stay on the record through a sighting of the box: a stack's
-- pulled set walks back over :00 and stands outside the counted box (`judgement`, the pull's TagRadius).
local RECORD_LEASH = 1200
local function alive(u)
    return not u:IsNull() and u:IsAlive()
end
local function recordCount(r)
    local n = r.added
    for ____, u in ipairs(r.units) do
        if alive(u) then
            n = n + 1
        end
    end
    return n
end
--- The spawn rule since the record's last minute: at each mark an empty camp gets a set, a camp holding neutrals gets nothing
-- (leftovers block the spawn: pullchain1, Dire 7:00). A stack's set is the stack row's to add (NoteSet), since the record
-- cannot tell a pulled-out camp from one in its box.
local function advance(r, ____type, now)
    local m = math.floor(now / GameRules.NEUTRAL_EVERY)
    while r.minute < m do
        r.minute = r.minute + 1
        if r.minute * GameRules.NEUTRAL_EVERY >= GameRules.NEUTRAL_FIRST and recordCount(r) == 0 then
            r.added = r.added + ____exports.SETTINGS.SetSize[____type]
            r.src = "rules"
        end
    end
end
local function recordOf(spawner, now)
    local r = records[spawner.idx]
    if r == nil then
        r = {
            units = {},
            added = 0,
            seenAt = now,
            src = "rules",
            minute = math.floor(now / GameRules.NEUTRAL_EVERY)
        }
        if now >= GameRules.NEUTRAL_FIRST then
            r.added = ____exports.SETTINGS.SetSize[spawner.type]
        end
        records[spawner.idx] = r
    end
    advance(r, spawner.type, now)
    return r
end
--- A look at the camp (`s`, CampStateOf now). A full view (the box's corners in sight, or `close`: one of ours stands at the
-- camp, since the corners never all read visible in the drills, ldr11) replaces the record; a partial one only raises it,
-- since a neutral out of view would drop a strong camp under the bar. An unseen origin says nothing (the API returns no
-- fogged neutrals).
function ____exports.NoteSighting(spawner, s, close)
    if not s.vis then
        return
    end
    local now = DotaTime()
    local r = recordOf(spawner, now)
    if r.heldUntil ~= nil and now < r.heldUntil then
        return
    end
    if not (s.full == true or close) and s.n <= recordCount(r) then
        return
    end
    local units = {unpack(s.units)}
    for ____, u in ipairs(r.units) do
        do
            local __continue62
            repeat
                if not alive(u) or not u:CanBeSeen() or __TS__ArrayIncludes(units, u) or GetUnitToLocationDistance(u, spawner.location) > RECORD_LEASH then
                    __continue62 = true
                    break
                end
                units[#units + 1] = u
                __continue62 = true
            until true
            if not __continue62 then
                break
            end
        end
    end
    r.units = units
    r.added = 0
    r.seenAt = now
    r.src = "seen"
end
--- The stack row's read of its camp after the mark: the set it pulled out (`pulled`, the handles at its hit) and the spawn it
-- saw come in (`fresh`), or a set by the rules when the box was out of sight (`fresh` undefined). It replaces the record:
-- the row held it through the stack (Hold), since no look at the box counts a pulled-out set.
function ____exports.NoteStack(spawner, pulled, fresh)
    local now = DotaTime()
    local r = recordOf(spawner, now)
    r.units = __TS__ArrayFilter(
        pulled,
        function(____, u) return alive(u) end
    )
    r.added = fresh or ____exports.SETTINGS.SetSize[spawner.type]
    r.src = fresh ~= nil and "seen" or "rules"
    if fresh ~= nil then
        r.seenAt = now
    end
    r.heldUntil = nil
end
--- No look updates the record until `until` (or NoteStack): a stack is pulling the camp out of its box.
function ____exports.Hold(spawner, ____until)
    recordOf(
        spawner,
        DotaTime()
    ).heldUntil = ____until
end
--- The camp's strength as this hero knows it now (CampRecord).
function ____exports.Known(spawner)
    local now = DotaTime()
    local r = recordOf(spawner, now)
    local n = recordCount(r)
    return {
        n = n,
        src = r.src,
        age = math.floor((now - r.seenAt) * 10) / 10,
        held = n - r.added
    }
end
--- The camp holds at least the bar's neutrals (SETTINGS.StrongAt) on this hero's record.
function ____exports.Strong(spawner)
    return ____exports.Known(spawner).n >= ____exports.SETTINGS.StrongAt
end
--- `empty` when the camp holds nothing to pull at `hitAt`: nothing returned while the team sees the camp's origin, and no
-- spawn minute before the hit (a camp respawns only on the minute, so it stays empty). An empty box out of sight says
-- nothing: the API returns no fogged neutrals (pc1: every one returned was `CanBeSeen`). `one` the same with a single
-- neutral left: too little to hold a wave (banked `ok` pulls with one neutral seen at the start diverted 26 of 56, two or
-- more 243 of 385; user 04/11/2026: skip it). Stacking it instead is the stack job's call, not this one's.
function ____exports.CampGate(s, now, hitAt)
    if not ____exports.ReadsHit(s, now, hitAt) then
        return nil
    end
    if s.n == 0 then
        return "empty"
    end
    if s.n == 1 then
        return "one"
    end
    return nil
end
return ____exports
