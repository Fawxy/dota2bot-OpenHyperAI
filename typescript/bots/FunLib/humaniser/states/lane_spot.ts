/**
 * Where a laner stands while no action has the frame (lane positioning step 1, docs/proposals/2026-11-03-lane-positioning.md;
 * the spot's contract is that proposal's s2 "Bounds": one point out, no orders, no decisions).
 *
 * A preferred point (a ranged core at attack range - 50 from the lowest-HP enemy creep, a melee core just behind our front,
 * both shifted away from the nearest enemy hero; a support towards its approach line), then the candidate nearest to it that
 * keeps the hard limits: outside every visible enemy hero's reach (its attack range plus both bounding radii plus 1.5 s of
 * its movement, and never under 800), outside the enemy creeps' acquisition rings (520 melee, 620 ranged), both widened by the
 * HP margin, outside every enemy tower's range plus the hold's drift, and no further back than the XP limit (1,000 from the
 * preferred point). With no candidate inside the XP limit that keeps them all, the furthest back that keeps the tower limit. Without a visible enemy wave (between waves,
 * walking out) the preferred point is 100 behind our front and the hero and tower limits apply.
 */
import { Unit, Vector } from "bots/ts_libs/dota";

export const MELEE_RING = 520;
export const RANGED_RING = 620;
/** Enemy tower attack range (~700) plus a margin; at every level, since nothing in lane owns a dive. */
export const TOWER_RING = 750;
/** How far the hold may leave the spot (its tolerance 40 plus scatter 40), so a hold on a spot at the ring stays outside it. */
const HOLD_DRIFT = 80;
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
/**
 * Seconds of the enemy hero's movement added to its attack reach: the ground it closes before we react (judgement). lposchk1
 * with a fixed 150: cores held 400-800 from an enemy hero lost 0.7-1.1 HP-% a second there, against 0.3 at 800-1,200.
 * lposchk2 with 1 s (reach about 920 against a 570-range hero): idle cores 800-1,000 from a ranged enemy still lost 0.39 a
 * second, 0.06 beyond 1,000; 1.5 s puts that reach at about 1,070.
 */
const REACT_SECS = 1.5;
/**
 * No enemy hero's reach is under this (the melee margin, judgement): lposchk2 idle cores 400-600 from a melee enemy (reach
 * about 500) lost 0.5 HP-% a second, 600-800 0.24, beyond 800 0.09; a melee hero closes on a core that stands at its reach.
 */
const MIN_REACH = 800;

export type Role = "core" | "support";
/** What decided the point: the preferred point itself, or the limit that moved it. */
export type Why = "pref" | "hero" | "creep" | "hp" | "tower" | "xp";

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

/** How close `self` may stand to an enemy hero: its attack reach to us plus REACT_SECS of its movement, at least MIN_REACH. */
export function HeroReach(self: Unit, enemy: Unit): number {
    return math.max(MIN_REACH, enemy.GetAttackRange() + enemy.GetBoundingRadius() + self.GetBoundingRadius() + REACT_SECS * enemy.GetCurrentMovementSpeed());
}

/**
 * The first hard limit `p` breaks, or undefined: an enemy hero's reach (`hero`), an enemy creep's ring (`creep`), a tower, or
 * `hp` when only the HP margin breaks a hero or creep limit. `reach` holds each hero's reach (HeroReach), in `heroes` order.
 */
export function Breaks(p: Vector, creeps: Unit[], towers: Unit[], margin = 0, heroes: Unit[] = [], reach: number[] = []): Why | undefined {
    let hp = false;
    for (let i = 0; i < heroes.length; i++) {
        const h = heroes[i];
        if (!alive(h)) continue;
        const dist = d2(p, h.GetLocation());
        if (dist < reach[i]) return "hero";
        if (dist < reach[i] + margin) hp = true;
    }
    for (const c of creeps) {
        if (!alive(c)) continue;
        const ring = isRangedCreep(c) ? RANGED_RING : MELEE_RING;
        const dist = d2(p, c.GetLocation());
        if (dist < ring) return "creep";
        if (dist < ring + margin) hp = true;
    }
    if (breaksTower(p, towers)) return "tower";
    return hp ? "hp" : undefined;
}

function breaksTower(p: Vector, towers: Unit[]): boolean {
    for (const t of towers) if (alive(t) && d2(p, t.GetLocation()) < TOWER_RING + HOLD_DRIFT) return true;
    return false;
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
    const heroes: Unit[] = [];
    const reach: number[] = [];
    for (const h of bot.GetNearbyHeroes(1600, true, 0)) {
        if (alive(h)) {
            heroes.push(h);
            reach.push(HeroReach(bot, h));
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
    const first = Breaks(pref, creeps, towers, margin, heroes, reach);
    if (first === undefined) return { spot: pref, pushed: 0, anchor, why: "pref", margin };

    // Nearest candidate to the preferred point that keeps every limit: back along the lane in PUSH_STEP rows, a few sideways.
    let best: Vector | undefined;
    let bestCost = math.huge;
    let bestPushed = 0;
    // The fallback: the furthest-back candidate that still keeps the tower limit.
    let keep: Vector | undefined;
    let keepPushed = 0;
    const steps = math.floor(MAX_BACK / PUSH_STEP);
    for (let k = 0; k <= steps; k++) {
        const bx = px + dx * PUSH_STEP * k;
        const by = py + dy * PUSH_STEP * k;
        for (const off of LATERAL) {
            const cost = len(PUSH_STEP * k, off);
            if (cost >= bestCost) continue;
            const p = Vector(bx + nx * off, by + ny * off, front.z);
            if (best === undefined && (keep === undefined || k > keepPushed) && !breaksTower(p, towers)) {
                keep = p;
                keepPushed = k;
            }
            if (Breaks(p, creeps, towers, margin, heroes, reach) === undefined) {
                best = p;
                bestCost = cost;
                bestPushed = k;
            }
        }
        if (best !== undefined && PUSH_STEP * (k + 1) >= bestCost) break;
    }
    if (best === undefined) {
        if (keep !== undefined) return { spot: keep, pushed: keepPushed, anchor, why: "xp", margin };
        return { spot: Vector(px + dx * PUSH_STEP * steps, py + dy * PUSH_STEP * steps, front.z), pushed: steps, anchor, why: "xp", margin };
    }
    return { spot: best, pushed: bestPushed, anchor, why: first, margin };
}
