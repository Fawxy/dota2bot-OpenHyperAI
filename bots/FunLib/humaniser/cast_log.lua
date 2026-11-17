--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__ArraySplice(self, ...)
    local args = {...}
    local len = #self
    local actualArgumentCount = __TS__CountVarargs(...)
    local start = args[1]
    local deleteCount = args[2]
    if start < 0 then
        start = len + start
        if start < 0 then
            start = 0
        end
    elseif start > len then
        start = len
    end
    local itemCount = actualArgumentCount - 2
    if itemCount < 0 then
        itemCount = 0
    end
    local actualDeleteCount
    if actualArgumentCount == 0 then
        actualDeleteCount = 0
    elseif actualArgumentCount == 1 then
        actualDeleteCount = len - start
    else
        actualDeleteCount = deleteCount or 0
        if actualDeleteCount < 0 then
            actualDeleteCount = 0
        end
        if actualDeleteCount > len - start then
            actualDeleteCount = len - start
        end
    end
    local out = {}
    for k = 1, actualDeleteCount do
        local from = start + k
        if self[from] ~= nil then
            out[k] = self[from]
        end
    end
    if itemCount < actualDeleteCount then
        for k = start + 1, len - actualDeleteCount do
            local from = k + actualDeleteCount
            local to = k + itemCount
            if self[from] then
                self[to] = self[from]
            else
                self[to] = nil
            end
        end
        for k = len - actualDeleteCount + itemCount + 1, len do
            self[k] = nil
        end
    elseif itemCount > actualDeleteCount then
        for k = len - actualDeleteCount, start + 1, -1 do
            local from = k + actualDeleteCount
            local to = k + itemCount
            if self[from] then
                self[to] = self[from]
            else
                self[to] = nil
            end
        end
    end
    local j = start + 1
    for i = 3, actualArgumentCount do
        self[j] = args[i]
        j = j + 1
    end
    for k = #self, len - actualDeleteCount + itemCount + 1, -1 do
        self[k] = nil
    end
    return out
end
-- End of Lua Library inline imports
local ____exports = {}
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local CoreTrade = require(GetScriptDirectory().."/FunLib/humaniser/states/core_trade")
local SpellReady = require(GetScriptDirectory().."/FunLib/humaniser/spell_ready")
--- A dead hero has no tick to drain its queue; casts past this many are dropped.
local PENDING_MAX = 16
local installed = {}
local keysLogged = {}
local pending = {}
--- The ability's name: a string, or a handle's GetName (smoke chase-log: 48 of 457 handles gave none through an IsNull test).
local function nameOf(a)
    if type(a) == "string" then
        return a
    end
    if type(a) ~= "table" then
        return nil
    end
    local h = a
    if type(h.IsNull) == "function" and h:IsNull() then
        return nil
    end
    if type(h.GetName) ~= "function" then
        return nil
    end
    local n = h:GetName()
    return type(n) == "string" and n ~= "" and n or nil
end
local function keysOf(event)
    local ks = {}
    for k, v in pairs(event) do
        ks[#ks + 1] = (tostring(k) .. ":") .. type(v)
    end
    table.sort(ks)
    return table.concat(ks, "|")
end
local function log(bot, p)
    local e = p.event
    if type(e) ~= "table" then
        return
    end
    local pid = bot:GetPlayerID()
    local loc = e.location
    local hasLoc = loc ~= nil and loc ~= nil and type(loc.x) == "number" and type(loc.y) == "number" and (loc.x ~= 0 or loc.y ~= 0)
    local ep = CoreTrade.EpisodeOf(pid)
    local t = ep and ep.target
    local seen = t ~= nil and not t:IsNull() and t:CanBeSeen()
    local name = nameOf(e.ability)
    local first = keysLogged[pid] ~= true
    keysLogged[pid] = true
    local el
    if hasLoc and seen then
        local tl = t:GetLocation()
        el = math.floor(math.sqrt((tl.x - loc.x) * (tl.x - loc.x) + (tl.y - loc.y) * (tl.y - loc.y)))
    end
    Telemetry.Event(
        "cast",
        {
            {"pid", pid},
            {"ab", name},
            {
                "cl",
                SpellReady.ClassByName(bot, name)
            },
            {
                "x",
                hasLoc and math.floor(loc.x) or nil
            },
            {
                "y",
                hasLoc and math.floor(loc.y) or nil
            },
            {"el", el},
            {"ek", ep and ep.kind},
            {"etg", ep and ep.tpid},
            {"es", ep ~= nil and (seen and 1 or 0) or nil},
            {
                "ed",
                seen and bot:IsAlive() and math.floor(GetUnitToUnitDistance(bot, t)) or nil
            },
            {
                "lag",
                math.floor((DotaTime() - p.at) * 10) / 10
            },
            {
                "ks",
                first and keysOf(e) or nil
            }
        }
    )
end
--- Installs the hero's callback once, then logs the casts queued since its last tick.
function ____exports.Tick(bot)
    if not Telemetry.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    if installed[pid] ~= true then
        installed[pid] = true
        pending[pid] = {}
        local q = pending[pid]
        local function handler(event)
            if #q < PENDING_MAX then
                q[#q + 1] = {
                    event = event,
                    at = DotaTime()
                }
            end
        end
        InstallCastCallback(
            pid,
            Telemetry.GuardsEnabled() and Telemetry.Guard("CastLog.OnCast", handler) or handler
        )
    end
    local q = pending[pid]
    if #q == 0 then
        return
    end
    local items = __TS__ArraySplice(q, 0, #q)
    for ____, p in ipairs(items) do
        pcall(log, bot, p)
    end
end
return ____exports
