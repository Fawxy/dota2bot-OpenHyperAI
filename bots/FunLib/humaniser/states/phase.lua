--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local Tower = ____dota.Tower
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
function ____exports.Settings()
    return Config.Get().Phase
end
function ____exports.IsEnabled()
    return Config.IsEnabled() and ____exports.Settings().Enable == true and Tasks.Enabled()
end
local TOWERS = {
    {Tower.Top1, 1},
    {Tower.Mid1, 1},
    {Tower.Bot1, 1},
    {Tower.Top2, 2},
    {Tower.Mid2, 2},
    {Tower.Bot2, 2},
    {Tower.Top3, 3},
    {Tower.Mid3, 3},
    {Tower.Bot3, 3},
    {Tower.Base1, 4},
    {Tower.Base2, 4}
}
local ORDER_PHASE = {PUSH = "push", DEFEND = "defend"}
local function enemyOf(team)
    return team == 2 and 3 or 2
end
local function alive(u)
    return u ~= nil and u ~= nil and u:IsAlive()
end
local function towerCount(team)
    local c = {t1 = 0, t2 = 0, t3 = 0}
    for ____, ____value in ipairs(TOWERS) do
        local id = ____value[1]
        local tier = ____value[2]
        do
            local __continue7
            repeat
                if tier > 3 or not alive(GetTower(team, id)) then
                    __continue7 = true
                    break
                end
                if tier == 1 then
                    c.t1 = c.t1 + 1
                elseif tier == 2 then
                    c.t2 = c.t2 + 1
                else
                    c.t3 = c.t3 + 1
                end
                __continue7 = true
            until true
            if not __continue7 then
                break
            end
        end
    end
    return c
end
local function heroes(team)
    local n = 0
    local up = 0
    local levels = 0
    for ____, pid in ipairs(GetTeamPlayers(team)) do
        n = n + 1
        if IsHeroAlive(pid) then
            up = up + 1
        end
        levels = levels + GetHeroLevel(pid)
    end
    return {alive = up, level = n > 0 and levels / n or 0}
end
local function dist2(ax, ay, bx, by)
    local dx = ax - bx
    local dy = ay - by
    return dx * dx + dy * dy
end
--- Enemies seen within SeenWindow, and the most of them near any one of our towers (with that tower's tier).
local function threat(team)
    local cfg = ____exports.Settings()
    local r2 = cfg.ThreatRadius * cfg.ThreatRadius
    local spots = {}
    for ____, pid in ipairs(GetTeamPlayers(enemyOf(team))) do
        do
            local __continue19
            repeat
                if not IsHeroAlive(pid) then
                    __continue19 = true
                    break
                end
                local info = GetHeroLastSeenInfo(pid)
                local last = info ~= nil and info[1] or nil
                if last == nil or last.time_since_seen > cfg.SeenWindow then
                    __continue19 = true
                    break
                end
                spots[#spots + 1] = {x = last.location.x, y = last.location.y}
                __continue19 = true
            until true
            if not __continue19 then
                break
            end
        end
    end
    local most = 0
    local tier = 0
    for ____, ____value in ipairs(TOWERS) do
        local id = ____value[1]
        local t = ____value[2]
        do
            local __continue23
            repeat
                local tower = GetTower(team, id)
                if not alive(tower) then
                    __continue23 = true
                    break
                end
                local loc = tower:GetLocation()
                local n = 0
                for ____, s in ipairs(spots) do
                    if dist2(s.x, s.y, loc.x, loc.y) <= r2 then
                        n = n + 1
                    end
                end
                if n > most or n == most and n > 0 and t > tier then
                    most = n
                    tier = t
                end
                __continue23 = true
            until true
            if not __continue23 then
                break
            end
        end
    end
    return {seen = #spots, heroes = most, tier = tier}
end
--- The snapshot for `team`. Net worth is left out: enemy net worth is not something a player reads mid-fight, and
-- the push phase works from heroes alive and lane fronts. Waves map GetLaneFrontAmount (0 at our base, 1 at
-- theirs) to -1..+1, so 0 is about the river, not the T1 midpoint the SDK nominally uses.
function ____exports.Snapshot(team)
    local ours = heroes(team)
    local theirs = heroes(enemyOf(team))
    local th = threat(team)
    local waves = {}
    for ____, lane in ipairs({Lane.Top, Lane.Mid, Lane.Bot}) do
        waves[#waves + 1] = 2 * GetLaneFrontAmount(team, lane, true) - 1
    end
    return {
        time = DotaTime(),
        towers = {
            ours = towerCount(team),
            theirs = towerCount(enemyOf(team))
        },
        alive = {ours = ours.alive, theirs = theirs.alive},
        levels = {ours = ours.level, theirs = theirs.level},
        enemiesSeen = th.seen,
        threat = {heroes = th.heroes, tier = th.tier},
        waves = waves
    }
end
local appliedOrders = {}
local function applyOrders(l, team)
    local seen = appliedOrders[team]
    if seen == nil then
        seen = {}
        appliedOrders[team] = seen
    end
    for ____, o in ipairs(Orders.GetActive(team)) do
        do
            local __continue35
            repeat
                local phase = ORDER_PHASE[o.type]
                if phase == nil or seen[o.id] then
                    __continue35 = true
                    break
                end
                seen[o.id] = true
                l.Phase.Order(
                    team,
                    phase,
                    o.expiresAt - GameTime(),
                    (("order:" .. o.type) .. ":") .. tostring(o.id)
                )
                __continue35 = true
            until true
            if not __continue35 then
                break
            end
        end
    end
end
local installed = false
local priorsOn = false
local function lib()
    local l = Tasks.Loaded()
    if l == nil or l.Phase == nil then
        return nil
    end
    if not installed then
        installed = true
        l.Phase.configure({interval = ____exports.Settings().Interval})
    end
    local want = ____exports.Settings().Priors == true
    if want ~= priorsOn then
        priorsOn = want
        l.States.SetPrior(want and l.Phase.Prior() or nil)
    end
    return l
end
--- Every frame from Humaniser.Tick, before States.Tick; the SDK builds the snapshot at most every Interval.
function ____exports.Tick(bot)
    if not ____exports.IsEnabled() then
        return
    end
    local l = lib()
    if l == nil then
        return
    end
    local team = bot:GetTeam()
    applyOrders(l, team)
    l.Phase.Tick(
        team,
        function() return ____exports.Snapshot(team) end
    )
end
function ____exports.Describe(team)
    if not ____exports.IsEnabled() then
        return nil
    end
    local ____opt_0 = Tasks.Loaded()
    local cur = ____opt_0 and ____opt_0.Phase.Current(team)
    if cur == nil then
        return "-"
    end
    return (cur.name .. (cur.ordered ~= nil and (" (" .. cur.ordered) .. ")" or "")) .. (priorsOn and "" or " shadow")
end
return ____exports
