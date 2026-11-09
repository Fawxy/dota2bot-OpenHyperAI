--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local TRACKED = {{item = "tango", modifier = "modifier_tango_heal", mana = false}, {item = "salve", modifier = "modifier_flask_healing", mana = false}, {item = "clarity", modifier = "modifier_clarity_potion", mana = true}}
local EARLY_TOLERANCE = 0.5
local REFRESH_RISE = 0.5
local SOURCE_WINDOW = 2
local active = {}
local recent = {}
local function sources(bot)
    local parts = {}
    if bot:WasRecentlyDamagedByAnyHero(SOURCE_WINDOW) then
        parts[#parts + 1] = "hero"
    end
    if bot:WasRecentlyDamagedByCreep(SOURCE_WINDOW) then
        parts[#parts + 1] = "creep"
    end
    if bot:WasRecentlyDamagedByTower(SOURCE_WINDOW) then
        parts[#parts + 1] = "tower"
    end
    return #parts > 0 and table.concat(parts, ",") or "-"
end
local function dropInWindow(pid, now, hp)
    local top = hp
    for ____, r in ipairs(recent[pid] or ({})) do
        if now - r.t <= SOURCE_WINDOW and r.hp > top then
            top = r.hp
        end
    end
    return top - hp
end
local function emit(bot, t, state, why, dur, left, miss, src, drop)
    local maxHP = bot:GetMaxHealth()
    local maxMP = bot:GetMaxMana()
    Telemetry.Event(
        "regen_obs",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"item", t.item},
            {"state", state},
            {"why", why},
            {
                "hp",
                maxHP > 0 and bot:GetHealth() / maxHP or -1
            },
            {
                "mp",
                maxMP > 0 and bot:GetMana() / maxMP or -1
            },
            {"miss", miss},
            {"dur", dur},
            {"left", left},
            {"src", src},
            {"drop", drop}
        }
    )
end
function ____exports.Tick(bot)
    if not Telemetry.IsEnabled() then
        return
    end
    local pid = bot:GetPlayerID()
    local ____active_0, ____pid_1 = active, pid
    if ____active_0[____pid_1] == nil then
        ____active_0[____pid_1] = {}
    end
    local mine = active[pid]
    local now = DotaTime()
    local ____recent_3, ____pid_4 = recent, pid
    if ____recent_3[____pid_4] == nil then
        ____recent_3[____pid_4] = {}
    end
    local hist = recent[pid]
    local drop = dropInWindow(
        pid,
        now,
        bot:GetHealth()
    )
    hist[#hist + 1] = {
        t = now,
        hp = bot:GetHealth()
    }
    while #hist > 0 and now - hist[1].t > SOURCE_WINDOW do
        table.remove(hist, 1)
    end
    for ____, t in ipairs(TRACKED) do
        local idx = bot:HasModifier(t.modifier) and bot:GetModifierByName(t.modifier) or -1
        local was = mine[t.modifier]
        if idx >= 0 then
            local left = bot:GetModifierRemainingDuration(idx)
            if was == nil then
                local miss = t.mana and bot:GetMaxMana() - bot:GetMana() or bot:GetMaxHealth() - bot:GetHealth()
                mine[t.modifier] = {startAt = now, dur = left, left = left}
                emit(
                    bot,
                    t,
                    "start",
                    "-",
                    left,
                    left,
                    miss,
                    "-",
                    0
                )
            else
                if left > was.left + REFRESH_RISE then
                    emit(
                        bot,
                        t,
                        "refresh",
                        "-",
                        was.dur,
                        left,
                        0,
                        "-",
                        0
                    )
                    was.startAt = now
                    was.dur = left
                end
                was.left = left
            end
        elseif was ~= nil then
            mine[t.modifier] = nil
            local elapsed = now - was.startAt
            local why = not bot:IsAlive() and "dead" or (elapsed < was.dur - EARLY_TOLERANCE and "early" or "full")
            emit(
                bot,
                t,
                "end",
                why,
                was.dur,
                math.max(0, was.dur - elapsed),
                0,
                why == "early" and sources(bot) or "-",
                drop
            )
        end
    end
end
return ____exports
