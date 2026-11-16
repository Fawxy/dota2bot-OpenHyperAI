--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__SparseArrayNew(...)
    local sparseArray = {...}
    sparseArray.sparseLength = __TS__CountVarargs(...)
    return sparseArray
end

local function __TS__SparseArrayPush(sparseArray, ...)
    local args = {...}
    local argsLen = __TS__CountVarargs(...)
    local listLen = sparseArray.sparseLength
    for i = 1, argsLen do
        sparseArray[listLen + i] = args[i]
    end
    sparseArray.sparseLength = listLen + argsLen
end

local function __TS__SparseArraySpread(sparseArray)
    local _unpack = unpack or table.unpack
    return _unpack(sparseArray, 1, sparseArray.sparseLength)
end
-- End of Lua Library inline imports
local ____exports = {}
local logged, r2
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local WorldFacts = require(GetScriptDirectory().."/FunLib/humaniser/world_facts")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
--- ev=threat for one consumer's decision on a read: on a changed decision, else at most once per LogEvery per hero and
-- consumer (gates run every think; the design's "once per decision" would flood). Returns whether it logged.
function ____exports.Log(bot, consumer, r, decision)
    local pid = bot:GetPlayerID()
    local key = (tostring(pid) .. ":") .. consumer
    local last = logged[key]
    if last ~= nil and last.decision == decision and r.t - last.t < ____exports.SETTINGS.LogEvery then
        return false
    end
    logged[key] = {t = r.t, decision = decision}
    local ____Telemetry_Event_4 = Telemetry.Event
    local ____array_3 = __TS__SparseArrayNew(
        {"pid", pid},
        {"who", consumer},
        {"dec", decision},
        {
            "x",
            math.floor(r.place.x)
        },
        {
            "y",
            math.floor(r.place.y)
        },
        {
            "hz",
            r2(r.horizon)
        },
        {
            "dep",
            r2(r.depth)
        },
        {
            "threat",
            r2(r.threat)
        },
        {"band", r.band},
        {"reach", #r.reach},
        {
            "rpid",
            #r.reach > 0 and table.concat(r.reach, ",") or nil
        },
        {
            "burst",
            r2(r.burst)
        },
        {"ally", r.allies}
    )
    local ____temp_2
    if #r.reach > 0 then
        ____temp_2 = r.escape
    else
        ____temp_2 = nil
    end
    __TS__SparseArrayPush(
        ____array_3,
        {"esc", ____temp_2},
        {"tower", r.tower},
        {
            "miss",
            r2(r.missing)
        },
        {
            "mpid",
            #r.mpids > 0 and table.concat(r.mpids, ",") or nil
        },
        {
            "mtss",
            r.mtss ~= nil and math.floor(r.mtss + 0.5) or nil
        },
        {"mcut", r.mcut > 0 and r.mcut or nil},
        {
            "hp",
            r2(bot:GetHealth() / math.max(
                1,
                bot:GetMaxHealth()
            ))
        }
    )
    ____Telemetry_Event_4(
        "threat",
        {__TS__SparseArraySpread(____array_3)}
    )
    return true
end
____exports.SETTINGS = {
    MissingAfter = 3,
    MissingSpeed = 330,
    MissingReachMax = 4000,
    MissingMargin = 600,
    EarlyWeight = 0.2,
    LateWeight = 0.5,
    EarlyUntil = 240,
    DepthFactor = {{0.5, 1}, {0.65, 0.25}, {1.01, 0.1}},
    DepthDefault = 0.5,
    DistFactor = {{2000, 1}, {3000, 0.5}, {math.huge, 0.25}},
    GateHorizon = 4,
    MissingRefuse = 0.5,
    VisionCut = true,
    WalkStep = 300,
    BurstWindow = 3,
    TowerReach = 868,
    WReach = 0.25,
    WMissing = 0.3,
    WTower = 0.4,
    WBurst = 0.5,
    WAlly = 0.15,
    Watch = 0.25,
    Pressured = 0.5,
    EscapeItems = {"item_blink", "item_force_staff", "item_tpscroll"},
    EscapeMargin = 100,
    EngagedRecent = 1,
    StandBurst = 1,
    StandHp = 0.5,
    HighBurst = 0.5,
    HighHp = 0.7,
    LogEvery = 5
}
local TOWER_IDS = {
    Tower.Top1,
    Tower.Top2,
    Tower.Top3,
    Tower.Mid1,
    Tower.Mid2,
    Tower.Mid3,
    Tower.Bot1,
    Tower.Bot2,
    Tower.Bot3,
    Tower.Base1,
    Tower.Base2
}
local MAX_PLAYER_ID = 23
local speeds = {}
logged = {}
function ____exports.ResetCache()
    speeds = {}
    logged = {}
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
local function distToSegment(p, a, b)
    local vx = b.x - a.x
    local vy = b.y - a.y
    local len2 = vx * vx + vy * vy
    local u = len2 > 0 and math.max(
        0,
        math.min(1, ((p.x - a.x) * vx + (p.y - a.y) * vy) / len2)
    ) or 0
    return math.sqrt((p.x - (a.x + u * vx)) ^ 2 + (p.y - (a.y + u * vy)) ^ 2)
end
local function valid(u)
    return u ~= nil and u ~= nil and u:IsAlive() and not u:IsIllusion()
end
local T1_IDS = {Tower.Top1, Tower.Mid1, Tower.Bot1}
--- A team's standing towers among `ids`, in `ids` order.
local function standing(team, ids)
    local out = {}
    for ____, id in ipairs(ids) do
        local tw = GetTower(team, id)
        if valid(tw) then
            out[#out + 1] = tw
        end
    end
    return out
end
local function nearestOf(at, place)
    local best
    for ____, a in ipairs(at) do
        local d = dist(a, place)
        if best == nil or d < best then
            best = d
        end
    end
    return best
end
local function stepFactor(steps, v)
    for ____, ____value in ipairs(steps) do
        local edge = ____value[1]
        local f = ____value[2]
        if v < edge then
            return f
        end
    end
    return steps[#steps][2]
end
--- The walk's points every WalkStep, and the place (the vision cut looks at each).
function ____exports.WalkPoints(from, place)
    local d = dist(from, place)
    local n = math.max(
        1,
        math.ceil(d / ____exports.SETTINGS.WalkStep)
    )
    local out = {}
    do
        local i = 0
        while i <= n do
            out[#out + 1] = Vector(from.x + (place.x - from.x) * i / n, from.y + (place.y - from.y) * i / n, place.z)
            i = i + 1
        end
    end
    return out
end
--- Some walk point within `r` of `at` is out of our sight.
local function unseenWithin(points, at, r)
    for ____, p in ipairs(points) do
        if dist(p, at) <= r and not IsLocationVisible(p) then
            return true
        end
    end
    return false
end
local function itemReady(bot, name)
    local slot = bot:FindItemSlot(name)
    if slot < 0 or slot > 5 then
        return false
    end
    local item = bot:GetItemInSlot(slot)
    return item ~= nil and item ~= nil and item:IsFullyCastable()
end
--- The last movement speed Read saw for an enemy hero (the missing belief's run uses it), or undefined.
function ____exports.SeenSpeed(pid)
    return speeds[pid]
end
function ____exports.BandOf(threat, lethal)
    if lethal then
        return "lethal"
    end
    return threat >= ____exports.SETTINGS.Pressured and "pressured" or (threat >= ____exports.SETTINGS.Watch and "watch" or "none")
end
--- The reads for `bot` with `horizon` seconds ahead, as a function of the walk (`from` to `place`). What does not depend on the
-- walk (who is seen and where, the standing towers, the unseen heroes' sightings, an escape item) is read from the game once,
-- here, so a caller weighing several places in one frame (the lane spot) pays for the heroes and towers once. Use it within
-- the frame it was made in. `lethal` fires when the heroes in reach can deal the bot's HP within the burst window, they
-- outnumber our heroes in reach and the bot has no `escape`.
-- 
-- The missing belief: per alive enemy hero unseen for more than MissingAfter, its possible run since the sighting (its last
-- read speed, capped) plus MissingMargin; one whose run touches the walk, with some of that reach out of our sight
-- (VisionCut), adds EarlyWeight or LateWeight by game minute, scaled by the place prior (DepthFactor for the place's depth,
-- DistFactor for its last-seen distance to the place). Walks player ids with GetTeamForPlayer (GetTeamPlayers is empty for
-- a bot-only team). A hero the API has no sighting of is not placed and not counted.
function ____exports.Reader(bot, horizon, opts)
    local s = ____exports.SETTINGS
    local now = DotaTime()
    local team = bot:GetTeam()
    local enemyTeam = team == Team.Radiant and Team.Dire or Team.Radiant
    local hull = bot:GetBoundingRadius()
    local window = math.min(horizon, s.BurstWindow)
    local visible = {}
    local enemies = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue30
            repeat
                if not valid(e) or not e:CanBeSeen() then
                    __continue30 = true
                    break
                end
                local pid = e:GetPlayerID()
                visible[pid] = true
                local sp = e:GetCurrentMovementSpeed()
                if sp ~= nil and sp > 0 then
                    speeds[pid] = sp
                end
                local at = e:GetLocation()
                if at == nil or at == nil then
                    __continue30 = true
                    break
                end
                enemies[#enemies + 1] = {
                    u = e,
                    pid = pid,
                    at = at,
                    run = sp * horizon + e:GetAttackRange() + e:GetBoundingRadius() + hull
                }
                __continue30 = true
            until true
            if not __continue30 then
                break
            end
        end
    end
    local allies = {}
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue35
            repeat
                if not valid(a) or a == bot or RetreatState.Running(a) then
                    __continue35 = true
                    break
                end
                local at = a:GetLocation()
                if at == nil or at == nil then
                    __continue35 = true
                    break
                end
                allies[#allies + 1] = {
                    u = a,
                    pid = a:GetPlayerID(),
                    at = at,
                    run = a:GetCurrentMovementSpeed() * horizon + a:GetAttackRange() + a:GetBoundingRadius() + hull
                }
                __continue35 = true
            until true
            if not __continue35 then
                break
            end
        end
    end
    local enemyTowers = standing(enemyTeam, TOWER_IDS)
    local enemyTowerAt = __TS__ArrayMap(
        enemyTowers,
        function(____, tw) return tw:GetLocation() end
    )
    local enemyTowerReach = {}
    local function depthAt(t, all)
        local t1 = __TS__ArrayMap(
            standing(t, T1_IDS),
            function(____, tw) return tw:GetLocation() end
        )
        return #t1 > 0 and t1 or (all or __TS__ArrayMap(
            standing(t, TOWER_IDS),
            function(____, tw) return tw:GetLocation() end
        ))
    end
    local ownDepthAt = depthAt(team, nil)
    local enemyDepthAt = depthAt(enemyTeam, enemyTowerAt)
    local unseen = {}
    do
        local pid = 0
        while pid <= MAX_PLAYER_ID do
            do
                local __continue43
                repeat
                    local t = GetTeamForPlayer(pid)
                    if t == team or t ~= Team.Radiant and t ~= Team.Dire or visible[pid] == true or not IsHeroAlive(pid) then
                        __continue43 = true
                        break
                    end
                    local info = GetHeroLastSeenInfo(pid)[1]
                    if info == nil or info.time_since_seen <= s.MissingAfter then
                        __continue43 = true
                        break
                    end
                    unseen[#unseen + 1] = {
                        pid = pid,
                        at = info.location,
                        tss = info.time_since_seen,
                        r = math.min((speeds[pid] or s.MissingSpeed) * info.time_since_seen, s.MissingReachMax) + s.MissingMargin
                    }
                    __continue43 = true
                until true
                if not __continue43 then
                    break
                end
            end
            pid = pid + 1
        end
    end
    local early = now < s.EarlyUntil and s.EarlyWeight or s.LateWeight
    local hp = math.max(
        1,
        bot:GetHealth()
    )
    local escapeItem
    return function(from, place)
        local reach = {}
        local chasers = {}
        local eng = {}
        local att = {}
        local dmg = 0
        for ____, e in ipairs(enemies) do
            do
                local __continue47
                repeat
                    if distToSegment(e.at, from, place) > e.run then
                        __continue47 = true
                        break
                    end
                    reach[#reach + 1] = e.pid
                    chasers[#chasers + 1] = e.u
                    if e.dmg == nil then
                        local w = window
                        if (opts and opts.engagedWindow) ~= nil then
                            e.att = e.u:GetAttackTarget() == bot
                            e.eng = bot:WasRecentlyDamagedByHero(e.u, s.EngagedRecent)
                            if e.eng then
                                w = opts.engagedWindow
                            end
                        end
                        e.dmg = e.u:GetEstimatedDamageToTarget(true, bot, w, DamageType.All)
                    end
                    if e.att == true then
                        att[#att + 1] = e.pid
                    end
                    if e.eng == true then
                        eng[#eng + 1] = e.pid
                    end
                    dmg = dmg + e.dmg
                    __continue47 = true
                until true
                if not __continue47 then
                    break
                end
            end
        end
        local near = 0
        for ____, a in ipairs(allies) do
            if distToSegment(a.at, place, place) <= a.run then
                near = near + 1
            end
        end
        local own = nearestOf(ownDepthAt, place)
        local en = nearestOf(enemyDepthAt, place)
        local depth = (own == nil or en == nil or own + en <= 0) and s.DepthDefault or en / (own + en)
        local base = early * stepFactor(s.DepthFactor, depth)
        local missing = 0
        local mcut = 0
        local mtss
        local mpids = {}
        local points
        for ____, m in ipairs(unseen) do
            do
                local __continue58
                repeat
                    if distToSegment(m.at, from, place) > m.r then
                        __continue58 = true
                        break
                    end
                    if s.VisionCut then
                        points = points or ____exports.WalkPoints(from, place)
                        if not unseenWithin(points, m.at, m.r) then
                            mcut = mcut + 1
                            __continue58 = true
                            break
                        end
                    end
                    missing = missing + base * stepFactor(
                        s.DistFactor,
                        dist(m.at, place)
                    )
                    mpids[#mpids + 1] = m.pid
                    mtss = math.max(mtss or 0, m.tss)
                    __continue58 = true
                until true
                if not __continue58 then
                    break
                end
            end
        end
        local tower = false
        do
            local i = 0
            while i < #enemyTowers and not tower do
                local r = enemyTowerReach[i + 1]
                if r == nil then
                    r = WorldFacts.TowerReach(enemyTowers[i + 1], s.TowerReach)
                    enemyTowerReach[i + 1] = r
                end
                tower = dist(enemyTowerAt[i + 1], place) <= r
                i = i + 1
            end
        end
        local escape = true
        if #chasers > 0 then
            if escapeItem == nil then
                escapeItem = false
                for ____, name in ipairs(s.EscapeItems) do
                    if itemReady(bot, name) then
                        escapeItem = true
                    end
                end
            end
            if not escapeItem then
                local ours = bot:GetCurrentMovementSpeed()
                for ____, e in ipairs(chasers) do
                    if e:GetCurrentMovementSpeed() >= ours or GetUnitToUnitDistance(bot, e) - e:GetAttackRange() - e:GetBoundingRadius() - hull < s.EscapeMargin then
                        escape = false
                        break
                    end
                end
            end
        end
        local burst = dmg / hp
        local raw = s.WReach * #reach + s.WMissing * missing + (tower and s.WTower or 0) + s.WBurst * math.min(1, burst) - s.WAlly * near
        local threat = math.max(
            0,
            math.min(1, raw)
        )
        local lethal = burst >= 1 and #reach > near and not escape
        return {
            t = now,
            from = from,
            place = place,
            horizon = horizon,
            depth = depth,
            reach = reach,
            burst = burst,
            allies = near,
            escape = escape,
            tower = tower,
            missing = missing,
            mpids = mpids,
            mtss = mtss,
            mcut = mcut,
            threat = threat,
            band = ____exports.BandOf(threat, lethal),
            eng = eng,
            att = att
        }
    end
end
--- One read: `bot` walking from `from` to `place` with `horizon` seconds ahead (see Reader).
function ____exports.Read(bot, from, place, horizon, opts)
    return ____exports.Reader(bot, horizon, opts)(from, place)
end
--- The lone-hero stand (slice mid-stand): exactly one visible enemy hero can reach the walk, it has not damaged us within
-- EngagedRecent (the read was made with `opts.engagedWindow`, so `eng` is filled), its burst is under StandBurst of our HP,
-- our HP share is StandHp or more, no enemy tower covers the place and the missing belief is under the gates' bar. The lane
-- spot does not refuse such a place and retreat does not leave it on `threat`: h2harbiter1 and 2, the mid stood about 1,400
-- from a lone enemy mid that was not hitting it (burst read 0.69 at the median) and retreat left such a stand 21 times a game.
-- Once that hero hits us the callers' own rules apply again (the dead end "a hold that never hits back" is the hit case).
function ____exports.LoneStand(bot, r)
    local s = ____exports.SETTINGS
    if #r.reach ~= 1 or #r.eng > 0 or r.tower then
        return false
    end
    if r.burst >= s.StandBurst or r.missing >= s.MissingRefuse then
        return false
    end
    return bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    ) >= s.StandHp
end
--- The high-HP stand (slice high-stand): two or more visible enemy heroes can reach the walk, none has damaged us within
-- EngagedRecent, their burst is under HighBurst of our HP, our HP share is HighHp or more, no enemy tower covers the place and
-- the missing belief is under the gates' bar. Retreat does not leave such a place on `threat` (the lone hero is LoneStand's);
-- the lane spot keeps its own limits, so the hero steps back within the lane instead of walking off. Once one of them hits us
-- the read and budget decide again.
function ____exports.HighStand(bot, r)
    local s = ____exports.SETTINGS
    if #r.reach < 2 or #r.eng > 0 or r.tower then
        return false
    end
    if r.burst >= s.HighBurst or r.missing >= s.MissingRefuse then
        return false
    end
    return bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    ) >= s.HighHp
end
local gateCut
--- cut.ts registers the gate's fixture cut here (it imports this module, so the module cannot import it); called after each logged gate decision.
function ____exports.SetGateCut(fn)
    gateCut = fn
end
--- The gate rule the starts share (the core camp trip, the pos3's pull, the support's pull and stack, the farm trip, the pull farm): held
-- by a visible hero who can reach the walk within GateHorizon ("threat"), else by the belief's weight sum at MissingRefuse
-- ("missing"); the read and its decision are logged as ev=threat for `consumer`.
function ____exports.Gate(bot, from, place, consumer)
    local r = ____exports.Read(bot, from, place, ____exports.SETTINGS.GateHorizon)
    local why = #r.reach > 0 and "threat" or (r.missing >= ____exports.SETTINGS.MissingRefuse and "missing" or nil)
    if ____exports.Log(bot, consumer, r, why or "go") and gateCut ~= nil then
        pcall(
            gateCut,
            bot,
            from,
            place,
            consumer
        )
    end
    return {why = why, r = r}
end
r2 = function(x) return math.floor(x * 100 + 0.5) / 100 end
return ____exports
