/**
 * Plays (slice rune-spawn; a behaviour library from its first commit, user 04/11/2026): a play is a short team action one
 * hero starts on a weighted dice roll, so rotations and skirmishes come at moments that feel spontaneous rather than
 * judged. A consumer defines its kinds (base weight, timeout, own hard zeros), offers chances (kind, initiator, target,
 * place); this module weighs each from the shared fight readings, draws once from the engine's Skill rng and keeps the
 * fired play visible to the team until it ends. What a play does is the consumer's; a hero in a fired play is driven by
 * it (other deciders defer, OWNERSHIP H14); joining is each other hero's own decision. One `ev=play` line per chance, one
 * `ev=play_end` line per fired play (the library ends any play past its timeout itself).
 */
import { Unit, Vector } from "bots/ts_libs/dota";
import * as FR from "bots/FunLib/humaniser/fight_readings";
import * as LaneConfig from "bots/FunLib/humaniser/lane_config";
import * as Telemetry from "bots/FunLib/humaniser/telemetry";

export type Kind = string;

/** A consumer's kind: its base weight, how long a play may run, whether its target is chased (a tower beside the target is
 *  then a hard zero) and any hard zero of its own over the plain inputs. */
export interface KindDef {
    base: number;
    timeout: number;
    chases: boolean;
    zero?: (this: void, i: Inputs) => string | undefined;
}

// All judgement (slice rune-spawn, Decisions) unless cited.
export const SETTINGS = {
    /** No play fires above this weight: every chance keeps some chance of not happening. */
    MaxWeight: 0.9,
    /** Heroes within this of the place count for either side. */
    Radius: 1600,
    /** Per level of average difference, ours minus theirs; the factor is clamped to LevelClamp. */
    PerLevel: 0.15,
    LevelClamp: [0.4, 1.6] as [number, number],
    /** By heroes up (ours minus theirs within Radius): one up, even, one down. Two or more down is a hard zero. */
    CountUp: 1.3,
    CountDown: 0.5,
    /** Initiator HP fraction below this: a hard zero. Above it the factor rises linearly to 1 at HpLow. */
    HpFloor: 0.4,
    HpLow: 0.6,
    /** Mana's share of the HP factor: hp x (1 - ManaShare + ManaShare x mana fraction). */
    ManaShare: 0.2,
    /** Target HP fraction: at or under TargetLow x TargetLowFactor, at or over TargetHigh x TargetHighFactor, linear between.
     *  Row "Core in lane"'s logs (04/11/2026): cores 11 kills per 100 encounters with the target at 40% HP or less, 0.6
     *  above 70%, the strongest kill predictor there; the factor sizes are judgement. */
    TargetLow: 0.4,
    TargetHigh: 0.7,
    TargetLowFactor: 1.6,
    TargetHighFactor: 0.8,
    /** A held power rune. */
    Rune: 1.4,
    /** The target's distance to its own nearest tower, for chasing kinds: under TowerZero a hard zero, under TowerNear x TowerFactor. */
    TowerZero: 700,
    TowerNear: 1500,
    TowerFactor: 0.5,
    /** A named forecast input is clamped to this. */
    ForecastClamp: [0.5, 1.5] as [number, number],
    /** After a play ends, a target death within this many seconds with one of the play's heroes within KillNear counts as its
     *  kill (row "Core in lane"'s `@lane_encounters` counts a kill near the hero within 5 s). */
    KillAfter: 5,
    KillNear: 1200,
    /** A target left under this HP fraction, or gone this far from where it stood (a TP or blink), was forced out. */
    ForcedHp: 0.3,
    ForcedMoved: 1200,
};

const kinds: Record<Kind, KindDef> = {};

/** Registers (or replaces) a kind. Consumers call it at load. */
export function Define(kind: Kind, def: KindDef): void {
    kinds[kind] = def;
}

export function DefOf(kind: Kind): KindDef | undefined {
    return kinds[kind];
}

/** Plain inputs of one chance: Weigh holds the rules over these so tests need no units. */
export interface Inputs {
    kind: Kind;
    /** Average level of our heroes and of theirs within Radius of the place (the initiator and target always count). */
    ourLevel: number;
    theirLevel: number;
    ours: number;
    theirs: number;
    hp: number;
    mana: number;
    /** The target's HP fraction (undefined with no target: factor 1). */
    targetHp?: number;
    rune: boolean;
    /** The target's distance to its nearest tower (math.huge with no target or no tower). */
    tower: number;
    forecast?: number;
}

export interface Weight {
    w: number;
    level: number;
    count: number;
    hp: number;
    target: number;
    rune: number;
    tower: number;
    forecast: number;
    /** Why the weight is a hard zero, if it is. */
    zero?: string;
}

function clamp(v: number, lo: number, hi: number): number {
    return math.max(lo, math.min(hi, v));
}

