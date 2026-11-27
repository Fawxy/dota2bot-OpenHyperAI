--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local JobVerbs = require(GetScriptDirectory().."/FunLib/humaniser/job_verbs")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local LaneOffers = require(GetScriptDirectory().."/FunLib/humaniser/lane_offers")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local TripTable = require(GetScriptDirectory().."/FunLib/humaniser/states/trip_table")
local Utils = require(GetScriptDirectory().."/FunLib/utils")
local attempted = false
local lib
function ____exports.Enabled()
    return Config.IsEnabled() and Config.Get().Tasks.Enable ~= false
end
--- A switch whose job runs on the bundle (StackJob, slice 4): it loads the bundle through `ForOurs` with the humaniser off.
local function oursOn()
    return Ours.On("StackExecute") or Ours.On("RuneRotation") or Ours.On("SupportPull")
end
--- A core counts as able to take a creep this far past its attack range (`judgement`).
local CORE_REACH_BUFFER = 150
--- ... or when its position this far ahead (s) is nearer the creep by more than the epsilon (it is walking to it).
local APPROACH_LOOKAHEAD = 0.5
local APPROACH_EPSILON = 25
local function coreCanReach(core, creep)
    local dist = GetUnitToUnitDistance(core, creep)
    if dist <= core:GetAttackRange() + CORE_REACH_BUFFER then
        return true
    end
    local ahead = GetUnitToLocationDistance(
        creep,
        core:GetExtrapolatedLocation(APPROACH_LOOKAHEAD)
    )
    return ahead < dist - APPROACH_EPSILON
end
--- An allied core (position 1-3, not the bot) within 1600 that can take the creep itself.
local function CoreCanTake(bot, creep, allies)
    for ____, ally in ipairs(allies) do
        if ally ~= bot and ally:IsAlive() then
            local pos = LaneConfig.PositionOf(ally)
            if pos ~= nil and pos <= 3 and coreCanReach(ally, creep) then
                return true
            end
        end
    end
    return false
end
--- One table per bot, cleared on a new frame (no allocation per frame).
local filterCache = {}
--- A core (the lowest `creep` cell) keeps the core-in-reach rule whatever the switch: `FreeFor` never holds it back.
local function opens(bot)
    return Ours.On("SupportCreeps") and TripTable.Outranked(
        "creep",
        LaneConfig.PositionOf(bot)
    )
end
--- Deleted with Ours.SupportCreeps' judgement (a flag between two versions of our own code): with the switch on `f.open` skips the core-in-reach
-- rule below for a support, as creep_row's `FreeFor` replaces it there.
local function mayTake(bot, creep, f)
    if creep == nil or creep == nil or creep:IsNull() then
        return false
    end
    if f.open then
        return true
    end
    local pos = LaneConfig.PositionOf(bot)
    if pos == nil or pos <= 2 then
        return true
    end
    if f.allies == nil then
        f.allies = bot:GetNearbyHeroes(1600, false, BotMode.None)
    end
    return not CoreCanTake(bot, creep, f.allies)
