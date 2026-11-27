--[[ Generated with https://github.com/TypeScriptToLua/TypeScriptToLua ]]
-- Lua Library inline imports
local function __TS__ArrayIndexOf(self, searchElement, fromIndex)
    if fromIndex == nil then
        fromIndex = 0
    end
    local len = #self
    if len == 0 then
        return -1
    end
    if fromIndex >= len then
        return -1
    end
    if fromIndex < 0 then
        fromIndex = len + fromIndex
        if fromIndex < 0 then
            fromIndex = 0
        end
    end
    for i = fromIndex + 1, len do
        if self[i] == searchElement then
            return i - 1
        end
    end
    return -1
end

local function __TS__ArrayPush(self, ...)
    local items = {...}
    local len = #self
    for i = 1, #items do
        len = len + 1
        self[len] = items[i]
    end
    return len
end
-- End of Lua Library inline imports
local ____exports = {}
local refuse
local ____dota = require(GetScriptDirectory().."/ts_libs/dota/index")
local BotMode = ____dota.BotMode
local Claims = require(GetScriptDirectory().."/FunLib/humaniser/claims")
local Danger = require(GetScriptDirectory().."/FunLib/humaniser/danger")
local HDebug = require(GetScriptDirectory().."/FunLib/humaniser/debug")
local ____ours = require(GetScriptDirectory().."/FunLib/humaniser/ours")
local OursOn = ____ours.On
local ____reads = require(GetScriptDirectory().."/FunLib/humaniser/reads")
local READS = ____reads.READS
local Tasks = require(GetScriptDirectory().."/FunLib/humaniser/tasks")
local Telemetry = require(GetScriptDirectory().."/FunLib/humaniser/telemetry")
function refuse(bot, s, r)
    s.refused[r.row] = r
    local key = (r.row .. "|") .. (r.tgt or "")
    local ____s_14, ____refLines_15 = s, "refLines"
    if ____s_14[____refLines_15] == nil then
        ____s_14[____refLines_15] = {}
    end
    local seen = s.refLines
    if seen[key] == true then
        return
    end
    seen[key] = true
    if not Telemetry.IsEnabled() then
        return
    end
    Telemetry.Event(
        "choice",
        {
            {
                "pid",
                bot:GetPlayerID()
            },
            {"kind", "decider"},
            {"ref", r.row},
            {"btgt", r.tgt},
            {"bfrom", r.mode},
            {"why", r.why}
        }
    )
end
--- Plan s3: above 0.95, the most Valve's attack showed, and at most 1.0, since above it J.IsRetreating reads a farm-mode
-- hero as retreating; under OHA's retreat latch (1.1). The value inside that band is judgement.
____exports.HARD = 0.98
--- Plan s3: what a soft hold is worth to Valve, entering or held: above laning's desire (0.45) and under every entry of Valve's
-- attack (none of 7,419 in h2hoha742 under 0.5), so attack, item, evasive and defend-ally outbid it when they want the hero.
-- The value inside that band is judgement.
____exports.SOFT = 0.495
--- Valve multiplies the active mode's desire by about this (derived: ev=snap d over the file's own value, oha-solo-deny
-- 22574266: laning 0.446 reads 0.491, an active soft hold 0.49 reads 0.539; not every round, and the hard hold's 0.98 was
-- never boosted). While the host mode is active a soft hold returns SOFT / BONUS, so it is worth about SOFT either way.
____exports.BONUS = 1.1
--- judgement: the most an OHA Lua mode file may return while a soft row holds (plan s3: the gate caps them beneath it).
-- With Valve's bonus on the active mode (CAP x BONUS, 0.484) it stays under SOFT, so an active capped mode cannot keep the
-- hero from a soft hold.
____exports.CAP = 0.44
--- Not capped under a soft hold: retreat (stock's way out; when it leads, the retreat read lets go) and attack's own file
-- (OHA's override of Valve's attack for a few heroes: the mode a soft hold gives way to; beyond plan s3's "retreat
-- excepted", decided 24/11/2026). `farm` is a guard only: while a row holds, Host never calls farm's gated desire.
local UNCAPPED = {retreat = true, attack = true, farm = true}
--- Doctrine order: the first row that wants the hero holds it. index.ts fills it through `Add` with the pull, stack, rune detour, creep and draw (aggro) rows (in that order), so no row is imported here; with none registered the decider is a pass-through.
____exports.ROWS = {}
--- The one way to add a row: appends it to ROWS (once) and guards its task name, so only the decider's begin starts that task.
function ____exports.Add(row)
    Tasks.GuardRowTask(row.name)
    if __TS__ArrayIndexOf(____exports.ROWS, row) < 0 then
        local ____exports_ROWS_0 = ____exports.ROWS
        ____exports_ROWS_0[#____exports_ROWS_0 + 1] = row
    end
end
--- The mode file that hosts the decider. Never a rival in the retreat read: its own desire is not computed while a row holds,
-- and counting it only when fresh (the round after a yield) would make the hold flicker every other round.
local HOST = "farm"
--- judgement: a mode's value older than this is from neither this round nor the last (Valve asks every mode every round), so
-- its file was not asked and its value is not a rival.
local FRESH = 0.5
local heroes = {}
local function stateOf(bot)
    local pid = bot:GetPlayerID()
    local s = heroes[pid]
    if s == nil then
        s = {seen = {}, refused = {}}
        heroes[pid] = s
    end
    return s
end
local function isSoft(row, bot)
    local ____temp_1
    if type(row.soft) == "function" then
        ____temp_1 = row.soft(bot)
    else
        ____temp_1 = row.soft == true
    end
    return ____temp_1
end
--- The name of the hero's running task, however the runner was loaded.
local function runningTask(bot)
    local ____opt_2 = Tasks.ForOurs.Running(bot)
    return ____opt_2 and ____opt_2.name
end
--- The modes a row's start is refused from (offers-and-the-decider s4 1a, user 27/11/2026: a row never starts over a fight;
-- fights stay Valve's). A row already holding the hero when a fight starts is not cut by this.
local FIGHT = {[BotMode.Attack] = true, [BotMode.Roam] = true, [BotMode.TeamRoam] = true}
--- Another hero's claim the offer may not take (s4 step 2): lower goes first, so one with no rank on either side, or a rank at or under this one's, holds.
local function holds(c, mine)
    return c.rank == nil or (mine and mine.rank) == nil or c.rank <= mine.rank
end
--- Acceptance (offers-and-the-decider s4), the same for a polled row and an offered one, its checks in s4's order. Step 1 (a row
-- above holds the hero) is `Offer`'s, before the row's `wants` is asked; a polled row is asked only when no row above wanted the
-- hero. 1a, the fight (Ours.FightFirst), refuses. 2, the claim (another hero holds the target, `holds`), and 3, the go-by (the
-- time to go by has passed), are asked and logged and refuse nothing: each still lives in its row (the creep row's `FreeFor`,
-- each row's own `by`) and refuses here once the conversion that removes the row's own check (route step 3) shows its shadow at 0.
-- 4, danger at the place, is `begin`'s once the begin went (`Danger.At`, logged only, until its shadow is graded); 5, the order,
-- is `pick`'s.
local function accept(bot, offer, mode)
    if FIGHT[mode] == true and OursOn("FightFirst") then
        return {no = "fight", others = 0}
    end
    local pid = bot:GetPlayerID()
    local others = 0
    local would
    if offer.tgt ~= nil then
        for ____, c in ipairs(Claims.ClaimsOn(offer.tgt)) do
            do
                local __continue12
                repeat
                    if c.pid == pid then
                        __continue12 = true
                        break
                    end
                    others = others + 1
                    if holds(c, offer.claim) then
                        would = "claim"
                    end
                    __continue12 = true
                until true
                if not __continue12 then
                    break
                end
            end
        end
    end
    if would == nil and offer.by ~= nil and DotaTime() > offer.by then
        would = "late"
    end
    return {would = would, others = others}
end
--- The one place a row's task starts: acceptance (`accept`), then the row's own begin; the decider takes the offer's target as the hero's claim.
local function begin(bot, s, row, offer)
    local over = runningTask(bot)
    local mode = bot:GetActiveMode()
    local from = HDebug.ModeName(mode)
    local v = accept(bot, offer, mode)
    if v.no ~= nil then
        refuse(bot, s, {row = row.name, tgt = offer.tgt, why = v.no, mode = from})
        return false
    end
    s.refLines = nil
    local ok, res = pcall(function() return Tasks.Begin(
        row.name,
        function() return row.begin(bot) end
    ) end)
    if (not ok or res == true) and offer.tgt ~= nil and runningTask(bot) == row.name then
        local c = offer.claim
        Claims.Take(
            offer.tgt,
            {
                pid = bot:GetPlayerID(),
                rank = c and c.rank,
                k = c and c.k,
                due = c and c.due,
                phase = c and c.phase
            }
        )
        s.claimRow = row.name
    end
    if not ok then
        error(res, 0)
    end
    if res ~= true then
        return false
    end
    s.refused[row.name] = nil
    local d
    local dfail
    if offer.at ~= nil and Telemetry.IsEnabled() then
        local at = offer.at
        local dok, dres = pcall(function() return Danger.At(bot, at, offer.secs) end)
        if dok then
            d = dres
        else
            dfail = true
        end
    end
    s.begun = {
        row = row,
        offer = offer,
        over = over,
        from = from,
        v = v,
        d = d,
        dfail = dfail
    }
    return true
end
--- Tasks' end hook for a row's task: the claim that row's begin took is released (after the row's own end, which may read it).
local function rowEnded(bot, name)
    local s = heroes[bot:GetPlayerID()]
    if s == nil or s.claimRow ~= name then
        return
    end
    s.claimRow = nil
    Claims.Release(bot:GetPlayerID())
end
Tasks.OnRowEnd(rowEnded)
--- Why the decider last refused to begin `row` for this hero, once (it is forgotten on reading): `fight` (the hero was in attack,
-- roam or team roam, Ours.FightFirst). A row reads it after a begin it asked for did not happen. Undefined when none is kept.
function ____exports.Refusal(bot, row)
    local s = heroes[bot:GetPlayerID()]
    local r = s and s.refused[row]
    if r == nil then
        return nil
    end
    s.refused[row] = nil
    return r.why
end
--- One row's turn: its offer, and its begin when its task does not run. Undefined when it does not want the hero or the begin was refused.
local function turn(bot, s, row)
    local offer = row.wants(bot, READS)
    if offer == nil then
        return nil
    end
    if runningTask(bot) == row.name or begin(bot, s, row, offer) then
        return offer
    end
    return nil
end
--- A refused begin passes the turn to the next row.
local function pick(bot, s)
    for ____, row in ipairs(____exports.ROWS) do
        if turn(bot, s, row) ~= nil then
            return row
        end
    end
    return nil
end
--- Chooser.Gate, for every gated mode file: the desire `mode`'s file returned to Valve. A value that is not a number (Valve's
-- own desire falls through) is not known, so it is forgotten.
function ____exports.NoteDesire(bot, mode, v)
    local seen = stateOf(bot).seen
    if type(v) ~= "number" then
        seen[mode] = nil
        return
    end
    local n = seen[mode]
    if n == nil then
        seen[mode] = {
            v = v,
            t = DotaTime()
        }
    else
        n.v = v
        n.t = DotaTime()
    end
end
--- Plan s3, user 23/11/2026: stock would retreat when the retreat file's desire leads every other mode the hold outbids. Each
-- value is the file's latest within FRESH, as Valve's order of calls gives it, so the read can lag the retreat call by a
-- round. Valve-only modes (attack for most heroes, item, evasive) have no file and are not seen. Every error of this read
-- should only yield to stock, so a tie with a rival lets go (Valve's tie-break is not known); a retreat at 0 never leads.
-- Returns the leading retreat value, else undefined.
local function retreatLeads(s)
    local now = DotaTime()
    local r = s.seen.retreat
    if r == nil or r.v <= 0 or now - r.t > FRESH then
        return nil
    end
    for mode, n in pairs(s.seen) do
        do
            local __continue48
            repeat
                if mode == "retreat" or mode == HOST or now - n.t > FRESH then
                    __continue48 = true
                    break
                end
                if n.v > r.v then
                    return nil
                end
                __continue48 = true
            until true
            if not __continue48 then
                break
            end
        end
    end
    return r.v
end
--- `win` is the mode Valve gave the hero from the last round's desires, read at this round's farm call: Valve asks every mode
-- once a round, so the hold or yield decided now shows up in the next line.
local function note(bot, s, heldRow, softNow)
    if heldRow == nil then
        heldRow = s.held
    end
    if softNow == nil then
        softNow = s.soft
    end
    local b = s.begun
    s.begun = nil
    if not Telemetry.IsEnabled() then
        return
    end
    local held = heldRow and heldRow.name or "-"
    local win = HDebug.ModeName(bot:GetActiveMode())
    local let_ = s.letAt ~= nil
    local soft = softNow == true
    if b == nil and held == s.lineHeld and win == s.lineWin and let_ == s.lineLet and soft == s.lineSoft then
        return
    end
    s.lineHeld = held
    s.lineWin = win
    s.lineLet = let_
    s.lineSoft = soft
    local fields = {
        {
            "pid",
            bot:GetPlayerID()
        },
        {"kind", "decider"},
        {"held", held},
        {"win", win}
    }
    if heldRow ~= nil then
        fields[#fields + 1] = {"hs", soft and "soft" or "hard"}
    end
    if s.letAt ~= nil then
        __TS__ArrayPush(fields, {"let", "retreat"}, {"d_retreat", s.letAt})
    end
    if b ~= nil then
        __TS__ArrayPush(
            fields,
            {"beg", b.row.name},
            {"btgt", b.offer.tgt},
            {
                "bby",
                b.offer.by ~= nil and math.floor(b.offer.by * 10 + 0.5) / 10 or nil
            },
            {"over", b.over},
            {"bfrom", b.from},
            {"bway", b.offer.way},
            {"bacc", b.v.would},
            {"bcl", b.v.others > 0 and b.v.others or nil}
        )
        if b.offer.at ~= nil then
            __TS__ArrayPush(
                fields,
                {
                    "bpx",
                    math.floor(b.offer.at.x)
                },
                {
                    "bpy",
                    math.floor(b.offer.at.y)
                }
            )
        end
        if b.d ~= nil then
            for ____, f in ipairs(Danger.Fields(b.d)) do
                fields[#fields + 1] = f
            end
        end
        if b.dfail == true then
            fields[#fields + 1] = {"dfail", 1}
        end
    end
    Telemetry.Event("choice", fields)
end
--- Wraps the host file's GetDesire: a held row's strength, else the inner desire unchanged. A row does not hold while stock would retreat.
function ____exports.Host(bot, inner)
    return function()
        local s = stateOf(bot)
        if FIGHT[bot:GetActiveMode()] ~= true then
            s.refLines = nil
        end
        local row = pick(bot, s)
        local ____temp_21
        if row ~= nil then
            ____temp_21 = retreatLeads(s)
        else
            ____temp_21 = nil
        end
        s.letAt = ____temp_21
        local ____temp_22
        if s.letAt == nil then
            ____temp_22 = row
        else
            ____temp_22 = nil
        end
        s.held = ____temp_22
        s.soft = s.held ~= nil and isSoft(s.held, bot)
        pcall(function() return note(bot, s) end)
        if s.held == nil then
            return inner()
        end
        if not s.soft then
            return ____exports.HARD
        end
        return bot:GetActiveMode() == BotMode.Farm and ____exports.SOFT / ____exports.BONUS or ____exports.SOFT
    end
end
--- Chooser.Gate, for every gated mode file, after NoteDesire saw the value as returned: while a soft row holds, an OHA Lua
-- mode's desire above CAP is returned as CAP, so only the Valve-only modes, retreat and attack's file outbid the hold. The
-- hold is the one decided at the last farm call, so files Valve asks before farm lag by one round: uncapped in the round a
-- soft hold starts, still capped in the round it lets go or stops wanting the hero. The cap follows `held`, so the lag cannot
-- flicker on its own. Anything else, and any value that is not a number, passes unchanged.
-- 
-- Known effect, not stock's: retreat is uncapped, so a retreat value between the hold's worth (about SOFT; SOFT / BONUS in a
-- round Valve gives the active farm no bonus) and the highest raw Lua mode wins the hero
-- from the hold although the retreat read (raw values) keeps holding; stock would have run that Lua mode. Plan s3 accepts
-- it ("retreat excepted"); the first soft row's smoke counts it.
function ____exports.Cap(bot, mode, v)
    local s = heroes[bot:GetPlayerID()]
    if s == nil or s.held == nil or s.soft ~= true or UNCAPPED[mode] == true or type(v) ~= "number" then
        return v
    end
    return v > ____exports.CAP and ____exports.CAP or v
end
--- Wraps the host file's Think: a held row's verb, not stepped while the bot cannot act (as Chooser.HostThink), else the inner Think.
function ____exports.HostThink(bot, inner, cannotAct)
    return function()
        local row = stateOf(bot).held
        if row == nil then
            return inner()
        end
        if cannotAct(bot) then
            return nil
        end
        if row.step(bot) then
            stateOf(bot).held = nil
        end
        return nil
    end
end
--- A row that decides at a read of its own (the creep row, at the creep offer read) asks to be begun now, so its start keeps the
-- read's moment. Begun when no row above it holds the hero (its task runs). The rows above are not asked `wants` here: theirs
-- takes the lane read and writes its decision lines at the moment it is first asked, so a second ask between rounds would move
-- them. Their last round's answer adds nothing: a row picked then has its task running now, unless that task has ended, and
-- then the row no longer wants the hero. A row above that comes to want the hero takes it at the next round (`over`). The row's
-- own `wants` is asked for the offer. True when the row was begun; a row not in ROWS is never begun.
-- What a row wants (offers-and-the-decider s3), every field optional and logged when the row is begun: its target (a name or id,
-- the claim's key), the game time it must go by, how it is taken (`way`: `attack`, `deny`, `spell`; absent where a row has one
-- way), what its claim carries (`claim`: the creep row's rank, kind, due time and phase), where the hero stands to act (`at`) and
-- the seconds it is held (`secs`, the walk back included where the row knows it): the danger at the place is asked for those
-- (`Danger.At`). The other fields of s3 (gain, phases, end) arrive with the first code that reads each.
function ____exports.Offer(bot, row)
    local at = __TS__ArrayIndexOf(____exports.ROWS, row)
    if at < 0 then
        return false
    end
    local s = stateOf(bot)
    local cur = runningTask(bot)
    do
        local i = 0
        while i < at do
            if cur == ____exports.ROWS[i + 1].name then
                return false
            end
            i = i + 1
        end
    end
    local offer = row.wants(bot, READS)
    if offer == nil or cur == row.name or not begin(bot, s, row, offer) then
        return false
    end
    pcall(function() return note(
        bot,
        s,
        row,
        isSoft(row, bot)
    ) end)
    return true
end
--- Whether `task` is the task of a row below `row` in doctrine order: a begin of `row` may take the hero from it (`over`), as `Host`
-- does at a round. False for any other task (a row above, a job no row started) and for a row not in ROWS.
function ____exports.Below(row, task)
    local at = __TS__ArrayIndexOf(____exports.ROWS, row)
    if at < 0 or task == nil then
        return false
    end
    do
        local i = at + 1
        while i < #____exports.ROWS do
            if ____exports.ROWS[i + 1].name == task then
                return true
            end
            i = i + 1
        end
    end
    return false
end
--- One row's turn as `Host` takes it, for that row alone (tests): true when it holds the hero, begun now or running.
function ____exports.Ask(bot, row)
    local s = stateOf(bot)
    local held = turn(bot, s, row) ~= nil
    s.begun = nil
    return held
end
--- The decider is yielding this hero to stock's retreat although a row wanted it (a cut row names it as its end's reason).
function ____exports.LetGo(bot)
    return stateOf(bot).letAt ~= nil
end
--- Whether the held row's hold was soft at this hero's last farm desire round (the overlay; the answer `Host` got, so a function-valued `Row.soft` counts).
function ____exports.Soft(bot)
    local ____opt_23 = heroes[bot:GetPlayerID()]
    return (____opt_23 and ____opt_23.soft) == true
end
--- The row that held this hero at its last farm desire round, if any (the overlay).
function ____exports.Held(bot)
    local ____opt_25 = heroes[bot:GetPlayerID()]
    return ____opt_25 and ____opt_25.held
end
--- Tests: forget every hero.
function ____exports.Reset()
    for k in pairs(heroes) do
        heroes[k] = nil
    end
    Claims.ResetCache()
end
return ____exports
