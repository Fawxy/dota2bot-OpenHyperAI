/**
 * The decider (plan s3, docs/proposals/2026-11-23-laning-plan-after-the-bisect.md): one per hero of ours, hosted in farm's mode
 * file, on both teams. Rows are behaviours in doctrine order, each behind its own Ours switch (so Ours.Team scopes it); the
 * first that wants the hero holds it, else the decider yields and farm's own desire and Think run untouched (stock's, or
 * today's per-mode code while it lasts). Desire exists here only as the wire to the engine: a row names no number.
 *
 * Only the decider starts a row's task (master docs/proposals/2026-11-26-decider-owns-starts.md s3). A row says whether it wants
 * the hero (`wants`, asked in doctrine order each round, which starts nothing) and starts its task when told (`begin`). A start
 * replaces the hero's running task, so a higher row begun while a lower row's task runs takes the hero from it, and the line
 * says so (`over`); a lower row is not asked while a higher one wants. A row that decides at a read of its own between rounds
 * (the creep row) asks to be begun through `Offer`.
 *
 * Built so far: the yield, the hard and soft holds, and letting go when stock would retreat. Worth with an incumbent margin
 * and the label hook arrive with the first row that needs each (plan s3).
 *
 * The decider wraps outside Chooser's gate in farm's file: while a row holds, farm's gated code does not run, so the job
 * chooser and the shadow line say nothing for that time. A row is re-picked every round and is not told when another mode
 * takes the hero, so its verb must cope with being cut off between any two steps.
 */
import { BotMode, Unit, Vector } from "bots/ts_libs/dota";
import * as Claims from "bots/FunLib/humaniser/claims";
import * as Danger from "bots/FunLib/humaniser/danger";
import * as HDebug from "bots/FunLib/humaniser/debug";
import { On as OursOn } from "bots/FunLib/humaniser/ours";
import { READS } from "bots/FunLib/humaniser/reads";
import type { Reads } from "bots/FunLib/humaniser/reads";
import * as Tasks from "bots/FunLib/humaniser/tasks";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

/**
 * What a row wants (offers-and-the-decider s3), every field optional and logged when the row is begun: its target (a name or id,
 * the claim's key), the game time it must go by, how it is taken (`way`: `attack`, `deny`, `spell`; absent where a row has one
 * way), what its claim carries (`claim`: the creep row's rank, kind, due time and phase), where the hero stands to act (`at`) and
 * the seconds it is held (`secs`, the walk back included where the row knows it): the danger at the place is asked for those
 * (`Danger.At`). The other fields of s3 (gain, phases, end) arrive with the first code that reads each.
 */
export interface Offer {
    tgt?: string;
    by?: number;
    way?: string;
    claim?: Omit<Claims.Claim, "pid">;
    at?: Vector;
    secs?: number;
}

export interface Row {
    /** Logged as `held`; also the name of the row's task, which is how the decider sees that the row's task runs. */
    name: string;
    /**
     * Cheap; asked every scoring round in doctrine order, until a row answers. An offer while the row's task runs (it holds) or
     * when it would start one now. It may keep the row's memo and write the row's own decision line; it starts, cancels and
     * orders nothing. What it decided for a start is kept for `begin`. Facts of the lane, camp or team come from `reads` (reads.ts), not from another row's file.
     */
    wants(this: void, bot: Unit, reads: Reads): Offer | undefined;
    /** Starts the row's task as `wants` decided it; false when the runner refused. Called only by the decider. */
    begin(this: void, bot: Unit): boolean;
    /** One frame of the row's verb, from farm's Think while the row holds; true when the row is finished. */
    step(this: void, bot: Unit): boolean;
    /**
     * True: the row holds at SOFT, so the Valve-only modes take the hero when they want it (plan s3). Absent: HARD. A function is asked once
     * each round (in `Host`), so a row can hold soft in one phase of its verb and hard in another.
     * CANDIDATE(soft-per-phase): no row uses the function form today; ARCHITECTURE rule 10 wants a hold per phase.
     */
    soft?: boolean | ((this: void, bot: Unit) => boolean);
}

