--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
--- The item by name in slots 0-5 (the backpack cannot be cast), when it can be cast now.
function ____exports.Usable(bot, name)
    local slot = bot:FindItemSlot(name)
    if slot == nil or slot < 0 or slot > 5 then
        return nil
    end
    local item = bot:GetItemInSlot(slot)
    return item ~= nil and item ~= nil and item:IsFullyCastable() and item or nil
end
--- The HP one use gives in full, read from the item: an instant restore (faerie fire) or regen per second times duration.
function ____exports.HpRestore(item)
    local spec = item
    local instant = spec:GetSpecialValueFloat("hp_restore")
    if instant > 0 then
        return instant
    end
    return spec:GetSpecialValueFloat("health_regen") * spec:GetSpecialValueFloat("buff_duration")
end
--- A visible, passable tree within the radius, for a tango.
function ____exports.TangoTree(bot, radius)
    for ____, tree in ipairs(bot:GetNearbyTrees(radius) or ({})) do
        local loc = GetTreeLocation(tree)
        if IsLocationVisible(loc) and IsLocationPassable(loc) then
            return tree
        end
    end
    return nil
end
--- The game time our code last ordered each item's use, per hero: regen_obs reads it as `by` (ours or OHA).
local usedAt = {}
local function used(bot, item)
    local ____usedAt_0, ____temp_1 = usedAt, bot:GetPlayerID()
    if ____usedAt_0[____temp_1] == nil then
        ____usedAt_0[____temp_1] = {}
    end
    usedAt[bot:GetPlayerID()][item:GetName()] = DotaTime()
end
--- Whether our code ordered one of these items' use on the bot within `within` seconds.
function ____exports.OursUsed(bot, names, within)
    local m = usedAt[bot:GetPlayerID()]
    if m == nil then
        return false
    end
    local now = DotaTime()
    for ____, n in ipairs(names) do
        if m[n] ~= nil and now - m[n] <= within then
            return true
        end
    end
    return false
end
--- An item cast on ourselves (salve, clarity).
function ____exports.UseOnSelf(bot, item)
    used(bot, item)
    bot:Action_UseAbilityOnEntity(item, bot)
end
--- A no-target item (faerie fire).
function ____exports.UseNoTarget(bot, item)
    used(bot, item)
    bot:Action_UseAbility(item)
end
--- A tango on a tree: the hero walks to within the cast range first, so the caller gives no move order meanwhile.
function ____exports.UseOnTree(bot, item, tree)
    used(bot, item)
    bot:Action_UseAbilityOnTree(item, tree)
end
return ____exports
