dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local FRONT = Vector(0, -5000)
local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = 2, bot = o.bot, loc = o.loc or FRONT, hp = o.hp })
	u.lane, u.pos, u.mode = Lane.Bot, o.pos, o.mode or 0
	return u
end

local function copy(t, over)
	local r = {}
	for k, v in pairs(t) do r[k] = v end
	for k, v in pairs(over or {}) do r[k] = v end
	return r
end

-- IsBusyPure: every row flips one input from the all-clear base.
do
	local B = LaneFresh({ Enable = true }, { skill = 0.5 }).Transitions.Busy
	local base = { order = false, campJob = false, fighting = false, retreating = false, hp = 1, mana = 1, dead = false,
		windowEnd = 200, carrying = false, humanPingOnLane = false }
	local busy, why = B.IsBusyPure(base)
	check("busy: all-clear base is free", busy == false and why == "", why)
	local rows = {
		{ "order", { order = true } }, { "job", { campJob = true } }, { "fight", { fighting = true } },
		{ "retreat", { retreating = true } }, { "hp", { hp = 0.49 } }, { "mana", { mana = 0.29 } },
		{ "dead", { dead = true } }, { "item", { carrying = true } }, { "ping", { humanPingOnLane = true } },
	}
	for _, row in ipairs(rows) do
		local b, w = B.IsBusyPure(copy(base, row[2]))
		check("busy: " .. row[1], b == true and w == row[1], w)
	end
	check("busy: hp exactly at the threshold is free", B.IsBusyPure(copy(base, { hp = 0.5 })) == false)
	check("busy: dead but back before the window ends is free", B.IsBusyPure(copy(base, { dead = true, respawnAfter = 190 })) == false)
	local b, w = B.IsBusyPure(copy(base, { dead = true, respawnAfter = 210 }))
	check("busy: dead past the window counts as dead", b == true and w == "dead", w)
	b, w = B.IsBusyPure(copy(base, { dead = true, respawnAfter = 190, hp = 0, mana = 0 }))
	check("busy: respawning in time is not blamed on 0 hp", b == false, w)
end

-- LaneCanSparePure
do
	local B = LaneFresh({ Enable = true }, { skill = 0.5 }).Transitions.Busy
	local base = { eqPos = 0, plan = "NEUTRAL", coreHealthy = true, partnerHP = 1, partnerCreepAggro = 0,
		enemies = { { visible = true, sinceSeen = 0, inKillPosition = false } }, enemyTpIncoming = false,
		humanAskedStay = false, strict = false, enemyNearPartner = false }
	local function spare(over) return B.LaneCanSparePure(copy(base, over)) end
	check("spare: clear base", spare() == true)
	check("spare: pushed lane under HOLD", spare({ eqPos = -0.3, plan = "HOLD" }) == false)
	check("spare: pushed lane under NEUTRAL", spare({ eqPos = -0.3 }) == false)
	check("spare: pushed lane under FREEZE with a healthy core", spare({ eqPos = -0.3, plan = "FREEZE" }) == true)
	check("spare: pushed lane under FREEZE with an unhealthy core", spare({ eqPos = -0.3, plan = "FREEZE", coreHealthy = false }) == false)
	check("spare: partner hp 0.55", spare({ partnerHP = 0.55 }) == false)
	check("spare: partner hp 0.65 is fine", spare({ partnerHP = 0.65 }) == true)
	check("spare: 2 creeps on the partner is fine", spare({ partnerCreepAggro = 2 }) == true)
	check("spare: 3 creeps on the partner", spare({ partnerCreepAggro = 3 }) == false)
	check("spare: enemy missing 6 s", spare({ enemies = { { visible = false, sinceSeen = 6, inKillPosition = false } } }) == false)
	check("spare: enemy out of sight 3 s is fine", spare({ enemies = { { visible = false, sinceSeen = 3, inKillPosition = false } } }) == true)
	check("spare: enemy in kill position", spare({ enemies = { { visible = true, sinceSeen = 0, inKillPosition = true } } }) == false)
	check("spare: tp incoming", spare({ enemyTpIncoming = true }) == false)
	check("spare: human asked to stay", spare({ humanAskedStay = true }) == false)
	check("strict: partner hp 0.7", spare({ strict = true, partnerHP = 0.7 }) == false)
	check("strict: partner hp 0.8 is fine", spare({ strict = true, partnerHP = 0.8 }) == true)
	check("strict: enemy near the partner", spare({ strict = true, enemyNearPartner = true }) == false)
	check("non-strict ignores an enemy near the partner", spare({ enemyNearPartner = true }) == true)
	check("non-strict accepts hp 0.7", spare({ partnerHP = 0.7 }) == true)
