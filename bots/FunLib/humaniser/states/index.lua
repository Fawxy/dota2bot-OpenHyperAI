--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
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
local Config = require(GetScriptDirectory().."/FunLib/humaniser/config")
local Difficulty = require(GetScriptDirectory().."/FunLib/humaniser/difficulty")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
local LANE_POS_EVERY = 2
function ____exports.Settings()
    return Config.Get().States
end
local function ownList(state)
    local own = ____exports.Settings().Own
    return own ~= nil and own[state] or nil
end
function ____exports.IsEnabled()
    return Config.IsEnabled() and ____exports.Settings().Enable == true and Tasks.Enabled()
end
local function teamApplies(bot)
    return ____exports.Settings().Teams == "all" or Difficulty.IsAllyOfHuman(bot)
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
    return ____exports.IsEnabled() and teamApplies(bot) and ownsAny()
end
local function owns(bot, state)
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
local installed = false
local defined = {}
local lanePosAt = {}
local function lib()
    local l = Tasks.Loaded()
    if l == nil or l.States == nil then
        return nil
    end
    if not installed then
        installed = true
        l.States.SetOwned(function(b, state) return owns(b, state) end)
    end
    return l
end
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
    local ____Telemetry_Event_4 = Telemetry.Event
    local ____array_3 = __TS__SparseArrayNew(
        {"pid", pid},
        {
            "d",
            spot ~= nil and math.floor(GetUnitToLocationDistance(bot, spot)) or nil
        },
        {"owned", cur.owned},
        {"running", cur.running}
    )
    local ____cur_running_2
    if cur.running then
        ____cur_running_2 = task and task.label
    else
        ____cur_running_2 = nil
    end
    __TS__SparseArrayPush(
        ____array_3,
        {"label", ____cur_running_2},
        {
            "mode",
            bot:GetActiveMode()
        }
    )
    ____Telemetry_Event_4(
        "lane_pos",
        {__TS__SparseArraySpread(____array_3)}
    )
end
--- Every frame from Humaniser.Tick, before Tasks.Tick.
function ____exports.Tick(bot)
    if not ____exports.IsEnabled() or not teamApplies(bot) then
        return
    end
    if ____exports.Settings().Shadow ~= true and not ownsAny() then
        return
    end
    local l = lib()
    if l == nil then
        return
    end
    local pid = bot:GetPlayerID()
    if defined[pid] ~= true then
        defined[pid] = true
        l.States.define(
            bot,
            {Laning.Spec(bot)}
        )
    end
    l.States.Tick(bot)
    lanePos(bot, l)
end
--- First thing in a host mode's Think() step it replaces: true when the state's body acted this frame.
function ____exports.Step(bot, mode)
    if not ____exports.IsEnabled() then
        return false
    end
    local l = lib()
    return l ~= nil and l.States.Step(bot, mode)
end
--- mode_laning_generic.lua hands over its PositionThink target (nil until its GetDesire has run).
function ____exports.SetLaneSpot(bot, fn)
    Laning.SetSpot(bot, fn)
end
function ____exports.Describe(bot)
    if not ____exports.IsEnabled() then
        return nil
    end
    local ____opt_5 = Tasks.Loaded()
    local cur = ____opt_5 and ____opt_5.States.Current(bot)
    return cur == nil and "-" or (((cur.name .. (cur.owned and "*" or "")) .. (cur.running and " run" or "")) .. " n=") .. tostring(cur.starts)
end
return ____exports
