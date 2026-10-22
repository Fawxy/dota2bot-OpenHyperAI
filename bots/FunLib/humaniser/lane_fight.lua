--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayPush(self, ...)
    local items = {...}
    local len = #self
    for i = 1, #items do
        len = len + 1
        self[len] = items[i]
    end
    return len
end
-- End of Lua Library inline imports
local ____exports = {}
local stateFor, gatesOpen, hpFraction, floorOf, touch, gate, priorityLive, startBlocked, usableUnit, memberByPid, isSupport, partnerOf, holdsReadyKey, isHeroTarget, skillOf, castingAt, sampleDistance, followable, partnerCommitTarget, countsPartner, attackingInRange, focusCap, claim, believedDown, start, ____end, checkMistake, partnerAbandoned, logAbandon, abortSignal, abortReason, lastHits, attackingTarget, targetEntry, seenTarget, endReason, checkEnd, heroName, callKill, planKill, visibleEnemy, coordinate, considerKill, INSTANCE_GAP, END_GRACE, MODE_GRACE, LEASH, RANGE_SLACK, ACTIVE_BOOST, WAIT_TIMEOUT, WAIT_HOLD, MISTAKE_WINDOW, FACING_COS, CAST_SLACK, CLOSE_MIN, PREV_MAX_AGE, SAMPLE_GAP, COUNT_EVERY, COUNT_RADIUS, IN_RANGE_ATTACKS, FOLLOW_FRESH, PARTNER_RANGE, INITIATE_GRACE, NEAR_MISS, FOCUS_SOURCE, PARTNER_ABANDON, COMMIT_ROLES, FOCUS_MODES, START_MODES, fights, tracks
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local LaneFightConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_config")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local AbilityClasses = require(GetScriptDirectory().."/FunLib/humaniser/ability_classes")
local CooldownMemory = require(GetScriptDirectory().."/FunLib/humaniser/cooldown_memory")
local CastWatch = require(GetScriptDirectory().."/FunLib/humaniser/cast_watch")
local FightRead = require(GetScriptDirectory().."/FunLib/humaniser/fight_read")
local KillCheck = require(GetScriptDirectory().."/FunLib/humaniser/kill_check")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local Orders = require(GetScriptDirectory().."/FunLib/humaniser/orders")
local Profile = require(GetScriptDirectory().."/FunLib/humaniser/profile")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
function stateFor(bot)
    local pid = bot:GetPlayerID()
    local s = fights[pid]
    if s == nil then
        s = {
            phase = "idle",
            startedAt = 0,
            tookOver = false,
            spent = {},
            hits = 0,
            lastAttack = 0,
            streak = 0,
            killDelay = 0,
            instances = {},
            partners = {},
            partnerSeen = {},
            partnerSince = 0,
            startEnemies = 0,
            countUp = false,
            countAt = -math.huge
        }
        fights[pid] = s
    end
    return s
end
function gatesOpen(bot)
    if not LaneFightConfig.IsActive() or not LaneFightConfig.AppliesTo(bot) or not LaneConfig.InLaningPhase() then
        return false
    end
    return LaneFightConfig.IsOn("Trade") or LaneFightConfig.IsOn("Kill")
end
function hpFraction(u)
    local max = u:GetMaxHealth()
    return max > 0 and u:GetHealth() / max or 0
end
function floorOf(bot, phase)
    local s = LaneFightConfig.Settings()
    if phase ~= "commit" then
        return s.TradeFloor
    end
    return hpFraction(bot) >= s.CommitHoldHP and s.CommitFloor or s.CommitLowFloor
end
function touch(s, key, now)
    local inst = s.instances[key]
    if inst == nil or now - inst.seen > INSTANCE_GAP then
        inst = {seen = now, started = false, gates = {}}
        s.instances[key] = inst
    end
    inst.seen = now
    return inst
