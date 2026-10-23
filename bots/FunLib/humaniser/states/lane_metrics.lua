--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local tracks = {}
--- Seconds back the damage source is looked up; widened at high timescales where frames are further apart.
local WINDOW = 0.3
function ____exports.Tick(bot)
    local pid = bot:GetPlayerID()
    local hp = bot:GetHealth()
    local now = DotaTime()
    local t = tracks[pid]
    if t == nil then
        t = {hp = hp, heroLost = 0, at = now}
        tracks[pid] = t
        return
    end
    local drop = t.hp - hp
    local w = math.min(
        2,
        math.max(WINDOW, 1.5 * (now - t.at))
    )
    t.hp = hp
    t.at = now
    if drop <= 0 or not bot:IsAlive() or not bot:WasRecentlyDamagedByAnyHero(w) then
        return
    end
    local mixed = bot:WasRecentlyDamagedByCreep(w) or bot:WasRecentlyDamagedByTower(w)
    t.heroLost = t.heroLost + (mixed and drop / 2 or drop)
end
--- HP lost to heroes so far this game.
function ____exports.HeroLost(bot)
    local ____math_floor_2 = math.floor
    local ____opt_0 = tracks[bot:GetPlayerID()]
    return ____math_floor_2(____opt_0 and ____opt_0.heroLost or 0)
end
return ____exports