function targetFactor(hp: number | undefined): number {
    const s = SETTINGS;
    if (hp === undefined) return 1;
    if (hp <= s.TargetLow) return s.TargetLowFactor;
    if (hp >= s.TargetHigh) return s.TargetHighFactor;
    return s.TargetLowFactor + ((hp - s.TargetLow) / (s.TargetHigh - s.TargetLow)) * (s.TargetHighFactor - s.TargetLowFactor);
}

export function Weigh(i: Inputs): Weight {
    const s = SETTINGS;
    const def = kinds[i.kind];
    const level = clamp(1 + s.PerLevel * (i.ourLevel - i.theirLevel), s.LevelClamp[0], s.LevelClamp[1]);
    const up = i.ours - i.theirs;
    const count = up >= 1 ? s.CountUp : up === 0 ? 1 : up === -1 ? s.CountDown : 0;
    const hpPart = i.hp < s.HpFloor ? 0 : i.hp >= s.HpLow ? 1 : (i.hp - s.HpFloor) / (s.HpLow - s.HpFloor);
    const hp = hpPart * (1 - s.ManaShare + s.ManaShare * clamp(i.mana, 0, 1));
    const target = targetFactor(i.targetHp);
    const rune = i.rune ? s.Rune : 1;
    const chases = def?.chases === true;
    const tower = chases && i.tower < s.TowerZero ? 0 : chases && i.tower < s.TowerNear ? s.TowerFactor : 1;
    const forecast = i.forecast !== undefined ? clamp(i.forecast, s.ForecastClamp[0], s.ForecastClamp[1]) : 1;
    const zero =
        def === undefined
            ? "unknown-kind"
            : i.hp < s.HpFloor
              ? "hp"
              : up <= -2
                ? "outnumbered"
                : tower === 0
                  ? "tower"
                  : def.zero !== undefined
                    ? def.zero(i)
                    : undefined;
    const w = zero !== undefined ? 0 : clamp(def!.base * level * count * hp * target * rune * tower * forecast, 0, s.MaxWeight);
    return { w, level, count, hp, target, rune, tower, forecast, zero };
}

export interface Chance {
    kind: Kind;
    by: Unit;
    target?: Unit;
    at: Vector;
    /** Optional named input (the creep forecast's lean, 1 = neutral). */
    forecast?: number;
}

export interface Play {
    id: number;
    kind: Kind;
    by: Unit;
    target?: Unit;
    at: Vector;
    started: number;
    joiners: Unit[];
    targetHp0?: number;
    targetAt0?: Vector;
}

interface Settling {
    play: Play;
    why: string;
    ended: number;
}

let nextId = 1;
const active: Play[] = [];
const settling: Settling[] = [];

export function ResetCache(): void {
    nextId = 1;
    active.length = 0;
    settling.length = 0;
}

/** Gathers a chance's inputs from the shared fight readings. */
export function InputsOf(c: Chance): Inputs {
    const r = SETTINGS.Radius;
    const ours = FR.AlliesNear(c.at, r, [c.by]);
    const theirs = FR.EnemiesNear(c.at, r, c.target !== undefined ? [c.target] : []);
    const target = FR.Alive(c.target) ? c.target : undefined;
    return {
        kind: c.kind,
        ourLevel: FR.AverageLevel(ours),
        theirLevel: theirs.length > 0 ? FR.AverageLevel(theirs) : FR.AverageLevel(ours),
        ours: ours.length,
        theirs: theirs.length,
        hp: FR.HpFraction(c.by),
        mana: FR.ManaFraction(c.by),
        targetHp: target !== undefined ? FR.HpFraction(target) : undefined,
        rune: FR.HoldsPowerRune(c.by),
        tower: target !== undefined ? FR.TowerDistance(target.GetTeam(), target.GetLocation()) : math.huge,
        forecast: c.forecast,
    };
}

function r2(x: number): number {
    return math.floor(x * 100 + 0.5) / 100;
}

/**
 * Offers one chance: weighs it, draws once from the engine's Skill rng and logs `ev=play`. Returns the fired play, or
 * undefined (weight zero, the draw above the weight, a hero already in a play, or no engine rng: never a host-side draw).
 */
