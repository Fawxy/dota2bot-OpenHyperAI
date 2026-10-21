-- Minimal Dota bot-API stubs so humaniser modules can be loaded and exercised outside the game.
T = 0
GAME_STATE = 8
DIFFICULTY_INVALID, DIFFICULTY_PASSIVE, DIFFICULTY_EASY, DIFFICULTY_MEDIUM, DIFFICULTY_HARD, DIFFICULTY_UNFAIR = -1, 0, 1, 2, 3, 4
GAME_STATE_GAME_IN_PROGRESS = 8
GAME_STATE_PRE_GAME = 7
BOT_MODE_ASSEMBLE = 14
BOT_MODE_RETREAT = 4
function GetScriptDirectory() return "bots" end
function GameTime() return T end
function DotaTime() return T end
function GetGameState() return GAME_STATE end
function RandomFloat(a, b) return a + (b - a) * (RANDOM_FRACTION or 0.5) end
function RandomInt(a, b) return a end
function DebugDrawText() end
function DebugDrawCircle() end
CHAT_CALLBACKS = {}
function InstallChatCallback(fn) table.insert(CHAT_CALLBACKS, fn) end
function Vector(x, y, z) return { x = x, y = y, z = z or 0 } end

UNITS = { [2] = {}, [3] = {} }
CURRENT_TEAM = 2
function GetTeam() return CURRENT_TEAM end
function GetTeamPlayers(team) local r = {} for _, u in ipairs(UNITS[team]) do table.insert(r, u.pid) end return r end
function GetTeamMember(i) return UNITS[CURRENT_TEAM][i] end
function IsPlayerBot(pid) for t = 2, 3 do for _, u in ipairs(UNITS[t]) do if u.pid == pid then return u.bot end end end return true end
function GetUnitToLocationDistance(u, loc) local dx, dy = u.loc.x - loc.x, u.loc.y - loc.y return math.sqrt(dx * dx + dy * dy) end

local Unit = {}
Unit.__index = Unit
function Unit:GetAssignedLane() return self.lane or 0 end
function Unit:GetPlayerID() return self.pid end
function Unit:GetTeam() return self.team end
function Unit:IsBot() return self.bot end
function Unit:IsIllusion() return false end
function Unit:IsHero() return true end
function Unit:IsAlive() return self.alive end
function Unit:CanBeSeen() return true end
function Unit:GetLocation() return self.loc end
function Unit:GetUnitName() return "npc_dota_hero_" .. self.pid end
function Unit:GetDifficulty() return self.difficulty end
function Unit:GetLevel() return self.level end
function Unit:HasModifier(name) return self.modifiers[name] ~= nil end
function Unit:GetModifierByName(name) if self.modifiers[name] then return 1 end return -1 end
function Unit:GetModifierStackCount(i) for _, v in pairs(self.modifiers) do return v end return 0 end
function Unit:IsChanneling() return false end
function Unit:GetActiveMode() return self.mode end
function Unit:GetActiveModeDesire() return self.desire or 0 end
function Unit:GetHealth() return self.hp end
function Unit:GetMaxHealth() return 100 end
function Unit:GetItemInSlot() return nil end
-- Intent arbitration (task 09): action queue, busy states and fountain distance.
BOT_ACTION_TYPE_NONE, BOT_ACTION_TYPE_IDLE, BOT_ACTION_TYPE_MOVE_TO = 0, 1, 2
function Unit:GetCurrentActionType() return self.action or BOT_ACTION_TYPE_IDLE end
function Unit:NumQueuedActions() return 0 end
function Unit:IsUsingAbility() return false end
function Unit:IsCastingAbility() return false end
function Unit:IsStunned() return false end
function Unit:IsHexed() return false end
function Unit:DistanceFromFountain() return self.fountainDist or 8000 end
-- tasks: unit API used by the lua-tasks verbs. Moves are recorded per unit.
function Unit:GetLastHits() return self.lastHits or 0 end
function Unit:GetAttackRange() return self.range or 150 end
function Unit:Action_MoveToLocation(loc) self.moves = self.moves or {} table.insert(self.moves, loc) end
ANCIENT = { IsAlive = function() return true end, GetHealth = function() return 4500 end }
function GetAncient() return ANCIENT end

function MakeUnit(o)
	local u = setmetatable({
		pid = o.pid, team = o.team or 2, bot = o.bot ~= false, alive = o.alive ~= false,
		loc = o.loc or Vector(0, 0), difficulty = o.difficulty or DIFFICULTY_MEDIUM,
		level = o.level or 1, modifiers = o.modifiers or {}, mode = o.mode or 0, hp = o.hp or 100,
	}, Unit)
	table.insert(UNITS[u.team], u)
	return u
end

function ResetWorld() UNITS = { [2] = {}, [3] = {} } CHAT_CALLBACKS = {} T = 0 GAME_STATE = 8 end

FAILS, PASSES = 0, 0
function check(name, cond, detail)
	if cond then PASSES = PASSES + 1 else FAILS = FAILS + 1 print("FAIL: " .. name .. (detail and (" -- " .. tostring(detail)) or "")) end
end
function near(a, b) return math.abs(a - b) < 1e-6 end
function finish() print(string.format("%d passed, %d failed", PASSES, FAILS)) if FAILS > 0 then error("tests failed") end end

-- Each fresh require of the humaniser gives a new module instance (as if modules were per-bot).
function FreshHumaniser(customHumaniser)
	for k in pairs(package.loaded) do
		if k:find("humaniser") or k:find("Customize") or k:find("custom_loader") then package.loaded[k] = nil end
	end
	local Customize = require("bots.Customize.general")
	Customize.Humaniser = customHumaniser
	package.loaded["bots/FunLib/custom_loader"] = Customize
	return require("bots/FunLib/humaniser/index")
end
