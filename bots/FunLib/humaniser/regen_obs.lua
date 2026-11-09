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
-- End of Lua Library inline imports
local ____exports = {}
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local TRACKED = {{item = "tango", modifier = "modifier_tango_heal", mana = false}, {item = "salve", modifier = "modifier_flask_healing", mana = false}, {item = "clarity", modifier = "modifier_clarity_potion", mana = true}}
local EARLY_TOLERANCE = 0.5
local REFRESH_RISE = 0.5
local SOURCE_WINDOW = 2
local active = {}
local MIN_WINDOW = 1
local TREE_SCAN = 1200
local wins = {}
local function inHand(bot, name)
    local slot = bot:FindItemSlot(name)
    if slot == nil or slot < 0 or slot > 5 then
        return nil
    end
    return bot:GetItemInSlot(slot) or nil
end
--- The HP an item gives in full, read from the item (regen per second x duration), 0 when it is not in hand.
local function effectOf(item)
    if item == nil then
        return 0
    end
    local spec = item
    return spec:GetSpecialValueFloat("health_regen") * spec:GetSpecialValueFloat("buff_duration")
end
local function nearestTree(bot)
    local best = -1
    for ____, tree in ipairs(bot:GetNearbyTrees(TREE_SCAN) or ({})) do
        do
            local __continue7
            repeat
                local loc = GetTreeLocation(tree)
                if not IsLocationVisible(loc) or not IsLocationPassable(loc) then
                    __continue7 = true
                    break
                end
                local d = GetUnitToLocationDistance(bot, loc)
                if best < 0 or d < best then
                    best = d
                end
                __continue7 = true
            until true
            if not __continue7 then
                break
            end
        end
    end
    return best
end
local function snapWindow(bot, w)
    w.snapped = true
    local tango = inHand(bot, "item_tango")
    local single = inHand(bot, "item_tango_single")
    local salve = inHand(bot, "item_flask")
    w.tg = (tango and tango:GetCurrentCharges() or 0) + (single ~= nil and 1 or 0)
    w.tge = effectOf(tango or single)
    w.sv = salve and salve:GetCurrentCharges() or 0
    w.sve = effectOf(salve)
    w.tree = w.tg > 0 and nearestTree(bot) or -1
    w.under = bot:HasModifier("modifier_tango_heal") or bot:HasModifier("modifier_flask_healing")
end
local function closeWindow(bot, w, now)
    local len = now - w.t0
    if not w.snapped or len < MIN_WINDOW then
        return
    end
    local efforts = __TS__ArrayFilter(
        {w.tg > 0 and w.tge or 0, w.sv > 0 and w.sve or 0},
        function(____, e) return e > 0 end
    )
    if #efforts == 0 or w.missMax < math.min(unpack(efforts)) then
        return
    end
    Telemetry.Event(
        "regen_win",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"mode", w.mode},
            {"len", len},
            {"miss0", w.miss0},
            {"missmax", w.missMax},
            {"tg", w.tg},
            {"sv", w.sv},
            {"tge", w.tge},
            {"sve", w.sve},
            {"tree", w.tree},
            {"under", w.under},
            {
                "used",
                #w.used > 0 and table.concat(w.used, ",") or "-"
            }
        }
    )
end
local function trackWindow(bot, pid, now)
    local idle = bot:IsAlive() and bot:GetAttackTarget() == nil and not bot:WasRecentlyDamagedByAnyHero(SOURCE_WINDOW)
    local w = wins[pid]
    if not idle then
        if w ~= nil then
            closeWindow(bot, w, now)
        end
        wins[pid] = nil
        return
    end
    local miss = bot:GetMaxHealth() - bot:GetHealth()
    if w == nil then
        w = {
            t0 = now,
            snapped = false,
            mode = bot:GetActiveMode(),
            miss0 = miss,
            missMax = miss,
            tg = 0,
            sv = 0,
            tge = 0,
            sve = 0,
            tree = -1,
            under = false,
            used = {}
        }
        wins[pid] = w
    end
    if miss > w.missMax then
        w.missMax = miss
    end
    if not w.snapped and now - w.t0 >= MIN_WINDOW then
        snapWindow(bot, w)
    end
end
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
    local ____active_4, ____pid_5 = active, pid
    if ____active_4[____pid_5] == nil then
        ____active_4[____pid_5] = {}
    end
    local mine = active[pid]
    local now = DotaTime()
    trackWindow(bot, pid, now)
    local ____recent_7, ____pid_8 = recent, pid
    if ____recent_7[____pid_8] == nil then
        ____recent_7[____pid_8] = {}
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
                local ____opt_10 = wins[pid]
                if ____opt_10 ~= nil then
                    local ____opt_11 = wins[pid]
                    local ____temp_13 = ____opt_11 and ____opt_11.used
                    ____temp_13[#____temp_13 + 1] = t.item
                end
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