export function Roll(c: Chance, now: number = DotaTime()): Play | undefined {
    Tick(now);
    const i = InputsOf(c);
    const wt = Weigh(i);
    const busy = Of(c.by) !== undefined;
    const draw = wt.w > 0 && !busy ? LaneConfig.Draw() : undefined;
    const fire = draw !== undefined && draw < wt.w;
    const why = wt.zero ?? (busy ? "in-play" : wt.w > 0 && draw === undefined ? "no-rng" : undefined);
    let play: Play | undefined;
    if (fire) {
        const target = FR.Alive(c.target) ? c.target : undefined;
        play = {
            id: nextId++,
            kind: c.kind,
            by: c.by,
            target: c.target,
            at: c.at,
            started: now,
            joiners: [],
            targetHp0: target !== undefined ? FR.HpFraction(target) : undefined,
            targetAt0: target !== undefined ? target.GetLocation() : undefined,
        };
        active.push(play);
    }
    Telemetry.Event("play", [
        ["pid", c.by.GetPlayerID()],
        ["kind", c.kind],
        ["tgt", c.target !== undefined ? c.target.GetPlayerID() : -1],
        ["w", r2(wt.w)],
        ["fl", r2(wt.level)],
        ["fc", r2(wt.count)],
        ["fh", r2(wt.hp)],
        ["fth", r2(wt.target)],
        ["fr", r2(wt.rune)],
        ["ft", r2(wt.tower)],
        ["ff", r2(wt.forecast)],
        ["al", i.ours],
        ["en", i.theirs],
        ["zero", why],
        ["draw", draw !== undefined ? r2(draw) : undefined],
        ["fire", fire ? 1 : 0],
        ["id", play?.id],
    ]);
    return play;
}

function heroesOf(p: Play): Unit[] {
    return [p.by, ...p.joiners];
}

function killedNear(p: Play): boolean {
    const t = p.target;
    if (t === undefined || t.IsAlive()) return false;
    const at = t.GetLocation();
    return heroesOf(p).some((u) => FR.Alive(u) && FR.Dist(u.GetLocation(), at) <= SETTINGS.KillNear);
}

/** The play's result so far from the units: kill (target dead with a play hero near), trade (that and the initiator dead),
 *  died, forced (target low or moved far), else none. */
export function Classify(p: Play): string {
    const t = p.target;
    const dead = t !== undefined && !t.IsAlive();
    const died = !p.by.IsAlive();
    // A dead initiator is not near its target: a dead target with the initiator dead is a trade.
    if (dead && died) return "trade";
    if (dead && killedNear(p)) return "kill";
    if (died) return "died";
    if (FR.Alive(t)) {
        if (FR.HpFraction(t) < SETTINGS.ForcedHp && (p.targetHp0 ?? 1) >= SETTINGS.ForcedHp) return "forced";
        if (p.targetAt0 !== undefined && FR.Dist(t.GetLocation(), p.targetAt0) > SETTINGS.ForcedMoved) return "forced";
    }
    return "none";
}

function line(p: Play, res: string, why: string, ended: number): void {
    Telemetry.Event("play_end", [
        ["id", p.id],
        ["pid", p.by.GetPlayerID()],
        ["kind", p.kind],
        ["tgt", p.target !== undefined ? p.target.GetPlayerID() : -1],
        ["res", res],
        ["why", why],
        ["join", p.joiners.length],
        ["dur", math.floor((ended - p.started) * 10) / 10],
    ]);
}

/**
 * Ends a play once: it leaves the team's running plays now. With `res` given, or a result that cannot change (kill,
 * trade, died), the line is written now; otherwise it settles for KillAfter seconds so a kill just after the end counts.
 */
export function End(p: Play, why: string, res?: string, now: number = DotaTime()): void {
    const idx = active.indexOf(p);
    if (idx < 0) return;
    active.splice(idx, 1);
    const r = res ?? Classify(p);
    if (res !== undefined || r === "kill" || r === "trade" || r === "died" || p.target === undefined) line(p, r, why, now);
    else settling.push({ play: p, why, ended: now });
}

/** Ends every play past its kind's timeout and writes settled lines. Called from Roll and by consumers each frame. */
export function Tick(now: number = DotaTime()): void {
    for (const p of [...active]) {
        const def = kinds[p.kind];
        if (def !== undefined && now - p.started >= def.timeout) End(p, "timeout", undefined, now);
    }
    for (const s of [...settling]) {
        const r = Classify(s.play);
        if (r === "kill" || r === "trade" || now - s.ended >= SETTINGS.KillAfter) {
            settling.splice(settling.indexOf(s), 1);
            line(s.play, r, s.why, s.ended);
        }
    }
}

/** The team's running plays, optionally of one kind. */
export function Active(kind?: Kind): Play[] {
    return active.filter((p) => kind === undefined || p.kind === kind);
}

/** Running plays whose place is within `radius` of `at` ("a fired play near me"), optionally of one kind. */
export function Near(at: Vector, radius: number, kind?: Kind): Play[] {
    return active.filter((p) => (kind === undefined || p.kind === kind) && FR.Dist(p.at, at) <= radius);
}

/** The running play this hero is in, as its initiator or a joiner: such a hero is driven by the play. */
export function Of(u: Unit): Play | undefined {
    return active.find((p) => p.by === u || p.joiners.includes(u));
}

/** A hero from any context signs up for a running play (its own decision); counted on the play's end line. */
export function Join(p: Play, u: Unit): boolean {
    if (!active.includes(p) || Of(u) !== undefined) return false;
    p.joiners.push(u);
    return true;
}
