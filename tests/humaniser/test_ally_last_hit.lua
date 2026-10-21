dofile(HARNESS_DIR .. "/dota_stubs.lua")

ACTIVITY_IDLE, ACTIVITY_RUN, ACTIVITY_ATTACK, ACTIVITY_ATTACK2 = 1500, 1502, 1503, 1504
LANE_TOP, LANE_MID, LANE_BOT = 1, 2, 3

local function dist(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
function GetUnitToUnitDistance(a, b) return dist(a.loc, b.loc) end

-- Extra unit API used by the etiquette module, added to the shared stub metatable.
local Unit = getmetatable(MakeUnit({ pid = 99 })).__index
function Unit:GetAttackRange() return self.range or 150 end
function Unit:GetAttackTarget() return self.target end
function Unit:GetLastAttackTime() return self.lastAttack or -100 end
function Unit:GetAnimActivity() return self.anim or ACTIVITY_IDLE end
function Unit:GetExtrapolatedLocation() return self.heading or self.loc end
function Unit:GetAssignedLane() return self.lane or LANE_BOT end
function Unit:GetNearbyHeroes() return ENEMY_HEROES end
function Unit:GetNearbyLaneCreeps() return ENEMY_CREEPS end
function Unit:GetMaxHealth() return self.maxhp or 100 end

local Creep = {}
Creep.__index = Creep
function Creep:GetTeam() return self.team end
function Creep:GetLocation() return self.loc end
function Creep:GetHealth() return self.hp end
function Creep:GetMaxHealth() return 100 end
function Creep:IsAlive() return true end
local function MakeCreep(team, x, hp) return setmetatable({ team = team, loc = Vector(x, 0), hp = hp or 40 }, Creep) end

local LANING = true

-- Radiant: human (pos humanPos) at the origin, allied bot (pos botPos) beside it. skill picks the deference tier.
local function Setup(o)
	o = o or {}
	ResetWorld()
	ENEMY_HEROES, ENEMY_CREEPS = {}, {}
	LANING = o.laning ~= false
	T = 100
	local humaniser = o.humaniser or { Enable = true, SkillOverride = o.skill or 0, AllyLastHit = o.allyLastHit or { Enable = true } }
	local H = FreshHumaniser(humaniser)
	H.AllyLastHit.SetHelpers({ GetPosition = function(u) return u.pos end, IsInLaningPhase = function() return LANING end })
	local human = MakeUnit({ pid = 0, bot = false, loc = Vector(0, 0) })
	human.pos, human.range, human.lastAttack = o.humanPos or 1, 150, T - 1
	local bot = MakeUnit({ pid = 1, loc = Vector(-200, 0) })
	bot.pos = o.botPos or 5
	return H, human, bot
end

local function may(H, bot, creep) return H.AllyLastHit.MayLastHit(bot, creep) end

-- Polite: never last-hits near a protected human, but may deny.
do
	local H, human, bot = Setup({ skill = 0 })
	local creep = MakeCreep(3, 100)
	local ok, reason = may(H, bot, creep)
	check("polite skips enemy creep", ok == false and reason == "skip: polite", reason)
	check("polite skips even when human is idle", (function() human.lastAttack = T - 10 return may(H, bot, creep) == false end)())
	local ok2, reason2 = may(H, bot, MakeCreep(2, 100))
	check("polite may deny", ok2 == true and reason2 == "free: deny", reason2)
end

-- No protection without a human in range, or outside the laning phase.
do
	local H, _, bot = Setup({ skill = 0 })
	local ok, reason = may(H, bot, MakeCreep(3, 1500))
	check("human out of protect range", ok == true and reason == "free: no-human", reason)
	LANING = false
	local ok2, reason2 = may(H, bot, MakeCreep(3, 100))
	check("no protection after laning", ok2 == true and reason2 == "free: not-laning", reason2)
end

-- Dead humans are not protected.
do
	local H, human, bot = Setup({ skill = 0 })
	human.alive = false
	check("dead human not protected", may(H, bot, MakeCreep(3, 100)) == true)
end

-- Helpful: holds back while the human is active and in reach; takes when the human can't or won't.
do
	local H, human, bot = Setup({ skill = 0.5 })
	check("tier helpful", H.AllyLastHit.GetTier(bot) == "helpful", H.AllyLastHit.GetTier(bot))
	local near = MakeCreep(3, 200)
	local ok, reason = may(H, bot, near)
	check("helpful holds back for active human", ok == false and reason == "skip: helpful", reason)

	local far = MakeCreep(3, 600)
	local ok2, reason2 = may(H, bot, far)
	check("helpful takes when human out of range", ok2 == true and reason2 == "take: human-away", reason2)
	human.heading = Vector(200, 0)
	check("helpful holds back when human walks toward the creep", may(H, bot, far) == false)
	human.heading = nil

	human.lastAttack = T - 4
	local ok3, reason3 = may(H, bot, near)
	check("helpful takes when human idle", ok3 == true and reason3 == "take: human-idle", reason3)
	human.lastAttack = T - 1

	local enemy = MakeUnit({ pid = 5, team = 3, loc = Vector(300, 0) })
	ENEMY_HEROES = { enemy }
	enemy.target = near
	T = T + 0.1 -- nearby heroes are cached per frame
	local ok4, reason4 = may(H, bot, near)
	check("helpful takes a creep about to be denied", ok4 == true and reason4 == "take: deny-race", reason4)
	near.hp = 60
	check("not a deny race above deniable health", may(H, bot, near) == false)

	near.hp = 40
	human.target = near
	local ok5, reason5 = may(H, bot, near)
	check("helpful never takes the human's target", ok5 == false and reason5 == "skip: human-target", reason5)
end

-- Teammate: normal last-hitting except the human's target, and the lowest creep in range mid-swing.
do
	local H, human, bot = Setup({ skill = 1 })
	local a, b = MakeCreep(3, 100, 30), MakeCreep(3, 120, 50)
	ENEMY_CREEPS = { a, b }
	human.target = a
	local ok, reason = may(H, bot, a)
	check("teammate skips human's target", ok == false and reason == "skip: human-target", reason)
	local ok2, reason2 = may(H, bot, b)
	check("teammate takes other creeps", ok2 == true and reason2 == "take: teammate", reason2)

	human.target = nil
	human.anim = ACTIVITY_ATTACK
	local ok3, reason3 = may(H, bot, a)
	check("teammate skips lowest creep in range mid-swing", ok3 == false and reason3 == "skip: human-swing", reason3)
	check("teammate takes higher-HP creep mid-swing", may(H, bot, b) == true)
	human.anim = ACTIVITY_RUN
	check("teammate takes lowest creep when human not swinging", may(H, bot, a) == true)

	human.anim = ACTIVITY_ATTACK
	local farLow = MakeCreep(3, 700, 10)
	ENEMY_CREEPS = { a, b, farLow }
	T = T + 0.1
	check("lowest is judged within human range only", may(H, bot, a) == false and may(H, bot, farLow) == true)
end

-- Position rules: human supports are not protected; bot cores keep their farm outside the human's lane.
do
	local H, _, bot = Setup({ skill = 0, humanPos = 5, botPos = 1 })
	local ok, reason = may(H, bot, MakeCreep(3, 100))
	check("human pos 5 not protected", ok == true and reason == "free: no-human", reason)

	local H2, human2, bot2 = Setup({ skill = 0, humanPos = 3, botPos = 1 })
	human2.lane, bot2.lane = LANE_TOP, LANE_BOT
	local ok2, reason2 = may(H2, bot2, MakeCreep(3, 100))
	check("bot core keeps own lane farm", ok2 == true and reason2 == "free: own-lane", reason2)
	human2.lane = LANE_BOT
	check("bot core defers in the human's lane", may(H2, bot2, MakeCreep(3, 100)) == false)

	local H3, _, bot3 = Setup({ skill = 0, humanPos = 3, botPos = 4 })
	bot3.lane = LANE_TOP
	check("supports defer regardless of lane", may(H3, bot3, MakeCreep(3, 100)) == false)
end

-- Config: protected positions and tier thresholds are tuneable.
do
	local H, _, bot = Setup({ skill = 0, humanPos = 2, allyLastHit = { Enable = true, ProtectPositions = { 1 } } })
	check("ProtectPositions replaces the default list", may(H, bot, MakeCreep(3, 100)) == true)

	local H2, _, bot2 = Setup({ skill = 0.15, allyLastHit = { Enable = true, PoliteMin = 0.9 } })
	check("PoliteMin threshold respected", H2.AllyLastHit.GetTier(bot2) == "helpful", H2.AllyLastHit.GetTier(bot2))
	local H3, _, bot3 = Setup({ skill = 0.15 })
	check("default thresholds: d=0.85 is polite", H3.AllyLastHit.GetTier(bot3) == "polite", H3.AllyLastHit.GetTier(bot3))
end

-- Kill switches: always allowed, FilterCreeps passes the list through untouched, laning not owned.
for _, case in ipairs({
	{ name = "AllyLastHit off", humaniser = { Enable = true, SkillOverride = 0, AllyLastHit = { Enable = false } } },
	{ name = "Humaniser off", humaniser = { Enable = false, SkillOverride = 0, AllyLastHit = { Enable = true } } },
}) do
	local H, _, bot = Setup({ humaniser = case.humaniser })
	local list = { MakeCreep(3, 100) }
	local ok, reason = may(H, bot, list[1])
	check(case.name .. ": allowed", ok == true and reason == "free: disabled", reason)
	check(case.name .. ": filter is identity", H.AllyLastHit.FilterCreeps(bot, list) == list)
	check(case.name .. ": laning not owned", H.AllyLastHit.OwnsLaning(bot) == false)
end

-- Enabled: FilterCreeps drops protected creeps and keeps denies; laning owned only on a team with a human.
do
	local H, _, bot = Setup({ skill = 0 })
	local enemyCreep, allyCreep, farCreep = MakeCreep(3, 100), MakeCreep(2, 100), MakeCreep(3, 1500)
	local kept = H.AllyLastHit.FilterCreeps(bot, { enemyCreep, allyCreep, farCreep })
	check("filter keeps deny and unprotected creeps", #kept == 2 and kept[1] == allyCreep and kept[2] == farCreep, #kept)
	check("laning owned with a human ally", H.AllyLastHit.OwnsLaning(bot) == true)
	local dire = MakeUnit({ pid = 6, team = 3 })
	check("laning not owned without a human ally", H.AllyLastHit.OwnsLaning(dire) == false)
end

finish()
