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
local modesOn, ownList, ownTeam, owns, lib, installModes, MODES_DEFAULTS, MODE_IDS, modesSettings, installed
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local Intent = require(GetScriptDirectory().."/FunLib/humaniser/intent")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
local LaneMetrics = require(GetScriptDirectory().."/FunLib/humaniser/states/lane_metrics")
local Shadow = require(GetScriptDirectory().."/FunLib/humaniser/states/shadow")
local CampJob = require(GetScriptDirectory().."/FunLib/humaniser/states/camp_job")
local Rotate = require(GetScriptDirectory().."/FunLib/humaniser/states/rotate")
local CampJobs = require(GetScriptDirectory().."/FunLib/humaniser/camp_jobs")
local Farm = require(GetScriptDirectory().."/FunLib/humaniser/states/farm")
local Gank = require(GetScriptDirectory().."/FunLib/humaniser/states/gank")
local FarmPattern = require(GetScriptDirectory().."/FunLib/humaniser/farm_pattern")
function ____exports.Modes()
    if modesSettings ~= nil then
        return modesSettings
    end
    local ____opt_2 = Config.Raw()
    if ____opt_2 ~= nil then
        ____opt_2 = ____opt_2.States
    end
    local ____opt_result_4
    if ____opt_2 ~= nil then
        ____opt_result_4 = ____opt_2.Modes
    end
    local ____opt_result_4_5 = ____opt_result_4
    if ____opt_result_4_5 == nil then
        ____opt_result_4_5 = {}
    end
    local c = ____opt_result_4_5
    local out = {}
    for k, v in pairs(MODES_DEFAULTS) do
        local ____k_7 = k
        local ____c_k_6 = c[k]
        if ____c_k_6 == nil then
            ____c_k_6 = v
        end
        out[____k_7] = ____c_k_6
    end
    modesSettings = out
    return modesSettings
end
function modesOn(bot)
    local m = ____exports.Modes()
    if m.Enable ~= true or not ____exports.IsEnabled() or not ownTeam(bot) then
        return false
    end
    local pos = LaneConfig.PositionOf(bot)
    for ____, p in ipairs(m.Positions) do
        if p == pos then
            return true
        end
    end
    return false
end
function ____exports.Settings()
    return Config.Get().States
end
function ownList(state)
    local own = ____exports.Settings().Own
    return own ~= nil and own[state] or nil
end
function ____exports.IsEnabled()
    return Config.IsEnabled() and ____exports.Settings().Enable == true and Tasks.Enabled()
end
function ownTeam(bot)
    return ____exports.Settings().Teams == "all" or Difficulty.IsAllyOfHuman(bot)
end
function owns(bot, state)
    if not ownTeam(bot) then
        return false
    end
    local list = ownList(state)
    if list == nil then
        return false
    end
    local pos = LaneConfig.PositionOf(bot)
    for ____, p in ipairs(list) do
        if p == pos then
            return true
        end
    end
    return false
end
function lib()
    local l = Tasks.Loaded()
    if l == nil or l.States == nil then
        return nil
    end
    if not installed then
        installed = true
        l.States.SetOwned(function(b, state)
            local u = b
            if not owns(u, state) then
                return false
            end
            local ____temp_10 = state ~= Farm.NAME
            if not ____temp_10 then
                local ____opt_8 = FarmPattern.Live(u)
                ____temp_10 = (____opt_8 and ____opt_8.sdk) == true
            end
            return ____temp_10
        end)
        installModes(l)
    end
    return l
