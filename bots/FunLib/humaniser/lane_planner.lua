--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Lane = ____dota.Lane
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneHooks = require(GetScriptDirectory().."/FunLib/humaniser/lane_hooks")
local Camps = require(GetScriptDirectory().."/FunLib/humaniser/camps")
local LaneState = require(GetScriptDirectory().."/FunLib/humaniser/lane_state")
local LaneRoles = require(GetScriptDirectory().."/FunLib/humaniser/lane_roles")
local LanePlan = require(GetScriptDirectory().."/FunLib/humaniser/lane_plan")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
function ____exports.Describe(c)
    return ((("tech=" .. c.tech) .. " (") .. c.reason) .. ")"
end
local cycles = {}
local current = {}
local inputs = {}
function ____exports.ResetCache()
    cycles = {}
    current = {}
    inputs = {}
end
local function pick(tech, reason)
    return {tech = tech, reason = reason}
end
function ____exports.Choose(i)
    local cfg = LaneConfig.Settings()
    local bands = cfg.Planner
    local function knows(tech)
        return LaneConfig.Knows(tech, i.skill)
    end
    local plan = i.plan
    local supportish = i.role == "support"
    if plan.handsOff then
        return pick("none", "handsoff")
    end
    if i.dotaTime >= 0 and i.dotaTime < cfg.Timing.BlockEnd and knows("block") then
        if i.role ~= "core" or not i.humanCoreInLane then
            return pick("block", "0:00 block")
        end
    end
    if i.override ~= nil and knows(i.override) then
        return pick(i.override, "counter: " .. i.override)
    end
    if i.rotationPlanned and plan.plan ~= "FREEZE" and knows("shove") then
        return pick("shove", "shove before rotating")
    end
    if plan.plan == "SHOVE" then
        return knows("shove") and pick("shove", "plan shove") or pick("none", "plan shove: unknown")
    end
    if i.coverAbsentCore and supportish then
        if knows("freeze") then
            return pick("freeze", "cover core: freeze")
        end
        if knows("aggro_pull") and i.laneScore <= bands.AggroCorrectBelow then
            return pick("aggro_pull", "cover core: aggro")
        end
        return pick("hold", "cover core: hold")
    end
    local campOk = i.pullCamp and plan.pullAllowed and i.mayRunCampJob and i.partnerSafe
    if plan.plan == "FREEZE" then
        if i.laneScore <= bands.SmallDriftBelow and i.allyCreeps >= i.enemyCreeps + bands.LargeWaveMargin and campOk and knows("half_pull") then
            return pick("half_pull", "freeze: thin large wave")
        end
        if not supportish and i.eqPos > i.desiredEq + cfg.Thresholds.FreezeDriftMargin and knows("aggro_pull") then
            return pick("aggro_pull", "freeze: drag back")
        end
        return knows("freeze") and pick("freeze", "plan freeze") or pick("hold", "plan freeze: hold")
    end
    if i.isMid and i.eqPos >= cfg.Thresholds.MidTowerEq and knows("aggro_pull") then
        return pick("aggro_pull", "mid: out of tower range")
    end
    local score = i.forecastScore or i.laneScore
    if not i.isMid or i.pullCamp then
        if (score <= bands.FullPullBelow or plan.pullForced) and campOk then
            if i.stackedPullCamp and knows("stack_pull") and i.enemyLaners > 0 then
                return pick("stack_pull", "deny: stacked camp")
            end
            if knows("full_pull") then
                return pick("full_pull", plan.pullForced and "pull ordered" or "wave pushed out")
            end
        end
        if score <= bands.SmallDriftBelow and campOk and knows("half_pull") then
            return pick("half_pull", "small drift")
        end
    end
    if score <= bands.AggroCorrectBelow and knows("aggro_pull") then
        return pick("aggro_pull", "small correction")
    end
    return pick("none", "lane fine")
end
local function cycleIndex(time)
    return math.floor(time / LaneConfig.Settings().Timing.WaveCycle)
end
local function stateFor(pid, now)
    local idx = cycleIndex(now)
    local c = cycles[pid]
    if c == nil or c.cycle ~= idx then
        c = {cycle = idx, rolls = {}}
        cycles[pid] = c
    end
    return c
end
--- A dead core makes RoleIn report the support as solo; the support keeps its role while covering.
local function roleOf(bot, s)
    local role = LaneRoles.RoleIn(bot, s)
    if role ~= "solo" or not LaneRoles.CoreAbsent(s) then
        return role
    end
    local pos = LaneConfig.PositionOf(bot)
    return pos ~= nil and pos >= 4 and "support" or role
