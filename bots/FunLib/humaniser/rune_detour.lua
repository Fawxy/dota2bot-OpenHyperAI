--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
local ____exports = {}
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Rune = ____dota.Rune
local Decider = require(GetScriptDirectory().."/FunLib/humaniser/decider")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local Drill = require(GetScriptDirectory().."/FunLib/humaniser/drill")
local Ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local Runes = require(GetScriptDirectory().."/FunLib/humaniser/game_rules")
local SafeGather = require(GetScriptDirectory().."/FunLib/humaniser/safe_gather")
local ____tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Tasks = ____tasks.ForOurs
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
____exports.SETTINGS = {
    Budget = 12,
    Radius = 1800,
    LaneR = 1100,
    Until = 600,
    Slack = 4,
    TookGold = 20,
    Rest = 0.5,
    Misses = 2
}
--- The task's host: the decider's (farm).
local HOST = BotMode.Farm
local passes = {}
--- pid -> the spawn this hero last went for and how many of its walks for it ended untaken.
local went = {}
--- pid -> its walk while it runs.
local running = {}
--- pid -> when its last walk ended.
local endedAt = {}
--- pid -> the walk the row's `wants` decided to start this round, for its `begin`.
local pending = {}
function ____exports.ResetCache()
    for k in pairs(passes) do
        passes[k] = nil
    end
    for k in pairs(went) do
        went[k] = nil
    end
    for k in pairs(running) do
        running[k] = nil
    end
    for k in pairs(endedAt) do
        endedAt[k] = nil
    end
    for k in pairs(pending) do
        pending[k] = nil
    end
end
function ____exports.On()
    return Ours.On("RuneDetour")
end
--- The bounty in this team's own jungle: of the two jungle bounties (Bounty1, Bounty2), the one nearer its ancient.
function ____exports.OwnRune(team)
    local anc = GetAncient(team):GetLocation()
    local a = GetRuneSpawnLocation(Rune.Bounty1)
    local b = GetRuneSpawnLocation(Rune.Bounty2)
    local function d(v)
        return (v.x - anc.x) * (v.x - anc.x) + (v.y - anc.y) * (v.y - anc.y)
    end
    return d(a) <= d(b) and Rune.Bounty1 or Rune.Bounty2
end
--- The bounty spawn this rune's live window belongs to (4:00, 8:00, ...).
function ____exports.SpawnOf(now)
    local every = Runes.RUNE_RULES.bounty.every
    return math.floor(math.max(now, 0) / every) * every
end
local function dist(a, b)
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
end
--- The pass read, the same in both arms: undefined when this is no pass. The detour is straight-line distances at the hero's
-- movement speed, to the front of its own lane (where a hero out of lane walks back to; `judgement`: its real goal and the
-- path are not read).
function ____exports.ReadPass(bot, now)
    if now == nil then
        now = DotaTime()
    end
    if not bot:IsAlive() or now >= ____exports.SETTINGS.Until then
        return nil
    end
    local spawn = ____exports.SpawnOf(now)
    if spawn <= 0 then
        return nil
    end
    local rune = ____exports.OwnRune(bot:GetTeam())
    if GetRuneStatus(rune) ~= RUNE_STATUS_AVAILABLE then
        return nil
    end
    local at = GetRuneSpawnLocation(rune)
    local me = bot:GetLocation()
    local dr = dist(me, at)
    if dr > ____exports.SETTINGS.Radius then
        return nil
    end
    local lane = bot:GetAssignedLane()
    if GetAmountAlongLane(lane, me).distance <= ____exports.SETTINGS.LaneR then
        return nil
    end
    local front = GetLaneFrontLocation(
        bot:GetTeam(),
        lane,
        0
    )
    local speed = math.max(
        100,
        bot:GetCurrentMovementSpeed()
    )
    local ex = math.max(
        0,
        dr + dist(at, front) - dist(me, front)
    ) / speed
    return {
        rune = rune,
        at = at,
        spawn = spawn,
        dr = dr,
        ex = ex,
        wr = dr / speed
    }
