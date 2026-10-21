dofile(HARNESS_DIR .. "/dota_stubs.lua")

DAMAGE_TYPE_PHYSICAL = 1

-- Rolls are consumed in order (eps first, then attempt); an empty queue falls back to the stub's midpoint.
local ROLLS = {}
local function rolls(...) ROLLS = { ... } end
function RandomFloat(a, b)
	local f = table.remove(ROLLS, 1)
	if f == nil then f = RANDOM_FRACTION or 0.5 end
	return a + (b - a) * f
end

local Unit = getmetatable(MakeUnit({ pid = 99 })).__index
function Unit:WasRecentlyDamagedByAnyHero() return self.pressured == true end
function Unit:GetAttackTarget() return self.target end
function Unit:GetLastHits() return self.lastHits or 0 end
function Unit:GetDenies() return self.denies or 0 end

local Creep = {}
Creep.__index = Creep
function Creep:GetHealth() return self.hp end
function Creep:GetMaxHealth() return 100 end
function Creep:GetTeam() return self.team end
function Creep:IsAlive() return self.hp > 0 end
function Creep:IsNull() return self.removed == true end
function Creep:IsHero() return false end
function Creep:GetUnitName() return self.name end
local function MakeCreep(hp, name) return setmetatable({ hp = hp, team = 3, name = name or "npc_dota_creep_badguys_melee" }, Creep) end

local function Setup(skill, lastHitSkill)
	ResetWorld()
	T = 100
	ROLLS = {}
	local H = FreshHumaniser({ Enable = true, SkillOverride = skill, LastHitSkill = lastHitSkill or { Enable = true, RequireOwnedLaning = false } })
	H.LastHitSkill.SetHelpers({ WillKillTarget = function(c, dmg) return dmg >= c:GetHealth() end })
	local bot = MakeUnit({ pid = 1 })
	-- The profile's personal roll happens on first use; take it before any queued rolls.
	H.Profile.Get(bot)
	return H, bot
end

local function will(H, bot, creep, dmg, isDeny) return H.LastHitSkill.WillKill(bot, creep, dmg or 10, 0.3, isDeny == true) end

-- e = lerp(0.15, 0.02, skill)
do
	local H, bot = Setup(0)
	check("error width at skill 0", near(H.LastHitSkill.ErrorWidth(bot), 0.15), H.LastHitSkill.ErrorWidth(bot))
	H, bot = Setup(0.5)
	check("error width at skill 0.5", near(H.LastHitSkill.ErrorWidth(bot), 0.085), H.LastHitSkill.ErrorWidth(bot))
	H, bot = Setup(0.99)
	check("error width at skill 0.99", near(H.LastHitSkill.ErrorWidth(bot), 0.02 + 0.13 * 0.01), H.LastHitSkill.ErrorWidth(bot))
end

-- Skill 1.0 and a disabled feature both pass the upstream predicate straight through, even on the worst roll.
local function matchesUpstream(H, bot, label)
	for _, isDeny in ipairs({ false, true }) do
		for _, hp in ipairs({ 9, 10, 11 }) do
			local c = MakeCreep(hp)
			rolls(0, 0.999)
			local got = will(H, bot, c, 10, isDeny)
			check(label .. " hp=" .. hp .. " deny=" .. tostring(isDeny), got == H.LastHitSkill.Upstream(c, 10, 0.3, isDeny), got)
		end
	end
end
do
	local H, bot = Setup(1)
	matchesUpstream(H, bot, "skill 1.0 is upstream")
	H, bot = Setup(0, { Enable = false })
	matchesUpstream(H, bot, "disabled passes the upstream predicate through")
	H, bot = Setup(0)
	H.Config.Get().Enable = false
	matchesUpstream(H, bot, "humaniser off passes the upstream predicate through")
end

-- eps = +1 at skill 0: damage 10 is believed to be 11.5, so an 11 hp creep looks killable (an early swing).
do
	local H, bot = Setup(0)
	local c = MakeCreep(11)
	rolls(1, 0)
	check("positive eps swings early", will(H, bot, c) == true)
	rolls(0, 0)
	T = 100.5
	check("eps fixed for the creep's lifetime (frame 2)", will(H, bot, c) == true)
	T = 101
	check("eps fixed for the creep's lifetime (frame 3)", will(H, bot, c) == true)
	local same = true
	for _ = 1, 20 do if will(H, bot, c) ~= true then same = false end end
	check("decision stable across calls and frames", same)

	local fresh = MakeCreep(11)
	rolls(0, 0)
	check("fresh roll for a new handle", will(H, bot, fresh) == false)

	local low = MakeCreep(10)
	rolls(0, 0)
	check("negative eps swings late", will(H, bot, low) == false)
end

