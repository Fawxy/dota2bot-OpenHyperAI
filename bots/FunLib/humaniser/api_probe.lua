--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__CountVarargs(...)
    return select("#", ...)
end

local function __TS__SparseArrayNew(...)
    local sparseArray = {...}
    sparseArray.sparseLength = __TS__CountVarargs(...)
    return sparseArray
end

local function __TS__SparseArrayPush(sparseArray, ...)
    local args = {...}
    local argsLen = __TS__CountVarargs(...)
    local listLen = sparseArray.sparseLength
    for i = 1, argsLen do
        sparseArray[listLen + i] = args[i]
    end
    sparseArray.sparseLength = listLen + argsLen
end

local function __TS__SparseArraySpread(sparseArray)
    local _unpack = unpack or table.unpack
    return _unpack(sparseArray, 1, sparseArray.sparseLength)
end

local function __TS__ArrayMap(self, callbackfn, thisArg)
    local result = {}
    for i = 1, #self do
        result[i] = callbackfn(thisArg, self[i], i - 1, self)
    end
    return result
end
-- End of Lua Library inline imports
local ____exports = {}
local num, round, abilityRows, estRow, nearestOf, nearestOwn, nearestEnemy, NIL, ERR, EST_WINDOW, ALL_DAMAGE, ABILITY_REPEAT, lastAbility
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function num(u, read)
    local ok, v = pcall(read, u)
    if not ok then
        return ERR
    end
    if v == nil or v == nil then
        return NIL
    end
    if type(v) == "boolean" then
        return v == true and 1 or 0
    end
    return type(v) == "number" and v or NIL
end
function round(v)
    return v < 0 and v or math.floor(v * 10 + 0.5) / 10
end
function abilityRows(team, pid, own, h)
    local u = h
    local ____temp_3
    if own == 1 then
        ____temp_3 = nearestEnemy(h)
    else
        ____temp_3 = nearestOwn(h)
    end
    local target = ____temp_3
    local now = DotaTime()
    do
        local slot = 0
        while slot <= 5 do
            do
                local __continue76
                repeat
                    local okA, a = pcall(function() return u:GetAbilityInSlot(slot) end)
                    if not okA or a == nil or a == nil then
                        __continue76 = true
                        break
                    end
                    local ab = a
                    local okN, name = pcall(function() return ab:GetName() end)
                    if not okN or type(name) ~= "string" or name == "generic_hidden" then
                        __continue76 = true
                        break
                    end
                    if num(
                        h,
                        function() return ab:IsHidden() end
                    ) == 1 then
                        __continue76 = true
                        break
                    end
                    local ____array_5 = __TS__SparseArrayNew(
                        {
                            "lvl",
                            num(
                                h,
                                function() return ab:GetLevel() end
                            )
                        },
                        {
                            "rdy",
                            num(
                                h,
                                function() return ab:IsCooldownReady() end
                            )
                        },
                        {
                            "fc",
                            num(
                                h,
                                function() return ab:IsFullyCastable() end
                            )
                        },
                        {
                            "mok",
                            num(
                                h,
                                function() return ab:IsOwnersManaEnough() end
                            )
                        },
                        {
                            "rem",
                            round(num(
                                h,
                                function() return ab:GetCooldownTimeRemaining() end
                            ))
                        },
                        {
                            "cd",
                            round(num(
                                h,
                                function() return ab:GetCooldown() end
                            ))
                        },
                        {
                            "scd",
                            round(num(
                                h,
                                function() return ab:GetSpecialValueFloat("AbilityCooldown") end
                            ))
                        },
                        {
                            "dmg",
                            round(num(
                                h,
                                function() return ab:GetAbilityDamage() end
                            ))
                        },
                        {
                            "mc",
                            round(num(
                                h,
                                function() return ab:GetManaCost() end
                            ))
                        }
                    )
                    local ____temp_4
                    if target == nil then
                        ____temp_4 = nil
                    else
                        ____temp_4 = round(num(
                            h,
                            function() return ab:GetEstimatedDamageToTarget(target, EST_WINDOW, ALL_DAMAGE) end
                        ))
                    end
                    __TS__SparseArrayPush(____array_5, {"aest", ____temp_4})
                    local fields = {__TS__SparseArraySpread(____array_5)}
                    local sig = table.concat(
                        __TS__ArrayMap(
                            fields,
                            function(____, ____bindingPattern0)
                                local v
                                local k
                                k = ____bindingPattern0[1]
                                v = ____bindingPattern0[2]
                                return k == "rem" and (v > 0 and "+" or tostring(v)) or (k == "aest" and "" or tostring(v))
                            end
                        ),
                        ","
                    )
                    local key = (((tostring(team) .. ":") .. tostring(pid)) .. ":") .. tostring(slot)
                    local last = lastAbility[key]
                    if last ~= nil and last.sig == sig and now - last.at < ABILITY_REPEAT then
                        __continue76 = true
                        break
                    end
                    lastAbility[key] = {sig = sig, at = now}
                    Telemetry.Event(
                        "apiprobe_abil",
                        {
                            {"team", team},
                            {"pid", pid},
                            {"own", own},
                            {"slot", slot},
                            {"name", name},
                            unpack(fields)
                        }
                    )
                    __continue76 = true
                until true
                if not __continue76 then
                    break
                end
            end
            slot = slot + 1
        end
    end
