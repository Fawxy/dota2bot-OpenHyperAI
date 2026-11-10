-- ev=bot `ours`: which Ours switches a game ran with, the only arm marker of a remote job (no --set).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Customize = package.loaded["bots/FunLib/custom_loader"]
local Ours = require("bots/FunLib/humaniser/ours")
Customize.Ours = { LeaveCoreCreep = false, CoreLastHit = true }
-- One entry per DEFAULTS key in name order; a slice adding a switch adds it here.
check("ours: the switch as set", Ours.Describe() == "ArbiterShadow:1,CoreCampTrip:1,CoreContest:1,CoreDenyYield:1,CoreHold:1,CoreLaneFight:1,CoreLastHit:1,CoreLastHitDire:1,CorePull:1,CoreTrade:1,DoubleStack:1,JobChooser:1,LaneAggro:1,LaneControl:1,LaneControlDrive:1,LaneSpot:1,LaneSpotThreat:1,LaneSpotTower:1,LeaveCoreCreep:0,PreDeny:1,PreHit:1,Retreat:1,RetreatOdds:1,RuneRotation:1,RuneSpawn:1,StackExecute:1,SupportDeny:1,SupportDenyDire:1,SupportHarass:1,SupportLastHit:1,SupportPull:1,SupportPullFarm:1,Threat:1", Ours.Describe())
Customize.Ours = {}
check("ours: a missing key takes its default", Ours.Describe() == "ArbiterShadow:1,CoreCampTrip:1,CoreContest:1,CoreDenyYield:1,CoreHold:1,CoreLaneFight:1,CoreLastHit:1,CoreLastHitDire:1,CorePull:1,CoreTrade:1,DoubleStack:1,JobChooser:1,LaneAggro:1,LaneControl:1,LaneControlDrive:1,LaneSpot:1,LaneSpotThreat:1,LaneSpotTower:1,LeaveCoreCreep:1,PreDeny:1,PreHit:1,Retreat:1,RetreatOdds:1,RuneRotation:1,RuneSpawn:1,StackExecute:1,SupportDeny:1,SupportDenyDire:1,SupportHarass:1,SupportLastHit:1,SupportPull:1,SupportPullFarm:1,Threat:1", Ours.Describe())
Customize.Enable = nil
Customize.Ours = { Team = "radiant" }
CURRENT_TEAM = 2
check("ours: Team=radiant leaves Radiant on", Ours.On("CoreLastHit") and Ours.On("SupportDeny"))
CURRENT_TEAM = 3
check("ours: Team=radiant turns every switch off for Dire", not Ours.Describe():find(":1", 1, true), Ours.Describe())
Customize.Ours = { Team = "dire" }
check("ours: Team=dire leaves Dire on", Ours.On("CoreLastHit") and Ours.On("PreDeny"))
CURRENT_TEAM = 2
check("ours: Team=dire turns every switch off for Radiant", not Ours.Describe():find(":1", 1, true), Ours.Describe())
Customize.Ours = { Team = "both" }
check("ours: any other Team value scopes nothing", Ours.On("CoreLastHit"))
Customize.Ours = { Team = "Radiant" }
CURRENT_TEAM = 3
check("ours: Team is case-insensitive", not Ours.On("CoreLastHit"))
Customize.Ours = { Team = 3 }
check("ours: Team=3 leaves Dire on", Ours.On("CoreLastHit"))
CURRENT_TEAM = 2
check("ours: Team=3 turns Radiant off", not Ours.On("CoreLastHit"))
Customize.Ours = { Team = "dire", CoreLastHit = true }
check("ours: the scope wins over an explicit switch value", not Ours.On("CoreLastHit"))
Customize.Ours = {}
Customize.Enable = false
check("ours: Customize.Enable = false turns every switch off", not Ours.Describe():find(":1", 1, true), Ours.Describe())
finish()