do
	local H, botA = Setup(0)
	local botB = MakeUnit({ pid = 2 })
	H.Profile.Get(botB)
	local c = MakeCreep(11)
	rolls(1, 0)
	local a = will(H, botA, c)
	rolls(0, 0)
	local b = will(H, botB, c)
	check("per-bot rolls are independent", a == true and b == false, tostring(a) .. "/" .. tostring(b))
end

-- A failed attempt roll means the bot does not go for that creep at all, however killable it is.
do
	local H, bot = Setup(0)
	local c = MakeCreep(5)
	rolls(0.5, 0.99)
	check("failed attempt roll skips a killable creep", will(H, bot, c) == false)
end

do
	math.randomseed(7)
	local H, bot = Setup(0)
	local stub = RandomFloat
	RandomFloat = function(a, b) return a + (b - a) * math.random() end
	local tries, denies, n = 0, 0, 2000
	for _ = 1, n do
		if will(H, bot, MakeCreep(1), 10, false) then tries = tries + 1 end
		if will(H, bot, MakeCreep(1), 10, true) then denies = denies + 1 end
	end
	RandomFloat = stub
	check("last-hit attempt rate at skill 0", math.abs(tries / n - 0.75) < 0.04, tries / n)
	check("deny attempt rate at skill 0", math.abs(denies / n - 0.35) < 0.04, denies / n)
end

do
	local H, bot = Setup(0)
	bot.pressured = true
	check("hero damage scales e", near(H.LastHitSkill.ErrorWidth(bot), 0.225), H.LastHitSkill.ErrorWidth(bot))
	bot.pressured = false
	T = 101
	check("e drops back once the pressure ends", near(H.LastHitSkill.ErrorWidth(bot), 0.15), H.LastHitSkill.ErrorWidth(bot))
	bot.target = MakeUnit({ pid = 7, team = 3 })
	T = 102
	check("harassing scales e", near(H.LastHitSkill.ErrorWidth(bot), 0.225), H.LastHitSkill.ErrorWidth(bot))
	-- Turning to a creep must not end harass pressure at once, or the last-hit answer flips its own input.
	bot.target = MakeCreep(50)
	T = 103
	check("harass pressure lasts after turning to a creep", near(H.LastHitSkill.ErrorWidth(bot), 0.225), H.LastHitSkill.ErrorWidth(bot))
	T = 104.5
	check("harass pressure ends after PressureSeconds", near(H.LastHitSkill.ErrorWidth(bot), 0.15), H.LastHitSkill.ErrorWidth(bot))

	-- The stored eps is unit-scaled, so pressure widens the error on a creep rolled before it began.
	local c = MakeCreep(12)
	rolls(1, 0)
	check("unpressured eps=+1 misses a 12 hp creep", will(H, bot, c) == false)
	bot.pressured = true
	T = 105
	check("pressure scales e at use time", will(H, bot, c) == true)
end

