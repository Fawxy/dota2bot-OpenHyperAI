--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Customize = require(GetScriptDirectory().."/FunLib/custom_loader")
____exports.DEFAULTS = {LeaveCoreCreep = true, StackExecute = true}
function ____exports.On(feature)
    if Customize.Enable == false then
        return false
    end
    local ____opt_0 = Customize.Ours
    if ____opt_0 ~= nil then
        ____opt_0 = ____opt_0[feature]
    end
    local value = ____opt_0
    if value == nil or value == nil then
        return ____exports.DEFAULTS[feature]
    end
    return value == true
end
return ____exports
