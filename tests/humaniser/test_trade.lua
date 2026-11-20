-- Trade (design 2026-11-19-trade-decision-design.md): Decide over plain inputs, one check per row of the design's section 7
-- table (case and control in one check, so a Decide that always answers none, or always the top level, fails every one),
-- then the ends of a running exchange, the order across candidates, Holds and the pure reads.
dofile(HARNESS_DIR .. "/dota_stubs.lua")
ResetWorld()
FreshHumaniser({ Enable = true, Telemetry = { Enable = false } })
local T = require("bots/FunLib/humaniser/states/trade")
local decide = function(i) return T.Decide(i) end

local CATCH = { ok = true, dmg = 900, first = 0.5, safe = 30 }
local function merge(base, o)
	for k, v in pairs(o or {}) do base[k] = v end
	return base
end
-- A favoured hit on a hero in reach, nothing else in the way.
local function cand(o)
	return merge({ pid = 7, thp = 0.7, thpAbs = 420, d = 300, gap = 100, away = 0, hitting = false, free = false,
		ko = 0.3, kt = 0.2, paid = false, tw = false }, o)
end
-- Safe.At's answers as Decide reads them: deadly vetoes a level, costly and safe pass.
local SAFE = { level = "safe", ratio = math.huge, reason = "safe" }
local COSTLY = { level = "costly", ratio = 3, reason = "hero" }
local function deadly(reason) return { level = "deadly", ratio = 0.5, reason = reason or "kill" } end
local function here(hit, hold) return { hit = hit, hold = hold or hit } end
local function inputs(o)
	return merge({ now = 100, hp = 1, safe = here(SAFE), n = 1, ms = 300, towerOnMe = false, creepsOnMe = 0, wave = 1, denyDue = false,
		cands = { cand() } }, o)
end
-- started = false: attack mode has not taken the offer (a nil would leave the default).
local function run(o)
	local r = merge({ level = "hit", target = 7, alive = true, offered = 2, started = 1.5, landed = false, soFar = 0, catchFails = 0 }, o)
	if r.started == false then r.started = nil end
	return r
end
local function unfavoured(o) return cand(merge({ ko = 0.2, kt = 0.3 }, o)) end
local function none(a, why) return a.level == "none" and a.reason == why end

check("Luna: target 0.21 with the catch ok, safe here: kill; deadly here: none, the answer's reason (kill); costly passes",
	decide(inputs({ cands = { cand({ thp = 0.21, thpAbs = 126, catch = CATCH }) } })).level == "kill"
		and none(decide(inputs({ safe = here(deadly("kill")), cands = { cand({ thp = 0.21, thpAbs = 126, catch = CATCH }) } })), "kill")
		and decide(inputs({ safe = here(COSTLY), cands = { cand({ thp = 0.21, thpAbs = 126, catch = CATCH }) } })).level == "kill")

-- The hit is judged without a hold, the hit back with one: a here answer that is deadly only without the hold refuses the hit and not the hit back.
-- HP enters only through the answer: 0.3 of max HP with a safe answer still hits back.
check("deadly without a hold, safe with one: a hitter is hit back (even at 0.3 HP), a quiet hero is not hit; deadly with the hold: neither",
	decide(inputs({ hp = 0.3, safe = here(deadly("kill"), SAFE), cands = { cand({ hitting = true }) } })).level == "hitback"
		and none(decide(inputs({ safe = here(deadly("kill"), SAFE), cands = { cand() } })), "kill")
		and none(decide(inputs({ safe = here(deadly("kill")), cands = { cand({ hitting = true }) } })), "kill")
		and decide(inputs({ hp = 0.3, cands = { cand({ hitting = true }) } })).level == "hitback")

check("tower at here is the veto's reason: none tower; the walk's `unknown` is a kill candidate's",
	none(decide(inputs({ safe = here(deadly("tower")), cands = { cand({ hitting = true }) } })), "tower")
		and none(decide(inputs({ cands = { unfavoured({ thp = 0.3, catch = CATCH, walk = deadly("unknown") }) } })), "unknown"))

do
	local k = run({ level = "kill" })
	local one = decide(inputs({ cands = { cand({ thp = 0.2, catch = { ok = false, dmg = 10, first = 1, safe = 3 } }) }, run = k }))
	local second = decide(inputs({ cands = { cand({ thp = 0.2, catch = { ok = false, dmg = 10, first = 1, safe = 3 } }) },
		run = run({ level = "kill", catchFails = 1, catchFailAt = 99.5 }) }))
	local soon = decide(inputs({ cands = { cand({ thp = 0.2, catch = { ok = false, dmg = 10, first = 1, safe = 3 } }) },
		run = run({ level = "kill", catchFails = 1, catchFailAt = 99.8 }) }))
	local back = decide(inputs({ cands = { cand({ thp = 0.2, catch = CATCH }) }, run = run({ level = "kill", catchFails = 1, catchFailAt = 99.5 }) }))
	check("a running kill keeps on one failed catch read and ends cannot_catch on the second 0.5 s later",
		one.level == "kill" and one.ended == nil and one.catchFails == 1 and one.catchFailAt == 100
			and none(second, "cannot_catch") and second.ended == "cannot_catch"
			and soon.level == "kill" and soon.catchFails == 1
			and back.level == "kill" and back.catchFails == 0)
end