end
function gate(bot, inst, reason, targetPid)
    if inst.gates[reason] == true then
        return
    end
    inst.gates[reason] = true
    local fields = {
        {
            "pid",
            bot:GetPlayerID()
        },
        {"gate", reason}
    }
    if targetPid ~= nil then
        fields[#fields + 1] = {"target", targetPid}
    end
    Telemetry.Event("lanefight_gate", fields)
end
function priorityLive(bot)
    return Intent.PriorityLive(bot) or Orders.GetFor(bot) ~= nil
end
function startBlocked(bot, commit)
    local cfg = LaneFightConfig.Settings()
    local mode = bot:GetActiveMode()
    local modeOk = false
    for ____, m in ipairs(START_MODES) do
        if m == mode then
            modeOk = true
        end
    end
    if not modeOk then
        return "mode:" .. HDebug.ModeName(mode)
    end
    if hpFraction(bot) < (commit and cfg.CommitStartHP or cfg.StartHP) then
        return "low-hp"
    end
    local retreat = Intent.Resolved(bot, BotMode.Retreat)
    if retreat ~= nil and retreat >= cfg.StartMaxRetreat then
        return "retreat"
    end
    if CampJobs.Active(bot) then
        return "camp"
    end
    if CampJobs.Covering(bot) then
        return "cover"
    end
    if priorityLive(bot) then
        return "priority"
    end
    return nil
end
function usableUnit(u)
    return u ~= nil and u ~= nil and not u:IsNull() and u:IsAlive() and u:CanBeSeen() and u:GetLocation() ~= nil
end
function memberByPid(team, pid)
    local count = #GetTeamPlayers(team)
    do
        local i = 1
        while i <= count do
            local u = GetTeamMember(i)
            if u ~= nil and u ~= nil and not u:IsNull() and u:GetPlayerID() == pid then
                return u
            end
            i = i + 1
        end
    end
    return nil
end
function isSupport(u)
    local pos = LaneConfig.PositionOf(u)
    return pos == 4 or pos == 5
end
function partnerOf(bot, snap)
    local p = LaneRoles.Partner(bot, snap)
    if p == nil or not p.alive then
        return nil
    end
    local unit = p.unit ~= nil and p.unit ~= nil and not p.unit:IsNull() and p.unit or memberByPid(
        bot:GetTeam(),
        p.pid
    )
    if not usableUnit(unit) then
        return nil
    end
    return {
        unit = unit,
        pid = p.pid,
        human = not IsPlayerBot(p.pid),
        support = isSupport(unit)
    }
end
function holdsReadyKey(u)
    do
        local i = 0
        while i < 6 do
            do
                local __continue43
                repeat
                    local a = u:GetAbilityInSlot(i)
                    if a == nil or a == nil or a:IsNull() or a:IsHidden() or a:GetLevel() < 1 then
                        __continue43 = true
                        break
                    end
                    local name = a:GetName()
                    if AbilityClasses.Classify(
                        name,
                        a:IsUltimate()
                    ) == "key" and not AbilityClasses.IsEscape(name) and a:IsFullyCastable() then
                        return true
                    end
                    __continue43 = true
                until true
                if not __continue43 then
                    break
                end
            end
            i = i + 1
        end
    end
    return false
end
function isHeroTarget(t, target, targetPid)
    if t == nil or t == nil or t:IsNull() or not t:IsHero() then
        return false
    end
    if target ~= nil and t == target then
        return true
    end
    return t:GetPlayerID() == targetPid and not t:IsIllusion()
end
function skillOf(bot)
    return Profile.Get(bot).skill
end
--- The ally's visible commit on `target`: it attacks the target while closing on it, or keeps attacking it from within
-- its attack range (IN_RANGE_ATTACKS within InRangeWindow: one harass hit is not a commit), or it is casting a
-- key-class ability or an ultimate at it. The bot API rarely exposes a cast's target, so "at it" is: facing within 30
-- degrees of the target and within the ability's cast range + 200. `prev` is the sample taken before this one.
function ____exports.IsCommitting(ally, target, prev)
    if not usableUnit(ally) or not usableUnit(target) then
        return false
    end
    local dist = GetUnitToUnitDistance(ally, target)
    if isHeroTarget(
        ally:GetAttackTarget(),
        target,
        target:GetPlayerID()
    ) then
        if dist <= ally:GetAttackRange() + RANGE_SLACK and (prev and prev.attacks or 0) >= IN_RANGE_ATTACKS then
            return true
        end
        if prev ~= nil and DotaTime() - prev.at <= PREV_MAX_AGE and dist < prev.dist - CLOSE_MIN then
            return true
        end
    end
    return castingAt(ally, target, dist)
end
function castingAt(ally, target, dist)
    if not ally:IsCastingAbility() then
        return false
    end
    local a = ally:GetCurrentActiveAbility()
    if a == nil or a == nil or a:IsNull() then
        return false
    end
    if AbilityClasses.Classify(
        a:GetName(),
        a:IsUltimate()
    ) == "other" then
        return false
    end
    if dist > a:GetCastRange() + CAST_SLACK then
        return false
    end
    if dist < 1 then
        return true
    end
    local f = ally:GetFacing() * math.pi / 180
    local from = ally:GetLocation()
    local to = target:GetLocation()
    return ((to.x - from.x) * math.cos(f) + (to.y - from.y) * math.sin(f)) / dist >= FACING_COS
end
function sampleDistance(bot, ally, target, now)
    local key = (((tostring(bot:GetPlayerID()) .. ":") .. tostring(ally:GetPlayerID())) .. ":") .. tostring(target:GetPlayerID())
    local t = tracks[key]
    if t == nil then
        t = {attackTimes = {}}
        tracks[key] = t
    end
    if t.cur ~= nil and now < t.cur.at then
        t.cur = nil
        t.attackTimes = {}
    end
    local last = ally:GetLastAttackTime()
    if t.lastAttack == nil or last < t.lastAttack then
        t.lastAttack = last
    elseif last > t.lastAttack then
        t.lastAttack = last
        if isHeroTarget(
            ally:GetAttackTarget(),
            target,
            target:GetPlayerID()
        ) then
            local ____t_attackTimes_2 = t.attackTimes
            ____t_attackTimes_2[#____t_attackTimes_2 + 1] = now
        end
    end
    local recent = {}
    local window = LaneFightConfig.Settings().InRangeWindow
    for ____, a in ipairs(t.attackTimes) do
        if now - a <= window then
            recent[#recent + 1] = a
        end
    end
    t.attackTimes = recent
    if t.cur == nil or now - t.cur.at >= SAMPLE_GAP then
        t.prev = t.cur
        t.cur = {
            dist = GetUnitToUnitDistance(ally, target),
            at = now
        }
    end
    t.cur.attacks = #recent
    if t.prev ~= nil then
        t.prev.attacks = #recent
    end
    return t.prev
end
function followable(s, ally, target, targetPid, prev)
    if s.phase == "wait_partner" and s.withPid == ally:GetPlayerID() and s.targetPid == targetPid then
        return true
    end
    if (prev and prev.attacks or 0) >= IN_RANGE_ATTACKS then
        return true
    end
    return castingAt(
        ally,
        target,
        GetUnitToUnitDistance(ally, target)
    )
end
function partnerCommitTarget(bot, s, ally, now)
    local found
    local counted = s.phase == "commit" and countsPartner(
        s,
        ally:GetPlayerID()
    )
    for ____, e in ipairs(LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )) do
        do
            local __continue76
            repeat
                if e == nil or not e.visible or not usableUnit(e.unit) then
                    __continue76 = true
                    break
                end
                local prev = sampleDistance(bot, ally, e.unit, now)
                local committing = ____exports.IsCommitting(ally, e.unit, prev)
                if found == nil and committing and followable(
                    s,
                    ally,
                    e.unit,
                    e.pid,
                    prev
                ) then
                    found = e.unit
                end
                if counted and e.pid == s.targetPid and (committing or attackingInRange(ally, e.unit)) then
                    s.partnerSeen[ally:GetPlayerID()] = now
                end
                __continue76 = true
            until true
            if not __continue76 then
                break
            end
        end
    end
    return found
end
function countsPartner(s, pid)
    for ____, u in ipairs(s.partners) do
        if not u:IsNull() and u:GetPlayerID() == pid then
            return true
        end
    end
    return false
end
function attackingInRange(ally, target)
    return isHeroTarget(
        ally:GetAttackTarget(),
        target,
        target:GetPlayerID()
    ) and GetUnitToUnitDistance(ally, target) <= ally:GetAttackRange() + RANGE_SLACK
end
function focusCap(bot)
    return floorOf(bot, "commit") / ACTIVE_BOOST - LaneFightConfig.Settings().CommitFocusMargin
end
function claim(bot, phase)
    local posted = Intent.Claim(
        bot,
        {
            source = "lanefight:" .. phase,
            tier = "FIGHT",
            mode = BotMode.TeamRoam,
            floor = floorOf(bot, phase)
        }
    )
    if not posted or phase ~= "commit" then
        return posted
    end
    local cap = focusCap(bot)
    for ____, mode in ipairs(FOCUS_MODES) do
        Intent.Claim(bot, {source = FOCUS_SOURCE, tier = "FIGHT", mode = mode, cap = cap})
    end
    if hpFraction(bot) >= LaneFightConfig.Settings().CommitHoldHP then
        Intent.Claim(bot, {source = FOCUS_SOURCE, tier = "FIGHT", mode = BotMode.Retreat, cap = cap})
    else
        Intent.Release(bot, FOCUS_SOURCE, BotMode.Retreat)
    end
    return posted
end
function believedDown(bot, target, spell, escapes, now)
    local out = {}
    local pid = bot:GetPlayerID()
    local tpid = target:GetPlayerID()
    for ____, a in ipairs(CastWatch.AbilitiesOf(target)) do
        do
            local __continue94
            repeat
                if not a.learned then
                    __continue94 = true
                    break
                end
                local wanted = spell and AbilityClasses.Classify(a.name, a.ult) == "key" or escapes and AbilityClasses.IsEscape(a.name)
                if not wanted then
                    __continue94 = true
                    break
                end
                local ready = CooldownMemory.ProbablyReady(
                    pid,
                    tpid,
                    a.name,
                    true,
                    now,
                    skillOf(bot)
                )
                if not ready then
                    out[a.name] = true
                end
                __continue94 = true
            until true
            if not __continue94 then
                break
            end
        end
    end
    return out
end
function start(bot, s, phase, target, inst, now, detail, opts)
    inst.started = true
    s.spent = {inst}
    s.tookOver = false
    s.clockAt = nil
    s.retreatSince = nil
    s.phase = phase
    s.target = target
    s.targetPid = target:GetPlayerID()
    s.lastLoc = target:GetLocation()
    s.startedAt = now
    s.hits = 0
    s.lastAttack = bot:GetLastAttackTime()
    s.fogSince = nil
    s.farSince = nil
    s.partners = opts.partners
    s.partnerSeen = {}
    s.partnerSince = opts.initiating == true and now + INITIATE_GRACE or now
    s.recheckMargin = opts.recheckMargin
    s.abort = nil
    s.countUp = false
    s.countAt = -math.huge
    s.startEnemies = 0
    local snap = LaneState.ForBot(bot)
    if phase == "commit" and snap ~= nil then
        s.startEnemies = FightRead.LaneCounts(bot, snap, COUNT_RADIUS).enemies
    end
    if phase ~= "wait_partner" then
        local abilities = believedDown(
            bot,
            target,
            opts.spell,
            phase == "commit",
            now
        )
        local old = s.bet
        if old ~= nil and not old.done and old.targetPid == s.targetPid and now - old.at <= MISTAKE_WINDOW then
            for name in pairs(abilities) do
                old.abilities[name] = true
            end
        else
            local first = next(abilities)
            s.bet = first ~= nil and ({targetPid = s.targetPid, at = now, abilities = abilities, done = false}) or nil
        end
    end
    s.offModeSince = now
    if phase ~= "wait_partner" then
        claim(bot, phase)
    end
    local fields = {
        {
            "pid",
            bot:GetPlayerID()
        },
        {"phase", phase},
        {"target", s.targetPid}
    }
    for ____, d in ipairs(detail) do
        fields[#fields + 1] = d
    end
    Telemetry.Event("lanefight_start", fields)
    if phase == "commit" then
        local margin
        local via
        for ____, ____value in ipairs(detail) do
            local k = ____value[1]
            local v = ____value[2]
            if k == "margin" then
                margin = v
            elseif k == "via" then
                via = v
            end
        end
        Telemetry.Event(
            "lanefight_commit",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"target", s.targetPid},
                {"margin", margin},
                {"role", COMMIT_ROLES[via] or via}
            }
        )
    end
    HDebug.Log(
        "lanefight",
        (((("start pid=" .. tostring(bot:GetPlayerID())) .. " phase=") .. phase) .. " target=") .. tostring(s.targetPid)
    )
end
function ____end(bot, s, reason)
    local phase = s.phase
    if phase == "idle" then
        return
    end
    Intent.ReleaseSource(bot, "lanefight:" .. phase)
    Intent.ReleaseSource(bot, FOCUS_SOURCE)
    if not s.tookOver and phase ~= "wait_partner" then
        for ____, inst in ipairs(s.spent) do
            inst.started = false
        end
    end
    s.spent = {}
    s.streak = 0
    s.streakKey = nil
    s.phase = "idle"
    s.target = nil
    s.targetPid = nil
    s.withPid = nil
    s.abort = nil
    if phase ~= "wait_partner" then
        bot:SetTarget(nil)
    end
    Telemetry.Event(
        "lanefight_end",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"phase", phase},
            {"reason", reason},
            {"hits", s.hits},
            {"took", s.tookOver and 1 or 0}
        }
    )
    HDebug.Log(
        "lanefight",
        (((("end pid=" .. tostring(bot:GetPlayerID())) .. " phase=") .. phase) .. " reason=") .. reason
    )
