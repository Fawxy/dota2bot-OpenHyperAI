--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArraySort(self, compareFn)
    if compareFn ~= nil then
        table.sort(
            self,
            function(a, b) return compareFn(nil, a, b) < 0 end
        )
    else
        table.sort(self)
    end
    return self
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Team = ____dota.Team
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local DesireLog = require(GetScriptDirectory().."/FunLib/humaniser/desire_log")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local LaneConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_config")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
local X = 20
local TOP = 90
local LINE = 14
--- A team's block: its own line and five heroes, then a gap.
local BLOCK = 7 * LINE
local RING = 140
local OURS_COLOUR = {255, 220, 0}
local WAITING_COLOUR = {200, 180, 110}
local STOCK_COLOUR = {140, 140, 140}
local RING_COLOUR = {pull = {0, 200, 255}, stack = {80, 230, 80}, rune_detour = {230, 80, 230}}
local headerAt = -1
local switchesLine
local function label()
    local ____opt_0 = Customize.Overrides
    if ____opt_0 ~= nil then
        ____opt_0 = ____opt_0.Label
    end
    local v = ____opt_0
    return type(v) == "string" and v ~= "" and v or nil
end
--- The Ours switches on for this VM's team, read once: they are fixed for the game.
local function switches()
    if switchesLine == nil then
        local on = {}
        for name in pairs(Ours.DEFAULTS) do
            if Ours.On(name) then
                on[#on + 1] = name
            end
        end
        __TS__ArraySort(on)
        switchesLine = #on > 0 and "ours: " .. table.concat(on, " ") or "stock"
    end
    return switchesLine
end
local function heroName(unit)
    return (string.gsub(
        unit:GetUnitName(),
        "npc_dota_hero_",
        ""
    ))
end
--- Before the horn OHA's GetPosition can fall back to 2 for heroes whose role is not set, and two lines would overlap.
local function rolesSettled()
    return DotaTime() >= 0
end
local function blockTop(team)
    return TOP + LINE + (team == Team.Radiant and 0 or BLOCK)
end
--- Ours while a task of ours runs under the active mode, or the decider holds the hero and farm (its host) is active.
local function doing(bot)
    local mode = bot:GetActiveMode()
    local task = Tasks.Running(bot)
    local held = Decider.Held(bot)
    local hold = held == nil and "" or (held.soft == true and " soft" or " hard")
    if task ~= nil and task.host == mode then
        local text = (task.name .. (task.label ~= nil and ":" .. task.label or "")) .. hold
        return {text = text, colour = OURS_COLOUR, ring = task.name}
    end
    if held ~= nil and mode == BotMode.Farm then
        return {text = held.name .. hold, colour = OURS_COLOUR, ring = held.name}
    end
    if held ~= nil then
        return {
            text = ((HDebug.ModeName(mode) .. " (") .. held.name) .. " outbid)",
            colour = WAITING_COLOUR
        }
    end
    return {
        text = HDebug.ModeName(mode),
        colour = STOCK_COLOUR
    }
end
function ____exports.Draw(bot)
    local name = label()
    if name == nil then
        return
    end
    local team = bot:GetTeam()
    local top = blockTop(team)
    local now = GameTime()
    if headerAt ~= now then
        headerAt = now
        if team == Team.Radiant then
            DebugDrawText(
                X,
                TOP,
                (name .. "  build ") .. Telemetry.Build(),
                255,
                255,
                255
            )
        end
        local r, g, b = unpack(team == Team.Radiant and ({120, 220, 120}) or ({230, 110, 110}))
        DebugDrawText(
            X,
            top,
            ((team == Team.Radiant and "RADIANT" or "DIRE") .. "  ") .. switches(),
            r,
            g,
            b
        )
        do
            local i = 1
            while i <= 5 and rolesSettled() do
                do
                    local __continue19
                    repeat
                        local m = GetTeamMember(i)
                        if m == nil or m == nil or m:IsAlive() then
                            __continue19 = true
                            break
                        end
                        local p = LaneConfig.PositionOf(m)
                        if p ~= nil and p >= 1 and p <= 5 then
                            DebugDrawText(
                                X,
                                top + p * LINE,
                                ((tostring(p) .. " ") .. heroName(m)) .. "  dead",
                                STOCK_COLOUR[1],
                                STOCK_COLOUR[2],
                                STOCK_COLOUR[3]
                            )
                        end
                        __continue19 = true
                    until true
                    if not __continue19 then
                        break
                    end
                end
                i = i + 1
            end
        end
    end
    local pos = LaneConfig.PositionOf(bot)
    if not rolesSettled() or pos == nil or pos < 1 or pos > 5 or not bot:IsAlive() then
        return
    end
    local d = doing(bot)
    local hero = heroName(bot)
    local extra = HDebug.IsEnabled() and "  " .. DesireLog.Competing(bot) or ""
    DebugDrawText(
        X,
        top + pos * LINE,
        ((((tostring(pos) .. " ") .. hero) .. "  ") .. d.text) .. extra,
        d.colour[1],
        d.colour[2],
        d.colour[3]
    )
    if d.ring ~= nil then
        local r, g, b = unpack(RING_COLOUR[d.ring] or OURS_COLOUR)
        DebugDrawCircle(
            bot:GetLocation(),
            RING,
            r,
            g,
            b
        )
    end
end
return ____exports
