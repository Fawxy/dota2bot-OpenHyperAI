--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__StringIncludes(self, searchString, position)
    if not position then
        position = 1
    else
        position = position + 1
    end
    local index = string.find(self, searchString, position, true)
    return index ~= nil
end

local function __TS__New(target, ...)
    local instance = setmetatable({}, target.prototype)
    instance:____constructor(...)
    return instance
end

local function __TS__Class(self)
    local c = {prototype = {}}
    c.prototype.__index = c.prototype
    c.prototype.constructor = c
    return c
end

local function __TS__ClassExtends(target, base)
    target.____super = base
    local staticMetatable = setmetatable({__index = base}, base)
    setmetatable(target, staticMetatable)
    local baseMetatable = getmetatable(base)
    if baseMetatable then
        if type(baseMetatable.__index) == "function" then
            staticMetatable.__index = baseMetatable.__index
        end
        if type(baseMetatable.__newindex) == "function" then
            staticMetatable.__newindex = baseMetatable.__newindex
        end
    end
    setmetatable(target.prototype, base.prototype)
    if type(base.prototype.__index) == "function" then
        target.prototype.__index = base.prototype.__index
    end
    if type(base.prototype.__newindex) == "function" then
        target.prototype.__newindex = base.prototype.__newindex
    end
    if type(base.prototype.__tostring) == "function" then
        target.prototype.__tostring = base.prototype.__tostring
    end
end

local Error, RangeError, ReferenceError, SyntaxError, TypeError, URIError
do
    local function getErrorStack(self, constructor)
        if debug == nil then
            return nil
        end
        local level = 1
        while true do
            local info = debug.getinfo(level, "f")
            level = level + 1
            if not info then
                level = 1
                break
            elseif info.func == constructor then
                break
            end
        end
        if __TS__StringIncludes(_VERSION, "Lua 5.0") then
            return debug.traceback(("[Level " .. tostring(level)) .. "]")
        else
            return debug.traceback(nil, level)
        end
    end
    local function wrapErrorToString(self, getDescription)
        return function(self)
            local description = getDescription(self)
            local caller = debug.getinfo(3, "f")
            local isClassicLua = __TS__StringIncludes(_VERSION, "Lua 5.0") or _VERSION == "Lua 5.1"
            if isClassicLua or caller and caller.func ~= error then
                return description
            else
                return (description .. "\n") .. tostring(self.stack)
            end
        end
    end
    local function initErrorClass(self, Type, name)
        Type.name = name
        return setmetatable(
            Type,
            {__call = function(____, _self, message) return __TS__New(Type, message) end}
        )
    end
    local ____initErrorClass_1 = initErrorClass
    local ____class_0 = __TS__Class()
    ____class_0.name = ""
    function ____class_0.prototype.____constructor(self, message)
        if message == nil then
            message = ""
        end
        self.message = message
        self.name = "Error"
        self.stack = getErrorStack(nil, self.constructor.new)
        local metatable = getmetatable(self)
        if metatable and not metatable.__errorToStringPatched then
            metatable.__errorToStringPatched = true
            metatable.__tostring = wrapErrorToString(nil, metatable.__tostring)
        end
    end
    function ____class_0.prototype.__tostring(self)
        return self.message ~= "" and (self.name .. ": ") .. self.message or self.name
    end
    Error = ____initErrorClass_1(nil, ____class_0, "Error")
    local function createErrorClass(self, name)
        local ____initErrorClass_3 = initErrorClass
        local ____class_2 = __TS__Class()
        ____class_2.name = ____class_2.name
        __TS__ClassExtends(____class_2, Error)
        function ____class_2.prototype.____constructor(self, ...)
            ____class_2.____super.prototype.____constructor(self, ...)
            self.name = name
        end
        return ____initErrorClass_3(nil, ____class_2, name)
    end
    RangeError = createErrorClass(nil, "RangeError")
    ReferenceError = createErrorClass(nil, "ReferenceError")
    SyntaxError = createErrorClass(nil, "SyntaxError")
    TypeError = createErrorClass(nil, "TypeError")
    URIError = createErrorClass(nil, "URIError")
