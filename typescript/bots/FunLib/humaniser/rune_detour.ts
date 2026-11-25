/**
 * The own bounty on a cheap detour (doctrine D26; families proposal s7, case 1; a small row, plan s5), switch Ours.RuneDetour.
 * A hero of ours out of its lane that passes its own jungle's live bounty takes it when the path by the rune adds about
 * Budget seconds or less; otherwise the hero is stock's. One hero, no threat input beyond the shared read's deadly answer.
 *
 * A pass is a run of reads in which the hero is alive, out of its own lane, within Radius of its own bounty while that rune
 * is available, before Until: the same rule hlog's @rune_passes reads from places and pickups, here from the API. Each pass
 * writes one `ev=choice kind=rune_detour` line: as it starts its first walk (`go=1`), or as it ends untaken (`go=0`, `why` what
 * held it: `detour`, `danger`, `busy` (a mode outside FROM), `ally`). Switched off, the same read is logged as the shadow (`src=shadow go=0
 * why=off`, `want` as the row would have read it). A started walk runs as `ev=job job=rune_detour` (engine `pickUpRune`);
 * its end's `why` is the engine verb's (`ok` when GetRuneStatus left available at the rune). That status can stay available after a
 * pickup (rdon1, 23/11/2026: the Radiant pos5's gold rose 47 at its 4:00 rune, the status stayed available to 8:00), so the walk
 * also reads its own gold: `took=1` when one step's gain is at least TookGold. The status reads available until the spot's last
 * rune is gone (an untaken bounty stays when the next spawns, so runes pile up on a spot), so while it reads available after a
 * walk the hero walks again and takes every rune lying there (user 24/11/2026; round 1, rdon2 to rdon4: three ready reps by a
 * second rune refused after a take). Only walks that end untaken count: Misses a spawn at most, so a rune that cannot be taken
 * does not hold the hero.
 */
import type * as Lib from "bots/FunLib/engine/tasks";
import { BotMode, Rune, Unit, Vector } from "bots/ts_libs/dota";
import * as Decider from "bots/FunLib/humaniser/decider";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Drill from "bots/FunLib/humaniser/drill";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Runes from "bots/FunLib/humaniser/game_rules";
import * as SafeGather from "bots/FunLib/humaniser/safe_gather";
import { ForOurs as Tasks } from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

declare function GetRuneStatus(this: void, rune: number): number;
declare function GetRuneSpawnLocation(this: void, rune: number): Vector;
declare const RUNE_STATUS_AVAILABLE: number;

export const SETTINGS = {
    /** Seconds the path by the rune may add (judgement: the families proposal s7, user 24/11/2026). */
    Budget: 12,
    /** A pass is read within this of the rune: @rune_passes' radius (the base walk's nearest point is about 1,300 to 1,750). */
    Radius: 1800,
    /** Farther than this from its own lane is out of it: hlog's LANE_R (dynamic.js), so both arms' passes read alike. */
    LaneR: 1100,
    /** Spawns before this (s): the laning stage, as @rune_passes' default `until`. */
    Until: 600,
    /** The walk's cap: its predicted seconds plus this (judgement), then the job ends `timeout`. */
    Slack: 4,
    /** A gold gain this large between two steps of the walk is the pickup (judgement: a 4:00 bounty is about 40 at face). */
    TookGold: 20,
    /**
     * Seconds the row yields after a walk ends before another may start: the mode read is the hold's own host (farm) until
     * Valve has picked from the other modes again (Decider FRESH; review 24/11/2026).
     */
    Rest: 0.5,
    /** Walks for one spawn that may end untaken (no gold jump) before the hero stops going for that spot (judgement). */
    Misses: 2,
};

/** The task's host: the decider's (farm). */
const HOST = BotMode.Farm;

interface Pass {
    spawn: number;
    rune: number;
    /** The smallest detour seen in this pass (s). */
    ex: number;
    dr: number;
    want: boolean;
    why?: string;
    /** Its line went out (at the first walk's start): a later walk for the same pass writes none. */
    logged?: boolean;
}

interface Read {
    rune: number;
    at: Vector;
    spawn: number;
    /** Distance to the rune. */
    dr: number;
    /** Seconds the path by the rune adds to the walk to the hero's lane front. */
    ex: number;
}

const passes: Record<number, Pass | undefined> = {};
/** pid -> the spawn this hero last went for and how many of its walks for it ended untaken. */
const went: Record<number, { spawn: number; misses: number } | undefined> = {};

interface Walk {
    /** The attempt id (Telemetry.NextAid): the pass's go choice line carries it for the first walk; a later walk of the pass takes a new one at its start. */
    aid: number;
    rune: number;
    gold: number;
    /** The largest gain between two steps. */
    jump: number;
}
/** pid -> its walk while it runs. */
const running: Record<number, Walk | undefined> = {};
/** pid -> when its last walk ended. */
const endedAt: Record<number, number | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(passes)) passes[k as number] = undefined;
    for (const [k] of pairs(went)) went[k as number] = undefined;
    for (const [k] of pairs(running)) running[k as number] = undefined;
    for (const [k] of pairs(endedAt)) endedAt[k as number] = undefined;
}