/**
 * Plan s3: above 0.95, the most Valve's attack showed, and at most 1.0, since above it J.IsRetreating reads a farm-mode
 * hero as retreating; under OHA's retreat latch (1.1). The value inside that band is judgement.
 */
export const HARD = 0.98;

/**
 * Plan s3: what a soft hold is worth to Valve, entering or held: above laning's desire (0.45) and under every entry of Valve's
 * attack (none of 7,419 in h2hoha742 under 0.5), so attack, item, evasive and defend-ally outbid it when they want the hero.
 * The value inside that band is judgement.
 */
export const SOFT = 0.495;

/**
 * Valve multiplies the active mode's desire by about this (derived: ev=snap d over the file's own value, oha-solo-deny
 * 22574266: laning 0.446 reads 0.491, an active soft hold 0.49 reads 0.539; not every round, and the hard hold's 0.98 was
 * never boosted). While the host mode is active a soft hold returns SOFT / BONUS, so it is worth about SOFT either way.
 */
export const BONUS = 1.1;

/**
 * judgement: the most an OHA Lua mode file may return while a soft row holds (plan s3: the gate caps them beneath it).
 * With Valve's bonus on the active mode (CAP x BONUS, 0.484) it stays under SOFT, so an active capped mode cannot keep the
 * hero from a soft hold.
 */
export const CAP = 0.44;

/**
 * Not capped under a soft hold: retreat (stock's way out; when it leads, the retreat read lets go) and attack's own file
 * (OHA's override of Valve's attack for a few heroes: the mode a soft hold gives way to; beyond plan s3's "retreat
 * excepted", decided 24/11/2026). `farm` is a guard only: while a row holds, Host never calls farm's gated desire.
 */
const UNCAPPED: Record<string, boolean> = { retreat: true, attack: true, farm: true };

/** Doctrine order: the first row that wants the hero holds it. index.ts fills it through `Add` with the pull, stack, rune detour, creep and draw (aggro) rows (in that order), so no row is imported here; with none registered the decider is a pass-through. */
export const ROWS: Row[] = [];

/** The one way to add a row: appends it to ROWS (once) and guards its task name, so only the decider's begin starts that task. */
export function Add(row: Row): void {
    Tasks.GuardRowTask(row.name);
    if (ROWS.indexOf(row) < 0) ROWS.push(row);
}

/**
 * The mode file that hosts the decider. Never a rival in the retreat read: its own desire is not computed while a row holds,
 * and counting it only when fresh (the round after a yield) would make the hold flicker every other round.
 */
const HOST = "farm";

/**
 * judgement: a mode's value older than this is from neither this round nor the last (Valve asks every mode every round), so
 * its file was not asked and its value is not a rival.
 */
const FRESH = 0.5;

interface Seen {
    v: number;
    t: number;
}

/** A begin since the last line: what the line carries once. */
interface Begun {
    row: Row;
    offer: Offer;
    /** The task the begin replaced (a lower row's, or an older job's). */
    over?: string;
    /** The mode Valve had the hero in at the moment of the begin (the creep row's `Offer` falls between rounds, so not `note`'s read). */
    from: string;
    /** Acceptance's answer (`accept`). */
    v: Verdict;
    /** Danger at the offer's place (s4 step 4, `Danger.At`), asked at the begin and logged; undefined when the offer names no place or the read failed. */
    d?: Danger.Parts;
    /** `Danger.At` raised an error at this begin (logged as `dfail`). */
    dfail?: boolean;
}

/** A begin the decider refused: kept for the row to read (`Refusal`), and logged once per row and target. */
interface Refused {
    row: string;
    tgt?: string;
    why: string;
    mode: string;
}

interface HeroState {
    held?: Row;
    begun?: Begun;
    /** The row whose begin took the hero's claim (`Claims`), released when that row's task ends (`rowEnded`). */
    claimRow?: string;
    /** Per row, the last begin refused since the row read it (`Refusal`); a begin of that row clears it. */
    refused: Record<string, Refused | undefined>;
    /** The rows and targets refused since the hero was last out of a fight, so each refusal is logged once while it repeats. */
    refLines?: Record<string, boolean>;
    /** Set when a row wanted the hero but stock would retreat: the retreat file's value that led. */
    letAt?: number;
    /** Whether the held row's hold is soft, as `Host` asked it this round; `Cap` and the line read this. */
    soft?: boolean;
    /** Each gated mode file's last returned desire (NoteDesire). */
    seen: Record<string, Seen>;
    /** What the last line said, so a line goes out only on a change. */
    lineHeld?: string;
    lineWin?: string;
    lineLet?: boolean;
    lineSoft?: boolean;
}

