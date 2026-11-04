--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayFilter(self, callbackfn, thisArg)
    local result = {}
    local len = 0
    for i = 1, #self do
        if callbackfn(thisArg, self[i], i - 1, self) then
            len = len + 1
            result[len] = self[i]
        end
    end
    return result
end

local function __TS__ArrayIncludes(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    local k = fromIndex
    if fromIndex < 0 then
        k = len + fromIndex
    end
    if k < 0 then
        k = 0
    end
    for i = k + 1, len do
        if self[i] == searchElement then
            return true
        end
    end
    return false
end

local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__ArrayReduce(self, callbackFn, ...)
    local len = #self
    local k = 0
    local accumulator = nil
    if __TS__CountVarargs(...) ~= 0 then
        accumulator = ...
    elseif len > 0 then
        accumulator = self[1]
        k = 1
    else
        error("Reduce of empty array with no initial value", 0)
    end
    for i = k + 1, len do
        accumulator = callbackFn(
            nil,
            accumulator,
            self[i],
            i - 1,
            self
        )
    end
    return accumulator
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Tower = ____dota.Tower
local UnitType = ____dota.UnitType
local TOWER_IDS = {
    Tower.Top1,
    Tower.Top2,
    Tower.Top3,
    Tower.Mid1,
    Tower.Mid2,
    Tower.Mid3,
    Tower.Bot1,
    Tower.Bot2,
    Tower.Bot3
}
local POWER_RUNE_MODIFIERS = {
    "modifier_rune_doubledamage",
    "modifier_rune_haste",
    "modifier_rune_invis",
    "modifier_rune_regen",
    "modifier_rune_arcane",
    "modifier_rune_shield"
}
function ____exports.Alive(u)
    return u ~= nil and u ~= nil and u:IsAlive()
end
function ____exports.Dist(a, b)
    return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
end
function ____exports.HpFraction(u)
    local max = u:GetMaxHealth()
    return max > 0 and u:GetHealth() / max or 0
end
function ____exports.ManaFraction(u)
    local max = u:GetMaxMana()
    return max > 0 and u:GetMana() / max or 1
end
function ____exports.HoldsPowerRune(u)
    for ____, m in ipairs(POWER_RUNE_MODIFIERS) do
        if u:HasModifier(m) then
            return true
        end
    end
    return false
end
--- Distance from `loc` to `team`'s nearest standing tower (math.huge with none).
function ____exports.TowerDistance(team, loc)
    local best = math.huge
    for ____, id in ipairs(TOWER_IDS) do
        do
            local __continue11
            repeat
                local tower = GetTower(team, id)
                if tower == nil or tower == nil or not tower:IsAlive() then
                    __continue11 = true
                    break
                end
                best = math.min(
                    best,
                    ____exports.Dist(
                        loc,
                        tower:GetLocation()
                    )
                )
                __continue11 = true
            until true
            if not __continue11 then
                break
            end
        end
    end
    return best
end
--- Our living heroes (GetTeamMember, not GetTeamPlayers) within `radius` of `at`; `always` are counted wherever they are.
function ____exports.AlliesNear(at, radius, always)
    if always == nil then
        always = {}
    end
    local out = __TS__ArrayFilter(
        always,
        function(____, u) return ____exports.Alive(u) end
    )
    do
        local i = 1
        while i <= 5 do
            local m = GetTeamMember(i)
            if ____exports.Alive(m) and not __TS__ArrayIncludes(out, m) and ____exports.Dist(
                m:GetLocation(),
                at
            ) <= radius then
                out[#out + 1] = m
            end
            i = i + 1
        end
    end
    return out
end
--- Enemy heroes (no illusions) within `radius` of `at` from the API's enemy list; `always` are counted wherever they are.
function ____exports.EnemiesNear(at, radius, always)
    if always == nil then
        always = {}
    end
    local out = __TS__ArrayFilter(
        always,
        function(____, u) return ____exports.Alive(u) end
    )
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        if ____exports.Alive(e) and not e:IsIllusion() and not __TS__ArrayIncludes(out, e) and ____exports.Dist(
            e:GetLocation(),
            at
        ) <= radius then
            out[#out + 1] = e
        end
    end
    return out
end
function ____exports.AverageLevel(units)
    return #units > 0 and __TS__ArrayReduce(
        units,
        function(____, a, u) return a + u:GetLevel() end,
        0
    ) / #units or 0
end
return ____exports
