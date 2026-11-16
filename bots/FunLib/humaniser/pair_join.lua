--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end

local function __TS__ObjectEntries(obj)
    local result = {}
    local len = 0
    for key in pairs(obj) do
        len = len + 1
        result[len] = {key, obj[key]}
    end
    return result
end

local function __TS__StringSubstring(self, start, ____end)
    if ____end ~= ____end then
        ____end = 0
    end
    if ____end ~= nil and start > ____end then
        start, ____end = ____end, start
    end
    if start >= 0 then
        start = start + 1
    else
        start = 1
    end
    if ____end ~= nil and ____end < 0 then
        ____end = 0
    end
    return string.sub(self, start, ____end)
end
-- End of Lua Library inline imports
local ____exports = {}
local live, dist, member, weigh, heroOf
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local UnitType = ____dota.UnitType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local SpellReady = require(GetScriptDirectory().."/FunLib/humaniser/spell_ready")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local RetreatState = require(GetScriptDirectory().."/FunLib/humaniser/retreat_state")
function live(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:GetLocation() ~= nil and not u:IsIllusion()
end
function dist(a, b)
    local p = a:GetLocation()
    local q = b:GetLocation()
    return math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2)
end
function member(u, ours)
    local l = u:GetLocation()
    local m = {
        pid = u:GetPlayerID(),
        x = math.floor(l.x + 0.5),
        y = math.floor(l.y + 0.5),
        hp = math.floor(u:GetHealth() + 0.5),
        mhp = math.floor(u:GetMaxHealth() + 0.5)
    }
    if ours then
        m.ret = RetreatState.Running(u) and 1 or 0
    end
    return m
