/**
 * Where a laner stands between last hits (team slice 3, knowledge.md 1.1): outside the enemy creeps' acquisition
 * rings (520 melee, 620 ranged) and the enemy T1's range before level 6, a ranged core at attack range - 50 from
 * the lowest-HP enemy creep, a melee core just behind our creep line, both shifted to the side away from the
 * nearest enemy hero. Supports (slice 5) stand on the enemy offlaner's approach line instead of on the core.
 * Without a visible enemy wave (walking out, between waves) the caller falls back to OHA's own spot.
 */
import { Unit, Vector } from "bots/ts_libs/dota";

export const MELEE_RING = 520;
export const RANGED_RING = 620;
/** Enemy T1 attack range (~700) plus a margin. */
export const TOWER_RING = 750;
/** Below this level the tower ring applies (no tower dives before 6). */
const TOWER_RING_LEVEL = 6;
const RANGED_ABOVE = 320;
/** Ranged cores stand this much inside their range from the creep they will hit next. */
const RANGE_INSET = 50;
/** Melee cores stand this far behind our front, before the rings push them back. */
const MELEE_BEHIND = 100;
const SIDE_SHIFT = 120;
const PUSH_STEP = 50;
/** No push further back than this from the front: XP is shared within 1500 of a dying creep. */
const MAX_BACK = 1000;
const QUERY = 1400;

export type Role = "core" | "support";

function sub(a: Vector, b: Vector): [number, number] {
    return [a.x - b.x, a.y - b.y];
}

function len(x: number, y: number): number {
    return math.sqrt(x * x + y * y);
}

function d2(a: Vector, b: Vector): number {
    const [x, y] = sub(a, b);
    return len(x, y);
}

function isRangedCreep(c: Unit): boolean {
    return string.find(c.GetUnitName(), "ranged", 1, true)[0] !== undefined;
}

function alive(u: Unit | undefined): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive();
}

export interface SpotInfo {
    spot: Vector;
    /** How many 50-unit pushes the rings needed (telemetry). */
    pushed: number;
    anchor: "creep" | "front";
}

/** Rings the spot must stay outside of: enemy creeps by type, the enemy tower before level 6. */
export function Violates(bot: Unit, p: Vector, creeps: Unit[], towers: Unit[]): boolean {
    for (const c of creeps) {
        if (alive(c) && d2(p, c.GetLocation()) < (isRangedCreep(c) ? RANGED_RING : MELEE_RING)) return true;
    }
    if (bot.GetLevel() < TOWER_RING_LEVEL) {
        for (const t of towers) if (alive(t) && d2(p, t.GetLocation()) < TOWER_RING) return true;
    }
    return false;
}

/**
 * The spot, or undefined when no enemy lane creep is visible near the lane front (then OHA's spot is used).
 * `role` decides the anchor: a support stands between the nearest enemy hero and our wave, at the same rings.
 */
export function Compute(bot: Unit, role: Role): SpotInfo | undefined {
    const team = bot.GetTeam();
    const lane = bot.GetAssignedLane();
    const front = GetLaneFrontLocation(team, lane, 0);
    const back = GetLaneFrontLocation(team, lane, -400);
    let [dx, dy] = sub(back, front);
    const l = len(dx, dy);
    if (l < 1) return undefined;
    dx /= l;
    dy /= l;

    const creeps: Unit[] = [];
    for (const c of bot.GetNearbyLaneCreeps(QUERY, true)) {
        if (alive(c) && d2(c.GetLocation(), front) <= 1000) creeps.push(c);
    }
    if (creeps.length === 0) return undefined;
    const towers = bot.GetNearbyTowers(1600, true);

    let enemyHero: Unit | undefined;
    let heroDist = math.huge;
    for (const h of bot.GetNearbyHeroes(1600, true, 0)) {
        if (alive(h)) {
            const dist = d2(h.GetLocation(), front);
            if (dist < heroDist) {
                heroDist = dist;
                enemyHero = h;
            }
        }
    }

    let px: number;
    let py: number;
    let anchor: SpotInfo["anchor"] = "front";
    const range = bot.GetAttackRange();
    if (role === "core" && range > RANGED_ABOVE) {
        let low: Unit | undefined;
        for (const c of creeps) if (low === undefined || c.GetHealth() < low.GetHealth()) low = c;
        const at = low!.GetLocation();
        px = at.x + dx * (range - RANGE_INSET);
        py = at.y + dy * (range - RANGE_INSET);
        anchor = "creep";
    } else {
        px = front.x + dx * MELEE_BEHIND;
        py = front.y + dy * MELEE_BEHIND;
    }

    // Perpendicular to the lane; shift away from the enemy hero (core) or towards its approach (support).
    const nx = -dy;
    const ny = dx;
    if (enemyHero !== undefined) {
        const [hx, hy] = sub(enemyHero.GetLocation(), front);
        const side = hx * nx + hy * ny >= 0 ? 1 : -1;
        const shift = role === "support" ? SIDE_SHIFT * 2 : -SIDE_SHIFT;
        px += nx * side * shift;
        py += ny * side * shift;
    }

    let pushed = 0;
    let p = Vector(px, py, front.z);
    while (Violates(bot, p, creeps, towers) && pushed * PUSH_STEP < MAX_BACK) {
        pushed++;
        p = Vector(px + dx * PUSH_STEP * pushed, py + dy * PUSH_STEP * pushed, front.z);
    }
    return { spot: p, pushed, anchor };
}
