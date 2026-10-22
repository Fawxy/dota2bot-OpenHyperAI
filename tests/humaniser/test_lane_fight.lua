dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local BOT_Y = LANE_Y[Lane.Bot]
local FRAME = 1 / 30
-- Dota scores all of a bot's modes in one round every ~0.31 s, in a fixed order (retreat before team_roam).
local ROUND = 0.31

local function ability(name, o)
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
local function world(o)
	o = o or {}
	local team = o.team or 2
	local other = team == 2 and 3 or 2
	local sign = team == 2 and 1 or -1
	local laneFight = o.laneFight or {}
	if laneFight.Enable == nil then laneFight.Enable = true end
	local H = LaneFresh({ Enable = true }, { skill = o.skill or 1, laneFight = laneFight, telemetry = { Enable = true },
		intent = o.intent, enable = o.enable })
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
	enemy.abilities = { [0] = ability("lion_impale", { cd = 12 }), [5] = ability("lion_finger_of_death", { ult = true, cd = 100 }) }
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
local function score(W)
	local H, bot = W.H, W.bot
	if W.beforeRetreat then W.beforeRetreat() end
	local d = {}
	d.retreat = H.Intent.Resolve(bot, BotMode.Retreat, W.retreat)
	d.laning = H.Intent.Resolve(bot, BotMode.Laning, W.laning)
	d.roam = H.Intent.Resolve(bot, BotMode.TeamRoam, H.LaneFight.RoamDesire(bot, W.roam))
	d.attack = W.attack
	local best, bestMode = -1, nil
	for _, m in ipairs({ { BotMode.Retreat, d.retreat }, { BotMode.Laning, d.laning }, { BotMode.TeamRoam, d.roam }, { BotMode.Attack, d.attack } }) do
		local eff = m[1] == bot.mode and m[2] * 1.1 or m[2]
		if eff > best then best, bestMode = eff, m[1] end
	end
	bot.mode = bestMode
	W.last = d
	return d
end

-- Frames at 30 fps: a scoring round every ROUND, and team_roam's Think every frame while it is the active mode.
local function play(W, seconds)
	local stop = T + seconds - 1e-9
	while T < stop do
		if T >= W.nextRound - 1e-9 then
			score(W)
			W.nextRound = W.nextRound + ROUND
		end
		if W.bot.mode == BotMode.TeamRoam then
			if W.LF.Think(W.bot) then W.acted = (W.acted or 0) + 1 end
		end
		if W.onFrame then W.onFrame() end
		T = T + FRAME
	end
end

local function hasStart(W, phase) return W.events("lanefight_start", "phase=" .. phase) > 0 end

-- --------------------------------------------------------------------------------------- trade start and claim