do
	local hb = run({ level = "hitback" })
	local a = decide(inputs({ denyDue = true, cands = { cand({ hitting = true }) }, run = hb }))
	local plain = inputs({ denyDue = true, cands = { cand() } })
	check("a due deny ends a running hit back (none deny) but Holds stays hitback; on a plain hit Holds is empty",
		none(a, "deny") and T.HoldsOf(inputs({ denyDue = true, cands = { cand({ hitting = true }) }, run = hb })) == "hitback"
			and T.HoldsOf(plain) == nil and none(decide(plain), "deny")
			and decide(inputs({ cands = { cand({ hitting = true }) }, run = hb })).level == "hitback")
end

-- `hitting` is the 1 s read, `swung` the hitter's own attack interval: an enemy between two swings has the second and not the first.
do
	local hb = run({ level = "hitback" })
	local between = function(o) return cand(merge({ hitting = false, swung = true }, o)) end
	local paidOnly = between({ ko = 0.2, kt = 0.3, paid = true })
	local stays = decide(inputs({ cands = { paidOnly }, run = hb }))
	local favoured = decide(inputs({ cands = { between() }, run = hb }))
	local stopped = decide(inputs({ cands = { cand({ ko = 0.2, kt = 0.3, paid = false, swung = false }) }, run = hb }))
	check("between the hitter's swings a running hit back stays hitback (paid or favoured, not dropped to hit); past its interval it ends unfavoured",
		stays.level == "hitback" and stays.ended == nil and favoured.level == "hitback" and favoured.ended == nil
			and none(stopped, "unfavoured") and stopped.ended == "unfavoured", stays.level .. "/" .. favoured.level)
	check("the start bar stays 1 s: no fresh hit back and no retreat hold on a hero between swings; a running hit back holds retreat",
		decide(inputs({ cands = { between() } })).level == "hit"
			and none(decide(inputs({ cands = { paidOnly } })), "unfavoured")
			and T.HoldsOf(inputs({ cands = { paidOnly } })) == nil
			and T.HoldsOf(inputs({ cands = { paidOnly }, run = hb })) == "hitback")
	check("a running hit on a hero between swings is no hit back: the stay bar is the hit back's own",
		decide(inputs({ cands = { between() }, run = run({ level = "hit" }) })).level == "hit")
end

do
	local function at(tw, mk)
		return mk(tw)
	end
	local hit = function(tw) return decide(inputs({ cands = { cand({ tw = tw }) } })) end
	local back = function(tw) return decide(inputs({ cands = { cand({ tw = tw, hitting = true }) } })) end
	local kill = function(tw) return decide(inputs({ cands = { cand({ tw = tw, thp = 0.2, catch = CATCH }) } })) end
	local pair = { tgt = 7, ko = 0.5, kt = 0.2, dec = "join" }
	local join = function(tw) return decide(inputs({ pair = pair, cands = { cand({ tw = tw, ko = 0.2, kt = 0.3 }) } })) end
	local shot = decide(inputs({ towerOnMe = true, cands = { cand({ thp = 0.2, catch = CATCH }) } }))
	check("our attack point in an enemy tower's reach: none tower at every level; outside it: the level",
		none(at(true, hit), "tower") and none(at(true, back), "tower") and none(at(true, kill), "tower") and none(at(true, join), "tower")
			and none(shot, "tower")
			and at(false, hit).level == "hit" and at(false, back).level == "hitback" and at(false, kill).level == "kill"
			and at(false, join).level == "join")
end

check("not free with ko 0.2 against kt 0.3: none unfavoured; the target swinging at a creep: hit",
	none(decide(inputs({ cands = { unfavoured() } })), "unfavoured")
		and decide(inputs({ cands = { unfavoured({ free = true }) } })).level == "hit")

check("range 600 against 150 is free, 300 against 250 is not (a hit then needs the favour)",
	T.Free(false, 600, 150) and not T.Free(false, 300, 250) and T.Free(true, 300, 600)
		and decide(inputs({ cands = { unfavoured({ free = T.Free(false, 600, 150) }) } })).level == "hit"
		and none(decide(inputs({ cands = { unfavoured({ free = T.Free(false, 300, 250) }) } })), "unfavoured"))

do
	local pair = { tgt = 7, ko = 0.5, kt = 0.2, dec = "join" }
	local k = function(w) return decide(inputs({ wave = w, cands = { cand({ thp = 0.2, catch = CATCH }) } })) end
	check("wave 4: none wave for a hit, a kill and a pair join go on; wave 3: hit; wave 6: none wave for a kill",
		none(decide(inputs({ wave = 4 })), "wave") and decide(inputs({ wave = 3 })).level == "hit"
			and k(4).level == "kill" and k(5).level == "kill" and none(k(6), "wave")
			and decide(inputs({ wave = 4, pair = pair, cands = { cand({ ko = 0.2, kt = 0.3 }) } })).level == "join")
end

do
	local function kill(walk, c) return decide(inputs({ cands = { c(merge({ thp = 0.2, catch = CATCH, walk = walk }, {})) } })) end
	check("kill candidate, catch ok: a deadly walk (unknown) refuses (none unknown, and a favoured hero still gets the hit); a costly or safe walk: kill",
		none(kill(deadly("unknown"), unfavoured), "unknown")
			and kill(deadly("unknown"), cand).level == "hit"
			and kill(COSTLY, unfavoured).level == "kill" and kill(SAFE, unfavoured).level == "kill")
	check("kill candidate, safe here but the walk deadly (kill): none kill, and the walk's answer replaces the one here (deadly here, safe walk: kill)",
		none(kill(deadly("kill"), unfavoured), "kill")
			and decide(inputs({ safe = here(deadly("kill")), cands = { unfavoured({ thp = 0.2, catch = CATCH, walk = SAFE }) } })).level == "kill")