end
--- Skill 1 (the adapter gives no `skill`, which the engine reads as 1): no reaction delay, jitter, aim error or lapse.
local SKILL_ONE = {react = 0, jitter = 0, aimError = 0, lapse = 0}
local adapter = {
    claim = function() return nil end,
    release = function() return nil end,
    lastHitFilter = function(bot, creep)
        local pid = bot:GetPlayerID()
        local now = DotaTime()
        local f = filterCache[pid]
        if f == nil then
            f = {
                t = now,
                by = {},
                open = opens(bot)
            }
            filterCache[pid] = f
        elseif f.t ~= now then
            f.t = now
            f.allies = nil
            f.open = opens(bot)
            for k in pairs(f.by) do
                f.by[k] = nil
            end
        end
        local by = f.by
        local hit = by[creep]
        if hit ~= nil then
            return hit
        end
        local allowed = mayTake(bot, creep, f)
        by[creep] = allowed
        return allowed
    end,
    profile = function() return SKILL_ONE end,
    lastHitError = function() return 0 end,
    random = function() return RandomFloat(0, 1) end,
    attackClock = function() return GameTime() end,
    now = function() return DotaTime() end,
    log = function(tag, msg) return HDebug.Log(tag, msg) end,
    event = function(name, fields) return Telemetry.EventUntyped(name, fields) end,
    vector = function(x, y, z) return Vector(x, y, z) end,
    enabled = function() return ____exports.Enabled() or oursOn() end
}
local function loadBundle(ours)
    if ours == nil then
        ours = false
    end
    if not ____exports.Enabled() and not (ours and oursOn()) then
        return nil
    end
    if attempted then
        return lib
    end
    attempted = true
    local ok, res = pcall(
        require,
        GetScriptDirectory() .. "/FunLib/engine/tasks"
    )
    local support = ("[H:tasks] support coroutine=" .. type(coroutine)) .. " bundle="
    local rawPrint = Utils.RawPrint
    if ok and type(res) == "table" then
        lib = res
        lib.init(adapter)
        JobVerbs.Bind(lib, adapter)
        local verbs = lib.Verbs
        LaneOffers.SetOffers(function(bot) return verbs.laneTargets(bot, {within = 1}) end);
        (rawPrint or print)(support .. "ok")
    else
        (rawPrint or print)((support .. "fail ") .. tostring(res))
    end
    return lib
end
--- The loaded bundle (loading it on first use), or undefined when tasks are off or it failed to load.
function ____exports.Loaded()
    return loadBundle()
end
LaneConfig.SetRng(function()
    local ____opt_0 = loadBundle()
    return ____opt_0 and ____opt_0.Skill
end)
--- True once the bundle has loaded and tasks are enabled.
function ____exports.IsActive()
    return lib ~= nil and ____exports.Enabled()
end
--- The decider's rows' task names (`Decider.Add` registers each): only the decider starts one (`Begin`), since a start replaces
-- whatever task the hero has (the runner's `replaced`) and the order among rows is the decider's. A row's name is its task's name.
local ROW_TASKS = {}
--- Guards `name` as a row's task: from now on only the decider's begin may start it.
function ____exports.GuardRowTask(name)
    ROW_TASKS[name] = true
end
--- The older chooser path, as built, starts a `stack` task of its own and names itself in `via`. RuneJob.Wants and
-- RuneJob.MidWants start `rune`, which is no row's task, so they need no entry.
local EXEMPT = {["StackJob.Wants"] = true}
--- The row whose begin the decider is running, if any.
local beginning
--- The decider's begin: `begin` runs with `row`'s task start allowed. An error in it is raised again after the allowance ends.
function ____exports.Begin(row, begin)
    local prev = beginning
    beginning = row
    local ok, res = pcall(begin)
    beginning = prev
    if not ok then
        error(res, 0)
    end
    return res == true
end
--- The decider's hook on a row's task end (`OnRowEnd`).
local rowEnd
--- The decider's hook, called when any guarded row's task ends, after the task's own onEnd (so a row's end line still sees what the
-- hero held): the decider releases the claim it took at the begin (offers-and-the-decider s6, claims by target).
function ____exports.OnRowEnd(fn)
    rowEnd = fn
end
--- A guarded row's task options with the decider's end hook after the row's own onEnd; any other task's unchanged. Exported for runner stubs in tests.
function ____exports.WithRowEnd(bot, opts)
    local name = opts.name
    if name == nil or ROW_TASKS[name] ~= true or rowEnd == nil then
        return opts
    end
    local own = opts.onEnd
    local hook = rowEnd
    return __TS__ObjectAssign(
        {},
        opts,
        {onEnd = function(r, info)
            local ok, err = unpack(own == nil and ({true, nil}) or ({pcall(own, r, info)}))
            hook(bot, name)
            if not ok then
                error(
                    tostring(err),
                    0
                )
            end
        end}
    )
