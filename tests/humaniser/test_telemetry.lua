dofile(HARNESS_DIR .. "/dota_stubs.lua")
local dota = require("bots/ts_libs/dota/index")
local BotMode = dota.BotMode

local UnitMeta = getmetatable(MakeUnit({ pid = 99, team = 3 })).__index
function UnitMeta:GetLastHits() return self.lh or 0 end
function UnitMeta:GetDenies() return self.dn or 0 end
function UnitMeta:GetAttackTarget() return self.target end
function UnitMeta:GetMana() return 50 end
function UnitMeta:GetMaxMana() return 100 end
function UnitMeta:GetGold() return 600 end
function UnitMeta:ActionImmediate_Chat(line) self.said = self.said or {} table.insert(self.said, line) end

local lines
local function fresh(telemetry)
	ResetWorld()
	local H = FreshHumaniser({ Enable = true, Telemetry = telemetry or { Enable = true } })
	lines = {}
	H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
	return H
end
local function events(name)
	local r = {}
	for _, l in ipairs(lines) do if l:find(" ev=" .. name .. " ", 1, true) or l:sub(-#name - 4) == " ev=" .. name then table.insert(r, l) end end
	return r
end
local function field(line, key) return line:match(" " .. key .. '="([^"]*)"') or line:match(" " .. key .. "=(%S+)") end
local function say(pid, text)
	T = T + 0.5
	for _, cb in ipairs(CHAT_CALLBACKS) do cb({ player_id = pid, string = text, team_only = true }) end
end
local function creep(name) return { GetUnitName = function() return name end } end

-- Kill switch: the Customize default is off, and then nothing is printed whatever happens.
do
	local H = fresh({})
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning })
	H.Telemetry.Tick(b)
	b.mode = BotMode.Farm
	T = 2
	H.Telemetry.Tick(b)
	H.Telemetry.Event("notice", { { "pid", 1 } })
	check("disabled prints nothing", #lines == 0, #lines)
end

-- Values with spaces, quotes or '=' survive as one quoted field; tools/hlog parses the same rule.
do
	local H = fresh()
	local line = H.Telemetry.FormatLine("cmd", { { "text", 'say "hi" a=b' }, { "n", 3 }, { "d", 0.5 }, { "ok", true }, { "skip", nil } })
	check("quoted text", field(line, "text") == "say 'hi' a=b", line)
	check("integer bare", field(line, "n") == "3", line)
	check("float 3dp", field(line, "d") == "0.500", line)
	check("bool as 1", field(line, "ok") == "1", line)
	check("nil field omitted", not line:find("skip=", 1, true), line)
end

-- Snapshots are throttled to SnapshotInterval; mode switches report the previous mode's dwell.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1, mode = BotMode.Laning })
	for i = 0, 20 do
		T = i * 0.1
		H.Telemetry.Tick(b)
	end
	check("snapshots throttled", #events("snap") == 3, #events("snap"))
	b.mode = BotMode.Farm
	T = 2.5
	H.Telemetry.Tick(b)
	local m = events("mode")
	check("one mode event", #m == 1, #m)
	check("mode from/to", m[1] and field(m[1], "from") == "laning" and field(m[1], "to") == "farm", m[1])
	check("mode dwell", m[1] and math.abs(tonumber(field(m[1], "dwell")) - 2.5) < 1e-6, m[1])
	check("profile reported once", #events("bot") == 1, #events("bot"))
end

-- A last hit is attributed to the etiquette decision on the creep the bot was attacking the frame before.
do
	local H = fresh()
	local b = MakeUnit({ pid = 1 })
	local c = creep("npc_dota_creep_badguys_melee")
	H.Telemetry.Tick(b)
	b.target = c
	T = 0.1
	H.Telemetry.NoteLastHitDecision(b, c, false, "skip: core")
	H.Telemetry.Tick(b)
	b.lh, b.target = 1, nil
	T = 0.2
	H.Telemetry.Tick(b)
	local lh = events("lasthit")
	check("lasthit emitted", #lh == 1, #lh)
	check("lasthit carries decision", lh[1] and field(lh[1], "dec") == "skip: core", lh[1])
	check("lasthit creep", lh[1] and field(lh[1], "creep") == "npc_dota_creep_badguys_melee", lh[1])

	-- A decision older than DecisionMaxAge says nothing about this kill.
	local c2 = creep("npc_dota_creep_badguys_ranged")
	b.target = c2
	H.Telemetry.NoteLastHitDecision(b, c2, false, "skip: core")
	T = 0.3
	H.Telemetry.Tick(b)
	b.lh = 2
	T = 2
	H.Telemetry.Tick(b)
	lh = events("lasthit")
	check("stale decision not attributed", lh[2] and field(lh[2], "dec") == nil, lh[2])
end

-- Human allies' last hits are tracked by the team's lowest-PID bot only.
do
	local H = fresh()
	local human = MakeUnit({ pid = 0, bot = false })
	local b1, b2 = MakeUnit({ pid = 1 }), MakeUnit({ pid = 2 })
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	human.lh = 1
	T = 0.1
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	local lh = events("lasthit")
	check("human last hit once", #lh == 1 and field(lh[1], "pid") == "0" and field(lh[1], "human") == "1", table.concat(lh, "\n"))
	check("human announced", #events("player") == 1, #events("player"))
end

-- !mark: one mark line and ack from the lowest-PID bot, one state line per bot, nothing repeated.
do
	local H = fresh()
	MakeUnit({ pid = 0, bot = false })
	local b1, b2 = MakeUnit({ pid = 1, mode = BotMode.Farm }), MakeUnit({ pid = 2, mode = BotMode.Laning })
	H.Chat.EnsureInstalled(b1)
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	say(0, "!mark pos4 walked into tower")
	say(0, "!marker not a mark")
	say(1, "!mark from a bot")
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	T = T + 0.1
	H.Telemetry.Tick(b1)
	H.Telemetry.Tick(b2)
	local marks, states = events("mark"), events("mark_state")
	check("one mark", #marks == 1, table.concat(marks, "\n"))
	check("mark text", marks[1] and field(marks[1], "text") == "pos4 walked into tower", marks[1])
	check("mark state per bot", #states == 2, #states)
	check("mark state has mode", states[2] and field(states[2], "mode") == "laning", states[2])
	check("ack from lowest bot only", b1.said and #b1.said == 1 and b1.said[1] == "mark 1 saved" and b2.said == nil)

	H.Telemetry.Tick(b1)
	say(0, "!MARK")
	H.Telemetry.Tick(b1)
	check("empty mark numbered 2", #events("mark") == 2 and field(events("mark")[2], "n") == "2")
end

finish()
