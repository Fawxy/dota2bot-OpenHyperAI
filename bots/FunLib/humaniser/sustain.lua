--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____retreat = require(GetScriptDirectory().."/FunLib/humaniser/retreat")
local RetreatSettings = ____retreat.SETTINGS
local ____safe = require(GetScriptDirectory().."/FunLib/humaniser/safe")
local SafeBars = ____safe.BARS
--- Every number the decision owns, with its source. The kill line's floor (`HealFloor`) and `HealUntil` are retreat's, its bar (`stay`) the safe-here read's: read at call time, not copied.
____exports.BARS = {topUp = 0.65, mana = 0.4, castSlack = 0.5, idleWalk = 8}
--- An instant HP item: kept for rule 1, never spent topping up.
local function reserved(it)
    return it.dur == 0 and it.hp > 0
end
--- Rule 2's tree (user 19/11/2026): the walk is a cost against the trip, so a tango counts when its walk is safe and there and back is shorter than home.
local function treeReach(i)
    return i.tree ~= nil and i.tree.safe and 2 * i.tree.walk < i.home
end
--- Rule 3's tree: a safe walk there and back that ends before the next hit is due (no last hit or deny missed); with none due, or between jobs, a short walk.
local function treeNow(i)
    if i.tree == nil or not i.tree.safe or i.tree.start == false then
        return false
    end
    local trip = 2 * i.tree.walk
    if i.nextDue ~= nil and not i.idle then
        return trip + ____exports.BARS.castSlack <= i.nextDue
    end
    return trip <= ____exports.BARS.idleWalk
end
--- Whether a use counts in what we reach: a tree item with a tree worth its walk, an item hero damage ends with a safe spot to use it at.
local function counts(i, it)
    if it.charges <= 0 then
        return false
    end
    if it.tree then
        return treeReach(i)
    end
    if it.breaks and it.dur > 0 then
        return i.safeSpot ~= nil
    end
    return true
end
--- Whether one use can start now: castable, and a tree item's walk fits before the next hit.
local function usable(i, it)
    if it.ready == false or not counts(i, it) then
        return false
    end
    return not it.tree or treeNow(i)
