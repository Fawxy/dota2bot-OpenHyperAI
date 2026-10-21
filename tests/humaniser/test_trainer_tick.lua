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
	CURRENT_TEAM = 2
	laning = true
	local cfg = { Enable = true, Debug = o.debug, Trainer = { LastHit = trainerCfg or {} } }
	local H = FreshHumaniser(cfg)
	calls = { delay = 0, bySubject = {} }
	H.Trainer.SetHelpers({
		GetAttackProDelayTime = function(subject)
			calls.delay = calls.delay + 1
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

	tick(H, bots, 1)
	check("verdict line is still drawn before off", drawnStarting("perfect") ~= nil)
	say(H, "!trainer off")
	tick(H, bots, 3)
	check("off clears screen text", #DRAWN == 0, #DRAWN)
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

do
	local H, human, bots = setup()
	for _ = 1, 12 do H.Trainer.OnCommand(2, 0, {}) end
	tick(H, bots, 200)
	check("reply queue holds at most 8 lines", #bots[1].said == 8, #bots[1].said)
end

finish()
