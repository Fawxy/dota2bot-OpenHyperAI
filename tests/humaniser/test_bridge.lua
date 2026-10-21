dofile(HARNESS_DIR .. "/dota_stubs.lua")
local Json = require("bots/ts_libs/utils/json")

REAL_T = 0
function RealTime() return REAL_T end

local ctorCalls, requests, printed

-- A stub request that captures its body and answers synchronously, like a sidecar echoing {}.
-- Accepts both CreateHTTPRequest(url) and CreateHTTPRequest("POST", url).
local function okRequest(a, b)
	ctorCalls = ctorCalls + 1
	local req = { url = b or a }
	function req:SetHTTPRequestHeaderValue() end
	function req:SetHTTPRequestRawPostBody(_, body) self.body = body end
	function req:Send(cb) table.insert(requests, self) cb({ StatusCode = 200, Body = "{}" }) end
	return req
end

local function throwingRequest(a, b)
	local req = okRequest(a, b)
	function req:Send() error("send exploded") end
	return req
end

local function setup(customHumaniser, ctor)
	ResetWorld()
	-- The vendored module holds its state at module level; drop it so each case starts clean.
	package.loaded["bots/FunLib/sdk/bridge"] = nil
	ctorCalls, requests, printed = 0, {}, {}
	REAL_T = 0
	CreateHTTPRequest = ctor or okRequest
	CreateRemoteHTTPRequest = ctor or okRequest
	print = function(s) table.insert(printed, tostring(s)) end
	return FreshHumaniser(customHumaniser)
end

local function bridgeLines(prefix)
	local out = {}
	for _, line in ipairs(printed) do
		if line:sub(1, #prefix) == prefix then table.insert(out, line) end
	end
	return out
end

local function runTicks(H, bots, frames)
	for _ = 1, frames do
		REAL_T = REAL_T + 0.1
		T = T + 0.1
		for _, b in ipairs(bots) do H.Tick(b) end
	end
end

local ORIG_PRINT = print

-- Bridge off by default: no HTTP constructor is touched and nothing is logged.
do
	local H = setup({ Enable = true })
	local bots = { MakeUnit({ pid = 1 }), MakeUnit({ pid = 2 }), MakeUnit({ pid = 7, team = 3 }) }
	runTicks(H, bots, 100)
	print = ORIG_PRINT
	check("default: no HTTP ctor calls", ctorCalls == 0, ctorCalls)
	check("default: no bridge lines", #bridgeLines("[H:bridge]") == 0, #bridgeLines("[H:bridge]"))
end

-- Humaniser off overrides Bridge.Enable.
do
	local H = setup({ Enable = false, Bridge = { Enable = true } })
	local bots = { MakeUnit({ pid = 1 }), MakeUnit({ pid = 2 }) }
	runTicks(H, bots, 100)
	print = ORIG_PRINT
	check("humaniser off: no HTTP ctor calls", ctorCalls == 0, ctorCalls)
	check("humaniser off: no bridge lines", #bridgeLines("[H:bridge]") == 0, #bridgeLines("[H:bridge]"))
end

-- Enabled: the vendored module loads through the real require path, probes the API and posts JSON with the ticking pids.
do
	local H = setup({ Enable = true, Bridge = { Enable = true, PayloadBytes = 64 } })
	local bots = { MakeUnit({ pid = 1 }), MakeUnit({ pid = 2 }), MakeUnit({ pid = 3 }) }
	runTicks(H, bots, 20)
	print = ORIG_PRINT
	local api = bridgeLines("[H:bridge] ev=api ")
	check("enabled: api line names the first form tried", #api == 1 and api[1]:find("ctor=CreateHTTPRequest2 ", 1, true) ~= nil, api[1])
	check("enabled: locks on the first form that answers 200", #bridgeLines("[H:bridge] ev=locked inst=") == 1 and bridgeLines("[H:bridge] ev=locked ")[1]:find("form=CreateHTTPRequest2 ", 1, true) ~= nil)
	check("enabled: send logged", #bridgeLines("[H:bridge] ev=send ") > 0)
	check("enabled: requests posted", #requests > 1, #requests)
	local last = requests[#requests]
	local ok, body = pcall(Json.decode, last and last.body or "")
	check("enabled: body decodes", ok and type(body) == "table", last and last.body)
	if ok and type(body) == "table" then
		check("enabled: body has team", body.team == 2, body.team)
		check("enabled: body lists ticking pids", type(body.pids) == "table" and table.concat(body.pids, ",") == "1,2,3", body.pids and table.concat(body.pids, ","))
	end
	check("enabled: url from merged config", last ~= nil and last.url == "http://127.0.0.1:41234/tick", last and last.url)
end

-- A Send that throws must not escape Tick.
do
	local H = setup({ Enable = true, Bridge = { Enable = true } }, throwingRequest)
	local bots = { MakeUnit({ pid = 1 }), MakeUnit({ pid = 2 }) }
	local ok, err = pcall(runTicks, H, bots, 50)
	print = ORIG_PRINT
	check("throwing send: no error escapes Tick", ok, err)
	check("throwing send: error logged", #bridgeLines("[H:bridge] ev=err ") > 0)
end

finish()