do
	local H, bot = Setup(0, { Enable = true, RequireOwnedLaning = true })
	local c = MakeCreep(11)
	rolls(1, 0)
	check("Valve-laning bot gets upstream", will(H, bot, c) == false)
	H.LastHitSkill.NoteLaningOwner(bot, true)
	local c2 = MakeCreep(11)
	rolls(1, 0)
	check("owned-laning bot gets the skill", will(H, bot, c2) == true)

	local other = MakeUnit({ pid = 3 })
	local printed = {}
	local realPrint = print
	print = function(s) table.insert(printed, s) end
	H.LastHitSkill.NoteLaningOwner(other, false)
	H.LastHitSkill.NoteLaningOwner(other, false)
	print = realPrint
	check("Valve-laning warning printed once", #printed == 1 and string.find(printed[1], "pid=3", 1, true) ~= nil, printed[1])
end

-- Task 2: ranged preference among creeps killable together, owned-laning wiring.
do
	local melee, ranged = MakeCreep(5), MakeCreep(5, "npc_dota_creep_badguys_ranged")
	local siege = MakeCreep(5, "npc_dota_badguys_siege")
	local H, bot = Setup(0.5)
	check("Choose keeps upstream order at skill 0.5", H.LastHitSkill.Choose(bot, { melee, ranged }) == melee)
	H, bot = Setup(1)
	check("Choose keeps upstream order at skill 1.0", H.LastHitSkill.Choose(bot, { melee, ranged }) == melee)
	H, bot = Setup(0.7)
	check("Choose prefers ranged above 0.6", H.LastHitSkill.Choose(bot, { melee, ranged }) == ranged)
	check("Choose prefers siege above 0.6", H.LastHitSkill.Choose(bot, { melee, siege }) == siege)
	check("Choose falls back to the first creep", H.LastHitSkill.Choose(bot, { melee }) == melee)
	H, bot = Setup(0.7, { Enable = false })
	check("Choose keeps upstream order when disabled", H.LastHitSkill.Choose(bot, { melee, ranged }) == melee)
end

do
	local H, bot = Setup(0)
	H.Trainer.IsSelfTestBot = function() return true end
	check("trainer self-test bot stays exact", H.LastHitSkill.IsActiveFor(bot) == false)
end

local function source(path)
	local f = io.open(HARNESS_DIR .. "/../../" .. path, "r")
	local text = f:read("*a")
	f:close()
	return text
end
local function has(text, s) return string.find(text, s, 1, true) ~= nil end

do
	local laning = source("bots/mode_laning_generic.lua")
	check("laning last hit pin", has(laning, "LastHitSkill.WillKill(bot, creep, attackDamage, nDelay, false)"))
	check("laning move-to lookahead pin", has(laning, "LastHitSkill.WillKill(bot, creep, attackDamage + dmgDelta, nDelay, false)"))
	check("laning deny pin", has(laning, "LastHitSkill.WillKill(bot, creep, attackDamage, 0, true)"))
	check("laning owner noted at load", has(laning, "LastHitSkill.NoteLaningOwner(bot, bOwnsThink)"))
	check("laning bare kill checks gone", not has(laning, "J.WillKillTarget(creep, attackDamage"))
	local mid = source("bots/FunLib/humaniser/lane_mid.lua")
	check("mid ranged deny pin", has(mid, "LastHitSkill.WillKill("))
end

do
	local roam = source("bots/mode_team_roam_generic.lua")
	check("team roam last-hit grab pin", has(roam, "LastHitSkill.WillKill(bot, creep, bot:GetAttackDamage()-1, nDelay, false)"))
	check("team roam bare kill check gone", not has(roam, "J.WillKillTarget(creep, bot:GetAttackDamage()-1"))
end

-- Task 4: an attempt is a swing the bot issued (NoteAttempt); kills are credited per tick from the counter delta.
local function swing(H, bot, creep, isDeny)
	rolls(0.5, 0)
	will(H, bot, creep, 10, isDeny)
	H.LastHitSkill.NoteAttempt(bot, creep)
end
local function counts(H, bot) local n = H.LastHitSkill.Counts(bot) return n.attempts .. "/" .. n.misses end
do
	local H, bot = Setup(0)
	T = 100
	H.LastHitSkill.Tick(bot)

	local probe = MakeCreep(5)
	rolls(0.5, 0)
	will(H, bot, probe)
	probe.hp = 0
	T = 101
	H.LastHitSkill.Tick(bot)
	check("a kill check without a swing is not an attempt", counts(H, bot) == "0/0", counts(H, bot))

	local c = MakeCreep(5)
	for _ = 1, 3 do swing(H, bot, c) end
	c.hp, bot.lastHits = 0, 1
	T = 102
	H.LastHitSkill.Tick(bot)
	check("attempt counted once per creep", counts(H, bot) == "1/0", counts(H, bot))

	local removed = MakeCreep(5)
	swing(H, bot, removed)
	removed.removed = true
	T = 103
	H.LastHitSkill.Tick(bot)
	check("miss when another unit took it", counts(H, bot) == "2/1", counts(H, bot))

	local a, b = MakeCreep(5), MakeCreep(5)
	swing(H, bot, a)
	swing(H, bot, b)
	b.hp, bot.lastHits = 0, 2
	T = 104
	H.LastHitSkill.Tick(bot)
	a.hp = 0
	T = 105
	H.LastHitSkill.Tick(bot)
	check("a last hit on another creep does not hide a miss", counts(H, bot) == "4/2", counts(H, bot))

	local x, y = MakeCreep(5), MakeCreep(5)
	swing(H, bot, x)
	swing(H, bot, y)
	x.hp, y.hp, bot.lastHits = 0, 0, 3
	T = 106
	H.LastHitSkill.Tick(bot)
	check("two attempts resolved in one tick share one kill", counts(H, bot) == "6/3", counts(H, bot))

	local d = MakeCreep(5)
	swing(H, bot, d, true)
	d.hp, bot.lastHits = 0, 4
	T = 107
	H.LastHitSkill.Tick(bot)
	check("deny miss uses GetDenies", counts(H, bot) == "7/4", counts(H, bot))

	local live = MakeCreep(5)
	swing(H, bot, live)
	T = 108
	H.LastHitSkill.Tick(bot)
	check("a live attempted creep is not resolved yet", counts(H, bot) == "7/4", counts(H, bot))
end

do
	local roam = source("bots/mode_team_roam_generic.lua")
	check("team roam notes its swing", has(roam, "J.Humaniser.LastHitSkill.NoteAttempt(bot, hTargetCreep)"))
	local laning = source("bots/mode_laning_generic.lua")
	check("laning notes its last-hit swing", has(laning, "LastHitSkill.NoteAttempt(bot, hitCreep)"))
	check("laning notes its deny swing", has(laning, "LastHitSkill.NoteAttempt(bot, denyCreep)"))
end

finish()
