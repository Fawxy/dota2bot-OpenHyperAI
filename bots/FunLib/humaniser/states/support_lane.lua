--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
--- User rule 02/11/2026: deny before anything else while denies are tuned. Wants the frame while the body is in a deny
-- attempt or would start one now; its scan picks the creep when stepped.
local deny = {
    name = "deny",
    wants = function(bot, ctx) return Laning.OwnsDenyOnly(bot) and ctx.bodyRunning() and (ctx.bodyLabel() == "deny" or Laning.DenyOffered(bot)) end,
    run = function(_bot, ctx) return ctx.stepBody() end
}
____exports.STEPS = {deny}
--- The name of the step that acted, or undefined when none wanted the frame (or the one that did issued nothing).
function ____exports.Step(bot, ctx)
    for ____, s in ipairs(____exports.STEPS) do
        if s.wants(bot, ctx) and s.run(bot, ctx) then
            return s.name
        end
    end
    return nil
end
--- Whether any step may act for this bot: decided per frame by mode_laning_generic before its own steps.
function ____exports.Applies(bot)
    return Laning.OwnsDenyOnly(bot)
end
return ____exports
