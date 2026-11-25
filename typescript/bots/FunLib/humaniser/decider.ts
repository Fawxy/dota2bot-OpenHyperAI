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
import { BotMode, Unit } from "bots/ts_libs/dota";
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

/** Doctrine order: the first row that applies holds. index.ts fills it with the pull, stack and rune detour rows (in that order), so no row is imported here; with none registered the decider is a pass-through. */
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
        if (s.held.soft !== true) return HARD;
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
 * soft hold starts, still capped in the round it lets go or stops applying. The cap follows `held`, so the lag cannot
 * flicker on its own. Anything else, and any value that is not a number, passes unchanged.
 *
 * Known effect, not stock's: retreat is uncapped, so a retreat value between the hold's worth (about SOFT; SOFT / BONUS in a
 * round Valve gives the active farm no bonus) and the highest raw Lua mode wins the hero
 * from the hold although the retreat read (raw values) keeps holding; stock would have run that Lua mode. Plan s3 accepts
 * it ("retreat excepted"); the first soft row's smoke counts it.
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

/** The decider is yielding this hero to stock's retreat although a row applied (a cut row names it as its end's reason). */
export function LetGo(bot: Unit): boolean {
    return stateOf(bot).letAt !== undefined;
}

/** The row that held this hero at its last farm desire round, if any (the overlay). */
export function Held(bot: Unit): Row | undefined {
    return heroes[bot.GetPlayerID()]?.held;
}

/** Tests: forget every hero. */
export function Reset(): void {
    for (const [k] of pairs(heroes)) heroes[k] = undefined as any;
}
