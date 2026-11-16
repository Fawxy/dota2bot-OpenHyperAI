--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local LaneFightConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_config")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local AbilityClasses = require(GetScriptDirectory().."/FunLib/humaniser/ability_classes")
local Perception = require(GetScriptDirectory().."/FunLib/humaniser/perception")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local SLOTS = 6
local SUMMARY_EVERY = 30
local ABILITY_CACHE = 5
local JUMP_POLLS = 2.5
local watches = {}
local abilityCache = {}
local function freshStats(now)
    return {
        since = now,
        polls = 0,
        visible = 0,
        casts = 0,
        jumps = 0
    }
end
local function watchFor(pid)
    local w = watches[pid]
    if w == nil then
        w = {
            nextPoll = -math.huge,
            seen = {},
            lastLoc = {},
            callbacks = {},
            pending = {},
            stats = freshStats(DotaTime())
        }
        watches[pid] = w
    end
    return w
end
local function isNullHandle(h)
    return h == nil or h == nil or h.IsNull ~= nil and h:IsNull() == true
end
local function usable(u)
    if isNullHandle(u) then
        return false
    end
    local unit = u
    if not unit:IsAlive() or not unit:CanBeSeen() or unit:IsIllusion() or unit:GetLocation() == nil then
        return false
    end
    local suspicious = LaneConfig.Helpers().IsSuspiciousIllusion
    return suspicious == nil or not suspicious(unit)
end
--- Ultimate: 1 at hero level 6, 2 at 12, 3 at 18. Basic ability: min(4, ceil(heroLevel / 2)).
function ____exports.LevelEstimate(heroLevel, isUlt)
    if isUlt then
        return heroLevel >= 18 and 3 or (heroLevel >= 12 and 2 or (heroLevel >= 6 and 1 or 0))
    end
    return math.max(
        0,
        math.min(
            4,
            math.ceil(heroLevel / 2)
        )
    )
end
local function handleLevel(h)
    if h.GetLevel == nil then
        return 0
    end
    local level = h:GetLevel()
    return type(level) == "number" and level or 0
end
local function isUltimate(h, slot, item)
    if item then
        return false
    end
    if h.IsUltimate ~= nil then
        return h:IsUltimate() == true
    end
    return slot == 5
end
local function describe(h, name, slot, heroLevel, item, cast)
    local ult = isUltimate(h, slot, item)
    local read = handleLevel(h)
    local level = read > 0 and read or (item and 1 or ____exports.LevelEstimate(heroLevel, ult))
    if cast and level < 1 then
        level = 1
    end
    return {
        name = name,
        slot = slot,
        learned = level > 0,
        ult = ult,
        level = level,
        item = item
    }
end
local function isItemName(name)
    return string.sub(name, 1, 5) == "item_"
end
local function nameOf(h)
    if isNullHandle(h) or h.GetName == nil then
        return nil
    end
    local name = h:GetName()
    return type(name) == "string" and name ~= "" and name or nil
end
--- Learned and unlearned abilities in slots 0-5 and items in inventory slots 0-5 (item = true), cached per enemy pid.
function ____exports.AbilitiesOf(enemy)
    if isNullHandle(enemy) then
        return {}
    end
    local epid = enemy:GetPlayerID()
    local now = DotaTime()
    local cached = abilityCache[epid]
    if cached ~= nil and now - cached.at < ABILITY_CACHE then
        return cached.list
    end
    local heroLevel = enemy:GetLevel()
    local list = {}
    do
        local i = 0
        while i < SLOTS do
            do
                local __continue24
                repeat
                    local a = enemy:GetAbilityInSlot(i)
                    local name = nameOf(a)
                    if name == nil or name == "generic_hidden" or a.IsHidden ~= nil and a:IsHidden() == true then
                        __continue24 = true
                        break
                    end
                    list[#list + 1] = describe(
                        a,
                        name,
                        i,
                        heroLevel,
                        false,
                        false
                    )
                    __continue24 = true
                until true
                if not __continue24 then
                    break
                end
            end
            i = i + 1
        end
    end
    do
        local i = 0
        while i < SLOTS do
            local it = enemy:GetItemInSlot(i)
            local name = nameOf(it)
            if name ~= nil then
                list[#list + 1] = describe(
                    it,
                    name,
                    i,
                    heroLevel,
                    true,
                    false
                )
            end
            i = i + 1
        end
    end
    abilityCache[epid] = {at = now, list = list}
    return list