end
function weigh(ally, ours)
    local theirs = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        if live(e) and e:CanBeSeen() and dist(e, ally) <= ____exports.SETTINGS.FoeRange then
            theirs[#theirs + 1] = e
        end
    end
    if #theirs == 0 then
        return nil
    end
    local dmg = {}
    local function fill(from, on)
        for ____, f in ipairs(from) do
            local row = {}
            for ____, o in ipairs(on) do
                row[o:GetPlayerID()] = math.floor(SpellReady.DamageOn(f, o, ____exports.SETTINGS.Window) + 0.5)
            end
            dmg[f:GetPlayerID()] = row
        end
    end
    fill(ours, theirs)
    fill(theirs, ours)
    return {
        ally = ally:GetPlayerID(),
        ours = __TS__ArrayMap(
            ours,
            function(____, u) return member(u, true) end
        ),
        theirs = __TS__ArrayMap(
            theirs,
            function(____, u) return member(u, false) end
        ),
        dmg = dmg
    }
end
function heroOf(pid)
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        if live(e) and e:GetPlayerID() == pid then
            return e
        end
    end
    return nil
end
____exports.SETTINGS = {
    AllyRange = 1200,
    FoeRange = 1000,
    OursRange = 1200,
    HitRecent = 1,
    Window = 3,
    Every = 0.5,
    Until = 720,
    CutEvery = 2,
    Keep = 1.5,
    TargetRange = 1200,
    AfterWindow = 8,
    AfterEvery = 1
}
--- The side `from`'s best kill share on `on` over the window: the target and the share.
local function best(from, on, dmg)
    local tgt = -1
    local share = 0
    for ____, o in ipairs(on) do
        local d = 0
        for ____, f in ipairs(from) do
            local ____opt_0 = dmg[f.pid]
            d = d + (____opt_0 and ____opt_0[o.pid] or 0)
        end
        local s = d / math.max(o.hp, 1)
        if tgt == -1 or s > share then
            tgt = o.pid
            share = s
        end
    end
    return tgt, share
end
--- The rule: outnumbered stays out; else join when our best kill share beats theirs. Ours in retreat (`ret` 1) are leaving: they count on neither side.
function ____exports.Decide(rec)
    local ours = __TS__ArrayFilter(
        rec.ours,
        function(____, m) return m.ret ~= 1 end
    )
    local tgt, ko = best(ours, rec.theirs, rec.dmg)
    local ____, kt = best(rec.theirs, ours, rec.dmg)
    if #rec.theirs > #ours then
        return {dec = "outnumbered", tgt = tgt, ko = ko, kt = kt}
    end
    return {dec = ko > kt and "join" or "losing", tgt = tgt, ko = ko, kt = kt}
end
--- The situation's record, or undefined when no ally within AllyRange (the bot included) was hit by a hero within HitRecent,
-- or fewer than two of ours not retreating stand within OursRange of the hit ally (a hero alone is D1's and D24's, not a
-- pair's; review of pair-join-on: a partner in retreat left a lone hero weighed 1v1, which could join). The hit ally is
-- the one at the lowest HP share.
function ____exports.Gather(bot)
    local ally
    local allies = {}
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        do
            local __continue16
            repeat
                if not live(a) then
                    __continue16 = true
                    break
                end
                allies[#allies + 1] = a
                if dist(a, bot) > ____exports.SETTINGS.AllyRange or not a:WasRecentlyDamagedByAnyHero(____exports.SETTINGS.HitRecent) then
                    __continue16 = true
                    break
                end
                if ally == nil or a:GetHealth() / a:GetMaxHealth() < ally:GetHealth() / ally:GetMaxHealth() then
                    ally = a
                end
                __continue16 = true
            until true
            if not __continue16 then
                break
            end
        end
    end
    if ally == nil then
        return nil
    end
    local ours = __TS__ArrayFilter(
        allies,
        function(____, a) return dist(a, ally) <= ____exports.SETTINGS.OursRange end
    )
    if #__TS__ArrayFilter(
        ours,
        function(____, a) return not RetreatState.Running(a) end
    ) < 2 then
        return nil
    end
    return weigh(ally, ours)
end
local states = {}
--- The bot's decision, made afresh at most every Every s (the matrix is 2 x n x m estimates); reads only.
function ____exports.For(bot)
    local now = DotaTime()
    local pid = bot:GetPlayerID()
    local ____temp_2 = states[pid] or ({})
    states[pid] = ____temp_2
    local st = ____temp_2
    if st.at ~= nil and now >= st.at and now - st.at < ____exports.SETTINGS.Every then
        return {rec = st.rec, ans = st.ans, fresh = false}
    end
    st.at = now
    local ____temp_3
    if bot:IsAlive() and now <= ____exports.SETTINGS.Until then
        ____temp_3 = ____exports.Gather(bot)
    else
        ____temp_3 = nil
    end
    st.rec = ____temp_3
    st.ans = st.rec ~= nil and ____exports.Decide(st.rec) or nil
    local ____opt_4 = st.ans
    if (____opt_4 and ____opt_4.dec) == "join" then
        st.joinAt = now
        st.joinTgt = st.ans.tgt
    elseif st.ans ~= nil then
        st.joinAt = nil
    end
    return {rec = st.rec, ans = st.ans, fresh = true}
end
--- With `Ours.PairJoin`: the enemy hero this bot joins the fight on (D10), or undefined. The last answer was `join` within
-- Keep s with no other answer since, the bot is not retreating, and the target is alive, seen and within TargetRange of it.
function ____exports.Joins(bot)
    if not Ours.On("PairJoin") or not bot:IsAlive() or RetreatState.Running(bot) then
        return nil
    end
    ____exports.For(bot)
    local st = states[bot:GetPlayerID()]
    if (st and st.joinAt) == nil or DotaTime() - st.joinAt > ____exports.SETTINGS.Keep then
        return nil
    end
    local ____temp_8
    if st.joinTgt ~= nil then
        ____temp_8 = heroOf(st.joinTgt)
    else
        ____temp_8 = nil
    end
    local t = ____temp_8
    if t == nil or not t:CanBeSeen() or dist(t, bot) > ____exports.SETTINGS.TargetRange then
        return nil
    end
    return t
end
local function members(ms)
    return table.concat(
        __TS__ArrayMap(
            ms,
            function(____, m) return table.concat(
                {
                    m.pid,
                    m.x,
                    m.y,
                    m.hp,
                    m.mhp,
                    unpack(m.ret ~= nil and ({m.ret}) or ({}))
                },
                ","
            ) end
        ),
        ";"
    )
end
local function dmgOf(rec)
    local out = {}
    for ____, side in ipairs({rec.ours, rec.theirs}) do
        for ____, f in ipairs(side) do
            for ____, ____value in ipairs(__TS__ObjectEntries(rec.dmg[f.pid] or ({}))) do
                local to = ____value[1]
                local d = ____value[2]
                out[#out + 1] = (((tostring(f.pid) .. ",") .. to) .. ",") .. tostring(d)
            end
        end
    end
    return table.concat(out, ";")
end
local watches = {}
local function r3(v)
    return math.floor(v * 1000 + 0.5) / 1000
end
local function r2(v)
    return math.floor(v * 100 + 0.5) / 100
end
--- A sample's field: whole numbers without a decimal point (Lua prints 1.0), others as rounded.
local function f(v)
    return type(v) ~= "number" and v or (v == math.floor(v) and string.format("%d", v) or string.format("%g", v))
end
local function flush(pid, res)
    local w = watches[pid]
    if w == nil then
        return
    end
    watches[pid] = nil
    Telemetry.Event(
        "join_after",
        {
            {"pid", pid},
            {"kind", w.kind},
            {"why", w.why},
            {"tgt", w.tgt},
            {"res", res},
            {
                "s",
                table.concat(w.samples, ";")
            }
        }
    )
end
--- A taken `join` or `trade` window of `bot` on `tpid` has ended with `why` (states/core_trade close): watch the weighing for
-- AfterWindow s, while telemetry is on and in the laning stage. A watch still open ends `reopen`. Reads only.
function ____exports.After(bot, kind, why, tpid)
    if not Telemetry.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    flush(pid, "reopen")
    local now = DotaTime()
    if kind ~= "join" and kind ~= "trade" or now > ____exports.SETTINGS.Until or not bot:IsAlive() then
        return
    end
    watches[pid] = {
        kind = kind,
        why = why,
        tgt = tpid,
        start = now,
        next = now,
        samples = {}
    }
end
--- Any CoreTrade window of `bot` (trade, join, kill, fight) has started: an open watch ends `reopen` (the fight went on). Reads only.
function ____exports.Reopened(bot)
    flush(
        bot:GetPlayerID(),
        "reopen"
    )
end
--- One sample of the watch: the weighing around the bot itself (no hit and no pair needed).
local function sample(bot, w, now)
    local allies = {}
    for ____, a in ipairs(GetUnitList(UnitType.AlliedHeroes) or ({})) do
        if live(a) and dist(a, bot) <= ____exports.SETTINGS.OursRange then
            allies[#allies + 1] = a
        end
    end
    local t = heroOf(w.tgt)
    local seen = t ~= nil and t:CanBeSeen()
    local thp = seen and r2(t:GetHealth() / math.max(
        1,
        t:GetMaxHealth()
    )) or -1
    local d = seen and math.floor(dist(t, bot) + 0.5) or -1
    local hp = r2(bot:GetHealth() / math.max(
        1,
        bot:GetMaxHealth()
    ))
    local dt = math.floor((now - w.start) * 10 + 0.5) / 10
    local rec = weigh(bot, allies)
    if rec == nil then
        return table.concat(
            __TS__ArrayMap(
                {
                    dt,
                    "n",
                    0,
                    0,
                    thp,
                    d,
                    hp,
                    #__TS__ArrayFilter(
                        allies,
                        function(____, a) return not RetreatState.Running(a) end
                    ),
                    0
                },
                function(____, v) return f(v) end
            ),
            ":"
        )
    end
    local a = ____exports.Decide(rec)
    local no = #__TS__ArrayFilter(
        rec.ours,
        function(____, m) return m.ret ~= 1 end
    )
    return table.concat(
        __TS__ArrayMap(
            {
                dt,
                __TS__StringSubstring(a.dec, 0, 1),
                r3(a.ko),
                r3(a.kt),
                thp,
                d,
                hp,
                no,
                #rec.theirs
            },
            function(____, v) return f(v) end
        ),
        ":"
    )
end
--- Per frame: the open watch's sample when due, and its line at the end. Reads only.
local function tickAfter(bot, now)
    local pid = bot:GetPlayerID()
    local w = watches[pid]
    if w == nil then
        return
    end
    if not bot:IsAlive() or now > w.next + ____exports.SETTINGS.AfterEvery then
        return flush(pid, "dead")
    end
    if now > ____exports.SETTINGS.Until then
        return flush(pid, "stage")
    end
    if now >= w.next then
        local ____w_samples_9 = w.samples
        ____w_samples_9[#____w_samples_9 + 1] = sample(bot, w, now)
        w.next = now + ____exports.SETTINGS.AfterEvery
    end
    if now - w.start >= ____exports.SETTINGS.AfterWindow then
        flush(pid, "full")
    end
end
--- Per frame (index Tick): on each fresh decision in the laning stage, its cut; the join-after watch. Reads only.
function ____exports.Tick(bot)
    if Telemetry.IsEnabled() then
        tickAfter(
            bot,
            DotaTime()
        )
    end
    if not Telemetry.IsEnabled() or Telemetry.Get().Cut ~= true or not bot:IsAlive() then
        return
    end
    local now = DotaTime()
    if now > ____exports.SETTINGS.Until then
        return
    end
    local pid = bot:GetPlayerID()
    local ____exports_For_result_10 = ____exports.For(bot)
    local rec = ____exports_For_result_10.rec
    local a = ____exports_For_result_10.ans
    local fresh = ____exports_For_result_10.fresh
    if not fresh then
        return
    end
    local st = states[pid]
    if rec == nil or a == nil then
        st.dec = nil
        return
    end
    if a.dec == st.dec and now - (st.cutAt or -math.huge) < ____exports.SETTINGS.CutEvery then
        return
    end
    st.dec = a.dec
    st.cutAt = now
    Telemetry.Event(
        "cut",
        {
            {"pid", pid},
            {"kind", "join"},
            {"al", rec.ally},
            {
                "po",
                members(rec.ours)
            },
            {
                "pt",
                members(rec.theirs)
            },
            {
                "dm",
                dmgOf(rec)
            },
            {"dec", a.dec},
            {"tgt", a.tgt},
            {
                "ko",
                math.floor(a.ko * 1000 + 0.5) / 1000
            },
            {
                "kt",
                math.floor(a.kt * 1000 + 0.5) / 1000
            }
        }
    )
end
return ____exports