end

local function __TS__ObjectGetOwnPropertyDescriptors(object)
    local metatable = getmetatable(object)
    if not metatable then
        return {}
    end
    return rawget(metatable, "_descriptors") or ({})
end

local function __TS__Delete(target, key)
    local descriptors = __TS__ObjectGetOwnPropertyDescriptors(target)
    local descriptor = descriptors[key]
    if descriptor then
        if not descriptor.configurable then
            error(
                __TS__New(
                    TypeError,
                    ((("Cannot delete property " .. tostring(key)) .. " of ") .. tostring(target)) .. "."
                ),
                0
            )
        end
        descriptors[key] = nil
        return true
    end
    target[key] = nil
    return true
end
-- End of Lua Library inline imports
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local DamageType = ____dota.DamageType
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local SpellReady = require(GetScriptDirectory().."/FunLib/humaniser/spell_ready")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {
    PokeWindow = 3,
    CommitWindow = 4,
    SecondGap = 1,
    ReactWindow = 1,
    NearHorizon = 2,
    Keep = 6,
    SumEvery = 60,
    ShapeLines = 3
}
local MAX_PLAYER_ID = 23
--- The hit evidence's state of one enemy: `committed`, `poked`, or undefined (no damage within `PokeWindow`). `pokers`: how many enemy heroes damaged us within `PokeWindow`, this one included.
function ____exports.HitState(hits, now, pokers)
    local last = -math.huge
    local first = math.huge
    for ____, t in ipairs(hits) do
        do
            local __continue3
            repeat
                if t > now or now - t > ____exports.SETTINGS.CommitWindow then
                    __continue3 = true
                    break
                end
                if t > last then
                    last = t
                end
                if t < first then
                    first = t
                end
                __continue3 = true
            until true
            if not __continue3 then
                break
            end
        end
    end
    if now - last > ____exports.SETTINGS.PokeWindow then
        return {st = nil}
    end
    if last - first >= ____exports.SETTINGS.SecondGap then
        return {st = "committed", why = "second"}
    end
    if pokers >= 2 then
        return {st = "committed", why = "pair"}
    end
    return {st = "poked", why = "hit"}
end
--- Every enemy's state towards one hero from its hit times (`hitsBy` by enemy pid) and which enemies are near: hit evidence first, then `near`, else `gone`.
function ____exports.States(hitsBy, near, now)
    local pokers = 0
    for ____, hits in pairs(hitsBy) do
        for ____, t in ipairs(hits) do
            if t <= now and now - t <= ____exports.SETTINGS.PokeWindow then
                pokers = pokers + 1
                break
            end
        end
    end
    local out = {}
    for epid, hits in pairs(hitsBy) do
        local h = ____exports.HitState(hits, now, pokers)
        if h.st ~= nil then
            out[epid] = {st = h.st, why = h.why}
        end
    end
    for epid, on in pairs(near) do
        if on and out[epid] == nil then
            out[epid] = {st = "near", why = "reach"}
        end
    end
    return out
end
--- Ready spells' part of an enemy's damage on us over the reaction window, and one attack: `DamageOn` less its attack part, floored at 0.
function ____exports.SplitBurst(total, attackOverWindow, oneAttack)
    return {
        spell = math.max(0, total - attackOverWindow),
        attack = math.max(0, oneAttack)
    }
end
local function isHandle(a)
    return type(a) == "table" and a.GetUnitName ~= nil
