dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local BOT_Y = LANE_Y[Lane.Bot]
local FRAME = 1 / 30
-- Dota scores all of a bot's modes in one round every ~0.31 s, in a fixed order (retreat before team_roam).
local ROUND = 0.31
local SPEED = 300

local function ability(name, o)
	o = o or {}
	return {
		GetName = function() return name end,
		GetLevel = function() return o.level or 1 end,
		IsUltimate = function() return o.ult == true end,
		IsHidden = function() return false end,
		IsNull = function() return false end,
		IsTrained = function() return (o.level or 1) > 0 end,
		GetCooldown = function() return o.cd or 12 end,
		IsFullyCastable = function() return o.ready ~= false end,
		GetCastRange = function() return o.range or 500 end,
	}
end

local PINGS = {}

-- Bottom lane. Our bot (pid 1) stands at x = -500, the enemy laner (pid 6) at x = 300, 800 away. A partner (pid 2)
-- stands next to the bot. `driven` partners run through the lane-fight module like the bot (both are scored and
-- ticked); other partners are moved by the test. `sign` mirrors x for Dire.
local function world(o)
	o = o or {}
	local team = o.team or 2
	local other = team == 2 and 3 or 2
	local sign = team == 2 and 1 or -1
	local laneFight = o.laneFight or {}
	if laneFight.Enable == nil then laneFight.Enable = true end
	-- The follow mechanics below are pinned at the old FollowMargin (0.8); the default (1.0) has its own test.
	if laneFight.FollowMargin == nil and not o.defaultFollow then laneFight.FollowMargin = 0.8 end
	local H = LaneFresh({ Enable = true }, { skill = o.skill or 1, laneFight = laneFight, telemetry = { Enable = true } })
	T = 100
	CURRENT_TEAM = team
	PINGS = {}
	LANE_FRONT[2][Lane.Bot], LANE_FRONT[3][Lane.Bot] = 0.5, 0.5
	local bot = MakeUnit({ pid = 1, team = team, loc = Vector(sign * (o.botX or -500), BOT_Y), level = o.botLevel or 1, hp = 100,
		mode = BotMode.Laning })
	bot.pos, bot.lane, bot.estDamage, bot.facing = o.botPos or 1, Lane.Bot, o.burst or 0, team == 2 and 0 or 180
	bot.abilities = o.botAbilities
	OBSERVER = bot
	getmetatable(bot).__index.ActionImmediate_Ping = function(self, x, y) table.insert(PINGS, { pid = self.pid, x = x, y = y, t = T }) end
	local W = { H = H, LF = H.LaneFight, bot = bot, sign = sign, lines = {}, times = {}, said = {}, bots = { bot }, d = {},
		nextRound = T }
	local p = o.partner
	if p then
		local partner = MakeUnit({ pid = 2, team = team, bot = p.human ~= true, loc = Vector(sign * (p.x or -450), BOT_Y), level = 1,
			hp = 100, mode = BotMode.Laning })
		partner.pos, partner.lane, partner.estDamage, partner.facing = p.pos or 5, Lane.Bot, p.burst or 0, team == 2 and 0 or 180
		partner.abilities = p.abilities
		W.partner = partner
		if p.driven then table.insert(W.bots, partner) end
	end
	local enemy = MakeUnit({ pid = 6, team = other, loc = Vector(sign * (o.enemyX or 300), BOT_Y), level = o.enemyLevel or 1,
		hp = o.enemyHP or 100 })
	enemy.lane = Lane.Bot
	enemy.abilities = o.enemyAbilities or { [0] = ability("lion_impale", { cd = 12 }), [5] = ability("lion_finger_of_death", { ult = true, cd = 100 }) }
	W.enemy = enemy
	MakeCreep({ team = other, x = sign * 100, y = BOT_Y })
	for _, b in ipairs(W.bots) do W.d[b] = { retreat = 0.2, laning = 0.45, roam = 0.2, attack = 0 } end
	H.Telemetry.SetSink(function(l) table.insert(W.lines, l) table.insert(W.times, T) end)
	H.Orders.SetAnnouncer(function(b, key, cooldown, args) table.insert(W.said, { pid = b:GetPlayerID(), key = key, cooldown = cooldown, args = args }) end)
	function W.events(ev, pattern)
		local n = 0
		for _, l in ipairs(W.lines) do
			if l:find("ev=" .. ev .. " ", 1, true) and (pattern == nil or l:find(pattern, 1, true)) then n = n + 1 end
		end
		return n
	end
	-- Game time of the first matching event.
	function W.firstAt(ev, pattern)
		for i, l in ipairs(W.lines) do
			if l:find("ev=" .. ev .. " ", 1, true) and (pattern == nil or l:find(pattern, 1, true)) then return W.times[i] end
		end
		return nil
	end
	function W.age(b, phase) return H.Intent.ClaimAge(b, "lanefight:" .. phase, BotMode.TeamRoam) end
	function W.loc(x) return Vector(sign * x, BOT_Y) end
	return W
end

local function dist(a, b) return math.sqrt((a.loc.x - b.loc.x) ^ 2 + (a.loc.y - b.loc.y) ^ 2) end

local function step(u, to)
	local dx, dy = to.x - u.loc.x, to.y - u.loc.y
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 1 then return end
	local s = math.min(len, SPEED * FRAME)
	u.loc = Vector(u.loc.x + dx / len * s, u.loc.y + dy / len * s)
	u.facing = math.deg(math.atan(dy, dx)) % 360
end

-- One scoring round in engine order for one bot; the engine then picks the highest desire, the active mode's x1.1.
local function score(W, b)
	local H, d = W.H, W.d[b]
	local r = {}
	r.retreat = H.Intent.Resolve(b, BotMode.Retreat, d.retreat)
	r.laning = H.Intent.Resolve(b, BotMode.Laning, d.laning)
	r.roam = H.Intent.Resolve(b, BotMode.TeamRoam, H.LaneFight.RoamDesire(b, d.roam))
	r.attack = d.attack
	local best, bestMode = -1, nil
	for _, m in ipairs({ { BotMode.Retreat, r.retreat }, { BotMode.Laning, r.laning }, { BotMode.TeamRoam, r.roam }, { BotMode.Attack, r.attack } }) do
		local eff = m[1] == b.mode and m[2] * 1.1 or m[2]
		if eff > best then best, bestMode = eff, m[1] end
	end
	b.mode = bestMode
