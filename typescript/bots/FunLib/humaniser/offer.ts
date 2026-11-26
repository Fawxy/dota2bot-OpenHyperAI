/**
 * CANDIDATE(offer): the offer and its three shared questions (no-creep-unpaid proposal s4, s4a), until the pull is a second
 * consumer. Pure functions of plain numbers and records, so no Dota call is made here and a test needs no game. Facts only:
 * nothing here orders anything.
 *
 * 1. Arrive: can the hero be there before the deadline (`Arrive`).
 * 2. Given up: what else comes due where the hero stands before it is back (`GivenUp`).
 * 3. Path cost: what the walk to the stand spot meets (`PathCost`).
 */

export interface Vec {
    x: number;
    y: number;
}

/** Be at `at` within `deadline` seconds from now, for `gain`. */
export interface Offer {
    at: Vec;
    deadline: number;
    gain: number;
}

export interface Arrival {
    ok: boolean;
    /** Deadline less the walk and the act, in seconds (negative when late). */
    slack: number;
}

export function Arrive(this: void, walk: number, act: number, deadline: number): Arrival {
    const slack = deadline - (walk + act);
    return { ok: slack > 0, slack };
}

/** Another target on offer in the hero's reach now (walk 0). */
export interface Other {
    due: number;
    ranged: boolean;
}

export interface Given {
    /** Of the others, how many come due before the hero is back. */
    due: number;
    /** Of those, how many are ranged. */
    ranged: number;
    /** Who stays behind, against how many; comes with the pull. */
    partner?: { stays: number; against: number };
}

/** `away`: the seconds until the hero is back (twice the walk plus the act). */
export function GivenUp(this: void, others: Other[], away: number): Given {
    let due = 0;
    let ranged = 0;
    for (const o of others) {
        if (o.due >= away) continue;
        due++;
        if (o.ranged) ranged++;
    }
    return { due, ranged };
}

/** One of their lane creeps: `reach` its acquisition range plus both hulls; `dps` its damage a second. */
export interface PathCreep extends Vec {
    reach: number;
    dps: number;
}

/** An enemy tower: `reach` its attack range plus both hulls. */
export interface PathTower extends Vec {
    reach: number;
}

export interface PathEnemy extends Vec {
    pid: number;
    range: number;
    hull: number;
    /** One hit and the seconds an attack takes. */
    dmg: number;
    spa: number;
    /** Movement speed; read by the creep row's race, not by PathCost. */
    speed?: number;
}

export interface PathIn {
    from: Vec;
    spot: Vec;
    /** The hero's movement speed (positive) and hull radius. */
    speed: number;
    hull: number;
    creeps: PathCreep[];
    towers: PathTower[];
    enemies: PathEnemy[];
}

export interface EnemyCost {
    pid: number;
    /** Centre to centre, to the stand spot. */
    dist: number;
    range: number;
    dmg: number;
    spa: number;
    /** Seconds of the straight walk spent inside this enemy's range (attack range and both hulls), the enemy standing still. */
    exp: number;
}

export interface PathCostAnswer {
    creeps: number;
    /** Their summed damage a second. */
    cdps: number;
    /** The stand spot is inside an enemy tower's attack range. */
    tower: boolean;
    enemies: EnemyCost[];
    /** Enemy heroes whose range covers the stand spot. */
    covering: number;
    /** The longest exposure among them (seconds). */
    exposure: number;
}

function dist(a: Vec, b: Vec): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

/**
 * The point at `reach` from the creep on the line from the hero to it; the hero's own place when it is already within
 * `reach` (attack range plus both hulls).
 */
export function StandSpot(this: void, hero: Vec, creep: Vec, reach: number): Vec {
    const d = dist(hero, creep);
    if (d <= reach || d === 0) return { x: hero.x, y: hero.y };
    const k = reach / d;
    return { x: creep.x + (hero.x - creep.x) * k, y: creep.y + (hero.y - creep.y) * k };
}

/** The length of the segment `from` to `to` that lies inside the circle at `c` with radius `r`. */
export function InsideLength(this: void, from: Vec, to: Vec, c: Vec, r: number): number {
    const dx = to.x - from.x;
    const dy = to.y - from.y;
    const len = math.sqrt(dx * dx + dy * dy);
    if (len === 0) return 0;
    const fx = from.x - c.x;
    const fy = from.y - c.y;
    // Along the walk: where the centre's nearest point lies, and how far either side of it the circle reaches.
    const along = -(fx * (dx / len) + fy * (dy / len));
    const half2 = r * r - (fx * fx + fy * fy - along * along);
    if (half2 <= 0) return 0;
    const half = math.sqrt(half2);
    const lo = math.max(along - half, 0);
    const hi = math.min(along + half, len);
    return hi > lo ? hi - lo : 0;
}

export function PathCost(this: void, p: PathIn): PathCostAnswer {
    let creeps = 0;
    let cdps = 0;
    for (const c of p.creeps) {
        if (dist(c, p.spot) > c.reach) continue;
        creeps++;
        cdps += c.dps;
    }
    let tower = false;
    for (const t of p.towers) {
        if (dist(t, p.spot) <= t.reach) {
            tower = true;
            break;
        }
    }
    const enemies: EnemyCost[] = [];
    let covering = 0;
    let exposure = 0;
    for (const e of p.enemies) {
        const r = e.range + e.hull + p.hull;
        const d = dist(e, p.spot);
        const exp = InsideLength(p.from, p.spot, e, r) / p.speed;
        enemies.push({ pid: e.pid, dist: d, range: e.range, dmg: e.dmg, spa: e.spa, exp });
        if (d <= r) {
            covering++;
            if (exp > exposure) exposure = exp;
        }
    }
    return { creeps, cdps, tower, enemies, covering, exposure };
}
