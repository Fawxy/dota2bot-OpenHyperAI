/**
 * CANDIDATE(spell-aim): where to cast a point or no-target spell so that it hits one unit it must, and what else it hits (slice
 * oha-spell-aim). Pure geometry on places passed in: spell_secure.ts aims at their lane creep, and a second asker (a cast on a
 * hero) would make it a shared module. The unit that must be hit is hit by its centre, so its hull is the aim's margin; any
 * other unit counts as hit when its hull touches the spell.
 */

export interface Place {
    x: number;
    y: number;
}

export interface Body extends Place {
    hull: number;
}

/**
 * Where a spell lands. `a`: an area of `radius` centred anywhere within `range` of the caster. `l`: a line from the caster, `length`
 * long and `half` to each side. `r`: a circle of `radius` whose centre is `offset` in front of the caster (it faces where it aims).
 * `s`: a circle of `radius` around the caster.
 */
export interface Geom {
    k: "a" | "l" | "r" | "s";
    range: number;
    radius: number;
    half: number;
    length: number;
    offset: number;
}

export interface Aim {
    /** How far the caster walks before the cast can hit `must` (0: it casts from where it stands); for `r` the walk may be away. */
    gap: number;
    /** Where it casts from. */
    from: Place;
    /** The cast's point: the area's or circle's centre, or for `l` the point on the line level with `must`. */
    at: Place;
    /** `must`'s distance from the centre (for `l`, from the line's axis). */
    off: number;
    /** Units of `wanted` the cast hits, and of `others`. */
    also: number;
    others: number;
}

// LuaJIT (Dota) has math.atan2; Lua 5.3 (fengari, tests) folds it into math.atan.
const atan2: (this: void, y: number, x: number) => number = (math as any).atan2 ?? (math as any).atan;

function dist(a: Place, b: Place): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

/** `p` moved `by` towards `to` (away for a negative `by`). */
function toward(p: Place, to: Place, by: number): Place {
    const d = dist(p, to);
    if (d <= 0 || by === 0) return { x: p.x, y: p.y };
    return { x: p.x + ((to.x - p.x) * by) / d, y: p.y + ((to.y - p.y) * by) / d };
}

/** An angle folded into (-pi, pi]. */
function norm(a: number): number {
    let x = a % (2 * Math.PI);
    if (x > Math.PI) x -= 2 * Math.PI;
    else if (x <= -Math.PI) x += 2 * Math.PI;
    return x;
}

/** Whether the line from `from` along angle `th` hits `b` within `length` and `half` plus `extra` of its axis. */
function onLine(from: Place, th: number, b: Place, g: Geom, extra: number): boolean {
    const px = b.x - from.x;
    const py = b.y - from.y;
    const along = px * math.cos(th) + py * math.sin(th);
    if (along < 0 || along > g.length + extra) return false;
    return math.abs(py * math.cos(th) - px * math.sin(th)) <= g.half + extra;
}

/** The centre of the circle an `r` spell lands, facing angle `th` from `from`. */
function ringCentre(from: Place, th: number, g: Geom): Place {
    return { x: from.x + g.offset * math.cos(th), y: from.y + g.offset * math.sin(th) };
}

function hitsAt(g: Geom, from: Place, th: number, b: Body): boolean {
    if (g.k === "l") return onLine(from, th, b, g, b.hull);
    return dist(ringCentre(from, th, g), b) <= g.radius + b.hull;
}

/**
 * The half-width of the arc of facing angles from `from` at which the spell hits a unit `d` away with `extra` of slack (its hull,
 * or 0 for `must`), around the angle to it; undefined when no facing reaches it.
 */
function arcOf(g: Geom, d: number, extra: number): number | undefined {
    if (g.k === "l") {
        if (d > g.length + extra) return undefined;
        const w = g.half + extra;
        return d <= w ? Math.PI / 2 : math.asin(w / d);
    }
    const r = g.radius + extra;
    if (d <= 0 || g.offset <= 0) return d + g.offset <= r ? Math.PI : undefined;
    const c = (d * d + g.offset * g.offset - r * r) / (2 * d * g.offset);
    if (c > 1) return undefined;
    return c <= -1 ? Math.PI : math.acos(c);
}

/**
 * The facing for a line or a ring: the arc that hits `must` is cut at the edges of each wanted unit's arc, and of the pieces the
 * one that hits the most wanted units wins. Within it the facing straight at `must` if the piece holds it, else the piece's middle,
 * so the unit nearest an edge keeps the most margin.
 */
