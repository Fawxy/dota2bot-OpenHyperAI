/**
 * The creep claim, a read (`Reads.creep`, hum/reads.ts; ARCHITECTURE rule 3), keyed by the creep's id (`Telemetry.CreepId`; the five
 * teammates share one Lua state). Per creep it holds the claim, which hero is going for it (its rank in the trip table, the game time
 * its hit is due and the verb's phase), and each hero's latest answer on it, go or refusal with the reason, which the creep row writes
 * as the offer reads. Stored knowledge, like the camp's record: it lasts across frames and carries its writers (`Take`, `Release`,
 * `Phase`, `Touch`). It decides nothing. CANDIDATE(creep-claim): nothing reads it to decide yet (slice oha-creep-claim, proposal
 * no-creep-unpaid s6a); a second reader makes it a shared abstraction.
 */

/** What the reads saw of one creep for one hero; dropped once a read no longer lists the creep. */
export interface Answer {
    /** The read's time when it was last listed (the prune's mark). */
    at: number;
    first: number;
    /** The first read where the creep was about to come due. */
    due0?: number;
    /** The last reason the row refused it at a read where it was about to come due, and the hero's mode name then when that was `held`. */
    why?: string;
    mode?: string;
    /** The last reason it refused the creep at a read where it was about to come due and on time (names a `notime_*` refusal). */
    ok?: string;
}

export interface Claim {
    pid: number;
    /** The rank of the hero's position in the trip table's line for the attempt's kind (lower wins). */
    rank: number;
    /** `lh` a last hit, `dn` a deny. */
    k: "lh" | "dn";
    /** The game time the hit is due to land. */
    due: number;
    /** The verb's phase; undefined before it reports one. */
    phase?: "walk" | "wait" | "swing";
}

/** pid -> creep id -> the hero's answer. */
const answers: Record<number, Record<number, Answer> | undefined> = {};

/** creep id -> pid -> the claim; and pid -> the creep it holds (a hero attempts one creep at a time). */
const claims: Record<number, Record<number, Claim> | undefined> = {};
const held: Record<number, number | undefined> = {};

export function ResetCache(): void {
    for (const t of [answers, claims, held] as Record<number, unknown>[]) for (const [k] of pairs(t)) t[k as number] = undefined;
}

/** The hero's answers on each listed creep, new ones made now; answers on creeps this read does not list are dropped. */
export function Touch(this: void, pid: number, cids: number[], now: number): Record<number, Answer> {
    let m = answers[pid];
    if (m === undefined) {
        m = {};
        answers[pid] = m;
    }
    for (const cid of cids) {
        const r = m[cid];
        if (r === undefined) m[cid] = { at: now, first: now };
        else r.at = now;
    }
    for (const [cid, r] of pairs(m)) if (r.at !== now) delete m[cid as number];
    return m;
}

/** The hero's latest answer on the creep, if the read still lists it. */
export function AnswerOf(this: void, pid: number, cid: number): Answer | undefined {
    return answers[pid]?.[cid];
}

/**
 * The hero takes the creep (a hero holds one claim: an earlier one is released first). Returns the heroes already holding a claim on the
 * same creep, which the caller logs; the claim is taken either way.
 */
export function Take(this: void, cid: number, c: Claim): number[] {
    Release(c.pid);
    let m = claims[cid];
    const others: number[] = [];
    if (m === undefined) {
        m = {};
        claims[cid] = m;
    }
    for (const [pid] of pairs(m)) others.push(pid as number);
    m[c.pid] = c;
    held[c.pid] = cid;
    return others;
}

/** The hero lets go of whatever it holds; true when it held a claim. */
export function Release(this: void, pid: number): boolean {
    const cid = held[pid];
    if (cid === undefined) return false;
    held[pid] = undefined;
    const m = claims[cid];
    if (m !== undefined) {
        delete m[pid];
        let any = false;
        for (const [k] of pairs(m)) {
            k;
            any = true;
            break;
        }
        if (!any) claims[cid] = undefined;
    }
    return true;
}

export function Phase(this: void, pid: number, p: "walk" | "wait" | "swing"): void {
    const cid = held[pid];
    const c = cid === undefined ? undefined : claims[cid]?.[pid];
    if (c !== undefined) c.phase = p;
}

/** The heroes holding a claim on the creep, none when it is free. */
export function ClaimsOn(this: void, cid: number): Claim[] {
    const out: Claim[] = [];
    const m = claims[cid];
    if (m !== undefined) for (const [, c] of pairs(m)) out.push(c);
    return out;
}

/** The creep the hero holds, if any. */
export function HeldBy(this: void, pid: number): number | undefined {
    return held[pid];
}