end
function checkMistake(bot, s, now)
    local bet = s.bet
    if bet == nil or bet.done then
        return
    end
    local seen = CastWatch.LastSeenCast(bot:GetPlayerID())
    if seen ~= nil and seen.enemyPid == bet.targetPid and seen.at >= bet.at and seen.at - bet.at <= MISTAKE_WINDOW and bet.abilities[seen.ability] == true then
        bet.done = true
        Telemetry.Event(
            "lanefight_mistake",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"kind", "bad_memory"},
                {"ability", seen.ability},
                {"target", bet.targetPid},
                {"after", seen.at - bet.at}
            }
        )
        return
    end
    if now - bet.at > MISTAKE_WINDOW + INSTANCE_GAP then
        s.bet = nil
    end
end
function partnerAbandoned(bot, s, target, now)
    local notice = LaneFightConfig.Curve(
        "AbortNotice",
        skillOf(bot)
    )
    for ____, u in ipairs(s.partners) do
        if not usableUnit(u) then
            return {ally = u, why = "gone", since = 0}
        end
        local last = math.max(
            s.partnerSince,
            s.partnerSeen[u:GetPlayerID()] or -math.huge
        )
        if target ~= nil and GetUnitToUnitDistance(u, target) > PARTNER_RANGE then
            return {ally = u, why = "far", since = now - last}
        end
        if now - last >= notice then
            return {ally = u, why = "unseen", since = now - last}
        end
    end
    return nil