end

check("creeps on us 2 (a tower counts 2): none creeps; 1: hit",
	none(decide(inputs({ creepsOnMe = 2 })), "creeps") and decide(inputs({ creepsOnMe = 1 })).level == "hit"
		and decide(inputs({ creepsOnMe = 2, cands = { cand({ thp = 0.2, catch = CATCH }) } })).level == "kill")

do
	check("Arrives: gap 300 at speed 300 is reached in 1.5 s and not in 0.5 s; a target fleeing at 250 is not caught; in range always counts",
		T.Arrives(300, 300, 0, 1.5) and not T.Arrives(300, 300, 0, 0.5) and not T.Arrives(300, 300, 250, 1.5) and T.Arrives(-20, 100, 400, 1.5))
	-- A hit pays for 0.5 s of walking (150 units at speed 300), and the target's approach is not credited; only its retreat counts.
	check("a hit and a hit back are refused beyond 0.5 s of walking even with the target coming towards us; opened inside it; a retreat counts against us",
		none(decide(inputs({ cands = { cand({ gap = 200, away = -71 }) } })), "no_reach")
			and none(decide(inputs({ cands = { cand({ gap = 200, away = -71, hitting = true }) } })), "no_reach")
			and decide(inputs({ cands = { cand({ gap = 140, away = -71 }) } })).level == "hit"
			and decide(inputs({ cands = { cand({ gap = 140, away = -71, hitting = true }) } })).level == "hitback"
			and none(decide(inputs({ cands = { cand({ gap = 140, away = 250 }) } })), "no_reach"))
	-- A running one is judged on 1 s (walkHit + slackWalk): 300 units at speed 300; a step out of the creeps is our own move.
	local function hitAt(gap, r) return decide(inputs({ cands = { cand({ gap = gap }) }, run = run(r) })) end
	check("a running hit is kept at the slack horizon and ended `no_reach` beyond it, but not while it steps out of the creeps",
		hitAt(250).level == "hit" and hitAt(250).ended == nil and none(hitAt(350), "no_reach") and hitAt(350).ended == "no_reach"
			and hitAt(350, { stepFor = 0.5 }).level == "hit" and hitAt(350, { stepFor = 0.5 }).ended == nil)
end

do
	local function hit(o) return decide(inputs({ cands = { cand() }, run = run(o) })) end
	check("running hit: landed with soFar 0.06 is losing; unlanded 0.1 keeps, 0.16 is losing",
		none(hit({ landed = true, soFar = 0.06 }), "losing") and hit({ landed = true, soFar = 0.06 }).ended == "losing"
			and hit({ landed = true, soFar = 0.04 }).level == "hit"
			and hit({ landed = false, soFar = 0.1 }).level == "hit" and hit({ landed = false, soFar = 0.1 }).ended == nil
			and none(hit({ landed = false, soFar = 0.16 }), "losing"))
end

do
	local pair8 = { tgt = 8, ko = 0.5, kt = 0.2, dec = "join" }
	local other = decide(inputs({ pair = pair8, cands = { cand(), cand({ pid = 8, d = 500, ko = 0.2, kt = 0.3 }) }, run = run() }))
	local same = decide(inputs({ pair = { tgt = 7, ko = 0.5, kt = 0.2, dec = "join" }, cands = { cand({ thp = 0.35, catch = CATCH }) }, run = run() }))
	check("running hit and the pair joins another hero: higher, join on it; the pair on the same target at 0.35 with catch: kill (pair)",
		other.ended == "higher" and other.level == "join" and other.target == 8 and other.source == "pair"
			and same.level == "kill" and same.source == "pair" and same.target == 7 and same.ended == nil)
end

check("a running hit ends on a deadly answer here (none kill, the reason named) and keeps on a costly one",
	none(decide(inputs({ safe = here(deadly("kill")), run = run() })), "kill") and decide(inputs({ safe = here(deadly("kill")), run = run() })).level == "none"
		and decide(inputs({ safe = here(COSTLY), run = run() })).level == "hit")

check("a support-position hit by a hero at 0.8, favoured: hit back; a paid hitter is answered unfavoured, an unpaid one not",
	decide(inputs({ hp = 0.8, cands = { cand({ hitting = true }) } })).level == "hitback"
		and decide(inputs({ cands = { unfavoured({ hitting = true, paid = true }) } })).level == "hitback"
		and none(decide(inputs({ cands = { unfavoured({ hitting = true }) } })), "unfavoured")
		and T.HoldsOf(inputs({ cands = { unfavoured({ hitting = true, paid = true }) } })) == "hitback"
		and T.HoldsOf(inputs({ cands = { unfavoured({ hitting = true }) } })) == nil)

check("a hero we lost an exchange with: no hit and no hit back (none lost), no hit-back hold (a second, not-lost hitter still holds), a kill on it goes on; not lost: hit",
	none(decide(inputs({ cands = { cand({ lost = true }) } })), "lost")
		and none(decide(inputs({ cands = { cand({ lost = true, hitting = true }) } })), "lost")
		and T.HoldsOf(inputs({ cands = { cand({ lost = true, hitting = true }) } })) == nil
		and T.HoldsOf(inputs({ cands = { cand({ lost = true, hitting = true }), cand({ pid = 8, hitting = true }) } })) == "hitback"
		and decide(inputs({ cands = { cand({ lost = true, thp = 0.2, catch = CATCH }) } })).level == "kill"
		and decide(inputs({ cands = { cand({ lost = false }) } })).level == "hit")