end

-- Frames at 30 fps in engine order: a scoring round every ROUND, team_roam's Think every frame while it is active, then
-- the humaniser tick (ItemUsageThink): LaneFight.Tick, then Intent.Tick. The engine part: an attack order walks into
-- range with the attack target set, a move order walks.
local function play(W, seconds)
	local stop = T + seconds - 1e-9
	while T < stop do
		if T >= W.nextRound - 1e-9 then
			for _, b in ipairs(W.bots) do score(W, b) end
			W.nextRound = W.nextRound + ROUND
		end
		for _, b in ipairs(W.bots) do
			if b.mode == BotMode.TeamRoam then
				ACTIONS = {}
				if W.LF.Think(b) then
					local a = ActionsOf(b.pid)[1]
					if a and a.kind == "AttackUnit" then
						if dist(b, a.args[1]) > b:GetAttackRange() + 50 then W.attackOrderedOutOfRange = (W.attackOrderedOutOfRange or 0) + 1 end
						b.target = a.args[1]
						if dist(b, a.args[1]) > b:GetAttackRange() then step(b, a.args[1].loc) end
					elseif a and a.kind == "MoveToLocation" then
						b.target = nil
						step(b, a.args[1])
					end
				end
			end
			W.LF.Tick(b)
			W.H.Intent.Tick(b)
		end
		if W.onFrame then W.onFrame() end
		T = T + FRAME
	end
end

-- The test-driven partner goes in from `at`: attack target set, walking at the target.
local function charge(W, at, target)
	W.onFrame = function()
		if T >= at - 1e-9 then
			W.partner.target = target or W.enemy
			if dist(W.partner, W.enemy) > 150 then step(W.partner, W.enemy.loc) end
		end
	end
end

-- A partner trading the enemy (attack target set, walking in, then attacking every 0.5 s in range) for `trade` s.
-- W.hits lists its attack times: a follow needs the second (one walk-in hit is how a harass looks).
local function trading(W, from, trade)
	W.hits = {}
	W.onFrame = function()
		if T < from - 1e-9 then return end
		if trade ~= nil and T >= from + trade - 1e-9 then
			W.partner.target = nil
			return
		end
		W.partner.target = W.enemy
		if dist(W.partner, W.enemy) > W.partner:GetAttackRange() - 50 then step(W.partner, W.enemy.loc)
		elseif (W.partner.lastAttack or -1000) < GameTime() - 0.5 + 1e-9 then
			W.partner.lastAttack = GameTime()
			table.insert(W.hits, T)
		end
	end
end

local function playUntil(W, fn, limit)
	local stop = T + limit
	while not fn() and T < stop do play(W, FRAME) end
end

local function stun(ready) return { [0] = ability("lion_impale", { cd = 12, ready = ready, range = 500 }) } end

-- ------------------------------------------------------------------------------- the support initiates

for _, team in ipairs({ 2, 3 }) do
	local tag = team == 2 and " (radiant)" or " (dire)"
	local W = world({ team = team, burst = 400, partner = { driven = true, pos = 5, burst = 400, abilities = stun(true) } })
	local core, support = W.bot, W.partner
	local waitingHeld, waitingFloor, coreModes, firstHit = false, false, {}, nil
	W.onFrame = function()
		if firstHit == nil and support.target == W.enemy then firstHit = T end
		if W.LF.CurrentPhase(core) == "wait_partner" then
			if W.H.Intent.HeldBy(core) == "lanefight:wait" then waitingHeld = true end
			if W.age(core, "wait_partner") ~= nil or W.H.Intent.Explain(core, BotMode.TeamRoam):find("lanefight", 1, true) then waitingFloor = true end
			coreModes[core.mode] = true
		end
	end
	play(W, 1.5)
	check("support with a stun initiates" .. tag, W.events("lanefight_start", "pid=2 phase=commit") == 1
		and W.events("lanefight_start", "pid=2 phase=commit target=6 margin=") == 1 and W.events("lanefight_start", "via=initiate") == 1,
		table.concat(W.lines, "\n"))
	check("the initiating support logs lanefight_commit role=initiator" .. tag,
		W.events("lanefight_commit", "pid=2 target=6 margin=") == 1 and W.events("lanefight_commit", "role=initiator") == 1, table.concat(W.lines, "\n"))
	check("the core waits for its support" .. tag, W.events("lanefight_start", "pid=1 phase=wait_partner target=6") == 1
		and W.events("lanefight_start", "with=2 human=0") == 1, table.concat(W.lines, "\n"))
	check("a waiting core holds still on purpose, posts no floor and keeps laning" .. tag, waitingHeld and not waitingFloor
		and coreModes[BotMode.Laning] and not coreModes[BotMode.TeamRoam])
	playUntil(W, function() return W.events("lanefight_start", "pid=1 phase=commit") > 0 end, 4)
	local coreAt = W.firstAt("lanefight_start", "pid=1 phase=commit")
	check("the support's commit Think attack-orders from out of range (walks in with the attack target set)" .. tag,
		(W.attackOrderedOutOfRange or 0) > 0 and #ActionsOf(2, "MoveToLocation") == 0)
	check("the core commits only after the support's visible commit" .. tag, firstHit ~= nil and coreAt ~= nil and coreAt > firstHit
		and W.events("lanefight_end", "pid=1 phase=wait_partner reason=commit") == 1
		and W.events("lanefight_start", "pid=1 phase=commit target=6 margin=") == 1, table.concat(W.lines, "\n"))
end

do
	local W = world({ burst = 400, partner = { driven = true, pos = 5, burst = 400, abilities = stun(false) } })
	play(W, 1.5)
	check("a core whose support has no ready stun commits itself", W.events("lanefight_start", "pid=1 phase=commit") == 1
		and W.events("lanefight_start", "phase=wait_partner") == 0, table.concat(W.lines, "\n"))
end

do
	-- A ready blink is a key-class escape, not a disable: the core does not wait on it.
	local W = world({ burst = 400, partner = { pos = 5, burst = 400, abilities = { [0] = ability("antimage_blink", { cd = 15 }) } } })
	play(W, 1.5)
	check("a support holding only a ready escape does not make its core wait", W.events("lanefight_start", "pid=1 phase=commit") == 1
		and W.events("lanefight_start", "phase=wait_partner") == 0, table.concat(W.lines, "\n"))
end

do
	-- The support never goes in: the core gives up after 3 s and keeps that kill pass spent.
	local W = world({ burst = 400, partner = { pos = 5, burst = 400, abilities = stun(true) } })
	playUntil(W, function() return W.events("lanefight_start", "phase=wait_partner") > 0 end, 2)
	local waitAt = T
	playUntil(W, function() return W.events("lanefight_end") > 0 end, 4)
	check("a wait with no partner commit ends after 3 s", W.events("lanefight_end", "phase=wait_partner reason=partner_timeout") == 1
		and math.abs(T - waitAt - 3) <= FRAME * 2, string.format("%.3f", T - waitAt))
	check("lanefight_end says the wait never took over", W.events("lanefight_end", "reason=partner_timeout hits=0 took=0") == 1,
		table.concat(W.lines, "\n"))
	play(W, 2)
	check("no new wait and no commit on the same kill pass", W.events("lanefight_start") == 1, table.concat(W.lines, "\n"))
end

-- ------------------------------------------------------------------------------------------ sync delay

for _, skill in ipairs({ 0, 1 }) do
	local W = world({ skill = skill, burst = 400, partner = { pos = 5, burst = 400, abilities = stun(true) } })
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "wait_partner" end, 2)
	local tp = T + 0.4
	charge(W, tp)
	playUntil(W, function() return W.events("lanefight_start", "phase=commit") > 0 end, 3)
	local react = W.H.Profile.SampleDelay(W.bot, "react")
	local sync = W.LF.Config.Curve("SyncDelay", skill)
	local at = W.firstAt("lanefight_start", "phase=commit")
	-- The partner's first step is visible on the next frame; the follow then lands on the first frame at or after its time.
	local want = tp + FRAME + react + sync
	check(string.format("core follows the partner's visible commit after react + SyncDelay at skill %d", skill),
		at ~= nil and at >= want - 1e-6 and at <= want + FRAME + 1e-6 and W.events("lanefight_start", "via=follow") == 1,
		string.format("at %s want %.3f (react %.3f sync %.3f)", tostring(at), want, react, sync))
	check(string.format("the following core logs lanefight_commit role=follower at skill %d", skill),
		W.events("lanefight_commit", "pid=1 target=6 margin=") == 1 and W.events("lanefight_commit", "role=follower") == 1, table.concat(W.lines, "\n"))
