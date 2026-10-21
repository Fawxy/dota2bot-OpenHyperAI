dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane = dota.Lane

local FRONT = Vector(0, -5000)

local function unit(o)
	local u = MakeUnit({ pid = o.pid, team = o.team or 2, bot = o.bot, loc = o.loc or FRONT, hp = o.hp })
	u.lane, u.pos = o.lane or Lane.Bot, o.pos
	return u
end

local function begin(skill, laneCfg)
	local H = LaneFresh(laneCfg or { Enable = true }, { skill = skill })
	T = 100
	CURRENT_TEAM = 2
	return H, H.Lane.LaneRoles, H.Lane.LaneState
end

local function snap(S, observer, lane)
	return S.Get(2, lane or Lane.Bot, observer)
end

local function advance(dt) T = T + dt end

local function enemyCreep(hp, target)
	return MakeCreep({ team = 3, x = 200, y = -5000, hp = hp or 550, target = target })
end

local function fogged(secs, x)
	return { pid = 10, visible = false, location = Vector(x or 0, -5000), timeSinceSeen = secs }
end
local function seen(pid, x)
	return { pid = pid, visible = true, location = Vector(x or 0, -5000), timeSinceSeen = 0 }
end

do
	local _, R, S = begin(0.5)
	local core = unit({ pid = 1, bot = true, pos = 1 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	local s = snap(S, core)
	check("pos1 is core", R.RoleIn(core, s) == "core")
	check("pos5 is support", R.RoleIn(support, s) == "support")
	check("core's partner is the support", R.Partner(core, s).pid == 5)
	check("support's partner is the core", R.Partner(support, s).pid == 1)

	local _, R2, S2 = begin(0.5)
	local mid = unit({ pid = 2, bot = true, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	local sm = snap(S2, mid, Lane.Mid)
	check("lone mid is solo", R2.RoleIn(mid, sm) == "solo")
	check("solo has no partner", R2.Partner(mid, sm) == nil)
end

local function aggroSetup(skill)
	local H, R, S = begin(skill)
	local core = unit({ pid = 1, bot = false, pos = 1 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	H.Lane.Config.SkillOf(support)
	T = 98
	local creep = enemyCreep(550, core)
	snap(S, support)
	creep.target = nil
	T = 100
	return R, S, support
end

do
	local R, S, support = aggroSetup(1)
	local ok, why = R.MayDrawAggro(support, snap(S, support))
	check("support waits after ally aggro 2 s ago", ok == false and why == "wait: ally-aggro", why)
	T = 101.5
	ok, why = R.MayDrawAggro(support, snap(S, support))
	check("support draws once the window passed", ok == true and why == "ok", why)
	check("snapshot keeps the draw time it saw", snap(S, support).lastAllyAggroAt[1] == 98)
end

do
	local R, S, support = aggroSetup(0)
	SetRandomSequence({ 0.1 })
	local ok, why = R.MayDrawAggro(support, snap(S, support))
	check("low skill double-draws on a low roll", ok == true and why == "mistake: double-draw", why)
	R, S, support = aggroSetup(0)
	SetRandomSequence({ 0.5 })
	ok, why = R.MayDrawAggro(support, snap(S, support))
	check("low skill still waits on a high roll", ok == false and why == "wait: ally-aggro", why)
	R, S, support = aggroSetup(1)
	SetRandomSequence({ 0.0 })
	ok, why = R.MayDrawAggro(support, snap(S, support))
	check("max skill never double-draws", ok == false and why == "wait: ally-aggro", why)
end

do
	local _, R, S = begin(1)
	unit({ pid = 1, bot = false, pos = 1 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	R.NoteAggroDraw(support, snap(S, support))
	advance(2)
	local ok, why = R.MayDrawAggro(support, snap(S, support))
	check("own cooldown blocks a second draw", ok == false and why == "wait: cooldown", why)
	advance(0.4)
	ok, why = R.MayDrawAggro(support, snap(S, support))
	check("cooldown expires", ok == true, why)
end

do
	local _, R, S = begin(1)
	local core = unit({ pid = 1, bot = true, pos = 1 })
	unit({ pid = 5, bot = true, pos = 5 })
	core.target = enemyCreep(60)
	local ok, why = R.MayDrawAggro(core, snap(S, core))
	check("core mid last-hit yields to the support", ok == false and why == "yield: support", why)

	core.target = nil
	core.hp = 55
	advance(1)
	ok, why = R.MayDrawAggro(core, snap(S, core))
	check("core under 60% HP yields to the support", ok == false and why == "yield: support", why)

	core.hp = 100
	advance(1)
	R.NoteNeed(core, T)
	advance(1.0)
	ok, why = R.MayDrawAggro(core, snap(S, core))
	check("healthy core staggers behind the support", ok == false and why == "yield: stagger", why)
	advance(0.6)
	ok, why = R.MayDrawAggro(core, snap(S, core))
	check("stagger ends after 1.5 s", ok == true and why == "ok", why)

	local _, R2, S2 = begin(1)
	local core2 = unit({ pid = 1, bot = true, pos = 1 })
	unit({ pid = 5, bot = false, pos = 5 })
	R2.NoteNeed(core2, T)
	advance(0.1)
	ok, why = R2.MayDrawAggro(core2, snap(S2, core2))
	check("no stagger when the support is human", ok == true, why)
end

do
	local _, R, S = begin(0.5)
	unit({ pid = 1, bot = true, pos = 1 })
	unit({ pid = 4, bot = true, pos = 4 })
	local five = unit({ pid = 5, bot = true, pos = 5 })
	check("highest position owns camp jobs", R.CampJobOwner(snap(S, five)) == 5)

	local _, R2, S2 = begin(0.5)
	unit({ pid = 1, bot = true, pos = 1 })
	local four = unit({ pid = 4, bot = true, pos = 4 })
	unit({ pid = 5, bot = false, pos = 5 })
	check("a human support keeps the camp jobs", R2.CampJobOwner(snap(S2, four)) == nil)

	local _, R3, S3 = begin(0.5)
	local mid = unit({ pid = 2, bot = true, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
	check("solo bot owns its camp jobs", R3.CampJobOwner(snap(S3, mid, Lane.Mid)) == 2)
end

do
	local function solo(skill)
		local _, R, S = begin(skill)
		local mid = unit({ pid = 2, bot = true, pos = 2, lane = Lane.Mid, loc = Vector(0, 0) })
		return R, mid, snap(S, mid, Lane.Mid)
	end
	local R, mid, s = solo(0.6)
	local ok, why = R.MayRunCampJob(mid, s, {})
	check("skill exactly at the gate is not enough", ok == false, why)
	R, mid, s = solo(0.61)
	ok, why = R.MayRunCampJob(mid, s, {})
	check("skill above the gate on a stable lane may run", ok == true and why == "ok", why)
	R, mid, s = solo(0.9)
	ok, why = R.MayRunCampJob(mid, s, { { pid = 10, visible = false, location = Vector(1000, 0), timeSinceSeen = 2 } })
	check("recently seen enemy nearby blocks the solo camp job", ok == false, why)
	R, mid, s = solo(0.9)
	ok, why = R.MayRunCampJob(mid, s, { { pid = 10, visible = false, location = Vector(1000, 0), timeSinceSeen = 4 } })
	check("a stale sighting does not", ok == true, why)
	R, mid, s = solo(0.9)
	LANING = false
	ok, why = R.MayRunCampJob(mid, s, {})
	check("no lane camp jobs after laning", ok == false, why)
	LANING = nil
end

do
	local _, R, S = begin(0.5)
	unit({ pid = 1, bot = true, pos = 1 })
	local four = unit({ pid = 4, bot = true, pos = 4 })
	local five = unit({ pid = 5, bot = true, pos = 5 })
	local s = snap(S, five)
	local ok, why = R.MayRunCampJob(four, s, {})
	check("only the owner runs the camp job", ok == false and why == "not-owner", why)
	ok = R.MayRunCampJob(five, s, {})
	check("owner with a safe partner runs it", ok == true)
	ok, why = R.MayRunCampJob(five, s, { seen(10), seen(11) })
	check("owner leaves the partner alone when unsafe", ok == false and why == "partner unsafe", why)
end

do
	local _, R, S = begin(0.5)
	local core = unit({ pid = 1, bot = true, pos = 1, hp = 39 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	local s = snap(S, support)
	check("partner at 39% is unsafe", R.PartnerSafe(support, s, {}) == false)
	core.hp = 40
	advance(1)
	s = snap(S, support)
	check("partner at 40% is safe", R.PartnerSafe(support, s, {}) == true)
	check("two visible enemies near the partner are unsafe", R.PartnerSafe(support, s, { seen(10, 1100), seen(11, 0) }) == false)
	check("one visible enemy is not", R.PartnerSafe(support, s, { seen(10, 0) }) == true)
	check("two visible enemies out of range are not", R.PartnerSafe(support, s, { seen(10, 1500), seen(11, 1500) }) == true)
	check("two fogged enemies do not count", R.PartnerSafe(support, s, { fogged(1), fogged(1) }) == true)
end

do
	local _, R, S = begin(0.5)
	local core = unit({ pid = 1, bot = true, pos = 1 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	local function absent()
		advance(1)
		return R.CoreAbsent(snap(S, support))
	end
	check("core at the front is not absent", absent() == false)
	core.alive = false
	check("dead core is absent", absent() == true)
	core.alive = true
	core.loc = Vector(1300, -5000)
	check("core 1300 away is absent", absent() == true)
	core.loc = Vector(900, -5000)
	check("core 900 away is not", absent() == false)

	local _, R2, S2 = begin(0.5)
	local lone = unit({ pid = 5, bot = true, pos = 5 })
	unit({ pid = 4, bot = true, pos = 4 })
	check("no core assigned is not absent", R2.CoreAbsent(snap(S2, lone)) == false)
end

do
	local H, R, S = begin(0)
	local core = unit({ pid = 1, bot = true, pos = 1, loc = Vector(1300, -5000) })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	H.Lane.Config.SkillOf(support)
	local function ask()
		advance(1)
		return R.CoverAbsentCore(support, snap(S, support), T)
	end
	SetRandomSequence({ 0.5 })
	check("failed roll means no cover", ask() == false)
	SetRandomSequence({ 0.1 })
	check("the same absence is not re-rolled", ask() == false)
	check("still not re-rolled later", ask() == false)
	core.loc = Vector(900, -5000)
	check("no cover once the core is back", ask() == false)
	core.loc = Vector(1300, -5000)
	SetRandomSequence({ 0.1 })
	check("a new absence rolls again", ask() == true)
	SetRandomSequence({ 0.9 })
	check("the cover decision holds for the absence", ask() == true)
end

do
	-- Hysteresis: a support needs the core at 40% to leave, but once committed only turns back below 35%.
	local _, R, S = begin(0.5)
	local core = unit({ pid = 1, bot = true, pos = 1, hp = 38 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	local s = snap(S, support)
	check("38%: no new job", R.PartnerSafe(support, s, {}) == false)
	check("38%: a running job holds", R.PartnerHolding(support, s, {}) == true)
	core.hp = 34
	local ok, why = R.PartnerHolding(support, s, {})
	check("34%: a running job turns back", ok == false and why == "partner low-hp", why)
	core.hp = 100
	check("two laners standing near a healthy core: no new job", R.PartnerSafe(support, s, { seen(10, 1100), seen(11, 0) }) == false)
	check("two laners standing near a healthy core: a running job holds", R.PartnerHolding(support, s, { seen(10, 1100), seen(11, 0) }) == true)
end

do
	-- A dive is an enemy on top of the core while the core loses HP, held for the support's reaction time.
	local _, R, S = begin(0.5)
	local core = unit({ pid = 1, bot = true, pos = 1, hp = 100 })
	local support = unit({ pid = 5, bot = true, pos = 5 })
	local s = snap(S, support)
	local on = { seen(10, 300) }
	check("enemy close, no damage yet", R.PartnerHolding(support, s, on) == true)
	advance(0.5) core.hp = 85
	check("damage starts: reaction delay", R.PartnerHolding(support, s, on) == true)
	advance(0.3)
	check("still within the delay", R.PartnerHolding(support, s, on) == true)
	advance(0.2)
	local ok, why = R.PartnerHolding(support, s, on)
	check("dive held 0.5 s: turn back", ok == false and why == "partner dived", why)
	advance(0.1)
	check("enemy leaves: holds again", R.PartnerHolding(support, s, { seen(10, 1100) }) == true)
	advance(3)
	check("old damage outside the window does not count", R.PartnerHolding(support, s, on) == true)
	local r = R.ReadPartner(support, s, on)
	check("reading: hp, near, close, loss", near(r.hp, 0.85) and r.near == 1 and r.close == 1 and near(r.loss, 0), r.loss)
end

finish()
