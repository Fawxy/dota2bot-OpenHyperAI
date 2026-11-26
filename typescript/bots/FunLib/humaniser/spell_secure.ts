/**
 * CANDIDATE(spell-secure): whether a castable spell could take a lane creep, and at what price (slice oha-creep-spell-shadow;
 * no-creep-unpaid proposal s6, "a ranged ability as a second verb"). Pure answers on facts passed in, so the tests need no game:
 * creep_offer.ts reads the facts (SpellReady.CreepSpellsOf, the engine's forecast and turn time) and logs the best answer on
 * the creep offer's line. Nothing decides on it yet; a row that casts will read the same answers.
 */
import type { CreepSpell } from "bots/FunLib/humaniser/spell_ready";

export interface Place {
    x: number;
    y: number;
}

export interface Foe extends Place {
    hull: number;
}

function dist(a: Place, b: Place): number {
    return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y));
}

export interface Timing {
    /** Centre distance less the cast range (for `n`, the radius); above 0 the hero must walk first. */
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

/** One spell's answer on one creep at one read. */
export interface Answer {
    spell: CreepSpell;
    timing: Timing;
    /** Damage after the creep's resistance; the forecast HP when it lands. */
    taken: number;
    hp: number;
    kill: boolean;
    over: number;
    also: number;
}

/** HP still to lose before the spell would kill. */
function short(a: Answer): number {
    return a.hp - a.taken;
}

/**
 * The best of a read's answers: a kill before none, then the reserve met, then the cheaper. With no kill: the creep alive when it
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
            } else if (a.spell.mana < best.spell.mana) best = a;
        } else if (a.hp > 0 !== best.hp > 0) {
            if (a.hp > 0) best = a;
        } else if (short(a) < short(best)) best = a;
    }
    return best;
}
