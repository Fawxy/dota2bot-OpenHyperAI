--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArraySort(self, compareFn)
    if compareFn ~= nil then
        table.sort(
            self,
            function(a, b) return compareFn(nil, a, b) < 0 end
        )
    else
        table.sort(self)
    end
    return self
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
local Offer = require(GetScriptDirectory().."/FunLib/humaniser/offer")
local Threat = require(GetScriptDirectory().."/FunLib/humaniser/threat")
local function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
--- The parts for `bot` walking from where it stands to `place`, held `secs` seconds. Facts only.
function ____exports.At(bot, place, secs)
    local window = secs ~= nil and secs > 0 and secs or Threat.SETTINGS.GateHorizon
    local from = bot:GetLocation()
    local r = Threat.Read(
        bot,
        from,
        place,
        window,
        {passive = true}
    )
    local enemies = {}
    local dmgOf = {}
    for ____, row in ipairs(r.rows) do
        do
            local __continue4
            repeat
                local u = row.u
                if u == nil then
                    __continue4 = true
                    break
                end
                dmgOf[row.pid] = row.dmg
                enemies[#enemies + 1] = {
                    x = row.at.x,
                    y = row.at.y,
                    pid = row.pid,
                    range = u:GetAttackRange(),
                    hull = u:GetBoundingRadius(),
                    dmg = 0,
                    spa = 1
                }
                __continue4 = true
            until true
            if not __continue4 then
                break
            end
        end
    end
    local path = Offer.PathCost({
        from = from,
        spot = place,
        speed = math.max(
            1,
            bot:GetCurrentMovementSpeed()
        ),
        hull = bot:GetBoundingRadius(),
        creeps = {},
        towers = {},
        enemies = enemies
    })
    local reach = {}
    for ____, e in ipairs(path.enemies) do
        reach[#reach + 1] = {pid = e.pid, dist = e.dist, exp = e.exp, dmg = dmgOf[e.pid] or 0}
    end
    local away = {}
    for ____, m in ipairs(r.uns) do
        away[#away + 1] = {
            pid = m.pid,
            tss = m.tss,
            dist = dist(m.at, place)
        }
    end
    __TS__ArraySort(
        away,
        function(____, a, b) return a.dist - b.dist end
    )
    return {
        secs = window,
        reach = reach,
        burst = r.burst,
        allies = r.allies,
        tower = r.tower,
        away = away,
        nos = r.nos
    }
end
local function r0(x)
    return math.floor(x + 0.5)
end
local function r1(x)
    return math.floor(x * 10 + 0.5) / 10
end
local function r2(x)
    return math.floor(x * 100 + 0.5) / 100
end
--- The begin line's fields (`ev=choice kind=decider`, events.ts): `dre` reachers `pid:dist:exp:dmg`, `dun` the unseen `pid:tss:dist`.
function ____exports.Fields(p)
    local dr = table.concat(
        __TS__ArrayMap(
            p.reach,
            function(____, e) return (((((tostring(e.pid) .. ":") .. tostring(r0(e.dist))) .. ":") .. tostring(r1(e.exp))) .. ":") .. tostring(r0(e.dmg)) end
        ),
        ","
    )
    local dun = table.concat(
        __TS__ArrayMap(
            p.away,
            function(____, m) return (((tostring(m.pid) .. ":") .. tostring(r0(m.tss))) .. ":") .. tostring(r0(m.dist)) end
        ),
        ","
    )
    return {
        {
            "bsec",
            r1(p.secs)
        },
        {"dn", #p.reach},
        {"dre", dr ~= "" and dr or nil},
        {
            "dbu",
            r2(p.burst)
        },
        {"dal", p.allies},
        {"dtw", p.tower and 1 or 0},
        {"dun", dun ~= "" and dun or nil},
        {"dnos", p.nos > 0 and p.nos or nil}
    }
end
return ____exports
