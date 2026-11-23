-- ev=bot `ours`: which Ours switches a game ran with, the only arm marker of a remote job (no --set).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Customize = package.loaded["bots/FunLib/custom_loader"]
local Ours = require("bots/FunLib/humaniser/ours")
Customize.Ours = { Retreat = false, MidWater = true }
-- One entry per DEFAULTS key in name order; a slice adding a switch adds it here.
check("ours: the switch as set", Ours.Describe() == "BurstReady:1,ChoiceShadow:0,DoubleStack:1,ExitWindow:1,IdleBar:1,JobChooser:1,MidWater:1,Retreat:0,RuneRotation:1,RuneSpawn:1,StackExecute:1,SupportPull:1,SupportPullFarm:1,Sustain:1,Threat:1,TowerRead:1,TripRead:1", Ours.Describe())
Customize.Ours = {}
check("ours: a missing key takes its default", Ours.Describe() == "BurstReady:1,ChoiceShadow:0,DoubleStack:1,ExitWindow:1,IdleBar:1,JobChooser:1,MidWater:0,Retreat:1,RuneRotation:1,RuneSpawn:1,StackExecute:1,SupportPull:1,SupportPullFarm:1,Sustain:1,Threat:1,TowerRead:1,TripRead:1", Ours.Describe())
Customize.Enable = nil
Customize.Ours = { Team = "radiant" }
CURRENT_TEAM = 2
check("ours: Team=radiant leaves Radiant on", Ours.On("Retreat") and Ours.On("SupportPull"))
CURRENT_TEAM = 3
check("ours: Team=radiant turns every switch off for Dire", not Ours.Describe():find(":1", 1, true), Ours.Describe())
Customize.Ours = { Team = "dire" }
check("ours: Team=dire leaves Dire on", Ours.On("Retreat") and Ours.On("Threat"))
CURRENT_TEAM = 2
check("ours: Team=dire turns every switch off for Radiant", not Ours.Describe():find(":1", 1, true), Ours.Describe())
Customize.Ours = { Team = "both" }
check("ours: any other Team value scopes nothing", Ours.On("Retreat"))
Customize.Ours = { Team = "Radiant" }
CURRENT_TEAM = 3
check("ours: Team is case-insensitive", not Ours.On("Retreat"))
Customize.Ours = { Team = 3 }
check("ours: Team=3 leaves Dire on", Ours.On("Retreat"))
CURRENT_TEAM = 2
check("ours: Team=3 turns Radiant off", not Ours.On("Retreat"))
Customize.Ours = { Team = "dire", Retreat = true }
check("ours: the scope wins over an explicit switch value", not Ours.On("Retreat"))
Customize.Ours = {}
Customize.Enable = false
check("ours: Customize.Enable = false turns every switch off", not Ours.Describe():find(":1", 1, true), Ours.Describe())
finish()