end
--- The modes the row may take a hero from: a hero walking, farming, laning or shopping. Any other (a gank, a rotation to defend,
-- a fight, a retreat) is a higher rule's, and the hold (Decider.HARD) would outbid it (review 24/11/2026).
local FROM = {
    [BotMode.None] = true,
    [BotMode.Laning] = true,
    [BotMode.Farm] = true,
    [BotMode.Rune] = true,
    [BotMode.Item] = true
}
--- What holds a cheap detour back now, else undefined.
local function block(bot, r)
    if FROM[bot:GetActiveMode()] ~= true then
        return "busy"
    end
    for pid, w in pairs(running) do
        if w.rune == r.rune and pid ~= bot:GetPlayerID() then
            return "ally"
        end
    end
    if SafeGather.At(bot, r.at, {who = "rune_detour"}).level == "deadly" then
        return "danger"
    end
    return nil
end
local function choiceLine(bot, p, go, why, src, aid)
    Telemetry.Event(
        "choice",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "rune_detour"},
            {"aid", aid},
            {"go", go and 1 or 0},
            {"want", p.want and 1 or 0},
            {"why", why},
            {"src", src},
            {
                "lane",
                bot:GetAssignedLane()
            },
            {"slot", p.spawn},
            {"rune", p.rune},
            {
                "ex",
                math.floor(p.ex * 10 + 0.5) / 10
            },
            {
                "dr",
                math.floor(p.dr + 0.5)
            }
        }
    )
end
local function jobLine(bot, phase, why, ex, cut, w, took, start)
    local a = w or start
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "rune_detour"},
            {"aid", a and a.aid},
            {
                "tgt",
                start ~= nil and "rune:" .. tostring(start.rune) or nil
            },
            {"phase", phase},
            {"why", why},
            {"host", HOST},
            {
                "ex",
                ex ~= nil and math.floor(ex * 10 + 0.5) / 10 or nil
            },
            {"cut", cut},
            {"took", took ~= nil and (took and 1 or 0) or nil},
            {"gj", w ~= nil and w.jump or nil}
        }
    )
end
--- Each step of the walk and at its end: the largest gold gain between two reads.
local function noteGold(bot, w)
    local g = bot:GetGold()
    if g - w.gold > w.jump then
        w.jump = g - w.gold
    end
    w.gold = g
end
--- One read of the pass for `bot`: opens, updates or closes its Pass. Returns the read when the pass is open and has not been
-- logged, else undefined. A closed pass writes its line with `src`.
local function observe(bot, src, now)
    local pid = bot:GetPlayerID()
    local r = ____exports.ReadPass(bot, now)
    local p = passes[pid]
    if p ~= nil and (r == nil or r.spawn ~= p.spawn) then
        if p.logged ~= true then
            choiceLine(
                bot,
                p,
                false,
                src == "shadow" and "off" or (p.why or "detour"),
                src
            )
        end
        passes[pid] = nil
        p = nil
    end
    local w = went[pid]
    if r == nil or w ~= nil and w.spawn == r.spawn and w.misses >= ____exports.SETTINGS.Misses then
        return nil
    end
    if p == nil then
        p = {
            spawn = r.spawn,
            rune = r.rune,
            ex = r.ex,
            dr = r.dr,
            want = false
        }
        passes[pid] = p
    elseif r.ex < p.ex then
        p.ex = r.ex
        p.dr = r.dr
    end
    return r
end
--- The reference arm's denominator: where the row is off, the same pass read and the same line (`src=shadow go=0 why=off`).
-- `want` is set when the detour was within budget at some read, as the row sets it. Reads and logs; nothing is ordered.
function ____exports.Shadow(bot)
    if not Telemetry.IsEnabled() or ____exports.On() or Drill.Held(bot) then
        return
    end
    local now = DotaTime()
    local r = observe(bot, "shadow", now)
    if r == nil then
        return
    end
    local p = passes[bot:GetPlayerID()]
    if r.ex <= ____exports.SETTINGS.Budget then
        p.want = true
    end
