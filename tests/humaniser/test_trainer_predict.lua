dofile(HARNESS_DIR .. "/dota_stubs.lua")

ITEM_SLOT_TYPE_INVALID, ITEM_SLOT_TYPE_MAIN, ITEM_SLOT_TYPE_BACKPACK = -1, 0, 1

local function dist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
function GetUnitToUnitDistance(a, b) return dist(a.loc, b.loc) end

local WORLD = {}
function GetUnitList(kind) return WORLD[kind] or {} end

local Unit = getmetatable(MakeUnit({ pid = 99 })).__index
function Unit:GetUnitName() return self.name or ("npc_dota_hero_" .. self.pid) end
function Unit:IsHero() return self.isHero ~= false end
function Unit:IsTower() return self.tower == true end
function Unit:GetAttackTarget() return self.target end
function Unit:GetAnimActivity() return self.anim or 1500 end
function Unit:GetAnimCycle() return self.cycle or 0 end
function Unit:GetAttackPoint() return self.point or 0.5 end
function Unit:GetSecondsPerAttack() return self.spa or 1 end
function Unit:GetLastAttackTime() return self.lastAttack or -100 end
function Unit:GetAttackDamage() return self.damage or 20 end
function Unit:GetAttackRange() return self.range or 150 end
function Unit:GetAttackProjectileSpeed() return self.projSpeed or 1000 end
function Unit:GetActualIncomingDamage(d) return d * (self.armor or 1) end
function Unit:GetIncomingTrackingProjectiles() return self.projectiles or {} end
function Unit:GetHealthRegen() return self.regen or 0 end
function Unit:GetMaxHealth() return self.maxhp or 100 end
function Unit:FindItemSlot(name) return self.items and self.items[name] or -1 end
function Unit:GetItemSlotType(slot) if slot < 0 then return ITEM_SLOT_TYPE_INVALID end return self.slotType or ITEM_SLOT_TYPE_MAIN end

local runs = 0
local function reset()
	ResetWorld()
	runs = runs + 1
	T = 100 + runs
	WORLD = {}
	CURRENT_TEAM = 2
end

