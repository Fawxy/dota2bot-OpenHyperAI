--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local tracks = {}
local WINDOW = 0.3
function ____exports.Tick(bot)
    local pid = bot:GetPlayerID()
    local hp = bot:GetHealth()
    local t = tracks[pid]
    if t == nil then
        t = {hp = hp, heroLost = 0}
        tracks[pid] = t
        return
    end
    local drop = t.hp - hp
    t.hp = hp
    if drop <= 0 or not bot:IsAlive() or not bot:WasRecentlyDamagedByAnyHero(WINDOW) then
        return
    end
    local mixed = bot:WasRecentlyDamagedByCreep(WINDOW) or bot:WasRecentlyDamagedByTower(WINDOW)
    t.heroLost = t.heroLost + (mixed and drop / 2 or drop)
end
--- HP lost to heroes so far this game.
function ____exports.HeroLost(bot)
    local ____math_floor_2 = math.floor
    local ____opt_0 = tracks[bot:GetPlayerID()]
    return ____math_floor_2(____opt_0 and ____opt_0.heroLost or 0)
end
return ____exports
