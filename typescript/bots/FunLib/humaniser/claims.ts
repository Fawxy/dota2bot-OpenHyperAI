import type * as Lib from "bots/FunLib/engine/tasks";

/**
 * Claims by target, a read (`Reads.claims`, hum/reads.ts): which heroes of ours hold an attempt on a target, keyed by the offer's
 * target (`creep:<cid>`, `camp:<idx>`, `rune:<rune>`, `draw:<cid>`; the five teammates share one Lua state). Taken by the decider when it begins a
 * row whose offer names a target and released when that row's task ends (offers-and-the-decider s6, "claims by target"); a hero
 * holds one claim. Stored knowledge that lasts across frames and carries its writers (`Take`, `Release`, `Phase`). It decides
 * nothing and reads no position (ARCHITECTURE rule 18): the decider's acceptance and the creep row's `FreeFor` and yield read it.
 */

export interface Claim {
    pid: number;
    /** The trip table's cell for the hero's position and the attempt's kind, where the row gives one (the creep row). Lower goes first. */
    rank?: number;
    /** The creep row's kind: `lh` a last hit, `dn` a deny. */
    k?: "lh" | "dn";
    /** The creep row: the game time the swing is due to be ordered. */
    due?: number;
    /** The creep row's verb phase; undefined before it reports one. */
    phase?: Lib.Verbs.LastHitPhase;
}

/** target -> pid -> the claim; and pid -> the target it holds. */
const claims: Record<string, Record<number, Claim> | undefined> = {};
const held: Record<number, string | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(claims)) claims[k as string] = undefined;
    for (const [k] of pairs(held)) held[k as number] = undefined;
}

/** The hero takes the target (an earlier claim of its own is released first). Returns the other heroes already holding it. */
export function Take(this: void, tgt: string, c: Claim): number[] {
    Release(c.pid);
    let m = claims[tgt];
    const others: number[] = [];
    if (m === undefined) {
        m = {};
        claims[tgt] = m;
    }
    for (const [pid] of pairs(m)) others.push(pid as number);
    m[c.pid] = c;
    held[c.pid] = tgt;
    return others;
}

/** The hero lets go of whatever it holds; true when it held a claim. */
export function Release(this: void, pid: number): boolean {
    const tgt = held[pid];
    if (tgt === undefined) return false;
    held[pid] = undefined;
    const m = claims[tgt];
    if (m !== undefined) {
        delete m[pid];
        if (next(m)[0] === undefined) claims[tgt] = undefined;
    }
    return true;
}

/** The verb's phase on the claim the hero holds. */
export function Phase(this: void, pid: number, p: Lib.Verbs.LastHitPhase): void {
    const tgt = held[pid];
    const c = tgt === undefined ? undefined : claims[tgt]?.[pid];
    if (c !== undefined) c.phase = p;
}

/** The heroes holding a claim on the target, none when it is free. */
export function ClaimsOn(this: void, tgt: string): Claim[] {
    const out: Claim[] = [];
    const m = claims[tgt];
    if (m !== undefined) for (const [, c] of pairs(m)) out.push(c);
    return out;
}

/** The target the hero holds, if any. */
export function HeldBy(this: void, pid: number): string | undefined {
    return held[pid];
}

/** The target key of a creep, as the creep row's offer names it. */
export function CreepTarget(this: void, cid: number): string {
    return `creep:${cid}`;
}