end
--- HP under which this place is `deadly` by the safe-here read's own bar (Stay x kill), so sustain and retreat send a hero
-- home on one line; never under the heal floor (sustain's own going-home floor) and never over max HP (a lane that can kill
-- a full hero would otherwise send one home from the fountain; that place is retreat's answer).
function ____exports.KillLine(i)
    return math.min(
        i.hpMax,
        math.max(RetreatSettings.HealFloor * i.hpMax, SafeBars.stay * i.safe.kill)
    )
end
--- HP plus what the regen running and the items in hand can restore, capped at max HP.
function ____exports.Reachable(i)
    local r = i.hp + i.regenLeft
    for ____, it in ipairs(i.items) do
        if it.hp > 0 and counts(i, it) then
            r = r + it.hp * it.charges
        end
    end
    return math.min(r, i.hpMax)
end
local function topLine(i, kill)
    return math.max(____exports.BARS.topUp * i.hpMax, kill)
end
local function manaLow(i)
    return i.mpMax > 0 and i.mp < ____exports.BARS.mana * i.mpMax
end
--- The purchase for `need` HP the gold covers: the largest that does not overshoot, else the smallest that covers it.
local function pickHp(i, need)
    local under
    local over
    for ____, o in ipairs(i.shop) do
        do
            local __continue21
            repeat
                if o.hp <= 0 or o.cost > i.gold then
                    __continue21 = true
                    break
                end
                if o.hp <= need then
                    if under == nil or o.hp > under.hp then
                        under = o
                    end
                elseif over == nil or o.hp < over.hp then
                    over = o
                end
                __continue21 = true
            until true
            if not __continue21 then
                break
            end
        end
    end
    return under or over
end
--- The cheapest purchase the gold covers that restores at least `need` HP.
local function pickCover(i, need)
    local best
    for ____, o in ipairs(i.shop) do
        if o.hp >= need and o.cost <= i.gold and (best == nil or o.cost < best.cost) then
            best = o
        end
    end
    return best
end
local function pickMp(i)
    local best
    for ____, o in ipairs(i.shop) do
        if o.mp > 0 and o.cost <= i.gold and (best == nil or o.cost < best.cost) then
            best = o
        end
    end
    return best
end
local function use(it, reason)
    return {kind = "use", slot = it.slot, name = it.name, reason = reason}
end
--- Rule 1: a hero in reach is hitting us, what the reachers can deal kills us, and an instant item (the most restored first) lifts us over it.
local function survive(i)
    if not i.safe.hitting or i.hp >= i.safe.kill then
        return nil
    end
    local best
    for ____, it in ipairs(i.items) do
        if reserved(it) and it.charges > 0 and it.ready ~= false and (best == nil or it.hp > best.hp) then
            best = it
        end
    end
    if best ~= nil and i.hp + best.hp >= i.safe.kill then
        return use(best, "survive")
    end
    return nil
end
--- Rule 2: what the items reach is under the kill line. Low on HP and mana goes home at once; else a delivery that lifts us over it, waited for at a safe spot, if it comes sooner than the trip; else home. Nothing is spent.
local function cannotStay(i, kill)
    local reach = ____exports.Reachable(i)
    if reach >= kill then
        return nil
    end
    if manaLow(i) then
        return {kind = "home", reason = "low_both"}
    end
    local o = pickCover(i, kill - reach)
    if o ~= nil and i.courier ~= nil and i.courier.eta < i.home and i.safeSpot ~= nil then
        return {kind = "buy", name = o.name, at = {x = i.safeSpot.x, y = i.safeSpot.y}, reason = "cannot_stay"}
    end
    return {kind = "home", reason = "cannot_stay"}
end
--- Rule 3: under the top-up line, or in an idle window, with no regen running and the missing HP covering one use. A
-- refilling item first, then a tree item, then one hero damage ends, used at a safe spot. Only an item hero damage ends
-- waits out a recent hit or a hero in reach (D6: a tango ticks through damage; a step-out ends `interrupted` on reach).
local function topUp(i, kill)
    if i.regenLeft > 0 then
        return nil
    end
    if i.hp >= topLine(i, kill) and not i.idle then
        return nil
    end
    local missing = i.hpMax - i.hp
    local function order(it)
        return it.refill and 0 or (it.tree and 1 or 2)
    end
    local best
    for ____, it in ipairs(i.items) do
        do
            local __continue50
            repeat
                if reserved(it) or it.hp <= 0 or it.charges <= 0 or missing < it.hp or not usable(i, it) then
                    __continue50 = true
                    break
                end
                if it.breaks and (i.hitRecently or i.safe.reach > 0) then
                    __continue50 = true
                    break
                end
                if best == nil or order(it) < order(best) then
                    best = it
                end
                __continue50 = true
            until true
            if not __continue50 then
                break
            end
        end
    end
    if best == nil then
        return nil
    end
    if best.breaks and best.dur > 0 and i.safeSpot ~= nil and i.safeSpot.walk > 0 then
        return {
            kind = "step_out_use",
            slot = best.slot,
            name = best.name,
            at = {x = i.safeSpot.x, y = i.safeSpot.y},
            reason = "top_up"
        }
    end
    return use(best, "top_up")
end
--- Rule 4: mana low, no regen running (one at a time), the missing mana covering one use; a refilling item first.
local function mana(i)
    if not manaLow(i) or i.manaLeft > 0 or i.regenLeft > 0 then
        return nil
    end
    local missing = i.mpMax - i.mp
    local best
    for ____, it in ipairs(i.items) do
        do
            local __continue59
            repeat
                if reserved(it) or it.mp <= 0 or it.charges <= 0 or it.ready == false or missing < it.mp then
                    __continue59 = true
                    break
                end
                if it.breaks and (i.hitRecently or i.safe.reach > 0) then
                    __continue59 = true
                    break
                end
                if best == nil or it.refill and not best.refill then
                    best = it
                end
                __continue59 = true
            until true
            if not __continue59 then
                break
            end
        end
    end
    return best ~= nil and use(best, "mana") or nil
end
--- Rule 5: no heal item in hand under the top-up line (or no mana item with mana low), and the courier free: buy.
local function buyAhead(i, kill)
    if i.courier == nil then
        return nil
    end
    local heals = false
    local manas = false
    for ____, it in ipairs(i.items) do
        do
            local __continue66
            repeat
                if it.charges <= 0 or reserved(it) then
                    __continue66 = true
                    break
                end
                if it.hp > 0 then
                    heals = true
                end
                if it.mp > 0 then
                    manas = true
                end
                __continue66 = true
            until true
            if not __continue66 then
                break
            end
        end
    end
    if not heals and i.hp < topLine(i, kill) then
        local o = pickHp(i, i.hpMax - i.hp)
        if o ~= nil then
            return {kind = "buy", name = o.name, reason = "buy_hp"}
        end
    end
    if not manas and manaLow(i) then
        local o = pickMp(i)
        if o ~= nil then
            return {kind = "buy", name = o.name, reason = "buy_mana"}
        end
    end
    return nil
end
--- Rule 6: an ally with no heal item misses one use's worth, and we hold two uses or more of an item we can give.
local function give(i)
    for ____, it in ipairs(i.items) do
        do
            local __continue76
            repeat
                if not it.share or it.charges < 2 or it.ready == false then
                    __continue76 = true
                    break
                end
                for ____, a in ipairs(i.allies) do
                    if a.heals == 0 and a.missing >= it.hp then
                        return {
                            kind = "give",
                            slot = it.slot,
                            name = it.name,
                            to = a.pid,
                            reason = "give"
                        }
                    end
                end
                __continue76 = true
            until true
            if not __continue76 then
                break
            end
        end
    end
    return nil
end
--- Why a running answer ends this frame, if it does.
local function ends(i, r, kill)
    if r.kind == "step_out_use" then
        if i.safe.reach > 0 then
            return "interrupted"
        end
        if i.hp >= topLine(i, kill) then
            return "topped"
        end
        if i.now - r.started >= (r.dur or 0) then
            return "done"
        end
        return nil
    end
    if r.kind == "home" then
        return i.atFountain and i.hp >= RetreatSettings.HealUntil * i.hpMax and "healed" or nil
    end
    return "done"
end
local function fresh(i, kill)
    return cannotStay(i, kill) or topUp(i, kill) or mana(i) or buyAhead(i, kill) or give(i) or ({kind = "none", reason = "fine"})
end
function ____exports.Decide(i)
    local s = survive(i)
    if s ~= nil then
        return s
    end
    local kill = ____exports.KillLine(i)
    local r = i.run
    if r == nil then
        return fresh(i, kill)
    end
    local why = ends(i, r, kill)
    if why == nil then
        return {
            kind = r.kind,
            slot = r.slot,
            name = r.name,
            at = r.at,
            reason = "running"
        }
    end
    local a = fresh(i, kill)
    a.ended = why
    return a
end
return ____exports
