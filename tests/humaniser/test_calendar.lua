-- Slice lane-control 3: each hero's own calendar (user 07/11/2026). The next leave and whether a pull window fits before a
-- departure the hero has booked (FitMargin 5).
dofile(HARNESS_DIR .. "/dota_stubs.lua")
FreshHumaniser({ Enable = false })
local Cal = require("bots/FunLib/humaniser/calendar")

local stack = { kind = "stack", key = 3, claim = 195, leave = 215, back = 250, fixed = false }
local rune = { kind = "rune", key = 360, claim = 300, leave = 345, back = 375, fixed = true }
local entries = { stack, rune }

-- NextLeave.
do
	check("next leave: the stack first", Cal.NextLeave(entries, 200) == 15)
	check("next leave: past the stack's leave, the rune", Cal.NextLeave(entries, 216) == 129)
	check("next leave: none after both", Cal.NextLeave(entries, 346) == nil)
	check("next leave: a running entry is not a leave ahead", Cal.NextLeave({ { kind = "stack", key = 3, claim = 195, leave = 230, back = 250, fixed = false, running = true } }, 200) == nil)
	check("next leave: empty calendar (a core)", Cal.NextLeave({}, 200) == nil)
end

-- FitOf: a pull from start to end.
do
	local f, e = Cal.FitOf(entries, 150, 175)
	check("free: before any claim", f == "free" and e == nil)
	f, e = Cal.FitOf(entries, 190, 205)
	check("fits: the stack's claim has begun, its leave is 10 s after the end", f == "fits" and e == stack)
	f, e = Cal.FitOf(entries, 200, 212)
	check("clash: the pull ends 3 s before the stack leaves (under FitMargin)", f == "clash" and e == stack)
	f, e = Cal.FitOf(entries, 305, 330)
	check("fits: inside the rune trip's claim, well before its leave", f == "fits" and e == rune)
	f, e = Cal.FitOf(entries, 335, 348)
	check("clash: the rune trip leaves during the pull", f == "clash" and e == rune)
	f, e = Cal.FitOf(entries, 251, 290)
	check("free: after the stack is back, before the rune's claim", f == "free")
	f, e = Cal.FitOf({ { kind = "stack", key = 3, claim = 195, leave = 230, back = 250, fixed = false, running = true } }, 196, 205)
	check("clash: a running job", f == "clash")
	f, e = Cal.FitOf({ stack, { kind = "rune", key = 240, claim = 200, leave = 208, back = 260, fixed = true } }, 190, 205)
	check("clash: one of two claims does not fit", f == "clash" and e.kind == "rune")
	-- lctl4_B_on_2 (2026-11-06T17-16-31) t=332 pid 8 and lctl4_B_on_5 t=302, 332: the stack (earlier leave) and the rune trip
	-- both clashed; the stack was reported, the pull kept its minute and the rune trip took the support (choice why=rune).
	local early = { kind = "stack", key = 5, claim = 315, leave = 340, back = 380, fixed = false }
	f, e = Cal.FitOf({ early, { kind = "rune", key = 360, claim = 300, leave = 342, back = 375, fixed = true } }, 330, 350)
	check("clash: a fixed clash wins over an earlier tentative one", f == "clash" and e.kind == "rune")
	f, e = Cal.FitOf({ early }, 330, 350)
	check("clash: a tentative clash alone is reported", f == "clash" and e == early)
end

finish()
