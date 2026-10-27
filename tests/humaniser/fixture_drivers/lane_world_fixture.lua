-- Builds a lane_world.lua world from a fixture's `world` block. Used by the drivers that run real humaniser modules.
-- world: t, team (2|3, default 2), lane (top|mid|bot, default bot), humaniser config blocks (transitions, laneFight,
--        lane), heroes [{pid, side = ally|enemy, pos, lane, bot (default true), at = front | [x, y], hp (0-1),
--        health and maxHealth (absolute, instead of hp), hitAgo (s since an enemy hero last hit it), towerHitAgo, unseen
--        (s; hidden, last seen at its spot), alive, burst (GetEstimatedDamageToTarget), range, speed, regen}],
--        creeps [{id, side = ally|enemy, x, y, hp, dmg, aspd}] (lane creeps; y defaults to the lane's).
-- Units carry fixtureId (hero#pid, creep#id) for the observation.
-- `front` is the lane front at the default amount 0.5. Returns H, { [pid] = hero } and { [id] = creep }.
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")

local LANES = { top = dota.Lane.Top, mid = dota.Lane.Mid, bot = dota.Lane.Bot }

function LaneFixtureWorld(w, skill)
	local H = LaneFresh(w.lane_cfg or { Enable = true }, { skill = skill or 1, transitions = w.transitions or { Enable = true },
		laneFight = w.laneFight, states = w.states })
	T = w.t or 300
	CURRENT_TEAM = w.team or 2
	local enemyTeam = CURRENT_TEAM == 2 and 3 or 2
	-- Profile delays (notice, reaction) are 0 so a fixture's world is what the bot acts on.
	H.Profile.SampleDelay = function() return 0 end
	H.Orders.SetAnnouncer(function() end)
	local units = {}
	for _, h in ipairs(w.heroes or {}) do
		local lane = LANES[h.lane or w.lane or "bot"]
		local loc = (h.at == nil or h.at == "front") and Vector(0, LANE_Y[lane]) or Vector(h.at[1], h.at[2])
		local team = h.side == "enemy" and enemyTeam or CURRENT_TEAM
		local u = MakeUnit({ pid = h.pid, team = team, bot = h.bot ~= false, loc = loc, alive = h.alive })
		u.lane, u.pos = lane, h.pos
		if h.maxHealth then u.GetMaxHealth = function() return h.maxHealth end end
		if h.hp then u.hp = u:GetMaxHealth() * h.hp end
		if h.health then u.hp = h.health end
		u.estDamage, u.range, u.speed = h.burst, h.range, h.speed
		if h.regen then u.GetHealthRegen = function() return h.regen end end
		if h.hitAgo then u.heroHitAt = T - h.hitAgo end
		if h.towerHitAgo then u.towerHitAt = T - h.towerHitAgo end
		if h.unseen then
			u.hiddenFrom = setmetatable({}, { __index = function() return true end })
			LAST_SEEN[h.pid] = { location = loc, time_since_seen = h.unseen }
		end
		u.fixtureId = "hero#" .. h.pid
		units[h.pid] = u
	end
	local creeps = {}
	for _, c in ipairs(w.creeps or {}) do
		local y = c.y or LANE_Y[LANES[w.lane or "bot"]]
		local cr = MakeCreep({ team = c.side == "enemy" and enemyTeam or CURRENT_TEAM, x = c.x, y = y, hp = c.hp })
		cr.dmg, cr.aspd = c.dmg, c.aspd
		cr.fixtureId = "creep#" .. c.id
		creeps[c.id] = cr
	end
	return H, units, creeps
end

-- Actions the unit issued since index `from` of ACTIONS, as observation actions: attack(<id>) for AttackUnit, move for
-- MoveToLocation, MovePath and ClearActions are left out.
function LaneFixtureActions(pid, from)
	local out = {}
	for i = (from or 0) + 1, #ACTIONS do
		local a = ACTIONS[i]
		if a.pid == pid then
			if a.kind == "AttackUnit" then table.insert(out, { verb = "attack", target = a.args[1] and a.args[1].fixtureId })
			elseif a.kind == "MoveToLocation" then table.insert(out, { verb = "move" }) end
		end
	end
	return out
end
