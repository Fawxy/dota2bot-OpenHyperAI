/**
 * Where a laner stands while no action has the frame (lane positioning step 1, docs/proposals/2026-11-03-lane-positioning.md;
 * the spot's contract is that proposal's s2 "Bounds": one point out, no orders, no decisions).
 *
 * A preferred point (a ranged core at attack range - 50 from the lowest-HP enemy creep, a melee core just behind our front,
 * both shifted away from the nearest enemy hero; a support towards its approach line), then the candidate nearest to it that
 * keeps the hard limits: outside the enemy creeps' acquisition rings (520 melee, 620 ranged) widened by the HP margin, outside
 * every enemy tower's range, and no further back than the XP limit. Without a visible enemy wave (between waves, walking out)
 * the preferred point is our front and only the tower ring applies.
 */
import { Unit, Vector } from "bots/ts_libs/dota";

export const MELEE_RING = 520;
export const RANGED_RING = 620;
/** Enemy tower attack range (~700) plus a margin; at every level, since nothing in lane owns a dive. */
export const TOWER_RING = 750;
const RANGED_ABOVE = 320;
/** Ranged cores stand this much inside their range from the creep they will hit next. */
const RANGE_INSET = 50;
/** Melee cores stand this far behind our front, before the limits push them back. */
const MELEE_BEHIND = 100;
const SIDE_SHIFT = 120;
const PUSH_STEP = 50;
/** No push further back than this from the front: XP is shared within 1500 of a dying creep. */
const MAX_BACK = 1000;
/** Sideways candidates either side of the lane axis, so a ring can be cleared without giving ground. */
const LATERAL = [0, -100, 100, -200, 200];
const QUERY = 1400;
/**
 * HP margin added to the creep rings (judgement, step 0: cores laning took back from retreat at 45-48% HP walked into the
 * enemy wave): none at HP_SAFE or more, rising linearly to HP_MARGIN at HP_LOW and below.
 */
const HP_SAFE = 0.5;
const HP_LOW = 0.25;
const HP_MARGIN = 300;

export type Role = "core" | "support";
/** What decided the point: the preferred point itself, or the limit that moved it. */
export type Why = "pref" | "creep" | "hp" | "tower" | "xp";

export interface SpotInfo {
    spot: Vector;
    /** How far back along the lane the chosen candidate is, in 50-unit steps (telemetry). */
    pushed: number;
    anchor: "creep" | "front" | "wave";
    why: Why;
    /** The HP margin on the creep rings this frame. */
    margin: number;
}

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

/** Alive and in sight: a unit in the fog keeps a valid handle but reads no location. */
function alive(u: Unit | undefined): u is Unit {
    return u !== undefined && u !== null && !u.IsNull() && u.IsAlive() && u.GetLocation() !== undefined;
}

export function HpMargin(hpFrac: number): number {
    if (hpFrac >= HP_SAFE) return 0;
    if (hpFrac <= HP_LOW) return HP_MARGIN;
    return (HP_MARGIN * (HP_SAFE - hpFrac)) / (HP_SAFE - HP_LOW);
}

/** The first hard limit `p` breaks, or undefined: an enemy creep's ring (`creep`, or `hp` when only the margin breaks it), a tower. */
export function Breaks(p: Vector, creeps: Unit[], towers: Unit[], margin = 0): Why | undefined {
    let hp = false;
    for (const c of creeps) {
        if (!alive(c)) continue;
        const ring = isRangedCreep(c) ? RANGED_RING : MELEE_RING;
        const dist = d2(p, c.GetLocation());
        if (dist < ring) return "creep";
        if (dist < ring + margin) hp = true;
    }
    for (const t of towers) if (alive(t) && d2(p, t.GetLocation()) < TOWER_RING) return "tower";
    return hp ? "hp" : undefined;
}

/**
 * The spot. `role` decides the preferred point: a support stands between the nearest enemy hero and our wave. Undefined only
 * when the lane has no direction (front and its back point coincide).
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
    if (creeps.length === 0) {
        anchor = "wave";
        px = front.x + dx * MELEE_BEHIND;
        py = front.y + dy * MELEE_BEHIND;
    } else if (role === "core" && range > RANGED_ABOVE) {
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

    const margin = HpMargin(bot.GetHealth() / math.max(1, bot.GetMaxHealth()));
    const pref = Vector(px, py, front.z);
    const first = Breaks(pref, creeps, towers, margin);
    if (first === undefined) return { spot: pref, pushed: 0, anchor, why: "pref", margin };

    // Nearest candidate to the preferred point that keeps every limit: back along the lane in PUSH_STEP rows, a few sideways.
    let best: Vector | undefined;
    let bestCost = math.huge;
    let bestPushed = 0;
    const steps = math.floor(MAX_BACK / PUSH_STEP);
    for (let k = 0; k <= steps; k++) {
        const bx = px + dx * PUSH_STEP * k;
        const by = py + dy * PUSH_STEP * k;
        for (const off of LATERAL) {
            const cost = len(PUSH_STEP * k, off);
            if (cost >= bestCost) continue;
            const p = Vector(bx + nx * off, by + ny * off, front.z);
            if (Breaks(p, creeps, towers, margin) === undefined) {
                best = p;
                bestCost = cost;
                bestPushed = k;
            }
        }
        if (best !== undefined && PUSH_STEP * (k + 1) >= bestCost) break;
    }
    if (best === undefined) {
        return { spot: Vector(px + dx * PUSH_STEP * steps, py + dy * PUSH_STEP * steps, front.z), pushed: steps, anchor, why: "xp", margin };
    }
    return { spot: best, pushed: bestPushed, anchor, why: first, margin };
}
