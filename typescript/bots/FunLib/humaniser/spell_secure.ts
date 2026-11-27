/**
 * CANDIDATE(spell-secure): whether a castable spell could take a lane creep, and at what price (slice oha-creep-spell-shadow;
 * no-creep-unpaid proposal s6, "a ranged ability as a second verb"). Pure answers on facts passed in, so the tests need no game:
 * creep_offer.ts reads the facts (SpellReady.CreepSpellsOf, the engine's forecast and turn time) and logs the best answer on
 * the creep offer's line; the creep row casts on `CastPick` of the same answers (Ours.CreepSpells).
 */
import type { CreepSpell } from "bots/FunLib/humaniser/spell_ready";
import * as SpellAim from "bots/FunLib/humaniser/spell_aim";

export interface Place {
    x: number;
    y: number;
}

export interface Foe extends Place {
    hull: number;
}

/** A unit with its velocity (units a second), to place it when a cast lands. */
export interface Moving extends Foe {
    vx: number;
    vy: number;
}

function dist(a: Place, b: Place): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

export interface Timing {
    /**
     * `TimingOf` (`u`): centre distance less the cast range, below 0 inside it. `Aimed` (`p`, `n`): the aim's walk, floored at 0 (for a
     * ring it may be away from the creep). Above 0 the hero must walk first.
     */
    gap: number;
    walk: number;
    /** Seconds from now until the damage lands: the walk, the turn (not for `n`), the cast point and the flight at `speed`. */
    land: number;
}

/**
 * When the spell's damage lands on a creep `d` away, the hero walking straight into range at `heroSpeed` and turning for `turn` s.
 * The flight is from where the hero casts (no farther than the cast range). The cast range is read centre to centre: whether
 * Valve adds hulls is not checked, so `gap` near 0 is uncertain by a hull (about 16 to 24).
 */
export function TimingOf(this: void, s: CreepSpell, d: number, heroSpeed: number, turn: number): Timing {
    const gap = d - s.range;
    const walk = math.max(0, gap) / math.max(100, heroSpeed);
    if (s.shape === "n") return { gap, walk, land: walk + s.cp };
    const flight = s.speed > 0 ? math.min(d, s.range) / s.speed : 0;
    return { gap, walk, land: walk + turn + s.cp + flight };
}

/** The spell kills the creep: it is alive when the damage lands (`hp` the forecast HP then) and the damage after resistance covers it. */
export function Kills(this: void, hp: number, taken: number): boolean {
    return hp > 0 && hp <= taken;
}

/**
 * Mana left after the cast over the reserve (user 27/11/2026: after the cast the hero can still cast its disable): the dearest of
 * the hero's other learned key spells, castable now or not. 0 or more meets the reserve.
 */
export function OverReserve(this: void, mana: number, s: CreepSpell, keys: Record<string, number>): number {
    let reserve = 0;
    for (const [name, cost] of pairs(keys)) if (name !== s.name && cost > reserve) reserve = cost;
    return mana - s.mana - reserve;
}

/**
 * Enemy heroes the cast aimed at the creep would also hit. A line (`half` over 0, not `n`): from the hero through the creep to the
 * farther of the cast range and the creep, within `half` plus the foe's hull of it. Otherwise an area (`radius` over 0) around the
 * creep, or around the hero for `n`. Else none. A bounce (Arc Lightning's jump radius) reads as an area around the creep.
 */
export function AlsoHit(this: void, s: CreepSpell, hero: Place, creep: Place, foes: Foe[]): number {
    let n = 0;
    if (s.half > 0 && s.shape !== "n") {
        const d = dist(hero, creep);
        if (d <= 0) return 0;
        const ux = (creep.x - hero.x) / d;
        const uy = (creep.y - hero.y) / d;
        const len = math.max(s.range, d);
        for (const f of foes) {
            const px = f.x - hero.x;
            const py = f.y - hero.y;
            const along = px * ux + py * uy;
            if (along < 0 || along > len) continue;
            if (math.abs(px * uy - py * ux) <= s.half + f.hull) n++;
        }
        return n;
    }
    if (s.radius <= 0) return 0;
    const centre = s.shape === "n" ? hero : creep;
    for (const f of foes) if (dist(f, centre) <= s.radius + f.hull) n++;
    return n;
}

