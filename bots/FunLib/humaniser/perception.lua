--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- Merged under Customize.Humaniser.Perception; its Enable key is the kill switch, read via Config.
____exports.DEFAULTS = {
    Permanence = 2,
    InstantRange = 300,
    InstantDamageWindow = 0.3,
    TeammateCallout = 1,
    EventGap = 0.5,
    IdentityTimeout = 2,
    WaitForWindowSkill = 0.7,
    Channel = true,
    RefreshInterval = 0.25
}
local NO_CASTER = {}
local observers = {}
local settings
local function weakKeys()
    return setmetatable({}, {__mode = "k"})
end
function ____exports.Settings()
    if settings == nil then
        local merged = {}
        for k, v in pairs(____exports.DEFAULTS) do
            merged[k] = v
        end
        local overrides = Config.Get().Perception
        if overrides ~= nil and type(overrides) == "table" then
            for k, v in pairs(overrides) do
                merged[k] = v
            end
        end
        settings = merged
    end
    return settings
end
function ____exports.IsActive()
    return Config.IsFeatureEnabled("Perception")
end
local function currentObserver()
    local bot = GetBot()
    if bot == nil or bot == nil then
        return nil
    end
    local pid = bot:GetPlayerID()
    local obs = observers[pid]
    if obs == nil then
        obs = {
            pid = pid,
            team = bot:GetTeam(),
            bot = bot,
            sightings = weakKeys(),
            casts = weakKeys(),
            channels = weakKeys(),
            projectiles = weakKeys(),
            refreshAt = -1000,
            lastNoticeDelay = 0,
            lastReactDelay = 0
        }
        observers[pid] = obs
    end
    obs.bot = bot
    return obs
end
local function format2(x)
    return string.format("%.2f", x)
end
--- Keeps lastSeen current for heroes still in our team's vision but outside the radius of recent queries,
-- so a hero in continuous view never loses object permanence. Also feeds the overlay.
local function refresh(obs, now)
    local cfg = ____exports.Settings()
    if now - obs.refreshAt < cfg.RefreshInterval then
        return
    end
    obs.refreshAt = now
    local hidden = 0
    local noticed = 0
    for hero, s in pairs(obs.sightings) do
        if hero:IsNull() then
            obs.sightings[hero] = nil
        elseif now - s.lastSeen < cfg.Permanence then
            if s.lastSeen < now and hero:IsAlive() and hero:CanBeSeen() then
                s.lastSeen = now
            end
            if s.noticed then
                noticed = noticed + 1
            else
                hidden = hidden + 1
            end
        end
    end
    if not HDebug.IsEnabled() then
        return
    end
    local pending = 0
    for ____, e in pairs(obs.casts) do
        if now < e.knownAt then
            pending = pending + 1
        end
    end
    HDebug.Text(
        obs.bot,
        "percept",
        (((("hidden=" .. tostring(hidden)) .. " noticed=") .. tostring(noticed)) .. " lastNotice=") .. format2(obs.lastNoticeDelay)
    )
    HDebug.Text(
        obs.bot,
        "react",
        (("pendingCasts=" .. tostring(pending)) .. " lastReact=") .. format2(obs.lastReactDelay)
    )
end
local function teammateNoticed(obs, hero, now, cfg)
    for ____, other in pairs(observers) do
        if other.pid ~= obs.pid and other.team == obs.team then
            local s = other.sightings[hero]
            if s ~= nil and s.noticed and now - s.noticedAt >= cfg.TeammateCallout and now - s.lastSeen < cfg.Permanence then
                return true
            end
        end
    end
    return false
end
local function immediateReason(obs, hero, now, cfg)
    if obs.bot:WasRecentlyDamagedByHero(hero, cfg.InstantDamageWindow) then
        return "damaged"
    end
    if GetUnitToUnitDistance(obs.bot, hero) <= cfg.InstantRange then
        return "close"
    end
    if teammateNoticed(obs, hero, now, cfg) then
        return "teammate"
    end
    return nil
