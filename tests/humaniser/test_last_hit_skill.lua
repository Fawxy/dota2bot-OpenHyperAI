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
	bot.target = MakeCreep(50)
	T = 103
	check("a creep target is not harassing", near(H.LastHitSkill.ErrorWidth(bot), 0.15), H.LastHitSkill.ErrorWidth(bot))

	-- The stored eps is unit-scaled, so pressure widens the error on a creep rolled before it began.
	local c = MakeCreep(12)
	rolls(1, 0)
	check("unpressured eps=+1 misses a 12 hp creep", will(H, bot, c) == false)
	bot.pressured = true
	T = 104
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

finish()