const heroes: Record<number, HeroState> = {};

function stateOf(bot: Unit): HeroState {
    const pid = bot.GetPlayerID();
    let s = heroes[pid];
    if (s === undefined) {
        s = { seen: {}, refused: {} };
        heroes[pid] = s;
    }
    return s;
}

function isSoft(row: Row, bot: Unit): boolean {
    return typeof row.soft === "function" ? row.soft(bot) : row.soft === true;
}

/** The name of the hero's running task, however the runner was loaded. */
function runningTask(bot: Unit): string | undefined {
    return Tasks.ForOurs.Running(bot)?.name;
}

/**
 * The modes a row's start is refused from (offers-and-the-decider s4 1a, user 27/11/2026: a row never starts over a fight;
 * fights stay Valve's). A row already holding the hero when a fight starts is not cut by this.
 */
const FIGHT: Record<number, boolean> = { [BotMode.Attack]: true, [BotMode.Roam]: true, [BotMode.TeamRoam]: true };

/**
 * Acceptance's answer for one offer: `no`, the check that refuses it; `would`, the first check asked but not yet allowed to refuse
 * (logged as `bacc`); `others`, how many other heroes of ours hold a claim on its target.
 */
interface Verdict {
    no?: string;
    would?: string;
    others: number;
}

/** Another hero's claim the offer may not take (s4 step 2): lower goes first, so one with no rank on either side, or a rank at or under this one's, holds. */
function holds(c: Claims.Claim, mine: Offer["claim"]): boolean {
    return c.rank === undefined || mine?.rank === undefined || c.rank <= mine.rank;
}

/**
 * Acceptance (offers-and-the-decider s4), the same for a polled row and an offered one, its checks in s4's order. Step 1 (a row
 * above holds the hero) is `Offer`'s, before the row's `wants` is asked; a polled row is asked only when no row above wanted the
 * hero. 1a, the fight (Ours.FightFirst), refuses. 2, the claim (another hero holds the target, `holds`), and 3, the go-by (the
 * time to go by has passed), are asked and logged and refuse nothing: each still lives in its row (the creep row's `FreeFor`,
 * each row's own `by`) and refuses here once the conversion that removes the row's own check (route step 3) shows its shadow at 0.
 * 4, danger at the place, is `begin`'s once the begin went (`Danger.At`, logged only, until its shadow is graded); 5, the order,
 * is `pick`'s.
 */
function accept(bot: Unit, offer: Offer, mode: number): Verdict {
    if (FIGHT[mode] === true && OursOn("FightFirst")) return { no: "fight", others: 0 };
    const pid = bot.GetPlayerID();
    let others = 0;
    let would: string | undefined;
    if (offer.tgt !== undefined) {
        for (const c of Claims.ClaimsOn(offer.tgt)) {
            if (c.pid === pid) continue;
            others++;
            if (holds(c, offer.claim)) would = "claim";
        }
    }
    if (would === undefined && offer.by !== undefined && DotaTime() > offer.by) would = "late";
    return { would, others };
}

