-- Slice 5a: the laner's choice among the engine's laneTargets facts (moved from the engine's nextLastHit).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Pick = require("bots/FunLib/humaniser/states/lane_pick")

local function target(kind, eta, ranged, walk, dies)
	return { creep = {}, kind = kind, eta = eta, due = eta, walk = walk or 0, dies = dies or math.huge, ranged = ranged == true }
end

-- The ranged creep wins over a melee creep due a little sooner (gold and XP).
do
	local m, r = target("lasthit", 0.2), target("lasthit", 0.4, true)
	check("pick: ranged preferred over a melee due 0.2 s sooner", Pick.Choose({ m, r }) == r)
end

-- ...but not over a melee creep due now when the ranged one is a second away: the bias is bounded.
do
	local m, r = target("lasthit", 0), target("lasthit", 1.0, true)
	check("pick: melee due now beats a ranged creep due in 1 s", Pick.Choose({ r, m }) == m)
end

-- Strict priority (user rule 01/11/2026): a reachable last hit beats a deny however much sooner the deny is due; a deny is
-- taken only when no last hit is offered.
do
	local d, e = target("deny", 0), target("lasthit", 0.2)
	check("pick: last hit beats a deny due slightly sooner", Pick.Choose({ d, e }) == e)
	local late = target("lasthit", 1.0)
	check("pick: last hit 1 s away still beats a deny due now", Pick.Choose({ late, d }) == late)
	check("pick: no last hit, the deny is chosen", Pick.Choose({ d }) == d)
	local rd = target("deny", 0, true)
	check("pick: a ranged deny never beats a melee last hit", Pick.Choose({ rd, late }) == late)
	local far = target("lasthit", 0, false, 2, 1)
	check("pick: an unreachable last hit does not block a deny", Pick.Choose({ far, d }) == d)
end

-- Slice l1-support-deny (user rule 02/11/2026): a support's pick is denies only, earliest eta with the ranged bias; last hits
-- are left to OHA's own step, and the reach rule still applies.
do
	local e, d = target("lasthit", 0), target("deny", 0.5)
	check("deny pick: a deny is chosen over a last hit due sooner", Pick.ChooseDeny({ e, d }) == d)
	check("deny pick: last hits only, nothing chosen", Pick.ChooseDeny({ e }) == nil)
	local d2, rd = target("deny", 0.2), target("deny", 0.5, true)
	check("deny pick: the ranged deny beats a melee one due 0.3 s sooner", Pick.ChooseDeny({ d2, rd }) == rd)
	local far = target("deny", 0, false, 1.2, 0.9)
	check("deny pick: a deny dead before the support arrives is skipped", Pick.ChooseDeny({ far, d }) == d)
end

-- Slice 5 (probe s5p3): a creep due now but 1.2 s of walking away, which the others kill in 0.9 s, is skipped even
-- though the pick would otherwise take it; one the bot can reach and swing at before it dies is kept.
do
	local far = target("lasthit", 0, true, 1.2, 0.9)
	local near = target("lasthit", 0.6, false, 0, 2)
	check("pick: a creep dead before the bot can reach it is skipped", Pick.Choose({ far, near }) == near)
	check("pick: nothing reachable, nothing picked", Pick.Choose({ far }) == nil)
	local reach = target("lasthit", 0.5, true, 0.5, 1.5)
	check("pick: a creep reachable with time to swing is kept", Pick.Choose({ reach, near }) == reach)
	-- In range already (walk 0): never skipped on this rule, even when it dies soon (lastHit judges the swing).
	local here = target("lasthit", 0, false, 0, 0.2)
	check("pick: a creep in range is kept however soon it dies", Pick.Choose({ here }) == here)
end

-- Missed-bar telemetry (s5b): the snapshot's lf field counts the offers the reach rule skipped, from the same rule Choose uses.
do
	local far = target("lasthit", 0, true, 1.2, 0.9)
	local near = target("lasthit", 0.6, false, 0, 2)
	check("lf: nothing before any scan", Pick.Describe(7, 10) == nil)
	Pick.NoteScan(7, 9.5, 340.6)
	Pick.NotePick(7, 8, { far, near }, Pick.Choose({ far, near }))
	Pick.NotePhase(7, "hold")
	check("lf: phase, ages, distance and offers", Pick.Describe(7, 10) == "ph=hold sc=0.5 aw=340 pk=2.0 n=2 sk=1 ch=1")
	Pick.NotePick(7, 10, { far }, Pick.Choose({ far }))
	check("lf: all offers skipped, none chosen", Pick.Describe(7, 10) == "ph=hold sc=0.5 aw=340 pk=0.0 n=1 sk=1 ch=0")
end

-- Slice lane-activity: what was on offer. A deny picked with a last hit arriving during its wait is what ev=lh's ow reports.
do
	local bot = { GetPlayerID = function() return 8 end }
	local ol, od = Pick.Options(bot)
	check("options: nothing before the bundle hands over its offers", ol == nil and od == nil)
	local far = target("lasthit", 0, true, 1.2, 0.9)
	local lh, dn = target("lasthit", 0.2), target("deny", 0)
	local now = { far, lh, dn }
	Pick.SetOffers(function() return now end)
	ol, od = Pick.Options(bot)
	check("options: counts obey the reach rule", ol == 1 and od == 1, tostring(ol) .. "/" .. tostring(od))

	Pick.NotePick(8, 1, { dn }, dn)
	Pick.NotePhase(8, "deny")
	now = { dn }
	Pick.NoteWait(bot)
	local a, b, c = Pick.AttemptOffers(8)
	check("offers: deny picked alone, no last hit seen yet", a == 0 and b == 1 and c == 0)
	now = { dn, lh, target("lasthit", 0.5), far }
	Pick.NoteWait(bot)
	now = { dn, lh }
	Pick.NoteWait(bot)
	a, b, c = Pick.AttemptOffers(8)
	check("offers: the most other reachable last hits seen during the wait", a == 0 and b == 1 and c == 2, tostring(c))

	Pick.NotePhase(8, "hold")
	Pick.NotePick(8, 2, { lh, dn }, lh)
	Pick.NotePhase(8, "lasthit")
	now = { lh, dn }
	Pick.NoteWait(bot)
	a, b, c = Pick.AttemptOffers(8)
	check("offers: the attempt's own creep is not another offer; a new pick resets", a == 1 and b == 1 and c == 0, tostring(c))

	Pick.NotePhase(8, "hold")
	now = { target("lasthit", 0), lh }
	Pick.NoteWait(bot)
	a, b, c = Pick.AttemptOffers(8)
	check("offers: not counted while holding", c == 0, tostring(c))

	-- Review H1: a retarget picks before the old attempt reports. The old attempt keeps its own offers; the next attempt gets the new pick's.
	local lh2 = target("lasthit", 0.3)
	Pick.NotePhase(8, "hold")
	Pick.NotePick(8, 3, { dn }, dn)
	Pick.NotePhase(8, "deny")
	now = { dn, lh2 }
	Pick.NoteWait(bot)
	Pick.NotePick(8, 4, { lh2 }, lh2) -- retarget: the deny creep is gone, the last hit is chosen
	a, b, c = Pick.AttemptOffers(8)
	check("retarget: the old deny reports its own offers", a == 0 and b == 1 and c == 1, tostring(a) .. "/" .. tostring(b) .. "/" .. tostring(c))
	Pick.NotePhase(8, "lasthit")
	now = { lh2 }
	Pick.NoteWait(bot)
	a, b, c = Pick.AttemptOffers(8)
	check("retarget: the next attempt reports the held pick", a == 1 and b == 0 and c == 0, tostring(a) .. "/" .. tostring(b) .. "/" .. tostring(c))
	-- A retarget that picks nothing leaves the attempt as it was.
	Pick.NotePick(8, 5, {}, nil)
	a, b, c = Pick.AttemptOffers(8)
	check("retarget: no new pick, offers unchanged", a == 1 and b == 0 and c == 0)
end

-- Leaving a waited-on creep (slice lane-last-hits): only for one killable now, unless the current is due within SWITCH_GAP.
do
	local cur = target("lasthit", 0.9)
	local soon = target("lasthit", 0.5)
	check("switch: another creep not yet killable does not move the wait", Pick.Choose({ cur, soon }, cur) == cur)
	local now = target("lasthit", 0.1)
	check("switch: a creep killable now is taken from a wait due later than the gap", Pick.Choose({ cur, now }, cur) == now)
	local near = target("lasthit", 0.3)
	check("switch: not when the current is due within the gap", Pick.Choose({ near, now }, near) == near)
	local deny = target("deny", 0.1)
	check("switch: a deny due now never replaces a last-hit wait", Pick.Choose({ cur, deny }, cur) == cur)
	local denyCur = target("deny", 0.3)
	local lh = target("lasthit", 1.2)
	check("switch: a last hit on offer replaces a deny wait", Pick.Choose({ denyCur, lh }, denyCur) == lh)
	local far = target("lasthit", 0.1, false, 2.0, 1.0)
	check("switch: an unreachable creep due now does not move the wait", Pick.Choose({ cur, far }, cur) == cur)
	check("switch: without a current the pick is the plain ranking", Pick.Choose({ cur, now }) == now)
end

finish()
