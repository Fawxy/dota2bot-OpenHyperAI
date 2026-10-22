--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
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
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
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
    if LaneFightConfig.IsOn("Memory") and LaneState.ForBot(bot) ~= nil then
        CastWatch.Tick(bot)
    end
end
--- The fight read for `bot`; callers act on it. Guarded in index.ts: an error reads as no window.
function ____exports.ReadFor(bot, now)
    return FightRead.ReadFor(bot, now)
end
--- The kill check on `target` with `partners`; guarded in index.ts: an error reads as no check.
function ____exports.CheckKill(bot, partners, target, now)
    return KillCheck.Check(bot, partners, target, now)
end
local INSTANCE_GAP = 1
local END_GRACE = 0.5
local MODE_GRACE = 1
local LEASH = 1800
local RANGE_SLACK = 50
local fights = {}
local function stateFor(bot)
    local pid = bot:GetPlayerID()
    local s = fights[pid]
    if s == nil then
        s = {
            phase = "idle",
            startedAt = 0,
            hits = 0,
            lastAttack = 0,
            streak = 0,
            killDelay = 0,
            instances = {}
        }
        fights[pid] = s
    end
    return s
end
local function gatesOpen(bot)
    if not LaneFightConfig.IsActive() or not LaneFightConfig.AppliesTo(bot) or not LaneConfig.InLaningPhase() then
        return false
    end
    return LaneFightConfig.IsOn("Trade") or LaneFightConfig.IsOn("Kill")
end
local function hpFraction(u)
    local max = u:GetMaxHealth()
    return max > 0 and u:GetHealth() / max or 0
end
local function floorOf(phase)
    local s = LaneFightConfig.Settings()
    return phase == "commit" and s.CommitFloor or s.TradeFloor
end
local function touch(s, key, now)
    local inst = s.instances[key]
    if inst == nil or now - inst.seen > INSTANCE_GAP then
        inst = {seen = now, started = false, gates = {}}
        s.instances[key] = inst
    end
    inst.seen = now
    return inst
end
local function gate(bot, inst, reason)
    if inst.gates[reason] == true then
        return
    end
    inst.gates[reason] = true
    Telemetry.Event(
        "lanefight_gate",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"gate", reason}
        }
    )
end
local function priorityLive(bot)
    return Intent.PriorityLive(bot) or Orders.GetFor(bot) ~= nil
end
--- Why a trade or commit must not start now, else undefined.
local function startBlocked(bot)
    local cfg = LaneFightConfig.Settings()
    if hpFraction(bot) < cfg.StartHP then
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
local function partnerUnits(bot, snap)
    local partner = LaneRoles.Partner(bot, snap)
    return partner ~= nil and partner.unit ~= nil and not partner.unit:IsNull() and ({partner.unit}) or ({})
end
local function claim(bot, phase)
    return Intent.Claim(
        bot,
        {
            source = "lanefight:" .. phase,
            tier = "FIGHT",
            mode = BotMode.TeamRoam,
            floor = floorOf(phase)
        }
    )
end
local function start(bot, s, phase, target, inst, now, detail)
    inst.started = true
    s.phase = phase
    s.target = target
    s.targetPid = target:GetPlayerID()
    s.lastLoc = target:GetLocation()
    s.startedAt = now
    s.hits = 0
    s.lastAttack = bot:GetLastAttackTime()
    s.fogSince = nil
    s.farSince = nil
    s.offModeSince = now
    claim(bot, phase)
    Telemetry.Event(
        "lanefight_start",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"phase", phase},
            {"target", s.targetPid},
            detail
        }
    )
    HDebug.Log(
        "lanefight",
        (((("start pid=" .. tostring(bot:GetPlayerID())) .. " phase=") .. phase) .. " target=") .. tostring(s.targetPid)
    )
end
local function ____end(bot, s, reason)
    local phase = s.phase
    if phase == "idle" then
        return
    end
    Intent.ReleaseSource(bot, "lanefight:" .. phase)
    s.phase = "idle"
    s.target = nil
    s.targetPid = nil
    bot:SetTarget(nil)
    Telemetry.Event(
        "lanefight_end",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"phase", phase},
            {"reason", reason}
        }
    )
    HDebug.Log(
        "lanefight",
        (((("end pid=" .. tostring(bot:GetPlayerID())) .. " phase=") .. phase) .. " reason=") .. reason
    )
end
local function lastHits(bot, s)
    local at = bot:GetLastAttackTime()
    if at <= s.lastAttack then
        return
    end
    s.lastAttack = at
    local t = bot:GetAttackTarget()
    if t ~= nil and not t:IsNull() and t:IsHero() and t:GetPlayerID() == s.targetPid then
        s.hits = s.hits + 1
    end
end
--- The lane-enemy entry for the target, from the perception-filtered cached list.
local function targetEntry(bot, s)
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
local function seenTarget(bot, s)
    local e = targetEntry(bot, s)
    local ____temp_2
    if (e and e.visible) == true then
        ____temp_2 = e.unit
    else
        ____temp_2 = nil
    end
    local u = ____temp_2
    if u == nil or u:IsNull() or not u:CanBeSeen() or u:GetLocation() == nil then
        return nil
    end
    return u
