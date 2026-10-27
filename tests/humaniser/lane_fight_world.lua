-- Lane-fight world: one laner per side in the bottom lane, scored and played frame by frame in engine order.
-- Shared by test_lane_fight.lua and the lane_fight fixture driver. Not a test_ file, so run.js skips it.
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local BOT_Y = LANE_Y[Lane.Bot]
local FRAME = 1 / 30
-- Dota scores all of a bot's modes in one round every ~0.31 s, in a fixed order (retreat before team_roam).
local ROUND = 0.31

function LaneFightAbility(name, o)
	o = o or {}
	return {
		GetName = function() return name end,
		GetLevel = function() return o.level or 1 end,
		IsUltimate = function() return o.ult == true end,
		IsHidden = function() return false end,
		IsNull = function() return false end,
		GetCooldown = function() return o.cd or 12 end,
	}
end

-- Bottom lane, one laner per side; fronts meet at x = 0 with one enemy creep there. The bot stands at x = -500, 800
-- from the enemy: out of attack range (550) but within the 950 a trade may start from. The bot is level 2 and the enemy
-- level 1, so the read gives a "level" window. `sign` mirrors x so our side is always negative x.
function LaneFightWorld(o)
	o = o or {}
	local team = o.team or 2
	local other = team == 2 and 3 or 2
	local sign = team == 2 and 1 or -1
	local laneFight = o.laneFight or {}
	if laneFight.Enable == nil then laneFight.Enable = true end
	local H = LaneFresh({ Enable = true }, { skill = o.skill or 1, laneFight = laneFight, telemetry = { Enable = true },
		intent = o.intent, enable = o.enable, debug = o.debug })
	T = 100
	CURRENT_TEAM = team
	LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.5, 0.5
	local bot = MakeUnit({ pid = 1, team = team, loc = Vector(sign * (o.botX or -500), BOT_Y), level = o.botLevel or 2, hp = o.botHP or 100,
		mode = BotMode.Laning })
	bot.pos, bot.lane = 5, Lane.Bot
	bot.estDamage = o.burst or 0
	OBSERVER = bot
	local enemy = MakeUnit({ pid = 6, team = other, loc = Vector(sign * (o.enemyX or 300), BOT_Y), level = o.enemyLevel or 1,
		hp = o.enemyHP or 100 })
	enemy.lane = Lane.Bot
	enemy.abilities = { [0] = LaneFightAbility("lion_impale", { cd = 12 }), [5] = LaneFightAbility("lion_finger_of_death", { ult = true, cd = 100 }) }
	local creep = MakeCreep({ team = other, x = sign * 100, y = BOT_Y })
	local W = { H = H, bot = bot, enemy = enemy, sign = sign, creep = creep, LF = H.LaneFight, lines = {}, nextRound = T,
		retreat = 0.2, laning = 0.45, roam = 0.2, attack = 0 }
	H.Telemetry.SetSink(function(l) table.insert(W.lines, l) end)
	function W.at(x) bot.loc = Vector(sign * x, BOT_Y) end
	function W.events(ev, pattern)
		local n = 0
		for _, l in ipairs(W.lines) do
			if l:find("ev=" .. ev, 1, true) and (pattern == nil or l:find(pattern, 1, true)) then n = n + 1 end
		end
		return n
	end
	function W.age(phase) return H.Intent.ClaimAge(bot, "lanefight:" .. phase, BotMode.TeamRoam) end
	return W
end

-- One scoring round in engine order; the engine then picks the highest desire, the active mode's ×1.1.
function LaneFightScore(W)
	local H, bot = W.H, W.bot
	if W.beforeRetreat then W.beforeRetreat() end
	local d = {}
	d.retreat = H.Intent.Resolve(bot, BotMode.Retreat, W.retreat)
	d.laning = H.Intent.Resolve(bot, BotMode.Laning, W.laning)
	d.roam = H.Intent.Resolve(bot, BotMode.TeamRoam, H.LaneFight.RoamDesire(bot, W.roam))
	-- W.luaAttack: OHA's Lua attack mode (some heroes), which goes through Intent; W.attack: Valve's, which does not.
	d.attack = W.luaAttack ~= nil and H.Intent.Resolve(bot, BotMode.Attack, W.luaAttack) or W.attack
	d.farm = W.farm ~= nil and H.Intent.Resolve(bot, BotMode.Farm, W.farm) or 0
	local best, bestMode = -1, nil
	for _, m in ipairs({ { BotMode.Retreat, d.retreat }, { BotMode.Laning, d.laning }, { BotMode.TeamRoam, d.roam }, { BotMode.Attack, d.attack },
		{ BotMode.Farm, d.farm } }) do
		local eff = m[1] == bot.mode and m[2] * 1.1 or m[2]
		if eff > best then best, bestMode = eff, m[1] end
	end
	bot.mode = bestMode
	W.last = d
	return d
end

-- Frames at 30 fps in engine order: a scoring round every ROUND, team_roam's Think every frame while it is the active
-- mode, then the humaniser tick (ItemUsageThink): LaneFight.Tick, then Intent.Tick (mode switches, stickiness).
function LaneFightPlay(W, seconds)
	local stop = T + seconds - 1e-9
	while T < stop do
		if T >= W.nextRound - 1e-9 then
			LaneFightScore(W)
			W.nextRound = W.nextRound + ROUND
		end
		if W.bot.mode == BotMode.TeamRoam then
			if W.LF.Think(W.bot) then W.acted = (W.acted or 0) + 1 end
		end
		W.LF.Tick(W.bot)
		W.H.Intent.Tick(W.bot)
		if W.onFrame then W.onFrame() end
		T = T + FRAME
	end
end