function facing(g: Geom, from: Place, must: Place, wanted: Body[]): number {
    const base = atan2(must.y - from.y, must.x - from.x);
    const a0 = arcOf(g, dist(from, must), 0) ?? 0;
    const cuts: number[] = [-a0, a0];
    const arcs: { c: number; a: number }[] = [];
    for (const w of wanted) {
        const a = arcOf(g, dist(from, w), w.hull);
        if (a === undefined) continue;
        const c = norm(atan2(w.y - from.y, w.x - from.x) - base);
        arcs.push({ c, a });
        for (const e of [norm(c - a), norm(c + a)]) if (e > -a0 && e < a0) cuts.push(e);
    }
    table.sort(cuts);
    let best = 0;
    let bestN = -1;
    let bestHas0 = false;
    for (let i = 0; i + 1 < cuts.length; i++) {
        const lo = cuts[i];
        const hi = cuts[i + 1];
        const mid = (lo + hi) / 2;
        let n = 0;
        for (const r of arcs) if (math.abs(norm(mid - r.c)) <= r.a) n++;
        const has0 = lo <= 0 && hi >= 0;
        if (n > bestN || (n === bestN && has0 && !bestHas0)) {
            bestN = n;
            best = has0 ? 0 : mid;
            bestHas0 = has0;
        }
    }
    return base + best;
}

function count(units: Body[], hit: (b: Body) => boolean): number {
    let n = 0;
    for (const b of units) if (hit(b)) n++;
    return n;
}

/**
 * Centres an area may take to hit `must` and wanted units: `must` itself; for each wanted unit near enough, the point between them
 * at the middle of the stretch where both are hit; and the middle of `must` and all of those. Each is pulled back within `range`.
 */
function areaCentres(g: Geom, from: Place, must: Place, wanted: Body[]): Place[] {
    const out: Place[] = [must];
    let sx = must.x;
    let sy = must.y;
    let n = 1;
    for (const w of wanted) {
        const d = dist(must, w);
        if (d > 2 * g.radius + w.hull) continue;
        const lo = math.max(0, d - g.radius - w.hull);
        const hi = math.min(g.radius, d);
        out.push(toward(must, w, (lo + hi) / 2));
        sx += w.x;
        sy += w.y;
        n++;
    }
    if (n > 2) out.push({ x: sx / n, y: sy / n });
    const pulled: Place[] = [];
    for (const c of out) {
        const d = dist(from, c);
        pulled.push(d > g.range ? toward(from, c, g.range) : c);
    }
    return pulled;
}

/** Where to cast `g` from `caster` so that it hits `must` and as many of `wanted` as it can; `others` are counted, not aimed for. */
export function AimAt(this: void, g: Geom, caster: Place, must: Place, wanted: Body[], others: Body[]): Aim {
    const d = dist(caster, must);
    if (g.k === "s") {
        const gap = math.max(0, d - g.radius);
        const from = toward(caster, must, gap);
        const hit = (b: Body): boolean => dist(from, b) <= g.radius + b.hull;
        return { gap, from, at: from, off: dist(from, must), also: count(wanted, hit), others: count(others, hit) };
    }
    if (g.k === "a") {
        const gap = math.max(0, d - (g.range + g.radius));
        const from = toward(caster, must, gap);
        const centres = areaCentres(g, from, must, wanted);
        // The first centre is `must` pulled into cast range, which after the walk sits at the radius's edge: it is always a candidate,
        // and the slack keeps rounding from dropping it.
        let at = centres[0];
        let bestN = -1;
        let bestOff = math.huge;
        for (const c of centres) {
            const off = dist(c, must);
            if (off > g.radius + 1e-6 * math.max(1, g.radius)) continue;
            const n = count(wanted, (b) => dist(c, b) <= g.radius + b.hull);
            if (n > bestN || (n === bestN && off < bestOff)) {
                at = c;
                bestN = n;
                bestOff = off;
            }
        }
        const hit = (b: Body): boolean => dist(at, b) <= g.radius + b.hull;
        return { gap, from, at, off: dist(at, must), also: count(wanted, hit), others: count(others, hit) };
    }
    // A line reaches `must` once within its length; a ring once `must` is within its radius of the offset, nearer or farther.
    let gap: number;
    let from: Place;
    if (g.k === "l") {
        gap = math.max(0, d - g.length);
        from = toward(caster, must, gap);
    } else {
        const miss = math.abs(d - g.offset) - g.radius;
        gap = math.max(0, miss);
        from = toward(caster, must, d > g.offset ? gap : -gap);
    }
    const th = facing(g, from, must, wanted);
    const hit = (b: Body): boolean => hitsAt(g, from, th, b);
    let at: Place;
    let off: number;
    if (g.k === "l") {
        const px = must.x - from.x;
        const py = must.y - from.y;
        const along = px * math.cos(th) + py * math.sin(th);
        at = { x: from.x + along * math.cos(th), y: from.y + along * math.sin(th) };
        off = math.abs(py * math.cos(th) - px * math.sin(th));
    } else {
        at = ringCentre(from, th, g);
        off = dist(at, must);
    }
    return { gap, from, at, off, also: count(wanted, hit), others: count(others, hit) };
}