-- The order across candidates (section 3).
do
	local low = cand({ pid = 4, thp = 0.3, thpAbs = 180, d = 800, gap = 600, catch = CATCH })
	local lower = cand({ pid = 5, thp = 0.2, thpAbs = 120, d = 900, gap = 700, catch = CATCH })
	local near = cand({ pid = 6, hitting = true, d = 200, gap = 0 })
	local far = cand({ pid = 8, hitting = true, d = 500, gap = 100 })
	local free = cand({ pid = 9, free = true, gap = 90 })
	local plain = cand({ pid = 10, gap = 20 })
	check("a kill outranks a hit back and a hit; two kills: the lowest HP; two hit backs: the nearest hitter",
		decide(inputs({ cands = { near, low } })).target == 4 and decide(inputs({ cands = { near, low, lower } })).target == 5
			and decide(inputs({ cands = { far, near } })).target == 6 and decide(inputs({ cands = { plain, far } })).level == "hitback")
	check("two hits: a free one first, then the smallest gap",
		decide(inputs({ cands = { plain, free } })).target == 9 and decide(inputs({ cands = { cand({ pid = 11, gap = 50 }), plain } })).target == 10)
	local play = { id = 3, kind = "lane_fight", tgt = 11 }
	local a = decide(inputs({ play = play, cands = { low, cand({ pid = 11, d = 600, gap = 400 }) } }))
	local zero = decide(inputs({ play = { id = 3, kind = "lane_fight", tgt = 11, zero = "hp" }, cands = { low, cand({ pid = 11, d = 600, gap = 400 }) } }))
	local far = decide(inputs({ play = play, cands = { cand({ pid = 11, d = 1500, gap = 1300 }) } }))
	check("a play's target is joined before a kill unless its zero holds; past reach plus 600 it is no join",
		a.level == "join" and a.source == "play" and a.target == 11 and zero.level == "kill" and zero.target == 4
			and far.level ~= "join")
end

do
	local pair = { tgt = 7, ko = 0.5, kt = 0.2, dec = "outnumbered" }
	check("the pair join reads ko against kt, not its outnumbered label; past 1,200 or with kt over ko it is no join",
		decide(inputs({ pair = pair, cands = { unfavoured({ d = 1100 }) } })).level == "join"
			and none(decide(inputs({ pair = pair, cands = { unfavoured({ d = 1300, gap = 1000 }) } })), "no_reach")
			and none(decide(inputs({ pair = { tgt = 7, ko = 0.2, kt = 0.5, dec = "losing" }, cands = { unfavoured() } })), "unfavoured")
			and T.HoldsOf(inputs({ pair = pair, cands = { unfavoured({ d = 1100 }) } })) == "join")
end

-- Ends of a running exchange.
do
	local gone = decide(inputs({ cands = {}, run = run({ level = "hit" }) }))
	local dead = decide(inputs({ cands = {}, run = run({ alive = false }) }))
	local untaken = decide(inputs({ run = run({ started = false, offered = 1.2 }) }))
	local taken = decide(inputs({ run = run({ started = false, offered = 0.8 }) }))
	local step = decide(inputs({ run = run({ stepFor = 2.2 }) }))
	check("a running hit ends target_lost unseen, target_dead, not_taken after 1 s, no_clear after a 2 s step out",
		none(gone, "target_lost") and none(dead, "target_dead") and none(untaken, "not_taken") and taken.level == "hit"
			and none(step, "no_clear"))
end

do
	local at = { x = 100, y = 200 }
	local function chase(o)
		return decide(inputs({ cands = {}, run = run({ level = "kill", chaseAt = at, catch = CATCH, unseen = merge({ at = false, tower = false, threat = false }, o) }) }))
	end
	local keep = chase({})
	-- The executor writes each frame's catchFails back into the run; replay that over frames 0.6 s apart (catchGap is 0.5 s).
	local function frames(catchOk, n)
		local r = run({ level = "kill", chaseAt = at, catch = { ok = catchOk, dmg = 0, first = math.huge, safe = 3 }, unseen = { at = false, tower = false, threat = false } })
		local a
		for f = 0, n - 1 do
			a = decide(inputs({ now = 100 + f * 0.6, cands = {}, run = r }))
			if a.ended ~= nil then return a, f end
			r.catchFails, r.catchFailAt = a.catchFails, a.catchFailAt
		end
		return a, n
	end
	local failing, endedAt = frames(false, 6)
	local holding = frames(true, 6)
	check("an unseen chase on a failing catch read ends cannot_catch at the second failure, frames 0.6 s apart; an ok read keeps chasing",
		failing.ended == "cannot_catch" and endedAt == 1 and holding.ended == nil and holding.level == "kill" and holding.catchFails == 0)
	check("an unseen kill walks to the predicted place and ends spot_clear, utower or threat on the reads; a failing catch read ends it too",
		keep.level == "kill" and keep.how.verb == "move" and keep.how.at.x == 100
			and none(chase({ at = true }), "spot_clear") and none(chase({ tower = true }), "utower") and none(chase({ threat = true }), "threat")
			and none(decide(inputs({ cands = {}, run = run({ level = "kill", chaseAt = at, catchFails = 1, catchFailAt = 99,
				catch = { ok = false, dmg = 0, first = math.huge, safe = 3 }, unseen = { at = false, tower = false, threat = false } }) })), "cannot_catch"))
end

