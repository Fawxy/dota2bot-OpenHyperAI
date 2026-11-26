--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
____exports.RUNE_RULES = {power = {first = 360, every = 120}, water = {first = 120, every = 120, last = 240}, bounty = {first = 0, every = 240}, wisdom = {first = 420, every = 420}}
--- Lane creep waves spawn every 30 s. Long-standing rule: the datafeed patch notes 7.38 to 7.41f record no change to wave or
-- neutral spawn timing (scan 08/11/2026), but they carry no base value either, so the 30 s is not read from the feed.
____exports.WAVE_EVERY = 30
--- Neutral camps first spawn at 1:00 game time, then refill every minute (Liquipedia "Neutral Creeps" page as cited before this module, not re-read 08/11/2026; no patch change 7.38 to 7.41f).
____exports.NEUTRAL_FIRST = 60
____exports.NEUTRAL_EVERY = 60
--- A dying enemy non-hero's experience is shared among the heroes of the other side within this range of it; a deny halves what
-- enemy heroes in this range get, so with none in it a deny is worth nothing (master docs/reference/specifics/
-- lane-creeps-and-bounties.md "Experience": "shared evenly (truncated) among allied heroes within 1500", from Liquipedia
-- Experience (Acquiring Experience) and (Denying)). No Valve function returns it.
____exports.XP_RANGE = 1500
return ____exports