end
local function finish(bot, ex, res)
    local pid = bot:GetPlayerID()
    local w = running[pid]
    running[pid] = nil
    endedAt[pid] = DotaTime()
    if w ~= nil then
        noteGold(bot, w)
    end
    local took = res.success or w ~= nil and w.jump >= ____exports.SETTINGS.TookGold
    local g = went[pid]
    if g ~= nil and not took then
        g.misses = g.misses + 1
    end
    local cut = not res.success and res.reason == "preempted" and (Decider.LetGo(bot) and "retreat" or HDebug.ModeName(bot:GetActiveMode())) or nil
    jobLine(
        bot,
        "end",
        res.success and "ok" or res.reason,
        ex,
        cut,
        w,
        took
    )
end
--- The row's `wants`: an offer while a walk runs or when one should start now.
local function rowWants(bot, _reads)
    local pid = bot:GetPlayerID()
    pending[pid] = nil
    if not ____exports.On() or Drill.Held(bot) then
        return nil
    end
    Tasks.Tick(bot)
    local w = running[pid]
    if w ~= nil then
        return {tgt = "rune:" .. tostring(w.rune)}
    end
    if Tasks.Jobs() == nil then
        return nil
    end
    local now = DotaTime()
    local ended = endedAt[pid]
    if ended ~= nil and now - ended < ____exports.SETTINGS.Rest then
        return nil
    end
    local r = observe(bot, "own", now)
    if r == nil then
        return nil
    end
    local p = passes[pid]
    if r.ex > ____exports.SETTINGS.Budget then
        if not p.want then
            p.why = "detour"
        end
        return nil
    end
    p.want = true
    local why = block(bot, r)
    if why ~= nil then
        p.why = why
        return nil
    end
    pending[pid] = r
    return {
        tgt = "rune:" .. tostring(r.rune),
        at = r.at,
        secs = r.wr
    }
end
--- The row's `begin`: starts the walk `rowWants` decided this round.
local function rowBegin(bot)
    local pid = bot:GetPlayerID()
    local r = pending[pid]
    pending[pid] = nil
    local p = passes[pid]
    if r == nil or p == nil then
        return false
    end
    local ex = r.ex
    local timeout = r.dr / math.max(
        100,
        bot:GetCurrentMovementSpeed()
    ) + ____exports.SETTINGS.Slack
    local ok = Tasks.Start(
        bot,
        {
            name = "rune_detour",
            host = HOST,
            preemptAfter = 1,
            stallAfter = 4,
            onEnd = function(res) return finish(bot, ex, res) end
        },
        function() return Tasks.Verbs().pickUpRune(bot, r.rune, {at = r.at, timeout = timeout}) end
    )
    local g = went[pid]
    if g == nil or g.spawn ~= r.spawn then
        went[pid] = {spawn = r.spawn, misses = 0}
    end
    local aid = ok and Telemetry.NextAid(pid) or nil
    if p.logged ~= true then
        local ____choiceLine_4 = choiceLine
        local ____bot_3 = bot
        local ____ok_2
        if ok then
            ____ok_2 = nil
        else
            ____ok_2 = "refused"
        end
        ____choiceLine_4(
            ____bot_3,
            p,
            ok,
            ____ok_2,
            "own",
            aid
        )
    end
    p.logged = true
    if not ok then
        return false
    end
    local walk = {
        aid = aid,
        rune = r.rune,
        gold = bot:GetGold(),
        jump = 0
    }
    running[pid] = walk
    jobLine(
        bot,
        "start",
        "pass",
        ex,
        nil,
        nil,
        nil,
        walk
    )
    return true
end
--- The row's verb: one frame of the walk; true once it has ended.
local function rowStep(bot)
    local w = running[bot:GetPlayerID()]
    if w ~= nil then
        noteGold(bot, w)
    end
    Tasks.Step(bot, HOST)
    return running[bot:GetPlayerID()] == nil
end
--- The decider's row (registered in index.ts, so the decider imports no row).
____exports.ROW = {name = "rune_detour", wants = rowWants, begin = rowBegin, step = rowStep}
return ____exports