end
function estRow(team, src, own, h, target)
    local u = h
    local okL, at = pcall(function() return u:GetLocation() end)
    local d = okL and at ~= nil and at ~= nil and GetUnitToLocationDistance(target, at) or -1
    Telemetry.Event(
        "apiprobe_est",
        {
            {"team", team},
            {"src", src},
            {
                "dst",
                target:GetPlayerID()
            },
            {"own", own},
            {
                "dist",
                math.floor(d)
            },
            {
                "et",
                round(num(
                    h,
                    function() return u:GetEstimatedDamageToTarget(true, target, EST_WINDOW, ALL_DAMAGE) end
                ))
            },
            {
                "ef",
                round(num(
                    h,
                    function() return u:GetEstimatedDamageToTarget(false, target, EST_WINDOW, ALL_DAMAGE) end
                ))
            }
        }
    )
end
function nearestOf(h, units)
    local ok, at = pcall(function() return h:GetLocation() end)
    if not ok or at == nil or at == nil then
        return nil
    end
    local best
    local bestD = math.huge
    for ____, x in ipairs(units) do
        do
            local __continue102
            repeat
                if x:IsNull() or not x:IsAlive() or x:IsIllusion() then
                    __continue102 = true
                    break
                end
                local d = GetUnitToLocationDistance(x, at)
                if d < bestD then
                    bestD = d
                    best = x
                end
                __continue102 = true
            until true
            if not __continue102 then
                break
            end
        end
    end
    return best
