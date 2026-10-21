--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
function ____exports.MainSlotType()
    return ITEM_SLOT_TYPE_MAIN
end
function ____exports.T(u)
    return u
end
function ____exports.DrawLine(a, b, r, g, b2)
    DebugDrawLine(
        a,
        b,
        r,
        g,
        b2
    )
end
function ____exports.CreepKind(u)
    local name = u:GetUnitName()
    if (string.find(name, "siege", 1, true)) ~= nil then
        return "siege"
    end
    if (string.find(name, "ranged", 1, true)) ~= nil then
        return "ranged"
    end
    return "melee"
end
--- "npc_dota_hero_crystal_maiden" -> "Crystal maiden".
function ____exports.HeroLabel(u)
    local name = (string.gsub((string.gsub(
        u:GetUnitName(),
        "npc_dota_hero_",
        ""
    )), "_", " "))
    return string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2)
end
local helpers
function ____exports.SetTrainerHelpers(h)
    helpers = h
end
function ____exports.GetTrainerHelpers()
    return helpers
end
return ____exports