end
local function isNoticed(obs, hero, now, cfg)
    local s = obs.sightings[hero]
    if s ~= nil and s.frame == now then
        return s.visible
    end
    if s == nil then
        s = {
            firstVisible = now,
            noticeAt = now,
            lastSeen = now,
            noticed = false,
            noticedAt = 0,
            frame = now,
            visible = false
        }
        s.noticeAt = now + Profile.SampleDelay(obs.bot, "notice")
        obs.sightings[hero] = s
    elseif now - s.lastSeen >= cfg.Permanence then
        s.firstVisible = now
        s.noticeAt = now + Profile.SampleDelay(obs.bot, "notice")
        s.noticed = false
    end
    s.lastSeen = now
    s.frame = now
    if not s.noticed then
        local reason = immediateReason(obs, hero, now, cfg) or (now >= s.noticeAt and "delay" or nil)
        if reason ~= nil then
            s.noticed = true
            s.noticedAt = now
            obs.lastNoticeDelay = now - s.firstVisible
            HDebug.Log(
                "perception",
                ((((((("pid=" .. tostring(obs.pid)) .. " noticed ") .. hero:GetUnitName()) .. " after ") .. format2(obs.lastNoticeDelay)) .. "s (") .. reason) .. ")"
            )
            Telemetry.Event(
                "notice",
                {
                    {"pid", obs.pid},
                    {
                        "target",
                        hero:GetUnitName()
                    },
                    {"delay", obs.lastNoticeDelay},
                    {"due", s.noticeAt - s.firstVisible},
                    {"reason", reason}
                }
            )
        end
    end
    s.visible = s.noticed
    return s.visible
end
--- Units the team cannot currently see are passed through untouched and get no sighting. The engine can list
-- such a hero with no location (GetUnitToUnitDistance then fails in its override), and a sighting would keep
-- its lastSeen fresh while out of view, giving it a head start on the notice delay and defeating Permanence.
-- Passing it through leaves callers exactly the engine's answer; their own CanBeSeen checks drop it.
local function isPerceivable(unit)
    return not unit:IsNull() and unit:CanBeSeen() and unit:GetLocation() ~= nil
