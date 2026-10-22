-- Plays two FarmPattern trips through the real modules with telemetry on and returns the [HEV] lines in HLOG_LINES:
-- one left unfinished at leaveBy and walked back, one pre-empted by the rune mode, then a farm_gate while the wave
-- is up. Driven from tools/hlog/test to check the Lua -> analyser contract for farm_trip_* and farm_gate events.
dofile(HARNESS_DIR .. "/lane_world.lua")
local dota = require("bots/ts_libs/dota/index")
local Lane, BotMode = dota.Lane, dota.BotMode

local FRONT, SMALL = Vector(0, -5000), Vector(0, -6200)
local H = LaneFresh({ Enable = true, PullTiming = { LanePaths = { dire_bot = { { 3250, -5000 }, { -7000, -5000 } } } } },
	{ skill = 0.9, telemetry = { Enable = true } })
HLOG_LINES = {}
H.Telemetry.SetSink(function(line) table.insert(HLOG_LINES, line) end)
CURRENT_TEAM, OBSERVER = 2, 1
SPAWNERS = { { team = 2, type = "small", location = Vector(SMALL.x, SMALL.y, 0), min = Vector(-150, -6350, 0), max = Vector(150, -6050, 0), speed = 0 } }
H.Lane.Camps.ResetCache()
H.FarmPattern.ResetCache()
local core = MakeUnit({ pid = 1, team = 2, loc = FRONT, level = 6, mode = BotMode.Laning })
core.lane, core.pos = Lane.Bot, 1
MakeUnit({ pid = 10, team = 3, loc = Vector(6000, 6000) }).pos = 3
local neutral = MakeNeutral({ x = SMALL.x, y = SMALL.y })

-- Trip 1 (7:25): walk in, farm until leaveBy (7:41), walk back, end at the front.
T = 445
H.FarmPattern.Desire(core)
core.mode, core.loc = BotMode.Farm, SMALL
H.FarmPattern.Think(core)
T = 461.5
H.FarmPattern.Desire(core)
H.FarmPattern.Think(core)
core.loc = Vector(0, -5300)
T = 463
H.FarmPattern.Desire(core)

-- Trip 2 (8:25, camp respawned): the rune mode takes over and farm stops thinking.
neutral.hp = 300
core.loc, core.mode = FRONT, BotMode.Laning
T = 505
H.FarmPattern.Desire(core)
core.mode = BotMode.Farm
H.FarmPattern.Think(core)
core.mode = BotMode.Rune
H.FarmPattern.OnEnd(core)
T = 507.5
H.FarmPattern.Desire(core)

-- 9:05: the camp is up but the wave is alive at the front, so no trip; farm_gate says why.
core.mode, core.loc = BotMode.Laning, FRONT
MakeCreep({ team = 3, x = 200, y = -5000 })
T = 545
H.FarmPattern.Desire(core)
