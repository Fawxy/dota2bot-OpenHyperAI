-- Vendored from dota-bot-sdk packages/lua-bridge @ 9043ff1. Do not edit; rebuild and re-vendor.
--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
____exports.DEFAULTS = {
    Enable = false,
    Url = "http://127.0.0.1:41234/tick",
    Hz = 4,
    TimeoutSec = 2,
    FailuresBeforeBackoff = 3,
    MaxBackoffSec = 30,
    PayloadBytes = 2048,
    SummaryEverySec = 30
}
local FORMS = {{name = "CreateHTTPRequest1", global = "CreateHTTPRequest", twoArg = false}, {name = "CreateHTTPRequest2", global = "CreateHTTPRequest", twoArg = true}, {name = "CreateRemoteHTTPRequest", global = "CreateRemoteHTTPRequest", twoArg = false}}
local METHODS = {"SetHTTPRequestRawPostBody", "SetHTTPRequestHeaderValue", "SetHTTPRequestGetOrPostParameter", "Send"}
local RING_SIZE = 200
local S
local function int(n)
    return string.format(
        "%d",
        math.floor(n)
    )
end
local function f1(n)
    return string.format("%.1f", n)
end
local function f2(n)
    return string.format("%.2f", n)
end
local function f3(n)
    return string.format("%.3f", n)
end
local function num(n)
    return n == math.floor(n) and int(n) or f3(n)
end
local function clean(e)
    local s = string.gsub(
        tostring(e),
        "%s",
        "_"
    )
    return string.sub(s, 1, 80)
end
local function ringPush(r, v)
    r.items[r.next + 1] = v
    r.next = (r.next + 1) % RING_SIZE