export function On(): boolean {
    return Ours.On("RuneDetour");
}

/** The bounty in this team's own jungle: of the two jungle bounties (Bounty1, Bounty2), the one nearer its ancient. */
export function OwnRune(team: number): number {
    const anc = GetAncient(team as never).GetLocation();
    const a = GetRuneSpawnLocation(Rune.Bounty1);
    const b = GetRuneSpawnLocation(Rune.Bounty2);
    const d = (v: Vector) => (v.x - anc.x) * (v.x - anc.x) + (v.y - anc.y) * (v.y - anc.y);
    return d(a) <= d(b) ? Rune.Bounty1 : Rune.Bounty2;
}

/** The bounty spawn this rune's live window belongs to (4:00, 8:00, ...). */
export function SpawnOf(now: number): number {
    const every = Runes.RUNE_RULES.bounty.every;
    return math.floor(math.max(now, 0) / every) * every;
}

function dist(a: Vector, b: Vector): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

/**
 * The pass read, the same in both arms: undefined when this is no pass. The detour is straight-line distances at the hero's
 * movement speed, to the front of its own lane (where a hero out of lane walks back to; `judgement`: its real goal and the
 * path are not read).
 */
export function ReadPass(bot: Unit, now: number = DotaTime()): Read | undefined {
    if (!bot.IsAlive() || now >= SETTINGS.Until) return undefined;
    const spawn = SpawnOf(now);
    // The 0:00 bounties are stock's (no gap: families s7).
    if (spawn <= 0) return undefined;
    const rune = OwnRune(bot.GetTeam());
    if (GetRuneStatus(rune) !== RUNE_STATUS_AVAILABLE) return undefined;
    const at = GetRuneSpawnLocation(rune);
    const me = bot.GetLocation();
    const dr = dist(me, at);
    if (dr > SETTINGS.Radius) return undefined;
    const lane = bot.GetAssignedLane();
    if (GetAmountAlongLane(lane, me).distance <= SETTINGS.LaneR) return undefined;
    const front = GetLaneFrontLocation(bot.GetTeam(), lane, 0);
    const speed = math.max(100, bot.GetCurrentMovementSpeed());
    const ex = math.max(0, dr + dist(at, front) - dist(me, front)) / speed;
    return { rune, at, spawn, dr, ex };
}

/**
 * The modes the row may take a hero from: a hero walking, farming, laning or shopping. Any other (a gank, a rotation to defend,
 * a fight, a retreat) is a higher rule's, and the hold (Decider.HARD) would outbid it (review 24/11/2026).
 */
const FROM: Record<number, boolean> = { [BotMode.None]: true, [BotMode.Laning]: true, [BotMode.Farm]: true, [BotMode.Rune]: true, [BotMode.Item]: true };

/** What holds a cheap detour back now, else undefined. */
function block(bot: Unit, r: Read): string | undefined {
    if (FROM[bot.GetActiveMode()] !== true) return "busy";
    for (const [pid, w] of pairs(running)) if (w.rune === r.rune && pid !== bot.GetPlayerID()) return "ally";
    if (SafeGather.At(bot, r.at, { who: "rune_detour" }).level === "deadly") return "danger";
    return undefined;
}

function choiceLine(bot: Unit, p: Pass, go: boolean, why: string | undefined, src: string, aid?: number): void {
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "rune_detour"],
        ["aid", aid],
        ["go", go ? 1 : 0],
        ["want", p.want ? 1 : 0],
        ["why", why],
        ["src", src],
        ["lane", bot.GetAssignedLane()],
        ["slot", p.spawn],
        ["rune", p.rune],
        ["ex", math.floor(p.ex * 10 + 0.5) / 10],
        ["dr", math.floor(p.dr + 0.5)],
    ]);
}

function jobLine(bot: Unit, phase: string, why: string, ex?: number, cut?: string, w?: Walk, took?: boolean, start?: Walk): void {
    const a = w ?? start;
    Telemetry.Event("job", [
        ["pid", bot.GetPlayerID()],
        ["job", "rune_detour"],
        ["aid", a?.aid],
        ["tgt", start !== undefined ? `rune:${start.rune}` : undefined],
        ["phase", phase],
        ["why", why],
        ["host", HOST],
        ["ex", ex !== undefined ? math.floor(ex * 10 + 0.5) / 10 : undefined],
        ["cut", cut],
        ["took", took !== undefined ? (took ? 1 : 0) : undefined],
        ["gj", w !== undefined ? w.jump : undefined],
    ]);
}

/** Each step of the walk and at its end: the largest gold gain between two reads. */
function noteGold(bot: Unit, w: Walk): void {
    const g = bot.GetGold();
    if (g - w.gold > w.jump) w.jump = g - w.gold;
    w.gold = g;
}