/** The one place a row's task starts: acceptance (`accept`), then the row's own begin; the decider takes the offer's target as the hero's claim. */
function begin(bot: Unit, s: HeroState, row: Row, offer: Offer): boolean {
    const over = runningTask(bot);
    const mode = bot.GetActiveMode();
    const from = HDebug.ModeName(mode);
    const v = accept(bot, offer, mode);
    if (v.no !== undefined) {
        refuse(bot, s, { row: row.name, tgt: offer.tgt, why: v.no, mode: from });
        return false;
    }
    s.refLines = undefined;
    const [ok, res] = pcall(() => Tasks.Begin(row.name, () => row.begin(bot)));
    // Taken after the begin, so a task the begin replaced has released its own (its end runs inside the start); only while the
    // row's task runs, so a task that ended inside its begin leaves none behind. A begin that threw after its task started still
    // holds the claim, as when the row took it itself; the error is raised again after.
    if ((!ok || res === true) && offer.tgt !== undefined && runningTask(bot) === row.name) {
        const c = offer.claim;
        Claims.Take(offer.tgt, { pid: bot.GetPlayerID(), rank: c?.rank, k: c?.k, due: c?.due, phase: c?.phase });
        s.claimRow = row.name;
    }
    if (!ok) error(res, 0);
    if (res !== true) return false;
    s.refused[row.name] = undefined;
    // Asked for begun offers only (the shadow sets the parts against what happened after a start); a fault never blocks the begin.
    let d: Danger.Parts | undefined;
    let dfail: boolean | undefined;
    if (offer.at !== undefined && Telemetry.IsEnabled()) {
        const at = offer.at;
        const [dok, dres] = pcall(() => Danger.At(bot, at, offer.secs));
        if (dok) d = dres;
        else dfail = true;
    }
    s.begun = { row, offer, over, from, v, d, dfail };
    return true;
}

/** Tasks' end hook for a row's task: the claim that row's begin took is released (after the row's own end, which may read it). */
function rowEnded(bot: Unit, name: string): void {
    const s = heroes[bot.GetPlayerID()];
    if (s === undefined || s.claimRow !== name) return;
    s.claimRow = undefined;
    Claims.Release(bot.GetPlayerID());
}
Tasks.OnRowEnd(rowEnded);

/** Keeps a refusal for the row and writes its line once per row and target while it repeats. */
function refuse(bot: Unit, s: HeroState, r: Refused): void {
    s.refused[r.row] = r;
    const key = `${r.row}|${r.tgt ?? ""}`;
    const seen = (s.refLines ??= {});
    if (seen[key] === true) return;
    seen[key] = true;
    if (!Telemetry.IsEnabled()) return;
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "decider"],
        ["ref", r.row],
        ["btgt", r.tgt],
        ["bfrom", r.mode],
        ["why", r.why],
    ]);
}

/**
 * Why the decider last refused to begin `row` for this hero, once (it is forgotten on reading): `fight` (the hero was in attack,
 * roam or team roam, Ours.FightFirst). A row reads it after a begin it asked for did not happen. Undefined when none is kept.
 */
export function Refusal(bot: Unit, row: string): string | undefined {
    const s = heroes[bot.GetPlayerID()];
    const r = s?.refused[row];
    if (r === undefined) return undefined;
    s.refused[row] = undefined;
    return r.why;
}

/** One row's turn: its offer, and its begin when its task does not run. Undefined when it does not want the hero or the begin was refused. */
function turn(bot: Unit, s: HeroState, row: Row): Offer | undefined {
    const offer = row.wants(bot, READS);
    if (offer === undefined) return undefined;
    if (runningTask(bot) === row.name || begin(bot, s, row, offer)) return offer;
    return undefined;
}

/** A refused begin passes the turn to the next row. */
function pick(bot: Unit, s: HeroState): Row | undefined {
    for (const row of ROWS) if (turn(bot, s, row) !== undefined) return row;
    return undefined;
}

/**
 * Chooser.Gate, for every gated mode file: the desire `mode`'s file returned to Valve. A value that is not a number (Valve's
 * own desire falls through) is not known, so it is forgotten.
 */
export function NoteDesire(bot: Unit, mode: string, v: any): void {
    const seen = stateOf(bot).seen;
    if (type(v) !== "number") {
        seen[mode] = undefined as any;
        return;
    }
    const n = seen[mode];
    if (n === undefined) seen[mode] = { v: v as number, t: DotaTime() };
    else {
        n.v = v as number;
        n.t = DotaTime();
    }
}

/**
 * Plan s3, user 23/11/2026: stock would retreat when the retreat file's desire leads every other mode the hold outbids. Each
 * value is the file's latest within FRESH, as Valve's order of calls gives it, so the read can lag the retreat call by a
 * round. Valve-only modes (attack for most heroes, item, evasive) have no file and are not seen. Every error of this read
 * should only yield to stock, so a tie with a rival lets go (Valve's tie-break is not known); a retreat at 0 never leads.
 * Returns the leading retreat value, else undefined.
 */
