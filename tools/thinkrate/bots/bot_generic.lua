-- Bare Valve bot script (BACKLOG 1.12 step a, folds in 0.9; WO-025): logs every Think call so the interval between calls
-- can be measured without OHA. Linked as the bots folder by `dotactl run --worktree tools/thinkrate`; never loaded by OHA.
local FROM, TO = 60, 120
function Think()
	local t = DotaTime()
	if t < FROM or t > TO then return end
	local bot = GetBot()
	print(string.format("[THINK] pid=%d dota=%.4f game=%.4f real=%.4f", bot:GetPlayerID(), t, GameTime(), RealTime()))
end
