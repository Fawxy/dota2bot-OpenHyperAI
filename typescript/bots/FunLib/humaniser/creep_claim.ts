/**
 * The creep answers, a read (`Reads.creep`, hum/reads.ts; ARCHITECTURE rule 3), keyed by the creep's id (`Telemetry.CreepId`; the five
 * teammates share one Lua state): each hero's latest answer on each creep it has on offer, go or refusal with the reason, which the
 * creep row writes as the offer reads. Stored knowledge, like the camp's record: it lasts across frames and carries its writer
 * (`Touch`). It decides nothing and reads no position (ARCHITECTURE rule 18): the creep row's `FreeFor` reads `AnswerOf` (slice
 * oha-support-creeps, proposal no-creep-unpaid s6a). Who holds a creep is the target claim (`claims.ts`), which the decider takes.
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

/** pid -> creep id -> the hero's answer. */
const answers: Record<number, Record<number, Answer> | undefined> = {};

export function ResetCache(): void {
    for (const [k] of pairs(answers)) answers[k as number] = undefined;
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

/** An answer older than this (s) is not a read of the hero's now: a dead hero's or a hero whose row is off stops touching its answers. */
export const ANSWER_FRESH = 1;
