--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local LaneFightConfig = require(GetScriptDirectory().."/FunLib/humaniser/lane_fight_config")
local memory = {}
local function roll(chance)
    return RandomFloat(0, 1) < chance
end
local function rememberChance(cls, skill)
    if cls == "ult" then
        return LaneFightConfig.Curve("RememberUlt", skill)
    end
    if cls == "key" then
        return LaneFightConfig.Curve("RememberKey", skill)
    end
    return LaneFightConfig.Curve("RememberOther", skill)
end
local function store(observerPid, enemyPid, ability, entry)
    if memory[observerPid] == nil then
        memory[observerPid] = {}
    end
    if memory[observerPid][enemyPid] == nil then
        memory[observerPid][enemyPid] = {}
    end
    memory[observerPid][enemyPid][ability] = entry
end
local function find(observerPid, enemyPid, ability)
    local byEnemy = memory[observerPid]
    if byEnemy == nil then
        return nil
    end
    local byAbility = byEnemy[enemyPid]
    local ____temp_0
    if byAbility == nil then
        ____temp_0 = nil
    else
        ____temp_0 = byAbility[ability]
    end
    return ____temp_0
end
function ____exports.Record(observerPid, enemyPid, ability, cls, cooldown, skill, now)
    if not roll(rememberChance(cls, skill)) then
        local byEnemy = memory[observerPid]
        if byEnemy ~= nil and byEnemy[enemyPid] ~= nil then
            byEnemy[enemyPid][ability] = nil
        end
        return false
    end
    local x = LaneFightConfig.Curve("TimingError", skill)
    local estReadyAt = now + cooldown * (1 + RandomFloat(-x, x))
    store(
        observerPid,
        enemyPid,
        ability,
        {
            seenAt = now,
            estReadyAt = estReadyAt,
            cls = cls,
            shared = false,
            forgetAt = estReadyAt + LaneFightConfig.Curve("ForgetWindow", skill)
        }
    )
    return true
end
function ____exports.Share(fromPid, toPids, enemyPid, ability, skill)
    local entry = find(fromPid, enemyPid, ability)
    if entry == nil then
        return
    end
    local loss = LaneFightConfig.Curve("ShareLoss", skill)
    for ____, pid in ipairs(toPids) do
        do
            local __continue16
            repeat
                if pid == fromPid then
                    __continue16 = true
                    break
                end
                local existing = find(pid, enemyPid, ability)
                if existing ~= nil and existing.seenAt >= entry.seenAt then
                    __continue16 = true
                    break
                end
                if roll(loss) then
                    __continue16 = true
                    break
                end
                store(
                    pid,
                    enemyPid,
                    ability,
                    {
                        seenAt = entry.seenAt,
                        estReadyAt = entry.estReadyAt,
                        cls = entry.cls,
                        shared = true,
                        forgetAt = entry.estReadyAt + LaneFightConfig.Curve("ForgetWindow", skill)
                    }
                )
                __continue16 = true
            until true
            if not __continue16 then
                break
            end
        end
    end
end
function ____exports.ProbablyReady(observerPid, enemyPid, ability, learned, now, _skill)
    if not learned then
        return false, 1
    end
    local entry = find(observerPid, enemyPid, ability)
    if entry == nil then
        return true, 0
    end
    if now < entry.estReadyAt then
        return false, 1
    end
    local window = entry.forgetAt - entry.estReadyAt
    local confidence = window > 0 and math.max(0, 1 - (now - entry.estReadyAt) / window) or 0
    return true, confidence
end
function ____exports.KeyThreatsDown(observerPid, enemyPid, keyAbilities, now, skill)
    if #keyAbilities == 0 then
        return 0
    end
    local down = 0
    for ____, ability in ipairs(keyAbilities) do
        local ready = ____exports.ProbablyReady(
            observerPid,
            enemyPid,
            ability,
            true,
            now,
            skill
        )
        if not ready then
            down = down + 1
        end
    end
    return down / #keyAbilities
end
function ____exports.Count(observerPid, now)
    local byEnemy = memory[observerPid]
    if byEnemy == nil then
        return 0
    end
    local n = 0
    for ____, byAbility in pairs(byEnemy) do
        for ____, entry in pairs(byAbility) do
            if now < entry.forgetAt then
                n = n + 1
            end
        end
    end
    return n
end
function ____exports.Reset()
    for k in pairs(memory) do
        memory[k] = nil
    end
end
return ____exports