end
local function slotOf(enemy, name)
    for ____, a in ipairs(____exports.AbilitiesOf(enemy)) do
        if a.name == name then
            return a.slot
        end
    end
    return -1
end
local function contains(name, part)
    return (string.find(name, part, 1, true)) ~= nil
end
local function blinkAbility(enemy)
    for ____, a in ipairs(____exports.AbilitiesOf(enemy)) do
        if a.learned and AbilityClasses.IsEscape(a.name) and contains(a.name, "blink") then
            return a
        end
    end
    return nil
end
--- The last visible cast this observer saw.
function ____exports.LastSeenCast(observerPid)
    local w = watches[observerPid]
    local ____temp_0
    if w == nil then
        ____temp_0 = nil
    else
        ____temp_0 = w.lastSeen
    end
    return ____temp_0
end
local function noteCast(w, enemyPid, info, now)
    local key = (tostring(enemyPid) .. ":") .. info.name
    local prev = w.seen[key]
    w.seen[key] = now
    if prev ~= nil and now - prev <= Perception.Settings().EventGap then
        return
    end
    local ____w_stats_1, ____casts_2 = w.stats, "casts"
    ____w_stats_1[____casts_2] = ____w_stats_1[____casts_2] + 1
    w.lastSeen = {enemyPid = enemyPid, ability = info.name, at = now}
end
local function castInfo(enemy, h, name)
    return describe(
        h,
        name,
        slotOf(enemy, name),
        enemy:GetLevel(),
        isItemName(name),
        true
    )
end
local function pollCast(w, enemy, enemyPid, now)
    if not enemy:IsCastingAbility() and not enemy:IsUsingAbility() then
        return
    end
    local a = enemy:GetCurrentActiveAbility()
    local name = nameOf(a)
    if name == nil then
        return
    end
    noteCast(
        w,
        enemyPid,
        castInfo(enemy, a, name),
        now
    )
end
local function checkJump(w, enemy, enemyPid, now)
    local loc = enemy:GetLocation()
    local prev = w.lastLoc[enemyPid]
    w.lastLoc[enemyPid] = {x = loc.x, y = loc.y, at = now}
    if prev == nil or now - prev.at > LaneFightConfig.Settings().PollInterval * JUMP_POLLS then
        return
    end
    local dx = loc.x - prev.x
    local dy = loc.y - prev.y
    if math.sqrt(dx * dx + dy * dy) <= LaneFightConfig.Settings().BlinkJump then
        return
    end
    local ____w_stats_3, ____jumps_4 = w.stats, "jumps"
    ____w_stats_3[____jumps_4] = ____w_stats_3[____jumps_4] + 1
    local blink = blinkAbility(enemy)
    if blink ~= nil then
        noteCast(w, enemyPid, blink, now)
    end
end
local function visibleEnemy(bot, enemyPid)
    for ____, e in ipairs(LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )) do
        if e ~= nil and e.pid == enemyPid and e.visible and usable(e.unit) then
            return e.unit
        end
    end
    return nil
end
local function onCastEvent(bot, enemyPid, event, now)
    if not LaneFightConfig.IsOn("Memory") or not LaneFightConfig.Settings().UseCastCallback then
        return
    end
    if now < 0 or not LaneConfig.InLaningPhase() or isNullHandle(bot) then
        return
    end
    local caster = visibleEnemy(bot, enemyPid)
    if caster == nil or type(event) ~= "table" then
        return
    end
    if event.unit ~= nil and event.unit ~= nil and event.unit ~= caster then
        return
    end
    local a = event.ability
    local name = type(a) == "string" and a or nameOf(a)
    if name == nil then
        return
    end
    local info
    if type(a) == "string" then
        for ____, x in ipairs(____exports.AbilitiesOf(caster)) do
            if x.name == name then
                info = x
            end
        end
    else
        info = castInfo(caster, a, name)
    end
    if info ~= nil then
        noteCast(
            watchFor(bot:GetPlayerID()),
            enemyPid,
            info,
            now
        )
    end
