--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Overrides = require(GetScriptDirectory().."/FunLib/humaniser/overrides")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
--- The attack animations (engine lasthit.ts).
local ACTIVITY_ATTACK = 1503
local ACTIVITY_ATTACK2 = 1504
--- Above this attack range a hero attacks with a projectile (engine lasthit.ts).
local RANGED_ABOVE = 320
--- A ranged projectile lands this far short of the creep's centre (engine lasthit.ts).
local CREEP_LAUNCH_OFFSET = 22
--- Seconds after first sight with no landing: the record ends `lost`. `judgement`: past any hero's wind-up plus flight.
local GIVE_UP = 3
local active = {}
local frameAt
function ____exports.ResetCache()
    for k in pairs(active) do
        active[k] = nil
    end
    frameAt = nil
end
local function dist(a, b)
    local dx = a.x - b.x
    local dy = a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
local function isLaneCreep(u)
    if u == nil or u == nil then
        return false
    end
    local c = u
    if c:IsNull() or not c:IsAlive() or not c:IsCreep() then
        return false
    end
    local team = c:GetTeam()
    if team ~= 2 and team ~= 3 then
        return false
    end
    local name = c:GetUnitName()
    return (string.find(name, "creep_goodguys", 1, true)) ~= nil or (string.find(name, "creep_badguys", 1, true)) ~= nil or (string.find(name, "siege", 1, true)) ~= nil
end
--- Seconds of wind-up left, or undefined when not winding up (engine windupLeft).
local function windupLeft(h)
    local act = h:GetAnimActivity()
    if act ~= ACTIVITY_ATTACK and act ~= ACTIVITY_ATTACK2 then
        return nil
    end
    local cyc = h:GetAnimCycle()
    local pt = h:GetAttackPoint()
    if cyc >= pt then
        return nil
    end
    return (pt - cyc) * h:GetSecondsPerAttack()
end
--- What a retarget went to: `creep` another lane creep, `hero`, `none`, `other`.
local function targetKind(u)
    if u == nil or u == nil then
        return "none"
    end
    if isLaneCreep(u) then
        return "creep"
    end
    local ok, hero = pcall(function() return u:IsHero() end)
    return ok and hero == true and "hero" or "other"
end
--- The hero's attack projectile at the creep: seconds to its landing from its own position (engine flightsAt), else undefined.
local function projectileEta(c, h)
    for ____, p in ipairs(c:GetIncomingTrackingProjectiles() or ({})) do
        if p.is_attack == true and p.caster == h then
            return dist(
                p.location,
                c:GetLocation()
            ) / math.max(
                1,
                h:GetAttackProjectileSpeed()
            )
        end
    end
    return nil
end
local function gone(c)
    return c:IsNull() or not c:IsAlive()
end
local function start(h, c, team, now)
    local left = windupLeft(h)
    if left == nil then
        return nil
    end
    local ranged = h:GetAttackRange() > RANGED_ABOVE and h:GetAttackProjectileSpeed() > 0
    local flight = ranged and math.max(
        0,
        dist(
            h:GetLocation(),
            c:GetLocation()
        ) - CREEP_LAUNCH_OFFSET
    ) / h:GetAttackProjectileSpeed() or 0
    local hp = c:GetHealth()
    return {
        h = h,
        c = c,
        cid = Telemetry.CreepId(c),
        own = c:GetTeam() == team and 1 or 0,
        ranged = ranged,
        t0 = now,
        cyc = h:GetAnimCycle(),
        pt = h:GetAttackPoint(),
        spa = h:GetSecondsPerAttack(),
        pf = left,
        pl = left + flight,
        aspd = h:GetAttackSpeed(),
        pf2 = h:GetAttackPoint() / math.max(
            0.01,
            h:GetAttackSpeed()
        ) * (1 - h:GetAnimCycle()),
        fl = flight,
        lat0 = h:GetLastAttackTime(),
        lh0 = h:GetLastHits(),
        dn0 = h:GetDenies(),
        hp0 = hp,
        hpPrev = hp,
        dmg = c:GetActualIncomingDamage(
            h:GetAttackDamage(),
            DAMAGE_TYPE_PHYSICAL or 1
        ),
        proj = false,
        gap = 0,
        last = now,
        pres = "",
        absent = 0,
        big = 0
    }
end
local function r3(x)
    return x == nil and -1 or math.floor(x * 1000 + 0.5) / 1000