end
function logAbandon(bot, s, target, a)
    local fields = {
        {
            "pid",
            bot:GetPlayerID()
        },
        {"why", a.why},
        {"since", a.since},
        {
            "mode",
            HDebug.ModeName(bot:GetActiveMode())
        }
    }
    if a.why ~= "gone" then
        local atk = a.ally:GetAttackTarget()
        local named = (atk == nil or atk == nil or atk:IsNull()) and "-" or (isHeroTarget(atk, target, s.targetPid) and "target" or atk:GetUnitName())
        __TS__ArrayPush(
            fields,
            {
                "ally",
                a.ally:GetPlayerID()
            },
            {
                "amode",
                HDebug.ModeName(a.ally:GetActiveMode())
            },
            {"atk", named},
            {
                "dist",
                GetUnitToUnitDistance(a.ally, target)
            },
            {
                "range",
                a.ally:GetAttackRange()
            },
            {
                "lastatk",
                DotaTime() - a.ally:GetLastAttackTime()
            }
        )
    end
    Telemetry.Event("lanefight_abandon", fields)
end
function abortSignal(bot, s, target, now)
    local seen = CastWatch.LastSeenCast(bot:GetPlayerID())
    if seen ~= nil and seen.enemyPid == s.targetPid and seen.at >= s.startedAt and seen.at ~= s.escapeAt and AbilityClasses.IsEscape(seen.ability) then
        s.escapeAt = seen.at
        return "escape"
    end
    if #s.partners > 0 and target ~= nil then
        local a = partnerAbandoned(bot, s, target, now)
        if a ~= nil then
            logAbandon(bot, s, target, a)
            return PARTNER_ABANDON
        end
    end
    if now - s.countAt < COUNT_EVERY then
        return nil
    end
    s.countAt = now
    local snap = LaneState.ForBot(bot)
    if snap == nil then
        return nil
    end
    local c = FightRead.LaneCounts(bot, snap, COUNT_RADIUS)
    local up = c.enemies > c.allies and c.enemies > s.startEnemies
    local rose = up and not s.countUp
    s.countUp = up
    return rose and "outnumbered" or nil
end
function abortReason(bot, s, target, now)
    if target == nil then
        for ____, u in ipairs(s.partners) do
            if not u:IsNull() then
                s.partnerSeen[u:GetPlayerID()] = now
            end
        end
    end
    if s.abort == nil then
        local why = abortSignal(bot, s, target, now)
        if why == nil then
            return nil
        end
        s.abort = {
            why = why,
            signalAt = now,
            at = now + LaneFightConfig.Curve(
                "AbortNotice",
                skillOf(bot)
            )
        }
        HDebug.Log(
            "lanefight",
            (("abort-signal pid=" .. tostring(bot:GetPlayerID())) .. " reason=") .. why
        )
    end
    local a = s.abort
    if now < a.at then
        return nil
    end
    s.abort = nil
    local abandon = a.why == PARTNER_ABANDON
    if abandon and (target == nil or partnerAbandoned(bot, s, target, now) == nil) then
        return nil
    end
    local solo = abandon or #s.partners > 0 and target ~= nil and partnerAbandoned(bot, s, target, now) ~= nil
    local partners = solo and ({}) or s.partners
    local ____temp_5
    if target ~= nil then
        ____temp_5 = KillCheck.Check(
            bot,
            partners,
            target,
            now,
            true
        )
    else
        ____temp_5 = nil
    end
    local k = ____temp_5
    local ____temp_7 = k ~= nil
    if ____temp_7 then
        local ____temp_6
        if not solo and s.recheckMargin ~= nil then
            ____temp_6 = k.margin >= s.recheckMargin
        else
            ____temp_6 = k.pass
        end
        ____temp_7 = ____temp_6
    end
    local pass = ____temp_7
    if pass and solo then
        s.partners = {}
        s.recheckMargin = nil
    end
    Telemetry.Event(
        "lanefight_recheck",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"reason", a.why},
            {"pass", pass and 1 or 0},
            {"margin", k and k.margin or 0},
            {"after", now - a.signalAt}
        }
    )
    if pass then
        return nil
    end
    Telemetry.Event(
        "lanefight_abort",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"phase", s.phase},
            {"reason", a.why}
        }
    )
    return a.why
