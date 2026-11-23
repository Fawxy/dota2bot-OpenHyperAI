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
    Slack = 4
}
--- The task's host: the decider's (farm).
local HOST = BotMode.Farm
local passes = {}
--- pid -> the spawn this hero already went for (one walk a spawn).
local went = {}
--- pid -> the rune this hero's walk is for, while it runs.
local running = {}
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
        ex = ex
    }
end
--- What holds a cheap detour back now, else undefined.
local function block(bot, r)
    local mode = bot:GetActiveMode()
    if mode == BotMode.Attack or mode == BotMode.Retreat then
        return "busy"
    end
    for pid, rune in pairs(running) do
        if rune == r.rune and pid ~= bot:GetPlayerID() then
            return "ally"
        end
    end
    if SafeGather.At(bot, r.at, {who = "rune_detour"}).level == "deadly" then
        return "danger"
    end
    return nil
end
local function choiceLine(bot, p, go, why, src)
    Telemetry.Event(
        "choice",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "rune_detour"},
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
local function jobLine(bot, phase, why, ex, cut)
    Telemetry.Event(
        "job",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"job", "rune_detour"},
            {"phase", phase},
            {"why", why},
            {"host", HOST},
            {
                "ex",
                ex ~= nil and math.floor(ex * 10 + 0.5) / 10 or nil
            },
            {"cut", cut}
        }
    )
end
--- One read of the pass for `bot`: opens, updates or closes its Pass. Returns the read when the pass is open and has not been
-- logged, else undefined. A closed pass writes its line with `src`.
local function observe(bot, src, now)
    local pid = bot:GetPlayerID()
    local r = ____exports.ReadPass(bot, now)
    local p = passes[pid]
    if p ~= nil and (r == nil or r.spawn ~= p.spawn) then
        choiceLine(
            bot,
            p,
            false,
            src == "shadow" and "off" or (p.why or "detour"),
            src
        )
        passes[pid] = nil
        p = nil
    end
    if r == nil or went[pid] == r.spawn then
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
-- `want` is set when the detour was within budget and nothing held it at some read. Reads and logs; nothing is ordered.
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
    if r.ex <= ____exports.SETTINGS.Budget and block(bot, r) == nil then
        p.want = true
    end
end
local function finish(bot, ex, res)
    running[bot:GetPlayerID()] = nil
    local cut = not res.success and res.reason == "preempted" and (Decider.LetGo(bot) and "retreat" or HDebug.ModeName(bot:GetActiveMode())) or nil
    jobLine(
        bot,
        "end",
        res.success and "ok" or res.reason,
        ex,
        cut
    )
end
--- The row's `applies`: true while a walk runs or as one starts.
local function rowApplies(bot)
    if not ____exports.On() or Drill.Held(bot) then
        return false
    end
    local pid = bot:GetPlayerID()
    Tasks.Tick(bot)
    if running[pid] ~= nil then
        return true
    end
    if Tasks.Jobs() == nil then
        return false
    end
    local now = DotaTime()
    local r = observe(bot, "own", now)
    if r == nil then
        return false
    end
    local p = passes[pid]
    if r.ex > ____exports.SETTINGS.Budget then
        if not p.want then
            p.why = "detour"
        end
        return false
    end
    p.want = true
    local why = block(bot, r)
    if why ~= nil then
        p.why = why
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
    went[pid] = r.spawn
    passes[pid] = nil
    local ____choiceLine_2 = choiceLine
    local ____bot_1 = bot
    local ____ok_0
    if ok then
        ____ok_0 = nil
    else
        ____ok_0 = "refused"
    end
    ____choiceLine_2(
        ____bot_1,
        p,
        ok,
        ____ok_0,
        "own"
    )
    if not ok then
        return false
    end
    running[pid] = r.rune
    jobLine(bot, "start", "pass", ex)
    return true
end
--- The row's verb: one frame of the walk; true once it has ended.
local function rowStep(bot)
    Tasks.Step(bot, HOST)
    return running[bot:GetPlayerID()] == nil
end
--- The decider's row (registered in index.ts, so the decider imports no row).
____exports.ROW = {name = "rune_detour", applies = rowApplies, step = rowStep}
return ____exports
