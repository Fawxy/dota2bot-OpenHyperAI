--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local Team = ____dota.Team
local UnitType = ____dota.UnitType
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
local MAX_PLAYER_ID = 23
local NIL = -1
local ERR = -2
local function num(u, read)
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
local function round(v)
    return v < 0 and v or math.floor(v * 10 + 0.5) / 10
end
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
                            Telemetry.EventUntyped(
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
                                Telemetry.EventUntyped(
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
                Telemetry.EventUntyped(
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
                Telemetry.EventUntyped(
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
    local ok, tps = pcall(function() return GetIncomingTeleports() end)
    if not ok or tps == nil or tps == nil then
        return
    end
    for ____, tp in ipairs(tps) do
        Telemetry.EventUntyped(
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
            local __continue72
            repeat
                if u:IsIllusion() then
                    __continue72 = true
                    break
                end
                st.handles[u:GetPlayerID()] = u
                __continue72 = true
            until true
            if not __continue72 then
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
    Telemetry.EventUntyped(
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
    if reporterPid(true) == pid then
        teamRows(bot, st)
    end
end
return ____exports