end
function installModes(l)
    local m = ____exports.Modes()
    local ids = {}
    for ____, name in ipairs(m.Own) do
        local id = MODE_IDS[name]
        if id ~= nil then
            ids[#ids + 1] = id
        end
    end
    l.Modes.SetOwned(ids)
    l.Modes.SetEnabled(function(b) return modesOn(b) end)
    l.Modes.configure({
        hold = m.Hold,
        interruptDwell = m.InterruptDwell,
        commit = m.Commit,
        idleAfter = m.IdleAfter,
        idleBackoff = m.IdleBackoff
    })
    if m.Enable == true then
        Intent.SetAuthority(function(bot, mode, raw, reason) return l.Modes.Decide(bot, mode, raw, reason) end)
    end
end
--- First thing in a host mode's Think() step it replaces: true when the state's body acted this frame.
function ____exports.Step(bot, mode)
    if not ____exports.IsEnabled() then
        return false
    end
    local l = lib()
    return l ~= nil and l.States.Step(bot, mode)
end
local LANE_POS_EVERY = 2
MODES_DEFAULTS = {
    Enable = false,
    Own = {"laning", "farm"},
    Positions = {
        1,
        2,
        3,
        4,
        5
    },
    Hold = 0.08,
    InterruptDwell = 1.5,
    Commit = 0.75,
    IdleAfter = 3,
    IdleBackoff = 5
}
MODE_IDS = {laning = BotMode.Laning, farm = BotMode.Farm, rune = BotMode.Rune, roam = BotMode.Roam}
--- Tests reload Customize between cases.
function ____exports.ResetModes()
    modesSettings = nil
end
local function shadowTeam(bot)
    return ____exports.Settings().Shadow == true and (____exports.Settings().ShadowTeams == "all" or ownTeam(bot))
end
local function ownsAny()
    local own = ____exports.Settings().Own
    if own == nil then
        return false
    end
    for ____, list in pairs(own) do
        if #list > 0 then
            return true
        end
    end
    return false
end
--- Whether the layer may ever own a state for this bot; for load-time decisions (mode_laning_generic's Think).
function ____exports.MayOwn(bot)
    return ____exports.IsEnabled() and ownTeam(bot) and ownsAny()
end
--- States by name in registration order; registering an existing name replaces it in place.
local registry = {}
local registryVersion = 0
function ____exports.Register(name, make)
    registryVersion = registryVersion + 1
    for ____, r in ipairs(registry) do
        if r.name == name then
            r.make = make
            return
        end
    end
    registry[#registry + 1] = {name = name, make = make}
end
function ____exports.Registered()
    return __TS__ArrayMap(
        registry,
        function(____, r) return r.name end
    )
end
____exports.Register(
    Laning.NAME,
    function(bot) return Laning.Spec(bot, owns) end
)
for ____, ____value in ipairs(Shadow.SPECS) do
    local name = ____value[1]
    local make = ____value[2]
    ____exports.Register(name, make)
end
____exports.Register(
    CampJob.PULL,
    function(bot) return CampJob.Spec(bot, CampJob.PULL, owns, Shadow.PullScore) end
)
____exports.Register(
    CampJob.STACK,
    function(bot) return CampJob.Spec(bot, CampJob.STACK, owns, Shadow.StackScore) end
)
____exports.Register(
    Rotate.NAME,
    function(bot) return Rotate.Spec(bot, owns, Shadow.RotateScore) end
)
____exports.Register(
    Farm.NAME,
    function(bot) return Farm.Spec(bot, Shadow.FarmScore) end
)
____exports.Register(
    Gank.NAME,
    function(bot) return Gank.Spec(bot, owns) end
)
local function guarded(spec)
    if Telemetry.GuardsEnabled() then
        spec.score = Telemetry.Guard(
            "States.score." .. spec.name,
            spec.score,
            function() return nil end
        )
    end
    return spec
end
installed = false
local defined = {}
local lanePosAt = {}
local function lanePos(bot, l)
    local cur = l.States.Current(bot)
    if cur == nil or cur.name ~= Laning.NAME then
        return
    end
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    if now - (lanePosAt[pid] or -math.huge) < (____exports.Settings().LanePosEvery or LANE_POS_EVERY) then
        return
    end
    lanePosAt[pid] = now
    local spot = Laning.Spot(bot)
    local task = Tasks.Current(bot)
    local info = Laning.SpotInfo(bot)
    local ____Telemetry_Event_17 = Telemetry.Event
    local ____array_16 = __TS__SparseArrayNew(
        {"pid", pid},
        {
            "d",
            spot ~= nil and math.floor(GetUnitToLocationDistance(bot, spot)) or nil
        },
        {"owned", cur.owned},
        {"running", cur.running}
    )
    local ____cur_running_13
    if cur.running then
        ____cur_running_13 = task and task.label
    else
        ____cur_running_13 = nil
    end
    __TS__SparseArrayPush(
        ____array_16,
        {"label", ____cur_running_13},
        {
            "mode",
            bot:GetActiveMode()
        },
        {"spot", info ~= nil and info.anchor or "oha"},
        {"pushed", info and info.pushed},
        {
            "hph",
            LaneMetrics.HeroLost(bot)
        }
    )
    ____Telemetry_Event_17(
        "lane_pos",
        {__TS__SparseArraySpread(____array_16)}
    )
end
--- Every frame from Humaniser.Tick, before Tasks.Tick.
function ____exports.Tick(bot)
    if not ____exports.IsEnabled() then
        return
    end
    if not shadowTeam(bot) and not (ownTeam(bot) and ownsAny()) then
        return
    end
    local l = lib()
    if l == nil then
        return
    end
    local pid = bot:GetPlayerID()
    if defined[pid] ~= registryVersion then
        defined[pid] = registryVersion
        l.States.define(
            bot,
            __TS__ArrayMap(
                registry,
                function(____, r) return guarded(r.make(bot)) end
            )
        )
    end
    l.States.Tick(bot)
    l.Modes.Tick(bot)
    LaneMetrics.Tick(bot)
    lanePos(bot, l)
end
--- Whether the layer runs `state`'s body for this bot now (enabled, team rule, position listed in Own).
function ____exports.Owns(bot, state)
    return ____exports.IsEnabled() and owns(bot, state)
end
--- Steps the bot's farm-hosted state only when it is one of `names`, so one executor never runs another's body.
local function stepFarm(bot, names)
    local ____opt_18 = lib()
    local cur = ____opt_18 and ____opt_18.States.Current(bot)
    return cur ~= nil and names[cur.name] == true and ____exports.Step(bot, BotMode.Farm)
end
local FARM_STATES = {[Farm.NAME] = true}
local CAMP_STATES = {[CampJob.STACK] = true, [CampJob.PULL] = true}
FarmPattern.SetExecutor({
    Owns = function(bot) return ____exports.Owns(bot, Farm.NAME) and lib() ~= nil end,
    Step = function(bot) return stepFarm(bot, FARM_STATES) end
})
CampJobs.SetExecutor({
    Owns = function(bot, job)
        local state = CampJob.StateOf(job)
        return state ~= nil and ____exports.Owns(bot, state) and lib() ~= nil
    end,
    Step = function(bot) return stepFarm(bot, CAMP_STATES) end
})
--- mode_rune_generic: OHA's own wisdom logic stands aside for this bot (its shrine trip is the state's) or for the
-- team (an owned trip is on the shrine this fill).
function ____exports.WisdomOwned(bot)
    if not ____exports.IsEnabled() then
        return false
    end
    return ____exports.Owns(bot, Rotate.NAME) and Rotate.OnTrip(bot) or Rotate.ShrineTaken(bot:GetTeam())
end
--- True while the laning body runs for this bot and owns its last hits: the Lua Think skips its own.
function ____exports.BodyLastHits(bot)
    if not ____exports.IsEnabled() or not Laning.OwnsLastHit(bot) then
        return false
    end
    local ____opt_20 = Tasks.Loaded()
    local cur = ____opt_20 and ____opt_20.States.Current(bot)
    return cur ~= nil and cur.name == Laning.NAME and cur.owned and cur.running
end
--- mode_laning_generic.lua hands over its own laning steps (everything its Think does but PositionThink); the
-- laning body runs them on its hold and walk frames, so none can re-order a last-hit swing (team slice 14).
function ____exports.SetLaneAssist(bot, fn)
    Laning.SetAssist(bot, fn)
end
--- Whether the layer decides this bot's mode desires now (overlay, tests).
function ____exports.ModesAsserting(bot)
    if not ____exports.IsEnabled() then
        return false
    end
    local l = Tasks.Loaded()
    return l ~= nil and l.Modes ~= nil and l.Modes.Asserting(bot)
end
--- mode_laning_generic.lua hands over its PositionThink target (nil until its GetDesire has run).
function ____exports.SetLaneSpot(bot, fn)
    Laning.SetSpot(bot, fn)
end
function ____exports.Describe(bot)
    if not ____exports.IsEnabled() then
        return nil
    end
    local ____opt_22 = Tasks.Loaded()
    local cur = ____opt_22 and ____opt_22.States.Current(bot)
    return cur == nil and "-" or (((cur.name .. (cur.owned and "*" or "")) .. (cur.running and " run" or "")) .. " n=") .. tostring(cur.starts)
end
return ____exports