end
function lastHits(bot, s)
    local at = bot:GetLastAttackTime()
    if at <= s.lastAttack then
        return
    end
    s.lastAttack = at
    if attackingTarget(bot, s) then
        s.hits = s.hits + 1
    end
end
function attackingTarget(bot, s)
    return isHeroTarget(
        bot:GetAttackTarget(),
        s.target,
        s.targetPid
    )
end
function targetEntry(bot, s)
    for ____, e in ipairs(LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )) do
        if e.pid == s.targetPid then
            return e
        end
    end
    return nil
end
function seenTarget(bot, s)
    local e = targetEntry(bot, s)
    local ____temp_12
    if (e and e.visible) == true then
        ____temp_12 = e.unit
    else
        ____temp_12 = nil
    end
    local u = ____temp_12
    if u == nil or u:IsNull() or not u:CanBeSeen() or u:GetLocation() == nil then
        return nil
    end
    return u
end
function endReason(bot, s, now)
    local cfg = LaneFightConfig.Settings()
    if not bot:IsAlive() then
        return "dead"
    end
    if hpFraction(bot) < cfg.StopHP then
        return "low-hp"
    end
    if s.phase == "trade" and not LaneFightConfig.IsOn("Trade") or s.phase ~= "trade" and not LaneFightConfig.IsOn("Kill") then
        return "flag-off"
    end
    if priorityLive(bot) then
        return "priority"
    end
    local target = seenTarget(bot, s)
    if target ~= nil then
        s.target = target
        s.lastLoc = target:GetLocation()
        s.fogSince = nil
        if not target:IsAlive() then
            return "target-dead"
        end
        local h = LaneConfig.Helpers()
        if target:IsIllusion() or h.IsSuspiciousIllusion ~= nil and h.IsSuspiciousIllusion(target) then
            return "illusion"
        end
        if h.CannotBeKilled ~= nil and h.CannotBeKilled(bot, target) then
            return "unkillable"
        end
        if target:IsMagicImmune() then
            return "magic_immune"
        end
        if GetUnitToUnitDistance(bot, target) > LEASH then
            s.farSince = s.farSince or now
            if now - s.farSince > END_GRACE then
                return "far"
            end
        else
            s.farSince = nil
        end
    else
        if s.targetPid == nil or not IsHeroAlive(s.targetPid) then
            return "target-dead"
        end
        s.fogSince = s.fogSince or now
        if now - s.fogSince > cfg.FogGrace then
            return "fog"
        end
    end
    if s.phase == "wait_partner" then
        if s.withPid == nil or not IsHeroAlive(s.withPid) then
            return "partner_gone"
        end
        return now - s.startedAt >= WAIT_TIMEOUT and "partner_timeout" or nil
    end
    if s.phase == "commit" then
        local abort = abortReason(bot, s, target, now)
        if abort ~= nil then
            return abort
        end
    end
    if s.phase == "trade" then
        if s.hits >= cfg.TradeHits then
            return "hits"
        end
        if s.clockAt == nil and attackingTarget(bot, s) then
            s.clockAt = now
        end
        if s.clockAt ~= nil and now - s.clockAt >= cfg.TradeDuration then
            return "duration"
        end
        if s.clockAt == nil and now - s.startedAt >= cfg.TradeDuration then
            return "reach"
        end
    elseif s.phase == "commit" and now - s.startedAt >= cfg.CommitMax then
        return "commit-max"
    end
    local retreat = Intent.Resolved(bot, BotMode.Retreat)
    if hpFraction(bot) < cfg.CommitHoldHP and retreat ~= nil and retreat >= floorOf(bot, s.phase) then
        s.retreatSince = s.retreatSince or now
        if now - s.retreatSince > END_GRACE then
            return "retreat"
        end
    else
        s.retreatSince = nil
    end
    local mode = bot:GetActiveMode()
    if mode == BotMode.TeamRoam or mode == BotMode.Attack then
        s.offModeSince = nil
        s.tookOver = true
    else
        s.offModeSince = s.offModeSince or now
        if now - s.offModeSince > MODE_GRACE then
            local reason = "mode:" .. HDebug.ModeName(mode)
            Telemetry.Event(
                "lanefight_abort",
                {
                    {
                        "pid",
                        bot:GetPlayerID()
                    },
                    {"phase", s.phase},
                    {"reason", reason}
                }
            )
            return reason
        end
    end
    return nil
end
function checkEnd(bot, s, now)
    checkMistake(bot, s, now)
    if s.phase == "idle" then
        return
    end
    lastHits(bot, s)
    local reason = endReason(bot, s, now)
    if reason ~= nil then
        ____end(bot, s, reason)
    end
end
function heroName(u)
    local h = LaneConfig.Helpers().HeroDisplayName
    local ____temp_13
    if h ~= nil then
        ____temp_13 = h(u)
    else
        ____temp_13 = nil
    end
    local name = ____temp_13
    return name or (string.gsub(
        u:GetUnitName(),
        "npc_dota_hero_",
        ""
    ))
end
function callKill(bot, s, target, now)
    if not LaneFightConfig.IsOn("CallKills") then
        return
    end
    local cd = LaneFightConfig.Settings().CallCooldown
    if s.lastCallAt ~= nil and now >= s.lastCallAt and now - s.lastCallAt < cd then
        return
    end
    s.lastCallAt = now
    local said = Orders.Say(
        bot,
        "say_lanefight_go",
        cd,
        {heroName(target)}
    )
    local pinged = Orders.Ping(
        bot,
        target:GetLocation()
    )
    Telemetry.Event(
        "lanefight_call",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {
                "target",
                target:GetPlayerID()
            },
            {"said", said and 1 or 0},
            {"pinged", pinged and 1 or 0}
        }
    )
