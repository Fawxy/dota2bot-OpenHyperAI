dofile(HARNESS_DIR .. "/dota_stubs.lua")

-- Byte identity of the event line: a fixed sequence through Event and EventUntyped (field order, number formats, booleans,
-- quoting, skipped nil values). The expected lines were captured from team-bots before typed events (slice typed-events).
ResetWorld()
local H = FreshHumaniser({ Enable = true, Telemetry = { Enable = true } })
local lines = {}
H.Telemetry.SetSink(function(line) table.insert(lines, line) end)
T = 12.5

local SEQUENCE = {
	{ "lasthit", { { "pid", 3 }, { "human", false }, { "n", 7 }, { "creep", "npc_dota_creep_goodguys_melee" }, { "dec", "allowed" }, { "decAge", 0.25 } } },
	{ "mode", { { "pid", 1 }, { "from", "laning" }, { "to", "farm" }, { "d", 0.4567891 }, { "dwell", 12 }, { "by", nil } } },
	{ "cmd", { { "by", 2 }, { "team", 2 }, { "name", "defend" }, { "args", "a,b" }, { "only", nil }, { "text", 'say "hi" there' } } },
	{ "lane_job_abort", { { "pid", 4 }, { "kind", "stack" }, { "camp", 5 }, { "reason", "late" }, { "acted", true }, { "pre", 1 } } },
	{ "front", { { "team", 3 }, { "top", 123.4 }, { "topx", -1500 }, { "topy", 2200 } } },
	{ "creep_death", { { "team", 2 }, { "kind", "melee" }, { "hp", 0.05 }, { "p1t", true }, { "p1a", 0.5 } } },
	{ "snap", { { "pid", 2 }, { "x", -6000 }, { "y", -5800 }, { "alive", true }, { "hp", 97 }, { "ln", "bot" }, { "s", 0.123456 } } },
}
local UNTYPED = { "farm_trip_start", { { "pid", 2 }, { "camp", 3 }, { "waveAt", "75.0" } } }

for _, e in ipairs(SEQUENCE) do H.Telemetry.Event(e[1], e[2]) end
H.Telemetry.EventUntyped(UNTYPED[1], UNTYPED[2])

local EXPECTED = {
	"[HEV] t=12.500 ev=lasthit pid=3 human=0 n=7 creep=npc_dota_creep_goodguys_melee dec=allowed decAge=0.250",
	"[HEV] t=12.500 ev=mode pid=1 from=laning to=farm d=0.457 dwell=12",
	"[HEV] t=12.500 ev=cmd by=2 team=2 name=defend args=a,b text=\"say 'hi' there\"",
	"[HEV] t=12.500 ev=lane_job_abort pid=4 kind=stack camp=5 reason=late acted=1 pre=1",
	"[HEV] t=12.500 ev=front team=3 top=123.400 topx=-1500 topy=2200",
	"[HEV] t=12.500 ev=creep_death team=2 kind=melee hp=0.050 p1t=1 p1a=0.500",
	"[HEV] t=12.500 ev=snap pid=2 x=-6000 y=-5800 alive=1 hp=97 ln=bot s=0.123",
	"[HEV] t=12.500 ev=farm_trip_start pid=2 camp=3 waveAt=75.0",
}

check("event count", #lines == #SEQUENCE + 1, #lines)
for i, want in ipairs(EXPECTED) do
	check("line " .. i .. " byte for byte", lines[i] == want, tostring(lines[i]))
end

finish()