do
	local pair = { tgt = 7, ko = 0.5, kt = 0.2, dec = "join" }
	local j = run({ level = "join", source = "pair" })
	local ended = decide(inputs({ cands = { unfavoured() }, run = j }))
	local kept = decide(inputs({ pair = pair, cands = { unfavoured() }, run = j }))
	check("a running pair join ends pair_end when the pair stops answering and keeps while it does",
		kept.level == "join" and kept.ended == nil and ended.ended == "pair_end" and ended.level == "none")
end

do
	local a = decide(inputs({ cands = { cand({ thp = 0.2, catch = CATCH }) } }))
	local hit = decide(inputs({ cands = { cand() } }))
	local join = decide(inputs({ pair = { tgt = 7, ko = 0.5, kt = 0.2, dec = "join" }, cands = { cand() } }))
	check("the how: a hit is aggro-free, a kill and a join commit",
		a.how.verb == "attack" and a.how.aggro == "commit" and hit.how.aggro == "free" and join.how.aggro == "commit"
			and decide(inputs({ cands = {} })).how == nil and none(decide(inputs({ cands = {} })), "no_target"))
end

-- The pure reads.
do
	local close = { d = 100, reach = 174, close = 50, dps = 40, spells = {} }
	local far = { d = 1000, reach = 174, close = 100, dps = 40, spells = { { range = 600, cp = 0.3, dmg = 200 } } }
	check("CatchRead: dps from the moment of arrival plus a ready spell reached in time, against the target's HP",
		T.CatchRead({ close }, 200, 5).ok and not T.CatchRead({ close }, 201, 5).ok
			and math.abs(T.CatchRead({ far }, 1, 10).dmg - (40 * (10 - 8.26) + 200)) < 1
			and not T.CatchRead({ { d = 1000, reach = 174, close = -10, dps = 40, spells = {} } }, 1, 10).ok)
	check("Deficit: HP lost beyond the target's over our max HP",
		math.abs(T.Deficit(500, 440, 400, 380, 600) - 40 / 600) < 1e-9 and T.Deficit(500, 500, 400, 300, 600) < 0)
end

