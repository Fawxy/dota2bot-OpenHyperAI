--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local modeName, close, GAP, kindLogged
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local UnitType = ____dota.UnitType
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
function ____exports.KindOf(bot)
    if not Ours.On("YieldProbe") then
        return nil
    end
    local slot = bot:GetPlayerID() % 5
    local k = slot <= 1 and "own" or (slot <= 3 and "zero" or "nil")
    if kindLogged[bot:GetPlayerID()] ~= true then
        kindLogged[bot:GetPlayerID()] = true
        Telemetry.Event(
            "yield",
            {
                {
                    "pid",
                    bot:GetPlayerID()
                },
                {"ph", "kind"},
                {"kind", k}
            }
        )
    end
    return k
end
function modeName(bot)
    return HDebug.ModeName(bot:GetActiveMode())
end
function close(bot, w, now, why)
    Telemetry.Event(
        "yield",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"ph", "end"},
            {
                "kind",
                ____exports.KindOf(bot)
            },
            {"why", why},
            {
                "mode",
                modeName(bot)
            },
            {
                "secs",
                math.floor((now - w.at) * 10) / 10
            },
            {"n", w.n},
            {"atk", w.atk},
            {"hero", w.hero},
            {
                "hp",
                math.floor(100 * bot:GetHealth() / bot:GetMaxHealth())
            }
        }
    )
    w["until"] = -1
    w.next = now + GAP
end
local HOLD = 4
GAP = 6
local REACH_EXTRA = 300
local MIN_HP = 0.7
--- Valve's attack desire for `own` in a window: above OHA's laning (0.45) and team roam (0.72), level with its retreat.
____exports.OWN_DESIRE = 0.95
local wins = {}
kindLogged = {}
local function nearestEnemy(bot)
    local best
    local bd = math.huge
    for ____, h in ipairs(GetUnitList(UnitType.EnemyHeroes) or ({})) do
        do
            local __continue6
            repeat
                if h:IsNull() or not h:IsAlive() or h:IsIllusion() then
                    __continue6 = true
                    break
                end
                local d = GetUnitToUnitDistance(bot, h)
                if d < bd then
                    bd = d
                    best = h
                end
                __continue6 = true
            until true
            if not __continue6 then
                break
            end
        end
    end
    return {best, bd}
end
--- Advances the hero's window once per game time; true while a window holds.
function ____exports.InWindow(bot)
    local pid = bot:GetPlayerID()
    local now = DotaTime()
    local w = wins[pid]
    if w == nil then
        w = {
            ["until"] = -1,
            next = 30,
            at = 0,
            tick = -1,
            n = 0,
            atk = 0,
            hero = 0,
            mode0 = ""
        }
        wins[pid] = w
    end
    if w.tick == now then
        return now < w["until"]
    end
    w.tick = now
    if not bot:IsAlive() then
        if now < w["until"] then
            close(bot, w, now, "dead")
        end
        return false
    end
    if now < w["until"] then
        w.n = w.n + 1
        if bot:GetActiveMode() == BotMode.Attack then
            w.atk = w.atk + 1
        end
        local t = bot:GetAttackTarget()
        if t ~= nil and t ~= nil and not t:IsNull() and t:IsHero() then
            w.hero = w.hero + 1
        end
        return true
    end
    if w["until"] > 0 then
        close(bot, w, now, "time")
    end
    if now < w.next or now > 600 then
        return false
    end
    if bot:GetHealth() < bot:GetMaxHealth() * MIN_HP then
        return false
    end
    local e, d = unpack(nearestEnemy(bot))
    if e == nil or d > bot:GetAttackRange() + REACH_EXTRA then
        return false
    end
    w["until"] = now + HOLD
    w.at = now
    w.n = 0
    w.atk = 0
    w.hero = 0
    w.mode0 = modeName(bot)
    Telemetry.Event(
        "yield",
        {
            {"pid", pid},
            {"ph", "start"},
            {
                "kind",
                ____exports.KindOf(bot)
            },
            {"mode", w.mode0},
            {
                "ed",
                math.floor(d)
            },
            {
                "tpid",
                e:GetPlayerID()
            },
            {
                "hp",
                math.floor(100 * bot:GetHealth() / bot:GetMaxHealth())
            }
        }
    )
    return true
end
--- `zero`: every gated mode returns 0 while the window holds.
function ____exports.Zeroes(bot)
    return ____exports.KindOf(bot) == "zero" and ____exports.InWindow(bot)
end
--- The attack file's GetDesire for `own` and `nil`; undefined is returned to the engine as nil.
function ____exports.AttackDesire(bot, k)
    if k == "own" and ____exports.InWindow(bot) then
        return ____exports.OWN_DESIRE
    end
    if k == "nil" then
        ____exports.InWindow(bot)
    end
    return nil
end
return ____exports
