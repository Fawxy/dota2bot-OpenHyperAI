/**
 * Danger at a place (offers-and-the-decider s5): for a walk from where the hero is to the place an offer names, over the offer's
 * seconds, the parts and no verdict. The decider asks it once for every offer it begins and logs the parts beside the begin, so
 * hlog can set them against what happened (`q @offer_danger`); it refuses nothing until the shadow is graded (route step 8).
 *
 * One home: the heroes, allies, tower cover and sightings are `Threat.Reader`'s per-team frame; each reacher's seconds of the walk
 * inside its range are `Offer.PathCost`'s (creep proposal s4a). Nothing here reads the game that those two do not.
 * CANDIDATE(danger): one consumer (the decider) until the danger re-ask while a row holds (s5) or the first refusal rule.
 */
import { Unit, Vector } from "bots/ts_libs/dota";
import * as Offer from "bots/FunLib/humaniser/offer";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";
import * as Threat from "bots/FunLib/humaniser/threat";

/** One visible enemy hero that can reach the walk within the window. */
export interface Reacher {
    pid: number;
    /** Centre to centre, from it to the place. */
    dist: number;
    /** Seconds of the straight walk inside its attack range and both hulls, it standing still (`Offer.PathCost`). */
    exp: number;
    /** Its damage on the hero over the threat read's burst window (`Threat.Read` rows). */
    dmg: number;
}

/** An enemy hero out of sight, as the place sees it. */
export interface Away {
    pid: number;
    /** Seconds since it was seen. */
    tss: number;
    /** From its last place to the offer's place. */
    dist: number;
}

export interface Parts {
    /** The window asked (the offer's seconds, else `Threat.SETTINGS.GateHorizon`). */
    secs: number;
    reach: Reacher[];
    /** Their summed damage as a share of the hero's HP (`Threat.Read.burst`). */
    burst: number;
    /** Our other heroes who can reach the place within the window (one in our retreat counts none). */
    allies: number;
    /** The place is inside a live enemy tower's reach. */
    tower: boolean;
    /** Every enemy hero out of sight with a sighting, nearest first, and those never sighted. */
    away: Away[];
    nos: number;
}

function dist(a: { x: number; y: number }, b: { x: number; y: number }): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

/** The parts for `bot` walking from where it stands to `place`, held `secs` seconds. Facts only. */
export function At(bot: Unit, place: Vector, secs?: number): Parts {
    const window = secs !== undefined && secs > 0 ? secs : Threat.SETTINGS.GateHorizon;
    const from = bot.GetLocation();
    const r = Threat.Read(bot, from, place, window, { passive: true });
    const enemies: Offer.PathEnemy[] = [];
    const dmgOf: Record<number, number> = {};
    for (const row of r.rows) {
        const u = row.u;
        if (u === undefined) continue;
        dmgOf[row.pid] = row.dmg;
        // PathCost's dmg and spa price a hit per second of exposure; only its exposure seconds are read here.
        enemies.push({ x: row.at.x, y: row.at.y, pid: row.pid, range: u.GetAttackRange(), hull: u.GetBoundingRadius(), dmg: 0, spa: 1 });
    }
    const path = Offer.PathCost({ from, spot: place, speed: math.max(1, bot.GetCurrentMovementSpeed()), hull: bot.GetBoundingRadius(), creeps: [], towers: [], enemies });
    const reach: Reacher[] = [];
    for (const e of path.enemies) reach.push({ pid: e.pid, dist: e.dist, exp: e.exp, dmg: dmgOf[e.pid] ?? 0 });
    const away: Away[] = [];
    for (const m of r.uns) away.push({ pid: m.pid, tss: m.tss, dist: dist(m.at, place) });
    away.sort((a, b) => a.dist - b.dist);
    return { secs: window, reach, burst: r.burst, allies: r.allies, tower: r.tower, away, nos: r.nos };
}

const r0 = (x: number): number => math.floor(x + 0.5);
const r1 = (x: number): number => math.floor(x * 10 + 0.5) / 10;
const r2 = (x: number): number => math.floor(x * 100 + 0.5) / 100;

/** The begin line's fields (`ev=choice kind=decider`, events.ts): `dre` reachers `pid:dist:exp:dmg`, `dun` the unseen `pid:tss:dist`. */
export function Fields(p: Parts): Telemetry.Fields<"choice"> {
    const dr = p.reach.map((e) => `${e.pid}:${r0(e.dist)}:${r1(e.exp)}:${r0(e.dmg)}`).join(",");
    const dun = p.away.map((m) => `${m.pid}:${r0(m.tss)}:${r0(m.dist)}`).join(",");
    return [
        ["bsec", r1(p.secs)],
        ["dn", p.reach.length],
        ["dre", dr !== "" ? dr : undefined],
        ["dbu", r2(p.burst)],
        ["dal", p.allies],
        ["dtw", p.tower ? 1 : 0],
        ["dun", dun !== "" ? dun : undefined],
        ["dnos", p.nos > 0 ? p.nos : undefined],
    ];
}