for _, team in ipairs({ 2, 3 }) do
	local tag = team == 2 and " (radiant)" or " (dire)"
	local W = world({ team = team })
	score(W)
	check("one read with a window starts nothing" .. tag, W.age("trade") == nil and not hasStart(W, "trade"))
	T = T + ROUND
	W.nextRound = T
	play(W, FRAME)
	check("a noticed trade window posts a FIGHT floor on team_roam" .. tag,
		W.H.Intent.Explain(W.bot, BotMode.TeamRoam):find("lanefight:trade", 1, true) ~= nil, W.H.Intent.Explain(W.bot, BotMode.TeamRoam))
	check("the floor lifts team_roam to TradeFloor" .. tag, near(W.last.roam, 0.75), W.last.roam)
	check("lanefight_start names the phase, target and window" .. tag,
		W.events("lanefight_start", "phase=trade target=6 window=level") == 1, table.concat(W.lines, "\n"))
	check("team_roam wins the round" .. tag, W.bot.mode == BotMode.TeamRoam)
	check("Target is the enemy" .. tag, W.LF.Target(W.bot) == W.enemy)
	check("Describe shows the phase and window" .. tag, W.LF.Describe(W.bot):find("window=level", 1, true) ~= nil
		and W.LF.Describe(W.bot):find("phase=trade", 1, true) ~= nil, W.LF.Describe(W.bot))
	ACTIONS = {}
	play(W, FRAME)
	check("out of range, Think moves towards the target" .. tag, #ActionsOf(1, "MoveToLocation") >= 1 and #ActionsOf(1, "AttackUnit") == 0)
	W.at(-200)
	ACTIONS = {}
	play(W, FRAME)
	local attacks = ActionsOf(1, "AttackUnit")
	check("in range, Think sets the target and attacks it" .. tag, #attacks >= 1 and attacks[1].args[1] == W.enemy and attacks[1].args[2] == false
		and W.bot.setTarget == W.enemy)
end

-- ------------------------------------------------------------------------------------------- trade ends

do
	local W = world()
	play(W, 0.7)
	check("setup: the trade runs", W.age("trade") ~= nil)
	W.bot.hp = 25
	play(W, ROUND)
	check("trade ends and releases its claim below StopHP", W.age("trade") == nil
		and W.H.Intent.Explain(W.bot, BotMode.TeamRoam):find("lanefight", 1, true) == nil, W.H.Intent.Explain(W.bot, BotMode.TeamRoam))
	check("ending clears the bot's target", W.bot.setTarget == nil and W.bot.setTargets[#W.bot.setTargets] == "nil")
	check("the end is logged with its reason", W.events("lanefight_end", "phase=trade reason=low-hp") == 1, table.concat(W.lines, "\n"))
end

do
	local W = world({ botX = -800 })
	play(W, 2)
	check("no trade on a target beyond attack range + 400", not hasStart(W, "trade") and W.events("lanefight_gate", "gate=range") == 1,
		table.concat(W.lines, "\n"))
end

do
	-- Out of range for 1.5 s after the start, then in range: the clock starts at the first in-range attack order.
	local W = world()
	play(W, 0.7)
	local started = T
	play(W, 1.5)
	W.at(-200)
	play(W, 2.2)
	check("the trade clock starts at the first in-range attack, not at the start", W.events("lanefight_end") == 0 and W.age("trade") ~= nil,
		T - started)
	play(W, 0.6)
	check("the trade ends TradeDuration after its first attack", W.events("lanefight_end", "reason=duration") == 1, table.concat(W.lines, "\n"))
	local W2 = world()
	play(W2, 3.4)
	check("a trade that never gets in range ends after TradeDuration", W2.events("lanefight_end", "reason=reach") == 1,
		table.concat(W2.lines, "\n"))
end

local function hitWorld(onCreep)
	local W = world()
	W.at(-200)
	play(W, 0.7)
	local started = T
	W.bot.target = onCreep and W.creep or W.enemy
	W.onFrame = function()
		if T - started >= 0.5 * ((W.swings or 0) + 1) then
			W.swings = (W.swings or 0) + 1
			W.bot.lastAttack = T
		end
	end
	return W, started
end

do
	local W = hitWorld(false)
	play(W, 1.7)
	check("trade ends after TradeHits landed attacks", W.events("lanefight_end", "reason=hits hits=3") == 1 and W.age("trade") == nil,
		table.concat(W.lines, "\n"))
	local W2 = hitWorld(true)
	play(W2, 1.7)
	check("attacks on a creep are not landed hits on the target", W2.events("lanefight_end") == 0 and W2.age("trade") ~= nil)
	play(W2, 1.5)
	check("trade ends after TradeDuration", W2.events("lanefight_end", "reason=duration") == 1, table.concat(W2.lines, "\n"))
	play(W2, 3)
	check("one trade per window instance", W2.events("lanefight_start") == 1, W2.events("lanefight_start"))
end

for _, case in ipairs({ { field = "unkillable", reason = "unkillable" }, { field = "magicImmune", reason = "magic_immune" } }) do
	local W = world()
	W.at(-200)
	play(W, 0.7)
	W.enemy[case.field] = true
	local acted = W.LF.Think(W.bot)
	check("abort when the target becomes " .. case.field .. " (within one Think)", acted == false and W.age("trade") == nil
		and W.events("lanefight_end", "reason=" .. case.reason) == 1, table.concat(W.lines, "\n"))
end

do
	local W = world()
	W.laning = 0.9
	play(W, 0.7)
	check("setup: the trade started while laning outbids team_roam", hasStart(W, "trade") and W.bot.mode == BotMode.Laning)
	play(W, 0.6)
	check("a mode other than team_roam or attack does not end it within 1 s", W.events("lanefight_end") == 0)
	local guard = 0
	while W.events("lanefight_end") == 0 and guard < 60 do play(W, FRAME) guard = guard + 1 end
	check("trades are not protected: laning at 0.9 ends a trade after 1 s", W.events("lanefight_abort", "reason=mode:laning") == 1
		and W.events("lanefight_end", "reason=mode:laning") == 1 and W.age("trade") == nil and T - 100.31 < 1.7, table.concat(W.lines, "\n"))
	play(W, 1)
	check("a trade that never took over does not use up its window instance", W.events("lanefight_start", "phase=trade") == 2,
		W.events("lanefight_start", "phase=trade"))
end

do
	local W = world()
	W.attack = 0.95
	W.bot.target = W.enemy
	play(W, 3.6)
	check("Valve's attack mode taking over does not abort the trade", W.bot.mode == BotMode.Attack and W.events("lanefight_abort") == 0
		and W.events("lanefight_end", "reason=duration") == 1, table.concat(W.lines, "\n"))
end

-- ------------------------------------------------------------------------------------------------ commit

for _, team in ipairs({ 2, 3 }) do
	local tag = team == 2 and " (radiant)" or " (dire)"
	local W = world({ team = team, burst = 1000 })
	score(W)
	check("a kill pass waits a reaction delay before committing" .. tag, W.age("commit") == nil)
	T = T + ROUND
	W.nextRound = T
	play(W, FRAME)
	check("a kill pass commits with the CommitFloor" .. tag, W.age("commit") ~= nil and near(W.last.roam, 0.82), W.last.roam)
	check("the commit is logged with its margin" .. tag, W.events("lanefight_start", "phase=commit target=6 margin=") == 1,
		table.concat(W.lines, "\n"))
	check("a commit is not also a trade" .. tag, W.age("trade") == nil and not hasStart(W, "trade"))

	W.enemy.hiddenFrom = { [W.bot] = true }
	LAST_SEEN[6] = { location = W.enemy.loc, time_since_seen = 0 }
	play(W, 0.6)
	check("a target in fog for under FogGrace keeps the commit" .. tag, W.age("commit") ~= nil and W.events("lanefight_end") == 0)
	play(W, 1.1)
	check("fogged target ends the commit after FogGrace" .. tag, W.age("commit") == nil
		and W.events("lanefight_end", "phase=commit reason=fog") == 1, table.concat(W.lines, "\n"))
end

do
	local W = world({ burst = 1000 })
	play(W, 0.7)
	play(W, 7)
	check("the commit holds up to CommitMax", W.events("lanefight_end") == 0 and W.age("commit") ~= nil)
	play(W, 1.0)
	check("CommitMax ends the commit", W.events("lanefight_end", "reason=commit-max") == 1, table.concat(W.lines, "\n"))
end

do
	local W = world({ burst = 1000 })
	W.at(-200)
	play(W, 0.7)
	check("setup: team_roam is committing", W.bot.mode == BotMode.TeamRoam and W.age("commit") ~= nil)
	W.H.Intent.Claim(W.bot, { source = "orders:BACK", tier = "HUMAN_ORDER", mode = BotMode.Retreat, floor = 0.85 })
	local d = score(W)
	check("a HUMAN_ORDER retreat floor beats the fight floor, even with team_roam's active-mode boost",
		d.retreat > d.roam * 1.1 and W.bot.mode == BotMode.Retreat, string.format("%.3f vs %.3f", d.retreat, d.roam))
	check("a live order ends the commit", W.events("lanefight_end", "reason=priority") == 1)
end

-- ------------------------------------------------------------------------------------- cadence and survival

do
	local W = world({ burst = 1000, laneFight = { StopHP = 0.1 } })
	W.at(-200)
	local ages = {}
	W.beforeRetreat = function()
		if W.bot.mode == BotMode.TeamRoam then table.insert(ages, W.age("commit") or 99) end
	end
	play(W, 3)
	local worst = 0
	for _, a in ipairs(ages) do worst = math.max(worst, a) end
	check("cadence: team_roam is active over several rounds", #ages >= 5, #ages)
	check("cadence: at retreat's read the FIGHT claim was posted by Think this round", worst < 0.1, worst)
	check("cadence: the claim stays live between rounds", W.events("lanefight_end") == 0 and W.bot.mode == BotMode.TeamRoam)

	W.bot.hp = 20
	W.retreat = 0.6
	play(W, ROUND)
	check("retreat at SURVIVAL still wins under 25% HP", W.bot.mode == BotMode.Retreat and W.last.retreat > W.last.roam * 1.1,
		string.format("%.3f vs %.3f", W.last.retreat, W.last.roam))
end

-- ---------------------------------------------------------------------------------------------- start gates

local function gateWorld(o, setup)
	local W = world(o)
	if setup then setup(W) end
	play(W, 2)
	return W
end

do
	local W = gateWorld({ botHP = 45 })
	check("below StartHP no trade starts", not hasStart(W, "trade") and W.age("trade") == nil)
	check("a blocked start logs gate=low-hp once per window instance", W.events("lanefight_gate", "gate=low-hp") == 1,
		table.concat(W.lines, "\n"))

	-- Laning stays the active mode, so the gate is retreat's desire, not the mode.
	W = gateWorld({}, function(W) W.retreat, W.laning = 0.72, 0.8 end)
	check("retreat at StartMaxRetreat blocks the start", not hasStart(W, "trade") and W.events("lanefight_gate", "gate=retreat") == 1,
		table.concat(W.lines, "\n"))

	W = gateWorld({}, function(W) W.H.Lane.CampJobs.Active = function() return true end end)
	check("no start during a camp job", not hasStart(W, "trade") and W.events("lanefight_gate", "gate=camp") == 1)

	W = gateWorld({}, function(W) W.H.Lane.CampJobs.Covering = function() return true end end)
	check("no start while covering a support's camp job", not hasStart(W, "trade") and W.events("lanefight_gate", "gate=cover") == 1)

	W = gateWorld({}, function(W)
		W.onFrame = function()
			W.H.Intent.Claim(W.bot, { source = "orders:GATHER", tier = "HUMAN_ORDER", mode = BotMode.Assemble, floor = 0.85 })
		end
	end)
	check("no start with a live HUMAN_ORDER claim", not hasStart(W, "trade") and W.events("lanefight_gate", "gate=priority") == 1)

	W = gateWorld({ botLevel = 1, enemyLevel = 2, burst = 1000 })
	check("respect blocks trades and commits and logs once", not hasStart(W, "trade") and not hasStart(W, "commit")
		and W.events("lanefight_gate", "gate=respect:their_spike") == 1, table.concat(W.lines, "\n"))
end

-- ---------------------------------------------------------------------------------------------- kill switches

local function offCase(name, o, setup)
	local W = world(o)
	if setup then setup(W) end
	GETUNITLIST_CALLS = {}
	local same, acted = true, false
	for _ = 1, 8 do
		T = T + ROUND
		if W.LF.RoamDesire(W.bot, 0.3) ~= 0.3 then same = false end
		W.bot.mode = BotMode.TeamRoam
		if W.LF.Think(W.bot) then acted = true end
	end
	local scans = 0
	for _, n in pairs(GETUNITLIST_CALLS) do scans = scans + n end
	check("with " .. name .. " RoamDesire returns raw and posts no claim", same and W.age("trade") == nil and W.age("commit") == nil
		and not acted and #W.lines == 0)
	check("with " .. name .. " nothing scans units", scans == 0, scans)
end
offCase("LaneFight off", { burst = 1000, laneFight = { Enable = false } })
offCase("Trade and Kill off", { burst = 1000, laneFight = { Trade = false, Kill = false } })
offCase("the laning phase over", { burst = 1000 }, function() LANING = false end)
offCase("Teams = allies and no human ally", { burst = 1000, laneFight = { Teams = "allies" } })
offCase("Humaniser off", { burst = 1000, enable = false })

do
	local W = world({ laneFight = { Trade = false } })
	play(W, 2)
	check("Trade off: a window alone starts nothing", W.events("lanefight_start") == 0)
	W = world({ burst = 1000, laneFight = { Trade = false } })
	play(W, 1)
	check("Trade off: a kill pass still commits", hasStart(W, "commit"))
end

do
	local W = world({ intent = { Enable = false } })
	play(W, 0.7)
	check("without intent RoamDesire returns max(raw, floor)", near(W.LF.RoamDesire(W.bot, 0.2), 0.75) and near(W.LF.RoamDesire(W.bot, 0.9), 0.9))
end

do
	local W = world()
	W.LF.FightRead.ReadFor = function() error("boom") end
	local ok, res = pcall(W.LF.RoamDesire, W.bot, 0.3)
	check("an error inside RoamDesire falls back to the raw desire", ok and res == 0.3, tostring(res))
end

-- ------------------------------------------------------------------------------------------ every start ends

do
	local W = hitWorld(false)
	play(W, 6)
	local W2 = world({ burst = 1000 })
	play(W2, 10)
	check("every lanefight_start has a lanefight_end", W.events("lanefight_start") == W.events("lanefight_end")
		and W2.events("lanefight_start") == W2.events("lanefight_end") and W2.events("lanefight_start") >= 1, table.concat(W2.lines, "\n"))
end

-- ------------------------------------------------------------------------------------------- commit focus

local function focusAge(mode, W) return W.H.Intent.ClaimAge(W.bot, "lanefight:commit_focus", mode) end

do
	local W = world({ burst = 1000 })
	W.laning = 0.9
	W.bot.mode = BotMode.Laning
	play(W, 1.5)
	check("a commit takes over from laning at 0.9 as the active mode", W.bot.mode == BotMode.TeamRoam and W.events("lanefight_end") == 0
		and W.age("commit") ~= nil, string.format("laning %.3f roam %.3f", W.last.laning, W.last.roam))
	check("the commit caps laning below its floor even with the x1.1", W.last.laning * 1.1 < W.last.roam, W.last.laning)

	W.at(-200)
	W.laning = 0.45
	W.bot.hp = 70
	W.retreat = 0.85
	play(W, 1.5)
	check("retreat's creep branch at 0.85 and 70% HP does not end the commit", W.bot.mode == BotMode.TeamRoam and W.events("lanefight_end") == 0
		and W.last.retreat < W.last.roam, string.format("retreat %.3f roam %.3f", W.last.retreat, W.last.roam))

	W.bot.hp = 45
	play(W, 1.5)
	check("below CommitHoldHP retreat wins", W.bot.mode == BotMode.Retreat and W.events("lanefight_end", "phase=commit reason=retreat") == 1,
		table.concat(W.lines, "\n"))
	check("the focus caps go with the commit", focusAge(BotMode.Laning, W) == nil and focusAge(BotMode.Retreat, W) == nil
		and focusAge(BotMode.Ward, W) == nil)
end

do
	local W = world()
	W.at(-200)
	play(W, 0.7)
	check("a trade posts no focus caps", W.age("trade") ~= nil and focusAge(BotMode.Laning, W) == nil and focusAge(BotMode.Retreat, W) == nil)
end

-- ------------------------------------------------------------------------------- avoid, mode gate, switches

do
	local W = world()
	play(W, 0.7)
	T = T + FRAME
	local r = W.LF.RoamDesire(W.bot, 0.3, true)
	check("team_roam's ability-zone escape ends the phase", r == 0.3 and W.age("trade") == nil
		and W.events("lanefight_end", "reason=avoid") == 1, table.concat(W.lines, "\n"))
end

do
	local W = world()
	W.bot.mode = BotMode.Farm
	for _ = 1, 6 do
		T = T + ROUND
		W.H.Intent.Resolve(W.bot, BotMode.Retreat, 0.2)
		W.LF.RoamDesire(W.bot, 0.2)
	end
	check("no start from another active mode, logged once", not hasStart(W, "trade") and W.events("lanefight_gate", "gate=mode:farm") == 1,
		table.concat(W.lines, "\n"))
end

do
	local W = world({ burst = 1000 })
	play(W, 0.7)
	W.H.Config.Get().LaneFight.Enable = false
	play(W, ROUND)
	check("turning LaneFight off mid-commit ends it and releases the claims", W.age("commit") == nil and focusAge(BotMode.Laning, W) == nil
		and W.events("lanefight_end", "reason=off") == 1, table.concat(W.lines, "\n"))
	local W2 = world()
	play(W2, 0.7)
	W2.LF.Config.Settings().Trade = false
	play(W2, ROUND)
	check("turning Trade off mid-trade ends it and releases the claim", W2.age("trade") == nil
		and W2.events("lanefight_end", "reason=flag-off") == 1, table.concat(W2.lines, "\n"))
end

-- Five switches in five seconds turn on Intent's thrash limiter; the phase starts right after and must still win.
for _, case in ipairs({ { phase = "trade", laning = 0.45 }, { phase = "commit", laning = 0.7 } }) do
	local W = world({ botLevel = 1 })
	W.bot.action = BOT_ACTION_TYPE_MOVE_TO
	W.laning = case.laning
	local switches, i = 0, 0
	local prev = W.bot.mode
	W.onFrame = function()
		W.H.Intent.Tick(W.bot)
		if W.bot.mode ~= prev then switches, prev = switches + 1, W.bot.mode end
	end
	-- team_roam's raw desire alternates above and below laning's every round.
	W.beforeRetreat = function()
		i = i + 1
		W.roam = (i % 2 == 1 and i <= 7) and 0.9 or 0.2
	end
	play(W, 7 * ROUND)
	local before = switches
	if case.phase == "trade" then W.bot.level = 2 else W.bot.estDamage = 1000 end
	play(W, 1.2)
	check("setup: five or more mode switches before the " .. case.phase .. " turned the thrash limiter on", before >= 5
		and W.events("thrash", "mode=laning") >= 1, before)
	check("a " .. case.phase .. " survives the thrash limiter", hasStart(W, case.phase) and W.bot.mode == BotMode.TeamRoam
		and W.events("lanefight_end") == 0, table.concat(W.lines, "\n"))
end

-- ------------------------------------------------------------------------------------------------ hook pins

-- team_roam's mode file cannot be loaded offline, so pin the two call sites and their order.
do
	local f = io.open(HARNESS_DIR .. "/../../bots/mode_team_roam_generic.lua", "r")
	local src = f:read("*a")
	f:close()
	check("team_roam GetDesire hook: RoamDesire after CapForLanePush, before Intent.Resolve", src:find(
		"    res = CapForLanePush(res)\n    res = J.Humaniser.LaneFight.RoamDesire(bot, res, IsAvoidingAbilityZone)\n", 1, true) ~= nil
		and src:find("    res = J.Humaniser.LaneFight.RoamDesire(bot, res, IsAvoidingAbilityZone)\n\n    -- J.Utils.SetCachedVars(cacheKey, res)\n    return J.Humaniser.Intent.Resolve(bot, BOT_MODE_TEAM_ROAM, res)", 1, true) ~= nil)
	check("team_roam Think hook: after ItemOpsThink, before the last-hit creep branch", src:find(
		"    ItemOpsThink()\n    if not IsAvoidingAbilityZone and J.Humaniser.LaneFight.Think(bot) then return end\n\n\tif J.IsValid(hTargetCreep) then", 1, true) ~= nil)
end

finish()