end
local function sortedCopy(items)
    local out = {}
    for ____, v in ipairs(items) do
        out[#out + 1] = v
    end
    table.sort(out)
    return out
end
local function percentile(sorted, p)
    local idx = math.max(
        1,
        math.ceil(p * #sorted / 100)
    )
    return sorted[idx]
end
local function p95(r, fmt)
    if #r.items == 0 then
        return "na"
    end
    return fmt(percentile(
        sortedCopy(r.items),
        95
    ))
end
local function sortedPids(s)
    local out = {}
    for p in pairs(s.pids) do
        out[#out + 1] = p
    end
    table.sort(out)
    return out
end
local function joinInts(list)
    local parts = {}
    for ____, v in ipairs(list) do
        parts[#parts + 1] = int(v)
    end
    return table.concat(parts, ",")
end
local function emit(s, line)
    s.deps.log(line)
end
local function logErr(s, seq, where, e)
    s.errors = s.errors + 1
    emit(
        s,
        (((((("ev=err inst=" .. s.inst) .. " seq=") .. int(seq)) .. " where=") .. where) .. " msg=") .. clean(e)
    )
end
local function succeed(s)
    s.fails = 0
    s.backoffUntil = 0
end
local function fail(s, now)
    s.fails = s.fails + 1
    local n = s.cfg.FailuresBeforeBackoff
    if s.fails >= n then
        local wait = math.min(s.cfg.MaxBackoffSec, 2 ^ (s.fails - n + 1))
        s.backoffUntil = now + wait
        emit(
            s,
            (((("ev=backoff inst=" .. s.inst) .. " fails=") .. int(s.fails)) .. " wait_s=") .. num(wait)
        )
    end
end
local function createWith(s, form)
    local fn = s.lookup(form.global)
    if type(fn) ~= "function" then
        return nil
    end
    local ctor = fn
    local ____form_twoArg_0
    if form.twoArg then
        ____form_twoArg_0 = ctor("POST", s.cfg.Url)
    else
        ____form_twoArg_0 = ctor(s.cfg.Url)
    end
    local h = ____form_twoArg_0
    if h == nil then
        return nil
    end
    if type(h.Send) ~= "function" then
        return nil
    end
    return h
end
local function probe(s)
    local tried = {}
    local handle
    for ____, form in ipairs(FORMS) do
        do
            local __continue31
            repeat
                local okL, fn = pcall(s.lookup, form.global)
                if okL and type(fn) ~= "function" then
                    tried[#tried + 1] = form.name .. ":missing"
                    __continue31 = true
                    break
                end
                local ok, res = pcall(createWith, s, form)
                if not ok then
                    tried[#tried + 1] = form.name .. ":err"
                elseif res == nil then
                    tried[#tried + 1] = form.name .. ":nil"
                else
                    tried[#tried + 1] = form.name .. ":ok"
                    handle = res
                    s.form = form
                    break
                end
                __continue31 = true
            until true
            if not __continue31 then
                break
            end
        end
    end
    local methods = {}
    if handle ~= nil then
        local h = handle
        for ____, m in ipairs(METHODS) do
            local ok, isFn = pcall(function() return type(h[m]) == "function" end)
            if ok and isFn == true then
                methods[#methods + 1] = m
            end
        end
    end
    s.ctorName = s.form ~= nil and s.form.name or "none"
    emit(
        s,
        (((((("ev=api inst=" .. s.inst) .. " ctor=") .. s.ctorName) .. " tried=") .. table.concat(tried, ",")) .. " methods=") .. table.concat(methods, ",")
    )
    if handle == nil then
        s.disabled = "no_api"
        emit(s, ("ev=disabled inst=" .. s.inst) .. " reason=no_api")
    end
    return handle
end
local function setBody(s, seq, h, body)
    if type(h.SetHTTPRequestRawPostBody) == "function" then
        if type(h.SetHTTPRequestHeaderValue) == "function" then
            local okH, eH = pcall(function() return h:SetHTTPRequestHeaderValue("Content-Type", "application/json") end)
            if not okH then
                logErr(s, seq, "header", eH)
            end
        end
        local okB, eB = pcall(function() return h:SetHTTPRequestRawPostBody("application/json", body) end)
        if not okB then
            logErr(s, seq, "body", eB)
        end
    elseif type(h.SetHTTPRequestGetOrPostParameter) == "function" then
        local okP, eP = pcall(function() return h:SetHTTPRequestGetOrPostParameter("payload", body) end)
        if not okP then
            logErr(s, seq, "body", eP)
        end
    end
end
local function encodeRequest(s, seq, team, gt, rt)
    local req = {
        v = 1,
        inst = s.inst,
        seq = seq,
        team = team,
        pids = sortedPids(s),
        gt = gt,
        rt = rt,
        pad = ""
    }
    local body = s.deps.encode(req)
    local padLen = s.cfg.PayloadBytes - #body
    if padLen <= 0 then
        return body
    end
    req.pad = string.rep("x", padLen)
    return s.deps.encode(req)
end
local function onResponse(s, seq, sendRt, sendGt, r)
    if S ~= s then
        return
    end
    local d = s.deps
    local now = d.realTime()
    local gtNow = d.gameTime()
    local late = s.inFlight == nil or s.inFlight.seq ~= seq
    local t = type(r)
    if not s.shapeLogged then
        s.shapeLogged = true
        local line = (("ev=shape inst=" .. s.inst) .. " type=") .. t
        if t == "table" then
            local keys = {}
            for k in pairs(r) do
                keys[#keys + 1] = tostring(k)
            end
            table.sort(keys)
            line = (line .. " keys=") .. table.concat(keys, ",")
        end
        emit(s, line)
    end
    local status = "na"
    local statusOk = true
    local body = nil
    if t == "string" then
        body = r
    elseif t == "table" or t == "userdata" then
        local sc = tonumber(r.StatusCode)
        body = r.Body
        if sc ~= nil then
            status = int(sc)
            statusOk = sc >= 200 and sc < 300
        end
    end
    local bodyStr = type(body) == "string" and body or nil
    local decoded = false
    local decMs
    if statusOk and bodyStr ~= nil then
        local t0 = d.realTime()
        local okD, v = pcall(d.decode, bodyStr)
        decMs = (d.realTime() - t0) * 1000
        if not okD then
            logErr(s, seq, "decode", v)
        elseif type(v) ~= "table" then
            logErr(s, seq, "decode", "not_a_table")
        else
            decoded = true
        end
    end
    local ok = statusOk and decoded
    local rttMs = (now - sendRt) * 1000
    if not late then
        s.inFlight = nil
        s.received = s.received + 1
        ringPush(s.rtt, rttMs)
        if decMs ~= nil then
            ringPush(s.dec, decMs)
        end
        if ok then
            succeed(s)
        else
            fail(s, now)
        end
    end
    emit(
        s,
        ((((((((((((((("ev=recv inst=" .. s.inst) .. " seq=") .. int(seq)) .. " status=") .. status) .. " bytes=") .. int(bodyStr ~= nil and #bodyStr or 0)) .. " rtt_ms=") .. f1(rttMs)) .. " gt_dt=") .. f3(gtNow - sendGt)) .. " dec_ms=") .. (decMs ~= nil and f3(decMs) or "na")) .. " ok=") .. (ok and "1" or "0")) .. (late and " late=1" or "")
    )
end
local function onCallbackError(s, seq, e)
    if S ~= s then
        return
    end
    logErr(s, seq, "callback", e)
    if s.inFlight ~= nil and s.inFlight.seq == seq then
        s.inFlight = nil
        fail(
            s,
            s.deps.realTime()
        )
    end
end
local function sendRequest(s, team, now)
    local h
    if s.form == nil then
        h = probe(s)
        if h == nil then
            return
        end
    end
    s.lastSendAt = now
    s.seq = s.seq + 1
    local seq = s.seq
    local d = s.deps
    if h == nil then
        local okC, res = pcall(createWith, s, s.form)
        if not okC or res == nil then
            logErr(s, seq, "create", okC and "nil_handle" or res)
            fail(s, now)
            return
        end
        h = res
    end
    local gt = d.gameTime()
    local t0 = d.realTime()
    local okE, encoded = pcall(
        encodeRequest,
        s,
        seq,
        team,
        gt,
        now
    )
    local encMs = (d.realTime() - t0) * 1000
    if not okE then
        logErr(s, seq, "encode", encoded)
        fail(s, now)
        return
    end
    local body = encoded
    ringPush(s.enc, encMs)
    setBody(s, seq, h, body)
    s.inFlight = {seq = seq}
    s.inFlightRt = now
    s.sent = s.sent + 1
    emit(
        s,
        (((((((((((("ev=send inst=" .. s.inst) .. " seq=") .. int(seq)) .. " team=") .. int(team)) .. " bytes=") .. int(#body)) .. " enc_ms=") .. f3(encMs)) .. " gt=") .. f3(gt)) .. " rt=") .. f3(now)
    )
    local handle = h
    local function cb(r)
        local okR, eR = pcall(
            onResponse,
            s,
            seq,
            now,
            gt,
            r
        )
        if not okR then
            pcall(onCallbackError, s, seq, eR)
        end
    end
    local okS, eS = pcall(function() return handle:Send(cb) end)
    if not okS then
        logErr(s, seq, "send", eS)
        if s.inFlight ~= nil and s.inFlight.seq == seq then
            s.inFlight = nil
            fail(s, now)
        end
    end
end
local function summarise(s, now)
    s.lastSummaryAt = now
    local rtt = sortedCopy(s.rtt.items)
    local n = #rtt
    local rtElapsed = now - s.initRt
    local ratio = rtElapsed > 0 and f2((s.deps.gameTime() - s.initGt) / rtElapsed) or "na"
    emit(
        s,
        (((((((((((((((((((((("ev=summary inst=" .. s.inst) .. " pids=") .. joinInts(sortedPids(s))) .. " sent=") .. int(s.sent)) .. " recv=") .. int(s.received)) .. " lost=") .. int(s.lost)) .. " errs=") .. int(s.errors)) .. " p50=") .. (n > 0 and f1(percentile(rtt, 50)) or "na")) .. " p95=") .. (n > 0 and f1(percentile(rtt, 95)) or "na")) .. " max=") .. (n > 0 and f1(rtt[n]) or "na")) .. " enc_p95=") .. p95(s.enc, f3)) .. " dec_p95=") .. p95(s.dec, f3)) .. " gt_rt_ratio=") .. ratio
    )
end
local function tickInner(s, team, pid)
    s.pids[pid] = true
    local now = s.deps.realTime()
    if s.inFlight ~= nil and now - s.inFlightRt > s.cfg.TimeoutSec then
        local seq = s.inFlight.seq
        s.inFlight = nil
        s.lost = s.lost + 1
        emit(
            s,
            (("ev=timeout inst=" .. s.inst) .. " seq=") .. int(seq)
        )
        fail(s, now)
    end
    if now - s.lastSummaryAt >= s.cfg.SummaryEverySec then
        summarise(s, now)
    end
    if s.disabled ~= nil or s.inFlight ~= nil or now < s.backoffUntil then
        return
    end
    if s.lastSendAt ~= nil and now - s.lastSendAt < 1 / s.cfg.Hz then
        return
    end
    sendRequest(s, team, now)
end
function ____exports.Init(deps, config)
    local c = config or ({})
    local ____c_Enable_1 = c.Enable
    if ____c_Enable_1 == nil then
        ____c_Enable_1 = ____exports.DEFAULTS.Enable
    end
    local cfg = {
        Enable = ____c_Enable_1,
        Url = c.Url or ____exports.DEFAULTS.Url,
        Hz = c.Hz or ____exports.DEFAULTS.Hz,
        TimeoutSec = c.TimeoutSec or ____exports.DEFAULTS.TimeoutSec,
        FailuresBeforeBackoff = c.FailuresBeforeBackoff or ____exports.DEFAULTS.FailuresBeforeBackoff,
        MaxBackoffSec = c.MaxBackoffSec or ____exports.DEFAULTS.MaxBackoffSec,
        PayloadBytes = c.PayloadBytes or ____exports.DEFAULTS.PayloadBytes,
        SummaryEverySec = c.SummaryEverySec or ____exports.DEFAULTS.SummaryEverySec
    }
    local random = deps.random or (function() return math.random() end)
    local lookup = deps.lookup or (function(name) return _G[name] end)
    local rt = cfg.Enable and deps.realTime() or 0
    S = {
        deps = deps,
        cfg = cfg,
        lookup = lookup,
        inst = string.format(
            "%04x",
            math.floor(random() * 65536) % 65536
        ),
        pids = {},
        seq = 0,
        sent = 0,
        received = 0,
        lost = 0,
        errors = 0,
        inFlightRt = 0,
        backoffUntil = 0,
        fails = 0,
        ctorName = "",
        shapeLogged = false,
        rtt = {items = {}, next = 0},
        enc = {items = {}, next = 0},
        dec = {items = {}, next = 0},
        initRt = rt,
        initGt = cfg.Enable and deps.gameTime() or 0,
        lastSummaryAt = rt
    }
end
function ____exports.Tick(team, pid)
    local s = S
    if s == nil or not s.cfg.Enable then
        return
    end
    local ok, e = pcall(tickInner, s, team, pid)
    if not ok then
        pcall(
            logErr,
            s,
            s.seq,
            "tick",
            e
        )
    end
end
function ____exports.GetStats()
    local s = S
    if s == nil then
        return {
            inst = "",
            sent = 0,
            received = 0,
            lost = 0,
            errors = 0,
            inFlight = false,
            backoffUntil = 0,
            ctor = ""
        }
    end
    return {
        inst = s.inst,
        sent = s.sent,
        received = s.received,
        lost = s.lost,
        errors = s.errors,
        inFlight = s.inFlight ~= nil,
        backoffUntil = s.backoffUntil,
        ctor = s.ctorName,
        disabled = s.disabled
    }
end
return ____exports