-- The cut line: the cadence (an answer change at once, a running exchange every 0.5 s, else every 2 s) and the fields the driver replays.
do
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true, Cut = true } })
	local C = require("bots/FunLib/humaniser/states/trade")
	local lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	local bot = MakeUnit({ pid = 1, team = 2 })
	local i = inputs({ cands = { cand({ thp = 0.2, catch = CATCH, walk = SAFE, hunters = {} }) }, denyDue = true })
	local a = decide(i)
	C.Cut(bot, i, a)
	local first = #lines
	C.Cut(bot, i, a)
	local steady = #lines
	i.now = 102.5
	C.Cut(bot, i, a)
	local idle = #lines
	local hit = inputs({ cands = { cand() }, now = 102.6 })
	C.Cut(bot, hit, decide(hit))
	local changed = #lines
	check("the cut: a line at the first decision, none for the same answer within 2 s, one after it, and one when the answer changes",
		first == 1 and steady == 1 and idle == 2 and changed == 3)
	local line = lines[1]
	check("the line names the kind, the answer and a candidate record the driver reads",
		line:find("kind=trade", 1, true) ~= nil and line:find("lv=kill", 1, true) ~= nil and line:find("why=kill", 1, true) ~= nil
			and line:find("cd=", 1, true) ~= nil)
	check("and Safe.At's answers here (svh, svb) and the candidate's walk answer ride on it for the replay",
		line:find("svh=safe,-,safe", 1, true) ~= nil and line:find("svb=safe,-,safe", 1, true) ~= nil and line:find(",safe,-,safe,", 1, true) ~= nil)
	local running = inputs({ cands = { cand() }, run = run(), now = 110 })
	local before = #lines
	for _, now in ipairs({ 110, 110.2, 110.6 }) do
		running.now = now
		C.Cut(bot, running, decide(running))
	end
	check("a running exchange logs every 0.5 s, not more often", #lines == before + 2)
end

-- Slice trade-count: start and running ask the same function. Over a grid of inputs, whatever level opens, fed back as that level running
-- (nothing changed), is kept and not ended; and every end reason the decision can give is mapped to a start gate or marked later only.
do
	local opened, ended = 0, {}
	for _, thp in ipairs({ 0.2, 0.35, 0.7 }) do
		for _, hit in ipairs({ false, true }) do
			for _, ko in ipairs({ { 0.3, 0.2 }, { 0.2, 0.3 } }) do
				for _, gap in ipairs({ 0, 100, 250 }) do
					for _, wave in ipairs({ 0, 3 }) do
						for _, paid in ipairs({ false, true }) do
							for _, pairOn in ipairs({ false, true }) do
								local c = cand({ thp = thp, thpAbs = thp * 600, hitting = hit, ko = ko[1], kt = ko[2], gap = gap, paid = paid, catch = CATCH })
								local i = inputs({ wave = wave, cands = { c }, pair = pairOn and { tgt = 7, ko = 0.5, kt = 0.2, dec = "join" } or nil })
								local a = decide(i)
								if a.level ~= "none" then
									opened = opened + 1
									i.run = run({ level = a.level, target = a.target, source = a.source })
									local b = decide(i)
									if b.ended ~= nil then ended[#ended + 1] = a.level .. ":" .. tostring(b.ended) end
								end
							end
						end
					end
				end
			end
		end
	end
	check("property: " .. opened .. " inputs that open a level, fed back as that level running, none ends it" .. (#ended > 0 and " (" .. table.concat(ended, ",", 1, math.min(#ended, 5)) .. ")" or ""),
		opened > 20 and #ended == 0)
	local reasons = { "tower", "kill", "unknown", "lost", "catch", "wave", "no_reach", "unfavoured", "deny", "creeps", "no_clear", "target_dead", "target_lost",
		"not_taken", "backstop", "losing", "cannot_catch", "spot_clear", "utower", "threat", "pair_end", "play_end", "higher", "switch", "lane_end", "dead", "play" }
	local all = true
	for _, r in ipairs(reasons) do
		local k = T.ENDS[r]
		if k ~= "gate" and k ~= "think" and k ~= "later" then all = false end
	end
	local i = inputs({ cands = { unfavoured({ hitting = true, paid = true }) } })
	local opens = T.OpenFails(i, i.cands[1])
	check("every end reason maps to a start gate or is marked later only; a hit back opened on `paid` already fails the hit's favoured gate, a later-only end has no flag",
		all and T.TrueAtOpen("unfavoured", opens, "order") == 1 and T.TrueAtOpen("deny", opens, "order") == 0
			and T.TrueAtOpen("no_clear", opens, "step") == 1 and T.TrueAtOpen("no_clear", opens, "order") == 0 and T.TrueAtOpen("losing", opens, "order") == nil
			and T.TrueAtOpen("mode_attack", opens, nil) == nil)
end

-- Slice trade-swing (step 4.3): `swing` on the inputs turns the rule on (absent: every case below is a plain hit). A swing draws the enemy
-- lane creeps inside the aggro radius of the swing place (`near`) unless our own order's cooldown covers it; their damage (`kc`) joins the target's.
do
	local sw = function(o) return merge({ cover = 0, atk = 0.4 }, o) end
	local near = function(o) return cand(merge({ near = 2, kc = 0.2 }, o)) end
	local off = decide(inputs({ cands = { near() } }))
	local drawn = decide(inputs({ swing = sw(), cands = { near() } }))
	local cheap = decide(inputs({ swing = sw(), cands = { near({ kc = 0.05 }) } }))
	local covered = decide(inputs({ swing = sw({ cover = 2 }), cands = { near() } }))
	local clear = decide(inputs({ swing = sw(), cands = { cand({ near = 0, kc = 0 }) } }))
	check("a hit that pays only with no creeps (0.3 against 0.2, the creeps add 0.2) does not open: none aggro; with the creeps at 0.05 it opens; under our order's cooldown it opens; a clear place opens; without the rule it opens",
		none(drawn, "aggro") and cheap.level == "hit" and covered.level == "hit" and clear.level == "hit" and off.level == "hit", drawn.level .. "/" .. tostring(drawn.reason))
	local freeDrawn = decide(inputs({ swing = sw(), cands = { near({ free = true, ko = 0.1, kt = 0 }) } }))
	local freeClear = decide(inputs({ swing = sw(), cands = { cand({ free = true, ko = 0.1, kt = 0, near = 0, kc = 0 }) } }))
	local freePays = decide(inputs({ swing = sw(), cands = { near({ free = true, ko = 0.3, kt = 0 }) } }))
	check("a free hit is free only from a clear place: among creeps it must beat their damage (0.1 against 0.2 no, 0.3 yes)",
		none(freeDrawn, "aggro") and freeClear.level == "hit" and freePays.level == "hit")
	check("a hit that does not pay even with no creeps is still `unfavoured`, not `aggro`",
		none(decide(inputs({ swing = sw(), cands = { near({ ko = 0.2, kt = 0.3 }) } })), "unfavoured"))
	local paid = decide(inputs({ swing = sw(), cands = { near({ hitting = true, swung = true, ko = 0.2, kt = 0.3, paid = true }) } }))
	check("a hit back on a hero in our creeps' aggro stays open among their creeps (paid)", paid.level == "hitback")
	-- The walk is gap over our speed (100 / 300 s), the swing lands `atk` after it: 0.73 s from now.
	local soon = decide(inputs({ swing = sw({ due = 0.5 }), cands = { cand({ near = 0 }) } }))
	local later = decide(inputs({ swing = sw({ due = 1.5 }), cands = { cand({ near = 0 }) } }))
	local running = decide(inputs({ swing = sw({ due = 0.5 }), cands = { cand({ near = 0 }) }, run = run() }))
	check("a last hit due before the swing lands (0.5 s against 0.73 s) refuses a fresh hit: none due; due after it (1.5 s) the hit opens; a running hit is not ended by it",
		none(soon, "due") and later.level == "hit" and running.level == "hit" and running.ended == nil, soon.level .. "/" .. tostring(soon.reason))
	local stepping = decide(inputs({ swing = sw(), cands = { cand({ near = 0, gap = 400 }) }, run = run({ stepFor = 0.5 }) }))
	check("no step out under the rule: a running hit out of reach ends no_reach whatever a step-out clock says", none(stepping, "no_reach"))
	-- Review: nothing new may end a hit between its open and its first swing. A creep that steps inside the radius meanwhile is no new reason;
	-- once our attack has fired the next swing is asked again.
	local crept = decide(inputs({ swing = sw(), cands = { near() }, run = run({ landed = false }) }))
	local next = decide(inputs({ swing = sw(), cands = { near() }, run = run({ landed = true }) }))
	local nextCovered = decide(inputs({ swing = sw({ cover = 0.2 }), cands = { near() }, run = run({ landed = true }) }))
	check("a running hit whose attack has not fired keeps the open's answer when a creep comes near; after it fired the next swing is refused (aggro) unless the cooldown still covers it",
		crept.level == "hit" and crept.ended == nil and none(next, "aggro") and next.ended == "aggro" and nextCovered.level == "hit")
	-- The walk and swing take 0.73 s: a cooldown with 0.3 s left does not cover a fresh hit, one with 1 s does.
	local short = decide(inputs({ swing = sw({ cover = 0.3 }), cands = { near() } }))
	local long = decide(inputs({ swing = sw({ cover = 1 }), cands = { near() } }))
	check("our order's cooldown covers a fresh hit only if it outlasts the walk and the swing (0.3 s no, 1 s yes)", none(short, "aggro") and long.level == "hit")
	check("a hero out of reach is `no_reach`, not `aggro`, whatever the creeps", none(decide(inputs({ swing = sw(), cands = { near({ gap = 400 }) } })), "no_reach"))
end

-- Ours.TradeHold (step 4.4, narrowed): an opened hit is carried to its first swing through a flip of the favoured test.
do
	local function hit(i, r) return decide(inputs(merge({ cands = { unfavoured() }, run = run(r) }, i))) end
	local offEnds = hit({})
	local held = hit({ hold = true })
	local swung = hit({ hold = true }, { landed = true })
	check("an unfired running hit whose target stopped being favoured: ends unfavoured with the rule off, kept with it on, asked again once it has fired",
		none(offEnds, "unfavoured") and offEnds.ended == "unfavoured" and held.level == "hit" and held.ended == nil
			and none(swung, "unfavoured") and swung.ended == "unfavoured")
	check("the hold opens nothing: a fresh unfavoured hit stays refused", none(decide(inputs({ hold = true, cands = { unfavoured() } })), "unfavoured"))
	check("a held hit still ends on a deadly read, a due deny, the reach and the HP lost before landing",
		none(hit({ hold = true, safe = here(deadly()) }), "kill") and none(hit({ hold = true, denyDue = true }), "deny")
			and none(hit({ hold = true, cands = { unfavoured({ gap = 350 }) } }), "no_reach") and none(hit({ hold = true }, { soFar = 0.16 }), "losing"))
	local hb = decide(inputs({ hold = true, cands = { unfavoured({ hitting = true, swung = true }) }, run = run() }))
	check("a held hit is not raised to a hit back the favoured test refuses", hb.level == "hit")
	local back = decide(inputs({ hold = true, cands = { unfavoured({ hitting = true, swung = true }) }, run = run({ level = "hitback" }) }))
	check("an unfired hit back is held the same way", back.level == "hitback" and back.ended == nil)
	local quiet = function(i) return decide(inputs(merge({ cands = { unfavoured() }, run = run({ level = "hitback" }) }, i))) end
	check("an unfired hit back whose target stopped swinging is carried as a hit (rule off: it ends unfavoured)",
		quiet({ hold = true }).level == "hit" and quiet({ hold = true }).ended == nil and quiet({}).ended == "unfavoured")
	local stuck, fired = hit({ hold = true }, { started = 3.1 }), decide(inputs({ hold = true, run = run({ started = 3.1, landed = true }) }))
	check("a held hit taken 3 s with no attack fired ends on the logged backstop; one that has fired, or with the rule off, does not",
		none(stuck, "backstop") and stuck.ended == "backstop" and fired.level == "hit" and fired.ended == nil
			and decide(inputs({ run = run({ started = 3.1 }) })).ended == nil)
	local sw = { cover = 0, atk = 0.4 }
	local among = decide(inputs({ hold = true, swing = sw, cands = { unfavoured({ near = 2, kc = 0.2 }) }, run = run() }))
	check("with the swing rule on too, the held hit stays among the creeps until it fires", among.level == "hit" and among.ended == nil)
end

-- Explore trade (Inputs.agg, `Ours.ExploreTrade`): the aggression scales the favoured test (ko x agg against kt), the kill level's target HP share
-- (0.4 x agg) and the `losing` end (0.05 x agg). Each row has its control in the same check: absent and 1 are the rules as they were.
do
	local function lvl(o, agg) o.agg = agg return decide(inputs(o)) end
	local unf = function() return { cand({ ko = 0.2, kt = 0.3 }) } end
	local fav = function() return { cand({ ko = 0.3, kt = 0.2 }) } end
	check("favoured margin: ko 0.2 against kt 0.3 hits only from agg 1.75 (0.35 over 0.3); ko 0.3 against 0.2 is refused only at agg 0.5 (0.15 under 0.2)",
		none(lvl({ cands = unf() }, nil), "unfavoured") and none(lvl({ cands = unf() }, 1), "unfavoured") and none(lvl({ cands = unf() }, 1.35), "unfavoured")
			and lvl({ cands = unf() }, 1.75).level == "hit"
			and lvl({ cands = fav() }, nil).level == "hit" and lvl({ cands = fav() }, 0.75).level == "hit"
			and none(lvl({ cands = fav() }, 0.5), "unfavoured"))
	local kill = function(thp) return { cand({ gap = 0, thp = thp, thpAbs = thp * 600, catch = CATCH, ko = 0.6, kt = 0.2 }) } end
	check("kill HP share: a target at 0.5 is a kill only from agg 1.35 (bar 0.54), a target at 0.3 stops being one at agg 0.5 (bar 0.2, a hit instead), the cap is 0.7",
		lvl({ cands = kill(0.5) }, 1).level == "hit" and lvl({ cands = kill(0.5) }, 1.35).level == "kill"
			and lvl({ cands = kill(0.3) }, nil).level == "kill" and lvl({ cands = kill(0.3) }, 0.75).level == "kill"
			and lvl({ cands = kill(0.3) }, 0.5).level == "hit"
			and lvl({ cands = kill(0.75) }, 1.75).level == "hit",
		lvl({ cands = kill(0.5) }, 1).level .. lvl({ cands = kill(0.5) }, 1.35).level .. lvl({ cands = kill(0.3) }, nil).level .. lvl({ cands = kill(0.3) }, 0.75).level .. lvl({ cands = kill(0.3) }, 0.5).level .. lvl({ cands = kill(0.75) }, 1.75).level)
	local landed = function(so) return run({ level = "hit", landed = true, soFar = so }) end
	check("losing end: 0.07 lost ends a landed hit at agg 1 and absent but not at 1.75 (bar 0.0875); 0.04 ends it only at agg 0.5 (bar 0.025)",
		lvl({ cands = fav(), run = landed(0.07) }, 1).ended == "losing" and lvl({ cands = fav(), run = landed(0.07) }, nil).ended == "losing"
			and lvl({ cands = fav(), run = landed(0.07) }, 1.75).level == "hit" and lvl({ cands = fav(), run = landed(0.07) }, 1.75).ended == nil
			and lvl({ cands = fav(), run = landed(0.04) }, 1).level == "hit" and lvl({ cands = fav(), run = landed(0.04) }, 0.5).ended == "losing")
	check("a hit back's hold follows the same margin: kt 0.3 against ko 0.2 holds retreat only at agg 1.75",
		T.HoldsOf(inputs({ cands = { cand({ hitting = true, ko = 0.2, kt = 0.3 }) } })) == nil
			and T.HoldsOf(inputs({ agg = 1.75, cands = { cand({ hitting = true, ko = 0.2, kt = 0.3 }) } })) == "hitback")
end

-- The walk a hit pays for (BARS.walkHit 0.5 s at agg 1, x agg; speed 300): a hit opens at gap 200 only from agg 1.35 (0.675 s reaches 202) and at gap 100 not at 0.5
-- (75); a running one is judged on the same walk plus its 0.5 s slack, so at gap 340 it ends no_reach at agg 1 (300) and goes on at 1.35 (352): open and end agree.
do
	local function lvl(o, agg) o.agg = agg return decide(inputs(o)) end
	local at = function(gap) return { cand({ gap = gap, ko = 0.6, kt = 0.2 }) } end
	check("walk by agg: gap 200 opens only from agg 1.35, gap 100 is refused at agg 0.5; a running hit at gap 340 ends no_reach at agg 1 and keeps at 1.35",
		none(lvl({ cands = at(200) }, nil), "no_reach") and none(lvl({ cands = at(200) }, 1), "no_reach") and lvl({ cands = at(200) }, 1.35).level == "hit"
			and lvl({ cands = at(100) }, 1).level == "hit" and none(lvl({ cands = at(100) }, 0.5), "no_reach")
			and lvl({ cands = at(340), run = run({ level = "hit" }) }, 1).ended == "no_reach"
			and lvl({ cands = at(340), run = run({ level = "hit" }) }, 1.35).level == "hit",
		lvl({ cands = at(200) }, 1).reason .. lvl({ cands = at(200) }, 1.35).level .. lvl({ cands = at(100) }, 0.5).reason .. tostring(lvl({ cands = at(340), run = run({ level = "hit" }) }, 1).ended) .. lvl({ cands = at(340), run = run({ level = "hit" }) }, 1.35).level)
end

-- The draw (explore.ts Agg): off gives nothing and draws nothing; on holds one value for a 45 s block counted from the hero's first call and redraws in the next.
do
	local Explore = require("bots/FunLib/humaniser/explore")
	local Customize = package.loaded["bots/FunLib/custom_loader"]
	local bot = { GetPlayerID = function() return 4 end, GetNearbyHeroes = function() return {} end, GetNearbyLaneCreeps = function() return {} end,
		GetHealth = function() return 500 end, GetMaxHealth = function() return 600 end, GetLevel = function() return 3 end }
	local function at(t, fraction) _G.T = t RANDOM_FRACTION = fraction return Explore.Agg(bot) end
	Customize.Ours.ExploreTrade = false
	local off = at(100, 0)
	Customize.Ours.ExploreTrade = true
	local a0 = at(100, 0)
	local held = at(144, 0.99)
	local a1 = at(145, 0.99)
	local still = at(189, 0)
	local a2 = at(190, 0)
	_G.T = 191
	local tally = Explore._test.blocks[4].tally
	Explore.Tally(bot, "none", "unfavoured", 191)
	Explore.Tally(bot, "none", "unfavoured", 191.5)
	Explore.Tally(bot, "hit", "hit", 192)
	Explore.Tally(bot, "none", "no_reach", 200)
	Explore.Order(bot)
	Explore.Order(bot)
	local sums = tally.sn == 1.5 and tally.rnf == 0.5 and tally.rnr == 1 and tally.sh == 0.5 and tally.ord == 2
	local fresh = at(235, 0) and next(Explore._test.blocks[4].tally) == nil
	check("explore trade: off draws nothing; on, the first call draws and the block holds to 44 s, redraws at 45 s and again at 90 s; the tally sums seconds by level and none's reason, counts orders, and starts empty in the next block",
		off == nil and a0 == 0.5 and held == 0.5 and a1 == 1.75 and still == 1.75 and a2 == 0.5
			and sums and fresh,
		tostring(off) .. " " .. tostring(a0) .. " " .. tostring(held) .. " " .. tostring(a1) .. " " .. tostring(still) .. " " .. tostring(a2))
	Customize.Ours.ExploreTrade = false
	RANDOM_FRACTION = nil
	Explore.ResetCache()
end

finish()
