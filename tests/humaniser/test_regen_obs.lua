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

function Unit:GetAttackTarget() return self.target end
function Unit:GetItemInSlot(i) return self.items and self.items[i] or nil end
function Unit:FindItemSlot(name) return self.slots and self.slots[name] or -1 end
function Unit:GetNearbyTrees() return self.trees or {} end
function Unit:GetCurrentMovementSpeed() return 300 end
function GetTreeLocation(tree) return tree end
function IsLocationVisible() return true end
function IsLocationPassable() return true end
function GetUnitToLocationDistance(_, tree) return tree end
local function item(name, charges, regen, dur)
	return { GetName = function() return name end, GetCurrentCharges = function() return charges end,
		GetSpecialValueFloat = function(_, k) return k == "health_regen" and regen or dur end }
end

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

-- A window: the hero idle for 3 s with 300 HP missing, a tango (112 in full) in hand and a tree 250 away is logged with the item, the
-- tree and what the hero did; a window with a tango eaten inside names it; one with too little HP missing or no item is not logged.
do
	local R = fresh()
	local function windows()
		local r = {}
		for _, l in ipairs(lines) do if l:find(" ev=regen_win ", 1, true) then table.insert(r, l) end end
		return r
	end
	local function idle(u, secs, hp)
		T = 100
		u.hp = hp or u.hp
		R.Tick(u)
		for _ = 1, secs do step(R, u, 1) end
	end
	local a = MakeUnit({ pid = 8, hp = 200, maxhp = 500 })
	a.slots = { item_tango = 0 }
	a.items = { [0] = item("item_tango", 3, 7, 16) }
	a.trees = { 250, 900 }
	idle(a, 3)
	a.target = { }
	R.Tick(a)
	local w = windows()
	check("idle window with HP missing and a tango is logged", #w == 1, #w)
	check("window names the tango and the nearest tree", field(w[1], "tg") == "3" and field(w[1], "tree") == "250", w[1])
	check("window reads the effect from the item", field(w[1], "tge") == "112", w[1])
	check("no use inside is -", field(w[1], "used") == "-")

	local b = MakeUnit({ pid = 9, hp = 200, maxhp = 500 })
	b.slots = { item_tango = 0 }
	b.items = { [0] = item("item_tango", 3, 7, 16) }
	b.trees = { 100 }
	idle(b, 2)
	b.modifiers = { modifier_tango_heal = 1 }
	b.left = 16
	step(R, b, 1)
	b.target = { }
	R.Tick(b)
	local wb
	for _, l in ipairs(windows()) do if field(l, "pid") == "9" then wb = l end end
	check("a tango eaten inside the window is named", wb ~= nil and field(wb, "used") == "tango", wb)

	-- A tango eaten 0.4 s into the window is a use inside it, not a buff that was already running.
	local e = MakeUnit({ pid = 12, hp = 200, maxhp = 500 })
	e.slots = { item_tango = 0 }
	e.items = { [0] = item("item_tango", 3, 7, 16) }
	e.trees = { 100 }
	T = 100
	R.Tick(e)
	step(R, e, 0.4)
	e.modifiers = { modifier_tango_heal = 1 }
	e.left = 16
	R.Tick(e)
	step(R, e, 1)
	e.target = { }
	R.Tick(e)
	local we
	for _, l in ipairs(windows()) do if field(l, "pid") == "12" then we = l end end
	check("a tango eaten early in the window is a use, not already running", we ~= nil and field(we, "under") == "0" and field(we, "used") == "tango", we)

	local c = MakeUnit({ pid = 10, hp = 480, maxhp = 500 })
	c.slots = { item_tango = 0 }
	c.items = { [0] = item("item_tango", 3, 7, 16) }
	idle(c, 3)
	c.target = { }
	R.Tick(c)
	local d = MakeUnit({ pid = 11, hp = 200, maxhp = 500 })
	idle(d, 3)
	d.target = { }
	R.Tick(d)
	local others = 0
	for _, l in ipairs(windows()) do if field(l, "pid") == "10" or field(l, "pid") == "11" then others = others + 1 end end
	check("too little HP missing, or no item in hand, is not a window", others == 0, others)
end

finish()
