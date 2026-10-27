-- Fixture: the Dire GetTeamPlayers cache in aba_global_overrides. In bots mode the first Dire calls saw an empty list;
-- caching it left all five Dire bots on role 1 and RoleByHero skipped Dire (log 2026-10-27T18-07-51-probe_role_s8_b, t=-90).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
TEAM_RADIANT, TEAM_DIRE = 2, 3
CDOTA_Bot_Script = CDOTA_Bot_Script or {}  -- the file wraps unit methods on load; this test only needs it to load

package.loaded["bots/FunLib/aba_global_overrides"] = nil
local harnessPrint = print
require("bots/FunLib/aba_global_overrides")
print = harnessPrint  -- the file gates print on Utils.DebugMode

local function count(t) local n = 0 for _ in pairs(t) do n = n + 1 end return n end

-- Hero selection: no Dire players yet.
UNITS[3] = {}
check("empty Dire list is returned", count(GetTeamPlayers(TEAM_DIRE)) == 0)

-- Players join later; the empty list must not have been cached.
for i = 1, 5 do table.insert(UNITS[3], { pid = 4 + i, bot = true, team = 3 }) end
local ids = GetTeamPlayers(TEAM_DIRE)
check("full Dire team seen after an early empty read", count(ids) == 5 and ids[1] == 5 and ids[5] == 9)

-- A full team is cached as before.
UNITS[3] = {}
check("full Dire team stays cached", count(GetTeamPlayers(TEAM_DIRE)) == 5)

-- Radiant is never cached.
UNITS[2] = {}
check("Radiant reads through", count(GetTeamPlayers(TEAM_RADIANT)) == 0)
for i = 1, 5 do table.insert(UNITS[2], { pid = i - 1, bot = true, team = 2 }) end
check("Radiant sees its team", count(GetTeamPlayers(TEAM_RADIANT)) == 5)
finish()