end

-- ------------------------------------------------------------------------------------------ human partner

do
	local W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40 } })
	play(W, 1)
	check("setup: a margin of 0.9 is no kill pass", W.events("lanefight_start") == 0 and #W.said == 0)
	trading(W, T)
	playUntil(W, function() return W.events("lanefight_start", "phase=commit") > 0 end, 4)
	local second = W.hits[2]
	local want = second ~= nil and second + W.H.Profile.SampleDelay(W.bot, "react") + W.LF.Config.Curve("SyncDelay", 1) or math.huge
	local at = W.firstAt("lanefight_start", "phase=commit")
	check("follows a human partner's attacks on an enemy hero after the second hit", at ~= nil and at >= want - 1e-6
		and at <= want + 2 * FRAME + 1e-6 and W.events("lanefight_start", "via=follow") == 1,
		string.format("at %s want %.3f", tostring(at), want))
end

do
	-- Attacking a creep while walking at the enemy is no commit on the enemy.
	local W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40 } })
	local creep = MakeCreep({ team = 3, x = 200, y = BOT_Y })
	charge(W, T, creep)
	play(W, 2)
	check("a human attacking a creep is not followed", W.events("lanefight_start") == 0, table.concat(W.lines, "\n"))
	-- An attack on the enemy from out of range without closing is no commit either.
	W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40, x = -700 } })
	W.partner.target = W.enemy
	play(W, 2)
	check("a human attack order that does not close is not followed", W.events("lanefight_start") == 0, table.concat(W.lines, "\n"))
	-- Below FollowMargin (0.8) the bot does not follow.
	W = world({ burst = 30, partner = { human = true, pos = 5, burst = 40 } })
	trading(W, T)
	play(W, 3)
	check("a margin below FollowMargin does not follow, logged once", W.events("lanefight_start") == 0
		and W.events("lanefight_gate", "gate=follow-margin") == 1, table.concat(W.lines, "\n"))
end

do
	-- An illusion of the enemy carries its player ID; attacking it while closing is no commit on the enemy.
	local W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40 } })
	charge(W, T, setmetatable({ IsIllusion = function() return true end }, { __index = W.enemy }))
	play(W, 2)
	check("a human attacking an illusion of the enemy is not followed", W.events("lanefight_start") == 0, table.concat(W.lines, "\n"))
end

