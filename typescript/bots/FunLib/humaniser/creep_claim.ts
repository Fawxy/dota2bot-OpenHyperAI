import type * as Lib from "bots/FunLib/engine/tasks";
import type { Unit } from "bots/ts_libs/dota";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as TripTable from "bots/FunLib/humaniser/states/trip_table";

/**
 * The creep claim, a read (`Reads.creep`, hum/reads.ts; ARCHITECTURE rule 3), keyed by the creep's id (`Telemetry.CreepId`; the five
 * teammates share one Lua state). Per creep it holds the claim, which hero is going for it (its rank in the trip table, the game time
 * its swing is due to be ordered and the verb's phase), and each hero's latest answer on it, go or refusal with the reason, which the creep row writes
 * as the offer reads. Stored knowledge, like the camp's record: it lasts across frames and carries its writers (`Take`, `Release`,
 * `Phase`, `Touch`). It decides nothing; `FreeFor` is a pure reader of it, asked by the creep row for a hero whose `creep` cell is above
 * the lowest (slice oha-support-creeps, proposal no-creep-unpaid s6a), and the row's yield reads `ClaimsOn`.
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
    /** The trip table's cell for the hero's position and the attempt's kind. Comparing it between heroes is for the behaviour merge to define. */
    rank: number;
    /** `lh` a last hit, `dn` a deny. */
    k: "lh" | "dn";
    /** The game time the swing is due to be ordered (the hit lands one own hit time later, later still if the walk is longer). */
    due: number;
    /** The verb's phase; undefined before it reports one. */
    phase?: Lib.Verbs.LastHitPhase;
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
        if (next(m)[0] === undefined) claims[cid] = undefined;
    }
    return true;
}

export function Phase(this: void, pid: number, p: Lib.Verbs.LastHitPhase): void {
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

/** An answer older than this (s) is not a read of the hero's now: a dead hero's or a hero whose row is off stops touching its answers. */
export const ANSWER_FRESH = 1;

export type Free = "claimed" | "wait" | "human";

/**
 * Whether the creep is free for this hero, as far as the heroes with a lower `creep` cell go; undefined when it is, else why not. A hero
 * with the lowest cell is always free, with no scan. In order: `claimed` (a lower-cell hero holds a claim on it), then over the teammates
 * with a lower cell: `human` (not a bot, in this hero's assigned lane: a human publishes no answers, so its creep is never free) and
 * `wait` (it has the creep on offer and has not refused it yet: its answer has no `why`). A fresh answer with a `why` is a refusal
 * (`Consider` sets `why` on every refusal, and the next read after an attempt's end gives `tried`, so a stale `why` from before a go is
 * overtaken by the claim, then by `tried`); no answer, or a stale one, is not on offer.
 */
export function FreeFor(this: void, bot: Unit, cid: number, now: number): Free | undefined {
    const pid = bot.GetPlayerID();
    const pos = LaneConfig.PositionOf(bot);
    const mine = TripTable.RankOf("creep", pos);
    if (mine === undefined || !TripTable.Outranked("creep", pos)) return undefined;
    for (const c of ClaimsOn(cid)) if (c.pid !== pid && c.k === "lh" && c.rank < mine) return "claimed";
    const lane = bot.GetAssignedLane();
    let wait = false;
    for (let i = 1; i <= 5; i++) {
        const m = GetTeamMember(i);
        if (m === null || m === undefined || m.GetPlayerID() === pid) continue;
        const cell = TripTable.RankOf("creep", LaneConfig.PositionOf(m));
        if (cell === undefined || cell >= mine) continue;
        if (!m.IsBot()) {
            if (m.GetAssignedLane() === lane) return "human";
            continue;
        }
        const a = AnswerOf(m.GetPlayerID(), cid);
        if (a !== undefined && a.why === undefined && now - a.at <= ANSWER_FRESH) wait = true;
    }
    return wait ? "wait" : undefined;
}