/**
 * Where a point or no-target spell lands (slice oha-spell-aim): SPELL_SHAPE's kind, else for a spell with no row the read before it
 * (a line when it has a width, else an area at the point; a no-target spell around the hero).
 */
export function GeomOf(this: void, s: CreepSpell): SpellAim.Geom {
    const k = s.geom ?? (s.shape === "n" ? "s" : s.half > 0 ? "l" : "a");
    return { k, range: s.range, radius: k === "s" && s.radius <= 0 ? s.range : s.radius, half: s.half, length: k === "l" ? math.max(s.length, s.range) : 0, offset: s.offset };
}

function movedBy(u: Moving, t: number): Moving {
    return { x: u.x + u.vx * t, y: u.y + u.vy * t, hull: u.hull, vx: u.vx, vy: u.vy };
}

/** A `p` or `n` spell's landing on an aim: the walk, the turn (not for a spell around the hero), the cast point, the flight from where it casts, the delay. */
function aimedTiming(s: CreepSpell, g: SpellAim.Geom, aim: SpellAim.Aim, creep: Place, heroSpeed: number, turn: number): Timing {
    const walk = aim.gap / math.max(100, heroSpeed);
    let flight = 0;
    if (s.speed > 0 && (g.k === "l" || g.k === "a")) flight = dist(aim.from, g.k === "l" ? creep : aim.at) / s.speed;
    return { gap: aim.gap, walk, land: walk + (g.k === "s" ? 0 : turn) + s.cp + flight + s.delay };
}

/**
 * A `p` or `n` spell aimed at the creep (spell_aim.ts): aimed at the creep and the foes where they are, then again where their
 * velocities put them when that cast lands, and timed on the second aim. `others` (their other creeps) are counted where they are.
 * `turn` is the turn to face the creep: a line or ring aimed off it to catch a hero turns at most its arc further (a hundredth
 * of a second or two). `centre`: the foes the same cast hits aimed straight at the creep, for the line to show what the aim added.
 */
export function Aimed(this: void, s: CreepSpell, hero: Place, heroSpeed: number, turn: number, creep: Moving, foes: Moving[], others: Foe[]): { aim: SpellAim.Aim; timing: Timing; centre: number } {
    const g = GeomOf(s);
    const first = SpellAim.AimAt(g, hero, creep, foes, others);
    const t = aimedTiming(s, g, first, creep, heroSpeed, turn).land;
    const c2 = movedBy(creep, t);
    const f2: Moving[] = [];
    for (const f of foes) f2.push(movedBy(f, t));
    const aim = SpellAim.AimAt(g, hero, c2, f2, others);
    // Aimed with nobody wanted, the cast goes straight at the creep; the foes passed as `others` are then those it hits anyway.
    const centre = SpellAim.AimAt(g, hero, c2, [], f2).others;
    return { aim, timing: aimedTiming(s, g, aim, c2, heroSpeed, turn), centre };
}

/** One spell's answer on one creep at one read. */
export interface Answer {
    spell: CreepSpell;
    timing: Timing;
    /** Damage after the creep's resistance; the forecast HP when it lands. */
    taken: number;
    hp: number;
    kill: boolean;
    over: number;
    /** Enemy heroes also hit: for `u` AlsoHit, for `p` and `n` the aim's. */
    also: number;
    /** `p` and `n`: the aim, and AlsoHit's count for the same spell aimed at the creep's centre (the read before the aim). */
    aim?: SpellAim.Aim;
    centre?: number;
}

/** HP still to lose before the spell would kill. */
function short(a: Answer): number {
    return a.hp - a.taken;
}

/**
 * The best of a read's answers (the line's, nothing decides on it): a kill before none, then the reserve met, then no walk, then the cheaper. With no kill: the creep alive when it
 * lands before dead by then, then the one with the least HP still to lose.
 */
