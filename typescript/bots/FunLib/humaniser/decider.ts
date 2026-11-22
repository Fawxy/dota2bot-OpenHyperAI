/**
 * The decider (plan s3, docs/proposals/2026-11-23-laning-plan-after-the-bisect.md): one per hero of ours, hosted in farm's mode
 * file. Rows are behaviours in doctrine order; the first that applies holds the hero, else the decider yields and farm's own
 * desire and Think run untouched (stock's, or today's per-mode code while it lasts). Desire exists here only as the wire to
 * the engine: a row names no number.
 *
 * Built so far: the yield and the hard hold. The soft hold, worth with an incumbent margin and the label hook arrive with the
 * first row that needs each (plan s3).
 */
import { Unit } from "bots/ts_libs/dota";
import * as HDebug from "bots/FunLib/humaniser/debug";
import * as Ours from "bots/FunLib/humaniser/ours";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export interface Row {
    /** Logged as `held`. */
    name: string;
    /** Cheap; asked every scoring round. The row holds while it is true. */
    applies(this: void, bot: Unit): boolean;
    /** One frame of the row's verb, from farm's Think while the row holds; true when the row is finished. */
    step(this: void, bot: Unit): boolean;
}

/**
 * Plan s3: above 0.95, the most Valve's attack showed, and at most 1.0, since above it J.IsRetreating reads a farm-mode
 * hero as retreating; under OHA's retreat latch (1.1). The value inside that band is judgement.
 */
export const HARD = 0.98;

/** Doctrine order: the first row that applies holds. Empty: the pass-through. */
export const ROWS: Row[] = [];

interface HeroState {
    held?: Row;
    /** What the last line said, so a line goes out only on a change. */
    lineHeld?: string;
    lineWin?: string;
}

const heroes: Record<number, HeroState> = {};

function stateOf(bot: Unit): HeroState {
    const pid = bot.GetPlayerID();
    let s = heroes[pid];
    if (s === undefined) {
        s = {};
        heroes[pid] = s;
    }
    return s;
}

function pick(bot: Unit): Row | undefined {
    for (const row of ROWS) if (row.applies(bot)) return row;
    return undefined;
}

/**
 * `win` is the mode Valve gave the hero from the last round's desires, read at this round's farm call: Valve asks every mode
 * once a round, so the hold or yield decided now shows up in the next line.
 */
function note(bot: Unit, s: HeroState): void {
    if (!Telemetry.IsEnabled()) return;
    const held = s.held?.name ?? "-";
    const win = HDebug.ModeName(bot.GetActiveMode());
    if (held === s.lineHeld && win === s.lineWin) return;
    s.lineHeld = held;
    s.lineWin = win;
    Telemetry.Event("choice", [
        ["pid", bot.GetPlayerID()],
        ["kind", "decider"],
        ["held", held],
        ["win", win],
    ]);
}

/** Wraps the host file's GetDesire: a held row's strength, else the inner desire unchanged. */
export function Host(bot: Unit, inner: () => any): () => any {
    return () => {
        if (!Ours.On("Decider")) return inner();
        const s = stateOf(bot);
        s.held = pick(bot);
        note(bot, s);
        return s.held !== undefined ? HARD : inner();
    };
}

/** Wraps the host file's Think: a held row's verb, else the inner Think. */
export function HostThink(bot: Unit, inner: () => any): () => any {
    return () => {
        if (!Ours.On("Decider")) return inner();
        const row = stateOf(bot).held;
        if (row === undefined) return inner();
        if (row.step(bot)) stateOf(bot).held = undefined;
        return undefined;
    };
}

/** Tests: forget every hero. */
export function Reset(): void {
    for (const [k] of pairs(heroes)) heroes[k] = undefined as any;
}