do
	-- One in-range right-click, then walking away: a harass hit, not a commit.
	local W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40, x = -200 } })
	local hitAt = T + 0.3
	W.onFrame = function()
		if math.abs(T - hitAt) < FRAME / 2 then W.partner.target, W.partner.lastAttack = W.enemy, T end
		if T > hitAt + 0.2 then W.partner.target = nil step(W.partner, W.loc(-1500)) end
	end
	play(W, 3)
	check("one in-range hit then walking away is not followed", W.events("lanefight_start") == 0, table.concat(W.lines, "\n"))

	-- In game (snapfire at 1:05): a harass walks in on the target, lands one hit and goes back to the wave. The walk-in
	-- alone must not be followed.
	W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40, x = -700 } })
	local walkFrom = T + 0.3
	local hit
	W.onFrame = function()
		if T < walkFrom - 1e-9 then return end
		if hit == nil then
			W.partner.target = W.enemy
			if dist(W.partner, W.enemy) > W.partner:GetAttackRange() - 50 then step(W.partner, W.enemy.loc)
			else hit = T W.partner.lastAttack = T end
		elseif T > hit + 0.2 then
			W.partner.target = nil
			step(W.partner, W.loc(-1500))
		end
	end
	play(W, 4)
	check("setup: the harass walked in and landed its hit", hit ~= nil and hit > walkFrom + 0.5, tostring(hit))
	check("a walk-in harass with one hit is not followed", W.events("lanefight_start") == 0, table.concat(W.lines, "\n"))

	-- Sustained attacks from range: two within 1.5 s make a commit.
	W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40, x = -200 } })
	W.partner.target = W.enemy
	local first = T + 0.3
	W.onFrame = function()
		if T >= first - 1e-9 and (W.partner.lastAttack or -1000) < T - 0.5 + 1e-9 then W.partner.lastAttack = T end
	end
	play(W, 3)
	local at = W.firstAt("lanefight_start", "via=follow")
	local want = first + 0.5 + W.H.Profile.SampleDelay(W.bot, "react") + W.LF.Config.Curve("SyncDelay", 1)
	check("sustained in-range attacks are followed after the second hit", at ~= nil and at >= want - 1e-6 and at <= want + 2 * FRAME + 1e-6,
		string.format("at %s want %.3f", tostring(at), want))

	-- A level-1 hero attacking every 2 s: the second hit lands inside InRangeWindow (2.5 s), so it is a commit.
	local function slowAttacks(cfg)
		local w = world({ burst = 50, partner = { human = true, pos = 5, burst = 40, x = -200 }, laneFight = cfg })
		w.partner.target = w.enemy
		local f = T + 0.3
		w.onFrame = function()
			if T >= f - 1e-9 and (w.partner.lastAttack or -1000) < T - 2 + 1e-9 then w.partner.lastAttack = T end
		end
		play(w, 4)
		return w, f
	end
	local slow, slowFirst = slowAttacks()
	local slowAt = slow.firstAt("lanefight_start", "via=follow")
	local slowWant = slowFirst + 2 + slow.H.Profile.SampleDelay(slow.bot, "react") + slow.LF.Config.Curve("SyncDelay", 1)
	check("in-range attacks 2 s apart are followed after the second hit", slowAt ~= nil and slowAt >= slowWant - 1e-6
		and slowAt <= slowWant + 2 * FRAME + 1e-6, string.format("at %s want %.3f", tostring(slowAt), slowWant))
	slow = slowAttacks({ InRangeWindow = 1.5 })
	check("InRangeWindow is read from config: at 1.5 s, attacks 2 s apart are not a commit", slow.events("lanefight_start") == 0,
		table.concat(slow.lines, "\n"))

	-- The partner lands two hits from range, then stops before the follow time (skill 0: over 1 s): no follow, logged once.
	W = world({ skill = 0, burst = 50, partner = { human = true, pos = 5, burst = 40, x = -200 } })
	local tp = T + 0.3
	W.onFrame = function()
		if T >= tp - 1e-9 and T < tp + 0.6 then
			W.partner.target = W.enemy
			if (W.partner.lastAttack or -1000) < T - 0.5 + 1e-9 then W.partner.lastAttack = T end
		elseif T >= tp + 0.6 then
			W.partner.target = nil
		end
	end
	play(W, 4)
	check("a partner that backs off before the follow time is not followed", W.events("lanefight_start") == 0
		and W.events("lanefight_gate", "gate=partner_backed_off") == 1, table.concat(W.lines, "\n"))
end

do
	-- A human's key-class cast towards the enemy, within its cast range + 200, is a commit. Burst credited for the walk
	-- into range (bot 5/6, partner 13/15): 0.92, a follow but no kill pass of its own.
	local W = world({ burst = 60, partner = { human = true, pos = 5, burst = 48 } })
	local cast = ability("lion_impale", { range = 600 })
	W.onFrame = function() W.partner.casting = cast end
	play(W, 2)
	check("a human's stun cast facing the enemy is followed", W.events("lanefight_start", "via=follow") == 1, table.concat(W.lines, "\n"))
	W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40 } })
	W.partner.facing = W.partner.facing + 90
	W.onFrame = function() W.partner.casting = cast end
	play(W, 2)
	check("the same cast facing 90 degrees away is not", W.events("lanefight_start") == 0, table.concat(W.lines, "\n"))
end