end
--- O(n) over the original list; returns the original table untouched when nothing is hidden.
local function filterList(obs, list, heroesOnly)
    local now = DotaTime()
    local cfg = ____exports.Settings()
    refresh(obs, now)
    if #list == 0 then
        return list
    end
    local out
    do
        local i = 0
        while i < #list do
            local unit = list[i + 1]
            local visible = not isPerceivable(unit) or heroesOnly and not unit:IsHero() or isNoticed(obs, unit, now, cfg)
            if not visible then
                if out == nil then
                    out = {}
                    do
                        local j = 0
                        while j < i do
                            out[#out + 1] = list[j + 1]
                            j = j + 1
                        end
                    end
                end
            elseif out ~= nil then
                out[#out + 1] = unit
            end
            i = i + 1
        end
    end
    return out or list
end
--- For CDOTA_Bot_Script:GetNearbyHeroes(r, true): filters only when the caller is on our team.
function ____exports.FilterNearbyEnemies(caller, list)
    if not ____exports.IsActive() or caller:GetTeam() ~= GetTeam() then
        return list
    end
    local obs = currentObserver()
    if obs == nil then
        return list
    end
    return filterList(obs, list, false)
end
--- For GetUnitList(UNIT_LIST_ENEMY_HEROES) (heroesOnly=false) or UNIT_LIST_ENEMIES (heroesOnly=true).
function ____exports.FilterUnitList(list, heroesOnly)
    if not ____exports.IsActive() then
        return list
    end
    local obs = currentObserver()
    if obs == nil then
        return list
    end
    return filterList(obs, list, heroesOnly)
end
local function newEvent(obs, name, now)
    return {
        name = name,
        firstSeen = now,
        knownAt = now + Profile.SampleDelay(obs.bot, "react"),
        lastSeen = now,
        logged = false
    }
end
local function markKnown(obs, e, now, who)
    if now < e.knownAt then
        return false
    end
    if not e.logged then
        e.logged = true
        obs.lastReactDelay = e.knownAt - e.firstSeen
        if e.name ~= "attack" then
            HDebug.Log(
                "perception",
                ((((((("pid=" .. tostring(obs.pid)) .. " react ") .. who) .. " ") .. e.name) .. " known after ") .. format2(obs.lastReactDelay)) .. "s"
            )
            Telemetry.Event("react", {{"pid", obs.pid}, {"who", who}, {"what", e.name}, {"delay", obs.lastReactDelay}})
        end
    end
    return true
end
--- True once the observer has watched this cast (caster + ability, from first sighting) for its react delay.
-- Call only while the caster is visibly casting the ability. Always true when perception is off.
function ____exports.IsCastKnown(caster, abilityName)
    if not ____exports.IsActive() then
        return true
    end
    local obs = currentObserver()
    if obs == nil then
        return true
    end
    local now = DotaTime()
    local e = obs.casts[caster]
    if e == nil or e.name ~= abilityName or now - e.lastSeen > ____exports.Settings().EventGap then
        e = newEvent(obs, abilityName, now)
        obs.casts[caster] = e
    end
    e.lastSeen = now
    return markKnown(
        obs,
        e,
        now,
        caster:GetUnitName()
    )
end
--- True when a skilled observer should hold a known targeted-spell reaction until the optimal window.
function ____exports.WaitsForOptimalWindow()
    local bot = GetBot()
    if bot == nil or bot == nil then
        return false
    end
    return Profile.Get(bot).skill >= ____exports.Settings().WaitForWindowSkill
end
--- target:GetIncomingTrackingProjectiles() without enemy projectiles the observer has not yet reacted to.
-- Identity is caster + ability name (or 'attack'); identities absent from a call are dropped.
-- Allied projectiles always pass. Cached per frame and per target.
function ____exports.GetIncomingTrackingProjectiles(target)
    local list = target:GetIncomingTrackingProjectiles()
    if not ____exports.IsActive() then
        return list
    end
    local obs = currentObserver()
    if obs == nil then
        return list
    end
    local now = DotaTime()
    local cache = obs.projectiles[target]
    if cache ~= nil and cache.frame == now then
        return cache.result
    end
    local prev = cache ~= nil and now - cache.frame <= ____exports.Settings().IdentityTimeout and cache.ids or nil
    local ids = weakKeys()
    if cache == nil then
        cache = {frame = now, ids = ids, result = list}
        obs.projectiles[target] = cache
    end
    local out
    do
        local i = 0
        while i < #list do
            local p = list[i + 1]
            local caster = p.caster
            local keep = true
            if caster == nil or caster:GetTeam() ~= obs.team then
                local key = caster or NO_CASTER
                local name = p.is_attack and "attack" or (p.ability ~= nil and p.ability:GetName() or "unknown")
                local byName = ids[key]
                if byName == nil then
                    byName = {}
                    ids[key] = byName
                end
                local ____byName_name_4 = byName[name]
                if ____byName_name_4 == nil then
                    local ____opt_0 = prev and prev[key]
                    ____byName_name_4 = ____opt_0 and ____opt_0[name]
                end
                local e = ____byName_name_4
                if e == nil then
                    e = newEvent(obs, name, now)
                end
                e.lastSeen = now
                byName[name] = e
                keep = markKnown(
                    obs,
                    e,
                    now,
                    caster ~= nil and caster:GetUnitName() or "?"
                )
            end
            if not keep then
                if out == nil then
                    out = {}
                    do
                        local j = 0
                        while j < i do
                            out[#out + 1] = list[j + 1]
                            j = j + 1
                        end
                    end
                end
            elseif out ~= nil then
                out[#out + 1] = p
            end
            i = i + 1
        end
    end
    cache.frame = now
    cache.ids = ids
    cache.result = out or list
    return cache.result
end
--- For CDOTA_Bot_Script:IsChanneling() on enemy units: true only once the observer has seen the channel
-- for its react delay. A channel that follows a cast the observer was already tracking inherits that
-- cast's knownAt, so the wind-up and the channel are not delayed twice.
function ____exports.FilterChanneling(unit, channeling)
    if not ____exports.IsActive() or ____exports.Settings().Channel ~= true then
        return channeling
    end
    local obs = currentObserver()
    if obs == nil then
        return channeling
    end
    if not channeling then
        obs.channels[unit] = nil
        return false
    end
    local now = DotaTime()
    local cfg = ____exports.Settings()
    local e = obs.channels[unit]
    if e == nil or now - e.lastSeen > cfg.IdentityTimeout then
        e = newEvent(obs, "channel", now)
        local cast = obs.casts[unit]
        if cast ~= nil and now - cast.lastSeen <= cfg.EventGap then
            e.firstSeen = cast.firstSeen
            e.knownAt = cast.knownAt
        end
        obs.channels[unit] = e
    end
    e.lastSeen = now
    return markKnown(
        obs,
        e,
        now,
        unit:GetUnitName()
    )
end
return ____exports