end
--- A row's task started anywhere but the decider's begin: refused and logged (ev=lua_error where=Tasks.Start).
local function refusedRowStart(name, via)
    if ROW_TASKS[name] ~= true or beginning == name or via ~= nil and EXEMPT[via] == true then
        return false
    end
    Telemetry.Failed("Tasks.Start", ("row task " .. name) .. " started outside the decider's begin")
    return true
end
function ____exports.Start(bot, opts, body, via)
    if refusedRowStart(opts.name, via) then
        return false
    end
    local l = loadBundle()
    return l ~= nil and l.Tasks.task(
        bot,
        ____exports.WithRowEnd(bot, opts),
        body
    )
end
--- Call from the host mode's Think(); returns false when no task of this bot runs under `mode`.
function ____exports.Step(bot, mode)
    local l = loadBundle()
    return l ~= nil and l.Tasks.Step(bot, mode)
end
function ____exports.Tick(bot)
    local ____opt_2 = loadBundle()
    if ____opt_2 ~= nil then
        ____opt_2.Tasks.Tick(bot)
    end
end
--- Never loads the bundle: no task can be running before one was started.
function ____exports.Current(bot)
    local ____IsActive_result_4
    if ____exports.IsActive() then
        ____IsActive_result_4 = lib.Tasks.Current(bot)
    else
        ____IsActive_result_4 = nil
    end
    return ____IsActive_result_4
end
--- The running task however the bundle was loaded (ForOurs too); never loads it (the overlay).
function ____exports.Running(bot)
    return lib and lib.Tasks.Current(bot)
end
function ____exports.Cancel(bot, reason, message)
    if ____exports.IsActive() then
        lib.Tasks.Cancel(bot, reason, message)
    end
end
function ____exports.Urgent(bot, on)
    if lib ~= nil then
        lib.Tasks.Urgent(bot, on)
    end
end
function ____exports.Label(bot, label)
    if lib ~= nil then
        lib.Tasks.Label(bot, label)
    end
end
function ____exports.Describe(bot)
    local ____opt_11 = loadBundle()
    return ____opt_11 and ____opt_11.Tasks.Describe(bot)
end
function ____exports.Verbs()
    local ____opt_13 = loadBundle()
    return ____opt_13 and ____opt_13.Verbs
end
--- The job verbs (bot code on the engine's verbs), or undefined when tasks are off or the bundle failed to load.
function ____exports.Jobs()
    return loadBundle() ~= nil and JobVerbs or nil
end
--- The task calls for a job behind an Ours switch (StackJob): the same runner, loaded for the switch alone, so the job runs
-- with the humaniser or its tasks off. The humaniser's own calls above stay gated on Enabled().
____exports.ForOurs = {
    Start = function(bot, opts, body, via)
        if refusedRowStart(opts.name, via) then
            return false
        end
        local l = loadBundle(true)
        return l ~= nil and l.Tasks.task(
            bot,
            ____exports.WithRowEnd(bot, opts),
            body
        )
    end,
    Step = function(bot, mode)
        local l = loadBundle(true)
        return l ~= nil and l.Tasks.Step(bot, mode)
    end,
    Tick = function(bot)
        local ____opt_15 = loadBundle(true)
        if ____opt_15 ~= nil then
            ____opt_15.Tasks.Tick(bot)
        end
    end,
    Cancel = function(bot, reason, message)
        if lib ~= nil then
            lib.Tasks.Cancel(bot, reason, message)
        end
    end,
    Running = function(bot) return lib and lib.Tasks.Current(bot) end,
    Jobs = function() return loadBundle(true) ~= nil and JobVerbs or nil end,
    Verbs = function()
        local ____opt_21 = loadBundle(true)
        return ____opt_21 and ____opt_21.Verbs
    end
}
return ____exports