end
local function humanCoreIn(bot, s)
    local pid = bot:GetPlayerID()
    for ____, h in ipairs(s.allies) do
        do
            local __continue31
            repeat
                if h.pid == pid or h.isBot or not h.alive or not h.assigned then
                    __continue31 = true
                    break
                end
                if h.position ~= nil and h.position >= 1 and h.position <= 3 then
                    return true
                end
                __continue31 = true
            until true
            if not __continue31 then
                break
            end
        end
    end
    return false
end
local function buildInput(bot, s, now)
    local role = roleOf(bot, s)
    local enemies = LaneState.Enemies(bot, s.lane)
    local camps = Camps.PullCampsFor(s.team, s.lane)
    local stacked = false
    for ____, job in ipairs(camps) do
        if LaneHooks.IsStacked(job.campIdx) then
            stacked = true
        end
    end
    local plan = role == "support" and LanePlan.ForSupport(bot, s) or LanePlan.View(bot, s)
    local view = LaneState.ScoreFor(bot, s)
    return {
        skill = LaneConfig.SkillOf(bot),
        role = role,
        isMid = s.lane == Lane.Mid,
        now = now,
        dotaTime = now,
        plan = plan,
        laneScore = view.laneScore,
        forecastScore = view.forecastScore,
        eqPos = s.eqPos,
        allyCreeps = s.ally.count,
        enemyCreeps = s.enemy.count,
        enemyLaners = LanePlan.EnemyLaners(bot, s),
        pullCamp = #camps > 0,
        stackedPullCamp = stacked,
        mayRunCampJob = (LaneRoles.MayRunCampJob(bot, s, enemies)),
        partnerSafe = LaneRoles.PartnerSafe(bot, s, enemies),
        coverAbsentCore = role == "support" and LaneRoles.CoverAbsentCore(bot, s, now),
        rotationPlanned = LaneHooks.IsRotationPlanned(bot),
        humanCoreInLane = humanCoreIn(bot, s),
        desiredEq = s.desiredEq,
        override = LaneHooks.TechniqueOverride(bot)
    }
end
local ORDERED_BY_PULL = {full_pull = true, stack_pull = true, half_pull = true}
local function gate(bot, i, choice)
    local tech = choice.tech
    if tech == "none" or tech == "hold" then
        return choice
    end
    local c = stateFor(
        bot:GetPlayerID(),
        i.now
    )
    if c.committed ~= nil then
        return c.committed == tech and choice or pick("none", ("one per cycle (" .. c.committed) .. ")")
    end
    if ORDERED_BY_PULL[tech] == true and i.plan.pullForced then
        return choice
    end
    if tech == "stack_pull" and i.plan.stackRequested then
        return choice
    end
    local ok = c.rolls[tech]
    if ok == nil then
        ok = LaneConfig.Roll(LaneConfig.Curve("AttemptRate", i.skill))
        c.rolls[tech] = ok
    end
    return ok and choice or pick("none", "skip: attempt-roll " .. tech)
end
function ____exports.Plan(bot, s)
    if not LaneConfig.IsActive() then
        return pick("none", "lane off")
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local input = buildInput(bot, s, now)
    local result = gate(
        bot,
        input,
        ____exports.Choose(input)
    )
    local prev = current[pid]
    if prev == nil or prev.tech ~= result.tech then
        LaneRoles.ClearNeed(bot)
        if result.tech == "aggro_pull" then
            LaneRoles.NoteNeed(bot, now)
        end
    end
    current[pid] = result
    inputs[pid] = input
    HDebug.Text(
        bot,
        "lane_tech",
        ____exports.Describe(result)
    )
    return result
end
function ____exports.Current(bot)
    return current[bot:GetPlayerID()]
end
--- The inputs of the bot's latest Plan call, for telemetry.
function ____exports.LastInput(bot)
    return inputs[bot:GetPlayerID()]
end
function ____exports.Commit(bot, tech)
    stateFor(
        bot:GetPlayerID(),
        DotaTime()
    ).committed = tech
end
--- Frees the cycle's technique when the job that committed it ended without acting.
function ____exports.Release(bot, tech)
    local c = stateFor(
        bot:GetPlayerID(),
        DotaTime()
    )
    if c.committed == tech then
        c.committed = nil
    end
end
function ____exports.Committed(bot)
    return stateFor(
        bot:GetPlayerID(),
        DotaTime()
    ).committed
end
return ____exports