end
function ____exports.ParseArgs(args)
    local out = {}
    local units = {}
    do
        local i = 0
        while i < 4 do
            local a = args[i + 1]
            if isHandle(a) then
                units[#units + 1] = a
            elseif type(a) == "number" and out.dmg == nil then
                out.dmg = a
            elseif type(a) == "table" then
                local t = a
                for ____, k in ipairs({"damage", "nDamage", "amount"}) do
                    if type(t[k]) == "number" and out.dmg == nil then
                        out.dmg = t[k]
                    end
                end
                for ____, k in ipairs({"attacking_player_id", "attacker_player_id"}) do
                    if type(t[k]) == "number" and out.attackerPid == nil then
                        out.attackerPid = t[k]
                    end
                end
                for ____, k in ipairs({"unit", "victim", "target"}) do
                    if isHandle(t[k]) and out.victim == nil then
                        out.victim = t[k]
                    end
                end
                for ____, k in ipairs({"attacking_unit", "attacker", "source"}) do
                    if isHandle(t[k]) and out.attacker == nil then
                        out.attacker = t[k]
                    end
                end
            end
            i = i + 1
        end
    end
    if #units >= 2 then
        out.victim = out.victim or units[1]
        out.attacker = out.attacker or units[2]
    elseif #units == 1 then
        if out.victim == nil then
            out.victim = units[1]
        elseif out.attacker == nil then
            out.attacker = units[1]
        end
    end
    return out
end
--- The (our hero's pid, enemy hero's pid) a parsed event is, or undefined (an attacker that is not an enemy hero, or none named).
function ____exports.Resolve(p, ours, teamOf)
    local v = p.victim
    if v == nil or not v:IsHero() or v:IsIllusion() or v:GetTeam() ~= ours then
        return nil
    end
    local apid = p.attackerPid
    if p.attacker ~= nil then
        if not p.attacker:IsHero() or p.attacker:IsIllusion() then
            return nil
        end
        apid = p.attacker:GetPlayerID()
    end
    if apid == nil or apid < 0 then
        return nil
    end
    local at = teamOf(apid)
    if at == ours or at ~= Team.Radiant and at ~= Team.Dire then
        return nil
    end
    return {
        victim = v:GetPlayerID(),
        attacker = apid
    }
end
local cbHits = {}
local pollHits = {}
local cbLive = false
local installedAll = false
local shapes = 0
local counts = {n = 0, ok = 0, cb = 0, poll = 0}
local sumAt
local lastPoll = {}
local current = {}
local function push(store, victim, attacker, t)
    local by = store[victim] or ({})
    store[victim] = by
    local list = by[attacker] or ({})
    local keep = {}
    for ____, x in ipairs(list) do
        if t - x <= ____exports.SETTINGS.Keep then
            keep[#keep + 1] = x
        end
    end
    keep[#keep + 1] = t
    by[attacker] = keep
end
local function describe(args)
    local parts = {}
    do
        local i = 0
        while i < 4 do
            local a = args[i + 1]
            if isHandle(a) then
                local u = a
                parts[#parts + 1] = (("h:" .. u:GetUnitName()) .. ":") .. tostring(u:GetPlayerID())
            elseif type(a) == "table" then
                local keys = {}
                for k, v in pairs(a) do
                    keys[#keys + 1] = (tostring(k) .. "=") .. (isHandle(v) and "h" or ((type(v) == "number" or type(v) == "string") and tostring(v) or type(v)))
                end
                parts[#parts + 1] = ("{" .. table.concat(keys, ",")) .. "}"
            else
                parts[#parts + 1] = type(a) == "number" and "n:" .. tostring(a) or type(a)
            end
            i = i + 1
        end
    end
    return table.concat(parts, "|")
end
local function onDamage(installed, args)
    counts.n = counts.n + 1
    local r = ____exports.Resolve(
        ____exports.ParseArgs(args),
        GetTeam(),
        GetTeamForPlayer
    )
    if shapes < ____exports.SETTINGS.ShapeLines then
        shapes = shapes + 1
        Telemetry.Event(
            "dmgcb",
            {
                {"kind", "shape"},
                {"ipid", installed},
                {"ok", r ~= nil and 1 or 0},
                {
                    "args",
                    describe(args)
                }
            }
        )
    end
    if r == nil then
        return
    end
    counts.ok = counts.ok + 1
    counts.cb = counts.cb + 1
    cbLive = true
    push(
        cbHits,
        r.victim,
        r.attacker,
        DotaTime()
    )
end
--- InstallDamageCallback on each of our heroes' player ids (it reports the damage that hero takes), once per team VM.
local function install()
    if installedAll then
        return
    end
    installedAll = true
    local g = _G
    if type(g.InstallDamageCallback) ~= "function" then
        Telemetry.Event("dmgcb", {{"kind", "missing"}})
        return
    end
    local installDamage = g.InstallDamageCallback
    local n = 0
    do
        local pid = 0
        while pid <= MAX_PLAYER_ID do
            do
                local __continue65
                repeat
                    local t = GetTeamForPlayer(pid)
                    if t ~= GetTeam() then
                        __continue65 = true
                        break
                    end
                    local ipid = pid
                    installDamage(
                        ipid,
                        function(...)
                            local args = {...}
                            local ok, err = pcall(onDamage, ipid, args)
                            if not ok then
                                Telemetry.Failed("Commit.onDamage", err)
                            end
                        end
                    )
                    n = n + 1
                    __continue65 = true
                until true
                if not __continue65 then
                    break
                end
            end
            pid = pid + 1
        end
    end
    Telemetry.Event("dmgcb", {{"kind", "installed"}, {"n", n}})
end
local function r0(v)
    return math.floor(v + 0.5)
end
local function burstOn(e, bot)
    local w = ____exports.SETTINGS.ReactWindow
    local total = SpellReady.DamageOn(e, bot, w)
    local ____this_1
    ____this_1 = e
    local ____opt_0 = ____this_1.GetSecondsPerAttack
    local spa = ____opt_0 and ____opt_0(____this_1) or 0
    local one = bot:GetActualIncomingDamage(
        e:GetAttackDamage(),
        DamageType.Physical
    )
    return ____exports.SplitBurst(total, spa > 0 and one * w / spa or 0, one)
end
--- Our hero's view of one enemy as last ticked (`rc` on the safe cut): `n` near, `p` poked, `c` committed, `-` gone or never seen.
function ____exports.Code(ourPid, epid)
    local ____opt_2 = current[ourPid]
    local st = ____opt_2 and ____opt_2[epid]
    return st == "near" and "n" or (st == "poked" and "p" or (st == "committed" and "c" or "-"))
end
--- The tracker's step, once per hero per Humaniser tick (10 Hz): installs the callback, polls the damage flags, and logs each enemy's
-- state change towards `bot` as `ev=commit`. A lower rate loses the poll's hit times (a 1 s gap between two hits needs a few samples a
-- second) and delays a transition's line. Nothing reads the state but `Code` (a log column).
function ____exports.Tick(bot)
    if not Ours.On("PricedLeave") then
        return
    end
    install()
    local now = DotaTime()
    if sumAt == nil then
        sumAt = now + ____exports.SETTINGS.SumEvery
    elseif now >= sumAt then
        sumAt = now + ____exports.SETTINGS.SumEvery
        Telemetry.Event("dmgcb", {
            {"kind", "sum"},
            {"n", counts.n},
            {"ok", counts.ok},
            {"cb", counts.cb},
            {"poll", counts.poll},
            {"live", cbLive and 1 or 0}
        })
        counts.n = 0
        counts.ok = 0
        counts.cb = 0
        counts.poll = 0
    end
    local pid = bot:GetPlayerID()
    local prev = current[pid] or ({})
    if not bot:IsAlive() then
        current[pid] = {}
        lastPoll[pid] = nil
        return
    end
    local since = lastPoll[pid]
    local w = since == nil and 0.1 or math.max(
        0.1,
        math.min(0.5, now - since)
    )
    lastPoll[pid] = now
    local at = bot:GetLocation()
    local near = {}
    local handles = {}
    for ____, e in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue77
            repeat
                if e:IsIllusion() or not e:IsAlive() then
                    __continue77 = true
                    break
                end
                local epid = e:GetPlayerID()
                handles[epid] = e
                if bot:WasRecentlyDamagedByHero(e, w) then
                    counts.poll = counts.poll + 1
                    push(pollHits, pid, epid, now)
                end
                local l = e:GetLocation()
                local d = math.sqrt((l.x - at.x) ^ 2 + (l.y - at.y) ^ 2)
                local reach = e:GetAttackRange() + e:GetCurrentMovementSpeed() * ____exports.SETTINGS.NearHorizon + e:GetBoundingRadius() + bot:GetBoundingRadius()
                near[epid] = d <= reach
                __continue77 = true
            until true
            if not __continue77 then
                break
            end
        end
    end
    local src = cbLive and "cb" or "poll"
    local states = ____exports.States((cbLive and cbHits or pollHits)[pid] or ({}), near, now)
    local next = {}
    local changed = false
    for epid, s in pairs(states) do
        do
            local __continue81
            repeat
                if handles[epid] == nil then
                    __continue81 = true
                    break
                end
                next[epid] = s.st
                if prev[epid] ~= s.st then
                    changed = true
                end
                __continue81 = true
            until true
            if not __continue81 then
                break
            end
        end
    end
    for epid in pairs(prev) do
        if next[epid] == nil then
            changed = true
        end
    end
    current[pid] = next
    if not changed or not Telemetry.IsEnabled() then
        return
    end
    local burst = {}
    local sum = 0
    for epid, st in pairs(next) do
        do
            local __continue87
            repeat
                if st == "gone" then
                    __continue87 = true
                    break
                end
                local b = burstOn(handles[epid], bot)
                burst[epid] = b
                sum = sum + (b.spell + b.attack)
                __continue87 = true
            until true
            if not __continue87 then
                break
            end
        end
    end
    local hp = bot:GetHealth()
    local byPid = (cbLive and cbHits or pollHits)[pid] or ({})
    local function emit(epid, st, was, why)
        local hits = 0
        for ____, t in ipairs(byPid[epid] or ({})) do
            if now - t <= ____exports.SETTINGS.CommitWindow then
                hits = hits + 1
            end
        end
        local b = burst[epid]
        Telemetry.Event(
            "commit",
            {
                {"pid", pid},
                {"epid", epid},
                {"st", st},
                {"was", was},
                {"why", why},
                {"hits", hits},
                {"src", src},
                {"hp", hp},
                {
                    "bs",
                    b ~= nil and r0(b.spell) or nil
                },
                {
                    "ba",
                    b ~= nil and r0(b.attack) or nil
                },
                {
                    "bsum",
                    r0(sum)
                },
                {
                    "bra",
                    sum > 0 and math.floor(hp / sum * 100 + 0.5) / 100 or nil
                }
            }
        )
    end
    for epid, st in pairs(next) do
        local was = prev[epid] or "gone"
        if was ~= st then
            emit(epid, st, was, states[epid].why)
        end
    end
    for epid, was in pairs(prev) do
        if next[epid] == nil then
            emit(epid, "gone", was, handles[epid] == nil and "lost" or "left")
        end
    end
end
--- Tests: forget every hit, state and the install.
function ____exports.Reset()
    for k in pairs(cbHits) do
        __TS__Delete(cbHits, k)
    end
    for k in pairs(pollHits) do
        __TS__Delete(pollHits, k)
    end
    for k in pairs(current) do
        __TS__Delete(current, k)
    end
    for k in pairs(lastPoll) do
        __TS__Delete(lastPoll, k)
    end
    cbLive = false
    installedAll = false
    shapes = 0
    sumAt = nil
    counts.n = 0
    counts.ok = 0
    counts.cb = 0
    counts.poll = 0
end
return ____exports
