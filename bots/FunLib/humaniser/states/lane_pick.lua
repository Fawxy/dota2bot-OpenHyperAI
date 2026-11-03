--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- Seconds of eta a ranged or siege creep is preferred by (more gold and XP).
____exports.RANGED_BIAS = 0.4
--- Added to a deny's key so any last hit sorts before it.
local DENY_OFFSET = 1000
--- Seconds a swing needs after the walk into range (wind-up plus a little) for the creep to still be alive when it lands.
-- A creep that dies to the others before walk + this is not offered (slice 5, probe s5p3: a third of the lost attempts
-- were creeps due now but more than a second's walk away, lost before the bot reached range). `judgement`.
____exports.ARRIVE_SLACK = 0.45
--- A creep with eta at or under this is killable now (about one body step, 0.167 s in game). `judgement`.
____exports.DUE_NOW = 0.2
--- A waited-on creep due within this is kept: our swing at the other would not have landed before it is due, so the
-- attempt in hand is as good (about a hero's wind-up plus a frame). Beyond it the sure creep is taken and the waited-on
-- one is most likely lost to the attack cooldown, as it would have been the other way round (a certain last hit over a
-- probable one; in llhscn1 an attempt in hand landed 0.39 of the time). `judgement`.
____exports.SWITCH_GAP = 0.5
--- The pick, and while an attempt waits on `current` (slice lane-last-hits) whether to leave it: a creep killable now is
-- taken unless the current one is due within SWITCH_GAP; a last hit always replaces a deny (the strict priority); a deny
-- never replaces a last-hit wait. Lane-only calibration llhscn1 (03/11/2026): 71% of the creeps that died in a core's range
-- with no attempt died while the body waited on another creep that was still on offer.
function ____exports.Choose(targets, current)
    local best
    local bestKey = math.huge
    local cur
    for ____, t in ipairs(targets) do
        do
            local __continue3
            repeat
                if current ~= nil and t.creep == current.creep then
                    cur = t
                end
                if t.walk > 0 and t.walk + ____exports.ARRIVE_SLACK >= t.dies then
                    __continue3 = true
                    break
                end
                local key = t.eta - (t.ranged and ____exports.RANGED_BIAS or 0) + (t.kind == "lasthit" and 0 or DENY_OFFSET)
                if key < bestKey then
                    bestKey = key
                    best = t
                end
                __continue3 = true
            until true
            if not __continue3 then
                break
            end
        end
    end
    if cur == nil or best == nil or best.creep == cur.creep then
        return best
    end
    if cur.kind == "deny" and best.kind == "lasthit" then
        return best
    end
    if best.kind == "deny" then
        return cur
    end
    return best.eta <= ____exports.DUE_NOW and cur.eta >= ____exports.SWITCH_GAP and best or cur
end
--- How many of `targets` are reachable last hits and reachable denies (the reach rule above), and how many last hits other than `except`.
local function countOffers(targets, except)
    local lastHits = 0
    local denies = 0
    local otherLastHits = 0
    for ____, t in ipairs(targets) do
        do
            local __continue12
            repeat
                if t.walk > 0 and t.walk + ____exports.ARRIVE_SLACK >= t.dies then
                    __continue12 = true
                    break
                end
                if t.kind == "lasthit" then
                    lastHits = lastHits + 1
                    if except == nil or t.creep ~= except.creep then
                        otherLastHits = otherLastHits + 1
                    end
                else
                    denies = denies + 1
                end
                __continue12 = true
            until true
            if not __continue12 then
                break
            end
        end
    end
    return lastHits, denies, otherLastHits
end
--- The engine's `laneTargets`, handed over by humaniser/tasks once the bundle is loaded; telemetry never loads the bundle itself.
local offers
function ____exports.SetOffers(fn)
    offers = fn
end
--- What the bot could take right now, whoever plays its laning (slice lane-activity, both arms): reachable last hits and denies,
-- as the laning body would be offered them. Reads facts only (no skill roll). Undefined while the bundle is not loaded.
function ____exports.Options(bot)
    if offers == nil then
        return nil, nil
    end
    local lastHits, denies = countOffers(offers(bot))
    return lastHits, denies
end
--- A support's pick (slice l1-support-deny, user rule 02/11/2026): denies only, the reachable one with the earliest eta (ranged
-- bias as Choose); the last hits laneTargets offers are left to OHA's own last-hit step.
function ____exports.ChooseDeny(targets)
    local best
    local bestKey = math.huge
    for ____, t in ipairs(targets) do
        do
            local __continue22
            repeat
                if t.kind ~= "deny" or t.walk > 0 and t.walk + ____exports.ARRIVE_SLACK >= t.dies then
                    __continue22 = true
                    break
                end
                local key = t.eta - (t.ranged and ____exports.RANGED_BIAS or 0)
                if key < bestKey then
                    bestKey = key
                    best = t
                end
                __continue22 = true
            until true
            if not __continue22 then
                break
            end
        end
    end
    return best
end
local scans = {}
local function scanOf(pid)
    local s = scans[pid]
    if s == nil then
        s = {}
        scans[pid] = s
    end
    return s
end
function ____exports.NotePhase(pid, ph)
    scanOf(pid).ph = ph
end
function ____exports.NoteScan(pid, now, aw)
    local s = scanOf(pid)
    s.scanAt = now
    s.aw = aw
end
function ____exports.NotePick(pid, now, targets, chosen)
    local s = scanOf(pid)
    s.pickAt = now
    s.n = #targets
    local sk = 0
    for ____, t in ipairs(targets) do
        if t.walk > 0 and t.walk + ____exports.ARRIVE_SLACK >= t.dies then
            sk = sk + 1
        end
    end
    s.sk = sk
    s.ch = chosen ~= nil
    if chosen ~= nil then
        local lastHits, denies = countOffers(targets)
        if s.chosen ~= nil and (s.ph == "lasthit" or s.ph == "deny") then
            s.next = {chosen = chosen, lastHits = lastHits, denies = denies}
        else
            s.next = nil
            s.chosen = chosen
            s.pickLastHits = lastHits
            s.pickDenies = denies
            s.seen = 0
        end
    end
end
--- While an attempt waits (the body's scan, every 0.1 s): the most last hits other than its creep on offer, so a deny's cost can be read.
function ____exports.NoteWait(bot)
    local s = scans[bot:GetPlayerID()]
    if s == nil or s.chosen == nil or offers == nil then
        return
    end
    if s.ph ~= "lasthit" and s.ph ~= "deny" then
        return
    end
    local ____, ____, others = countOffers(
        offers(bot),
        s.chosen
    )
    if others > (s.seen or 0) then
        s.seen = others
    end
end
--- ev=lh's offer fields for the attempt that just ended: last hits and denies offered at its pick, most other last hits seen during
-- it. Call once per attempt: it then moves on to the pick a retarget held back.
function ____exports.AttemptOffers(pid)
    local s = scans[pid]
    if s == nil then
        return nil, nil, nil
    end
    local lastHits = s.pickLastHits
    local denies = s.pickDenies
    local seen = s.seen
    if s.next ~= nil then
        s.chosen = s.next.chosen
        s.pickLastHits = s.next.lastHits
        s.pickDenies = s.next.denies
        s.seen = 0
        s.next = nil
    end
    return lastHits, denies, seen
end
--- `ph=hold sc=0.1 aw=340 pk=2.3 n=2 sk=1 ch=0`: ages in s since the last scan and the last pick; undefined before any.
function ____exports.Describe(pid, now)
    local s = scans[pid]
    if s == nil then
        return nil
    end
    local function age(t)
        return t == nil and "-" or string.format("%.1f", now - t)
    end
    return string.format(
        "ph=%s sc=%s aw=%s pk=%s n=%s sk=%s ch=%s",
        s.ph or "-",
        age(s.scanAt),
        s.aw == nil and "-" or tostring(math.floor(s.aw)),
        age(s.pickAt),
        tostring(s.n or "-"),
        tostring(s.sk or "-"),
        s.ch == nil and "-" or (s.ch and "1" or "0")
    )
end
return ____exports
