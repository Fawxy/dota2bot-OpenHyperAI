--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local Laning = require(GetScriptDirectory().."/FunLib/humaniser/states/laning")
--- User rule 02/11/2026: the support's lane hits before anything else (denies, and since slice support-lane-hits the last hits
-- its claims give it). Wants the frame while the body is in an attempt or would start one now; its scan picks the creep.
local hit = {
    name = "hit",
    wants = function(bot, ctx)
        if not Laning.OwnsSupportHits(bot) or not ctx.bodyRunning() then
            return false
        end
        local label = ctx.bodyLabel()
        return label == "deny" or label == "lasthit" or Laning.HitOffered(bot)
    end,
    run = function(_bot, ctx) return ctx.stepBody() end
}
____exports.STEPS = {hit}
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
    return Laning.OwnsSupportHits(bot)
end
return ____exports