-- kind: "melee" | "ranged" | "siege" | "tower" | "hero"
local function Attacker(kind, o)
	local u = MakeUnit({ pid = 50 + runs * 10 + #UNITS[3], team = 3, loc = o.loc or Vector(100, 0) })
	u.isHero = kind == "hero"
	u.tower = kind == "tower"
	u.name = ({ melee = "npc_dota_creep_badguys_melee", ranged = "npc_dota_creep_badguys_ranged",
		siege = "npc_dota_badguys_siege", tower = "npc_dota_badguys_tower1_mid", hero = "npc_dota_hero_axe" })[kind]
	for k, v in pairs(o) do u[k] = v end
	table.insert(WORLD[9] or {}, u)
	WORLD[9] = WORLD[9] or { u }
	return u
end

local function Creep(o)
	o = o or {}
	local u = MakeUnit({ pid = 900 + runs, team = o.team or 2, loc = Vector(0, 0), hp = o.hp or 100 })
	u.isHero = false
	u.name = "npc_dota_creep_goodguys_melee"
	for k, v in pairs(o) do u[k] = v end
	return u
end

local function Subject()
	local s = MakeUnit({ pid = 1, loc = Vector(-150, 0) })
	s.damage = 30
	return s
end

local Predict = require("bots/FunLib/humaniser/trainer/predict")
local Incoming = require("bots/FunLib/humaniser/trainer/incoming")
local Api = require("bots/FunLib/humaniser/trainer/api")

-- TSTL classes have no constructor entry point other than its inlined __TS__New.
function NewSmoother()
	local s = setmetatable({}, Predict.Smoother.prototype)
	Predict.Smoother.prototype.____constructor(s)
	return s
end

local function hasHit(hits, at, damage)
	for _, h in ipairs(hits) do
		if math.abs(h.at - at) < 1e-6 and math.abs(h.damage - damage) < 1e-6 then return true end
	end
	return false
end

-- Curve and window maths.
do
	local curve = Predict.BuildCurve(100, 0, { { at = 0.3, damage = 20 }, { at = 0.8, damage = 20 }, { at = 1.3, damage = 20 }, { at = 1.3, damage = 50 } })
	check("curve has 41 samples", #curve == 41, #curve)
	check("curve drops 20 at 0.3", near(curve[7], 80) and near(curve[6], 100), curve[7])
	check("two attackers on one tick merge into one drop", near(curve[27], -10) and near(curve[26], 60), curve[27])

	local w = Predict.KillWindow(curve, 60, 0.3)
	check("steady curve: window from subject's damage to the other kill", w ~= nil and math.abs(w.open - 0.5) < 1e-6 and math.abs(w.close - 1.0) < 1e-6, w and (w.open .. "," .. w.close))
end

do
	local curve = Predict.BuildCurve(100, 0, { { at = 0.6, damage = 110 } })
	check("tower shot closes the window early", Predict.KillWindow(curve, 40, 0.3) == nil)
	check("a shot before the killing blow leaves a window", Predict.KillWindow(curve, 110, 0.3) ~= nil)
end

do
	local curve = Predict.BuildCurve(100, 0, { { at = 0.3, damage = 5 }, { at = 0.8, damage = 10 }, { at = 1.3, damage = 100 } })
	check("empty window when the subject can never finish before the other kill", Predict.KillWindow(curve, 5, 0.3) == nil)
end

do
	local curve = Predict.BuildCurve(100, 0, { { at = 0.4, damage = 70 }, { at = 1.5, damage = 40 } })
	local w = Predict.KillWindow(curve, 100, 0.3)
	check("without a floor the window opens immediately", w ~= nil and w.open < 0, w and w.open)
	local denied = Predict.KillWindow(curve, 100, 0.3, 0.4)
	check("deny floor: the start can't open before HP drops below half", denied ~= nil and math.abs(denied.open - 0.4) < 1e-6, denied and denied.open)
end

-- Hits.
do
	reset()
	local subject, creep = Subject(), Creep()
	local other = Attacker("melee", { target = creep, anim = 1503, cycle = 0.25, point = 0.5, spa = 1, damage = 20 })
	subject.target = creep
	subject.anim, subject.cycle, subject.point = 1503, 0.1, 0.5
	creep.projectiles = { { location = Vector(0, 0), caster = subject, is_attack = true } }
	WORLD[8] = { subject }
	local hits = Incoming.Hits(creep, subject, 2.0)
	check("Hits excludes the subject's own projectile and swing", #hits == 2 and hasHit(hits, 0.25, 20) and hasHit(hits, 1.25, 20), #hits)
end

do
	reset()
	local subject, creep = Subject(), Creep()
	Attacker("melee", { target = creep, lastAttack = T - 0.2, point = 0.5, spa = 1, damage = 20 })
	local hits = Incoming.Hits(creep, subject, 2.0)
	check("idle creep's next swing is projected and repeats", #hits == 1 and hasHit(hits, 1.3, 20), #hits)

	reset()
	creep = Creep()
	Attacker("tower", { target = creep, lastAttack = T - 0.2, point = 0.5, spa = 0.83, projSpeed = 1000, loc = Vector(122, 0), damage = 100 })
	hits = Incoming.Hits(creep, subject, 2.0)
	check("a tower repeats every attack period", #hits == 2 and hasHit(hits, 0.63 + 0.415 + 0.1, 100) and hasHit(hits, 0.63 + 0.415 + 0.1 + 0.83, 100), #hits)
end

do
	reset()
	local subject, creep = Subject(), Creep()
	Attacker("hero", { target = creep, anim = 1503, cycle = 0.2, point = 0.5, spa = 1, damage = 40 })
	local hits = Incoming.Hits(creep, subject, 2.0)
	check("a hero counts for its current hit only", #hits == 1 and hasHit(hits, 0.3, 40), #hits)
end

do
	reset()
	local subject, creep = Subject(), Creep({ armor = 0.5 })
	local tower = Attacker("tower", { target = nil, projSpeed = 1000, damage = 100, loc = Vector(5000, 0) })
	local rangedCreep = Attacker("melee", { target = creep, lastAttack = T - 0.2, damage = 20, loc = Vector(50, 0) })
	creep.projectiles = {
		{ location = Vector(93, 0), caster = tower, is_attack = true },
		{ location = Vector(10, 0), caster = rangedCreep, is_attack = false },
	}
	local hits = Incoming.Hits(creep, subject, 2.0)
	check("in-flight tower projectile lands at distance / (speed * 0.93) with armour applied", hasHit(hits, 93 / 930, 50), #hits)
	check("non-attack projectiles are ignored", #hits == 2, #hits)
end

do
	reset()
	local subject, creep = Subject(), Creep()
	Attacker("siege", { target = creep, anim = 1503, cycle = 0.146, loc = Vector(22, 0), damage = 45 })
	local hits = Incoming.Hits(creep, subject, 2.0)
	check("siege in swing lands by its fixed swing curve", hasHit(hits, (0.292 - 0.146) * 0.699 / 0.292, 45), hits[1] and hits[1].at)
end

-- NearbyUnits.
do
	reset()
	local calls = 0
	local real = GetUnitList
	function GetUnitList(kind) calls = calls + 1 return real(kind) end
	local near1 = Attacker("melee", { loc = Vector(100, 0) })
	Attacker("melee", { loc = Vector(3000, 0) })
	local found = Incoming.NearbyUnits(Vector(0, 0), 1600)
	check("NearbyUnits filters by radius", #found == 1 and found[1] == near1, #found)
	local afterFirst = calls
	T = T + 0.1
	Incoming.NearbyUnits(Vector(0, 0), 1600)
	check("NearbyUnits caches lists for 0.25 s", calls == afterFirst, calls)
	T = T + 0.2
	Incoming.NearbyUnits(Vector(0, 0), 1600)
	check("NearbyUnits refreshes after 0.25 s", calls > afterFirst, calls)
	GetUnitList = real
end

-- EffectiveDamage and Predict.
do
	reset()
	local creep = Creep({ armor = 0.5 })
	local subject = Subject()
	check("no quelling blade: raw damage through armour", near(Predict.EffectiveDamage(subject, creep, false), 15))
	subject.items = { item_quelling_blade = 3 }
	check("quelling blade adds 8 for a melee last hit", near(Predict.EffectiveDamage(subject, creep, false), 19))
	subject.range = 600
	check("quelling blade adds 4 for a ranged last hit", near(Predict.EffectiveDamage(subject, creep, false), 17))
	check("quelling blade does not apply to a deny", near(Predict.EffectiveDamage(subject, creep, true), 15))
	subject.range = 150
	subject.slotType = ITEM_SLOT_TYPE_BACKPACK
	check("quelling blade in the backpack gives no bonus", near(Predict.EffectiveDamage(subject, creep, false), 15))
end

do
	reset()
	Api.SetTrainerHelpers({ GetAttackProDelayTime = function() return 0.3 end, IsInLaningPhase = function() return true end })
	local subject, creep = Subject(), Creep({ hp = 50 })
	subject.damage = 25
	Attacker("melee", { target = creep, anim = 1503, cycle = 0.25, point = 0.5, spa = 1, damage = 30 })
	local p = Predict.Predict(subject, creep, false, T, NewSmoother())
	check("Predict opens at the subject's damage and closes at the other kill", p ~= nil and math.abs(p.startOpen - (T - 0.05)) < 1e-6 and math.abs(p.startClose - (T + 0.95)) < 1e-6, p and (p.startOpen - T))
	check("Predict ideal is the window midpoint", p ~= nil and math.abs(p.ideal - (T + 0.45)) < 1e-6)
	check("Predict carries delay and damage", p ~= nil and near(p.delay, 0.3) and near(p.effDmg, 25) and p.hp == 50)
end

-- Smoother.
do
	local s = NewSmoother()
	local t0 = 10
	local r = s:Push(t0, 1.0, 2.0)
	r = s:Push(t0 + 1 / 30, 1.0, 2.0)
	r = s:Push(t0 + 2 / 30, 1.0, 2.0)
	check("smoother: a steady window is certain", r.uncertain == false and near(r.open, 1.0) and near(r.close, 2.0))
	r = s:Push(t0 + 0.33, 1.3, 2.3)
	check("smoother flags a jump against an older sample", r.uncertain == true)
	check("smoother averages the last 3 pushes", math.abs(r.open - (1.0 + 1.0 + 1.3) / 3) < 1e-6, r.open)

	local slow = NewSmoother()
	slow:Push(0, 1.0, 2.0)
	r = slow:Push(0.1, 1.3, 2.3)
	check("a jump only 0.1 s after the older sample is not flagged", r.uncertain == false)
end

do
	local s = NewSmoother()
	local r
	for i = 0, 15 do
		local t = 10 + i / 30
		r = s:Push(t, t - 0.4, 12.0)
	end
	check("smoother: an already-open window tracking now stays certain over 0.5 s", r.uncertain == false)
	r = s:Push(10.8, 10.4, 12.3)
	check("smoother: a 0.3 jump in the close edge is still flagged", r.uncertain == true)

	local future = NewSmoother()
	future:Push(10, 11.0, 12.0)
	r = future:Push(10.33, 11.3, 12.0)
	check("smoother: a future open edge jumping 0.3 is flagged", r.uncertain == true)
end

finish()
