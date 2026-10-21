dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, UnitType = dota.Lane, dota.UnitType

-- Extra stubs for chat commands (kept here so dota_stubs.lua stays core-only).
local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetMostRecentPing() return self.ping or { time = 0, location = Vector(0, 0), normal_ping = true } end
function UnitMeta:ActionImmediate_Ping() end
function UnitMeta:FindItemSlot(name) return self.items and self.items[name] or -1 end
function UnitMeta:GetAttackTarget() return self.attackTarget end
function GetUnitToUnitDistance(a, b) return GetUnitToLocationDistance(a, b.loc) end
function GetUnitList(t)
	if t == UnitType.EnemyHeroes then return UNITS[3] end
	if t == UnitType.AlliedHeroes then return UNITS[2] end
	return {}
end
LANE_FRONTS = {}
TOWERS = {}
function GetLaneFrontLocation(team, lane) return LANE_FRONTS[lane] end
function GetAncient(team) return { loc = Vector(-6000, -6000), GetLocation = function(self) return self.loc end, IsAlive = function() return true end, GetHealth = function() return 4500 end } end
function GetTower(team, id) return TOWERS[id] end

local ROSH = Vector(-3000, 2300)
local function reset()
	ResetWorld()
	LANE_FRONTS = { [Lane.Top] = Vector(-6000, 2000), [Lane.Mid] = Vector(0, 0), [Lane.Bot] = Vector(4000, -6000) }
	TOWERS = {}
end
local function fresh(cfg)
	local H = FreshHumaniser(cfg or { Enable = true })
	H.Pings.SetHelpers({ roshanLocation = function() return ROSH end, reservedSpots = function() return {} end })
	return H
end
local function named(u, hero) u.GetUnitName = function() return "npc_dota_hero_" .. hero end return u end
local function say(pid, text, teamOnly)
	T = T + 0.5 -- past the chat hub's duplicate window
	for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = pid, string = text, team_only = teamOnly ~= false }) end
end
local function orders(H) return H.Orders.GetActive(2) end
local function one(H) local l = orders(H) return #l == 1 and l[1] or nil end

-- A team: human 0 plus bots 1-4 (lion = slot 3, pid 2; two Linas, as OHA allows duplicate heroes).
local function team()
	local human = MakeUnit({ pid = 0, bot = false, loc = Vector(0, 0) })
	local bots = {
		named(MakeUnit({ pid = 1, loc = Vector(500, 0) }), "crystal_maiden"),
		named(MakeUnit({ pid = 2, loc = Vector(1000, 0) }), "lion"),
		named(MakeUnit({ pid = 3, loc = Vector(5000, 0) }), "lina"),
		named(MakeUnit({ pid = 4, loc = Vector(9000, 0) }), "lina"),
	}
	return human, bots
end

-- Parsing: names, aliases, lanes, selectors, legacy, and names left to FretBots
do
	reset()
	local H = fresh()
	team()
	named(MakeUnit({ pid = 6, loc = Vector(0, 0) }), "medusa")
	local P = function(text) return H.Commands.Parse(text, 2) end
	local p = P("!def mid")
	check("def mid", p and p.name == "def" and p.args[1] == "mid" and p.onlyPIDs == nil)
	check("alias defend + case", P("!DEFEND t").name == "def")
	check("alias !g", P("!g").name == "group")
	check("roshan alias", P("!roshan").name == "rosh")
	local slot = P("!3 push bot")
	check("slot selector", slot and slot.name == "push" and slot.onlyPIDs[1] == 2 and slot.args[1] == "bot", slot and slot.onlyPIDs and slot.onlyPIDs[1])
	local hero = P("!lion def top")
	check("hero selector", hero and hero.name == "def" and hero.onlyPIDs[1] == 2)
	check("hero selector with second !", P("!lion !def top").onlyPIDs[1] == 2)
	check("squashed multi-word name", P("!crystalmaiden g").onlyPIDs[1] == 1)
	check("slot of a human is not a bot target", P("!1 def") == nil)
	check("ambiguous name rejected (two Linas)", P("!lin def") == nil and P("!lina def") == nil)
	check("FretBots names never become selectors", P("!me def") == nil and P("!diff 5") == nil and P("!info") == nil)
	check("unknown command ignored", P("!dance") == nil)
	check("targeted farm/bhelp not allowed", P("!lion farm") == nil and P("!lion bhelp") == nil)
	check("legacy defend alias", P("-都来守家").name == "def")
	check("plain chat ignored", P("def mid") == nil)
end

-- Lanes: t/m/b are map lanes; safe/off mirror by side
do
	reset()
	local H = fresh()
	local L = H.Commands.ParseLane
	check("t/m/b", L("t", 2) == Lane.Top and L("m", 3) == Lane.Mid and L("b", 2) == Lane.Bot)
	check("radiant safe = bot, off = top", L("safe", 2) == Lane.Bot and L("off", 2) == Lane.Top)
	check("dire safe = top, off = bot", L("safe", 3) == Lane.Top and L("off", 3) == Lane.Bot)
	check("junk lane", L("xyz", 2) == nil)
