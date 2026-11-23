/**
 * The decider (plan s3, docs/proposals/2026-11-23-laning-plan-after-the-bisect.md): one per hero of ours, hosted in farm's mode
 * file, on both teams. Rows are behaviours in doctrine order, each behind its own Ours switch (so Ours.Team scopes it); the
 * first that applies holds the hero, else the decider yields and farm's own desire and Think run untouched (stock's, or
 * today's per-mode code while it lasts). Desire exists here only as the wire to the engine: a row names no number.
 *
 * Built so far: the yield, the hard and soft holds, and letting go when stock would retreat. Worth with an incumbent margin
 * and the label hook arrive with the first row that needs each (plan s3).
 *
 * The decider wraps outside Chooser's gate in farm's file: while a row holds, farm's gated code does not run, so the job
 * chooser and the shadow line say nothing for that time. A row is re-picked every round and is not told when another mode
 * takes the hero, so its verb must cope with being cut off between any two steps.
 */
import { Unit } from "bots/ts_libs/dota";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export interface Row {
    /** Logged as `held`. */
    name: string;
    /** Cheap; asked every scoring round. The row holds while it is true. */
    applies(this: void, bot: Unit): boolean;
    /** One frame of the row's verb, from farm's Think while the row holds; true when the row is finished. */
    step(this: void, bot: Unit): boolean;
    /** True: the row holds at SOFT, so the Valve-only modes take the hero when they want it (plan s3). Absent: HARD. */
    soft?: boolean;
}

/**
 * Plan s3: above 0.95, the most Valve's attack showed, and at most 1.0, since above it J.IsRetreating reads a farm-mode
 * hero as retreating; under OHA's retreat latch (1.1). The value inside that band is judgement.
 */
export const HARD = 0.98;

/**
 * Plan s3: above laning's desire (0.45) and under every entry of Valve's attack (none of 7,419 in h2hoha742 under 0.5), so
 * attack, item, evasive and defend-ally outbid a soft hold when they want the hero. The value inside that band is judgement.
 */
export const SOFT = 0.49;

/** judgement: the most an OHA Lua mode file may return while a soft row holds (plan s3: the gate caps them beneath it). */
export const CAP = 0.48;

/**
 * Not capped under a soft hold: retreat (stock's way out; when it leads, the retreat read lets go) and attack's own file
 * (OHA's override of Valve's attack for a few heroes: the mode a soft hold gives way to). The host's value is the decider's.
 */
const UNCAPPED: Record<string, boolean> = { retreat: true, attack: true, farm: true };

/** Doctrine order: the first row that applies holds. Empty: the pass-through. */
export const ROWS: Row[] = [];

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

interface HeroState {
    held?: Row;
    /** Set when a row applied but stock would retreat: the retreat file's value that led. */
    letAt?: number;
    /** Each gated mode file's last returned desire (NoteDesire). */
    seen: Record<string, Seen>;
    /** What the last line said, so a line goes out only on a change. */
    lineHeld?: string;
    lineWin?: string;
    lineLet?: boolean;
}

const heroes: Record<number, HeroState> = {};

function stateOf(bot: Unit): HeroState {
    const pid = bot.GetPlayerID();
    let s = heroes[pid];
    if (s === undefined) {
        s = { seen: {} };
        heroes[pid] = s;
    }
    return s;
}

function pick(bot: Unit): Row | undefined {
    for (const row of ROWS) if (row.applies(bot)) return row;
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
function note(bot: Unit, s: HeroState): void {
    if (!Telemetry.IsEnabled()) return;
    const held = s.held?.name ?? "-";
    const win = HDebug.ModeName(bot.GetActiveMode());
    const let_ = s.letAt !== undefined;
    if (held === s.lineHeld && win === s.lineWin && let_ === s.lineLet) return;
    s.lineHeld = held;
    s.lineWin = win;
    s.lineLet = let_;
    const fields: Telemetry.Fields<"choice"> = [
        ["pid", bot.GetPlayerID()],
        ["kind", "decider"],
        ["held", held],
        ["win", win],
    ];
    if (s.held !== undefined) fields.push(["hs", s.held.soft === true ? "soft" : "hard"]);
    if (s.letAt !== undefined) fields.push(["let", "retreat"], ["d_retreat", s.letAt]);
    Telemetry.Event("choice", fields);
}

/** Wraps the host file's GetDesire: a held row's strength, else the inner desire unchanged. A row does not hold while stock would retreat. */
export function Host(bot: Unit, inner: () => any): () => any {
    return () => {
        const s = stateOf(bot);
        const row = pick(bot);
        s.letAt = row !== undefined ? retreatLeads(s) : undefined;
        s.held = s.letAt === undefined ? row : undefined;
        pcall(() => note(bot, s));
        if (s.held === undefined) return inner();
        return s.held.soft === true ? SOFT : HARD;
    };
}

/**
 * Chooser.Gate, for every gated mode file, after NoteDesire saw the value as returned: while a soft row holds, an OHA Lua
 * mode's desire above CAP is returned as CAP, so only the Valve-only modes, retreat and attack's file outbid the hold. The
 * hold is the one decided at the last farm call, so a file Valve asks before farm in the round a soft hold starts is not
 * yet capped (one round). Anything else, and any value that is not a number, passes unchanged.
 */
export function Cap(bot: Unit, mode: string, v: any): any {
    const s = heroes[bot.GetPlayerID()];
    const held = s === undefined ? undefined : s.held;
    if (held === undefined || held.soft !== true || UNCAPPED[mode] === true || type(v) !== "number") return v;
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

/** Tests: forget every hero. */
export function Reset(): void {
    for (const [k] of pairs(heroes)) heroes[k] = undefined as any;
}
