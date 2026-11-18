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
	return merge({ pid = 7, thp = 0.7, thpAbs = 420, d = 300, gap = 100, away = 0, arrives = true, hitting = false, free = false,
		ko = 0.3, kt = 0.2, paid = false, tw = false }, o)
end
local function inputs(o)
	return merge({ now = 100, hp = 1, burst = 0.2, n = 1, missing = 0, towerOnMe = false, creepsOnMe = 0, wave = 1, denyDue = false,
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

check("Luna: n 1 and a small burst, target 0.21 with the catch ok: kill; n 2 and burst 0.6: none burst",
	decide(inputs({ burst = 0.18, cands = { cand({ thp = 0.21, thpAbs = 126, catch = CATCH }) } })).level == "kill"
		and none(decide(inputs({ n = 2, burst = 0.6, cands = { cand({ thp = 0.21, thpAbs = 126, catch = CATCH }) } })), "burst"))

check("hit at 0.6 HP against one hitter, favoured: hit back; two reach us: none hp",
	decide(inputs({ hp = 0.6, cands = { cand({ hitting = true }) } })).level == "hitback"
		and none(decide(inputs({ hp = 0.6, n = 2, burst = 0.3, cands = { cand({ hitting = true }) } })), "hp"))

check("target 0.3, our burst 1.2 at n 1: none burst; burst 0.4: kill",
	none(decide(inputs({ burst = 1.2, cands = { cand({ thp = 0.3, catch = CATCH }) } })), "burst")
		and decide(inputs({ burst = 0.4, cands = { cand({ thp = 0.3, catch = CATCH }) } })).level == "kill")

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
		none(a, "deny") and T.Holds(inputs({ denyDue = true, cands = { cand({ hitting = true }) }, run = hb })) == "hitback"
			and T.Holds(plain) == nil and none(decide(plain), "deny")
			and decide(inputs({ cands = { cand({ hitting = true }) }, run = hb })).level == "hitback")
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
	check("kill candidate, catch ok: walk.missing 0.6 refuses (none missing, and a favoured hero still gets the hit); 0.3: kill",
		none(kill({ burst = 0.1, n = 1, missing = 0.6 }, unfavoured), "missing")
			and kill({ burst = 0.1, n = 1, missing = 0.6 }, cand).level == "hit"
			and kill({ burst = 0.1, n = 1, missing = 0.3 }, unfavoured).level == "kill")
	check("kill candidate, n 1 here but walk.n 2 and walk.burst 0.6: none burst; walk.burst 0.4: kill",
		none(kill({ burst = 0.6, n = 2, missing = 0 }, unfavoured), "burst")
			and kill({ burst = 0.4, n = 2, missing = 0 }, unfavoured).level == "kill")
end

check("creeps on us 2 (a tower counts 2): none creeps; 1: hit",
	none(decide(inputs({ creepsOnMe = 2 })), "creeps") and decide(inputs({ creepsOnMe = 1 })).level == "hit"
		and decide(inputs({ creepsOnMe = 2, cands = { cand({ thp = 0.2, catch = CATCH }) } })).level == "kill")

do
	local fleeing = T.Arrives(300, 300, 250, 1.5)
	local still = T.Arrives(300, 300, 0, 1.5)
	check("gap 300, our speed 300, the target fleeing at 250: none no_reach; not fleeing: hit; already in range counts",
		not fleeing and still and T.Arrives(-20, 100, 400, 1.5)
			and none(decide(inputs({ cands = { cand({ gap = 300, away = 250, arrives = fleeing }) } })), "no_reach")
			and decide(inputs({ cands = { cand({ gap = 300, arrives = still }) } })).level == "hit")
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

check("running hit at 0.47 HP, n 1: keeps (slack 0.05); a fresh hit at 0.47 is none hp",
	decide(inputs({ hp = 0.47, run = run() })).level == "hit" and none(decide(inputs({ hp = 0.47 })), "hp")
		and none(decide(inputs({ hp = 0.44, run = run() })), "hp"))

check("a support-position hit by a hero at 0.8, favoured: hit back; a paid hitter is answered unfavoured, an unpaid one not",
	decide(inputs({ hp = 0.8, cands = { cand({ hitting = true }) } })).level == "hitback"
		and decide(inputs({ cands = { unfavoured({ hitting = true, paid = true }) } })).level == "hitback"
		and none(decide(inputs({ cands = { unfavoured({ hitting = true }) } })), "unfavoured")
		and T.Holds(inputs({ cands = { unfavoured({ hitting = true, paid = true }) } })) == "hitback"
		and T.Holds(inputs({ cands = { unfavoured({ hitting = true }) } })) == nil)

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
			and T.Holds(inputs({ pair = pair, cands = { unfavoured({ d = 1100 }) } })) == "join")
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

finish()
