dofile(HARNESS_DIR .. "/dota_stubs.lua")

ITEM_SLOT_TYPE_INVALID, ITEM_SLOT_TYPE_MAIN = -1, 0
local ATTACK = 1503

local function dist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
function GetUnitToUnitDistance(a, b) return dist(a.loc, b.loc) end

local WORLD = {}
function GetUnitList(kind) return WORLD[kind] or {} end

local Unit = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function Unit:GetUnitName() return self.name or ("npc_dota_hero_" .. self.pid) end
function Unit:IsHero() return self.isHero ~= false end
function Unit:IsTower() return false end
function Unit:IsNull() return false end
function Unit:CanBeSeen() return self.seen ~= false end
function Unit:GetAttackTarget() return self.target end
function Unit:GetAnimActivity() return self.anim or 1500 end
function Unit:GetAnimCycle() return self.cycle or 0 end
function Unit:GetAttackPoint() return 0.5 end
function Unit:GetAttackSpeed() return 1 end
function Unit:GetSecondsPerAttack() return 1 end
function Unit:GetLastAttackTime() return -100 end
function Unit:GetAttackDamage() return self.damage or 20 end
function Unit:GetAttackRange() return 150 end
function Unit:GetAttackProjectileSpeed() return 1000 end
function Unit:GetActualIncomingDamage(d) return d end
function Unit:GetHealthRegen() return 0 end
function Unit:GetMaxHealth() return self.maxhp or 100 end
function Unit:FindItemSlot() return -1 end
function Unit:GetItemSlotType() return ITEM_SLOT_TYPE_INVALID end
function Unit:GetLastHits() return self.lh or 0 end
function Unit:GetDenies() return self.dn or 0 end
function Unit:IsStunned() return false end
function Unit:IsHexed() return false end
function Unit:WasRecentlyDamagedByAnyHero() return false end
function Unit:ActionImmediate_Chat(line) self.said = self.said or {} table.insert(self.said, line) end
-- Projectiles stay in flight until their landing time, then the HP drop is applied.
function Unit:GetIncomingTrackingProjectiles()
	local r = {}
	for _, h in ipairs(self.incoming or {}) do
		if h.at > T then
			table.insert(r, { location = Vector(self.loc.x + (h.at - T) * 1000, self.loc.y), caster = h.caster, is_attack = true })
		end
	end
	return r
end
function Unit:GetHealth()
	local hp = self.hp
	for _, h in ipairs(self.incoming or {}) do if h.at <= T then hp = hp - h.damage end end
	return math.max(hp, 0)
end
function Unit:IsAlive() return self.alive and self:GetHealth() > 0 end

local DRAWN = {}
local LINES = {}
function DebugDrawLine(a, b, r, g, b2) table.insert(LINES, { a = a, b = b, r = r, g = g, b2 = b2 }) end
function DebugDrawText(x, y, text, r, g, b) table.insert(DRAWN, { x = x, y = y, text = text, r = r, g = g, b = b }) end

-- Creeps stay out of UNITS so they never show up as team players.
local nextCreep = 900
local function Creep(team, o)
	nextCreep = nextCreep + 1
	local c = setmetatable({ pid = nextCreep, team = team, alive = true, loc = o.loc or Vector(100, 0), hp = o.hp or 25, modifiers = {} }, Unit)
	c.isHero = false
	c.name = team == 3 and "npc_dota_creep_badguys_melee" or "npc_dota_creep_goodguys_ranged"
	for k, v in pairs(o) do c[k] = v end
	local list = team == CURRENT_TEAM and 3 or 9
	WORLD[list] = WORLD[list] or {}
	table.insert(WORLD[list], c)
	return c
end

