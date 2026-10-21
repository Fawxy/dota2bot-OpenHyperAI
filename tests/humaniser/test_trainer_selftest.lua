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


local DT = 0.05
local textDrawn = 0
local function tick(H, bots, n)
	for _ = 1, n do
		T = T + DT
		DRAWN = {}
		for _, b in ipairs(bots) do H.Trainer.Tick(b) end
		textDrawn = textDrawn + #DRAWN
	end
end

local function capturePrint(fn)
	local lines, old = {}, print
	print = function(s) table.insert(lines, tostring(s)) end
	local ok, err = pcall(fn)
	print = old
	if not ok then error(err) end
	return lines
end

local function count(list, prefix)
	local n = 0
	for _, l in ipairs(list or {}) do if l:sub(1, #prefix) == prefix then n = n + 1 end end
	return n
end

do
	local H, _, bots = setup({ SelfTest = true })
	check("the lowest-PID bot is the self-test bot", H.Trainer.IsSelfTestBot(bots[1]) == true)
	check("another bot is not", H.Trainer.IsSelfTestBot(bots[2]) == false)
	local H2, _, bots2 = setup({ SelfTest = false })
	check("SelfTest off: nobody is", H2.Trainer.IsSelfTestBot(bots2[1]) == false and H2.Trainer.IsSelfTestBot(bots2[2]) == false)
end

do
	-- 60 HP, a 50 HP hit lands at A+1.0 and another at A+2.0 kills it; the bot's 20 damage needs HP <= 20 and
	-- its attack takes 0.4 s, so the start window is roughly A+0.6 .. A+1.6.
	local H, _, bots = setup({ SelfTest = true })
	local A = T
	local caster = setmetatable({ pid = 801, team = 2, alive = true, loc = Vector(0, 0), modifiers = {}, damage = 50, isHero = false }, Unit)
	local creep = Creep(3, { hp = 60, incoming = { { at = A + 1.0, damage = 50, caster = caster }, { at = A + 2.0, damage = 50, caster = caster } } })
	tick(H, bots, 2)
	local preds = H.Trainer.SubjectPredictions(2, bots[1].pid)
	check("control: the self-test bot has a prediction for the creep", #preds == 1 and preds[1].creep == creep, #preds)
	local open, close = preds[1].startOpen, preds[1].startClose
	check("control: the window is still ahead", open > T, open - T)
	check("no target before the window reaches now", H.Trainer.SelfTestTarget(bots[1]) == nil)
	local early, firstHit
	while firstHit == nil and T < A + 3 do
		local before = H.Trainer.SubjectPredictions(2, bots[1].pid)[1]
		if before and before.startOpen > T + DT then early = early or false end
		tick(H, bots, 1)
		local p = H.Trainer.SubjectPredictions(2, bots[1].pid)[1]
		local target = H.Trainer.SelfTestTarget(bots[1])
		if target == nil and p and p.startOpen <= T then early = "nil despite an open window" end
		if target ~= nil then
			firstHit = target
			check("target only once the window reaches now", p.startOpen <= T and T < p.startClose, T)
		end
	end
	check("no target while the window was still ahead", early == false, early)
	check("the creep is targeted once its window reaches now", firstHit == creep)
	creep.incoming = { { at = T - 0.01, damage = 100, caster = caster } }
	tick(H, bots, 1)
	check("no target after the window closes", H.Trainer.SelfTestTarget(bots[1]) == nil)
end

do
	-- Two creeps whose windows are both open: the one that closes first is hit first.
	local H, _, bots = setup({ SelfTest = true })
	local A = T
	local caster = setmetatable({ pid = 801, team = 2, alive = true, loc = Vector(0, 0), modifiers = {}, damage = 50, isHero = false }, Unit)
	local late = Creep(3, { hp = 15, incoming = { { at = A + 3.0, damage = 50, caster = caster } } })
	local early = Creep(3, { hp = 15, incoming = { { at = A + 1.5, damage = 50, caster = caster } } })
	tick(H, bots, 3)
	check("the earliest-closing window wins", H.Trainer.SelfTestTarget(bots[1]) == early)
end

do
	local H, human, bots = setup({ SelfTest = true }, { debug = true })
	local creep = Creep(3, { hp = 15 })
	human.loc = Vector(5000, 0)
	textDrawn = 0
	local printed = capturePrint(function()
		tick(H, bots, 10)
		creep.alive = false
		for _, list in pairs(WORLD) do
			for i = #list, 1, -1 do if list[i] == creep then table.remove(list, i) end end
		end
		tick(H, bots, 20)
	end)
	local logged = 0
	for _, l in ipairs(printed) do
		if l:find("[H:trainer] selftest predicted=", 1, true) then logged = logged + 1 end
	end
	check("self-test bot attempts are logged", logged > 0, #printed)
	check("nothing is drawn as text for the self-test bot", textDrawn == 0, textDrawn)
end

-- In game DotaTime lags GameTime by the whole pre-game; predictions and attack times are on GameTime.
local function withDotaLag(lag, fn)
	local real = DotaTime
	DotaTime = function() return T - lag end
	local ok, err = pcall(fn)
	DotaTime = real
	if not ok then error(err) end
end

withDotaLag(90, function()
	local H, _, bots = setup({ SelfTest = true })
	local A = T
	local caster = setmetatable({ pid = 801, team = 2, alive = true, loc = Vector(0, 0), modifiers = {}, damage = 50, isHero = false }, Unit)
	local creep = Creep(3, { hp = 60, incoming = { { at = A + 1.0, damage = 50, caster = caster }, { at = A + 2.0, damage = 50, caster = caster } } })
	local found
	while found == nil and T < A + 3 do
		tick(H, bots, 1)
		found = H.Trainer.SelfTestTarget(bots[1])
	end
	check("DotaTime behind GameTime: the self-test target is still found", found == creep)
end)

withDotaLag(90, function()
	-- GameTime 350 is DotaTime 260, so the 300 s checkpoint is still ahead at switch-on.
	local H, _, bots = setup({ SelfTest = true }, { start = 350 })
	tick(H, bots, 2)
	while T < 385 do tick(H, bots, 1) end
	check("control: no checkpoint summary before DotaTime 300", count(bots[1].said, "LH ") == 0, #(bots[1].said or {}))
	while T < 392 do tick(H, bots, 1) end
	tick(H, bots, 20)
	check("the checkpoint fires on DotaTime, not GameTime", count(bots[1].said, "LH 0/0") == 1, #(bots[1].said or {}))
end)

-- SelfTestHolding: mid-swing on a creep the laning Think must not issue an order, or it cancels the swing.
do
	local H, _, bots = setup({ SelfTest = true })
	local bot = bots[1]
	local creep = Creep(3, { hp = 60 })
	local hero = MakeUnit({ pid = 7, team = 3 })
	bot.anim, bot.cycle, bot.target = ATTACK, 0.2, creep
	check("holds while swinging at a creep before the attack point", H.Trainer.SelfTestHolding(bot) == true)
	bot.cycle = 0.6
	check("does not hold after the attack point", H.Trainer.SelfTestHolding(bot) == false)
	bot.cycle, bot.target = 0.2, hero
	check("does not hold while swinging at a hero", H.Trainer.SelfTestHolding(bot) == false)
	bot.anim, bot.target = 1500, creep
	check("does not hold outside the attack animation", H.Trainer.SelfTestHolding(bot) == false)
	local H2, _, bots2 = setup({ SelfTest = false })
	bots2[1].anim, bots2[1].cycle, bots2[1].target = ATTACK, 0.2, Creep(3, { hp = 60 })
	check("SelfTest off: never holds", H2.Trainer.SelfTestHolding(bots2[1]) == false)
end

finish()