end
--- A dead observer has no Tick to drain its queue; casts past this many are dropped.
local PENDING_MAX = 32
local function installCallbacks(bot, w)
    local enemyTeam = bot:GetTeam() == Team.Radiant and Team.Dire or Team.Radiant
    for ____, enemyPid in ipairs(GetTeamPlayers(enemyTeam)) do
        do
            local __continue65
            repeat
                if w.callbacks[enemyPid] == true then
                    __continue65 = true
                    break
                end
                w.callbacks[enemyPid] = true
                local function handler(event)
                    if #w.pending < PENDING_MAX then
                        local ____w_pending_5 = w.pending
                        ____w_pending_5[#____w_pending_5 + 1] = {
                            enemyPid = enemyPid,
                            event = event,
                            at = DotaTime()
                        }
                    end
                end
                InstallCastCallback(
                    enemyPid,
                    Telemetry.GuardsEnabled() and Telemetry.Guard("CastWatch.OnCast", handler) or handler
                )
                __continue65 = true
            until true
            if not __continue65 then
                break
            end
        end
    end
end
local function summarise(bot, w, now)
    local st = w.stats
    if now - st.since < SUMMARY_EVERY then
        return
    end
    Telemetry.Event(
        "lanefight_watch",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"polls", st.polls},
            {"visible", st.visible},
            {"casts", st.casts},
            {"jumps", st.jumps}
        }
    )
    w.stats = freshStats(now)
end
--- Whether a cast callback has queued an event this bot has not read yet.
function ____exports.Pending(bot)
    local w = watches[bot:GetPlayerID()]
    return w ~= nil and #w.pending > 0
end
--- Reads the queued cast events. Every frame (LaneFight.Frame): an event counts only while its caster is visible at the
-- read, so a blink into fog read a few frames late would be dropped.
function ____exports.Drain(bot)
    local now = DotaTime()
    if now < 0 then
        return
    end
    local w = watchFor(bot:GetPlayerID())
    if #w.pending == 0 then
        return
    end
    local queued = w.pending
    w.pending = {}
    local gap = Perception.Settings().EventGap
    for ____, q in ipairs(queued) do
        if now - q.at <= gap then
            onCastEvent(bot, q.enemyPid, q.event, q.at)
        end
    end
end
function ____exports.Tick(bot)
    local now = DotaTime()
    if now < 0 then
        return
    end
    ____exports.Drain(bot)
    local w = watchFor(bot:GetPlayerID())
    if now < w.nextPoll then
        return
    end
    local s = LaneFightConfig.Settings()
    w.nextPoll = now + s.PollInterval - 0.000001
    if s.UseCastCallback == true then
        installCallbacks(bot, w)
    end
    local visible = {}
    for ____, e in ipairs(LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )) do
        do
            local __continue83
            repeat
                if e == nil or not e.visible or not usable(e.unit) then
                    __continue83 = true
                    break
                end
                visible[e.pid] = true
                local ____w_stats_6, ____visible_7 = w.stats, "visible"
                ____w_stats_6[____visible_7] = ____w_stats_6[____visible_7] + 1
                pollCast(w, e.unit, e.pid, now)
                checkJump(w, e.unit, e.pid, now)
                __continue83 = true
            until true
            if not __continue83 then
                break
            end
        end
    end
    local ____w_stats_8, ____polls_9 = w.stats, "polls"
    ____w_stats_8[____polls_9] = ____w_stats_8[____polls_9] + 1
    summarise(bot, w, now)
    for pid in pairs(w.lastLoc) do
        if visible[pid] ~= true then
            w.lastLoc[pid] = nil
        end
    end
end
return ____exports