export function Best(this: void, as: Answer[]): Answer | undefined {
    let best: Answer | undefined;
    for (const a of as) {
        if (best === undefined) {
            best = a;
            continue;
        }
        if (a.kill !== best.kill) {
            if (a.kill) best = a;
            continue;
        }
        if (a.kill) {
            if (a.over >= 0 !== best.over >= 0) {
                if (a.over >= 0) best = a;
            } else if (a.timing.gap <= 0 !== best.timing.gap <= 0) {
                // Slice oha-spell-aim: three razes cost the same, and the cheaper-first order kept Raze 1 where Raze 2 hits from the spot.
                if (a.timing.gap <= 0) best = a;
            } else if (a.spell.mana < best.spell.mana) best = a;
        } else if (a.hp > 0 !== best.hp > 0) {
            if (a.hp > 0) best = a;
        } else if (short(a) < short(best)) best = a;
    }
    return best;
}

/**
 * Whether the cast lands where the hero faces, so the hero turns before it (slice oha-aimed-cast): a no-target line or circle in front
 * of the hero. A point spell turns the hero to its point in the game's own order; a spell around the hero needs no facing.
 */
export function Turns(this: void, s: CreepSpell): boolean {
    if (s.shape !== "n") return false;
    const k = GeomOf(s).k;
    return k === "l" || k === "r";
}

/** The facing (radians) an aimed line or ring casts at (the aim's `th`); undefined for any other answer. */
export function FacingOf(this: void, a: Answer): number | undefined {
    return a.aim?.th;
}

/**
 * Why an answer is not a cast the creep row may order, in the order asked; undefined when it is (`CastPick`). `aim`: a cast that turns
 * the hero whose aim has less slack than the pick's `slack`. `aimoff`: a point or no-target cast that passes every gate while
 * Ours.AimedCasts is off (the shadow of that widening).
 */
export type CastWhy = "shape" | "nokill" | "walk" | "reserve" | "key" | "aim" | "aimoff";

const CAST_STAGES: CastWhy[] = ["shape", "nokill", "walk", "reserve", "key", "aim", "aimoff"];

export interface PickOpts {
    /** Ours.AimedCasts: point and no-target answers may be cast. */
    aimed: boolean;
    /** The least slack (radians) a cast that turns the hero needs. */
    slack: number;
}

function castWhyOf(a: Answer, o: PickOpts): CastWhy | undefined {
    if (a.spell.shape !== "u" && a.aim === undefined) return "shape";
    if (!a.kill) return "nokill";
    if (a.timing.gap > 0) return "walk";
    if (a.over < 0) return "reserve";
    // User 27/11/2026: a disable secures a creep only when the same cast also hits an enemy hero.
    if (a.spell.key && a.also <= 0) return "key";
    if (a.spell.shape === "u") return undefined;
    if (Turns(a.spell) && (a.aim!.slack ?? 0) < o.slack) return "aim";
    return o.aimed ? undefined : "aimoff";
}

/** Whether `a` is the better of two casts that both pass: a damage spell before a key spell, a unit-target one before an aimed one, then the cheaper. */
function castBefore(a: Answer, b: Answer): boolean {
    if (a.spell.key !== b.spell.key) return !a.spell.key;
    const au = a.spell.shape === "u";
    if (au !== (b.spell.shape === "u")) return au;
    return a.spell.mana < b.spell.mana;
}

const UNIT_ONLY: PickOpts = { aimed: false, slack: 0 };

/**
 * The cast the creep row may order (slices oha-creep-spells, oha-aimed-cast): a spell that kills now, needs no walk, meets the reserve,
 * and is a damage spell or also hits an enemy hero; a point or no-target one only aimed, with `o.aimed`, and with the slack to turn to
 * when it turns the hero. Of those `castBefore`'s order. With none, `why` is the furthest any answer got (`CAST_STAGES`' order), so the
 * line says what came closest.
 */
export function CastPick(this: void, as: Answer[], o: PickOpts = UNIT_ONLY): { pick?: Answer; why?: CastWhy } {
    let pick: Answer | undefined;
    let far = -1;
    for (const a of as) {
        const why = castWhyOf(a, o);
        if (why === undefined) {
            if (pick === undefined || castBefore(a, pick)) pick = a;
            continue;
        }
        const at = CAST_STAGES.indexOf(why);
        if (at > far) far = at;
    }
    if (pick !== undefined) return { pick };
    return { why: far >= 0 ? CAST_STAGES[far] : undefined };
}