end
local function emit(s)
    local kill = (s.h:GetLastHits() > s.lh0 or s.h:GetDenies() > s.dn0) and 1 or 0
    Telemetry.Event(
        "swing_probe",
        {
            {
                "pid",
                s.h:GetPlayerID()
            },
            {"cid", s.cid},
            {"own", s.own},
            {"rng", s.ranged and 1 or 0},
            {
                "cyc",
                r3(s.cyc)
            },
            {
                "pt",
                r3(s.pt)
            },
            {
                "spa",
                r3(s.spa)
            },
            {
                "pf",
                r3(s.pf)
            },
            {
                "pl",
                r3(s.pl)
            },
            {
                "aspd",
                r3(s.aspd)
            },
            {
                "pf2",
                r3(s.pf2)
            },
            {
                "fl",
                r3(s.fl)
            },
            {
                "fire",
                r3(s.fire)
            },
            {
                "seen",
                r3(s.seen)
            },
            {
                "land",
                r3(s.land)
            },
            {"same", s.same or -1},
            {"proj", s.proj and 1 or 0},
            {
                "hp0",
                math.floor(s.hp0)
            },
            {
                "drop",
                s.drop == nil and -1 or math.floor(s.drop)
            },
            {
                "dmg",
                math.floor(s.dmg)
            },
            {"kill", kill},
            {"end", s.endWhy},
            {"to", s.to},
            {
                "gap",
                r3(s.gap)
            },
            {
                "age",
                r3(s.age)
            },
            {
                "pl3",
                r3(s.pl3)
            },
            {
                "drop2",
                s.drop2 == nil and -1 or math.floor(s.drop2)
            },
            {"pres", s.ranged and s.pres or nil},
            {
                "big",
                math.floor(s.big)
            },
            {
                "bigat",
                r3(s.bigAt)
            }
        }
    )
end
--- One frame of a live record: true when it has ended (its line goes out the frame after the landing, for the counters).
local function follow(s, now)
    s.gap = math.max(s.gap, now - s.last)
    s.last = now
    if s.endWhy ~= nil then
        if s.drop ~= nil then
            s.drop2 = s.ranged and s.drop or s.drop + (s.hpLand or 0) - (gone(s.c) and 0 or s.c:GetHealth())
        end
        emit(s)
        return true
    end
    local isGone = gone(s.c)
    local hp = isGone and 0 or s.c:GetHealth()
    if s.fire == nil and s.h:GetLastAttackTime() > s.lat0 then
        s.fire = s.h:GetLastAttackTime() - (GameTime() - now) - s.t0
        s.seen = now - s.t0
        s.same = s.h:GetAttackTarget() == s.c and 1 or 0
        if not s.ranged then
            s.land = s.seen
            s.drop = s.hpPrev - hp
            s.endWhy = "land"
        end
    elseif s.fire == nil then
        if isGone then
            s.endWhy = "gone"
        elseif s.h:GetAttackTarget() ~= s.c then
            s.endWhy = "retarget"
            s.to = targetKind(s.h:GetAttackTarget())
        elseif windupLeft(s.h) == nil then
            s.endWhy = "cancel"
        end
    elseif s.ranged then
        local ____isGone_0
        if isGone then
            ____isGone_0 = nil
        else
            ____isGone_0 = projectileEta(s.c, s.h)
        end
        local eta = ____isGone_0
        local flying = eta ~= nil
        if #s.pres < 40 then
            s.pres = s.pres .. (flying and "1" or "0")
        end
        if s.hpPrev - hp > s.big then
            s.big = s.hpPrev - hp
            s.bigAt = now - s.t0
        end
        if flying and not s.proj then
            s.pl3 = now - s.t0 + eta
        end
        if flying then
            s.proj = true
            s.absent = 0
        elseif s.proj then
            s.absent = s.absent + 1
            if s.absent == 1 then
                s.land1 = now - s.t0
                s.hpLand = s.hpPrev
            end
        end
        if not flying and (s.proj and s.absent >= 2 or isGone) then
            s.land = s.absent >= 2 and (s.land1 or now - s.t0) or now - s.t0
            s.drop = (s.absent >= 2 and (s.hpLand or s.hpPrev) or s.hpPrev) - hp
            s.endWhy = isGone and not s.proj and "gone" or "land"
        end
    end
    if s.endWhy == nil and now - s.t0 > GIVE_UP then
        s.endWhy = "lost"
    end
    if s.endWhy ~= nil then
        s.age = now - s.t0
        if s.drop ~= nil and not s.ranged then
            s.hpLand = hp
        end
    end
    s.hpPrev = hp
    return false
end
--- The probe's frame: every hero of the bot's team, once per team VM per frame.
local function frame(bot)
    local now = DotaTime()
    if frameAt == now then
        return
    end
    frameAt = now
    local team = bot:GetTeam()
    do
        local i = 1
        while i <= 5 do
            do
                local __continue47
                repeat
                    local u = GetTeamMember(i)
                    if u == nil or u == nil or u:IsNull() or u:IsIllusion() then
                        __continue47 = true
                        break
                    end
                    local pid = u:GetPlayerID()
                    local s = active[pid]
                    if s ~= nil then
                        if follow(s, now) then
                            active[pid] = nil
                        else
                            __continue47 = true
                            break
                        end
                    end
                    if not u:IsAlive() then
                        __continue47 = true
                        break
                    end
                    local t = u:GetAttackTarget()
                    if not isLaneCreep(t) then
                        __continue47 = true
                        break
                    end
                    active[pid] = start(u, t, team, now)
                    __continue47 = true
                until true
                if not __continue47 then
                    break
                end
            end
            i = i + 1
        end
    end
end
function ____exports.Tick(bot)
    if Overrides.Get("SwingProbe") ~= true then
        return
    end
    pcall(frame, bot)
end
return ____exports