local calls
local laning
local function setup(trainerCfg, o)
	o = o or {}
	ResetWorld()
	T = o.start or 100
	WORLD = {}
	DRAWN = {}
	LINES = {}
	CURRENT_TEAM = 2
	laning = true
	local cfg = { Enable = true, Debug = o.debug, Trainer = { LastHit = trainerCfg or {} } }
	local H = FreshHumaniser(cfg)
	calls = { delay = 0, bySubject = {}, log = {} }
	H.Trainer.SetHelpers({
		GetAttackProDelayTime = function(subject, creep)
			calls.delay = calls.delay + 1
			table.insert(calls.log, { pid = subject.pid, creep = creep, t = T })
			calls.bySubject[subject.pid] = (calls.bySubject[subject.pid] or 0) + 1
			return 0.4
		end,
		IsInLaningPhase = function() return laning end,
	})
	local human = MakeUnit({ pid = 0, bot = false })
	human.damage = 30
	local bots = {}
	for _, pid in ipairs(o.bots or { 1, 3 }) do table.insert(bots, MakeUnit({ pid = pid })) end
	WORLD[2] = { human }
	for _, b in ipairs(bots) do table.insert(WORLD[2], b) end
	return H, human, bots
end

local function say(H, text, pid)
	T = T + 0.5
	H.Commands.HandleMessage(2, { pid = pid or 0, text = text, teamOnly = true, time = T })
end

local DT = 0.05
local function tick(H, bots, n, before, after)
	for _ = 1, n or 1 do
		T = T + DT
		DRAWN = {}
		LINES = {}
		if before then before() end
		for _, b in ipairs(bots) do H.Trainer.Tick(b) end
		if after then after() end
	end
end

