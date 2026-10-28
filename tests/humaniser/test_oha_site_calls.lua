-- Every J.Site.<fn>( call in the OHA entry files names a function aba_site defines (slice 1, H.1). A call to an undefined
-- J.Site.IsCampDangerous in farm Think raised on every nearer camp: 19 console "error in error handling" lines per game,
-- attributed in ~/.dotactl/logs/2026-10-28T21-09-28-s1p_A_on_1.log (first at t=635.2, ev=lua_error where=oha.mode_farm.Think).
dofile(HARNESS_DIR .. "/dota_stubs.lua")

local function read(rel) return io.open(BOTS_ROOT .. "/bots/" .. rel, "r"):read("a") end

local site = read("FunLib/aba_site.lua")
local defined = {}
for name in site:gmatch("\n____exports%.([%w_]+) = ") do defined[name] = true end
check("aba_site exports found", defined.GetClosestNeutralSpwan == true)

local files = { "mode_farm_generic.lua", "mode_laning_generic.lua", "mode_retreat_generic.lua", "mode_roam_generic.lua",
	"mode_rune_generic.lua", "mode_team_roam_generic.lua", "mode_ward_generic.lua", "mode_assemble_generic.lua",
	"mode_outpost_generic.lua", "mode_roshan_generic.lua", "mode_secret_shop_generic.lua", "mode_side_shop_generic.lua",
	"item_purchase_generic.lua", "ability_item_usage_generic.lua", "FunLib/jmz_func.lua", "FunLib/aba_push.lua",
	"FunLib/aba_defend.lua" }
local calls = 0
for _, f in ipairs(files) do
	for line in (read(f) .. "\n"):gmatch("([^\n]*)\n") do
		local code = line:gsub("%-%-.*$", "")
		for name in code:gmatch("J%.Site%.([%w_]+)%s*%(") do
			calls = calls + 1
			check(f .. " calls a defined J.Site." .. name, defined[name] == true)
		end
	end
end
check("J.Site calls found", calls > 0, calls)

finish()
