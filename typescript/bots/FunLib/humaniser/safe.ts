/**
 * Safe here: one read for "can I be killed at this place" (design docs/proposals/2026-11-19-safe-here-design.md in the
 * master repo, sections 2 and 6.1). `Decide` is pure over `Inputs`: no unit handles, no game calls, so a logged cut replays
 * offline. One function for every position and every consumer; `Gather` and the callers come in later steps.
 *
 * Rules, first match: 1 tower, 2 kill, 3 unknown, 4 price, 5 safe.
 */
import { SETTINGS as ThreatSettings } from "bots/FunLib/humaniser/threat";

/** Every number the decision owns, with its source. The unseen bar is `Threat.SETTINGS.MissingRefuse`, read at call time, not copied. */
export const BARS = {
    /** ESTIMATE: under this HP / kill ratio a place is deadly. From the shadow batch safeshadow1 (6 games, 13 deaths): retreating between 1.0 and 1.25 of the kill line died about 18%, staying between 1.25 and 1.5 under 1% (user 19/11/2026). The overnight 7.42 batch picks. */
    stay: 1.25,
    /** A caller with a hold (a hit back, a join, a committed job) may stay down to this ratio: their damage is our HP. Replaces `lethal`. */
    hold: 1.0,
    /** A fresh place (a lane spot candidate, a creep's hit place, where a retreat may stop) needs this share more than `stay`; a place the caller already holds (`held`) and a hold are judged at their bar alone, so a hero is not sent where it would leave the next frame. */
    slack: 0.15,
};

/** One enemy hero that can be in attack range of the walk within the horizon. */
export interface Reacher {
    pid: number;
    /** Damaged us in the last 1 s. */
    hitting: boolean;
    /** What it can deal to us: over 2 s, or over 6 s if `hitting`. */
    dmg: number;
    /** A lane opponent seen in the last 10 s and not visible now; counts like any other row. */
    unseen?: boolean;
}

export interface Inputs {
    /** Absolute. */
    hp: number;
    hpMax: number;
    reach: Reacher[];
    /** The belief's weight sum for other unseen heroes. */
    missing: number;
    /** The place is in a live enemy tower's reach. */
    tower: boolean;
    towerOnMe: boolean;
    /** HP per second lost to each source over the last 2 s. */
    landing: { hero: number; creeps: number; tower: number };
    /** Seconds to walk out of every reacher's range. Logged only: it never changes the answer. */
    exit?: number;
    /** The walk leaves our creeps and tower. */
    away: boolean;
    /** The caller already holds a standing answer at this place. */
    held: boolean;
    /** The caller has a hold and may stay down to `BARS.hold`. */
    hold: boolean;
}

export type Level = "safe" | "costly" | "deadly";

export interface Answer {
    level: Level;
    /** Absolute damage the reachers can deal. */
    kill: number;
    /** hp / kill; `math.huge` when nothing can reach. */
    ratio: number;
    /** HP per second lost over the last 2 s, always reported. */
    price: number;
    reason: string;
}

export function Decide(i: Inputs, stay: number = BARS.stay): Answer {
    let kill = 0;
    for (const r of i.reach) kill += r.dmg;
    const ratio = kill > 0 ? i.hp / kill : math.huge;
    const { hero, creeps, tower } = i.landing;
    const price = hero + creeps + tower;
    const answer = (level: Level, reason: string): Answer => ({ level, kill, ratio, price, reason });

    if (i.tower || i.towerOnMe) return answer("deadly", "tower");

    const bar = i.hold ? math.min(stay, BARS.hold) : i.held ? stay : stay * (1 + BARS.slack);
    if (ratio < bar) return answer("deadly", "kill");

    if (i.away && i.missing >= ThreatSettings.MissingRefuse) return answer("deadly", "unknown");

    if (price > 0) return answer("costly", hero >= creeps && hero >= tower ? "hero" : creeps >= tower ? "creeps" : "tower");

    return answer("safe", "safe");
}
