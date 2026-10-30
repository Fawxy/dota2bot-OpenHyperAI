-- ev=bot `ours`: which Ours switches a game ran with, the only arm marker of a remote job (no --set).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Customize = package.loaded["bots/FunLib/custom_loader"]
local Ours = require("bots/FunLib/humaniser/ours")
Customize.Ours = { LeaveCoreCreep = false }
-- One entry per DEFAULTS key in name order; a slice adding a switch adds it here.
check("ours: the switch as set", Ours.Describe() == "LeaveCoreCreep:0,StackExecute:1", Ours.Describe())
Customize.Ours = {}
check("ours: a missing key takes its default", Ours.Describe() == "LeaveCoreCreep:1,StackExecute:1", Ours.Describe())
Customize.Enable = false
check("ours: Customize.Enable = false turns every switch off", not Ours.Describe():find(":1", 1, true), Ours.Describe())
finish()