end
function nearestOwn(h)
    local own = {}
    do
        local i = 1
        while i <= 5 do
            local m = GetTeamMember(i)
            if m ~= nil and m ~= nil then
                own[#own + 1] = m
            end
            i = i + 1
        end
    end
    return nearestOf(h, own)
end
function nearestEnemy(h)
    return nearestOf(
        h,
        GetUnitList(UnitType.EnemyHeroes)
    )
end
local MAX_PLAYER_ID = 23
NIL = -1
ERR = -2
local function cooldownSum(u)
    local sum = 0
    do
        local slot = 0
        while slot <= 5 do
            local a = u:GetAbilityInSlot(slot)
            if a ~= nil and a ~= nil then
                sum = sum + a:GetCooldownTimeRemaining()
            end
            slot = slot + 1
        end
    end
    return sum
end
local function itemCount(u)
    local n = 0
    do
        local slot = 0
        while slot <= 5 do
            local item = u:GetItemInSlot(slot)
            if item ~= nil and item ~= nil then
                n = n + 1
            end
            slot = slot + 1
        end
    end
    return n
end
local function firstItem(u)
    local ok, name = pcall(function()
        do
            local slot = 0
            while slot <= 5 do
                local item = u:GetItemInSlot(slot)
                if item ~= nil and item ~= nil then
                    return item:GetName()
                end
                slot = slot + 1
            end
        end
        return nil
    end)
    if not ok then
        return "err"
    end
    local ____name_0 = name
    if ____name_0 == nil then
        ____name_0 = "none"
    end
    return ____name_0
end
local function unitFields(u)
    local okLoc, loc = pcall(function() return u:GetLocation() end)
    local hasLoc = okLoc and loc ~= nil and loc ~= nil
    return {
        {"loc", not okLoc and ERR or (hasLoc and 1 or 0)},
        {
            "x",
            hasLoc and math.floor(loc.x) or nil
        },
        {
            "y",
            hasLoc and math.floor(loc.y) or nil
        },
        {
            "alive",
            num(
                u,
                function(h) return h:IsAlive() end
            )
        },
        {
            "hp",
            num(
                u,
                function(h) return h:GetHealth() end
            )
        },
        {
            "mp",
            round(num(
                u,
                function(h) return h:GetMana() end
            ))
        },
        {
            "lvl",
            num(
                u,
                function(h) return h:GetLevel() end
            )
        },
        {
            "ms",
            num(
                u,
                function(h) return h:GetCurrentMovementSpeed() end
            )
        },
        {
            "nw",
            num(
                u,
                function(h) return h:GetNetWorth() end
            )
        },
        {
            "nmod",
            num(
                u,
                function(h) return h:NumModifiers() end
            )
        },
        {
            "cds",
            round(num(u, cooldownSum))
        },
        {
            "nitem",
            num(u, itemCount)
        },
        {
            "it0",
            firstItem(u)
        },
        {
            "tgt",
            num(
                u,
                function(h) return h:GetAttackTarget() ~= nil and h:GetAttackTarget() ~= nil end
            )
        },
        {
            "chan",
            num(
                u,
                function(h) return h:IsChanneling() end
            )
        },
        {
            "cast",
            num(
                u,
                function(h) return h:IsCastingAbility() end
            )
        }
    }
end
local states = {}
local installed = {}
local damage = {}
local shapeLogged = false
local function heroPids()
    local pids = {}
    do
        local pid = 0
        while pid <= MAX_PLAYER_ID do
            local t = GetTeamForPlayer(pid)
            if t == Team.Radiant or t == Team.Dire then
                pids[#pids + 1] = pid
            end
            pid = pid + 1
        end
    end
    return pids
end
--- The team's lowest-pid living hero writes the team-wide rows, so they appear once whether or not modules are shared.
local function reporterPid(alive)
    local best
    do
        local i = 1
        while i <= 5 do
            do
                local __continue34
                repeat
                    local m = GetTeamMember(i)
                    if m == nil or m == nil or alive and not m:IsAlive() then
                        __continue34 = true
                        break
                    end
                    local pid = m:GetPlayerID()
                    if best == nil or pid < best then
                        best = pid
                    end
                    __continue34 = true
                until true
                if not __continue34 then
                    break
                end
            end
            i = i + 1
        end
    end
    return best
end
--- 1 visible, 0 held but out of sight, -1 never held, -2 the read failed.
local function visibleNow(handles, pid)
    local h = handles[pid]
    if h == nil then
        return NIL
    end
    return num(
        h,
        function(u) return u:CanBeSeen() end
    )
end
local function describeArgs(args)
    local parts = {}
    do
        local i = 0
        while i < 4 do
            local a = args[i + 1]
            if type(a) == "table" then
                local keys = {}
                for k, v in pairs(a) do
                    keys[#keys + 1] = (tostring(k) .. ":") .. type(v)
                end
                parts[#parts + 1] = ("{" .. table.concat(keys, ",")) .. "}"
            else
                parts[#parts + 1] = type(a)
            end
            i = i + 1
        end
    end
    return table.concat(parts, "|")
end
local function install(bot, st)
    local team = bot:GetTeam()
    local g = _G
    for ____, pid in ipairs(heroPids()) do
        do
            local __continue46
            repeat
                if installed[pid] == true then
                    __continue46 = true
                    break
                end
                installed[pid] = true
                local own = GetTeamForPlayer(pid) == team and 1 or 0
                InstallCastCallback(
                    pid,
                    function(event)
                        pcall(function()
                            local ____temp_1
                            if type(event) == "table" then
                                ____temp_1 = event.ability
                            else
                                ____temp_1 = nil
                            end
                            local a = ____temp_1
                            local name = "?"
                            if type(a) == "string" then
                                name = a
                            elseif a ~= nil and a ~= nil then
                                name = a:GetName()
                            end
                            Telemetry.Event(
                                "apiprobe_cast",
                                {
                                    {"team", team},
                                    {"pid", pid},
                                    {"own", own},
                                    {
                                        "vis",
                                        own == 1 and 1 or visibleNow(st.handles, pid)
                                    },
                                    {"ability", name}
                                }
                            )
                        end)
                    end
                )
                if type(g.InstallDamageCallback) ~= "function" then
                    __continue46 = true
                    break
                end
                local installDamage = g.InstallDamageCallback
                installDamage(
                    pid,
                    function(...)
                        local args = {...}
                        pcall(function()
                            if not shapeLogged then
                                shapeLogged = true
                                Telemetry.Event(
                                    "apiprobe_dmgshape",
                                    {
                                        {"team", team},
                                        {
                                            "args",
                                            describeArgs(args)
                                        }
                                    }
                                )
                            end
                            local d = damage[pid] or ({n = 0, fog = 0, sum = 0})
                            damage[pid] = d
                            d.n = d.n + 1
                            if own == 0 and visibleNow(st.handles, pid) ~= 1 then
                                d.fog = d.fog + 1
                            end
                            local first = args[1]
                            local ____temp_2
                            if type(first) == "table" then
                                ____temp_2 = first.damage
                            else
                                ____temp_2 = args[3]
                            end
                            local amount = ____temp_2
                            if type(amount) == "number" then
                                d.sum = d.sum + amount
                            end
                        end)
                    end
                )
                __continue46 = true
            until true
            if not __continue46 then
                break
            end
        end
    end
end
local function teamRows(bot, st)
    local team = bot:GetTeam()
    for pid, h in pairs(st.handles) do
        do
            local __continue60
            repeat
                local okNull, isNull = pcall(function() return h:IsNull() end)
                if okNull and isNull then
                    __continue60 = true
                    break
                end
                Telemetry.Event(
                    "apiprobe_enemy",
                    {
                        {"team", team},
                        {"pid", pid},
                        {
                            "vis",
                            num(
                                h,
                                function(u) return u:CanBeSeen() end
                            )
                        },
                        unpack(unitFields(h))
                    }
                )
                __continue60 = true
            until true
            if not __continue60 then
                break
            end
        end
    end
    for pid, d in pairs(damage) do
        do
            local __continue64
            repeat
                if d.n == 0 then
                    __continue64 = true
                    break
                end
                Telemetry.Event(
                    "apiprobe_dmg",
                    {
                        {"team", team},
                        {"pid", pid},
                        {
                            "own",
                            GetTeamForPlayer(pid) == team and 1 or 0
                        },
                        {"n", d.n},
                        {"fog", d.fog},
                        {
                            "sum",
                            math.floor(d.sum)
                        }
                    }
                )
                d.n = 0
                d.fog = 0
                d.sum = 0
                __continue64 = true
            until true
            if not __continue64 then
                break
            end
        end
    end
    for epid, h in pairs(st.handles) do
        do
            local __continue66
            repeat
                if num(
                    h,
                    function(u) return u:CanBeSeen() end
                ) ~= 1 or num(
                    h,
                    function(u) return u:IsAlive() end
                ) ~= 1 then
                    __continue66 = true
                    break
                end
                abilityRows(team, epid, 0, h)
                local target = nearestOwn(h)
                if target ~= nil then
                    estRow(
                        team,
                        epid,
                        0,
                        h,
                        target
                    )
                end
                __continue66 = true
            until true
            if not __continue66 then
                break
            end
        end
    end
    local ok, tps = pcall(function() return GetIncomingTeleports() end)
    if not ok or tps == nil or tps == nil then
        return
    end
    for ____, tp in ipairs(tps) do
        Telemetry.Event(
            "apiprobe_tp",
            {
                {"team", team},
                {"pid", tp.playerid},
                {
                    "own",
                    GetTeamForPlayer(tp.playerid) == team and 1 or 0
                },
                {
                    "x",
                    math.floor(tp.location.x)
                },
                {
                    "y",
                    math.floor(tp.location.y)
                },
                {
                    "rem",
                    round(tp.time_remaining)
                }
            }
        )
    end
end
EST_WINDOW = 3
ALL_DAMAGE = 3
ABILITY_REPEAT = 10
lastAbility = {}
function ____exports.Tick(bot)
    if Overrides.Get("ApiProbe") ~= true then
        return
    end
    local now = DotaTime()
    local pid = bot:GetPlayerID()
    local st = states[pid] or ({nextAt = -math.huge, handles = {}})
    states[pid] = st
    for ____, u in ipairs(GetUnitList(UnitType.EnemyHeroes)) do
        do
            local __continue112
            repeat
                if u:IsIllusion() then
                    __continue112 = true
                    break
                end
                st.handles[u:GetPlayerID()] = u
                __continue112 = true
            until true
            if not __continue112 then
                break
            end
        end
    end
    if reporterPid(false) == pid then
        install(bot, st)
    end
    if now < st.nextAt then
        return
    end
    st.nextAt = math.floor(now) + 1
    Telemetry.Event(
        "apiprobe_own",
        {
            {
                "team",
                bot:GetTeam()
            },
            {"pid", pid},
            {
                "seen",
                num(
                    bot,
                    function(u) return u:CanBeSeen() end
                )
            },
            unpack(unitFields(bot))
        }
    )
    abilityRows(
        bot:GetTeam(),
        pid,
        1,
        bot
    )
    local foe = nearestEnemy(bot)
    if foe ~= nil and foe:CanBeSeen() then
        estRow(
            bot:GetTeam(),
            pid,
            1,
            bot,
            foe
        )
    end
    if reporterPid(true) == pid then
        teamRows(bot, st)
    end
end
return ____exports