function retreatLeads(s: HeroState): number | undefined {
    const now = DotaTime();
    const r = s.seen["retreat"];
    if (r === undefined || r.v <= 0 || now - r.t > FRESH) return undefined;
    for (const [mode, n] of pairs(s.seen)) {
        if (mode === "retreat" || mode === HOST || now - n.t > FRESH) continue;
        if (n.v > r.v) return undefined;
    }
    return r.v;
}

/**
 * `win` is the mode Valve gave the hero from the last round's desires, read at this round's farm call: Valve asks every mode
 * once a round, so the hold or yield decided now shows up in the next line.
 */
function note(bot: Unit, s: HeroState, heldRow = s.held, softNow = s.soft): void {
    const b = s.begun;
    s.begun = undefined;
    if (!Telemetry.IsEnabled()) return;
    const held = heldRow?.name ?? "-";
    const win = HDebug.ModeName(bot.GetActiveMode());
    const let_ = s.letAt !== undefined;
    const soft = softNow === true;
    if (b === undefined && held === s.lineHeld && win === s.lineWin && let_ === s.lineLet && soft === s.lineSoft) return;
    s.lineHeld = held;
    s.lineWin = win;
    s.lineLet = let_;
    s.lineSoft = soft;
    const fields: Telemetry.Fields<"choice"> = [
        ["pid", bot.GetPlayerID()],
        ["kind", "decider"],
        ["held", held],
        ["win", win],
    ];
    if (heldRow !== undefined) fields.push(["hs", soft ? "soft" : "hard"]);
    if (s.letAt !== undefined) fields.push(["let", "retreat"], ["d_retreat", s.letAt]);
    if (b !== undefined) {
        fields.push(["beg", b.row.name], ["btgt", b.offer.tgt], ["bby", b.offer.by !== undefined ? math.floor(b.offer.by * 10 + 0.5) / 10 : undefined], ["over", b.over], ["bfrom", b.from], ["bway", b.offer.way], ["bacc", b.v.would], ["bcl", b.v.others > 0 ? b.v.others : undefined]);
        if (b.offer.at !== undefined) fields.push(["bpx", math.floor(b.offer.at.x)], ["bpy", math.floor(b.offer.at.y)]);
        if (b.d !== undefined) for (const f of Danger.Fields(b.d)) fields.push(f);
        if (b.dfail === true) fields.push(["dfail", 1]);
    }
    Telemetry.Event("choice", fields);
}

/** Wraps the host file's GetDesire: a held row's strength, else the inner desire unchanged. A row does not hold while stock would retreat. */
export function Host(bot: Unit, inner: () => any): () => any {
    return () => {
        const s = stateOf(bot);
        if (FIGHT[bot.GetActiveMode()] !== true) s.refLines = undefined;
        const row = pick(bot, s);
        s.letAt = row !== undefined ? retreatLeads(s) : undefined;
        s.held = s.letAt === undefined ? row : undefined;
        s.soft = s.held !== undefined && isSoft(s.held, bot);
        pcall(() => note(bot, s));
        if (s.held === undefined) return inner();
        if (!s.soft) return HARD;
        // Farm active (the hold's own, or farm's for any reason in a soft row's first round): Valve adds its bonus to the
        // active mode, so the hold asks for less to stay worth SOFT. Where the
        // bonus is missing it is worth SOFT / BONUS (0.45): still over every capped Lua mode, and it yields to Valve's more.
        return bot.GetActiveMode() === BotMode.Farm ? SOFT / BONUS : SOFT;
    };
}

