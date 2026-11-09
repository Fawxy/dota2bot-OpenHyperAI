dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- The observer's one job: a timed regen buff's start, refresh and end are logged, and an end is told apart as ran-out, early (with the
-- damage sources just before it) or death, so OHA's uses and ours are read on the same truth.
local Unit = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function Unit:GetModifierRemainingDuration() return self.left or 0 end
function Unit:WasRecentlyDamagedByAnyHero() return self.hitBy == "hero" end
function Unit:WasRecentlyDamagedByCreep() return self.hitBy == "creep" end
function Unit:WasRecentlyDamagedByTower() return self.hitBy == "tower" end
function Unit:GetPlayerID() return self.pid end
function Unit:GetMana() return self.mp or 100 end
function Unit:GetMaxMana() return 100 end

local lines
local function fresh()
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	return require("bots/FunLib/humaniser/regen_obs")
end
local function obs()
	local r = {}
	for _, l in ipairs(lines) do if l:find(" ev=regen_obs ", 1, true) then table.insert(r, l) end end
	return r
end
local function field(line, key) return line:match(" " .. key .. "=(%S+)") end
local function step(R, b, dt) T = T + dt R.Tick(b) end

-- A salve that runs its 13 s out: one start with the missing HP and the live duration, one end `full`, no sources.
do
	local R = fresh()
	local b = MakeUnit({ pid = 1, hp = 60, maxhp = 100 })
	T = 100
	R.Tick(b)
	check("no buff, no line", #obs() == 0)
	b.modifiers = { modifier_flask_healing = 1 }
	b.left = 13
	R.Tick(b)
	step(R, b, 6) b.left = 7
	R.Tick(b)
	b.modifiers = {}
	step(R, b, 7)
	local o = obs()
	check("start and end logged", #o == 2, #o)
	check("start item", field(o[1], "item") == "salve")
	check("start miss is the HP missing", field(o[1], "miss") == "40", field(o[1], "miss"))
	check("start dur is read live", field(o[1], "dur") == "13")
	check("ran out is full", field(o[2], "why") == "full", o[2])
	check("full end names no source", field(o[2], "src") == "-")
end

-- A salve broken after 4 s by a hero: the end is `early`, names the source and what was lost (time left).
do
	local R = fresh()
	local b = MakeUnit({ pid = 2, hp = 50, maxhp = 100 })
	T = 100
	b.modifiers = { modifier_flask_healing = 1 }
	b.left = 13
	R.Tick(b)
	step(R, b, 4)
	b.modifiers = {}
	b.hitBy = "hero"
	R.Tick(b)
	local o = obs()
	check("early end", field(o[2], "why") == "early", o[2])
	check("early end names the source", field(o[2], "src") == "hero", o[2])
	check("left is what the break cost", field(o[2], "left") == "9", field(o[2], "left"))
end

-- An end with no flagged source still shows whether HP fell just before it: the clarity that ended early at full HP in the smoke
-- game (no damage) against one that lost 20 HP in the same second (a source the flags do not name).
do
	local R = fresh()
	local quiet = MakeUnit({ pid = 6, hp = 90, maxhp = 100 })
	local hit = MakeUnit({ pid = 7, hp = 90, maxhp = 100 })
	T = 100
	for _, u in ipairs({ quiet, hit }) do u.modifiers = { modifier_clarity_potion = 1 } u.left = 25 R.Tick(u) end
	step(R, quiet, 1) step(R, hit, 0)
	hit.hp = 70
	step(R, hit, 0.5) quiet.modifiers = {} hit.modifiers = {}
	R.Tick(quiet) R.Tick(hit)
	local drops = {}
	for _, l in ipairs(obs()) do if field(l, "state") == "end" then drops[field(l, "pid")] = field(l, "drop") end end
	check("quiet early end has no HP drop", drops["6"] == "0", drops["6"])
	check("hit early end shows the HP lost", drops["7"] == "20", drops["7"])
end

-- Clarity restores mana: the missing amount is mana. A tango recast while active is a refresh, not a second start.
do
	local R = fresh()
	local b = MakeUnit({ pid = 3, hp = 100, maxhp = 100 })
	b.mp = 30
	T = 100
	b.modifiers = { modifier_clarity_potion = 1 }
	b.left = 25
	R.Tick(b)
	check("clarity miss is mana", field(obs()[1], "miss") == "70", obs()[1])
	local c = MakeUnit({ pid = 4, hp = 70, maxhp = 100 })
	c.modifiers = { modifier_tango_heal = 1 }
	c.left = 16
	R.Tick(c)
	step(R, c, 6) c.left = 10
	R.Tick(c)
	step(R, c, 0.1) c.left = 16
	R.Tick(c)
	local states = {}
	for _, l in ipairs(obs()) do if field(l, "pid") == "4" then table.insert(states, field(l, "state")) end end
	check("recast is a refresh", table.concat(states, ",") == "start,refresh", table.concat(states, ","))
end

-- A death ends the buff but is not an early end.
do
	local R = fresh()
	local b = MakeUnit({ pid = 5, hp = 50, maxhp = 100 })
	T = 100
	b.modifiers = { modifier_flask_healing = 1 }
	b.left = 13
	R.Tick(b)
	step(R, b, 3)
	b.modifiers = {}
	b.alive = false
	R.Tick(b)
	check("death is why=dead", field(obs()[2], "why") == "dead", obs()[2])
end

finish()