end
function planKill(bot, p, target, now)
    if p ~= nil and p.human then
        local partners = {p.unit}
        local k = KillCheck.Check(bot, partners, target, now)
        if k == nil or not k.pass then
            return {action = "none", k = k, partners = partners, via = "call"}
        end
        if skillOf(bot) > LaneFightConfig.Settings().SoloSkill then
            local solo = KillCheck.Check(bot, {}, target, now)
            if solo ~= nil and solo.pass and solo.overwhelming then
                return {action = "commit", k = solo, partners = {}, via = "solo"}
            end
        end
        return {action = "wait", k = k, partners = partners, via = "call"}
    end
    local support = isSupport(bot)
    if support and holdsReadyKey(bot) then
        local partners = p ~= nil and ({p.unit}) or ({})
        local k = KillCheck.Check(bot, partners, target, now)
        return {action = k ~= nil and k.pass and "commit" or "none", k = k, partners = partners, via = "initiate"}
    end
    if p ~= nil and p.support and holdsReadyKey(p.unit) then
        local partners = {p.unit}
        local k = KillCheck.Check(bot, partners, target, now)
        return {action = k ~= nil and k.pass and "wait" or "none", k = k, partners = partners, via = "partner"}
    end
    if support and p ~= nil and not p.support then
        return {
            action = "none",
            k = KillCheck.Check(bot, {p.unit}, target, now),
            partners = {p.unit},
            via = "follow"
        }
    end
    local k = KillCheck.Check(bot, {}, target, now)
    return {action = k ~= nil and k.pass and "commit" or "none", k = k, partners = {}, via = "solo"}
end
function visibleEnemy(bot, pid)
    for ____, e in ipairs(LaneState.Enemies(
        bot,
        bot:GetAssignedLane()
    )) do
        if e ~= nil and e.pid == pid and e.visible and usableUnit(e.unit) then
            return e.unit
        end
    end
    return nil
end
function coordinate(bot, s, snap, now)
    if s.phase == "wait_partner" then
        Intent.Hold(bot, WAIT_HOLD)
    end
    checkMistake(bot, s, now)
    local ____LaneFightConfig_IsOn_result_14
    if LaneFightConfig.IsOn("Kill") then
        ____LaneFightConfig_IsOn_result_14 = partnerOf(bot, snap)
    else
        ____LaneFightConfig_IsOn_result_14 = nil
    end
    local p = ____LaneFightConfig_IsOn_result_14
    if p == nil then
        s.follow = nil
        return
    end
    local seen = partnerCommitTarget(bot, s, p.unit, now)
    if seen ~= nil then
        local tpid = seen:GetPlayerID()
        local inst = touch(
            s,
            (("follow:" .. tostring(p.pid)) .. ":") .. tostring(tpid),
            now
        )
        if not inst.started and (s.follow == nil or s.follow.targetPid ~= tpid or s.follow.allyPid ~= p.pid) then
            local delay = Profile.SampleDelay(bot, "react") + LaneFightConfig.Curve(
                "SyncDelay",
                skillOf(bot)
            )
            s.follow = {
                allyPid = p.pid,
                targetPid = tpid,
                seenAt = now,
                lastSeen = now,
                at = now + delay,
                delay = delay,
                inst = inst
            }
            HDebug.Log(
                "lanefight",
                (((((("partner-commit pid=" .. tostring(bot:GetPlayerID())) .. " ally=") .. tostring(p.pid)) .. " target=") .. tostring(tpid)) .. " follow-in=") .. tostring(delay)
            )
        end
        if s.follow ~= nil and s.follow.targetPid == tpid and s.follow.allyPid == p.pid then
            s.follow.lastSeen = now
        end
    end
    local f = s.follow
    if f == nil then
        return
    end
    if f.allyPid ~= p.pid then
        s.follow = nil
        return
    end
    if now > f.at + INSTANCE_GAP then
        if now - f.lastSeen > FOLLOW_FRESH then
            gate(bot, f.inst, "partner_backed_off")
        end
        s.follow = nil
        return
    end
    if now < f.at then
        return
    end
    if now - f.lastSeen > FOLLOW_FRESH then
        return
    end
    if s.phase == "commit" then
        f.inst.started = true
        s.follow = nil
        return
    end
    local target = visibleEnemy(bot, f.targetPid)
    if target == nil then
        return
    end
    local k = KillCheck.Check(bot, {p.unit}, target, now)
    if k == nil or k.margin < LaneFightConfig.Settings().FollowMargin then
        gate(bot, f.inst, "follow-margin")
        return
    end
    local blocked = startBlocked(bot, true)
    if blocked ~= nil then
        gate(bot, f.inst, blocked)
        return
    end
    s.follow = nil
    if s.phase ~= "idle" then
        ____end(bot, s, "commit")
    end
    local read = FightRead.ReadFor(bot, now)
    local spell = read.window == "spell" and read.target ~= nil and read.target:GetPlayerID() == f.targetPid
    start(
        bot,
        s,
        "commit",
        target,
        f.inst,
        now,
        {{"margin", k.margin}, {"via", "follow"}, {"with", p.pid}, {"sync", f.delay}},
        {
            partners = {p.unit},
            spell = spell,
            recheckMargin = LaneFightConfig.Settings().FollowMargin
        }
    )