for _, case in ipairs({ { skill = 0.5, burst = 120, what = "a kill" }, { skill = 0.5, burst = 1000, what = "an overwhelming kill" } }) do
	local W = world({ skill = case.skill, burst = case.burst, partner = { human = true, pos = 5, burst = 500 } })
	play(W, 6)
	local s = W.said[1]
	check("with a human partner " .. case.what .. " at skill 0.5 calls once", #W.said == 1 and s.key == "say_lanefight_go" and s.cooldown == 30
		and s.args ~= nil and s.args[1] == "6" and W.events("lanefight_call", "pid=1 target=6") == 1, #W.said)
	check("... and pings the target once", #PINGS == 1 and PINGS[1].pid == 1 and math.abs(PINGS[1].x - W.enemy.loc.x) < 1, #PINGS)
	check("... and does not dive alone", W.events("lanefight_start", "phase=commit") == 0
		and W.events("lanefight_end", "phase=wait_partner reason=partner_timeout") == 1, table.concat(W.lines, "\n"))
end

do
	local W = world({ skill = 0.5, burst = 120, partner = { human = true, pos = 5, burst = 500 } })
	W.H.Lane.Config.Helpers().HeroDisplayName = function(u) return u:GetPlayerID() == 6 and "Lion" or nil end
	play(W, 1.5)
	check("the call names the hero by its display name", W.said[1] ~= nil and W.said[1].args[1] == "Lion")
	W = world({ skill = 0.5, burst = 120, partner = { human = true, pos = 5, burst = 500 }, laneFight = { CallKills = false } })
	play(W, 1.5)
	check("CallKills off: no line and no ping, still waits", #W.said == 0 and #PINGS == 0 and W.events("lanefight_start", "phase=wait_partner") == 1)
end

do
	-- A second kill pass 12 s later (past Say's 10 s line limit) waits again but does not call: CallCooldown is 30 s.
	local W = world({ skill = 0.5, burst = 120, partner = { human = true, pos = 5, burst = 500 } })
	play(W, 4)
	W.enemy.hiddenFrom = { [W.bot] = true }
	play(W, 8)
	W.enemy.hiddenFrom = nil
	play(W, 4)
	check("a second kill pass within CallCooldown waits without a second call", W.events("lanefight_start", "phase=wait_partner") == 2
		and #W.said == 1 and W.events("lanefight_call") == 1, table.concat(W.lines, "\n"))
	W.enemy.hiddenFrom = { [W.bot] = true }
	play(W, 16)
	W.enemy.hiddenFrom = nil
	play(W, 2)
	check("past CallCooldown the next pass calls again", #W.said == 2 and W.events("lanefight_call") == 2, #W.said)
end

do
	local W = world({ skill = 0.8, burst = 1000, partner = { human = true, pos = 5, burst = 500 } })
	play(W, 1.5)
	check("overwhelming kill at skill 0.8 commits alone", W.events("lanefight_start", "phase=commit") == 1
		and W.events("lanefight_start", "via=solo") == 1 and W.events("lanefight_start", "phase=wait_partner") == 0, table.concat(W.lines, "\n"))
	check("a solo commit logs lanefight_commit role=solo", W.events("lanefight_commit", "pid=1 target=6 margin=") == 1
		and W.events("lanefight_commit", "role=solo") == 1, table.concat(W.lines, "\n"))
	-- The solo check leaves the human out: 120 of burst alone is a margin of 1.2, not overwhelming.
	W = world({ skill = 0.8, burst = 120, partner = { human = true, pos = 5, burst = 1000 } })
	play(W, 1.5)
	check("at skill 0.8 a kill that is overwhelming only with the human waits for the human",
		W.events("lanefight_start", "phase=commit") == 0 and W.events("lanefight_start", "phase=wait_partner") == 1, table.concat(W.lines, "\n"))
end

do
	-- Two supports, neither with a ready disable: each goes on its own solo check rather than waiting on the other.
	local W = world({ botPos = 4, burst = 400, partner = { driven = true, pos = 5, burst = 400 } })
	play(W, 1.5)
	check("a dual-support lane without disables still commits", W.events("lanefight_start", "pid=1 phase=commit") == 1
		and W.events("lanefight_start", "pid=2 phase=commit") == 1 and W.events("lanefight_start", "phase=wait_partner") == 0,
		table.concat(W.lines, "\n"))
end

do
	-- Out of range, a commit's Think attack-orders the target (a trade still walks there).
	local W = world({ burst = 1000, botPos = 5, botX = -700 })
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	W.bot.mode = BotMode.TeamRoam
	ACTIONS = {}
	W.LF.Think(W.bot)
	local a = ActionsOf(1)[1]
	check("an out-of-range commit Think orders an attack, not a move", a ~= nil and a.kind == "AttackUnit" and a.args[1] == W.enemy
		and dist(W.bot, W.enemy) > W.bot:GetAttackRange() + 50, a and a.kind)
end

do
	-- Default FollowMargin 1.0: a partner's trade-shaped attacks on a target the bot reads at 0.9 are not followed.
	local W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40 }, defaultFollow = true })
	trading(W, T)
	play(W, 3)
	check("default FollowMargin: a 0.9 margin is not followed", W.events("lanefight_start") == 0
		and W.events("lanefight_gate", "gate=follow-margin") == 1, table.concat(W.lines, "\n"))
end

-- ------------------------------------------------------------------------------------------------ aborts

do
	-- A follow went in on margin 0.9 (no full pass): its re-check after an escape holds it to FollowMargin, not a pass.
	local W = world({ burst = 50, partner = { human = true, pos = 5, burst = 40 }, enemyAbilities = { [0] = ability("lion_impale", { cd = 12 }),
		[1] = ability("antimage_blink", { cd = 15 }) } })
	trading(W, T)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 3)
	check("setup: a follow commit", W.events("lanefight_start", "via=follow") == 1, table.concat(W.lines, "\n"))
	W.enemy.casting = W.enemy.abilities[1]
	play(W, 0.2)
	W.enemy.casting = nil
	play(W, 0.5)
	check("a follow commit's re-check passes on FollowMargin", W.LF.CurrentPhase(W.bot) == "commit"
		and W.events("lanefight_recheck", "reason=escape pass=1") == 1, table.concat(W.lines, "\n"))
end

-- A partner whose commit the kill check counted stops going in: after AbortNotice the commit re-checks solo.
do
	-- The support initiates on a check that counts its core (60 + 60 of burst); the core never follows.
	local W = world({ botPos = 5, burst = 60, botAbilities = stun(true), partner = { pos = 1, burst = 60 } })
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	check("setup: the support initiates counting its core", W.events("lanefight_start", "pid=1 phase=commit") == 1
		and W.events("lanefight_start", "via=initiate") == 1, table.concat(W.lines, "\n"))
	playUntil(W, function() return W.events("lanefight_end") > 0 end, 5)
	check("an initiator whose partner never follows re-checks solo and ends", W.events("lanefight_end", "phase=commit reason=partner_abandon") == 1
		and W.events("lanefight_recheck", "reason=partner_abandon pass=0") == 1, table.concat(W.lines, "\n"))

	-- In game (earthshaker at 1:29) the support initiated counting a core at 46% HP, below CommitStartHP, which the core
	-- itself needs to commit: it never followed.
	W = world({ botPos = 5, burst = 60, botAbilities = stun(true), partner = { pos = 1, burst = 60 } })
	W.partner.hp = 46
	play(W, 2)
	check("a support does not initiate counting a core below CommitStartHP", W.events("lanefight_start", "phase=commit") == 0,
		table.concat(W.lines, "\n"))
	W = world({ botPos = 5, burst = 60, botAbilities = stun(true), partner = { pos = 1, burst = 60 } })
	W.partner.hp = 66
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	check("a core at CommitStartHP still counts", W.events("lanefight_start", "via=initiate") == 1, table.concat(W.lines, "\n"))
	W = world({ botPos = 5, burst = 120, botAbilities = stun(true), partner = { pos = 1, burst = 60 } })
	W.partner.hp = 46
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	check("a support that kills alone still initiates with a hurt core, counting none", W.events("lanefight_start", "via=initiate") == 1
		and W.events("lanefight_commit", "role=solo") + W.events("lanefight_commit", "role=initiator") == 1, table.concat(W.lines, "\n"))
end

do
	-- In game (6:05) the core waited on one target while its support went in on another; it followed only "its" target.
	local W = world({ burst = 400, partner = { pos = 5, burst = 400, abilities = stun(true) } })
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "wait_partner" end, 2)
	check("setup: the core waits on target 6", W.events("lanefight_start", "pid=1 phase=wait_partner target=6") == 1, table.concat(W.lines, "\n"))
	local other = MakeUnit({ pid = 7, team = 3, loc = W.loc(250), level = 1, hp = 100 })
	other.lane = Lane.Bot
	other.abilities = W.enemy.abilities
	W.onFrame = function()
		W.partner.target = other
		if dist(W.partner, other) > 150 then step(W.partner, other.loc) end
	end
	playUntil(W, function() return W.events("lanefight_start", "phase=commit") > 0 end, 3)
	check("a waiting core follows its partner going in on another lane enemy", W.events("lanefight_start", "pid=1 phase=commit target=7") == 1
		and W.events("lanefight_start", "via=follow") == 1, table.concat(W.lines, "\n"))
end

do
	-- The follow-margin gate names the margin and, on a veto, the kill check's reason.
	local W = world({ burst = 30, partner = { human = true, pos = 5, burst = 40 } })
	trading(W, T)
	play(W, 3)
	check("the follow-margin gate logs its margin", W.events("lanefight_gate", "gate=follow-margin target=6 margin=0.650") == 1, table.concat(W.lines, "\n"))
end


do
	local W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	local from = T
	trading(W, from, 2.5)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	check("setup: the core follows its trading partner", W.events("lanefight_start", "pid=1 phase=commit") == 1
		and W.events("lanefight_start", "via=follow") == 1, table.concat(W.lines, "\n"))
	playUntil(W, function() return W.events("lanefight_end") > 0 end, 5)
	local endAt = W.firstAt("lanefight_end")
	check("a follower whose partner's trade ends re-checks solo and ends", endAt ~= nil and endAt >= from + 2.5
		and W.events("lanefight_end", "phase=commit reason=partner_abandon") == 1
		and W.events("lanefight_recheck", "reason=partner_abandon pass=0") == 1, table.concat(W.lines, "\n"))
	check("the abandon logs what the partner was doing: unseen, no attack target", W.events("lanefight_abandon",
		"why=unseen") == 1 and W.events("lanefight_abandon", "ally=" .. W.partner.pid .. " ") == 1
		and W.events("lanefight_abandon", "atk=-") == 1, table.concat(W.lines, "\n"))

	W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	trading(W, T)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	play(W, 4)
	check("a partner that keeps committing raises no partner abort", W.LF.CurrentPhase(W.bot) == "commit"
		and W.events("lanefight_recheck") == 0 and W.events("lanefight_abort") == 0, table.concat(W.lines, "\n"))
end

-- In game most partner abandons were partners plainly on the target: chasing just past range + slack measured
-- centre to centre, or next to it between attacks with no attack target set at that instant.
do
	-- A melee partner (range 150) holding the target at 230 centre to centre: 182 edge to edge with 24 hulls.
	local W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	trading(W, T)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	check("setup: a follow commit", W.events("lanefight_start", "via=follow") == 1, table.concat(W.lines, "\n"))
	W.partner.range = 150
	W.onFrame = function()
		W.partner.target = W.enemy
		W.partner.loc = Vector(W.enemy.loc.x - W.sign * 230, BOT_Y)
	end
	play(W, 3)
	check("a melee partner on the target within range + both hulls is not abandoned", W.LF.CurrentPhase(W.bot) == "commit"
		and W.events("lanefight_abandon") == 0, table.concat(W.lines, "\n"))

	-- Next to the target, attacking every 1.7 s (level 1), the attack target set only on the attack's frame.
	W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	trading(W, T)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	W.onFrame = function()
		W.partner.target = nil
		if (W.partner.lastAttack or -1000) < GameTime() - 1.7 + 1e-9 then
			W.partner.target = W.enemy
			W.partner.lastAttack = GameTime()
		end
	end
	play(W, 4)
	check("a partner attacking the target every 1.7 s is not abandoned between attacks", W.LF.CurrentPhase(W.bot) == "commit"
		and W.events("lanefight_abandon") == 0, table.concat(W.lines, "\n"))
end

do
	-- In game (0:40) both bots chased a fleeing target at the same speed: no attack target while out of range, not closing.
	-- The bot is kept in range so its own ChaseMax does not decide; the partner runs after the target, 400 behind.
	local function chase(partnerMoves)
		local W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
		trading(W, T)
		playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
		play(W, 0.6)
		W.onFrame = function()
			W.enemy.loc = Vector(W.enemy.loc.x + W.sign * SPEED * FRAME, BOT_Y)
			W.bot.loc = Vector(W.enemy.loc.x - W.sign * 300, BOT_Y)
			W.partner.target = nil
			if partnerMoves then step(W.partner, W.enemy.loc)
			else W.partner.facing = W.sign > 0 and 0 or 180 end
			if dist(W.partner, W.enemy) < 400 then W.partner.loc = Vector(W.enemy.loc.x - W.sign * 400, BOT_Y) end
		end
		play(W, 4)
		return W
	end
	local W = chase(true)
	check("a partner chasing the target at its pace is not abandoned", W.LF.CurrentPhase(W.bot) == "commit"
		and W.events("lanefight_abandon") == 0, table.concat(W.lines, "\n"))
	W = chase(false)
	check("a partner standing still facing the target is abandoned", W.events("lanefight_abandon", "why=unseen") == 1, table.concat(W.lines, "\n"))
end

do
	-- A follow commit re-checks to FollowMargin (0.82 here passes it), but under the target's tower 0.82 is short of
	-- TowerOverride: the dive still ends.
	local W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	trading(W, T)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	check("setup: a follow commit at margin 0.82", W.events("lanefight_start", "margin=0.817 via=follow") == 1, table.concat(W.lines, "\n"))
	local tower
	for _, t in pairs(TOWERS_W[3]) do if math.abs(t.loc.y - BOT_Y) < 1000 then tower = t end end
	W.enemy.loc = Vector(tower.loc.x - 600, BOT_Y)
	W.bot.loc = Vector(W.enemy.loc.x - 300, BOT_Y)
	W.partner.loc = Vector(W.enemy.loc.x - 350, BOT_Y)
	play(W, 1)
	check("a follow commit's tower re-check needs TowerOverride, not FollowMargin", W.events("lanefight_end", "phase=commit reason=tower") == 1,
		table.concat(W.lines, "\n"))
end

do
	-- A partner that stops: its last attack counts for PARTNER_RECENT_ATTACK, then PartnerLapse, then the re-check.
	local function stops(cfg)
		local W = world({ burst = 50, partner = { pos = 5, burst = 40 }, laneFight = cfg })
		trading(W, T)
		playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
		play(W, 0.6)
		W.onFrame = function()
			W.partner.target = nil
			step(W.partner, W.loc(-1500))
		end
		local stop = W.partner.lastAttack
		playUntil(W, function() return W.events("lanefight_abandon") > 0 end, 6)
		return W, stop, W.firstAt("lanefight_abandon")
	end
	local W, stop, at = stops()
	check("an abandon waits for the last attack's 1.5 s and PartnerLapse (1 s)", at ~= nil and at >= stop + 2.5 - 1e-6
		and at <= stop + 2.5 + 0.4, string.format("stop %.3f abandon %s", stop, tostring(at)))
	W, stop, at = stops({ PartnerLapse = 0.3 })
	check("PartnerLapse is read from config", at ~= nil and at >= stop + 1.8 - 1e-6 and at <= stop + 1.8 + 0.4,
		string.format("stop %.3f abandon %s", stop, tostring(at)))
end

do
	-- The engine's GetLastAttackTime is on GameTime(), which runs ahead of DotaTime() by the pre-horn time.
	local dotaGameTime = GameTime
	GameTime = function() return T + 190 end
	local W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	trading(W, T, 2.5)
	local ok = pcall(function()
		playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
		playUntil(W, function() return W.events("lanefight_abandon") > 0 end, 6)
	end)
	GameTime = dotaGameTime
	local line
	for _, l in ipairs(W.lines) do if l:find("ev=lanefight_abandon", 1, true) then line = l end end
	local since = line and tonumber(line:match("lastatk=([%-%d%.]+)"))
	check("lanefight_abandon's lastatk is seconds since the partner's last attack on the game clock", ok and since ~= nil
		and since >= 0 and since < 4, tostring(line))
end

-- The target jukes into fog mid-commit while the partner keeps chasing it. As in the engine, the handle answers
-- CanBeSeen false at once. Skill 1: AbortNotice 0.15 s, FogGrace 1 s.
local function fog(W, on)
	W.enemy.hiddenFrom = on and { [W.bot] = true } or nil
	W.enemy.CanBeSeen = function() return not on end
end

do
	local W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	trading(W, T)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	check("setup: a follow commit counting its partner", W.events("lanefight_start", "via=follow") == 1, table.concat(W.lines, "\n"))
	play(W, 0.3)
	fog(W, true)
	play(W, 0.5)
	fog(W, false)
	play(W, 1)
	check("a 0.5 s fog blip on the target with the partner still chasing keeps the commit", W.LF.CurrentPhase(W.bot) == "commit"
		and W.events("lanefight_end") == 0 and W.events("lanefight_recheck", "reason=partner_abandon") == 0, table.concat(W.lines, "\n"))

	W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	trading(W, T)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	play(W, 0.3)
	fog(W, true)
	LAST_SEEN[6] = { location = W.enemy.loc, time_since_seen = 0 }
	playUntil(W, function() return W.events("lanefight_end") > 0 end, 2)
	check("a target in fog past FogGrace ends a partnered commit on fog, not partner_abandon",
		W.events("lanefight_end", "phase=commit reason=fog") == 1 and W.events("lanefight_recheck", "reason=partner_abandon") == 0,
		table.concat(W.lines, "\n"))
	LAST_SEEN[6] = nil

	-- After a fog blip the partner stops chasing while the target is visible: the abandon still fires.
	W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	local from = T
	trading(W, from, 2.5)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	play(W, 0.3)
	fog(W, true)
	play(W, 0.5)
	fog(W, false)
	playUntil(W, function() return W.events("lanefight_end") > 0 end, 4)
	local endAt = W.firstAt("lanefight_end")
	check("after a fog blip, a partner that backs off with the target visible still ends partner_abandon", endAt ~= nil
		and endAt >= from + 2.5 and W.events("lanefight_end", "phase=commit reason=partner_abandon") == 1, table.concat(W.lines, "\n"))
end

local blinkWorld = function(skill)
	local W = world({ skill = skill, burst = 1000, botPos = 5, enemyAbilities = { [0] = ability("lion_impale", { cd = 12 }),
		[1] = ability("antimage_blink", { cd = 15 }) } })
	-- The bot remembers the blink as down, so its kill check passes.
	W.H.LaneFight.CooldownMemory.Record(1, 6, "antimage_blink", "key", 15, 1, T)
	return W
end

for _, skill in ipairs({ 0, 1 }) do
	local W = blinkWorld(skill)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	check("setup: committed with the blink believed down at skill " .. skill, W.LF.CurrentPhase(W.bot) == "commit")
	play(W, 0.3)
	local blink = W.enemy.abilities[1]
	W.enemy.casting = blink
	playUntil(W, function() return W.LF.CastWatch.LastSeenCast(1) ~= nil end, 1)
	local seenAt = W.LF.CastWatch.LastSeenCast(1).at
	W.enemy.casting = nil
	-- The blink lands 1300 from the bot: out of its burst range.
	W.enemy.loc = Vector(W.bot.loc.x + W.sign * 1300, BOT_Y)
	playUntil(W, function() return W.events("lanefight_end") > 0 end, 2)
	local notice = W.LF.Config.Curve("AbortNotice", skill)
	local endAt = W.firstAt("lanefight_end")
	check(string.format("escape cast triggers a re-check after AbortNotice at skill %d", skill), endAt ~= nil
		and endAt >= seenAt + notice - 1e-6 and endAt <= seenAt + notice + FRAME + 1e-6
		and W.events("lanefight_end", "phase=commit reason=escape") == 1 and W.events("lanefight_abort", "reason=escape") == 1
		and W.events("lanefight_recheck", "pid=1 reason=escape pass=0") == 1,
		string.format("seen %.3f end %s notice %.2f\n%s", seenAt, tostring(endAt), notice, table.concat(W.lines, "\n")))
	check("the escape believed down and cast within 2 s is a bad-memory mistake at skill " .. skill,
		W.events("lanefight_mistake", "pid=1 kind=bad_memory ability=antimage_blink") == 1, table.concat(W.lines, "\n"))
end

do
	local W = blinkWorld(1)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	W.enemy.casting = W.enemy.abilities[1]
	play(W, 0.15)
	W.enemy.casting = nil
	play(W, 1)
	check("a re-check that still passes keeps the commit", W.LF.CurrentPhase(W.bot) == "commit" and W.events("lanefight_end") == 0
		and W.events("lanefight_recheck", "reason=escape pass=1") == 1, table.concat(W.lines, "\n"))
end

do
	-- A second enemy walks into the lane mid-commit: two of them against our one.
	local W = world({ burst = 1000, botPos = 5 })
	local second = MakeUnit({ pid = 7, team = 3, loc = W.loc(3000), level = 1, hp = 100 })
	second.lane = Lane.Bot
	second.alive = false
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	play(W, 0.3)
	second.alive = true
	second.loc = W.loc(500)
	local appeared = T
	playUntil(W, function() return W.events("lanefight_end") > 0 end, 2)
	check("a rising enemy count re-checks after AbortNotice and aborts", W.events("lanefight_end", "reason=outnumbered") == 1
		and W.events("lanefight_recheck", "reason=outnumbered pass=0") == 1 and T - appeared >= W.LF.Config.Curve("AbortNotice", 1) - 1e-6,
		table.concat(W.lines, "\n"))
end

do
	-- A commit stays on its target when a nearer killable enemy walks up (2 v 2, so no count abort).
	local W = world({ burst = 1000, partner = { pos = 5, burst = 0, abilities = stun(false) } })
	local second = MakeUnit({ pid = 7, team = 3, loc = W.loc(3000), level = 1, hp = 100 })
	second.lane = Lane.Bot
	second.alive = false
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	second.alive = true
	second.loc = Vector(W.bot.loc.x + W.sign * 200, BOT_Y)
	play(W, 1.5)
	check("a commit does not switch to a nearer killable enemy", W.LF.Target(W.bot) == W.enemy and W.events("lanefight_start") == 1
		and W.events("lanefight_end") == 0, table.concat(W.lines, "\n"))
end

-- ------------------------------------------------------------------------------------------- bad memory

local function spellWorld()
	local W = world({ burst = 0, botPos = 5 })
	W.H.LaneFight.CooldownMemory.Record(1, 6, "lion_impale", "key", 12, 1, T)
	return W
end

do
	local W = spellWorld()
	playUntil(W, function() return W.events("lanefight_start", "phase=trade") > 0 end, 2)
	check("setup: a spell-window trade", W.events("lanefight_start", "phase=trade target=6 window=spell") == 1, table.concat(W.lines, "\n"))
	play(W, 1)
	W.enemy.casting = W.enemy.abilities[0]
	play(W, 0.3)
	check("bad memory emits the mistake event", W.events("lanefight_mistake", "pid=1 kind=bad_memory ability=lion_impale") == 1,
		table.concat(W.lines, "\n"))
	play(W, 1)
	check("one mistake per start", W.events("lanefight_mistake") == 1)

	W = spellWorld()
	playUntil(W, function() return W.events("lanefight_start", "phase=trade") > 0 end, 2)
	play(W, 2.1)
	W.enemy.casting = W.enemy.abilities[0]
	play(W, 0.3)
	check("a cast more than 2 s after the start is no mistake", W.events("lanefight_mistake") == 0)

	W = spellWorld()
	playUntil(W, function() return W.events("lanefight_start", "phase=trade") > 0 end, 2)
	W.enemy.casting = W.enemy.abilities[5]
	play(W, 0.3)
	check("casting an ability that was not believed down is no mistake", W.events("lanefight_mistake") == 0)
end

do
	-- A spell-window trade (impale and voodoo believed down) upgrades to a commit after voodoo's remembered cooldown
	-- ran out, so the commit's own read has no spell window. The trade's bet must survive the upgrade.
	local W = world({ burst = 0, botPos = 5, enemyAbilities = { [0] = ability("lion_impale", { cd = 12 }), [1] = ability("lion_voodoo", { cd = 12 }) } })
	W.H.LaneFight.CooldownMemory.Record(1, 6, "lion_impale", "key", 12, 1, T)
	W.H.LaneFight.CooldownMemory.Record(1, 6, "lion_voodoo", "key", 1, 1, T)
	playUntil(W, function() return W.events("lanefight_start", "phase=trade") > 0 end, 2)
	local tradeAt = T
	check("setup: a spell-window trade", W.events("lanefight_start", "phase=trade target=6 window=spell") == 1, table.concat(W.lines, "\n"))
	play(W, 0.9)
	W.bot.estDamage = 1000
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 1)
	W.enemy.casting = W.enemy.abilities[0]
	play(W, 0.2)
	check("setup: the upgrade and the cast are within 2 s of the trade", W.LF.CastWatch.LastSeenCast(1) ~= nil
		and W.LF.CastWatch.LastSeenCast(1).at - tradeAt <= 2 and W.events("lanefight_end", "phase=trade reason=commit") == 1,
		table.concat(W.lines, "\n"))
	check("a trade's bad-memory bet survives its upgrade to a commit", W.events("lanefight_mistake", "ability=lion_impale") == 1,
		table.concat(W.lines, "\n"))