end

-- !def mid from a human ally in team chat: DEFEND mid, every bot responds, read with the chat delay
do
	reset()
	local H = fresh()
	local human, bots = team()
	H.Tick(bots[1])
	say(0, "!def mid")
	local o = one(H)
	check("def posted", o and o.type == "DEFEND" and o.lane == Lane.Mid and o.delayKind == "chat")
	check("def responders: all bots", o and #o.responders == 4, o and #o.responders)
	check("def not yet read", H.Orders.GetFor(bots[1]) == nil)
end

-- Issuer filtering: all-chat, enemy-team human and bots are ignored
do
	reset()
	local H = fresh({ Enable = true, Debug = true })
	local human, bots = team()
	MakeUnit({ pid = 5, team = 3, bot = false })
	H.Tick(bots[1])
	local printed = {}
	local oldPrint = print
	print = function(s) table.insert(printed, s) end
	say(0, "!def mid", false)
	say(5, "!def mid", true)
	say(1, "!def mid", true)
	H.Tick(bots[1]) -- callback diagnostics are printed on the next Tick
	print = oldPrint
	check("all-chat / enemy / bot issuers post nothing", #orders(H) == 0, #orders(H))
	local warned = false
	for _, line in ipairs(printed) do if string.find(line, "WARN", 1, true) and string.find(line, "player 5", 1, true) then warned = true end end
	check("enemy issuer logged", warned)
end

-- Targeting: !lion push bot moves only Lion
do
	reset()
	local H = fresh()
	local human, bots = team()
	H.Tick(bots[1])
	say(0, "!lion push bot")
	local o = one(H)
	check("targeted push", o and o.type == "PUSH" and o.lane == Lane.Bot and #o.responders == 1 and o.responders[1] == 2)
	T = T + 5
	check("other bots ignore it", H.Orders.GetFor(bots[1]) == nil and H.Orders.GetFor(bots[2]) ~= nil)
end

-- !def without a lane picks the lane whose front is deepest toward our ancient
do
	reset()
	local H = fresh()
	local human, bots = team()
	H.Tick(bots[1])
	say(0, "!def")
	local o = one(H)
	check("default defend lane = most pushed", o and o.lane == Lane.Top, o and o.lane)
	MakeUnit({ pid = 7, team = 3, loc = Vector(4000, -5800) })
	say(0, "!def")
	o = orders(H)[#orders(H)]
	check("visible enemies outweigh depth", o and o.lane == Lane.Bot, o and o.lane)
end

-- !rosh uses the current pit; !g gathers on the issuer; repeating a command re-posts it
do
	reset()
	local H = fresh()
	local human, bots = team()
	H.Tick(bots[1])
	say(0, "!rosh")
	local o = one(H)
	check("rosh at pit, everyone", o and o.type == "ROSHAN" and o.location == ROSH and #o.responders == 4)
	human.loc = Vector(-2000, -2000)
	say(0, "!g")
	local g
	for _, x in ipairs(orders(H)) do if x.type == "GATHER" then g = x end end
	check("group at issuer", g and g.location.x == -2000)
	local firstKey = g.sourceKey
	say(0, "!g")
	for _, x in ipairs(orders(H)) do if x.type == "GATHER" then g = x end end
	check("repeat re-posts with a new key", g and g.sourceKey ~= firstKey, g and g.sourceKey)
end

-- !go pairs with the issuer's last ping (and the hero standing there)
do
	reset()
	local H = fresh()
	local human, bots = team()
	local enemy = MakeUnit({ pid = 7, team = 3, loc = Vector(3000, 3000) })
	H.Tick(bots[1])
	say(0, "!go")
	check("go without ping or target does nothing", #orders(H) == 0)
	human.ping = { time = T, location = Vector(3050, 3000), normal_ping = true }
	say(0, "!go")
	local o = one(H)
	check("go attacks the pinged hero", o and o.type == "ATTACK" and o.target == enemy and #o.responders == 4)
end

-- !back cancels everything and sends nearby bots to the nearest unthreatened tower
do
	reset()
	local H = fresh()
	local human, bots = team()
	TOWERS[0] = setmetatable({ alive = true, loc = Vector(800, 0) }, { __index = UnitMeta })
	TOWERS[1] = setmetatable({ alive = true, loc = Vector(-1500, 0) }, { __index = UnitMeta })
	MakeUnit({ pid = 7, team = 3, loc = Vector(900, 100) })
	H.Tick(bots[1])
	say(0, "!def mid")
	say(0, "!back")
	local o = one(H)
	check("back replaces all orders", o and o.type == "BACK")
	check("back avoids the threatened tower", o and o.location.x == -1500, o and o.location.x)
	check("back responders: bots near issuer only", o and table.concat(o.responders, ",") == "1,2", o and table.concat(o.responders, ","))
end

-- !farm releases everything; the lowest-slot bot answers once in its own Tick
do
	reset()
	local H = fresh()
	local said = {}
	H.Orders.SetAnnouncer(function(bot, key) table.insert(said, bot:GetPlayerID() .. ":" .. key) end)
	local human, bots = team()
	H.Tick(bots[2])
	say(0, "!rosh")
	say(0, "!farm")
	check("farm cancels", #orders(H) == 0)
	H.Tick(bots[2])
	H.Tick(bots[1])
	H.Tick(bots[1])
	check("one release line from bot 1", #said == 1 and said[1] == "1:say_order_ack_release", table.concat(said, " "))
end

-- !bhelp prints from one bot
do
	reset()
	local H = fresh()
	local said = {}
	H.Orders.SetAnnouncer(function(bot, key) table.insert(said, bot:GetPlayerID() .. ":" .. key) end)
	local human, bots = team()
	for _, b in ipairs(bots) do H.Tick(b) end
	say(0, "!bhelp")
	for _, b in ipairs(bots) do H.Tick(b) end
	check("help once", #said == 1 and said[1] == "1:say_cmd_help" and #orders(H) == 0, table.concat(said, " "))
end

-- !smoke: "no smoke" when nobody has one; otherwise the first responder holding smoke pops it with 3 heroes close
do
	reset()
	local H = fresh()
	local said = {}
	H.Orders.SetAnnouncer(function(bot, key) table.insert(said, bot:GetPlayerID() .. ":" .. key) end)
	local human, bots = team()
	H.Tick(bots[1])
	say(0, "!smoke")
	H.Tick(bots[1])
	check("no smoke: no order, one reply", #orders(H) == 0 and said[1] == "1:say_cmd_no_smoke", table.concat(said, " "))

	bots[2].items = { item_smoke_of_deceit = 2 }
	bots[3].items = { item_smoke_of_deceit = 0 }
	say(0, "!smoke")
	local o = one(H)
	check("smoke follows the issuer", o and o.type == "SMOKE" and o.target == human)
	T = T + 5
	check("not yet gathered", H.Commands.ShouldUseOrderedSmoke(bots[2]) == false)
	bots[2].loc = Vector(200, 0)
	bots[1].loc = Vector(100, 0)
	bots[3].loc = Vector(150, 0)
	T = T + 0.1
	check("nearest holder pops smoke", H.Commands.ShouldUseOrderedSmoke(bots[2]) == true)
	check("other holder does not", H.Commands.ShouldUseOrderedSmoke(bots[3]) == false)
end

-- Two module instances seeing the same chat derive the same order and responders
do
	reset()
	local human, bots = team()
	local A = fresh()
	A.Tick(bots[1])
	local B = fresh()
	B.Tick(bots[4])
	check("two callbacks (one per instance)", #CHAT_CALLBACKS == 2)
	say(0, "!push top")
	local oa, ob = one(A), one(B)
	check("instances agree", oa and ob and oa.sourceKey == ob.sourceKey and oa.lane == ob.lane
		and table.concat(oa.responders, ",") == table.concat(ob.responders, ","))
end

-- Kill switches
do
	reset()
	local H = fresh({ Enable = true, Commands = { Enable = false } })
	local human, bots = team()
	H.Tick(bots[1])
	say(0, "!def mid")
	check("commands disabled: nothing posted", #orders(H) == 0)
	GAME_STATE = GAME_STATE_PRE_GAME
	local H2 = fresh()
	H2.Tick(bots[1])
	say(0, "!def mid")
	check("not in progress: nothing posted", #orders(H2) == 0)
end

-- In-game, the hub installed during pre-game never received chat: hero_selection.lua re-installs its own callback
-- every pre-game frame. With an engine that keeps only the latest callback, the hub must install after the horn.
do
	reset()
	local saved = InstallChatCallback
	InstallChatCallback = function(fn) CHAT_CALLBACKS = { fn } end
	local H = fresh()
	local human, bots = team()
	GAME_STATE = GAME_STATE_PRE_GAME
	for _ = 1, 3 do
		H.Tick(bots[1])
		InstallChatCallback(function() end) -- hero_selection's per-frame re-install
	end
	GAME_STATE = GAME_STATE_GAME_IN_PROGRESS
	H.Tick(bots[1])
	human.loc = Vector(-2000, -2000)
	say(0, "!g")
	local g
	for _, x in ipairs(orders(H)) do if x.type == "GATHER" then g = x end end
	check("hub installed after the horn survives pre-game re-installs", g ~= nil and g.location.x == -2000)
	InstallChatCallback = saved
end

finish()