local function drawnStarting(prefix)
	for _, d in ipairs(DRAWN) do if d.text:sub(1, #prefix) == prefix then return d end end
	return nil
end

local function count(list, prefix)
	local n = 0
	for _, l in ipairs(list or {}) do if l:sub(1, #prefix) == prefix then n = n + 1 end end
	return n
end

local function capturePrint(fn)
	local lines, old = {}, print
	print = function(s) table.insert(lines, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err) end
	return lines
end

-- Human swings at the creep from now; the cycle tracks elapsed time so swingStart stays fixed.
local function swingFrames(H, bots, human, creep, frames, onFrame, afterFrame)
	local start = T + DT
	human.target = creep
	tick(H, bots, frames, function()
		human.anim, human.cycle = ATTACK, T - start
		if onFrame then onFrame(T - start) end
	end, afterFrame)
end

-- A last hit: the creep has 25 HP and the human deals 30, so the start window is open throughout.
local function scriptedLastHit(H, bots, human, creep)
	human.target = creep
	tick(H, bots, 4)
	local drawnPerfect
	swingFrames(H, bots, human, creep, 12, function(elapsed)
		if elapsed >= 0.4 and creep.alive then
			creep.alive = false
			human.lh = (human.lh or 0) + 1
		end
	end, function() drawnPerfect = drawnPerfect or drawnStarting("perfect") end)
	human.anim, human.target = 1500, nil
	return drawnPerfect
end

do
	local H, human, bots = setup()
	Creep(3, {})
	tick(H, bots, 30)
	check("off: no predictions run", calls.delay == 0, calls.delay)
	say(H, "!trainer on")
	tick(H, bots, 5)
	check("control: switched on, the creep is predicted", calls.delay > 0, calls.delay)
end

do
	local H, human, bots = setup()
	local creep = Creep(3, {})
	say(H, "!trainer on")
	local d = scriptedLastHit(H, bots, human, creep)
	check("on: verdict line drawn after a scripted last hit", d ~= nil)
	check("perfect line is green at the text corner", d and d.r == 0 and d.g == 255 and d.b == 0 and d.x == 560 and d.y == 40, d and d.text)

	say(H, "!trainer stats")
	tick(H, bots, 40)
	local said = bots[1].said or {}
	check("stats command replies with summary lines", count(said, "LH 1/1 (100%) - denies 0/0 - easy misses 0") == 1, said[#said])
	check("stats includes the leak line", count(said, "not enough data yet") == 1)

	say(H, "!trainer reset")
	say(H, "!trainer stats")
	tick(H, bots, 30)
	check("reset clears the stats", count(bots[1].said, "LH 0/0 (0%)") == 1, bots[1].said[#bots[1].said])

	Creep(3, { loc = Vector(120, 0) })
	tick(H, bots, 3)
	check("verdict line is still drawn before off", drawnStarting("perfect") ~= nil)
	check("control: bar predictions exist before off", #H.Trainer.Predictions(2) > 0)
	say(H, "!trainer off")
	tick(H, bots, 3)
	check("off clears screen text", #DRAWN == 0, #DRAWN)
	check("off clears the bar predictions", #H.Trainer.Predictions(2) == 0)
	say(H, "!trainer on")
	tick(H, bots, 3)
	check("switching back on does not bring the old line back", drawnStarting("perfect") == nil)
end

-- Late: an allied ranged creep's shots land at A+0.62 and A+0.82, so the start window is [A+0.22, A+0.42).
-- The human starts at A+0.62, so their hit would land at A+1.02, after the creep died at A+0.82.
local function lateCreep(H, bots, human)
	local A = T
	local caster = setmetatable({ pid = 800, team = 2, alive = true, loc = Vector(0, 0), modifiers = {}, damage = 20, isHero = false }, Unit)
	local creep = Creep(3, { hp = 40, incoming = { { at = A + 0.62, damage = 20, caster = caster }, { at = A + 0.82, damage = 20, caster = caster } } })
	human.target = creep
	while T < A + 0.6 do tick(H, bots, 1) end
	swingFrames(H, bots, human, creep, 10)
	human.anim, human.target = 1500, nil
	tick(H, bots, 2)
end

do
	local H, human, bots = setup({ Chat = "misses" })
	say(H, "!trainer on")
	scriptedLastHit(H, bots, human, Creep(3, {}))
	tick(H, bots, 50)
	lateCreep(H, bots, human)
	tick(H, bots, 20)
	local said = bots[1].said or {}
	check("chat misses mode sends late", count(said, "late by") == 1, said[#said])
	check("chat misses mode does not send perfect", count(said, "perfect") == 0)
end

do
	local H, human, bots = setup({ Chat = "all" })
	local creep = Creep(3, {})
	say(H, "!trainer on")
	human.target = creep
	tick(H, bots, 4)
	local function cancel()
		swingFrames(H, bots, human, creep, 3)
		human.anim = 1500
		tick(H, bots, 1)
	end
	cancel()
	tick(H, bots, 6)
	cancel()
	tick(H, bots, 40)
	cancel()
	tick(H, bots, 20)
	check("chat rate limit drops extras within 2s", count(bots[1].said, "cancelled swing") == 2, #(bots[1].said or {}))
end

do
	local H, human, bots = setup(nil, { start = 395 })
	say(H, "!trainer on")
	tick(H, bots, 20)
	check("checkpoints already past are skipped", count(bots[1].said, "LH ") == 0)
	while T < 600 do tick(H, bots, 1) end
	tick(H, bots, 20)
	check("the next checkpoint posts the summary to chat", count(bots[1].said, "LH 0/0") == 1, #bots[1].said)
	check("checkpoint summary is drawn below the verdicts", drawnStarting("LH 0/0") ~= nil and drawnStarting("LH 0/0").y == 90)
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	tick(H, bots, 20)
	check("control: no summary while laning", count(bots[1].said, "LH ") == 0)
	laning = false
	tick(H, bots, 20)
	check("laning end posts a summary", count(bots[1].said, "LH 0/0") == 1)
end

do
	local H, human, bots = setup(nil, { debug = true })
	local second = MakeUnit({ pid = 4, bot = false, loc = Vector(3000, 0) })
	second.damage = 30
	table.insert(WORLD[2], second)
	Creep(3, {})
	Creep(3, { loc = Vector(3100, 0) })
	say(H, "!trainer on")
	local printed = capturePrint(function() tick(H, bots, 30) end)
	local warns = 0
	for _, l in ipairs(printed) do
		if l == "[H:trainer] [WARN] trainer coaches one player; ignoring pid 4" then warns = warns + 1 end
	end
	check("second human is ignored with one warning", warns == 1, warns)
	check("second human's creeps are never predicted", calls.bySubject[4] == nil and (calls.bySubject[0] or 0) > 0)
end

do
	-- The stub GetTeamMember answers for team 2 whatever team asks, so the Dire bot sees the Radiant human.
	local H, human = setup({ SelfTest = true }, { bots = {} })
	local dire = MakeUnit({ pid = 5, team = 3, loc = Vector(0, 0) })
	Creep(3, {})
	Creep(2, { hp = 15 })
	say(H, "!trainer on")
	tick(H, { dire }, 30)
	check("other team's trainer does not coach this human", calls.bySubject[0] == nil)
	check("control: the Dire self-test bot is coached", (calls.bySubject[5] or 0) > 0)
end

-- Lost creeps: the creep leaves the unit lists and CanBeSeen turns false, as when it walks into fog.
local function loseCreep(creep)
	creep.seen = false
	for _, list in pairs(WORLD) do
		for i = #list, 1, -1 do if list[i] == creep then table.remove(list, i) end end
	end
end

do
	-- 100 HP; the allied ranged creep's shots leave it at 20 HP from A+1.1 until A+1.7, a 0.6 s start window.
	-- Graded as a death, that would be an easy miss.
	local H, human, bots = setup()
	say(H, "!trainer on")
	local A = T
	local caster = setmetatable({ pid = 801, team = 2, alive = true, loc = Vector(0, 0), modifiers = {}, damage = 40, isHero = false }, Unit)
	local creep = Creep(3, { hp = 100, incoming = { { at = A + 1.0, damage = 40, caster = caster }, { at = A + 1.1, damage = 40, caster = caster }, { at = A + 1.7, damage = 40, caster = caster } } })
	tick(H, bots, 4)
	check("control: the full-HP creep is selected", #H.Trainer.SubjectPredictions(2, 0) == 1)
	loseCreep(creep)
	tick(H, bots, 60)
	say(H, "!trainer stats")
	tick(H, bots, 40)
	check("creep lost at full HP is dropped, not graded", count(bots[1].said, "LH 0/0 (0%) - denies 0/0 - easy misses 0") == 1, bots[1].said[#bots[1].said])
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	local creep = Creep(3, {})
	tick(H, bots, 4)
	loseCreep(creep)
	tick(H, bots, 3)
	say(H, "!trainer stats")
	tick(H, bots, 40)
	check("creep lost at lethal HP near the subject is graded as a death", count(bots[1].said, "LH 0/1 (0%) - denies 0/0 - easy misses 1") == 1, bots[1].said[#bots[1].said])
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	local creep = Creep(3, {})
	tick(H, bots, 4)
	creep.IsNull = function() return true end
	tick(H, bots, 3)
	say(H, "!trainer stats")
	tick(H, bots, 40)
	check("invalid handle at lethal HP is graded as a death", count(bots[1].said, "LH 0/1 (0%) - denies 0/0 - easy misses 1") == 1, bots[1].said[#bots[1].said])
end

-- Calls per frame for the human, keyed by frame time.
local function callsPerFrame(from)
	local perFrame, creeps = {}, {}
	for _, c in ipairs(calls.log) do
		if c.pid == 0 and c.t > from then
			perFrame[c.t] = (perFrame[c.t] or 0) + 1
			creeps[c.creep] = true
		end
	end
	local lo, hi, distinct = math.huge, 0, 0
	for _, n in pairs(perFrame) do lo, hi = math.min(lo, n), math.max(hi, n) end
	for _ in pairs(creeps) do distinct = distinct + 1 end
	return lo, hi, distinct
end

do
	local H, human, bots = setup()
	for i = 1, 6 do Creep(3, { loc = Vector(60 + 40 * i, 0) }) end
	say(H, "!trainer on")
	local from = T
	tick(H, bots, 40)
	local _, hi, distinct = callsPerFrame(from)
	check("six candidates: at most 4 predictions per frame", hi == 4, hi)
	check("six candidates: every creep still gets predicted", distinct == 6, distinct)
end

do
	local H, human, bots = setup()
	for i = 1, 4 do Creep(3, { loc = Vector(60 + 40 * i, 0) }) end
	say(H, "!trainer on")
	tick(H, bots, 5)
	local from = T
	tick(H, bots, 20)
	local lo, hi = callsPerFrame(from)
	check("watched creeps are re-predicted only every WatchInterval", lo == 2 and hi == 4, lo .. "/" .. hi)
end

do
	local H = setup({ Enable = false })
	check("GetSubjects is gated by the kill switch", #H.Trainer.GetSubjects(2) == 0)
	local H2 = setup()
	check("control: GetSubjects finds the human when enabled", #H2.Trainer.GetSubjects(2) == 1)
end

do
	local H, human, bots = setup()
	for _ = 1, 12 do H.Trainer.OnCommand(2, 0, {}) end
	tick(H, bots, 200)
	check("reply queue holds at most 8 lines", #bots[1].said == 8, #bots[1].said)
end

local function linesOf(r, g, b)
	local out = {}
	for _, l in ipairs(LINES) do if l.r == r and l.g == g and l.b2 == b then table.insert(out, l) end end
	return out
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	local creep = Creep(3, { loc = Vector(100, 50, 10) })
	tick(H, bots, 4)
	check("bar draws lines for a visible creep", #LINES >= 4, #LINES)
	local now = linesOf(255, 255, 255)
	check("time bar has a white now tick 0.5/2.5 along, 16 tall at z+180",
		#now == 1 and now[1].a.x == 52 and now[1].b.x == 52 and now[1].a.z == 190 and now[1].b.z == 206 and now[1].a.y == 50, #now)
	local track = linesOf(128, 128, 128)[1]
	check("time bar track spans 160 units, from 0.5 s in the past to 2 s ahead", track ~= nil and track.b.x - track.a.x == 160)
	check("control: the window of a lethal creep is green", #linesOf(0, 255, 0) > 0)
	check("no swing tick before the subject swings", #linesOf(80, 160, 255) == 0)
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	local creep = Creep(3, {})
	tick(H, bots, 4)
	check("control: bar draws for the creep", #LINES > 0)
	human.target = creep
	swingFrames(H, bots, human, creep, 3)
	local blue = linesOf(80, 160, 255)
	check("swing tick sits at swingStart, 0.1 s behind now, 0.1/2.5 left of the now tick", #blue == 1 and math.abs(blue[1].a.x - (20 + 160 * 0.4 / 2.5)) < 1e-6, blue[1] and blue[1].a.x)
	human.target = nil
	tick(H, bots, 1, function() human.anim, human.cycle = ATTACK, 0.1 end)
	check("no swing tick when the swing is at another target", #linesOf(80, 160, 255) == 0)
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	Creep(3, {})
	tick(H, bots, 4)
	human.alive = false
	tick(H, bots, 1)
	check("bar hidden when the subject is dead", #LINES == 0, #LINES)
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	local creep = Creep(3, {})
	tick(H, bots, 4)
	creep.loc = Vector(1300, 0)
	tick(H, bots, 1)
	check("bar hidden once the creep is far away", #LINES == 0, #LINES)
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	Creep(3, {})
	tick(H, bots, 4)
	say(H, "!trainer bar off")
	tick(H, bots, 2)
	check("bar hidden when bar is off", #LINES == 0, #LINES)
	say(H, "!trainer bar on")
	tick(H, bots, 2)
	check("bar comes back on", #LINES > 0)
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	Creep(2, { hp = 25 })
	tick(H, bots, 4)
	check("deny bar uses cyan", #linesOf(0, 255, 255) > 0 and #linesOf(0, 255, 0) == 0, #linesOf(0, 255, 255))
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	local A = T
	local function caster(damage) return setmetatable({ pid = 802, team = 2, alive = true, loc = Vector(0, 0), modifiers = {}, damage = damage, isHero = false }, Unit) end
	local creep = Creep(3, { hp = 100, incoming = { { at = A + 1.2, damage = 50, caster = caster(50) }, { at = A + 1.5, damage = 30, caster = caster(30) } } })
	tick(H, bots, 2)
	check("control: a stable window is green, not amber", #linesOf(0, 255, 0) > 0 and #linesOf(255, 191, 0) == 0)
	table.insert(creep.incoming, { at = A + 1.0, damage = 30, caster = caster(30) })
	tick(H, bots, 8)
	check("uncertain bar uses amber", #linesOf(255, 191, 0) > 0 and #linesOf(0, 255, 0) == 0)
end

do
	local H, human, bots = setup({ BarStyle = "hp" })
	say(H, "!trainer on")
	local casters = {}
	for i, dmg in ipairs({ 10, 20, 30, 20 }) do casters[i] = setmetatable({ pid = 810 + i, team = 2, alive = true, loc = Vector(0, 0), modifiers = {}, damage = dmg, isHero = false }, Unit) end
	local creep = Creep(3, { loc = Vector(100, 0), hp = 100 })
	-- delay is 0.4 s, so the ghost sample is index 8; hits on samples 7, 8, 9 give 90, 70, 40 there.
	tick(H, bots, 4, function()
		creep.incoming = {
			{ at = T + 0.33, damage = 10, caster = casters[1] }, { at = T + 0.38, damage = 20, caster = casters[2] },
			{ at = T + 0.43, damage = 30, caster = casters[3] }, { at = T + 0.63, damage = 20, caster = casters[4] },
		}
	end)
	local marker = linesOf(0, 255, 0)
	check("hp bar: ghost marker uses the exact sample round(delay/STEP)", #marker == 1 and math.abs(marker[1].a.x - (20 + 160 * 0.70)) < 1e-6, marker[1] and marker[1].a.x)
end

do
	local H, human, bots = setup({ BarStyle = "hp" })
	say(H, "!trainer on")
	Creep(3, { loc = Vector(100, 0) })
	tick(H, bots, 4)
	local marker = linesOf(0, 255, 0)
	local effDmg = linesOf(255, 255, 255)
	check("hp bar: ghost marker at the HP when a hit started now would land", #marker == 1 and marker[1].a.x == 60, #marker)
	check("hp bar: white line at effective damage", #effDmg == 1 and effDmg[1].a.x == 68, #effDmg)
	local fill = linesOf(128, 128, 128)[1]
	check("hp bar: grey fill covers current HP", fill ~= nil and fill.a.x == 20 and fill.b.x == 60)
end

do
	local H, human, bots = setup()
	local Draw = require("bots/FunLib/humaniser/trainer/draw")
	local function pred(creep)
		return { creep = creep, isDeny = false, startOpen = T, startClose = T + 1, ideal = T + 0.5, uncertain = false, delay = 0.4, effDmg = 30, hp = 25, curve = { 25, 25 }, at = T }
	end
	local near = Creep(3, { loc = Vector(1100, 0) })
	local far = Creep(3, { loc = Vector(1300, 0) })
	LINES = {}
	Draw.Bars(human, { pred(far) }, "time", T)
	check("Bars draws nothing for a creep more than 1200 away", #LINES == 0, #LINES)
	Draw.Bars(human, { pred(near) }, "time", T)
	check("control: Bars draws for a creep 1100 away", #LINES > 0)
end

do
	local H, human, bots = setup()
	say(H, "!trainer on")
	scriptedLastHit(H, bots, human, Creep(3, {}))
	tick(H, bots, 10)
	say(H, "!trainer on")
	tick(H, bots, 10)
	say(H, "!trainer stats")
	tick(H, bots, 40)
	local said = bots[1].said or {}
	check("on while already on still replies with the status", count(said, "trainer on") == 2, #said)
	check("on while already on keeps the stats", count(said, "LH 1/1 (100%)") == 1, said[#said])
	check("stats also shows the summary on screen", drawnStarting("LH 1/1 (100%)") ~= nil)
end

do
	-- A creep handle's address can be reused by a later creep; that creep is judged afresh.
	local H, human, bots = setup()
	local function recycled()
		local c = Creep(3, {})
		return setmetatable(c, { __index = Unit, __tostring = function() return "creep: 0xreused" end })
	end
	say(H, "!trainer on")
	for _ = 1, 2 do
		local creep = recycled()
		-- Past the 0.25 s unit-list cache, so the new creep is seen.
		tick(H, bots, 8)
		creep.alive = false
		tick(H, bots, 3)
	end
	say(H, "!trainer stats")
	tick(H, bots, 40)
	local said = bots[1].said or {}
	check("a reused creep id gets its own easy miss", count(said, "LH 0/2 (0%) - denies 0/0 - easy misses 2") == 1, said[#said])
end

finish()