end

-- --------------------------------------------------------------------------------------- camp-job probe

do
	local W = world({ burst = 1000, botPos = 5 })
	local before = W.H.Lane.Hooks.IsFightCommitting(W.bot)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	local during = W.H.Lane.Hooks.IsFightCommitting(W.bot)
	W.bot.hp = 20
	play(W, ROUND)
	check("the lane-fight probe is true only while a commit is live", not before and during
		and not W.H.Lane.Hooks.IsFightCommitting(W.bot) and W.events("lanefight_end") == 1)

	W = world({ burst = 1000, botPos = 5 })
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	W.H.Config.Get().LaneFight.Enable = false
	check("the probe is false once LaneFight is off, before the commit is ended", W.LF.CurrentPhase(W.bot) == "commit"
		and not W.H.Lane.Hooks.IsFightCommitting(W.bot))
end

do
	-- Final review fix: a follow commit's tower re-check also needs the kill check to pass, so a follower clearing
	-- TowerOverride on margin but unable to survive the tower's shots still ends the dive.
	local W = world({ burst = 50, partner = { pos = 5, burst = 40 } })
	trading(W, T)
	playUntil(W, function() return W.LF.CurrentPhase(W.bot) == "commit" end, 2)
	check("setup (survive): a follow commit", W.events("lanefight_start", "via=follow") == 1, table.concat(W.lines, "\n"))
	local tower
	for _, t in pairs(TOWERS_W[3]) do if math.abs(t.loc.y - BOT_Y) < 1000 then tower = t end end
	W.bot.estDamage, W.partner.estDamage = 400, 400
	tower.dmg = 100
	W.enemy.loc = Vector(tower.loc.x - 600, BOT_Y)
	W.bot.loc = Vector(W.enemy.loc.x - 300, BOT_Y)
	W.partner.loc = Vector(W.enemy.loc.x - 350, BOT_Y)
	play(W, 1)
	check("a follower that cannot survive the tower ends the dive", W.events("lanefight_end", "phase=commit reason=tower") == 1,
		table.concat(W.lines, "\n"))
	tower.dmg = 0
end

finish()
