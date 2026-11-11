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
--- An item cast on ourselves (salve, clarity).
function ____exports.UseOnSelf(bot, item)
    bot:Action_UseAbilityOnEntity(item, bot)
end
--- A no-target item (faerie fire).
function ____exports.UseNoTarget(bot, item)
    bot:Action_UseAbility(item)
end
--- A tango on a tree: the hero walks to within the cast range first, so the caller gives no move order meanwhile.
function ____exports.UseOnTree(bot, item, tree)
    bot:Action_UseAbilityOnTree(item, tree)
end
return ____exports
