-- Runs one fixture's driver (FIXTURE and SKILL are set by fixtures.js) and leaves its observation in OBS_JSON.
-- A driver file returns function(fx, skill) -> { actions = { { verb, target } }, desire = { mode = n }, fact = { name = n } }.

local function json(v)
	local t = type(v)
	if t == "nil" then return "null" end
	if t == "boolean" then return tostring(v) end
	-- JSON has no nan or inf; null makes a term on the value fail as "not observed".
	if t == "number" then return (v ~= v or v == math.huge or v == -math.huge) and "null" or tostring(v) end
	if t == "string" then return '"' .. (v:gsub('[%c"\\]', function(c) return string.format("\\u%04x", c:byte()) end)) .. '"' end
	if #v > 0 or next(v) == nil then
		local parts = {}
		for _, x in ipairs(v) do table.insert(parts, json(x)) end
		return "[" .. table.concat(parts, ",") .. "]"
	end
	local parts = {}
	for k, x in pairs(v) do table.insert(parts, json(tostring(k)) .. ":" .. json(x)) end
	return "{" .. table.concat(parts, ",") .. "}"
end

local driver = dofile(HARNESS_DIR .. "/fixture_drivers/" .. FIXTURE.decision .. ".lua")
local obs = driver(FIXTURE, SKILL)
obs.actions, obs.desire, obs.fact = obs.actions or {}, obs.desire or {}, obs.fact or {}
OBS_JSON = json(obs)