end
function considerKill(bot, s, snap, read, target, windowKey, now)
    local tpid = target:GetPlayerID()
    local p = partnerOf(bot, snap)
    local plan = planKill(bot, p, target, now)
    local ____s_18 = s
    local ____opt_16 = plan.k
    ____s_18.lastMargin = ____opt_16 and ____opt_16.margin
    if plan.action == "none" then
        s.killSince = nil
        local k = plan.k
        if k ~= nil and not k.pass and k.margin >= NEAR_MISS and k.reason ~= nil and s.phase ~= "commit" then
            local miss = touch(
                s,
                "killfail:" .. tostring(tpid),
                now
            )
            local logged = next(miss.gates)
            if logged == nil then
                gate(bot, miss, "kill:" .. k.reason, tpid)
            end
        end
        return
    end
    if s.killSince == nil or s.killPid ~= tpid then
        s.killSince = now
        s.killPid = tpid
        s.killDelay = Profile.SampleDelay(bot, "react")
    end
    local inst = touch(
        s,
        "kill:" .. tostring(tpid),
        now
    )
    local ready = now - s.killSince >= s.killDelay and not inst.started and s.phase ~= "commit" and (plan.action == "commit" or s.phase == "idle")
    if not ready then
        return
    end
    local blocked = startBlocked(bot, true)
    if blocked ~= nil then
        gate(bot, inst, blocked)
    elseif plan.action == "commit" then
        if s.phase ~= "idle" then
            ____end(bot, s, "commit")
        end
        start(
            bot,
            s,
            "commit",
            target,
            inst,
            now,
            {{"margin", plan.k.margin}, {"via", plan.via}},
            {partners = plan.partners, spell = read.window == "spell", initiating = plan.via == "initiate"}
        )
        if windowKey ~= nil then
            local w = touch(s, windowKey, now)
            w.started = true
            local ____s_spent_19 = s.spent
            ____s_spent_19[#____s_spent_19 + 1] = w
        end
    elseif p ~= nil then
        if p.human then
            callKill(bot, s, target, now)
        end
        s.withPid = p.pid
        start(
            bot,
            s,
            "wait_partner",
            target,
            inst,
            now,
            {{"margin", plan.k.margin}, {"with", p.pid}, {"human", p.human and 1 or 0}},
            {partners = plan.partners, spell = false}
        )
    end
end
____exports.Config = LaneFightConfig
____exports.AbilityClasses = AbilityClasses
____exports.CooldownMemory = CooldownMemory
____exports.CastWatch = CastWatch
____exports.FightRead = FightRead
____exports.KillCheck = KillCheck
function ____exports.IsActive()
    return LaneFightConfig.IsActive()
end
function ____exports.Tick(bot)
    if not LaneFightConfig.IsActive() or not LaneFightConfig.AppliesTo(bot) or not LaneConfig.InLaningPhase() then
        return
    end
    if not LaneFightConfig.IsOn("Memory") and not gatesOpen(bot) then
        return
    end
    local snap = LaneState.ForBot(bot)
    if snap == nil then
        return
    end
    if LaneFightConfig.IsOn("Memory") then
        CastWatch.Tick(bot)
    end
    local now = DotaTime()
    if now < 0 or not gatesOpen(bot) then
        return
    end
    local s = stateFor(bot)
    coordinate(bot, s, snap, now)
    checkEnd(bot, s, now)
end
--- The fight read for `bot`; callers act on it. Guarded in index.ts: an error reads as no window.
function ____exports.ReadFor(bot, now)
    return FightRead.ReadFor(bot, now)
end
--- The kill check on `target` with `partners`; guarded in index.ts: an error reads as no check.
function ____exports.CheckKill(bot, partners, target, now)
    return KillCheck.Check(bot, partners, target, now)
end
INSTANCE_GAP = 1
END_GRACE = 0.5
MODE_GRACE = 1
LEASH = 1800
RANGE_SLACK = 50
local TRADE_REACH = 400
ACTIVE_BOOST = 1.1
WAIT_TIMEOUT = 3
WAIT_HOLD = "lanefight:wait"
MISTAKE_WINDOW = 2
FACING_COS = math.cos(math.pi / 6)
CAST_SLACK = 200
CLOSE_MIN = 1
PREV_MAX_AGE = 0.5
SAMPLE_GAP = 0.02
COUNT_EVERY = 0.1
COUNT_RADIUS = 1200
IN_RANGE_ATTACKS = 2
FOLLOW_FRESH = 0.3
PARTNER_RANGE = 1200
INITIATE_GRACE = 1.5
NEAR_MISS = 0.8
FOCUS_SOURCE = "lanefight:commit_focus"
PARTNER_ABANDON = "partner_abandon"
COMMIT_ROLES = {initiate = "initiator", follow = "follower", solo = "solo"}
FOCUS_MODES = {
    BotMode.Laning,
    BotMode.Farm,
    BotMode.Attack,
    BotMode.Ward,
    BotMode.Rune,
    BotMode.SecretShop,
    BotMode.SideShop,
    BotMode.Roam
}
START_MODES = {BotMode.Laning, BotMode.TeamRoam, BotMode.Attack}
fights = {}
tracks = {}
--- Laning's desire this round, with the engine's x1.1 when it is the active mode, at or above the trade floor.
local function laningOutbids(bot)
    local laning = Intent.Resolved(bot, BotMode.Laning)
    if laning == nil then
        return false
    end
    local boost = bot:GetActiveMode() == BotMode.Laning and ACTIVE_BOOST or 1
    return laning * boost >= LaneFightConfig.Settings().TradeFloor
end
--- Reads the fight and starts a trade or commit, or upgrades a trade to a commit, when the gates allow. Respect blocks
-- trades only: from level 6 an ult never seen cast reads as ready, so it would block every kill; the kill check's own
-- escape, tower, outnumbered and counter rules decide kills.
local function considerStart(bot, s, snap, now)
    local read = FightRead.ReadFor(bot, now)
    local fresh = read ~= s.lastRead
    s.lastRead = read
    s.lastWindow = read.window
    local target = read.target
    if target == nil then
        s.streak = 0
        s.streakKey = nil
        s.killSince = nil
        return
    end
    local tpid = target:GetPlayerID()
    local windowKey = read.respect == nil and read.window ~= nil and read.noticed and (("trade:" .. read.window) .. ":") .. tostring(tpid) or nil
    if fresh then
        s.streak = windowKey ~= nil and windowKey == s.streakKey and s.streak + 1 or (windowKey ~= nil and 1 or 0)
        s.streakKey = windowKey
    end
    if LaneFightConfig.IsOn("Kill") then
        considerKill(
            bot,
            s,
            snap,
            read,
            target,
            windowKey,
            now
        )
    end
    if read.respect ~= nil then
        if s.phase == "idle" then
            gate(
                bot,
                touch(
                    s,
                    (("respect:" .. read.respect) .. ":") .. tostring(tpid),
                    now
                ),
                "respect:" .. read.respect
            )
        end
        return
    end
    if windowKey == nil or not LaneFightConfig.IsOn("Trade") then
        return
    end
    local inst = touch(s, windowKey, now)
    if s.phase ~= "idle" or inst.started or s.streak < 2 then
        return
    end
    local blocked = startBlocked(bot, false)
    local ____temp_15
    if blocked == nil then
        ____temp_15 = visibleEnemy(bot, tpid)
    else
        ____temp_15 = nil
    end
    local seen = ____temp_15
    if blocked == nil and seen == nil then
        blocked = "unseen"
    end
    if blocked == nil and GetUnitToUnitDistance(bot, seen) > bot:GetAttackRange() + TRADE_REACH then
        blocked = "range"
    end
    if blocked == nil and laningOutbids(bot) then
        blocked = "laning"
    end
    if blocked ~= nil then
        gate(bot, inst, blocked)
    else
        start(
            bot,
            s,
            "trade",
            seen,
            inst,
            now,
            {{"window", read.window}},
            {partners = {}, spell = read.window == "spell"}
        )
    end
end
--- mode_team_roam_generic GetDesire, after CapForLanePush. While a trade or commit runs it posts the FIGHT floor on
-- team_roam and returns `raw`; the claim lifts it in Intent.Resolve. Without intent it returns max(raw, floor).
-- `avoiding` is team_roam's IsAvoidingAbilityZone: its escape runs instead of the fight, so the phase ends.
function ____exports.RoamDesire(bot, raw, avoiding)
    if type(raw) ~= "number" then
        return raw
    end
    local s = fights[bot:GetPlayerID()]
    if not gatesOpen(bot) then
        if s ~= nil then
            ____end(bot, s, "off")
        end
        return raw
    end
    if avoiding == true then
        if s ~= nil then
            ____end(bot, s, "avoid")
        end
        return raw
    end
    local snap = LaneState.ForBot(bot)
    if snap == nil or DotaTime() < 0 then
        if s ~= nil then
            ____end(bot, s, "off")
        end
        return raw
    end
    local st = s or stateFor(bot)
    local now = DotaTime()
    checkEnd(bot, st, now)
    coordinate(bot, st, snap, now)
    considerStart(bot, st, snap, now)
    if st.phase ~= "trade" and st.phase ~= "commit" then
        return raw
    end
    if claim(bot, st.phase) then
        return raw
    end
    return math.max(
        raw,
        floorOf(bot, st.phase)
    )
end
--- mode_team_roam_generic Think, right after ItemOpsThink and before its last-hit branch: true when the fight owns
-- this frame (the bot attacks its target, or walks to it or to where it was last seen).
function ____exports.Think(bot)
    local s = fights[bot:GetPlayerID()]
    if s == nil or s.phase == "idle" then
        return false
    end
    if not gatesOpen(bot) then
        ____end(bot, s, "off")
        return false
    end
    checkEnd(
        bot,
        s,
        DotaTime()
    )
    if s.phase ~= "trade" and s.phase ~= "commit" then
        return false
    end
    local target = seenTarget(bot, s)
    if target == nil then
        if s.lastLoc == nil then
            return false
        end
        claim(bot, s.phase)
        bot:Action_MoveToLocation(s.lastLoc)
        return true
    end
    claim(bot, s.phase)
    bot:SetTarget(target)
    if GetUnitToUnitDistance(bot, target) <= bot:GetAttackRange() + RANGE_SLACK then
        if s.clockAt == nil then
            s.clockAt = DotaTime()
        end
        bot:Action_AttackUnit(target, false)
    elseif s.phase == "commit" then
        bot:Action_AttackUnit(target, false)
    else
        bot:Action_MoveToLocation(target:GetLocation())
    end
    return true
end
--- The trade or commit target, while one runs.
function ____exports.Target(bot)
    local s = fights[bot:GetPlayerID()]
    local ____temp_20
    if s ~= nil and (s.phase == "trade" or s.phase == "commit") then
        ____temp_20 = s.target
    else
        ____temp_20 = nil
    end
    return ____temp_20
end
function ____exports.CurrentPhase(bot)
    local ____opt_21 = fights[bot:GetPlayerID()]
    return ____opt_21 and ____opt_21.phase or "idle"
end
--- "window=<type|none> kill=<margin|-> mem=<n> phase=<p>": the overlay's `fight` line.
function ____exports.Describe(bot)
    local s = fights[bot:GetPlayerID()]
    local margin = (s and s.lastMargin) ~= nil and string.format("%.2f", s.lastMargin) or "-"
    return (((((("window=" .. (s and s.lastWindow or "none")) .. " kill=") .. margin) .. " mem=") .. tostring(CooldownMemory.Count(
        bot:GetPlayerID(),
        DotaTime()
    ))) .. " phase=") .. (s and s.phase or "idle")
end
function ____exports.RegisterProbes()
    LaneHooks.SetFightProbe(function(bot) return LaneFightConfig.IsActive() and ____exports.CurrentPhase(bot) == "commit" end)
end
____exports.RegisterProbes()
return ____exports