end
--- Why the running phase must end now, else undefined.
local function endReason(bot, s, now)
    local cfg = LaneFightConfig.Settings()
    if not bot:IsAlive() then
        return "dead"
    end
    if hpFraction(bot) < cfg.StopHP then
        return "low-hp"
    end
    if s.phase == "trade" and not LaneFightConfig.IsOn("Trade") or s.phase == "commit" and not LaneFightConfig.IsOn("Kill") then
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
    if s.phase == "trade" then
        if s.hits >= cfg.TradeHits then
            return "hits"
        end
        if now - s.startedAt >= cfg.TradeDuration then
            return "duration"
        end
    elseif s.phase == "commit" and now - s.startedAt >= cfg.CommitMax then
        return "commit-max"
    end
    local mode = bot:GetActiveMode()
    if mode == BotMode.TeamRoam or mode == BotMode.Attack then
        s.offModeSince = nil
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
local function checkEnd(bot, s, now)
    if s.phase == "idle" then
        return
    end
    lastHits(bot, s)
    local reason = endReason(bot, s, now)
    if reason ~= nil then
        ____end(bot, s, reason)
    end
end
--- Reads the fight and starts a trade or commit, or upgrades a trade to a commit, when the gates allow.
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
    if read.respect ~= nil then
        s.streak = 0
        s.streakKey = nil
        s.killSince = nil
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
    local windowKey = read.window ~= nil and read.noticed and (("trade:" .. read.window) .. ":") .. tostring(tpid) or nil
    if fresh then
        s.streak = windowKey ~= nil and windowKey == s.streakKey and s.streak + 1 or (windowKey ~= nil and 1 or 0)
        s.streakKey = windowKey
    end
    local commitReady = false
    if LaneFightConfig.IsOn("Kill") then
        local k = KillCheck.Check(
            bot,
            partnerUnits(bot, snap),
            target,
            now
        )
        s.lastMargin = k and k.margin
        if k ~= nil and k.pass then
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
            commitReady = now - s.killSince >= s.killDelay and not inst.started
            if commitReady and s.phase ~= "commit" then
                local blocked = startBlocked(bot)
                if blocked ~= nil then
                    gate(bot, inst, blocked)
                else
                    if s.phase == "trade" then
                        ____end(bot, s, "commit")
                    end
                    start(
                        bot,
                        s,
                        "commit",
                        target,
                        inst,
                        now,
                        {"margin", k.margin}
                    )
                    if windowKey ~= nil then
                        touch(s, windowKey, now).started = true
                    end
                end
            end
        else
            s.killSince = nil
        end
    end
    if windowKey == nil or not LaneFightConfig.IsOn("Trade") then
        return
    end
    local inst = touch(s, windowKey, now)
    if s.phase ~= "idle" or inst.started or s.streak < 2 then
        return
    end
    local blocked = startBlocked(bot)
    if blocked ~= nil then
        gate(bot, inst, blocked)
    else
        start(
            bot,
            s,
            "trade",
            target,
            inst,
            now,
            {"window", read.window}
        )
    end
end
--- mode_team_roam_generic GetDesire, after CapForLanePush. While a trade or commit runs it posts the FIGHT floor on
-- team_roam and returns `raw`; the claim lifts it in Intent.Resolve. Without intent it returns max(raw, floor).
function ____exports.RoamDesire(bot, raw)
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
    considerStart(bot, st, snap, now)
    if st.phase ~= "trade" and st.phase ~= "commit" then
        return raw
    end
    if claim(bot, st.phase) then
        return raw
    end
    return math.max(
        raw,
        floorOf(st.phase)
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
        bot:Action_AttackUnit(target, false)
    else
        bot:Action_MoveToLocation(target:GetLocation())
    end
    return true
end
--- The trade or commit target, while one runs.
function ____exports.Target(bot)
    local s = fights[bot:GetPlayerID()]
    local ____temp_5
    if s ~= nil and (s.phase == "trade" or s.phase == "commit") then
        ____temp_5 = s.target
    else
        ____temp_5 = nil
    end
    return ____temp_5
end
function ____exports.CurrentPhase(bot)
    local ____opt_6 = fights[bot:GetPlayerID()]
    return ____opt_6 and ____opt_6.phase or "idle"
end
--- "fight: window=<type|none> kill=<margin|-> mem=<n> phase=<p>" for the overlay.
function ____exports.Describe(bot)
    local s = fights[bot:GetPlayerID()]
    local margin = (s and s.lastMargin) ~= nil and string.format("%.2f", s.lastMargin) or "-"
    return (((((("fight: window=" .. (s and s.lastWindow or "none")) .. " kill=") .. margin) .. " mem=") .. tostring(CooldownMemory.Count(
        bot:GetPlayerID(),
        DotaTime()
    ))) .. " phase=") .. (s and s.phase or "idle")
end
return ____exports
