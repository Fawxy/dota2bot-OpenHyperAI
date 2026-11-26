-- ev=bot `ours`: which Ours switches a game ran with, the only arm marker of a remote job (no --set).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Customize = package.loaded["bots/FunLib/custom_loader"]
-- The shipped defaults, not the suites' (dota_stubs.lua FreshHumaniser turns the features on).
package.loaded["bots/FunLib/humaniser/ours"] = nil
local Ours = require("bots/FunLib/humaniser/ours")
-- A game reads general.lua's block, which sets every key, so DEFAULTS alone do not say what ships (review).
package.loaded["bots.Customize.general"] = nil
local shipped = require("bots.Customize.general").Ours
-- Plan s5: a small row or a widening merges on as provisional until the checkpoint batch reads it; a row that beat the
-- reference arm in its own batch merges on.
local PROVISIONAL = { RuneDetour = true, SupportCreeps = true }
local ON = { SupportPull = true, LaneCreeps = true, CreepDeny = true, TowerCreeps = true }
local stray = {}
for name in pairs(Ours.DEFAULTS) do local on = PROVISIONAL[name] == true or ON[name] == true
	if shipped[name] ~= on or Ours.DEFAULTS[name] ~= on then stray[#stray + 1] = name end end
for name in pairs(shipped) do if Ours.DEFAULTS[name] == nil then stray[#stray + 1] = name end end
check("ours: general.lua's block has every DEFAULTS key and no other, all off but the provisional rows and those merged on", #stray == 0, table.concat(stray, ","))
Customize.Ours = { Retreat = false, MidWater = true, SupportPull = true }
-- One entry per DEFAULTS key in name order; a slice adding a switch adds it here.
check("ours: the switch as set", Ours.Describe() == "BurstReady:0,ChoiceShadow:0,CreepDeny:1,DoubleStack:0,ExitWindow:0,IdleBar:0,JobChooser:0,LaneCreeps:1,MidWater:1,Retreat:0,RuneDetour:1,RuneRotation:0,RuneSpawn:0,StackExecute:0,SupportCreeps:1,SupportPull:1,Sustain:0,Threat:0,TowerCreeps:1,TowerRead:0,TripRead:0", Ours.Describe())
Customize.Ours = {}
check("ours: a missing key takes its default, and every default is off but the provisional rows and those merged on", Ours.Describe() == "BurstReady:0,ChoiceShadow:0,CreepDeny:1,DoubleStack:0,ExitWindow:0,IdleBar:0,JobChooser:0,LaneCreeps:1,MidWater:0,Retreat:0,RuneDetour:1,RuneRotation:0,RuneSpawn:0,StackExecute:0,SupportCreeps:1,SupportPull:1,Sustain:0,Threat:0,TowerCreeps:1,TowerRead:0,TripRead:0", Ours.Describe())
Customize.Enable = nil
Customize.Ours = { Team = "radiant", Retreat = true, SupportPull = true }
CURRENT_TEAM = 2
check("ours: Team=radiant leaves Radiant on", Ours.On("Retreat") and Ours.On("SupportPull"))
CURRENT_TEAM = 3
check("ours: Team=radiant turns every switch off for Dire", not Ours.Describe():find(":1", 1, true), Ours.Describe())
Customize.Ours = { Team = "dire", Retreat = true, Threat = true }
check("ours: Team=dire leaves Dire on", Ours.On("Retreat") and Ours.On("Threat"))
CURRENT_TEAM = 2
check("ours: Team=dire turns every switch off for Radiant", not Ours.Describe():find(":1", 1, true), Ours.Describe())
Customize.Ours = { Team = "both", Retreat = true }
check("ours: any other Team value scopes nothing", Ours.On("Retreat"))
Customize.Ours = { Team = "Radiant", Retreat = true }
CURRENT_TEAM = 3
check("ours: Team is case-insensitive", not Ours.On("Retreat"))
Customize.Ours = { Team = 3, Retreat = true }
check("ours: Team=3 leaves Dire on", Ours.On("Retreat"))
CURRENT_TEAM = 2
check("ours: Team=3 turns Radiant off", not Ours.On("Retreat"))
Customize.Ours = { Team = "dire", Retreat = true }
check("ours: the scope wins over an explicit switch value", not Ours.On("Retreat"))
Customize.Ours = { Retreat = true, Threat = true }
Customize.Enable = false
check("ours: Customize.Enable = false turns every switch off", not Ours.Describe():find(":1", 1, true), Ours.Describe())
finish()