/**
 * One read of the pass for `bot`: opens, updates or closes its Pass. Returns the read when the pass is open and has not been
 * logged, else undefined. A closed pass writes its line with `src`.
 */
function observe(bot: Unit, src: string, now: number): Read | undefined {
    const pid = bot.GetPlayerID();
    const r = ReadPass(bot, now);
    let p = passes[pid];
    if (p !== undefined && (r === undefined || r.spawn !== p.spawn)) {
        if (p.logged !== true) choiceLine(bot, p, false, src === "shadow" ? "off" : p.why ?? "detour", src);
        passes[pid] = undefined;
        p = undefined;
    }
    const w = went[pid];
    if (r === undefined || (w !== undefined && w.spawn === r.spawn && w.misses >= SETTINGS.Misses)) return undefined;
    if (p === undefined) {
        p = { spawn: r.spawn, rune: r.rune, ex: r.ex, dr: r.dr, want: false };
        passes[pid] = p;
    } else if (r.ex < p.ex) {
        p.ex = r.ex;
        p.dr = r.dr;
    }
    return r;
}

/**
 * The reference arm's denominator: where the row is off, the same pass read and the same line (`src=shadow go=0 why=off`).
 * `want` is set when the detour was within budget at some read, as the row sets it. Reads and logs; nothing is ordered.
 */
export function Shadow(bot: Unit): void {
    if (!Telemetry.IsEnabled() || On() || Drill.Held(bot)) return;
    const now = DotaTime();
    const r = observe(bot, "shadow", now);
    if (r === undefined) return;
    const p = passes[bot.GetPlayerID()]!;
    if (r.ex <= SETTINGS.Budget) p.want = true;
}

function finish(bot: Unit, ex: number, res: Lib.Result): void {
    const pid = bot.GetPlayerID();
    const w = running[pid];
    running[pid] = undefined;
    endedAt[pid] = DotaTime();
    if (w !== undefined) noteGold(bot, w);
    // The verb's ok (the status left available at the rune) is a pickup too: the gold can land a frame after it (rdaud s25).
    const took = res.success || (w !== undefined && w.jump >= SETTINGS.TookGold);
    const g = went[pid];
    if (g !== undefined && !took) g.misses++;
    const cut = !res.success && res.reason === "preempted" ? (Decider.LetGo(bot) ? "retreat" : HDebug.ModeName(bot.GetActiveMode())) : undefined;
    jobLine(bot, "end", res.success ? "ok" : res.reason, ex, cut, w, took);
}

/** The row's `applies`: true while a walk runs or as one starts. */
function rowApplies(bot: Unit): boolean {
    if (!On() || Drill.Held(bot)) return false;
    const pid = bot.GetPlayerID();
    Tasks.Tick(bot);
    if (running[pid] !== undefined) return true;
    if (Tasks.Jobs() === undefined) return false;
    const now = DotaTime();
    const ended = endedAt[pid];
    if (ended !== undefined && now - ended < SETTINGS.Rest) return false;
    const r = observe(bot, "own", now);
    if (r === undefined) return false;
    const p = passes[pid]!;
    if (r.ex > SETTINGS.Budget) {
        if (!p.want) p.why = "detour";
        return false;
    }
    p.want = true;
    const why = block(bot, r);
    if (why !== undefined) {
        p.why = why;
        return false;
    }
    const ex = r.ex;
    const timeout = r.dr / math.max(100, bot.GetCurrentMovementSpeed()) + SETTINGS.Slack;
    const ok = Tasks.Start(bot, { name: "rune_detour", host: HOST, preemptAfter: 1, stallAfter: 4, onEnd: (res) => finish(bot, ex, res) }, () =>
        Tasks.Verbs()!.pickUpRune(bot as unknown as Lib.TaskUnit, r.rune, { at: r.at, timeout })
    );
    const g = went[pid];
    if (g === undefined || g.spawn !== r.spawn) went[pid] = { spawn: r.spawn, misses: 0 };
    // One line a pass: a later walk for the same pass (a rune piled on the spot) writes none.
    const aid = ok ? Telemetry.NextAid(pid) : undefined;
    if (p.logged !== true) choiceLine(bot, p, ok, ok ? undefined : "refused", "own", aid);
    p.logged = true;
    if (!ok) return false;
    const walk: Walk = { aid: aid!, rune: r.rune, gold: bot.GetGold(), jump: 0 };
    running[pid] = walk;
    jobLine(bot, "start", "pass", ex, undefined, undefined, undefined, walk);
    return true;
}

/** The row's verb: one frame of the walk; true once it has ended. */
function rowStep(bot: Unit): boolean {
    const w = running[bot.GetPlayerID()];
    if (w !== undefined) noteGold(bot, w);
    Tasks.Step(bot, HOST);
    return running[bot.GetPlayerID()] === undefined;
}

/** The decider's row (registered in index.ts, so the decider imports no row). */
export const ROW: Decider.Row = { name: "rune_detour", applies: rowApplies, step: rowStep };