/**
 * Chooser.Gate, for every gated mode file, after NoteDesire saw the value as returned: while a soft row holds, an OHA Lua
 * mode's desire above CAP is returned as CAP, so only the Valve-only modes, retreat and attack's file outbid the hold. The
 * hold is the one decided at the last farm call, so files Valve asks before farm lag by one round: uncapped in the round a
 * soft hold starts, still capped in the round it lets go or stops wanting the hero. The cap follows `held`, so the lag cannot
 * flicker on its own. Anything else, and any value that is not a number, passes unchanged.
 *
 * Known effect, not stock's: retreat is uncapped, so a retreat value between the hold's worth (about SOFT; SOFT / BONUS in a
 * round Valve gives the active farm no bonus) and the highest raw Lua mode wins the hero
 * from the hold although the retreat read (raw values) keeps holding; stock would have run that Lua mode. Plan s3 accepts
 * it ("retreat excepted"); the first soft row's smoke counts it.
 */
export function Cap(bot: Unit, mode: string, v: any): any {
    const s = heroes[bot.GetPlayerID()];
    if (s === undefined || s.held === undefined || s.soft !== true || UNCAPPED[mode] === true || type(v) !== "number") return v;
    return (v as number) > CAP ? CAP : v;
}

/** Wraps the host file's Think: a held row's verb, not stepped while the bot cannot act (as Chooser.HostThink), else the inner Think. */
export function HostThink(bot: Unit, inner: () => any, cannotAct: (this: void, bot: Unit) => boolean): () => any {
    return () => {
        const row = stateOf(bot).held;
        if (row === undefined) return inner();
        if (cannotAct(bot)) return undefined;
        if (row.step(bot)) stateOf(bot).held = undefined;
        return undefined;
    };
}

/**
 * A row that decides at a read of its own (the creep row, at the creep offer read) asks to be begun now, so its start keeps the
 * read's moment. Begun when no row above it holds the hero (its task runs). The rows above are not asked `wants` here: theirs
 * takes the lane read and writes its decision lines at the moment it is first asked, so a second ask between rounds would move
 * them. Their last round's answer adds nothing: a row picked then has its task running now, unless that task has ended, and
 * then the row no longer wants the hero. A row above that comes to want the hero takes it at the next round (`over`). The row's
 * own `wants` is asked for the offer. True when the row was begun; a row not in ROWS is never begun.
 */
export function Offer(bot: Unit, row: Row): boolean {
    const at = ROWS.indexOf(row);
    if (at < 0) return false;
    const s = stateOf(bot);
    const cur = runningTask(bot);
    for (let i = 0; i < at; i++) if (cur === ROWS[i].name) return false;
    const offer = row.wants(bot, READS);
    if (offer === undefined || cur === row.name || !begin(bot, s, row, offer)) return false;
    pcall(() => note(bot, s, row, isSoft(row, bot)));
    return true;
}

/**
 * Whether `task` is the task of a row below `row` in doctrine order: a begin of `row` may take the hero from it (`over`), as `Host`
 * does at a round. False for any other task (a row above, a job no row started) and for a row not in ROWS.
 */
export function Below(row: Row, task: string | undefined): boolean {
    const at = ROWS.indexOf(row);
    if (at < 0 || task === undefined) return false;
    for (let i = at + 1; i < ROWS.length; i++) if (ROWS[i].name === task) return true;
    return false;
}

/** One row's turn as `Host` takes it, for that row alone (tests): true when it holds the hero, begun now or running. */
export function Ask(bot: Unit, row: Row): boolean {
    const s = stateOf(bot);
    const held = turn(bot, s, row) !== undefined;
    s.begun = undefined;
    return held;
}

/** The decider is yielding this hero to stock's retreat although a row wanted it (a cut row names it as its end's reason). */
export function LetGo(bot: Unit): boolean {
    return stateOf(bot).letAt !== undefined;
}

/** Whether the held row's hold was soft at this hero's last farm desire round (the overlay; the answer `Host` got, so a function-valued `Row.soft` counts). */
export function Soft(bot: Unit): boolean {
    return heroes[bot.GetPlayerID()]?.soft === true;
}

/** The row that held this hero at its last farm desire round, if any (the overlay). */
export function Held(bot: Unit): Row | undefined {
    return heroes[bot.GetPlayerID()]?.held;
}

/** Tests: forget every hero. */
export function Reset(): void {
    for (const [k] of pairs(heroes)) heroes[k] = undefined as any;
    Claims.ResetCache();
}