end

-- Adapters
local function adapterWorld()
	local H = LaneFresh({ Enable = true }, { skill = 0.5 })
	T = 100
	CURRENT_TEAM = 2
	return H
end

do
	local H = adapterWorld()
	local support = unit({ pid = 5, bot = true, pos = 5 })
	local ok, why = H.Transitions.Busy.LaneCanSpare(support, false)
	check("solo lane is never spare", ok == false and why == "solo", why)
end

do
	local H = adapterWorld()
	local core = unit({ pid = 1, bot = false, pos = 1 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	local ok, why = H.Transitions.Busy.LaneCanSpare(support, false)
	check("duo lane with a healthy core can spare", ok == true, why)
	core.hp = 40
	ok, why = H.Transitions.Busy.LaneCanSpare(support, false)
	check("duo lane with a hurt core cannot", ok == false and why == "partner hp", why)
end

do
	local H = adapterWorld()
	local core = unit({ pid = 1, bot = false, pos = 1 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	local function creepsOn(n)
		for _ = 1, n do MakeCreep({ team = 3, x = 200, y = -5000, target = core }) end
	end
	creepsOn(2)
	check("2 creeps on the partner still spares", H.Transitions.Busy.LaneCanSpare(support, false) == true)
	creepsOn(1)
	H.Lane.LaneState.ResetCache()
	local ok, why = H.Transitions.Busy.LaneCanSpare(support, false)
	check("3 creeps on the partner cannot", ok == false and why == "creep aggro", why)
end

do
	local H = adapterWorld()
	unit({ pid = 1, bot = false, pos = 1 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	local foe = MakeUnit({ pid = 10, team = 3, loc = Vector(600, -5000) })
	check("visible enemy at a healthy partner is fine", H.Transitions.Busy.LaneCanSpare(support, false) == true)
	foe.CanBeSeen = function() return false end
	LAST_SEEN[10] = { location = Vector(600, -5000), time_since_seen = 6 }
	H.Lane.LaneState.ResetCache()
	local ok, why = H.Transitions.Busy.LaneCanSpare(support, false)
	check("laner missing for 6 s blocks", ok == false and why == "enemy missing", why)
	LAST_SEEN[10] = { location = Vector(600, -5000), time_since_seen = 3 }
	H.Lane.LaneState.ResetCache()
	check("laner out of sight for 3 s does not", H.Transitions.Busy.LaneCanSpare(support, false) == true)
	LAST_SEEN[10] = { location = Vector(6000, 5000), time_since_seen = 30 }
	H.Lane.LaneState.ResetCache()
	check("a hero missing far from the lane does not", H.Transitions.Busy.LaneCanSpare(support, false) == true)
end

do
	local H = adapterWorld()
	unit({ pid = 1, bot = false, pos = 1 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	check("strict: no enemy near is fine", H.Transitions.Busy.LaneCanSpare(support, true) == true)
	MakeUnit({ pid = 10, team = 3, loc = Vector(900, -5000) })
	H.Lane.LaneState.ResetCache()
	local ok, why = H.Transitions.Busy.LaneCanSpare(support, true)
	check("strict: enemy within 1200 of the partner blocks", ok == false and why == "enemy near", why)
	check("non-strict allows the same enemy", H.Transitions.Busy.LaneCanSpare(support, false) == true)
end

do
	local H = adapterWorld()
	local bot = unit({ pid = 5, bot = true, pos = 5 })
	local busy, why = H.Transitions.Busy.IsBusy(bot, 120)
	check("adapter: fresh bot is free", busy == false and why == "", why)
	bot.mode = BotMode.Retreat
	busy, why = H.Transitions.Busy.IsBusy(bot, 120)
	check("adapter: retreat mode", busy == true and why == "retreat", why)
	bot.mode = BotMode.TeamRoam
	busy, why = H.Transitions.Busy.IsBusy(bot, 120)
	check("adapter: team roam is a fight", busy == true and why == "fight", why)
	bot.mode = 0
	bot.mana = 20
	busy, why = H.Transitions.Busy.IsBusy(bot, 120)
	check("adapter: low mana", busy == true and why == "mana", why)
	bot.mana = 100
	bot.alive, bot.respawn = false, 10
	busy, why = H.Transitions.Busy.IsBusy(bot, 120)
	check("adapter: dead but back inside the window is free", busy == false, why)
	bot.respawn = 40
	busy, why = H.Transitions.Busy.IsBusy(bot, 120)
	check("adapter: dead past the window", busy == true and why == "dead", why)
	bot.alive = true
	H.Lane.Hooks.SetBusyProbe(function() return true end)
	busy, why = H.Transitions.Busy.IsBusy(bot, 120)
	check("adapter: busy probe counts as fighting", busy == true and why == "fight", why)
end

do
	local H = adapterWorld()
	local human = unit({ pid = 1, bot = false, pos = 1 })
	local bot = unit({ pid = 5, bot = true, pos = 5 })
	function human:GetMostRecentPing() return self.ping or { time = 0, location = Vector(0, 0), normal_ping = true } end
	check("no ping: free", H.Transitions.Busy.IsBusy(bot, 120) == false)
	human.ping = { time = 90, location = Vector(100, -4900), normal_ping = true }
	H.Pings.Scan(2)
	local busy, why = H.Transitions.Busy.IsBusy(bot, 120)
	check("human ping on the lane makes the bot busy", busy == true and why == "ping", why)
	T = 125
	busy, why = H.Transitions.Busy.IsBusy(bot, 150)
	check("ping older than the window no longer counts", busy == false, why)
	T = 100
	human.ping = { time = 95, location = Vector(0, 3000), normal_ping = true }
	H.Pings.Scan(2)
	check("far ping is not on the lane", H.Pings.HumanPingNear(2, FRONT, 50, 30) == false and H.Pings.HumanPingNear(2, Vector(0, 3000), 500, 30) == true)
end

do
	local H = adapterWorld()
	local human = unit({ pid = 1, bot = false, pos = 1 })
	function human:GetMostRecentPing() return self.ping or { time = 0, location = Vector(0, 0), normal_ping = true } end
	human.ping = { time = 50, location = Vector(0, -5000), normal_ping = true }
	T = 95
	H.Pings.Scan(2)
	check("pings are kept for 30 s", H.Pings.HumanPingNear(2, FRONT, 100, 60) == true)
	human.ping = { time = 100, location = Vector(3000, 3000), normal_ping = true }
	T = 100
	H.Pings.Scan(2)
	check("old ping is pruned once a newer one lands past 30 s", H.Pings.HumanPingNear(2, FRONT, 100, 1000) == false)
	check("new ping is recorded where it landed", H.Pings.HumanPingNear(2, Vector(3000, 3000), 100, 5) == true)
	check("other team sees nothing", H.Pings.HumanPingNear(3, Vector(3000, 3000), 100, 5) == false)
end

finish()
