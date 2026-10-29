dofile(HARNESS_DIR .. "/lane_fight_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local BOT_Y = LANE_Y[Lane.Bot]
local FRAME = 1 / 30
local ROUND = 0.31
local ability, world, score, play = LaneFightAbility, LaneFightWorld, LaneFightScore, LaneFightPlay

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

do
	-- Hits on an illusion of the target (same player ID) are not hits on the target.
	local W = hitWorld(false)
	local illusion = setmetatable({ IsIllusion = function() return true end }, { __index = W.enemy })
	W.bot.target = illusion
	play(W, 1.7)
	check("attacks on an illusion of the target are not landed hits", W.events("lanefight_end", "reason=hits") == 0, table.concat(W.lines, "\n"))
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
	-- Laning at 0.9 as the active mode (0.99 with the engine's x1.1) would out-bid the trade floor and abort the trade a
	-- second later, so the trade does not start; the window instance stays unused.
	local W = world()
	W.laning = 0.9
	play(W, 2)
	check("laning bidding at the trade floor gates the trade start, logged once", not hasStart(W, "trade")
		and W.events("lanefight_gate", "gate=laning") == 1 and W.bot.mode == BotMode.Laning, table.concat(W.lines, "\n"))
	W.laning = 0.45
	play(W, 0.7)
	check("the same window starts the trade once laning drops", W.events("lanefight_start", "phase=trade") == 1, table.concat(W.lines, "\n"))

	-- Laning rising after team_roam took over: trades are not protected, and the taken-over trade spends its window.
	W.laning = 0.9
	play(W, 0.6)
	check("a mode other than team_roam or attack does not end it within 1 s", W.events("lanefight_end") == 0)
	local guard = 0
	while W.events("lanefight_end") == 0 and guard < 60 do play(W, FRAME) guard = guard + 1 end
	check("trades are not protected: laning at 0.9 ends a trade after 1 s", W.events("lanefight_abort", "reason=mode:laning") == 1
		and W.events("lanefight_end", "reason=mode:laning hits=0 took=1") == 1 and W.age("trade") == nil, table.concat(W.lines, "\n"))
	W.laning = 0.45
	play(W, 1.5)
	check("a trade that took over uses up its window instance", W.events("lanefight_start", "phase=trade") == 1,
		W.events("lanefight_start", "phase=trade"))

	-- 0.7 is under the 0.75 floor, but as the active mode it bids 0.77.
	W = world()
	W.laning = 0.7
	play(W, 2)
	check("laning at 0.7 as the active mode gates the trade", not hasStart(W, "trade") and W.events("lanefight_gate", "gate=laning") == 1,
		table.concat(W.lines, "\n"))
	W = world()
	W.laning, W.attack = 0.7, 0.95
	W.bot.target = W.enemy
	play(W, 2)
	check("laning at 0.7 while Valve's attack mode is active does not", hasStart(W, "trade") and W.events("lanefight_gate", "gate=laning") == 0,
		table.concat(W.lines, "\n"))
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
	check("a kill pass commits with the CommitFloor" .. tag, W.age("commit") ~= nil and near(W.last.roam, 1.06), W.last.roam)
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
	local W = world({ burst = 1000, botX = 0 })
	play(W, 0.7)
	play(W, 4)
	check("the commit holds up to CommitMax (5 s)", W.events("lanefight_end") == 0 and W.age("commit") ~= nil)
	play(W, 1.0)
	check("CommitMax ends the commit at 5 s", W.events("lanefight_end", "reason=commit-max") == 1, table.concat(W.lines, "\n"))
end

do
	-- The kill stops working (the stun missed, the target regenerated): margin under AbandonMargin for over AbandonAfter.
	local W = world({ burst = 1000, botX = 0 })
	play(W, 0.7)
	check("setup: committing", W.age("commit") ~= nil)
	W.bot.estDamage = 50
	play(W, 0.6)
	check("a dip under AbandonMargin shorter than AbandonAfter keeps the commit", W.events("lanefight_end") == 0 and W.age("commit") ~= nil,
		table.concat(W.lines, "\n"))
	W.bot.estDamage = 1000
	play(W, 0.6)
	W.bot.estDamage = 50
	play(W, 1.6)
	check("a margin under AbandonMargin for over AbandonAfter ends the commit as margin", W.events("lanefight_end", "phase=commit reason=margin") == 1,
		table.concat(W.lines, "\n"))
end

do
	-- An enemy tower takes aggro on the bot mid-commit: retreat is no longer held, and the commit ends as tower-aggro.
	local W = world({ burst = 1000, botX = 0 })
	play(W, 0.7)
	check("setup: committing", W.age("commit") ~= nil)
	local tower
	for _, t in pairs(TOWERS_W[W.bot.team == 2 and 3 or 2]) do if math.abs(t.loc.y - BOT_Y) < 1000 then tower = t end end
	W.bot.loc = Vector(tower.loc.x - W.sign * 600, BOT_Y)
	W.enemy.loc = Vector(tower.loc.x - W.sign * 400, BOT_Y)
	tower.target = W.bot
	W.retreat = 0.85
	score(W)
	check("under tower fire the commit does not cap retreat", near(W.last.retreat, 0.85), W.last.retreat)
	play(W, 1)
	check("tower aggro ends the commit", W.events("lanefight_end", "phase=commit reason=tower-aggro") == 1, table.concat(W.lines, "\n"))
	tower.target = nil
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

	-- Task 12's caution (a lone core, a missing enemy, not stronger) suppresses lane trades, ours included.
	W = gateWorld({}, function(W) W.H.Lane.Hooks.SetTradeProbe(function() return true end) end)
	check("no trade while caution suppresses trades, logged once", not hasStart(W, "trade")
		and W.events("lanefight_gate", "gate=caution") == 1, table.concat(W.lines, "\n"))

	W = gateWorld({}, function(W)
		W.onFrame = function()
			W.H.Intent.Claim(W.bot, { source = "orders:GATHER", tier = "HUMAN_ORDER", mode = BotMode.Assemble, floor = 0.85 })
		end
	end)
	check("no start with a live HUMAN_ORDER claim", not hasStart(W, "trade") and W.events("lanefight_gate", "gate=priority") == 1)

	-- Their level spike on our level-2 bot: a "level" window of ours is gone, but lasthit/position would still read.
	W = gateWorld({ botLevel = 1, enemyLevel = 2 })
	check("respect blocks a trade and logs once", not hasStart(W, "trade") and W.events("lanefight_gate", "gate=respect:their_spike") == 1,
		table.concat(W.lines, "\n"))
	W = gateWorld({ botLevel = 1, enemyLevel = 2, burst = 1000 })
	check("respect does not block a kill that passes the kill check", hasStart(W, "commit"), table.concat(W.lines, "\n"))
end

do
	-- From level 6 an ult never seen cast is assumed ready (their_ult respect on every read); the kill check decides kills.
	local W = world({ botLevel = 6, enemyLevel = 6, burst = 1000 })
	W.enemy.bot = false
	play(W, 1)
	check("setup: the unseen ult of a level-6 human reads as their_ult", W.LF.ReadFor(W.bot, T).respect == "their_ult")
	check("a level-6 human with an unseen ult and a passing kill check is committed on", hasStart(W, "commit"), table.concat(W.lines, "\n"))
end

do
	-- Their level-6 spike (and unseen ult) for 2 s during a commit, then gone: the kill pass stayed one instance, so
	-- CommitMax ends the commit for good rather than a lapsed instance restarting it.
	local W = world({ burst = 1000, botX = 0 })
	play(W, 1)
	check("setup: committing", W.LF.CurrentPhase(W.bot) == "commit")
	W.enemy.level = 6
	play(W, 2)
	check("setup: respect read during the commit", W.LF.ReadFor(W.bot, T).respect ~= nil and W.LF.CurrentPhase(W.bot) == "commit")
	W.bot.level = 6
	W.LF.CooldownMemory.Record(1, 6, "lion_finger_of_death", "ult", 100, 1, T)
	play(W, 7)
	check("a respect during a commit does not lapse its kill instance", W.events("lanefight_end", "reason=commit-max") == 1
		and W.events("lanefight_start", "phase=commit") == 1, table.concat(W.lines, "\n"))
end

do
	-- CommitStartHP (0.65) gates commits; trades keep StartHP (0.5).
	local W = world({ burst = 1000, botHP = 60 })
	play(W, 2)
	check("at 0.6 HP a kill pass does not commit (gate=low-hp once) and a trade still starts", not hasStart(W, "commit")
		and hasStart(W, "trade") and W.events("lanefight_gate", "gate=low-hp") == 1, table.concat(W.lines, "\n"))
	W = world({ burst = 1000, botHP = 70 })
	play(W, 1)
	check("at 0.7 HP the same kill pass commits", hasStart(W, "commit"), table.concat(W.lines, "\n"))
end

do
	-- A near miss (margin 0.9) logs why it failed, once per target instance; a margin under 0.8 logs nothing. The bot
	-- stands 250 outside its range, so 108 burst is credited at 5/6: 0.9.
	local W = world({ botLevel = 1, burst = 108 })
	play(W, 3)
	check("a kill check failing with margin >= 0.8 logs gate=kill:<reason> once", W.events("lanefight_gate", "gate=kill:burst target=6") == 1
		and W.events("lanefight_gate", "gate=kill:") == 1, table.concat(W.lines, "\n"))
	W = world({ botLevel = 1, burst = 1000 })
	W.enemy.abilities[1] = ability("antimage_blink", { cd = 15 })
	play(W, 3)
	check("an unseen escape on a killable target logs gate=kill:escape", W.events("lanefight_gate", "gate=kill:escape target=6") == 1
		and not hasStart(W, "commit"), table.concat(W.lines, "\n"))
	W = world({ botLevel = 1, burst = 70 })
	play(W, 3)
	check("a kill check under margin 0.8 logs no kill gate", W.events("lanefight_gate", "gate=kill:") == 0, table.concat(W.lines, "\n"))
end

do
	-- Out of range and in another mode: the mode gate is reported, not the range.
	local W = world({ botX = -800 })
	W.bot.mode = BotMode.Farm
	for _ = 1, 6 do
		T = T + ROUND
		W.H.Intent.Resolve(W.bot, BotMode.Retreat, 0.2)
		W.LF.RoamDesire(W.bot, 0.2)
	end
	check("the mode gate is checked before the range gate", W.events("lanefight_gate", "gate=mode:farm") == 1
		and W.events("lanefight_gate", "gate=range") == 0, table.concat(W.lines, "\n"))

	-- A cached read (WindowReadEvery 0.6) still names a target that has since gone into fog: no trade on it.
	W = world({ laneFight = { WindowReadEvery = 0.6 } })
	W.laning = 0.9
	play(W, 0.7)
	check("setup: the window was read twice and laning gated it", W.events("lanefight_gate", "gate=laning") == 1 and not hasStart(W, "trade"),
		table.concat(W.lines, "\n"))
	-- As in the engine: the handle answers CanBeSeen false at once; lane_state's snapshot catches up on its refresh.
	W.enemy.hiddenFrom = { [W.bot] = true }
	W.enemy.CanBeSeen = function() return false end
	LAST_SEEN[6] = { location = W.enemy.loc, time_since_seen = 0 }
	W.laning = 0.45
	play(W, 0.3)
	check("a trade does not start on a target the cached read saw but the bot no longer does", not hasStart(W, "trade")
		and W.events("lanefight_gate", "gate=unseen") == 1,
		table.concat(W.lines, "\n"))
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

do
	-- Caution holds trades only: a kill pass still commits (the kill check's tower, outnumbered and counter rules decide).
	local W = world({ burst = 1000, botX = 0 })
	W.H.Lane.Hooks.SetTradeProbe(function() return true end)
	play(W, 1)
	check("caution does not stop a kill commit", W.age("commit") ~= nil and W.events("lanefight_gate", "gate=caution") == 0,
		table.concat(W.lines, "\n"))
end

-- ------------------------------------------------------------------------------------- chase and dive limits

local function enemyT1(team)
	for _, t in pairs(TOWERS_W[team]) do if math.abs(t.loc.y - BOT_Y) < 1000 then return t end end
end

do
	-- The bot reaches the target, then the target pulls out of range and stays out: the chase ends after ChaseMax (3 s)
	-- out of reach, well before CommitMax (8 s).
	local W = world({ burst = 1000, botX = 0 })
	play(W, 0.7)
	check("setup: an in-range commit", W.age("commit") ~= nil, table.concat(W.lines, "\n"))
	play(W, 1)
	local lost = T
	W.at(-700)
	local endAt
	for _ = 1, 200 do
		play(W, 1 / 30)
		for i, l in ipairs(W.lines) do if endAt == nil and l:find("ev=lanefight_end", 1, true) then endAt = T end end
		if endAt then break end
	end
	check("a chase out of reach for ChaseMax ends the commit as chase", endAt ~= nil and endAt >= lost + 3 - 1e-6 and endAt <= lost + 3.4
		and W.events("lanefight_end", "phase=commit reason=chase") == 1, string.format("lost %.2f end %s", lost, tostring(endAt)))

	W = world({ burst = 1000, botX = 0, laneFight = { ChaseMax = 1.5 } })
	play(W, 1.7)
	W.at(-700)
	play(W, 1.7)
	check("ChaseMax is read from config", W.events("lanefight_end", "phase=commit reason=chase") == 1, table.concat(W.lines, "\n"))
end

do
	-- The target runs under its tower. Margin 1.2: enough to commit, short of TowerOverride (1.3), so the dive ends.
	local W = world({ burst = 120, botX = 0 })
	play(W, 0.7)
	check("setup: a commit at margin 1.2 outside tower range", W.age("commit") ~= nil, table.concat(W.lines, "\n"))
	local tower = enemyT1(W.other or (W.bot.team == 2 and 3 or 2))
	W.enemy.loc = Vector(tower.loc.x - W.sign * 600, BOT_Y)
	W.bot.loc = Vector(W.enemy.loc.x - W.sign * 300, BOT_Y)
	play(W, 1)
	check("a target fleeing under its tower ends a commit short of TowerOverride", W.events("lanefight_end", "phase=commit reason=tower") == 1
		and W.events("lanefight_recheck", "reason=tower pass=0") == 1, table.concat(W.lines, "\n"))

	W = world({ burst = 1000, botX = 0 })
	play(W, 0.7)
	W.enemy.loc = Vector(tower.loc.x - W.sign * 600, BOT_Y)
	W.bot.loc = Vector(W.enemy.loc.x - W.sign * 300, BOT_Y)
	play(W, 1)
	check("a commit that clears TowerOverride follows the target under its tower", W.age("commit") ~= nil
		and W.events("lanefight_recheck", "reason=tower pass=1") == 1 and W.events("lanefight_end") == 0, table.concat(W.lines, "\n"))
end

-- ------------------------------------------------------------------------------------------- commit focus

local function focusAge(mode, W) return W.H.Intent.ClaimAge(W.bot, "lanefight:commit_focus", mode) end

do
	-- In game every commit stayed in Valve's attack mode (0.92-1.0, active so x1.1) and lane fight's Think never ran.
	local W = world({ burst = 1000 })
	W.attack = 0.95
	W.bot.mode = BotMode.Attack
	play(W, 1.5)
	check("a commit takes over from Valve's attack mode at 0.95 as the active mode", W.age("commit") ~= nil
		and W.bot.mode == BotMode.TeamRoam and W.events("lanefight_end") == 0, string.format("mode %s roam %.3f", tostring(W.bot.mode), W.last.roam))

	-- OHA's farm bids 1.10 in lane and ended a commit as mode:farm; its Lua attack mode bids 1.0 for some heroes.
	W = world({ burst = 1000 })
	play(W, 1.0)
	check("setup: a commit from laning", W.age("commit") ~= nil and W.bot.mode == BotMode.TeamRoam, tostring(W.bot.mode))
	W.farm, W.luaAttack = 1.1, 1.0
	play(W, 1.5)
	check("a commit takes over from farm at 1.10 and a Lua attack mode at 1.0", W.age("commit") ~= nil and W.bot.mode == BotMode.TeamRoam
		and W.events("lanefight_end") == 0, string.format("mode %s farm %.3f attack %.3f roam %.3f", tostring(W.bot.mode), W.last.farm,
		W.last.attack, W.last.roam))
	check("the commit caps farm and the Lua attack mode below its floor even with the x1.1", W.last.farm * 1.1 < W.last.roam
		and W.last.attack * 1.1 < W.last.roam, string.format("farm %.3f attack %.3f", W.last.farm, W.last.attack))
end

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

-- ------------------------------------------------------------------------------ overlay, telemetry and regression

do
	-- Spell window: the stun is remembered as down. Kill margin 112 / 100 = 1.12 fails under their tower (TowerOverride
	-- 1.3), so the bot keeps trading. Two remembered cooldowns.
	local W = world({ burst = 112, debug = true })
	TOWERS_W[3][dota.Tower.Bot1].loc = Vector(1150, BOT_Y)
	SetRandomSequence({ 0.1, 0.5, 0.1, 0.5 })
	W.LF.CooldownMemory.Record(1, 6, "lion_impale", "key", 12, 1, T)
	W.LF.CooldownMemory.Record(1, 6, "lion_finger_of_death", "ult", 100, 1, T)
	SetRandomSequence({})
	play(W, 0.7)
	-- The humaniser tick also takes a telemetry snapshot.
	function W.bot:GetLastHits() return 0 end
	function W.bot:GetDenies() return 0 end
	function W.bot:GetGold() return 600 end
	check("setup: the overlay world trades", W.LF.CurrentPhase(W.bot) == "trade", W.LF.CurrentPhase(W.bot))
	local drawn = {}
	local realDraw = DebugDrawText
	DebugDrawText = function(_, _, text) table.insert(drawn, text) end
	W.H.Tick(W.bot)
	DebugDrawText = realDraw
	local line
	for _, t in ipairs(drawn) do if t:sub(1, 6) == "fight:" then line = t end end
	check("overlay shows window, kill margin and remembered count", line == "fight: window=spell kill=0.93 mem=2 phase=trade",
		tostring(line) .. " | " .. table.concat(drawn, " | ") .. table.concat(W.lines, "\n"))

	local W2 = world({ burst = 112 })
	local drawn2 = {}
	DebugDrawText = function(_, _, text) table.insert(drawn2, text) end
	play(W2, 0.7)
	W2.H.Tick(W2.bot)
	DebugDrawText = realDraw
	local any = false
	for _, t in ipairs(drawn2) do if t:find("fight:", 1, true) then any = true end end
	check("no fight overlay line with Debug off", not any)
end

-- [HEV] fields as hlog's parser reads them: k=v, v quoted when it holds spaces.
local function hevFields(line)
	local ev = line:match(" ev=(%S+)")
	local fields, pos = {}, (line:find(" ev=", 1, true) or 1) + 4 + #ev
	while true do
		local s, e, k = line:find("^%s+(%w+)=", pos)
		if s == nil then break end
		local v
		if line:sub(e + 1, e + 1) == '"' then
			local close = line:find('"', e + 2, true)
			v, pos = line:sub(e + 2, close - 1), close + 1
		else
			local _, ve, raw = line:find("^(%S+)", e + 1)
			v, pos = tonumber(raw) or raw, ve + 1
		end
		table.insert(fields, { k, v })
	end
	return ev, fields
end

local function fieldSet(fields)
	local set = {}
	for _, f in ipairs(fields) do set[f[1]] = f[2] end
	return set
end

do
	-- 1,200 burst credited at 5/6 (the bot starts 250 outside its range): margin 10.
	local W = world({ burst = 1200 })
	play(W, 1.5)
	local stripT = function(l) return (l:gsub(" t=%S+", "", 1)) end
	local seen, roundTrip = {}, true
	for _, l in ipairs(W.lines) do
		local ev, fields = hevFields(l)
		if ev:sub(1, 10) == "lanefight_" then
			seen[ev] = fieldSet(fields)
			if stripT(W.H.Telemetry.FormatLine(ev, fields)) ~= stripT(l) then roundTrip = false end
		end
	end
	check("telemetry lines parse through hlog: every lanefight line round-trips through FormatLine", roundTrip and seen.lanefight_start ~= nil,
		table.concat(W.lines, "\n"))
	local w = seen.lanefight_window
	check("lanefight_window carries pid, window, target and noticed", w ~= nil and w.pid == 1 and w.window == "level" and w.target == 6
		and w.noticed ~= nil, table.concat(W.lines, "\n"))
	local c = seen.lanefight_commit
	check("lanefight_commit carries pid, target, margin and role", c ~= nil and c.pid == 1 and c.target == 6 and c.margin == 10
		and c.role == "solo", table.concat(W.lines, "\n"))
end

-- With LaneFight.Enable = false, everything the lane-fight hooks return, order and draw matches the humaniser being off.
-- The defaults run through the same world as a positive control.
do
	local function run(o)
		local W = world(o)
		local R = { desires = {}, thinks = {}, actions = {}, draws = 0 }
		local function hook(fn)
			local real = RandomFloat
			RandomFloat = function(a, b) R.draws = R.draws + 1 return real(a, b) end
			ACTIONS = {}
			local r = fn()
			RandomFloat = real
			for _, a in ipairs(ACTIONS) do table.insert(R.actions, a.kind .. ":" .. tostring(a.args[1] and a.args[1].pid)) end
			return r
		end
		local stop, nextRound, i = T + 3, T, 0
		while T < stop do
			hook(function() W.LF.Tick(W.bot) end)
			if T >= nextRound - 1e-9 then
				i = i + 1
				local raw = i % 2 == 0 and 0.5 or 0.2
				-- As mode_team_roam_generic's GetDesire: the lane-fight hook, then Intent.Resolve (where its FIGHT floor lands).
				table.insert(R.desires, string.format("%.4f", hook(function()
					return W.H.Intent.Resolve(W.bot, BotMode.TeamRoam, W.LF.RoamDesire(W.bot, raw, false))
				end)))
				nextRound = nextRound + ROUND
			end
			W.bot.mode = BotMode.TeamRoam
			table.insert(R.thinks, tostring(hook(function() return W.LF.Think(W.bot) end)))
			T = T + FRAME
		end
		R.lines = 0
		for _, l in ipairs(W.lines) do if l:find("ev=lanefight_", 1, true) then R.lines = R.lines + 1 end end
		return R
	end
	local same = function(a, b) return table.concat(a, ",") == table.concat(b, ",") end
	for _, team in ipairs({ 2, 3 }) do
		local tag = team == 2 and " (radiant)" or " (dire)"
		local base = run({ team = team, burst = 1000, enable = false })
		local off = run({ team = team, burst = 1000, laneFight = { Enable = false } })
		local on = run({ team = team, burst = 1000 })
		check("control: with defaults the lane-fight hooks change desire, actions and draws" .. tag, not same(on.desires, base.desires)
			and #on.actions > 0 and on.draws > 0, on.draws)
		check("regression: LaneFight.Enable=false leaves team_roam desire, actions and RandomFloat draws unchanged" .. tag,
			same(off.desires, base.desires) and same(off.thinks, base.thinks) and same(off.actions, base.actions)
			and off.draws == base.draws and off.draws == 0 and #off.actions == 0 and off.lines == 0, string.format("draws %d/%d actions %d/%d", off.draws, base.draws, #off.actions, #base.actions))
	end
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
		"    ItemOpsThink()\n    if not IsAvoidingAbilityZone and J.Humaniser.LaneFight.Think(bot) then return end\n\n"
		.. "\t-- Ours.LeaveCoreCreep: a swing or auto-attack on a creep a core can take is cancelled.\n"
		.. "\tif J.Humaniser.Etiquette.LeavesTarget(bot) then\n\t\tbot:Action_MoveToLocation(bot:GetLocation())\n\t\treturn\n\tend\n\n"
		.. "\tif J.IsValid(hTargetCreep) then", 1, true) ~= nil)
end

finish()
