--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- Seconds of eta a ranged or siege creep is preferred by (more gold and XP).
____exports.RANGED_BIAS = 0.4
--- Seconds of eta a last hit is preferred over a deny by (a core never gives up its last hit to deny).
____exports.LAST_HIT_BIAS = 0.3
--- Seconds a swing needs after the walk into range (wind-up plus a little) for the creep to still be alive when it lands.
-- A creep that dies to the others before walk + this is not offered (slice 5, probe s5p3: a third of the lost attempts
-- were creeps due now but more than a second's walk away, lost before the bot reached range). `judgement`.
____exports.ARRIVE_SLACK = 0.45
function ____exports.Choose(targets)
    local best
    local bestKey = math.huge
    for ____, t in ipairs(targets) do
        do
            local __continue3
            repeat
                if t.walk > 0 and t.walk + ____exports.ARRIVE_SLACK >= t.dies then
                    __continue3 = true
                    break
                end
                local key = t.eta - (t.ranged and ____exports.RANGED_BIAS or 0) - (t.kind == "lasthit" and ____exports.LAST_HIT_BIAS or 0)
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
